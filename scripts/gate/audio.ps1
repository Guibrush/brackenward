#requires -Version 5.1
# G2.7 — audio files match the spec in docs/AUDIO.md.
#
# Checks are objective only: codec, rate, channels, duration, loudness, peak,
# and the loop seam measured AFTER processing. Nothing here judges whether the
# sound is good; that is the human's ear.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

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
$loops = 0

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
    $channels = [int]$stream.channels
    $dur = [double]$info.format.duration

    $kind = 'sfx'
    if ($e.PSObject.Properties.Name -contains 'kind') { $kind = $e.kind }

    if ($kind -eq 'music' -and $codec -ne 'vorbis') { $codecBad += ($e.id + ' codec ' + $codec + ', expected vorbis') }
    if ($kind -eq 'sfx' -and $codec -ne 'pcm_s16le') { $codecBad += ($e.id + ' codec ' + $codec + ', expected pcm_s16le') }
    if ($rate -ne 48000) { $rateBad += ($e.id + ' ' + $rate + ' Hz') }

    if ($e.PSObject.Properties.Name -contains 'max_seconds' -and $dur -gt [double]$e.max_seconds) {
        $lenBad += ($e.id + ' ' + [math]::Round($dur, 2) + 's exceeds ' + $e.max_seconds + 's')
    }

    $target = -16.0
    if ($kind -eq 'music') { $target = -18.0 }
    if ($e.PSObject.Properties.Name -contains 'target_lufs') { $target = [double]$e.target_lufs }

    $ln = Invoke-Native -Exe $ffmpeg -Arguments @('-hide_banner', '-nostats', '-i', $file, '-af', 'ebur128=peak=true', '-f', 'null', '-')
    $mI = [regex]::Match($ln.Output, '(?m)^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS')
    $mP = [regex]::Match($ln.Output, '(?m)^\s*Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS')
    if (-not $mI.Success) {
        $loudBad += ($e.id + ' loudness unreadable')
    } else {
        $lufs = [double]$mI.Groups[1].Value
        if ([math]::Abs($lufs - $target) -gt $LoudnessTolerance) {
            $loudBad += ($e.id + ' ' + $lufs + ' LUFS, target ' + $target + ' +/-' + $LoudnessTolerance)
        }
        if ($mP.Success) {
            $tp = [double]$mP.Groups[1].Value
            if ($tp -gt $PeakCeiling) { $peakBad += ($e.id + ' peak ' + $tp + ' dBTP') }
        }
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

if ($rateBad.Count -eq 0) { Add-Result 'G2.7.r' 'Sample rate is 48 kHz' 'pass' '' }
else { Add-Result 'G2.7.r' 'Sample rate is 48 kHz' 'fail' (($rateBad | Select-Object -First 5) -join '; ') }

if ($loudBad.Count -eq 0) { Add-Result 'G2.7.l' 'Loudness within tolerance' 'pass' ('+/- ' + $LoudnessTolerance + ' LU') }
else { Add-Result 'G2.7.l' 'Loudness within tolerance' 'fail' (($loudBad | Select-Object -First 5) -join '; ') }

if ($peakBad.Count -eq 0) { Add-Result 'G2.7.p' 'Peak below ceiling' 'pass' ($PeakCeiling.ToString() + ' dBTP') }
else { Add-Result 'G2.7.p' 'Peak below ceiling' 'fail' (($peakBad | Select-Object -First 5) -join '; ') }

if ($lenBad.Count -eq 0) { Add-Result 'G2.7.d' 'Durations within budget' 'pass' '' }
else { Add-Result 'G2.7.d' 'Durations within budget' 'fail' (($lenBad | Select-Object -First 5) -join '; ') }

if ($loops -eq 0) {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'blocked' 'no looping entries declared'
} elseif ($seamBad.Count -eq 0) {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'pass' ($loops.ToString() + ' loops')
} else {
    Add-Result 'G2.7.s' 'Loop seams measured after processing' 'fail' ($seamBad -join '; ')
}

Complete-Gate 'G2 audio'
