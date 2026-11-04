#requires -Version 5.1
# Applies and verifies branch protection. Idempotent: safe to run repeatedly.
#
#   powershell -NoProfile -File scripts/git/protect.ps1
#   powershell -NoProfile -File scripts/git/protect.ps1 -DryRun
#
# `main` requires one approval; `dev` requires none, because CI is the gate there
# and agents must be able to merge their own work. Neither allows force pushes,
# deletions, or bypassing by administrators.
#
# Note: on some account tiers branch protection is unavailable for private
# repositories. This script reports that plainly rather than implying success.

param(
    [switch]$DryRun,
    [string]$CheckName = 'gates'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

# Every protection requirement that could not be applied or read back. The exit
# code is derived from this list, so a failed call can never be reported as a
# success, which is how the BOM-mangled payload went unnoticed the first time.
$script:ProtectFailures = New-Object System.Collections.ArrayList

$nwo = $null
$view = Invoke-Native -Exe 'gh' -Arguments @('repo', 'view', '--json', 'nameWithOwner')
if ($view.ExitCode -ne 0) {
    Write-Host 'ERROR: gh repo view failed - no repository here, or not authenticated'
    exit 1
}
$nwo = ($view.Output | ConvertFrom-Json).nameWithOwner
Write-Host ('repository: ' + $nwo)

function Set-Protection {
    param([string]$Branch, [int]$Approvals)

    $payload = [ordered]@{
        required_status_checks          = [ordered]@{ strict = $true; contexts = @($CheckName) }
        enforce_admins                  = $true
        required_pull_request_reviews   = [ordered]@{
            required_approving_review_count = $Approvals
            dismiss_stale_reviews           = $true
        }
        restrictions                    = $null
        allow_force_pushes              = $false
        allow_deletions                 = $false
        required_conversation_resolution = $true
    } | ConvertTo-Json -Depth 6

    if ($DryRun) {
        Write-Host ('  [dry-run] would protect ' + $Branch + ' (approvals=' + $Approvals + ')')
        Write-Host ('  payload: ' + ($payload -replace '\s+', ' '))
        return
    }

    # `Set-Content -Encoding utf8` emits a UTF-8 BOM on Windows PowerShell 5.1,
    # and `gh api --input` sends the file byte for byte. GitHub answers 400
    # "Problems parsing JSON" and never applies the protection, so the body is
    # written explicitly as UTF-8 without a preamble.
    $tmp = Join-Path $env:TEMP ('protect_' + $Branch + '.json')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $payload, $utf8NoBom)

    $put = Invoke-Native -Exe 'gh' -Arguments @('api', '-X', 'PUT', ('repos/' + $nwo + '/branches/' + $Branch + '/protection'), '--input', $tmp)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    if ($put.ExitCode -ne 0) {
        $msg = ($put.Output -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 3) -join ' | '
        Write-Host ('  FAILED to protect ' + $Branch + ': ' + $msg)
        Write-Host '  If this is a private repository, protection may not be available on your plan.'
        [void]$script:ProtectFailures.Add(('protection was not applied to ' + $Branch))
        return
    }
    Write-Host ('  protected ' + $Branch + ' (approvals=' + $Approvals + ')')
}

function Show-Protection {
    param([string]$Branch)
    $get = Invoke-Native -Exe 'gh' -Arguments @('api', ('repos/' + $nwo + '/branches/' + $Branch + '/protection'))
    if ($get.ExitCode -ne 0) {
        Write-Host ('  ' + $Branch + ': not readable or not protected')
        [void]$script:ProtectFailures.Add(('protection not readable on ' + $Branch))
        return
    }
    $p = $get.Output | ConvertFrom-Json
    $approvals = 0
    if ($p.required_pull_request_reviews) { $approvals = $p.required_pull_request_reviews.required_approving_review_count }
    $checks = 'none'
    if ($p.required_status_checks -and $p.required_status_checks.contexts) { $checks = ($p.required_status_checks.contexts -join ',') }
    Write-Host ('  ' + $Branch + ': approvals=' + $approvals + ' checks=' + $checks + ' forcePush=' + $p.allow_force_pushes.enabled + ' delete=' + $p.allow_deletions.enabled)
}

Write-Host 'applying protection'
Set-Protection -Branch 'main' -Approvals 1
Set-Protection -Branch 'dev' -Approvals 0

if (-not $DryRun) {
    Write-Host 'verifying'
    Show-Protection -Branch 'main'
    Show-Protection -Branch 'dev'
}

Write-Host ''
if ($script:ProtectFailures.Count -gt 0) {
    Write-Host ('FAILED: ' + $script:ProtectFailures.Count + ' protection requirement(s) not satisfied')
    foreach ($f in $script:ProtectFailures) { Write-Host ('  - ' + $f) }
    Write-Host 'G1.2 and G1.3 are not satisfied until branch protection is actually applied.'
    exit 1
}
Write-Host 'Protection is enforced by GitHub, not by local policy. Verify it after any settings change.'
exit 0
