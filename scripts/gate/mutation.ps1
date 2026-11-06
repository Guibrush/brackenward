#requires -Version 5.1
# Process precondition — no in-place mutation is in progress.
#
# A mutator writes `.mutation-active` at the repository root before it touches the
# first file, and removes it only after `scripts/gate/restore.ps1` has put every
# touched path back and re-verified its SHA-256. While that file exists the tree is
# not the tree the gate believes it is reviewing, so no gate result may be reported
# as a pass: all.ps1 runs this script first and aborts the whole suite when it fails.
#
# This check deliberately does NOT look at `git status`. A mutated file can be
# committed by an agent that never runs status, and a clean status proves nothing
# about content that was rewritten and committed. The sentinel is a fact on disk,
# not a diff (T-0031, "Do not").
#
# It carries no numbered gate criterion. It is a process precondition required by
# T-0031; turning it into a numbered criterion is a human decision, not a tooling
# one.
#
# What it guarantees:
#   exit 0  `.mutation-active` is absent                       (pass)
#   exit 1  `.mutation-active` is present, contents quoted      (fail)
#   exit 3  never — the question "does the file exist" is always answerable
#
# A `.mutation-backup/` left behind without a sentinel is reported as NOTE, not as
# a result: it is residue worth seeing, but it is not the criterion this script owns
# and it must not change what the gate requires.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'Process - in-place mutation'

$sentinel = Join-Path $StudioRoot '.mutation-active'
$backupDir = Join-Path $StudioRoot '.mutation-backup'

if (-not (Test-Path -LiteralPath $sentinel)) {
    Add-Result 'MUT' 'No in-place mutation in progress' 'pass' '.mutation-active absent'
} else {
    # Quote the contents so the transcript says who mutated what, not just that
    # something did. One line per key: the failure detail has to fit in the suite
    # summary without hiding the payload.
    $raw = ''
    try {
        $raw = [System.IO.File]::ReadAllText($sentinel)
    } catch {
        $raw = '(unreadable: ' + $_.Exception.Message + ')'
    }

    $lines = @()
    foreach ($l in ($raw -split "\r?\n")) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { $lines += $t }
    }
    $quoted = ($lines -join ' | ')
    if ($quoted.Length -gt 600) { $quoted = $quoted.Substring(0, 600) + ' ...(truncated)' }
    if ($quoted -eq '') { $quoted = '(empty file)' }

    # An incomplete sentinel still fails; say which keys are missing so the operator
    # knows whether to restore or to read the file by hand.
    $missing = @()
    foreach ($key in @('AGENT:', 'TASK:', 'PATH:')) {
        $hit = $false
        foreach ($l in $lines) { if ($l.StartsWith($key)) { $hit = $true } }
        if (-not $hit) { $missing += $key.TrimEnd(':') }
    }
    $detail = 'MUTATION IN PROGRESS - ' + $quoted
    if ($missing.Count -gt 0) { $detail = $detail + ' [missing: ' + ($missing -join ', ') + ']' }
    $detail = $detail + ' - run: powershell -NoProfile -File scripts/gate/restore.ps1'

    Add-Result 'MUT' 'No in-place mutation in progress' 'fail' $detail
}

# Advisory only. A backup directory with no sentinel means one of two things: the
# restore was interrupted between deleting the sentinel and the backups, or someone
# deleted the sentinel by hand, which restore.ps1 is written never to do. Either
# way the tree deserves a look, and either way this is not the criterion above.
if ((Test-Path -LiteralPath $backupDir) -and -not (Test-Path -LiteralPath $sentinel)) {
    Write-Host '  NOTE  .mutation-backup/ exists without a sentinel - restore residue, inspect before committing'
}

Complete-Gate 'mutation check'
