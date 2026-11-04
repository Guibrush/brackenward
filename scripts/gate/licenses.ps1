#requires -Version 5.1
# G5.4 — every third-party asset, model and library has its licence recorded.
#
# Two sources of truth:
#   docs/LICENSES.md        human-readable record, one row per dependency
#   manifest `license` field, present on every generated asset entry
# Both are required: the doc is what you can hand to a store, the manifest field
# is what makes the check mechanical.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G5 - licences'

$licPath = Join-Path $DocsDir 'LICENSES.md'
if (-not (Test-Path $licPath)) {
    Add-Result 'G5.4' 'Licence record exists' 'blocked' 'docs/LICENSES.md missing - required at G5'
    Complete-Gate 'G5 licences'
}

$lic = Read-Text $licPath
if ($lic -match '\bTODO\b') {
    Add-Result 'G5.4' 'Licence record is complete' 'fail' 'TODO markers remain'
} else {
    Add-Result 'G5.4' 'Licence record is complete' 'pass' ''
}

$manifests = @(
    (Join-Path $ArtDir 'manifest.json'),
    (Join-Path $StudioRoot 'audio\manifest.json')
)
$entries = @()
foreach ($mp in $manifests) {
    if (-not (Test-Path $mp)) { continue }
    try { $m = Get-Content $mp -Raw | ConvertFrom-Json } catch { continue }
    foreach ($prop in @('assets', 'entries')) {
        if ($m.PSObject.Properties.Name -contains $prop) { $entries += @($m.$prop) }
    }
}

if ($entries.Count -eq 0) {
    Add-Result 'G5.4.m' 'Every generated asset records its licence' 'blocked' 'no manifest entries yet'
} else {
    $missing = @()
    foreach ($e in $entries) {
        if (-not ($e.PSObject.Properties.Name -contains 'license') -or [string]::IsNullOrEmpty($e.license)) {
            $missing += [string]$e.id
        }
    }
    if ($missing.Count -eq 0) {
        Add-Result 'G5.4.m' 'Every generated asset records its licence' 'pass' ($entries.Count.ToString() + ' entries')
    } else {
        Add-Result 'G5.4.m' 'Every generated asset records its licence' 'fail' ($missing.Count.ToString() + ' without a licence, e.g. ' + (($missing | Select-Object -First 5) -join ', '))
    }
}

Complete-Gate 'G5 licences'
