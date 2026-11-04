#requires -Version 5.1
# Creates the project repository and sets up the branch model. This is the
# sanctioned way to enter G1; running the git commands by hand risks skipping
# the secret scan or the protection step.
#
#   powershell -NoProfile -File scripts/git/init-repo.ps1 -Name forest-echo `
#       -Description "2D pixel-art exploration game"
#
# Order of operations is deliberate:
#   scan for secrets -> commit -> create repo -> push main -> create dev
#   -> make dev the default branch -> apply protection -> verify
#
# Nothing reaches GitHub before the secret scan passes.

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Description = '',
    [ValidateSet('public', 'private')][string]$Visibility = 'public',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

function Fail($msg) { Write-Host ('ERROR: ' + $msg); exit 1 }

# --- validate the name -------------------------------------------------------
$repoPart = $Name
if ($Name.Contains('/')) { $repoPart = $Name.Split('/')[-1] }
if ($repoPart -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') {
    Fail '-Name must be 3-40 lowercase characters, digits or single hyphens (an owner/ prefix is allowed)'
}
if ($repoPart -match '--') { Fail '-Name must not contain consecutive hyphens' }

Write-Host ('repository: ' + $Name + ' (' + $Visibility + ')')

# --- preconditions -----------------------------------------------------------
if (-not (Test-Path (Join-Path $DocsDir 'CHARTER.md'))) {
    Fail 'docs/CHARTER.md not found - run this from the project root, and only after G0 is signed'
}

$auth = Invoke-Native -Exe 'gh' -Arguments @('auth', 'status')
if ($auth.ExitCode -ne 0) { Fail 'gh is not authenticated - run: gh auth login' }

if (-not (Get-GitPath)) {
    Fail 'git is not installed or not on PATH - install Git for Windows, then reopen the shell'
}
$git = Get-GitPath

$inside = Invoke-Native -Exe $git -Arguments @('rev-parse', '--is-inside-work-tree')
if ($inside.ExitCode -eq 0) {
    $remote = Invoke-Native -Exe $git -Arguments @('remote', 'get-url', 'origin')
    if ($remote.ExitCode -eq 0) {
        Fail ('this working tree already has an origin: ' + $remote.Output.Trim())
    }
}

$email = Invoke-Native -Exe $git -Arguments @('config', 'user.email')
if ($email.ExitCode -ne 0 -or $email.Output.Trim() -eq '') {
    Fail 'git user.email is not set - run: git config --global user.email "you@example.com" and user.name'
}

if (-not (Test-Path (Join-Path $StudioRoot '.gitignore'))) {
    Fail '.gitignore is missing - refusing to create a repository that may commit build output'
}

# --- secret scan before anything leaves the machine --------------------------
Write-Host 'scanning for secrets'
$scan = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot '..\gate\secrets.ps1'))
if ($scan.ExitCode -ne 0) {
    Write-Host $scan.Output.TrimEnd()
    Fail 'secret scan failed - fix it before creating the repository'
}
Write-Host '  no key-shaped strings found'

if ($DryRun) {
    Write-Host ''
    Write-Host 'would run:'
    Write-Host '  git init && git add -A && git commit -m "chore: initial studio scaffold"'
    Write-Host ('  gh repo create ' + $Name + ' --' + $Visibility + ' --source . --remote origin --push')
    Write-Host '  git switch -c dev && git push -u origin dev'
    Write-Host '  gh repo edit --default-branch dev'
    Write-Host '  scripts/git/protect.ps1'
    exit 0
}

# --- initialise and commit ---------------------------------------------------
if ($inside.ExitCode -ne 0) {
    Write-Host 'initialising repository'
    $init = Invoke-Native -Exe $git -Arguments @('init', '-b', 'main')
    if ($init.ExitCode -ne 0) { Fail ('git init failed: ' + $init.Output.Trim()) }
}

$add = Invoke-Native -Exe $git -Arguments @('add', '-A')
if ($add.ExitCode -ne 0) { Fail ('git add failed: ' + $add.Output.Trim()) }

$staged = Invoke-Native -Exe $git -Arguments @('diff', '--cached', '--name-only')
if ($staged.Output.Trim() -eq '') {
    Write-Host 'nothing to commit'
} else {
    $count = @($staged.Output.Trim() -split "`n").Count
    $commit = Invoke-Native -Exe $git -Arguments @('commit', '-m', 'chore: initial studio scaffold', '-m', ($count.ToString() + ' files: studio agents, gates, scripts, and documentation.'))
    if ($commit.ExitCode -ne 0) { Fail ('git commit failed: ' + $commit.Output.Trim()) }
    Write-Host ('committed ' + $count + ' files')
}

$branch = Invoke-Native -Exe $git -Arguments @('branch', '--show-current')
if ($branch.Output.Trim() -ne 'main') {
    $rename = Invoke-Native -Exe $git -Arguments @('branch', '-M', 'main')
    if ($rename.ExitCode -ne 0) { Fail ('could not create main: ' + $rename.Output.Trim()) }
}

# --- create the remote and push ---------------------------------------------
Write-Host 'creating repository'
$create = Invoke-Native -Exe 'gh' -Arguments @('repo', 'create', $Name, ('--' + $Visibility), '--source', '.', '--remote', 'origin', '--push', '--description', $Description)
if ($create.ExitCode -ne 0) {
    Write-Host $create.Output.TrimEnd()
    Fail 'gh repo create failed - the name may be taken, or the account lacks permission'
}
Write-Host ('  ' + $create.Output.Trim())

# --- integration branch ------------------------------------------------------
Write-Host 'creating dev'
$switch = Invoke-Native -Exe $git -Arguments @('switch', '-c', 'dev')
if ($switch.ExitCode -ne 0) { Fail ('could not create dev: ' + $switch.Output.Trim()) }

$push = Invoke-Native -Exe $git -Arguments @('push', '-u', 'origin', 'dev')
if ($push.ExitCode -ne 0) { Fail ('could not push dev: ' + $push.Output.Trim()) }

# dev is the default branch: the place work lands, not the place releases live.
$edit = Invoke-Native -Exe 'gh' -Arguments @('repo', 'edit', '--default-branch', 'dev')
if ($edit.ExitCode -ne 0) {
    Write-Host 'WARNING: could not set dev as the default branch - set it manually in repository settings'
}

# --- protection --------------------------------------------------------------
Write-Host 'applying protection'
$protect = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'protect.ps1'))
Write-Host $protect.Output.TrimEnd()
if ($protect.ExitCode -ne 0) {
    Write-Host 'WARNING: protection did not fully apply. G1.2 and G1.3 are not satisfied until it does.'
}

# --- summary -----------------------------------------------------------------
$url = Invoke-Native -Exe 'gh' -Arguments @('repo', 'view', '--json', 'url', '--jq', '.url')
Write-Host ''
Write-Host ('repository: ' + $url.Output.Trim())
Write-Host 'branches:   main (release, 1 approval), dev (integration, CI-gated)'
Write-Host ''
Write-Host 'next:'
Write-Host '  1. record the URL and codename in docs/STATE.md'
Write-Host '  2. powershell -NoProfile -File scripts/gate/repo.ps1   # verify protection'
Write-Host '  3. prove the loop: new-task-branch.ps1 -> commit -> push -> gh pr create --base dev'
Write-Host '  4. G1.8 is signed on that merged pull request, not on this script output'
exit 0
