#requires -Version 5.1
# G2.9 — the test suite is green.
#
# Convention: the suite entry point is scripts/tests/run.ps1 and exits 0 on
# success. Keeping the runner behind one script means the gate does not need to
# know which framework is in use.
param()
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G2 - tests'

$testDir = Join-Path $StudioRoot 'tests'
$runner = Join-Path $StudioRoot 'scripts\tests\run.ps1'

if (-not (Test-Path $testDir)) {
    Add-Result 'G2.9' 'A test suite exists' 'blocked' 'no tests/ directory - required before G2'
    Complete-Gate 'G2 tests'
}
if (-not (Test-Path $runner)) {
    Add-Result 'G2.9' 'A runner exists' 'blocked' 'scripts/tests/run.ps1 missing - see this file header for the convention'
    Complete-Gate 'G2 tests'
}

$r = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner)
if ($r.ExitCode -eq 0) {
    Add-Result 'G2.9' 'Test suite passes' 'pass' ''
} else {
    $tail = ($r.Output -split "`n" | Select-Object -Last 8) -join ' | '
    Add-Result 'G2.9' 'Test suite passes' 'fail' ('exit ' + $r.ExitCode + ': ' + $tail)
}

Complete-Gate 'G2 tests'
