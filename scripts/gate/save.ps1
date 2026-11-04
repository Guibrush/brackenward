#requires -Version 5.1
# G3.2 — save and load round-trip, including across a process restart.
#
# Blocked until a save system exists. When it does, the convention is:
#   scripts/tests/save_roundtrip.gd      writes a known state, reads it back
#   scripts/tests/save_roundtrip.ps1     runs it twice in separate processes:
#                                        1. write, then quit
#                                        2. launch, load, print the state
#   Pass when both processes agree and the saved file survives the restart.
#
# Two processes matters: a same-process round trip passes even when the file is
# never flushed to disk.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G3 - save and load'

$tests = Join-Path $StudioRoot 'tests'
$roundtripScript = Join-Path $StudioRoot 'scripts\tests\save_roundtrip.gd'
$roundtripRunner = Join-Path $StudioRoot 'scripts\tests\save_roundtrip.ps1'

if (-not (Test-Path $roundtripScript) -or -not (Test-Path $roundtripRunner)) {
    Add-Result 'G3.2' 'Save/load round-trip test exists' 'blocked' 'scripts/tests/save_roundtrip.{gd,ps1} not written - required at G3'
    Complete-Gate 'G3 save'
}

$r = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $roundtripRunner)
if ($r.ExitCode -eq 0) {
    Add-Result 'G3.2' 'Save/load round-trip passes across processes' 'pass' ''
} else {
    $tail = ($r.Output -split "`n" | Select-Object -Last 6) -join ' | '
    Add-Result 'G3.2' 'Save/load round-trip passes across processes' 'fail' ('exit ' + $r.ExitCode + ': ' + $tail)
}

Complete-Gate 'G3 save'
