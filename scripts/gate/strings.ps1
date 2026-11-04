#requires -Version 5.1
# G4.4 — no hardcoded player-facing strings.
#
# Heuristic on purpose, and honest about it: it flags string literals assigned to
# UI text properties in .gd and .tscn files. A string built at runtime from parts
# will escape it, which is why G4.4 is checked alongside a human read of the UI.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G4 - player-facing strings'

$scenes = @(Get-ChildItem (Join-Path $StudioRoot 'scenes') -Recurse -Filter '*.tscn' -File -ErrorAction SilentlyContinue)
$uiScenes = @($scenes | Where-Object { $_.FullName -match '\\ui\\' })
$code = @(Get-ChildItem (Join-Path $StudioRoot 'src') -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue)

if ($uiScenes.Count -eq 0 -and $code.Count -eq 0) {
    Add-Result 'G4.4' 'UI exists to check' 'blocked' 'no scenes/ui or src code yet'
    Complete-Gate 'G4 strings'
}

$hits = @()

foreach ($f in $code) {
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\.(text|placeholder_text|tooltip_text)\s*=\s*"[^"]+"') {
            $hits += ($f.Name + ':' + ($i + 1))
        }
    }
}

foreach ($f in $scenes) {
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(text|placeholder_text|tooltip_text)\s*=\s*"[^"]+"') {
            $hits += ($f.Name + ':' + ($i + 1))
        }
    }
}

if ($hits.Count -eq 0) {
    Add-Result 'G4.4' 'No hardcoded player-facing strings' 'pass' ($code.Count.ToString() + ' scripts, ' + $scenes.Count.ToString() + ' scenes scanned')
} else {
    Add-Result 'G4.4' 'No hardcoded player-facing strings' 'fail' ($hits.Count.ToString() + ' literals, e.g. ' + (($hits | Select-Object -First 6) -join ', '))
}

$table = Join-Path $StudioRoot 'assets\i18n\strings.csv'
if (Test-Path $table) {
    Add-Result 'G4.4.t' 'String table exists' 'pass' 'assets/i18n/strings.csv'
} else {
    Add-Result 'G4.4.t' 'String table exists' 'blocked' 'assets/i18n/strings.csv not created - required at G4'
}

Complete-Gate 'G4 strings'
