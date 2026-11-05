#requires -Version 5.1
# G2.9 - the test suite is green.
#
# The criterion is "the suite passes", so this gate runs the suite. It does not
# inspect the tests directory, count files, or trust a summary: it invokes
# scripts/tests/run.ps1 and reads the runner's own verdict.
#
# The runner owns the per-case rules (one TEST_RESULT line per case, a case that
# never ran is a failure, an ERROR: line contradicts a pass); they are documented
# in scripts/tests/run.ps1. This gate owns three things only:
#
#   1. the runner exists, or G2.9 is blocked - not failed, since no suite ran;
#   2. the runner's exit code maps to the studio's contract -
#        0 -> pass, 1 -> fail, 3 -> blocked, anything else -> fail
#      (an unrecognised code means the runner itself broke, which is a failure of
#      the suite, never a pass);
#   3. the failing case names reach the gate result, so a red gate names the test
#      without anyone opening a log.
#
# The runner's output is echoed through this gate unchanged. A gate that swallows
# the detail it decided on is unreadable at 2 a.m.
#
# Exit codes: 0 pass, 1 fail, 3 blocked (no engine, no runner, no cases).
#
#   powershell -NoProfile -File scripts/gate/tests.ps1
param()

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G2 - tests'

$runner = Join-Path $StudioRoot 'scripts\tests\run.ps1'
$casesDir = Join-Path $StudioRoot 'scripts\tests\cases'

if (-not (Test-Path -LiteralPath $runner)) {
    Add-Result 'G2.9' 'Test suite passes' 'blocked' 'scripts/tests/run.ps1 is missing - no suite can run'
    Complete-Gate 'G2 tests'
}
if (-not (Test-Path -LiteralPath $casesDir)) {
    Add-Result 'G2.9' 'Test suite passes' 'blocked' 'scripts/tests/cases/ is missing - the runner has nothing to run'
    Complete-Gate 'G2 tests'
}

$r = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner)

# Everything the suite decided, printed where the gate result is printed.
$lines = @($r.Output -split "`n" | Where-Object { $_.Trim() -ne '' })
foreach ($line in $lines) { Write-Host ('  | ' + $line.TrimEnd()) }

# Names of the cases that failed, as the runner printed them. A FAIL line is
# "  FAIL  <name>  - <why>"; the name is the case's own sentence when it ran, and
# its file when it never got that far.
$failedNames = @()
foreach ($line in $lines) {
    if ($line -match '^\s*FAIL\s+(.+?)(\s+-\s+.*)?$') {
        $failedNames += $Matches[1].Trim()
    }
}

switch ($r.ExitCode) {
    0 {
        Add-Result 'G2.9' 'Test suite passes' 'pass' 'every case in scripts/tests/cases passed'
    }
    1 {
        if ($failedNames.Count -gt 0) {
            $shown = @($failedNames | Select-Object -First 5) -join '; '
            if ($failedNames.Count -gt 5) { $shown = $shown + '; +' + ($failedNames.Count - 5) + ' more' }
            $detail = ($failedNames.Count.ToString() + ' case(s) failed: ' + $shown)
        } elseif ($lines.Count -gt 0) {
            $detail = 'exit 1, no FAIL line: ' + $lines[$lines.Count - 1]
        } else {
            $detail = 'exit 1, runner printed no output'
        }
        Add-Result 'G2.9' 'Test suite passes' 'fail' $detail
    }
    3 {
        $why = 'runner reported blocked (this run would be blocked too)'
        if ($lines.Count -gt 0) { $why = $lines[$lines.Count - 1] }
        Add-Result 'G2.9' 'Test suite passes' 'blocked' $why
    }
    default {
        $tail = ''
        if ($lines.Count -gt 0) {
            $tail = ($lines | Select-Object -Last 3) -join ' | '
        }
        Add-Result 'G2.9' 'Test suite passes' 'fail' ('runner exited ' + $r.ExitCode + ', which is not a test result: ' + $tail)
    }
}

Complete-Gate 'G2 tests'
