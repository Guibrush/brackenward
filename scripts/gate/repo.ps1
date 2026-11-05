#requires -Version 5.1
# G1.1 - G1.4 — repository exists, branches are protected, CI is green.
#
# Protection is enforced by GitHub. This script verifies that it actually is,
# because "we assume we configured it" is how a force-push reaches main.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G1 - repository'

function Invoke-Gh {
    param([string[]]$Arguments)
    Push-Location $StudioRoot
    try { return (Invoke-Native -Exe 'gh' -Arguments $Arguments) }
    finally { Pop-Location }
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Add-Result 'G1.1' 'Repository reachable' 'blocked' 'gh not installed'
    Complete-Gate 'G1 repo'
}

$view = Invoke-Gh @('repo', 'view', '--json', 'nameWithOwner,url,visibility')
if ($view.ExitCode -ne 0) {
    Add-Result 'G1.1' 'Repository exists and is reachable' 'fail' 'gh repo view failed - no repository, or not authenticated'
    Add-Result 'G1.2' 'main is protected' 'blocked' 'no repository'
    Add-Result 'G1.3' 'dev is protected' 'blocked' 'no repository'
    Add-Result 'G1.4' 'CI green on dev' 'blocked' 'no repository'
    Complete-Gate 'G1 repo'
}

$repo = $view.Output | ConvertFrom-Json
$nwo = $repo.nameWithOwner
Write-Host ('  repository: ' + $nwo + ' (' + $repo.visibility + ')')
Add-Result 'G1.1' 'Repository exists and is reachable' 'pass' $nwo

$dev = Invoke-Gh @('api', ('repos/' + $nwo + '/branches/dev'))
if ($dev.ExitCode -eq 0) {
    Add-Result 'G1.1.b' 'dev branch exists' 'pass' 'dev'
} else {
    Add-Result 'G1.1.b' 'dev branch exists' 'fail' 'branch dev not found'
}

function Test-BranchProtection {
    param(
        [string]$Branch,
        [string]$Id,
        [int]$MinApprovals
    )
    $res = Invoke-Gh @('api', ('repos/' + $nwo + '/branches/' + $Branch + '/protection'))
    if ($res.ExitCode -ne 0) {
        $hint = 'not protected, or not readable (needs admin or a paid plan)'
        Add-Result $Id ('' + $Branch + ' is protected') 'fail' $hint
        return
    }
    $p = $res.Output | ConvertFrom-Json
    $problems = @()
    if (-not ($p.PSObject.Properties.Name -contains 'required_pull_request_reviews') -or $null -eq $p.required_pull_request_reviews) {
        $problems += 'PR not required'
    } else {
        $approvals = $p.required_pull_request_reviews.required_approving_review_count
        if ($null -eq $approvals) { $approvals = 0 }
        if ($approvals -ne $MinApprovals) { $problems += ('expected ' + $MinApprovals + ' approvals, found ' + $approvals) }
    }
    if (-not ($p.PSObject.Properties.Name -contains 'required_status_checks') -or $null -eq $p.required_status_checks) {
        $problems += 'status checks not required'
    }
    if ($p.allow_force_pushes -and $p.allow_force_pushes.enabled) { $problems += 'force push allowed' }
    if ($p.allow_deletions -and $p.allow_deletions.enabled) { $problems += 'deletion allowed' }

    if ($problems.Count -eq 0) {
        Add-Result $Id ('' + $Branch + ' is protected') 'pass' 'PR, checks, no force push, no delete'
    } else {
        Add-Result $Id ('' + $Branch + ' is protected') 'fail' ($problems -join '; ')
    }
}

Test-BranchProtection -Branch 'main' -Id 'G1.2' -MinApprovals 1
Test-BranchProtection -Branch 'dev' -Id 'G1.3' -MinApprovals 0

$runs = Invoke-Gh @('run', 'list', '--branch', 'dev', '--limit', '1', '--json', 'status,conclusion,headSha,workflowName')
if ($runs.ExitCode -ne 0) {
    Add-Result 'G1.4' 'CI is green on dev' 'fail' 'gh run list failed'
} else {
    $list = @($runs.Output | ConvertFrom-Json)
    if ($list.Count -eq 0) {
        Add-Result 'G1.4' 'CI is green on dev' 'fail' 'no workflow runs on dev'
    } else {
        $run = $list[0]
        $sha = [string]$run.headSha
        if ($sha.Length -gt 7) { $sha = $sha.Substring(0, 7) }
        if ($run.status -ne 'completed') {
            # An unfinished run is unknown, not failed. Reporting fail here turns G1
            # red for the minutes after every merge, which teaches people to ignore
            # a red gate (L-019).
            Add-Result 'G1.4' 'CI is green on dev' 'blocked' ('run still ' + $run.status + ' on ' + $sha)
        } elseif ($run.conclusion -eq 'success') {
            Add-Result 'G1.4' 'CI is green on dev' 'pass' ([string]$run.workflowName + ' @ ' + $sha)
        } elseif ($run.conclusion -eq 'cancelled') {
            Add-Result 'G1.4' 'CI is green on dev' 'blocked' ('run cancelled on ' + $sha + ' - re-run it')
        } else {
            Add-Result 'G1.4' 'CI is green on dev' 'fail' ('run ' + $run.conclusion + ' on ' + $sha)
        }
    }
}

Complete-Gate 'G1 repo'
