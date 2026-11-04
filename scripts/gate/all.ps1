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

$fails = @($rows | Where-Object { $_.Code -eq 1 }).Count
$blocks = @($rows | Where-Object { $_.Code -eq 3 }).Count
$errors = @($rows | Where-Object { $_.Code -notin @(0, 1, 3) }).Count

Write-Host ''
Write-Host ('Summary: ' + $rows.Count + ' scripts, ' + $fails + ' fail, ' + $blocks + ' blocked, ' + $errors + ' error')
Write-Host 'Signature is still required from the human.'

if ($fails -gt 0 -or $errors -gt 0) { exit 1 }
if ($blocks -gt 0) { exit 3 }
exit 0
