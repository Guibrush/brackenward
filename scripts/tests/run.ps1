#requires -Version 5.1
# Test entry point expected by scripts/gate/tests.ps1.
#
# Convention: every `tests/**/*.gd` is a Godot script that extends SceneTree,
# prints what it checks, and exits non-zero on failure. No framework, no plugin,
# nothing to keep in sync with the engine version.
#
#   extends SceneTree
#   func _init() -> void:
#       if 1 + 1 != 2:
#           printerr("math is broken")
#           quit(1)
#       else:
#           quit(0)
#
# Exit codes: 0 all passed, 1 at least one failed, 3 no engine.

param(
    [string]$Filter = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

$bin = Get-GodotConsole
if (-not $bin) {
    Write-Host 'tests: blocked, no Godot console executable'
    exit 3
}

$testsDir = Join-Path $StudioRoot 'tests'
if (-not (Test-Path $testsDir)) {
    Write-Host 'tests: no tests/ directory'
    exit 0
}

$files = @(Get-ChildItem $testsDir -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue)
if ($Filter -ne '') { $files = @($files | Where-Object { $_.FullName -match $Filter }) }

if ($files.Count -eq 0) {
    Write-Host 'tests: 0 test scripts found'
    exit 0
}

Write-Host ('tests: ' + $files.Count + ' script(s)')

$failed = @()
foreach ($f in $files) {
    $rel = ConvertTo-ResPath -Root $StudioRoot -Path $f.FullName
    if (-not $rel) { continue }
    $name = $f.FullName.Replace($StudioRoot.TrimEnd('\') + '\', '')
    $r = Invoke-Native -Exe $bin -Arguments @('--headless', '--path', $StudioRoot, '--script', $rel)
    $ok = ($r.ExitCode -eq 0)
    $errors = @($r.Output -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:' })

    if ($ok -and $errors.Count -eq 0) {
        Write-Host ('  PASS  ' + $name)
    } else {
        $why = ''
        if ($r.ExitCode -ne 0) { $why = 'exit ' + $r.ExitCode }
        elseif ($errors.Count -gt 0) { $why = $errors[0].Trim() }
        Write-Host ('  FAIL  ' + $name + '  ' + $why)
        $failed += $name
    }
}

Write-Host ''
Write-Host ('tests: ' + ($files.Count - $failed.Count) + ' passed, ' + $failed.Count + ' failed')

if ($failed.Count -gt 0) { exit 1 }
exit 0
