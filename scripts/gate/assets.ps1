#requires -Version 5.1
# G2.4, G2.5 — asset manifest integrity and palette conformance.
#
# Manifest schema: docs/ASSETS.md
#
# param() must be the first statement in a script. Placing it after the
# dot-sourcing below makes PowerShell treat it as a command: the switch is never
# bound and the script prints a "param is not recognized" error on every run.
param([switch]$PlaceholdersForbidden)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G2 - assets'

$manifestPath = Join-Path $ArtDir 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    Add-Result 'G2.4' 'Asset manifest exists' 'blocked' 'art/manifest.json missing'
    Complete-Gate 'G2 assets'
}

try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json }
catch {
    Add-Result 'G2.4' 'Asset manifest parses' 'fail' $_.Exception.Message
    Complete-Gate 'G2 assets'
}

$assets = @()
if ($manifest.PSObject.Properties.Name -contains 'assets') { $assets = @($manifest.assets) }
if ($assets.Count -eq 0) {
    Add-Result 'G2.4' 'Manifest has entries' 'blocked' 'no assets declared yet'
    Complete-Gate 'G2 assets'
}

$missingFile = @()
$missingFrame = @()
$badSize = @()
$placeholders = @()
$checked = 0

foreach ($a in $assets) {
    $checked++
    foreach ($field in @('id', 'file')) {
        if (-not ($a.PSObject.Properties.Name -contains $field) -or [string]::IsNullOrEmpty($a.$field)) {
            $missingFile += ('entry without ' + $field)
        }
    }
    if ($a.PSObject.Properties.Name -contains 'placeholder' -and $a.placeholder -eq $true) {
        $placeholders += $a.id
    }

    $file = [string]$a.file
    if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path $StudioRoot $file }
    if (-not (Test-Path $file)) { $missingFile += $a.file; continue }

    if ($a.PSObject.Properties.Name -contains 'width' -and $a.PSObject.Properties.Name -contains 'height') {
        $size = Get-PngSize $file
        if ($size) {
            if ($size.Width -ne $a.width -or $size.Height -ne $a.height) {
                $badSize += ($a.id + ' declared ' + $a.width + 'x' + $a.height + ', actual ' + $size.Width + 'x' + $size.Height)
            }
        } else {
            $badSize += ($a.id + ' is not a readable PNG')
        }
    }

    # `frames` is either a list of frame files or a count of frames inside `file`.
    # A count is not a path: treating it as one produced "3 missing, e.g. 1".
    if ($a.PSObject.Properties.Name -contains 'frames') {
        $framesValue = $a.frames
        if ($framesValue -is [string]) {
            $fp = [string]$framesValue
            if (-not [System.IO.Path]::IsPathRooted($fp)) { $fp = Join-Path $StudioRoot $fp }
            if (-not (Test-Path $fp)) { $missingFrame += $framesValue }
        } elseif ($framesValue -is [System.Array]) {
            foreach ($framepath in $framesValue) {
                if ($framepath -isnot [string]) { continue }
                $fp = [string]$framepath
                if (-not [System.IO.Path]::IsPathRooted($fp)) { $fp = Join-Path $StudioRoot $fp }
                if (-not (Test-Path $fp)) { $missingFrame += $framepath }
            }
        }
    }
}

if ($missingFile.Count -eq 0) {
    Add-Result 'G2.4' 'Every manifest entry has its file' 'pass' ($checked.ToString() + ' assets')
} else {
    Add-Result 'G2.4' 'Every manifest entry has its file' 'fail' (($missingFile | Select-Object -First 6) -join '; ')
}
if ($missingFrame.Count -eq 0) {
    Add-Result 'G2.4.f' 'Every declared frame exists' 'pass' ''
} else {
    Add-Result 'G2.4.f' 'Every declared frame exists' 'fail' ($missingFrame.Count.ToString() + ' missing, e.g. ' + ($missingFrame[0]))
}
if ($badSize.Count -eq 0) {
    Add-Result 'G2.4.s' 'Declared sizes match the files' 'pass' ''
} else {
    Add-Result 'G2.4.s' 'Declared sizes match the files' 'fail' (($badSize | Select-Object -First 4) -join '; ')
}

if ($PlaceholdersForbidden) {
    if ($placeholders.Count -eq 0) {
        Add-Result 'G4.8' 'No placeholders marked as final' 'pass' ''
    } else {
        Add-Result 'G4.8' 'No placeholders marked as final' 'fail' ($placeholders -join ', ')
    }
}

# Palette conformance: compare every visible pixel against the palette declared
# in art/STYLE.md. Tolerance is exact - a near-miss colour is still drift.
$stylePath = Join-Path $ArtDir 'STYLE.md'
$style = Read-Text $stylePath
$palette = @()
if ($style) {
    $row = ($style -split "`n") | Where-Object { $_ -match '^\s*\|\s*Palette\s*\|' } | Select-Object -First 1
    if ($row) {
        foreach ($m in [regex]::Matches($row, '#([0-9A-Fa-f]{6})')) { $palette += $m.Groups[1].Value.ToUpper() }
    }
}

if ($palette.Count -lt 3) {
    Add-Result 'G2.5' 'Sprite palette matches the style guide' 'blocked' 'no concrete palette in art/STYLE.md'
} else {
    Add-Type -AssemblyName System.Drawing
    $offenders = @()
    $scannedImages = 0
    $rawSkipped = @()
    foreach ($a in $assets) {
        if (-not ($a.PSObject.Properties.Name -contains 'file')) { continue }
        if ($a.file -notmatch '\.png$') { continue }
        # The one exempt entry is the unmodified generator dump, `status` =
        # 'raw-evidence'. It exists to document the pre-snap colour set, so it is
        # off-palette by definition and scanning it could only ever fail.
        # Placeholders are scanned: exempting them made G2.5 green while a single
        # image was seen (L-031). Do not key this on `placeholder` again.
        $status = ''
        if ($a.PSObject.Properties.Name -contains 'status') { $status = [string]$a.status }
        if ($status -eq 'raw-evidence') { $rawSkipped += [string]$a.id; continue }
        $file = [string]$a.file
        if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path $StudioRoot $file }
        if (-not (Test-Path $file)) { continue }
        $size = Get-PngSize $file
        if (-not $size) { continue }
        if ($size.Width -gt 512 -or $size.Height -gt 512) { continue }
        # Counted only once the bitmap is actually open: an unreadable file is
        # not scanned, and a count that includes it understates the hole.
        try { $bmp = [System.Drawing.Bitmap]::FromFile($file) } catch { continue }
        $scannedImages++
        $bad = New-Object 'System.Collections.Generic.HashSet[string]'
        for ($y = 0; $y -lt $bmp.Height; $y++) {
            for ($x = 0; $x -lt $bmp.Width; $x++) {
                $px = $bmp.GetPixel($x, $y)
                if ($px.A -eq 0) { continue }
                $hex = ('{0:X2}{1:X2}{2:X2}' -f $px.R, $px.G, $px.B)
                if ($palette -notcontains $hex) { [void]$bad.Add('#' + $hex) }
            }
        }
        $bmp.Dispose()
        if ($bad.Count -gt 0) {
            $sample = @($bad) | Select-Object -First 3
            $offenders += ($a.id + ': ' + ($sample -join ','))
        }
    }
    # The count and the exempt list are printed so an exemption is never silent.
    $scannedDetail = $scannedImages.ToString() + ' images within palette'
    if ($rawSkipped.Count -gt 0) {
        $scannedDetail = $scannedDetail + '; skipped raw-evidence: ' + ((@($rawSkipped) | Sort-Object) -join ', ')
    }

    if ($scannedImages -eq 0) {
        Add-Result 'G2.5' 'Sprite palette matches the style guide' 'blocked' 'no scannable PNG assets'
    } elseif ($offenders.Count -eq 0) {
        Add-Result 'G2.5' 'Sprite palette matches the style guide' 'pass' $scannedDetail
    } else {
        Add-Result 'G2.5' 'Sprite palette matches the style guide' 'fail' ($offenders -join '; ')
    }
}

Complete-Gate 'G2 assets'
