#requires -Version 5.1
# Test runner behind G2.9. One case = one file in scripts/tests/cases/*.gd.
#
# A case extends scripts/tests/lib/suite.gd, drives the real res://scenes/main.tscn,
# records checks, and prints exactly one machine-readable line before exiting:
#
#   TEST_RESULT {"name":"...","status":"pass|fail","checks":N,"failed":M,...}
#
# This runner classifies a case from what the case printed, never from the exit
# code alone (L-035: the arena quits 0 while printing errors). Five shapes, and
# all four non-green ones are failures with their own words, so a case that
# silently does nothing can never look green (L-021, L-031, L-033):
#
#   exactly one TEST_RESULT, status pass, exit 0, no ERROR: line  -> pass
#   exactly one TEST_RESULT, status fail                          -> fail, named
#     by the case's own name (the human sentence, not the file)
#   no TEST_RESULT line                                           -> fail, named
#     by its file: parse error, crash, or a script the engine refused to load
#   more than one TEST_RESULT line                                -> fail, ambiguous
#   TEST_RESULT says pass but the engine printed ERROR:/SCRIPT ERROR:,
#     or exited non-zero, or the case counted zero checks          -> fail
#
# Cases run one engine process each: one parse error or infinite loop cannot take
# the rest of the suite with it.
#
# Exit codes: 0 every case passed, 1 at least one case failed, 3 blocked (no
# engine, no cases directory, or no case file - an empty suite proves nothing and
# must never read as a pass).
#
#   powershell -NoProfile -File scripts/tests/run.ps1
#   powershell -NoProfile -File scripts/tests/run.ps1 -Filter leak_damage   # probe
param(
    # Regex matched against the case file's full path. A debugging aid for one
    # case; never used by the gate, which runs the whole suite.
    [string]$Filter = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

# Ceiling for a single case, in seconds. The harness bounds every wait it makes
# (suite.gd MAX_WAIT_FRAMES = 1200 physics frames), so a case that reaches this
# ceiling is hung in its own code, not slow. A gate that can hang forever is not
# a gate, which is why this is bounded rather than common.ps1's Invoke-Native.
$CaseTimeoutSeconds = 120

$ResultPrefix = 'TEST_RESULT '
$ErrorPattern = '^\s*(ERROR:|SCRIPT ERROR:)'

$bin = Get-GodotConsole
if (-not $bin) {
    Write-Host 'tests: blocked, no Godot console executable'
    exit 3
}

$casesDir = Join-Path $StudioRoot 'scripts\tests\cases'
if (-not (Test-Path -LiteralPath $casesDir)) {
    Write-Host ('tests: blocked, no cases directory at scripts/tests/cases')
    exit 3
}

# Sorted by name: Get-ChildItem order is whatever the filesystem feels like, and
# the same tree must produce the same report every run.
$cases = @(Get-ChildItem -LiteralPath $casesDir -Filter '*.gd' -File | Sort-Object -Property Name)
if ($Filter -ne '') { $cases = @($cases | Where-Object { $_.FullName -match $Filter }) }
if ($cases.Count -eq 0) {
    Write-Host 'tests: blocked, no case files in scripts/tests/cases'
    exit 3
}

# Runs the engine with a hard bound. Modeled on scripts/gate/smoke.ps1's
# Invoke-BoundedRun, which exists for the same reason: common.ps1's Invoke-Native
# waits forever, and a hung case is a result to report, not something to wait on.
# The pipe handling is identical, also for the reason written there - redirected
# native stderr must not become a PowerShell ErrorRecord in a caller running with
# $ErrorActionPreference = 'Stop'.
function Invoke-CaseRun {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]') { $quoted += ('"' + ($a -replace '"', '\"') + '"') }
        else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        return [pscustomobject]@{
            ExitCode = 127
            TimedOut = $false
            Output   = ('executable not found or not runnable: ' + $Exe)
        }
    }

    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $p.Kill() } catch { }
        # Drain the pipes so the read tasks can complete and the output is kept.
        [void]$p.WaitForExit(5000)
    }

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        TimedOut = $timedOut
        Output   = (Remove-Ansi ($outTask.Result + $errTask.Result))
    }
}

function Get-CaseReport {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][object]$Run
    )

    $lines = @($Run.Output -split "`n")
    $resultLines = @($lines | Where-Object { $_ -match '^TEST_RESULT\s' })
    $errorLines = @($lines | Where-Object { $_ -match $ErrorPattern })

    if ($Run.TimedOut) {
        return [pscustomobject]@{ Name = $Label; Pass = $false; Why = ('did not finish within ' + $CaseTimeoutSeconds + 's, killed - the case is hung') }
    }
    if ($resultLines.Count -gt 1) {
        return [pscustomobject]@{ Name = $Label; Pass = $false; Why = ('printed ' + $resultLines.Count + ' TEST_RESULT lines; a case must print exactly one') }
    }
    if ($resultLines.Count -eq 0) {
        # The case never got as far as reporting. A parse error is the common
        # cause and the engine's own line is the most useful text available.
        if ($errorLines.Count -gt 0) {
            $why = 'never ran: ' + $errorLines[0].Trim()
        } else {
            $why = 'never ran: no TEST_RESULT line (engine exit ' + $Run.ExitCode + ')'
        }
        return [pscustomobject]@{ Name = $Label; Pass = $false; Why = $why }
    }

    $json = ($resultLines[0] -replace '^TEST_RESULT\s+', '')
    $payload = $null
    try { $payload = $json | ConvertFrom-Json } catch { $payload = $null }
    if ($null -eq $payload) {
        return [pscustomobject]@{ Name = $Label; Pass = $false; Why = ('TEST_RESULT line is not valid JSON: ' + $json) }
    }

    $name = $Label
    if ($payload.PSObject.Properties.Name -contains 'name' -and $payload.name) { $name = [string]$payload.name }

    if ([string]$payload.status -ne 'pass') {
        $detail = ''
        if ($payload.PSObject.Properties.Name -contains 'message' -and $payload.message) { $detail = [string]$payload.message }
        if ($detail -eq '') { $detail = 'no message' }
        $count = ''
        if ($payload.PSObject.Properties.Name -contains 'failed') { $count = [string]$payload.failed + ' failed of ' + [string]$payload.checks + ' check(s): ' }
        return [pscustomobject]@{ Name = $name; Pass = $false; Why = ('status fail, engine exit ' + $Run.ExitCode + ', ' + $count + $detail) }
    }

    # From here the case called itself a pass. Three things can still contradict it.
    if ($errorLines.Count -gt 0) {
        return [pscustomobject]@{ Name = $name; Pass = $false; Why = ('reported pass but the scene printed: ' + $errorLines[0].Trim()) }
    }
    if ($Run.ExitCode -ne 0) {
        return [pscustomobject]@{ Name = $name; Pass = $false; Why = ('reported pass but the engine exited ' + $Run.ExitCode) }
    }
    if ($payload.PSObject.Properties.Name -contains 'checks' -and [int]$payload.checks -eq 0) {
        return [pscustomobject]@{ Name = $name; Pass = $false; Why = 'reported pass while recording zero checks - it proved nothing' }
    }
    return [pscustomobject]@{ Name = $name; Pass = $true; Why = '' }
}

Write-Host ('tests: ' + $cases.Count + ' case(s) in scripts/tests/cases')

$passed = @()
$failed = @()

foreach ($case in $cases) {
    $label = 'scripts/tests/cases/' + $case.Name
    $res = ConvertTo-ResPath -Root $StudioRoot -Path $case.FullName
    if (-not $res) {
        Write-Host ('  FAIL  ' + $label + '  - not inside the project, so it has no res:// path')
        $failed += [pscustomobject]@{ Name = $label; Why = 'no res:// path' }
        continue
    }

    $run = Invoke-CaseRun -Exe $bin -Arguments @('--headless', '--path', $StudioRoot, '--script', $res) -TimeoutSeconds $CaseTimeoutSeconds
    $report = Get-CaseReport -Label $label -Run $run

    if ($report.Pass) {
        Write-Host ('  PASS  ' + $report.Name)
        $passed += $report.Name
    } else {
        Write-Host ('  FAIL  ' + $report.Name + '  - ' + $report.Why)
        $failed += $report
    }
}

Write-Host ''
Write-Host ('tests: ' + $passed.Count + ' passed, ' + $failed.Count + ' failed, ' + $cases.Count + ' case(s)')
if ($failed.Count -gt 0) {
    Write-Host 'failing:'
    foreach ($f in $failed) {
        Write-Host ('  - ' + $f.Name)
    }
    exit 1
}
exit 0
