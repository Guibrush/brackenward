# Shared configuration for gate scripts. Dot-source after common.ps1.
#
# Nothing here hardcodes the project path. $StudioRoot is derived from this
# file's location, so the folder can be renamed at G1 without breaking a script.

$StudioRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$DocsDir    = Join-Path $StudioRoot 'docs'
$ArtDir     = Join-Path $StudioRoot 'art'
$AssetsDir  = Join-Path $StudioRoot 'assets'
$GodotBase  = Join-Path $env:LOCALAPPDATA 'Programs\Godot'

# Minimum loudness tolerance, in LU, when checking an audio file against its spec.
$LoudnessTolerance = 2.0
# Peak ceiling in dBTP.
$PeakCeiling = -1.0

function Get-GodotConsole {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }

    if (Test-Path $GodotBase) {
        $dirs = Get-ChildItem $GodotBase -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = { try { [version]$_.Name } catch { [version]'0.0.0' } } } -Descending
        foreach ($d in $dirs) {
            $exe = Get-ChildItem $d.FullName -Filter '*_console.exe' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }

    foreach ($name in @('godot_console.exe', 'godot.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Get-GodotVersionString {
    param([string]$Bin)
    if (-not $Bin) { return $null }
    $out = & $Bin --version 2>&1 | Out-String
    $line = ($out -split "`n" | Where-Object { $_ -match '^\d+\.\d+' } | Select-Object -First 1)
    if (-not $line) { return $null }
    return $line.Trim()
}

# "4.7.2.stable.official.ed1daf0bf" -> "4.7.2"
function ConvertTo-ShortVersion {
    param([string]$Version)
    if ([string]::IsNullOrEmpty($Version)) { return $null }
    $m = [regex]::Match($Version, '^(\d+\.\d+\.\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Git may be installed but absent from the PATH of a long-running process.
# Resolve it explicitly rather than assuming the environment is current (L-001).
function Get-GitPath {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Git\cmd\git.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe') }
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-FfmpegPath {    foreach ($name in @('ffmpeg.exe', 'ffmpeg')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $pkg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $pkg) {
        $exe = Get-ChildItem $pkg -Filter 'ffmpeg.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Get-FfprobePath {
    foreach ($name in @('ffprobe.exe', 'ffprobe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $pkg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $pkg) {
        $exe = Get-ChildItem $pkg -Filter 'ffprobe.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
