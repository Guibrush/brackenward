#requires -Version 5.1
# G5.2 — a build from a clean clone reproduces byte-identical output.
#
# Blocked until an export preset exists. Method when it does:
#   1. Export twice into two empty directories from the same commit.
#   2. Compare file lists and hashes; ignore timestamps and any embedded build id
#      that the engine stamps deterministically from the same inputs.
#   3. Pass only when both trees hash identically.
#
# This is the check that catches "it built on my machine because of a stale
# cache", which is otherwise discovered by a player.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G5 - reproducible build'

$presets = Join-Path $StudioRoot 'export_presets.cfg'
if (-not (Test-Path $presets)) {
    Add-Result 'G5.2' 'Export preset exists' 'blocked' 'export_presets.cfg missing - required at G5'
    Complete-Gate 'G5 repro'
}

Add-Result 'G5.2' 'Reproducible build harness implemented' 'blocked' 'export preset present but the double-build comparison is not written yet'
Complete-Gate 'G5 repro'
