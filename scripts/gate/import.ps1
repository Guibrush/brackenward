#requires -Version 5.1
# G1.6 — the project imports headlessly and every script parses.
#
# Two checks on purpose. `--import` exits 0 even when a script has a parse error
# and prints nothing, so it cannot be the only signal. See L-005.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G1 - headless import'

$bin = Get-GodotConsole
if (-not $bin) {
    Add-Result 'G1.6' 'Godot is available' 'blocked' 'no Godot console executable found'
    Complete-Gate 'G1 import'
}

$project = Join-Path $StudioRoot 'project.godot'
if (-not (Test-Path $project)) {
    Add-Result 'G1.6' 'Project file exists' 'blocked' 'project.godot missing - created at G1'
    Complete-Gate 'G1 import'
}

$import = Invoke-Native -Exe $bin -Arguments @('--headless', '--path', $StudioRoot, '--import')
if ($import.ExitCode -ne 0) {
    $tail = ($import.Output -split "`n" | Select-Object -Last 6) -join ' | '
    Add-Result 'G1.6' 'Asset import succeeds' 'fail' ('exit ' + $import.ExitCode + ': ' + $tail)
} else {
    Add-Result 'G1.6' 'Asset import succeeds' 'pass' ''
}

$scripts = @(Get-ChildItem $StudioRoot -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.godot\\' })

if ($scripts.Count -eq 0) {
    Add-Result 'G1.6.s' 'Script syntax check' 'pass' 'no scripts yet'
} else {
    $bad = @()
    foreach ($s in $scripts) {
        $res = ConvertTo-ResPath -Root $StudioRoot -Path $s.FullName
        if (-not $res) { continue }
        $chk = Invoke-Native -Exe $bin -Arguments @('--headless', '--path', $StudioRoot, '--check-only', '--script', $res)
        if ($chk.ExitCode -ne 0) {
            $first = ($chk.Output -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR|ERROR' } | Select-Object -First 1)
            if (-not $first) { $first = 'exit ' + $chk.ExitCode }
            $bad += ($res + ' -> ' + $first.Trim())
        }
    }
    if ($bad.Count -eq 0) {
        Add-Result 'G1.6.s' 'Script syntax check' 'pass' ($scripts.Count.ToString() + ' scripts parsed')
    } else {
        Add-Result 'G1.6.s' 'Script syntax check' 'fail' ($bad.Count.ToString() + ' of ' + $scripts.Count + ' failed: ' + ($bad -join '; '))
    }
}

Complete-Gate 'G1 import'
