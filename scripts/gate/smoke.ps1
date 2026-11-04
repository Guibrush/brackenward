#requires -Version 5.1
# G2.1, G4.5 — the game runs headlessly for a fixed duration without crashing.
#
# This is not a substitute for playing it. It catches crashes, script errors and
# infinite loops; it cannot tell you whether the game is any good.
param(
    [int]$Duration = 300
)
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G2 - smoke'

$bin = Get-GodotConsole
if (-not $bin) {
    Add-Result 'G2.1' 'Engine available' 'blocked' 'no Godot console executable'
    Complete-Gate 'G2 smoke'
}

$projectPath = Join-Path $StudioRoot 'project.godot'
$project = Read-Text $projectPath
if (-not $project) {
    Add-Result 'G2.1' 'Project exists' 'blocked' 'project.godot missing'
    Complete-Gate 'G2 smoke'
}

$m = [regex]::Match($project, '(?m)^run/main_scene\s*=\s*"([^"]+)"')
if (-not $m.Success) {
    Add-Result 'G2.1' 'A main scene is configured' 'blocked' 'run/main_scene is not set - nothing to run'
    Complete-Gate 'G2 smoke'
}

$frames = $Duration * 60
Write-Host ('  running ' + $m.Groups[1].Value + ' for ' + $Duration + 's (' + $frames + ' frames)')

$r = Invoke-Native -Exe $bin -Arguments @('--headless', '--path', $StudioRoot, '--quit-after', [string]$frames)
$errors = @($r.Output -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' })
if ($r.ExitCode -ne 0) {
    $tail = ($r.Output -split "`n" | Select-Object -Last 6) -join ' | '
    Add-Result 'G2.1' 'Runs without crashing' 'fail' ('exit ' + $r.ExitCode + ': ' + $tail)
} elseif ($errors.Count -gt 0) {
    Add-Result 'G2.1' 'Runs without crashing' 'fail' ($errors.Count.ToString() + ' error line(s), first: ' + $errors[0].Trim())
} else {
    Add-Result 'G2.1' 'Runs without crashing' 'pass' ($Duration.ToString() + 's, no error output')
}

Complete-Gate 'G2 smoke'
