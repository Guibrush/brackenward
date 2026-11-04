#requires -Version 5.1
# Creates a task branch from `dev` with a consistent name.
#
#   powershell -NoProfile -File scripts/git/new-task-branch.ps1 -TaskId T-0012 -Slug jump-tuning
#
# Enforces the naming the pull-request templates and CI expect. Refuses to run
# on a dirty tree, because a branch created over uncommitted work makes the first
# commit ambiguous.

param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$Slug,
    [string]$Base = 'dev'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

if ($TaskId -notmatch '^T-\d{4}$') {
    Write-Host 'ERROR: -TaskId must look like T-0012'
    exit 1
}
if ($Slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    Write-Host 'ERROR: -Slug must be lowercase words separated by single hyphens'
    exit 1
}

$branch = 'task/' + $TaskId + '-' + $Slug
Write-Host ('branch: ' + $branch + ' from ' + $Base)

if (-not (Get-GitPath)) {
    Write-Host 'ERROR: git is not installed or not on PATH'
    exit 1
}
$git = Get-GitPath

$status = Invoke-Native -Exe $git -Arguments @('status', '--porcelain')
if ($status.ExitCode -ne 0) {
    Write-Host 'ERROR: not a git repository'
    exit 1
}
if ($status.Output.Trim() -ne '') {
    Write-Host 'ERROR: working tree is not clean - commit or stash first'
    exit 1
}

$fetch = Invoke-Native -Exe $git -Arguments @('fetch', 'origin')
if ($fetch.ExitCode -ne 0) {
    Write-Host ('ERROR: git fetch failed: ' + $fetch.Output.Trim())
    exit 1
}

$exists = Invoke-Native -Exe $git -Arguments @('rev-parse', '--verify', ('origin/' + $Base))
if ($exists.ExitCode -ne 0) {
    Write-Host ('ERROR: origin/' + $Base + ' does not exist - has the repository been created and pushed?')
    exit 1
}

$create = Invoke-Native -Exe $git -Arguments @('switch', '-c', $branch, ('origin/' + $Base))
if ($create.ExitCode -ne 0) {
    Write-Host ('ERROR: could not create branch: ' + $create.Output.Trim())
    exit 1
}

Write-Host ''
Write-Host 'next:'
Write-Host ('  1. write the brief in tasks/' + $TaskId + '.md if it does not exist')
Write-Host '  2. do the work, then commit in Conventional Commits format'
Write-Host ('  3. git push -u origin ' + $branch)
Write-Host ('  4. gh pr create --base ' + $Base + ' --title "<type>(<scope>): <summary>"')
exit 0
