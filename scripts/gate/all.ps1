#requires -Version 5.1
# Runs every gate up to the requested one, cumulatively.
#
#   powershell -NoProfile -File scripts/gate/all.ps1            # everything
#   powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1   # G0 + G1
#
# An earlier gate is always re-checked, because "G0 still holds" is itself a
# criterion in every later gate.
param(
    [ValidateSet('G0', 'G1', 'G2', 'G3', 'G4', 'G5')]
    [string]$Gate = 'G5',
    # Scripts to skip by name. CI skips `repo` because reading branch protection
    # needs admin scope that a workflow token does not have; that check is run
    # locally by the human instead.
    [string[]]$Skip = @()
)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

$plan = [ordered]@{
    'G0' = @('charter', 'style', 'audio_spec')
    'G1' = @('engine', 'import', 'repo', 'secrets')
    'G2' = @('assets', 'audio', 'tests', 'smoke', 'perf')
    'G3' = @('save')
    'G4' = @('strings')
    'G5' = @('licenses', 'repro')
}

$order = @('G0', 'G1', 'G2', 'G3', 'G4', 'G5')
$upto = [array]::IndexOf($order, $Gate)

Write-Host ('Running gates G0..' + $Gate)
Write-Host ''

$rows = @()
$aborted = $false

# Process precondition, not a gate criterion, and therefore not part of the plan
# table below: a tree with an in-place mutation in progress is not the tree the
# gates were written to describe, so the suite stops before evaluating anything.
# Reporting twelve green criteria about content nobody has seen is worse than
# reporting nothing (T-0031, scripts/gate/mutation.ps1). Its exit code is handled
# by the same summary and the same exit-code meanings as every other script.
$preName = 'mutation'
if ($Skip -contains $preName) {
    $rows += [pscustomobject]@{ Gate = '--'; Script = $preName; Code = 0; Note = 'skipped' }
    Write-Host ('  -- ' + $preName.PadRight(12) + ' skipped')
} else {
    $prePath = Join-Path $PSScriptRoot ($preName + '.ps1')
    if (-not (Test-Path $prePath)) {
        $rows += [pscustomobject]@{ Gate = '--'; Script = $preName; Code = 3; Note = 'script missing' }
        Write-Host ('  -- ' + $preName.PadRight(12) + ' script missing')
        $aborted = $true
    } else {
        $pr = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $prePath)
        $preNote = ''
        if ($pr.ExitCode -eq 0) { $preNote = 'pass' }
        elseif ($pr.ExitCode -eq 1) { $preNote = 'fail' }
        elseif ($pr.ExitCode -eq 3) { $preNote = 'blocked' }
        else { $preNote = 'error ' + $pr.ExitCode }
        $rows += [pscustomobject]@{ Gate = '--'; Script = $preName; Code = $pr.ExitCode; Note = $preNote }
        Write-Host ('  -- ' + $preName.PadRight(12) + ' ' + $preNote)

        if ($pr.ExitCode -ne 0) {
            # The child's own lines are the evidence — for a sentinel that is the
            # quoted contents, for anything else the failing assertion. Reducing it
            # to one word would throw away the only thing the operator needs.
            foreach ($line in ($pr.Output -split "\r?\n")) {
                if ($line.Trim() -ne '') { Write-Host ('     ' + $line) }
            }
            $aborted = $true
        }
    }
}
Write-Host ''

if (-not $aborted) {
foreach ($g in $order[0..$upto]) {
    foreach ($script in $plan[$g]) {
        if ($Skip -contains $script) {
            $rows += [pscustomobject]@{ Gate = $g; Script = $script; Code = 0; Note = 'skipped' }
            Write-Host ('  ' + $g + ' ' + $script.PadRight(12) + ' skipped')
            continue
        }
        $path = Join-Path $PSScriptRoot ($script + '.ps1')
        if (-not (Test-Path $path)) {
            $rows += [pscustomobject]@{ Gate = $g; Script = $script; Code = 3; Note = 'script missing' }
            continue
        }
        $r = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path)
        $note = ''
        if ($r.ExitCode -eq 0) { $note = 'pass' }
        elseif ($r.ExitCode -eq 1) { $note = 'fail' }
        elseif ($r.ExitCode -eq 3) { $note = 'blocked' }
        else { $note = 'error ' + $r.ExitCode }
        $rows += [pscustomobject]@{ Gate = $g; Script = $script; Code = $r.ExitCode; Note = $note }
        Write-Host ('  ' + $g + ' ' + $script.PadRight(12) + ' ' + $note)
    }
}
}

$fails = @($rows | Where-Object { $_.Code -eq 1 }).Count
$blocks = @($rows | Where-Object { $_.Code -eq 3 }).Count
$errors = @($rows | Where-Object { $_.Code -notin @(0, 1, 3) }).Count

Write-Host ''
Write-Host ('Summary: ' + $rows.Count + ' scripts, ' + $fails + ' fail, ' + $blocks + ' blocked, ' + $errors + ' error')
if ($aborted) {
    Write-Host 'ABORTED by the mutation precondition - no gate criterion was evaluated against this tree.'
} else {
    Write-Host 'Signature is still required from the human.'
}

if ($fails -gt 0 -or $errors -gt 0) { exit 1 }
if ($blocks -gt 0) { exit 3 }
exit 0
