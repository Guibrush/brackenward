#requires -Version 5.1
# G2.7 — audio files match the spec in docs/AUDIO.md.
#
# Two loudness regimes, per ADR-0004, and the boundary is 1 s of audio:
#   >= 1 s  beds and loops  integrated LUFS must sit within +/-2 LU of target
#                           (music -18, ambience -20, otherwise the entry's target)
#   <  1 s  one-shots      true peak must sit at or below -1 dBTP; integrated LUFS is
#                           still measured and printed, labelled advisory, and never
#                           gates, because R128 integrates over 400 ms blocks and a
#                           transient cannot be lifted to a bed target without its
#                           peaks passing 0 dBTP.
# Both numbers are printed for every asset, in both regimes.
#
# Duration is read from the file, never from the manifest: a mis-declared duration
# would otherwise be a way to move an asset into the weaker regime.
#
# No placeholder exemption. Every manifest entry is measured whatever it is flagged
# as; an exemption flag able to hide a whole category from the gate it is supposed
# to police is not a gate (L-031).
#
# A check with nothing to check reports N/A with the reason printed. It does not
# block, because an empty category would otherwise hold the whole gate at exit 3
# until content exists, and it does not report pass, because that would claim
# evidence it does not have. N/A is recomputed from the file-measured asset list on
# every run, so the first >= 1 s asset or the first loop makes the check real again.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

# Numbers go into output text, so they are formatted with the invariant culture or
# the same run would read differently on a machine with a decimal comma.
function Format-Db {
    param([double]$Value, [string]$Pattern = '0.0')
    return $Value.ToString($Pattern, [System.Globalization.CultureInfo]::InvariantCulture)
}

# Loop-seam analysis runs in compiled code: 160k samples in a PowerShell loop is
# slow enough to look like a hang, and array creation there is error-prone.
if (-not ('SeamCheck' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
public static class SeamCheck {
    public static double[] Analyze(string path) {
        byte[] b = System.IO.File.ReadAllBytes(path);
        int n = b.Length / 2;
        if (n < 1000) throw new Exception("too few samples");
        short[] x = new short[n];
        for (int i = 0; i < n; i++) x[i] = BitConverter.ToInt16(b, i * 2);
        double[] d = new double[n - 1];
        for (int i = 0; i < n - 1; i++) d[i] = Math.Abs((double)x[i + 1] - x[i]);
        double[] s = (double[])d.Clone();
        Array.Sort(s);
        double p999 = s[(int)(0.999 * (n - 2))];
        double seam = Math.Abs((double)x[0] - x[n - 1]);
        int lead = 0;
        for (int i = 0; i < n; i++) { if (Math.Abs((int)x[i]) < 200) lead++; else break; }
        return new double[] { seam, p999, lead / 16.0 };
    }
}
'@
}

Write-Host 'G2 - audio'

$manifestPath = Join-Path $StudioRoot 'audio\manifest.json'
if (-not (Test-Path $manifestPath)) {
    Add-Result 'G2.7' 'Audio manifest exists' 'blocked' 'audio/manifest.json missing'
    Complete-Gate 'G2 audio'
}

try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json }
catch {
    Add-Result 'G2.7' 'Audio manifest parses' 'fail' $_.Exception.Message
    Complete-Gate 'G2 audio'
}

$entries = @()
if ($manifest.PSObject.Properties.Name -contains 'entries') { $entries = @($manifest.entries) }
if ($entries.Count -eq 0) {
    Add-Result 'G2.7' 'Manifest has entries' 'blocked' 'no audio declared yet'
    Complete-Gate 'G2 audio'
}

$ffprobe = Get-FfprobePath
$ffmpeg = Get-FfmpegPath
if (-not $ffprobe -or -not $ffmpeg) {
    Add-Result 'G2.7' 'ffmpeg and ffprobe available' 'blocked' 'install ffmpeg to evaluate audio'
    Complete-Gate 'G2 audio'
}

$codecBad = @()
$rateBad = @()
$loudBad = @()
$peakBad = @()
$lenBad = @()
$seamBad = @()
$checked = 0
$beds = 0
$oneShots = 0
$loops = 0
$lenChecked = 0

foreach ($e in $entries) {
    $checked++
    $file = [string]$e.file
    if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path $StudioRoot $file }
    if (-not (Test-Path $file)) { $codecBad += ($e.id + ' missing file'); continue }

    $probe = Invoke-Native -Exe $ffprobe -Arguments @('-v', 'quiet', '-print_format', 'json', '-show_streams', '-show_format', $file)
    if ($probe.ExitCode -ne 0) { $codecBad += ($e.id + ' unreadable'); continue }
    $info = $probe.Output | ConvertFrom-Json
    $stream = @($info.streams)[0]
    $codec = [string]$stream.codec_name
    $rate = [int]$stream.sample_rate

    # Duration comes from the stream header when it has one, otherwise the container.
    # Either way it is the file's own number, not the manifest's.
    $dur = 0.0
    if ($stream.PSObject.Properties.Name -contains 'duration' -and [string]$stream.duration -ne '') {
        $dur = [double]$stream.duration
    }
    if ($dur -le 0 -and $info.format.PSObject.Properties.Name -contains 'duration') {
        $dur = [double]$info.format.duration
    }
    if ($dur -le 0) {
        # Without a duration there is no way to know which regime applies, and
        # guessing would let the asset pick its own rule.
        $lenBad += ($e.id + ' duration unreadable, cannot select a loudness regime')
        continue
    }

    $kind = 'sfx'
    if ($e.PSObject.Properties.Name -contains 'kind') { $kind = $e.kind }

    if ($kind -eq 'music' -and $codec -ne 'vorbis') { $codecBad += ($e.id + ' codec ' + $codec + ', expected vorbis') }
    if ($kind -eq 'sfx' -and $codec -ne 'pcm_s16le') { $codecBad += ($e.id + ' codec ' + $codec + ', expected pcm_s16le') }
    if ($rate -ne 48000) { $rateBad += ($e.id + ' ' + $rate + ' Hz') }

    if ($e.PSObject.Properties.Name -contains 'max_seconds') {
        $lenChecked++
        if ($dur -gt [double]$e.max_seconds) {
            $lenBad += ($e.id + ' ' + (Format-Db $dur '0.00') + 's exceeds ' + $e.max_seconds + 's')
        }
    }

    $target = -16.0
    if ($kind -eq 'music') { $target = -18.0 }
    if ($kind -eq 'ambience') { $target = -20.0 }
    if ($e.PSObject.Properties.Name -contains 'target_lufs') { $target = [double]$e.target_lufs }

    # ADR-0004: the domain of the loudness criterion is the set of assets of at
    # least one second. Everything shorter is judged on true peak alone.
    $isBed = ($dur -ge 1.0)
    if ($isBed) { $beds++ } else { $oneShots++ }

    $ln = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $file, '-af', 'ebur128=peak=true', '-f', 'null', '-')
    # The summary block is printed last, so the last match is the whole-file figure.
    $lufs = $null
    $tp = $null
    $silent = $false
    $mi = [regex]::Matches($ln.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
    if ($mi.Count -gt 0) { $lufs = [double]$mi[$mi.Count - 1].Groups[1].Value }
    if ([regex]::IsMatch($ln.Output, '(?m)^\s*Peak:\s*-inf\s*dBFS')) { $silent = $true }
    $mp = [regex]::Matches($ln.Output, '(?m)^\s*Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS')
    if ($mp.Count -gt 0) { $tp = [double]$mp[$mp.Count - 1].Groups[1].Value }

    # One line per asset, both numbers, and which of them is allowed to fail it.
    $peakText = 'unreadable'
    if ($silent) { $peakText = '-inf dBTP (silent)' }
    elseif ($null -ne $tp) { $peakText = (Format-Db $tp) + ' dBTP' }

    $lufsText = 'unreadable'
    if ($null -ne $lufs) {
        $lufsText = (Format-Db $lufs) + ' LUFS'
        if ($lufs -le -69.9) { $lufsText = $lufsText + ' (at the -70 LUFS floor)' }
    }

    if ($isBed) {
        $regime = 'gating: I target ' + (Format-Db $target) + ' +/-' + (Format-Db $LoudnessTolerance) + ' LU'
    } else {
        $regime = 'advisory: peak <= ' + (Format-Db $PeakCeiling) + ' dBTP gates'
    }
    Write-Host ('  asset   ' + ([string]$e.id).PadRight(24) + (Format-Db $dur '0.00') + 's  peak ' + $peakText + '  I ' + $lufsText + '  [' + $regime + ']')

    if ($null -eq $lufs) {
        $loudBad += ($e.id + ' loudness unreadable')
    } elseif ($isBed) {
        if ([math]::Abs($lufs - $target) -gt $LoudnessTolerance) {
            $loudBad += ($e.id + ' ' + (Format-Db $lufs) + ' LUFS, target ' + (Format-Db $target) + ' +/-' + (Format-Db $LoudnessTolerance))
        }
    }

    # The peak ceiling applies to both regimes: it is the gate for one-shots and the
    # ceiling for beds. A silent file has no measurable peak and fails here rather
    # than passing as "unmeasurable".
    if ($null -eq $tp) {
        $peakBad += ($e.id + ' true peak unreadable (silent or undecodable)')
    } elseif ($tp -gt $PeakCeiling) {
        $peakBad += ($e.id + ' peak ' + (Format-Db $tp) + ' dBTP, ceiling ' + (Format-Db $PeakCeiling))
    }

    if ($e.PSObject.Properties.Name -contains 'loop' -and $e.loop -eq $true) {
        $loops++
        $tmp = Join-Path $env:TEMP ('seam_' + [guid]::NewGuid().ToString('N') + '.pcm')
        $dec = Invoke-Native -Exe $ffmpeg -Arguments @('-y', '-loglevel', 'error', '-i', $file, '-ac', '1', '-ar', '16000', '-f', 's16le', $tmp)
        if ($dec.ExitCode -eq 0 -and (Test-Path $tmp)) {
            try {
                $m = [SeamCheck]::Analyze($tmp)
                $seam = $m[0]; $p999 = $m[1]; $leadMs = $m[2]
                if ($seam -gt $p999) {
                    $seamBad += ($e.id + ' seam ' + [math]::Round($seam, 1) + ' exceeds p99.9 ' + [math]::Round($p999, 1))
                }
                if ($leadMs -gt 5) {
                    $seamBad += ($e.id + ' ' + [math]::Round($leadMs, 1) + 'ms of leading silence')
                }
            } catch {
                $seamBad += ($e.id + ' seam analysis failed: ' + $_.Exception.Message)
            }
        } else {
            $seamBad += ($e.id + ' could not decode for seam check')
        }
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

if ($codecBad.Count -eq 0) { Add-Result 'G2.7.c' 'Codecs match the specification' 'pass' ($checked.ToString() + ' files') }
else { Add-Result 'G2.7.c' 'Codecs match the specification' 'fail' (($codecBad | Select-Object -First 5) -join '; ') }

if ($rateBad.Count -eq 0) { Add-Result 'G2.7.r' 'Sample rate is 48 kHz' 'pass' ($checked.ToString() + ' files') }
else { Add-Result 'G2.7.r' 'Sample rate is 48 kHz' 'fail' (($rateBad | Select-Object -First 5) -join '; ') }

# Loudness gates beds only. With no bed in the manifest there is nothing the
# criterion can be false of, and saying so is not the same as passing it.
if ($loudBad.Count -gt 0) {
    Add-Result 'G2.7.l' 'Loudness within tolerance' 'fail' (($loudBad | Select-Object -First 5) -join '; ')
} elseif ($beds -eq 0) {
    Add-Result 'G2.7.l' 'Loudness within tolerance' 'n/a' ('no asset at or above 1 s; ' + $oneShots + ' one-shot(s) report LUFS as advisory only')
} else {
    Add-Result 'G2.7.l' 'Loudness within tolerance' 'pass' ($beds.ToString() + ' assets >= 1 s, +/- ' + (Format-Db $LoudnessTolerance) + ' LU')
}

if ($peakBad.Count -eq 0) { Add-Result 'G2.7.p' 'Peak below ceiling' 'pass' ($checked.ToString() + ' files at or below ' + (Format-Db $PeakCeiling) + ' dBTP') }
else { Add-Result 'G2.7.p' 'Peak below ceiling' 'fail' (($peakBad | Select-Object -First 5) -join '; ') }

if ($lenBad.Count -gt 0) { Add-Result 'G2.7.d' 'Durations within budget' 'fail' (($lenBad | Select-Object -First 5) -join '; ') }
elseif ($lenChecked -eq 0) { Add-Result 'G2.7.d' 'Durations within budget' 'n/a' 'no entry declares max_seconds' }
else { Add-Result 'G2.7.d' 'Durations within budget' 'pass' ($lenChecked.ToString() + ' declared budgets') }

# A seam can only be measured on a loop. Empty is not applicable, not blocked: the
# check is re-derived from the manifest every run, so the first `loop: true` entry
# turns this line back into a measurement without anyone remembering to re-enable it.
if ($seamBad.Count -gt 0) {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'fail' ($seamBad -join '; ')
} elseif ($loops -eq 0) {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'n/a' 'no looping entries declared, so no seam exists to measure'
} else {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'pass' ($loops.ToString() + ' loops')
}

Write-Host ''
Write-Host ('G2.7 measured ' + $checked + ' asset(s): ' + $beds + ' at or above 1 s (LUFS gating), ' + $oneShots + ' under 1 s (peak gating, LUFS advisory).')

Complete-Gate 'G2 audio'
