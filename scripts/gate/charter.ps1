#requires -Version 5.1
# G0.1, G0.4, G0.5 — charter completeness.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G0 - charter'

$path = Join-Path $DocsDir 'CHARTER.md'
$text = Read-Text $path
if (-not $text) {
    Add-Result 'G0.1' 'Charter exists' 'blocked' 'docs/CHARTER.md missing'
    Complete-Gate 'G0 charter'
}

$required = @(
    'One-line pitch', 'Audience and platform', 'Three pillars', 'Non-goals',
    'Core loop', 'Fun hypothesis', 'Scope budget', 'Codename candidates'
)
$missing = @()
foreach ($h in $required) {
    if ((Get-Section $text $h).Trim() -eq '') { $missing += $h }
}
if ($missing.Count -eq 0) {
    Add-Result 'G0.1' 'Required sections present' 'pass' ($required.Count.ToString() + ' sections')
} else {
    Add-Result 'G0.1' 'Required sections present' 'fail' ('missing or empty: ' + ($missing -join ', '))
}

$todos = Get-TodoLines $text
if ($todos.Count -eq 0) {
    Add-Result 'G0.4' 'No placeholders left in the document' 'pass' ''
} else {
    Add-Result 'G0.4' 'No placeholders left in the document' 'fail' ($todos.Count.ToString() + ' TODO line(s) remain')
}

$nonGoals = Get-Section $text 'Non-goals'
$items = @($nonGoals -split "`n" | Where-Object { $_ -match '^\s*-\s+\S' })
if ($items.Count -ge 3) {
    Add-Result 'G0.5' 'Non-goals has at least three entries' 'pass' ($items.Count.ToString() + ' entries')
} else {
    Add-Result 'G0.5' 'Non-goals has at least three entries' 'fail' ($items.Count.ToString() + ' entries')
}

$budget = Get-Section $text 'Scope budget'
if ($budget.Trim() -eq '') {
    Add-Result 'G0.4.b' 'Scope budget table is filled in' 'fail' 'section is empty'
} else {
    $rows = @($budget -split "`n" | Where-Object { $_ -match '^\s*\|' })
    $data = @($rows | Where-Object { $_ -notmatch '^\s*\|\s*[-: ]+\|' -and $_ -notmatch '\|\s*Item\s*\|' })
    $empty = @()
    foreach ($r in $data) {
        $cells = @($r.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 3) { $empty += 'malformed row'; continue }
        if ($cells[1] -eq '' -or $cells[1] -match '^TODO') { $empty += ($cells[0] + ' has no budget') }
    }
    if ($data.Count -lt 5) {
        Add-Result 'G0.4.b' 'Scope budget table is filled in' 'fail' ($data.Count.ToString() + ' rows, expected at least 5')
    } elseif ($empty.Count -gt 0) {
        Add-Result 'G0.4.b' 'Scope budget table is filled in' 'fail' ($empty -join '; ')
    } else {
        Add-Result 'G0.4.b' 'Scope budget table is filled in' 'pass' ($data.Count.ToString() + ' rows')
    }
}

$pillars = Get-Section $text 'Three pillars'
$numbered = @($pillars -split "`n" | Where-Object { $_ -match '^\s*[1-3]\.\s+\S' })
if ($numbered.Count -eq 3) {
    Add-Result 'G0.2.s' 'Three pillars are numbered' 'pass' '3 entries'
} else {
    Add-Result 'G0.2.s' 'Three pillars are numbered' 'fail' ($numbered.Count.ToString() + ' numbered entries')
}

Complete-Gate 'G0 charter'
