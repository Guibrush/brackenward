#requires -Version 5.1
# G1.9, G1.10 — no secrets in tracked files, and .gitignore covers the basics.
#
# Value-shaped patterns only. Matching on variable names would fire on every
# document that mentions an API key, which trains people to ignore the check.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G1 - secrets and ignore rules'

$patterns = @(
    @{ Name = 'OpenAI/OpenRouter key'; Regex = 'sk-(or-v1-)?[A-Za-z0-9_\-]{20,}' },
    @{ Name = 'Anthropic key';        Regex = 'sk-ant-[A-Za-z0-9_\-]{20,}' },
    @{ Name = 'GitHub token';         Regex = '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}' },
    @{ Name = 'GitHub fine-grained';  Regex = 'github_pat_[A-Za-z0-9_]{40,}' },
    @{ Name = 'AWS access key';       Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'Private key block';    Regex = 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' },
    @{ Name = 'Assigned secret';      Regex = '(API_KEY|API_TOKEN|SECRET|PASSWORD)\s*[:=]\s*["''][^"'']{12,}["'']' }
)

$skipExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ogg', '.wav', '.mp3', '.zip', '.exe', '.dll', '.pck', '.ttf', '.otf', '.res', '.import')

$files = @()
$gitDir = Join-Path $StudioRoot '.git'
$gitExe = Get-GitPath
if ((Test-Path $gitDir) -and $gitExe) {
    $tracked = Invoke-Native -Exe $gitExe -Arguments @('ls-files')
    if ($tracked.ExitCode -eq 0) {
        $files = @($tracked.Output -split "`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { Join-Path $StudioRoot $_.Trim() } | Where-Object { Test-Path $_ })
    }
}
if ($files.Count -eq 0) {
    $files = @(Get-ChildItem $StudioRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\|\\\.godot\\|\\node_modules\\|\\build\\' })
}

$findings = @()
$scanned = 0
foreach ($f in $files) {
    if ($skipExtensions -contains $f.Extension.ToLower()) { continue }
    if ($f.FullName -match '\\scripts\\gate\\') { continue }   # this scanner describes the patterns
    if ($f.FullName -match '\\scripts\\lib\\') { continue }
    $scanned++
    try {
        $content = Get-Content $f.FullName -Raw -ErrorAction Stop
    } catch { continue }
    if ([string]::IsNullOrEmpty($content)) { continue }
    foreach ($p in $patterns) {
        if ($content -match $p.Regex) {
            $rel = $f.FullName.Replace($StudioRoot + '\', '')
            $findings += ($p.Name + ' in ' + $rel)
        }
    }
}

if ($findings.Count -eq 0) {
    Add-Result 'G1.9' 'No key-shaped strings in tracked files' 'pass' ($scanned.ToString() + ' files scanned')
} else {
    Add-Result 'G1.9' 'No key-shaped strings in tracked files' 'fail' (($findings | Select-Object -First 6) -join '; ')
}

$ignorePath = Join-Path $StudioRoot '.gitignore'
$ignore = Read-Text $ignorePath
$required = @('.env', '.godot/', 'build/')
$missing = @()
foreach ($r in $required) {
    if (-not $ignore -or -not $ignore.Contains($r)) { $missing += $r }
}
if ($missing.Count -eq 0) {
    Add-Result 'G1.10' '.gitignore covers engine cache, builds, and env files' 'pass' ''
} else {
    Add-Result 'G1.10' '.gitignore covers engine cache, builds, and env files' 'fail' ('missing: ' + ($missing -join ', '))
}

Complete-Gate 'G1 secrets'
