#requires -Version 5.1
# Deterministic post-processing for generated audio.
#
# Order matters and is deliberate:
#   1. trim leading silence, and trailing silence for one-shots
#   2. crossfade the loop seam, which changes the length and therefore loudness
#   3. normalise the RESULT - by peak under 1 s, by integrated loudness above it
#   4. encode for the engine, then measure what was actually written
#
# Normalising before the crossfade would measure a file that no longer exists.
# A single-pass loudnorm misses its target by several LU; see L-006.
#
# Normalisation has two regimes, with the same 1 s boundary the gate uses
# (ADR-0004). R128 integrates over 400 ms gating blocks, so a sub-second one-shot
# reports the -70 LUFS floor and a gain derived from it is enormous and meaningless:
# it does not correct the clip, it destroys it. Short clips are peak-normalised
# instead. Beds keep the loudness path and its -1.5 dBTP limiter.
#
# Named parameters only. No prompt text, no randomness, no network.

param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateSet('sfx', 'music')][string]$Kind = 'sfx',
    [switch]$Loop,
    [double]$TargetLufs = 0,
    [double]$TargetPeak = -1.5,
    [int]$CrossfadeMs = 100,
    [int]$MaxSeconds = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

$ffmpeg = Get-FfmpegPath
$ffprobe = Get-FfprobePath
if (-not $ffmpeg -or -not $ffprobe) { Write-Error 'ffmpeg and ffprobe are required'; exit 1 }
if (-not (Test-Path $In)) { Write-Error ("input not found: " + $In); exit 1 }
if ($TargetLufs -eq 0) { if ($Kind -eq 'music') { $TargetLufs = -18 } else { $TargetLufs = -16 } }

# Numbers are pasted into filter arguments and into the report. With a decimal
# comma the filtergraph breaks ("volume=0,5dB"), so every number is formatted with
# the invariant culture.
function Format-Num {
    param([double]$Value, [string]$Pattern = '0.00')
    return $Value.ToString($Pattern, [System.Globalization.CultureInfo]::InvariantCulture)
}

$work = Join-Path $env:TEMP ('post_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Get-Duration {
    param([string]$Path)
    $p = Invoke-Native -Exe $ffprobe -Arguments @('-v', 'quiet', '-print_format', 'json', '-show_format', $Path)
    if ($p.ExitCode -ne 0) { return 0 }
    return [double](($p.Output | ConvertFrom-Json).format.duration)
}

function Invoke-Ffmpeg {
    param([string[]]$Arguments)
    $r = Invoke-Native -Exe $ffmpeg -Arguments (@('-y', '-hide_banner', '-loglevel', 'error') + $Arguments)
    if ($r.ExitCode -ne 0) {
        $tail = ($r.Output -split "`n" | Select-Object -Last 4) -join ' | '
        Write-Error ('ffmpeg failed: ' + $tail)
        return $false
    }
    return $true
}

$step1 = Join-Path $work 'trimmed.wav'
# Channel layout is fixed here, before any measurement. Measuring a stereo file
# and then downmixing to mono at encode time shifts loudness by about 3 dB,
# because the downmix sums correlated channels.
$channels = '1'
if ($Kind -eq 'music') { $channels = '2' }

# Leading silence only at -60 dB, plus an explicit trailing-silence trim for
# one-shots. The trailing trim is what ADR-0004 asked for: an untrimmed tail is what
# put a 20 ms click inside a half-second file.
#
# The tail threshold is -70 dB, not the -50 dB an earlier version used. At -50 dB a
# decaying sound falls below the threshold while it is still audible, and that
# version cut a 1.07s blip down to 0.31s. At -70 dB the trim can only remove
# material nobody can hear; the 5 ms fade-out that follows removes the step the cut
# would otherwise add, and doubles as the tail fade when nothing is trimmed.
if ($Kind -eq 'sfx') {
    $trimFilter = 'silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.01,' +
                  'areverse,' +
                  'silenceremove=start_periods=1:start_threshold=-70dB:start_silence=0.005,' +
                  'afade=t=in:st=0:d=0.005,' +
                  'areverse'
} else {
    $trimFilter = 'silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.01'
}
$trimArgs = @('-i', $In, '-af', $trimFilter, '-ar', '48000', '-ac', $channels, '-c:a', 'pcm_s16le', $step1)
if ($MaxSeconds -gt 0) { $trimArgs = @('-t', [string]$MaxSeconds) + $trimArgs }
if (-not (Invoke-Ffmpeg $trimArgs)) { exit 1 }

$current = $step1
$crossfaded = $false

if ($Loop) {
    $length = Get-Duration $step1
    $n = $CrossfadeMs / 1000.0
    if ($length -le (2 * $n)) {
        Write-Error ('cannot crossfade: file is ' + (Format-Num $length) + 's, needs more than ' + (Format-Num (2 * $n)) + 's')
        exit 1
    }
    $step2 = Join-Path $work 'looped.wav'
    # seam = crossfade(tail, head); output = seam + middle. Length shrinks by N.
    $graph = '[0:a]atrim=0:' + (Format-Num $n '0.###') + ',asetpts=PTS-STARTPTS[head];' +
             '[0:a]atrim=start=' + (Format-Num ($length - $n) '0.###') + ',asetpts=PTS-STARTPTS[tail];' +
             '[tail][head]acrossfade=d=' + (Format-Num $n '0.###') + ':c1=tri:c2=tri[seam];' +
             '[0:a]atrim=start=' + (Format-Num $n '0.###') + ':end=' + (Format-Num ($length - $n) '0.###') + ',asetpts=PTS-STARTPTS[mid];' +
             '[seam][mid]concat=n=2:v=0:a=1[out]'
    if (-not (Invoke-Ffmpeg @('-i', $step1, '-filter_complex', $graph, '-map', '[out]', '-ar', '48000', '-ac', $channels, '-c:a', 'pcm_s16le', $step2))) { exit 1 }
    $current = $step2
    $crossfaded = $true
}

# Normalisation. Two regimes, split at 1 s so that post and gate agree on which
# rule applies (ADR-0004).
#   under 1 s  peak: gain = target true peak - measured true peak
#   1 s and up integrated loudness
# loudnorm is unreliable under three seconds, which is most one-shots, so the
# loudness regime below that is measured with ebur128 and corrected with a fixed
# gain. Music keeps the two-pass loudnorm, which is more accurate on long input.
$duration = Get-Duration $current
if ($duration -le 0) { Write-Error 'could not read the duration of the trimmed clip'; exit 1 }

if ($duration -lt 1.0) {
    $measure = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $current, '-af', 'ebur128=peak=true', '-f', 'null', '-')
    $mp = [regex]::Match($measure.Output, '(?m)^\s*Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS')
    if (-not $mp.Success) {
        $tail = ($measure.Output -split "`n" | Select-Object -Last 6) -join ' | '
        Write-Error ('could not measure true peak (input may be silent): ' + $tail)
        exit 1
    }
    $measuredPeak = [double]$mp.Groups[1].Value
    $gain = [math]::Round($TargetPeak - $measuredPeak, 2)
    # No limiter here: the gain is derived from the measured peak, so the output
    # peak lands on the target by construction, above or below it. The measurement
    # after the write is the guard, and it reads the file the engine will ship.
    $normalise = 'volume=' + (Format-Num $gain) + 'dB'
    Write-Host ('  measured  peak ' + (Format-Num $measuredPeak) + ' dBTP, applying ' + (Format-Num $gain) + ' dB to reach ' + (Format-Num $TargetPeak) + ' dBTP')
} elseif ($duration -lt 3.0) {
    $measure = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $current, '-af', 'ebur128=peak=true', '-f', 'null', '-')
    $mi = [regex]::Match($measure.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
    if (-not $mi.Success) {
        $tail = ($measure.Output -split "`n" | Select-Object -Last 6) -join ' | '
        Write-Error ('could not measure loudness (input may be silent): ' + $tail)
        exit 1
    }
    $measured = [double]$mi.Groups[1].Value
    if ($measured -le -69.9) {
        Write-Error ('measured ' + (Format-Num $measured '0.0') + ' LUFS, the R128 floor: this clip is shorter than one gating block or silent, so an integrated-loudness gain is meaningless')
        exit 1
    }
    $gain = [math]::Round($TargetLufs - $measured, 2)
    # alimiter's limit is linear. 0.794 is about -2 dBFS, which keeps true peak
    # near -1.5 dBTP: the limiter caps sample peaks, while the gate measures true
    # peak, so a -1 dBFS limit reads as -0.7 dBTP and fails the ceiling.
    # level=false is required; the default auto-levels the output back up.
    # latency=true is required too. Without it alimiter pads its attack window with
    # digital silence at the head of the file - measured at 4.8-5.0 ms, i.e. x0 = 0 -
    # which is exactly the defect loop processing exists to remove, and which slides
    # under the gate's 5 ms leading-silence rule. With latency=true the filtergraph
    # compensates the lookahead and the head is real audio (T-0021, T-0022).
    $normalise = 'volume=' + (Format-Num $gain) + 'dB,alimiter=limit=0.794:level=false:latency=true'
    Write-Host ('  measured  ' + (Format-Num $measured '0.0') + ' LUFS, applying ' + (Format-Num $gain) + ' dB')
} else {
    $measure = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $current, '-af', ('loudnorm=I=' + (Format-Num $TargetLufs '0.#') + ':TP=-1.5:LRA=11:print_format=json'), '-f', 'null', '-')
    $mi = [regex]::Match($measure.Output, '"input_i"\s*:\s*"(-?[\d\.]+)"')
    $mtp = [regex]::Match($measure.Output, '"input_tp"\s*:\s*"(-?[\d\.]+)"')
    $mlra = [regex]::Match($measure.Output, '"input_lra"\s*:\s*"(-?[\d\.]+)"')
    $mth = [regex]::Match($measure.Output, '"input_thresh"\s*:\s*"(-?[\d\.]+)"')
    $moff = [regex]::Match($measure.Output, '"target_offset"\s*:\s*"(-?[\d\.]+)"')
    if (-not ($mi.Success -and $mtp.Success -and $mlra.Success -and $mth.Success -and $moff.Success)) {
        $tail = ($measure.Output -split "`n" | Select-Object -Last 6) -join ' | '
        Write-Error ('could not measure loudness (input may be silent): ' + $tail)
        exit 1
    }
    $normalise = 'loudnorm=I=' + (Format-Num $TargetLufs '0.#') + ':TP=-1.5:LRA=11' +
        ':measured_I=' + $mi.Groups[1].Value +
        ':measured_TP=' + $mtp.Groups[1].Value +
        ':measured_LRA=' + $mlra.Groups[1].Value +
        ':measured_thresh=' + $mth.Groups[1].Value +
        ':offset=' + $moff.Groups[1].Value +
        ':linear=true'
}

$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

if ($Kind -eq 'music') {
    $args = @('-i', $current, '-af', $normalise, '-ar', '48000', '-ac', '2', '-c:a', 'libvorbis', '-q:a', '5', $Out)
} else {
    $args = @('-i', $current, '-af', $normalise, '-ar', '48000', '-ac', '1', '-c:a', 'pcm_s16le', $Out)
}
if (-not (Invoke-Ffmpeg $args)) { exit 1 }

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

# Report, and check, what was actually written. Post-processing that returns 0 is a
# claim that the file is ready for the gate, so the numbers come from the encoded
# output rather than from the gain that was requested.
$finalLufs = 'unknown'
$finalPeak = 'unknown'
$check = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $Out, '-af', 'ebur128=peak=true', '-f', 'null', '-')
$mc = [regex]::Match($check.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
if ($mc.Success) { $finalLufs = (Format-Num ([double]$mc.Groups[1].Value) '0.0') }
$mpc = [regex]::Match($check.Output, '(?m)^\s*Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS')
if ($mpc.Success) { $finalPeak = (Format-Num ([double]$mpc.Groups[1].Value)) }
$finalDuration = Get-Duration $Out

$regime = 'integrated loudness, target ' + (Format-Num $TargetLufs '0.0') + ' LUFS'
if ($finalDuration -lt 1.0) { $regime = 'true peak, target ' + (Format-Num $TargetPeak) + ' dBTP' }

Write-Host ('post: ' + (Split-Path $Out -Leaf))
Write-Host ('  kind      ' + $Kind + $(if ($Loop) { ', looped' } else { '' }))
Write-Host ('  duration  ' + (Format-Num $finalDuration '0.00') + 's')
Write-Host ('  loudness  ' + $finalLufs + ' LUFS' + $(if ($finalDuration -lt 1.0) { ' (advisory under 1 s)' } else { ', target ' + (Format-Num $TargetLufs '0.0') }))
Write-Host ('  peak      ' + $finalPeak + ' dBTP, ceiling ' + (Format-Num $PeakCeiling '0.0') + ' dBTP')
Write-Host ('  regime    ' + $regime)
Write-Host ('  seam      ' + $(if ($crossfaded) { 'crossfaded ' + $CrossfadeMs + 'ms' } else { 'not crossfaded' }))

if ($mpc.Success -and [double]$mpc.Groups[1].Value -gt $PeakCeiling) {
    Write-Error ('true peak ' + $finalPeak + ' dBTP exceeds the ' + (Format-Num $PeakCeiling '0.0') + ' dBTP ceiling; the gate would fail this file')
    exit 1
}
exit 0
