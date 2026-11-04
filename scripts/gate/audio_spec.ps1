#requires -Version 5.1
# G0.8 — audio guide is complete and actionable.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G0 - audio specification'

$path = Join-Path $DocsDir 'AUDIO.md'
$text = Read-Text $path
if (-not $text) {
    Add-Result 'G0.8' 'Audio guide exists' 'blocked' 'docs/AUDIO.md missing'
    Complete-Gate 'G0 audio spec'
}

$required = @('Format rules', 'Loudness', 'Loops', 'Naming', 'Budgets', 'Review limits')
$missing = @()
foreach ($h in $required) {
    if ((Get-Section $text $h).Trim() -eq '') { $missing += $h }
}
if ($missing.Count -eq 0) {
    Add-Result 'G0.8' 'Required sections present' 'pass' ($required.Count.ToString() + ' sections')
} else {
    Add-Result 'G0.8' 'Required sections present' 'fail' ('missing or empty: ' + ($missing -join ', '))
}

# The format rules must name both formats the engine actually consumes.
$formats = @()
if ($text -match '\.wav') { $formats += 'wav' }
if ($text -match '\.ogg') { $formats += 'ogg' }
if ($formats.Count -eq 2) {
    Add-Result 'G0.8.f' 'WAV and OGG are both specified' 'pass' ''
} else {
    Add-Result 'G0.8.f' 'WAV and OGG are both specified' 'fail' ('found: ' + ($formats -join ', '))
}

# Loudness targets must be measurable, not adjectives.
$hasLufs = $text -match 'LUFS'
$hasPeak = $text -match 'dBTP'
if ($hasLufs -and $hasPeak) {
    Add-Result 'G0.8.l' 'Loudness targets are measurable' 'pass' 'LUFS and dBTP present'
} else {
    Add-Result 'G0.8.l' 'Loudness targets are measurable' 'fail' 'LUFS or dBTP missing'
}

# The loop policy must say that the seam is measured after processing.
$loop = Get-Section $text 'Loops'
if ($loop -match 'after' -and $loop -match '\bgate\b|seam') {
    Add-Result 'G0.8.o' 'Loop policy requires an after-processing check' 'pass' ''
} else {
    Add-Result 'G0.8.o' 'Loop policy requires an after-processing check' 'fail' 'the Loops section does not require measuring the seam after processing'
}

$todos = Get-TodoLines $text
if ($todos.Count -eq 0) {
    Add-Result 'G0.8.t' 'No placeholders left in the audio guide' 'pass' ''
} else {
    Add-Result 'G0.8.t' 'No placeholders left in the audio guide' 'fail' ($todos.Count.ToString() + ' TODO line(s) remain')
}

Complete-Gate 'G0 audio spec'
