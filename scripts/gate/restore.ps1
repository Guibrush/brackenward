#requires -Version 5.1
# Restores the tree after an in-place mutation.
#
#   powershell -NoProfile -File scripts/gate/restore.ps1
#   powershell -NoProfile -File scripts/gate/restore.ps1 -Root <path>   # audit/drill
#
# A mutator writes `.mutation-active` at the repository root before it touches a
# file, and records the backup and the original SHA-256 of every path it is about
# to overwrite. This script is the only sanctioned way out of that state:
#
#   1. read `.mutation-backup/manifest.json`
#   2. copy every recorded backup back over its path
#   3. re-hash the path on disk and compare with the recorded SHA-256
#   4. delete `.mutation-backup/` and then `.mutation-active`, only if every hash
#      matched
#
# Exit codes, and what each one means to the caller:
#   0  pass     every path restored and every SHA-256 verified; residues deleted
#   1  fail     something could not be restored or verified; NOTHING was deleted,
#               the sentinel is still there, and every failing path is named
#   3  blocked  `.mutation-active` is absent, so there is nothing to restore.
#               This is not a pass: no restore was performed and no hash was
#               checked. A caller that treats 3 as success would report an
#               unverified tree as a clean one.
#
# Format this script accepts (written by the mutator, not by this script):
#
#   .mutation-active
#       # optional comment lines, ignored
#       ISO: 2026-11-06T14:03:11Z
#       AGENT: eng/tools
#       TASK: T-0031
#       MANIFEST: .mutation-backup/manifest.json
#       PATH: src/gameplay/arena.gd
#
#   .mutation-backup/manifest.json
#       {
#         "version": 1,
#         "iso": "2026-11-06T14:03:11Z",
#         "agent": "eng/tools",
#         "task": "T-0031",
#         "entries": [
#           { "path": "src/gameplay/arena.gd",
#             "backup": ".mutation-backup/files/src/gameplay/arena.gd",
#             "sha256": "<64 uppercase hex of the ORIGINAL file>" }
#         ]
#       }
#
# Paths are relative to the repository root, forward slashes. Anything absolute, any
# `..` segment, and any backup outside `.mutation-backup/` is refused rather than
# resolved: a manifest is data on disk, and data on disk is untrusted input.
param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Root -eq '') {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
} else {
    $root = (Resolve-Path -LiteralPath $Root).Path
}
$root = $root.TrimEnd('\')

$sentinel   = Join-Path $root '.mutation-active'
$backupDir  = Join-Path $root '.mutation-backup'
$manifest   = Join-Path $backupDir 'manifest.json'

Write-Host 'restore - in-place mutation'
Write-Host ('  root    ' + $root)

# No sentinel is not success. It means no restoration happened and no hash was
# checked, so reporting 0 would be the exact lie this task exists to prevent.
if (-not (Test-Path -LiteralPath $sentinel)) {
    Write-Host '  nothing to restore: .mutation-active is absent'
    Write-Host 'restore: blocked - no mutation in progress, nothing was verified'
    exit 3
}

if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Host ('  [FAIL] cannot restore: ' + $manifest + ' is missing')
    Write-Host '  .mutation-active is KEPT - a sentinel is only cleared by a verified restore'
    exit 1
}

try {
    $obj = [System.IO.File]::ReadAllText($manifest) | ConvertFrom-Json
} catch {
    Write-Host ('  [FAIL] cannot restore: manifest is not valid JSON - ' + $_.Exception.Message)
    Write-Host '  .mutation-active is KEPT'
    exit 1
}

$entries = @()
if ($obj.PSObject.Properties.Name -contains 'entries') { $entries = @($obj.entries) }
if ($entries.Count -eq 0) {
    Write-Host '  [FAIL] cannot restore: the manifest records no paths'
    Write-Host '  .mutation-active is KEPT'
    exit 1
}
if ($obj.PSObject.Properties.Name -contains 'task') {
    Write-Host ('  task    ' + $obj.task + ' by ' + $obj.agent)
}

# A relative path that stays inside the root, or $null. Both the restore target and
# the backup are checked: one is written over, the other is read.
function Test-RelPath {
    param([string]$Rel, [string]$MustStartWith = '')
    if ([string]::IsNullOrWhiteSpace($Rel)) { return $null }
    $p = $Rel.Replace('\', '/').Trim()
    if ($p.StartsWith('/')) { return $null }
    if ($p -match '^[A-Za-z]:') { return $null }
    foreach ($seg in $p.Split('/')) {
        if ($seg -eq '..') { return $null }
    }
    if ($MustStartWith -ne '' -and -not $p.StartsWith($MustStartWith)) { return $null }
    return $p
}

$failed = 0
$checked = 0
$manifestPaths = @()

foreach ($e in $entries) {
    $checked = $checked + 1
    $rel = Test-RelPath -Rel ([string]$e.path)
    if ($null -eq $rel) {
        Write-Host ('  [FAIL] ' + [string]$e.path + ' - not a relative path inside the repository')
        $failed = $failed + 1
        continue
    }
    $manifestPaths += $rel
    $relBackup = Test-RelPath -Rel ([string]$e.backup) -MustStartWith '.mutation-backup/'
    if ($null -eq $relBackup) {
        Write-Host ('  [FAIL] ' + $rel + ' - backup path is missing or outside .mutation-backup/')
        $failed = $failed + 1
        continue
    }
    $expected = ([string]$e.sha256).Trim().ToUpperInvariant()
    if ($expected -notmatch '^[0-9A-F]{64}$') {
        Write-Host ('  [FAIL] ' + $rel + ' - recorded sha256 is not 64 hex characters: ' + $expected)
        $failed = $failed + 1
        continue
    }

    $target = Join-Path $root ($rel.Replace('/', '\'))
    $source = Join-Path $root ($relBackup.Replace('/', '\'))

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Host ('  [FAIL] ' + $rel + ' - backup missing: ' + $relBackup)
        $failed = $failed + 1
        continue
    }

    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    Copy-Item -LiteralPath $source -Destination $target -Force

    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        Write-Host ('  [FAIL] ' + $rel + ' - sha256 mismatch: recorded ' + $expected + ', on disk ' + $actual)
        $failed = $failed + 1
        continue
    }
    Write-Host ('  [OK]   ' + $rel + '  sha256 ' + $actual)
}

# The sentinel is the claim that these paths were mutated. Clearing it while one of
# its own paths is absent from the manifest would restore the tree halfway and then
# erase the record of the rest: silent loss, which is the failure this task exists
# to make impossible.
$sentinelPaths = @()
foreach ($line in ([System.IO.File]::ReadAllText($sentinel) -split "\r?\n")) {
    $m = [regex]::Match($line, '^\s*PATH:\s*(\S.*?)\s*$')
    if ($m.Success) { $sentinelPaths += (Test-RelPath -Rel $m.Groups[1].Value) }
}
if ($sentinelPaths.Count -gt 0) {
    foreach ($sp in $sentinelPaths) {
        if ($null -eq $sp) { continue }
        if ($manifestPaths -notcontains $sp) {
            Write-Host ('  [FAIL] ' + $sp + ' - listed in .mutation-active but not restored from the manifest')
            $failed = $failed + 1
            $checked = $checked + 1
        }
    }
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host ('restore: ' + $checked + ' path(s), ' + $failed + ' failed - .mutation-active KEPT, .mutation-backup/ KEPT')
    exit 1
}

# Every recorded hash matched. Only now may the record be destroyed.
Remove-Item -LiteralPath $backupDir -Recurse -Force
Remove-Item -LiteralPath $sentinel -Force
Write-Host ('restore: ' + $checked + ' path(s) restored and verified - .mutation-backup/ and .mutation-active removed')
exit 0
