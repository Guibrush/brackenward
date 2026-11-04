#requires -Version 5.1
# G1.5 — the latest stable Godot release is installed.
#
# Policy: docs/adr/0001-engine-version-policy.md
# When Godot publishes a release, this check goes red. The remedy is upgrading
# the engine, never editing this script.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G1 - engine version'

$bin = Get-GodotConsole
if (-not $bin) {
    Add-Result 'G1.5' 'Godot is installed' 'blocked' 'no *_console.exe under %LOCALAPPDATA%\Programs\Godot and not on PATH'
    Complete-Gate 'G1 engine'
}

$localRaw = Get-GodotVersionString $bin
$local = ConvertTo-ShortVersion $localRaw
if (-not $local) {
    Add-Result 'G1.5' 'Godot reports a version' 'fail' ('unreadable output from ' + $bin)
    Complete-Gate 'G1 engine'
}
Write-Host ('  engine: ' + $bin)
Write-Host ('  local:  ' + $localRaw)

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Add-Result 'G1.5' 'Latest stable release known' 'blocked' 'gh not available to query the release API'
    Complete-Gate 'G1 engine'
}

$r = Invoke-Native -Exe 'gh' -Arguments @('api', 'repos/godotengine/godot/releases/latest', '--jq', '.tag_name')
if ($r.ExitCode -ne 0 -or $r.Output.Trim() -eq '') {
    # Offline or rate limited is not a version failure.
    Add-Result 'G1.5' 'Latest stable release known' 'blocked' 'could not query GitHub releases (offline or rate limited)'
    Complete-Gate 'G1 engine'
}

$latestRaw = $r.Output.Trim()
$latest = ConvertTo-ShortVersion $latestRaw
Write-Host ('  latest: ' + $latestRaw)

if (-not $latest) {
    Add-Result 'G1.5' 'Latest stable release parsed' 'blocked' ('unexpected tag format: ' + $latestRaw)
} elseif ($local -eq $latest) {
    Add-Result 'G1.5' 'Latest stable release installed' 'pass' ($local + ' matches ' + $latest)
} else {
    Add-Result 'G1.5' 'Latest stable release installed' 'fail' ('installed ' + $local + ', latest is ' + $latest + ' - upgrade the engine')
}

Complete-Gate 'G1 engine'
