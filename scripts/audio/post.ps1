#requires -Version 5.1
# Deterministic post-processing for generated audio.
#
# Order matters and is deliberate:
#   1. trim leading silence (and trailing, for one-shots)
#   2. crossfade the loop seam, which changes the length and therefore loudness
#   3. normalise the RESULT in two passes
#   4. encode for the engine
#
# Normalising before the crossfade would measure a file that no longer exists.
# A single-pass loudnorm misses its target by several LU; see L-006.
#
# Named parameters only. No prompt text, no randomness, no network.

param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateSet('sfx', 'music')][string]$Kind = 'sfx',
    [switch]$Loop,
    [double]$TargetLufs = 0,
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

# Leading silence only, at a low threshold. An earlier version also trimmed the
# tail at -50 dB and cut a 1.07s blip down to 0.31s, because a decaying sound
# falls below that threshold early. One-shots get a short fade instead, which
# removes the click without removing the body of the sound.
if ($Kind -eq 'sfx') {
    $trimFilter = 'silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.01,areverse,afade=t=in:st=0:d=0.01,areverse'
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
        Write-Error ('cannot crossfade: file is ' + [math]::Round($length, 2) + 's, needs more than ' + (2 * $n) + 's')
        exit 1
    }
    $step2 = Join-Path $work 'looped.wav'
    # seam = crossfade(tail, head); output = seam + middle. Length shrinks by N.
    $graph = '[0:a]atrim=0:' + $n + ',asetpts=PTS-STARTPTS[head];' +
             '[0:a]atrim=start=' + ($length - $n) + ',asetpts=PTS-STARTPTS[tail];' +
             '[tail][head]acrossfade=d=' + $n + ':c1=tri:c2=tri[seam];' +
             '[0:a]atrim=start=' + $n + ':end=' + ($length - $n) + ',asetpts=PTS-STARTPTS[mid];' +
             '[seam][mid]concat=n=2:v=0:a=1[out]'
    if (-not (Invoke-Ffmpeg @('-i', $step1, '-filter_complex', $graph, '-map', '[out]', '-ar', '48000', '-ac', $channels, '-c:a', 'pcm_s16le', $step2))) { exit 1 }
    $current = $step2
    $crossfaded = $true
}

# Normalisation. loudnorm is unreliable under three seconds, which is most sound
# effects, so short clips are measured with ebur128 and corrected with a fixed
# gain. Music keeps the two-pass loudnorm, which is more accurate on long input.
$duration = Get-Duration $current
if ($duration -lt 3.0) {
    $measure = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $current, '-af', 'ebur128=peak=true', '-f', 'null', '-')
    $mi = [regex]::Match($measure.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
    if (-not $mi.Success) {
        $tail = ($measure.Output -split "`n" | Select-Object -Last 6) -join ' | '
        Write-Error ('could not measure loudness (input may be silent): ' + $tail)
        exit 1
    }
    $measured = [double]$mi.Groups[1].Value
    $gain = [math]::Round($TargetLufs - $measured, 2)
    # alimiter's limit is linear. 0.794 is about -2 dBFS, which keeps true peak
    # near -1.5 dBTP: the limiter caps sample peaks, while the gate measures true
    # peak, so a -1 dBFS limit reads as -0.7 dBTP and fails the ceiling.
    # level=false is required; the default auto-levels the output back up.
    $normalise = 'volume=' + $gain + 'dB,alimiter=limit=0.794:level=false'
    Write-Host ('  measured  ' + $measured + ' LUFS, applying ' + $gain + ' dB')
} else {
    $measure = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $current, '-af', ('loudnorm=I=' + $TargetLufs + ':TP=-1.5:LRA=11:print_format=json'), '-f', 'null', '-')
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
    $normalise = 'loudnorm=I=' + $TargetLufs + ':TP=-1.5:LRA=11' +
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

$finalLufs = 'unknown'
$check = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $Out, '-af', 'ebur128=peak=true', '-f', 'null', '-')
$mc = [regex]::Match($check.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
if ($mc.Success) { $finalLufs = $mc.Groups[1].Value }

Write-Host ('post: ' + (Split-Path $Out -Leaf))
Write-Host ('  kind      ' + $Kind + $(if ($Loop) { ', looped' } else { '' }))
Write-Host ('  duration  ' + [math]::Round((Get-Duration $Out), 2) + 's')
Write-Host ('  loudness  ' + $finalLufs + ' LUFS, target ' + $TargetLufs)
Write-Host ('  seam      ' + $(if ($crossfaded) { 'crossfaded ' + $CrossfadeMs + 'ms' } else { 'not crossfaded' }))
exit 0
