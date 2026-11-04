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

# $files must hold FileInfo objects, not strings: the scanner needs .Extension and
# .FullName. Building it from `git ls-files` text gives strings, on which both
# properties are $null - the loop then threw once per file and scanned nothing
# while still counting every file (T-0006). Anything added here must stay a
# FileInfo.
$files = @()
$gitDir = Join-Path $StudioRoot '.git'
$gitExe = Get-GitPath
if ((Test-Path $gitDir) -and $gitExe) {
    # -z keeps paths literal. Without it git quotes names that contain non-ASCII
    # bytes, Test-Path then rejects the quoted string, and the file is silently
    # dropped from the scan.
    $tracked = Invoke-Native -Exe $gitExe -Arguments @('ls-files', '-z')
    if ($tracked.ExitCode -eq 0) {
        $files = @($tracked.Output -split "`0" |
            Where-Object { $_.Trim() -ne '' } |
            ForEach-Object { Join-Path $StudioRoot ($_.Trim() -replace '/', '\') } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            ForEach-Object { Get-Item -LiteralPath $_ })
    }
}
if ($files.Count -eq 0) {
    $files = @(Get-ChildItem $StudioRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\|\\\.godot\\|\\node_modules\\|\\build\\' })
}

$findings = @()
$unreadable = @()
$scanned = 0
$skipped = 0
foreach ($f in $files) {
    $ext = $f.Extension.ToLowerInvariant()
    if ($skipExtensions -contains $ext) { $skipped++; continue }
    if ($f.FullName -match '\\scripts\\gate\\') { continue }   # this scanner describes the patterns
    if ($f.FullName -match '\\scripts\\lib\\') { continue }
    try {
        $content = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Not counted as scanned: a file we could not read was not regex-tested,
        # and reporting it as covered is the failure T-0006 exists to remove.
        $unreadable += $f.FullName.Replace($StudioRoot + '\', '')
        continue
    }
    $scanned++
    if ([string]::IsNullOrEmpty($content)) { continue }
    foreach ($p in $patterns) {
        if ($content -match $p.Regex) {
            $rel = $f.FullName.Replace($StudioRoot + '\', '')
            $findings += ($p.Name + ' in ' + $rel)
        }
    }
}

$coverage = ($scanned.ToString() + ' files scanned, ' + $skipped.ToString() + ' skipped by extension')

if ($findings.Count -gt 0) {
    Add-Result 'G1.9' 'No key-shaped strings in tracked files' 'fail' (($findings | Select-Object -First 6) -join '; ')
} elseif ($unreadable.Count -gt 0) {
    # Cannot evaluate is blocked, never pass: an unread scannable file is a hole.
    Add-Result 'G1.9' 'No key-shaped strings in tracked files' 'blocked' ('unreadable: ' + (($unreadable | Select-Object -First 6) -join '; '))
} else {
    Add-Result 'G1.9' 'No key-shaped strings in tracked files' 'pass' $coverage
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
