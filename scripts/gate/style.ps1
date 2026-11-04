#requires -Version 5.1
# G0.6 — art style is locked.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G0 - style'

$path = Join-Path $ArtDir 'STYLE.md'
$text = Read-Text $path
if (-not $text) {
    Add-Result 'G0.6' 'Style guide exists' 'blocked' 'art/STYLE.md missing'
    Complete-Gate 'G0 style'
}

$required = @(
    'Tile size', 'Character canvas', 'Palette', 'Outline',
    'Light direction', 'Max colours per sprite', 'Projection'
)
$table = Get-Section $text 'Locked parameters'
$rows = @($table -split "`n" | Where-Object { $_ -match '^\s*\|' })

$missing = @()
$unlocked = @()
foreach ($name in $required) {
    $row = $rows | Where-Object { $_ -match ('^\s*\|\s*' + [regex]::Escape($name) + '\s*\|') } | Select-Object -First 1
    if (-not $row) { $missing += $name; continue }
    $cells = @($row.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($cells.Count -lt 2) { $missing += $name; continue }
    $value = $cells[1]
    if ($value -eq '' -or $value -match '^TODO') { $unlocked += $name }
}

if ($missing.Count -gt 0) {
    Add-Result 'G0.6' 'All locked parameters are present' 'fail' ('missing rows: ' + ($missing -join ', '))
} elseif ($unlocked.Count -gt 0) {
    Add-Result 'G0.6' 'All locked parameters are present' 'fail' ('still TODO: ' + ($unlocked -join ', '))
} else {
    Add-Result 'G0.6' 'All locked parameters are present' 'pass' ($required.Count.ToString() + ' parameters')
}

# The palette must be expressed as concrete hex values, not a description.
$paletteRow = $rows | Where-Object { $_ -match '^\s*\|\s*Palette\s*\|' } | Select-Object -First 1
if ($paletteRow) {
    $hexes = [regex]::Matches($paletteRow, '#[0-9A-Fa-f]{6}')
    if ($hexes.Count -ge 3) {
        Add-Result 'G0.6.p' 'Palette is a concrete hex list' 'pass' ($hexes.Count.ToString() + ' colours declared')
    } else {
        Add-Result 'G0.6.p' 'Palette is a concrete hex list' 'fail' ($hexes.Count.ToString() + ' hex colours, expected at least 3')
    }
} else {
    Add-Result 'G0.6.p' 'Palette is a concrete hex list' 'fail' 'no palette row'
}

$todos = Get-TodoLines $text
if ($todos.Count -eq 0) {
    Add-Result 'G0.6.t' 'No placeholders left in the style guide' 'pass' ''
} else {
    Add-Result 'G0.6.t' 'No placeholders left in the style guide' 'fail' ($todos.Count.ToString() + ' TODO line(s) remain')
}

$anchor = Join-Path $ArtDir 'style\anchor.png'
if (Test-Path $anchor) {
    $size = Get-PngSize $anchor
    if ($size) {
        Add-Result 'G0.6.a' 'Style anchor image present' 'pass' ($size.Width.ToString() + 'x' + $size.Height.ToString())
    } else {
        Add-Result 'G0.6.a' 'Style anchor image present' 'fail' 'anchor.png is not a readable PNG'
    }
} else {
    Add-Result 'G0.6.a' 'Style anchor image present' 'blocked' 'art/style/anchor.png not created yet'
}

Complete-Gate 'G0 style'
