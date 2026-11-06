#requires -Version 5.1
# T-0030 - prove a gate fails, without ever writing to the real tree.
#
# A failure demonstration used to be "edit the tree, run the gate, put it back".
# Twice in one day the agent that was going to put it back ran out of steps first,
# so a tree headed for a commit carried a deliberately broken file. This script
# takes the promise out of the process: it copies the project to a temp directory,
# applies a named mutation *inside the copy only*, runs the named gate *from the
# copy*, and deletes the copy in `finally`. The real tree is never written to, and
# that claim is checked rather than asserted - the SHA-256 of every mutated path is
# printed before and after.
#
# Four separations make it hard to get wrong:
#
#   1. Mutations are a registry in this file, not callbacks, so every demonstration
#      is reviewable at once, together with the gate it belongs to and the text the
#      gate's output must contain to count as naming the defect.
#   2. Every mutated path is resolved through Get-CopyPath, which refuses anything
#      outside the copy. No code path in this file can name a real-tree file.
#   3. The copy's own gate.config.ps1 is asked where it thinks the project is, by
#      running it the way a gate does. If the answer is not the copy the run stops
#      before the gate starts: a gate that reads the real tree would pass on an
#      unmutated project and "prove" nothing.
#   4. The copy is removed in `finally`, which runs on a thrown error and on Ctrl-C,
#      and its absence is verified, not assumed.
#
# If the copy cannot be made this fails and says so. It never falls back to editing
# the tree: a broken demonstration is cheaper than a mutated repository, and a
# script that silently degrades into the thing it was written to replace is worse
# than no script.
#
# Exit codes - this is a tool, not a gate, so its contract is its own:
#   0  the gate exited with the expected code inside the copy, the copy's gates
#      resolved the copy as their root, the expected defect text appeared, the copy
#      is gone, and the real tree's hashes are unchanged
#   1  the demonstration is not evidence: the copy failed, the gate script does not
#      exist, the gate and mutation do not belong together, the exit code was wrong,
#      the root check failed, the defect was not named, cleanup failed, or the real
#      tree changed
#   3  blocked before anything was copied: an unknown -Case, a temp root that
#      overlaps the tree, or a real-tree path the mutation needs is missing
#
#   powershell -NoProfile -File scripts/gate/prove-failure.ps1 -Gate assets -Case off-palette-pixel
#   powershell -NoProfile -File scripts/gate/prove-failure.ps1 -Gate tests  -Case assertion-2x-damage
#   powershell -NoProfile -File scripts/gate/prove-failure.ps1 -Gate smoke  -Case despawn-disabled
param(
    # The gate file to run, by bare name: `assets` runs <copy>\scripts\gate\assets.ps1.
    [Parameter(Mandatory = $true)][string]$Gate,

    # A key of the mutation registry below. Not a script block, not a path.
    [Parameter(Mandatory = $true)][string]$Case,

    # The exit code the demonstration claims. Default 1 (fail). An unexpected code
    # is a failed demonstration, never a shrug.
    [int]$ExpectExit = 1,

    # Where the copy is made. Defaults to %TEMP%. Point it at a path that does not
    # exist to see the whole directory come and go.
    [string]$TempRoot = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

# This script's own location is the only thing it trusts about the real tree.
$RealRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')

# Arguments a gate needs to be measurable inside a copy. Applied to the copy only,
# and only here: smoke's criterion is 300 s, which would make every despawn
# demonstration cost five minutes, while its own -Duration flag exists for probes
# and still fails the duration check, so a short run can never be mistaken for a
# pass. 20 s is five arrivals at the arena's 3 s spawn interval, the first at ~4 s.
$GateExtraArgs = @{
    'smoke' = @('-Duration', '20')
}

# Gates that start the engine need the copy's import cache built before they run.
# `.godot/` is excluded from the copy (it is derived state, and the brief excludes
# it), and without it scripts/tests/cases cannot resolve scripts/tests/lib/suite.gd:
# the suite fails with a parse error that has nothing to do with the mutation. The
# import is preparation, never evidence - `--import` exits 0 even on a parse error
# (L-033), so its exit code gates the run and is not reported as a result.
#
# A new engine gate must be added here. If one is not, its demonstration fails the
# named-defect check below rather than passing quietly, which is why that check
# insists on the text and not only on the exit code.
$GateImportFirst = @('tests', 'smoke')

# The registry.
#
# `Paths` lists every file `Apply` writes - it is what the real tree's hashes are
# taken of, so a mutation that forgets a path makes the "unchanged" check weaker
# than it looks. `Expect` is what the gate's output must contain: the exit code
# alone is not a naming (L-035), and a gate that failed for some unrelated reason
# must not be accepted as this demonstration.
#
# Every Apply resolves its target through Get-CopyPath, which is bound to the run's
# copy and refuses anything else.
$Cases = [ordered]@{
    'off-palette-pixel' = @{
        Description = 'one visible pixel of assets/art/towers/arrow/idle/south.png set to #FF00FF'
        Gates       = @('assets')
        Paths       = @('assets\art\towers\arrow\idle\south.png')
        Expect      = @('\[FAIL\s*\] G2\.5', '#FF00FF')
        Apply       = {
            $path = Get-CopyPath 'assets\art\towers\arrow\idle\south.png'
            $px = Set-VisiblePixel -Path $path -R 255 -G 0 -B 255
            return ('pixel (' + $px.X + ',' + $px.Y + ') ' + $px.Old + ' -> #FF00FF')
        }
    }

    'assertion-2x-damage' = @{
        Description = 'scripts/tests/cases/leak_damage.gd expects twice damage_per_leak'
        Gates       = @('tests')
        Paths       = @('scripts\tests\cases\leak_damage.gd')
        Expect      = @('\[FAIL\s*\] G2\.9', 'a leak applies exactly damage_per_leak health')
        Apply       = {
            $path = Get-CopyPath 'scripts\tests\cases\leak_damage.gd'
            $line = Replace-Once -Path $path `
                -Pattern 'check_eq_int\(before - after, per_leak,' `
                -Replacement 'check_eq_int(before - after, per_leak * 2,' `
                -What 'expect twice damage_per_leak'
            return ('line ' + $line + ': one leak now expects per_leak * 2')
        }
    }

    'despawn-disabled' = @{
        Description = 'src/gameplay/lane_walker.gd: the _despawn() body becomes pass'
        Gates       = @('smoke')
        Paths       = @('src\gameplay\lane_walker.gd')
        Expect      = @('\[FAIL\s*\] G2\.1\.3', 'stuck [1-9]')
        Apply       = {
            $path = Get-CopyPath 'src\gameplay\lane_walker.gd'
            $line = Replace-Once -Path $path `
                -Pattern '(?m)(^func _despawn\(\) -> void:\r?\n)([ \t]+)queue_free\(\)' `
                -Replacement '${1}${2}pass' `
                -What 'disable the despawn handler'
            return ('line ' + $line + ': queue_free() -> pass inside _despawn()')
        }
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The only way a mutation is allowed to name a file. A path outside the copy is a
# refusal, not a warning: this is the one guard that makes "the script wrote to the
# real tree" impossible rather than merely unlikely.
function Get-CopyPath {
    param([Parameter(Mandatory = $true)][string]$Relative)
    if (-not $script:CopyRoot) { throw 'Get-CopyPath was called before a copy existed' }
    $rootFull = [System.IO.Path]::GetFullPath($script:CopyRoot).TrimEnd('\')
    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
    if (-not $full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ('refusing to touch ' + $full + ': it is not inside the copy at ' + $rootFull)
    }
    return $full
}

function Test-SamePath {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrEmpty($A) -or [string]::IsNullOrEmpty($B)) { return $false }
    $a = [System.IO.Path]::GetFullPath($A).TrimEnd('\')
    $b = [System.IO.Path]::GetFullPath($B).TrimEnd('\')
    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

# Copies every file under Source except the excluded directories and files. Writes
# nothing anywhere else, and returns the number of files copied.
#
# -Force so dot-files (.gitignore, .github) are seen: they are part of the tree the
# gates read, and a copy without them is not the project. The directories that must
# not be copied are filtered by name before any write happens, which is also why
# this walks the tree itself instead of asking robocopy to do both jobs.
function Copy-ProjectTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )
    $src = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $src -Recurse -File -Force)) {
        if ($ExcludeFiles -contains $file.Name) { continue }
        $rel = $file.FullName.Substring($src.Length + 1)
        $parts = $rel.Split('\')
        $skip = $false
        # Directory segments only: the file's own name is the last element.
        for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
            if ($ExcludeDirs -contains $parts[$i]) { $skip = $true; break }
        }
        if ($skip) { continue }

        $dest = Join-Path $Destination $rel
        $parent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        [System.IO.File]::Copy($file.FullName, $dest, $true)
        $count++
    }
    return $count
}

# Replaces exactly one occurrence of Pattern in a copied file and returns the line
# number it changed. Zero or two matches means the file is no longer the file the
# mutation was written against, and the demonstration would be measuring something
# else, so it stops instead of guessing.
function Replace-Once {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$What
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw ('cannot apply "' + $What + '": ' + $Path + ' is missing from the copy')
    }
    $text = [System.IO.File]::ReadAllText($Path)
    $found = [regex]::Matches($text, $Pattern)
    if ($found.Count -ne 1) {
        throw ('cannot apply "' + $What + '": expected 1 match of /' + $Pattern + '/ in ' +
            (Split-Path $Path -Leaf) + ', found ' + $found.Count)
    }
    $line = @($text.Substring(0, $found[0].Index) -split "`n").Count
    $updated = [regex]::Replace($text, $Pattern, $Replacement)
    # Re-encoded without a BOM: the copy must differ from the real tree by the
    # mutation and nothing else, or a later diff of this demo is unreadable.
    [System.IO.File]::WriteAllText($Path, $updated, (New-Object System.Text.UTF8Encoding($false)))
    return $line
}

# Sets the top-left-most visible pixel to the given colour and reports what was
# there. Row-major from the origin, so the same file always yields the same pixel.
function Set-VisiblePixel {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$R,
        [Parameter(Mandatory = $true)][int]$G,
        [Parameter(Mandatory = $true)][int]$B
    )
    Add-Type -AssemblyName System.Drawing
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # Loaded from memory and saved to memory: a Bitmap opened with FromFile holds
    # the file open and refuses to save over it, and this runs on the file itself.
    $in = New-Object System.IO.MemoryStream
    [void]$in.Write($bytes, 0, $bytes.Length)
    $in.Position = 0
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $in
    try {
        $x = -1
        $y = -1
        $old = ''
        for ($row = 0; $row -lt $bmp.Height -and $y -lt 0; $row++) {
            for ($col = 0; $col -lt $bmp.Width; $col++) {
                $px = $bmp.GetPixel($col, $row)
                if ($px.A -gt 0) {
                    $x = $col
                    $y = $row
                    $old = ('#{0:X2}{1:X2}{2:X2}' -f $px.R, $px.G, $px.B)
                    break
                }
            }
        }
        if ($y -lt 0) {
            throw ('cannot apply the off-palette pixel: ' + (Split-Path $Path -Leaf) + ' has no visible pixel')
        }
        $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $R, $G, $B))
        $out = New-Object System.IO.MemoryStream
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::WriteAllBytes($Path, $out.ToArray())
        $out.Dispose()
    } finally {
        $bmp.Dispose()
        $in.Dispose()
    }
    return [pscustomobject]@{ X = $x; Y = $y; Old = $old }
}

# Asks the copy where its gates think the project is. The probe is written into the
# copy's scripts/gate and dot-sources that copy's own gate.config.ps1, which is
# exactly what assets.ps1, tests.ps1 and smoke.ps1 do on their second line - so the
# answer is the root the gate will get, not an inference about it. The probe file is
# removed before the gate runs, so the gate sees the copied tree plus the mutation
# and nothing else.
function Resolve-CopyStudioRoot {
    param([Parameter(Mandatory = $true)][string]$Copy)
    $probe = Join-Path $Copy 'scripts\gate\prove-failure-root-probe.ps1'
    $body = @(
        '# Written by scripts/gate/prove-failure.ps1 into a throwaway copy, run, then',
        '# deleted again. It prints the root the gates in this copy resolve, using the',
        '# same dot-source line they use.',
        '. (Join-Path $PSScriptRoot ''gate.config.ps1'')',
        'Write-Output (''STUDIO_ROOT='' + $StudioRoot)'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($probe, $body + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    try {
        $r = Invoke-Native -Exe 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probe)
    } finally {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force }
    }
    $line = @(($r.Output -split "`n") | Where-Object { $_ -match '^STUDIO_ROOT=' })[0]
    if ($r.ExitCode -ne 0 -or -not $line) {
        $tail = (@(($r.Output -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 3) -join ' | ')
        throw ('could not read the root the copy''s gates resolve (probe exit ' + $r.ExitCode + '): ' + $tail)
    }
    return (($line -replace '^STUDIO_ROOT=', '').Trim())
}

# Fills a hashtable with SHA-256 per path. Takes the hashtable rather than returning
# one: a dictionary returned from a function is an object of ambiguous shape once it
# passes through the pipeline, and a hash table that quietly unrolls compares every
# key to null and reports "unchanged" for the wrong reason.
function Fill-TreeHashes {
    param(
        [Parameter(Mandatory = $true)]$Hashes,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [Parameter(Mandatory = $true)][string]$Root
    )
    foreach ($rel in $RelativePaths) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $path)) { throw ('missing from the real tree: ' + ($rel -replace '\\', '/')) }
        $Hashes[$rel] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}

function Write-Hashes {
    param($Hashes, [string[]]$RelativePaths, [string]$Label)
    foreach ($rel in $RelativePaths) {
        $shown = ($rel -replace '\\', '/')
        Write-Host ('  ' + $Label.PadRight(7) + $shown.PadRight(46) + $Hashes[$rel])
    }
}

# Asks the gates' own config which Godot console executable this machine has.
#
# The dot-source has to happen *inside* a function. Dot-sourcing a file assigns into
# the calling scope, so doing it at script scope would put gate.config.ps1's
# $StudioRoot - the real tree - into this script, where every guard in the run is
# written against $RealRoot. Inside a function those variables land in the function's
# scope and are discarded when it returns, so only the answer comes back out.
#
# This resolves a machine-level fact, not a copy-level one: the copy and the real tree
# are the same machine, so this is deliberately the real gate.config.ps1 and not the
# copy's. The copy's own config is still the authority on the copy's root, and is
# asked separately in Resolve-CopyStudioRoot.
function Resolve-GodotConsole {
    . (Join-Path $PSScriptRoot 'gate.config.ps1')
    return (Get-GodotConsole)
}

# ---------------------------------------------------------------------------
# Preconditions - nothing is copied until the request makes sense
# ---------------------------------------------------------------------------

Write-Host 'prove-failure: a gate failing inside a throwaway copy of the project'
Write-Host ''

if (-not $Cases.Contains($Case)) {
    Write-Host ('  [ERROR] no mutation named "' + $Case + '" in the registry of ' + $PSScriptRoot + '\prove-failure.ps1')
    Write-Host ('  known cases: ' + (@($Cases.Keys) -join ', '))
    Write-Host 'prove-failure: blocked, nothing to demonstrate'
    exit 3
}
$entry = $Cases[$Case]

$gateRel = 'scripts\gate\' + $Gate + '.ps1'
foreach ($rel in $entry.Paths) {
    if (-not (Test-Path -LiteralPath (Join-Path $RealRoot $rel))) {
        Write-Host ('  [ERROR] the mutation needs ' + ($rel -replace '\\', '/') + ', which is not in the real tree')
        Write-Host 'prove-failure: blocked, the demonstration has no subject'
        exit 3
    }
}

if ([string]::IsNullOrWhiteSpace($TempRoot)) { $TempRoot = $env:TEMP }
if ([string]::IsNullOrWhiteSpace($TempRoot)) {
    Write-Host '  [ERROR] no temp directory: pass -TempRoot'
    Write-Host 'prove-failure: blocked, nowhere to copy to'
    exit 3
}

$TempRoot = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\')
if ($TempRoot.StartsWith($RealRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $RealRoot.StartsWith($TempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ('  [ERROR] the temp root ' + $TempRoot + ' overlaps the real tree ' + $RealRoot)
    Write-Host 'prove-failure: blocked, a copy there would be inside the tree it must not touch'
    exit 3
}

# Deterministic name: same gate and case, same path. A leftover from a crashed run is
# removed and reported rather than copied over, and concurrency is excluded by the
# studio's one-writer rule, not by randomness that would make output unrepeatable.
$safeGate = $Gate -replace '[^A-Za-z0-9._-]', '-'
$safeCase = $Case -replace '[^A-Za-z0-9._-]', '-'
$CopyRoot = Join-Path $TempRoot ('brackenward-prove-failure-' + $safeGate + '-' + $safeCase)

$tempRootCreated = $false
$beforeHashes = [ordered]@{}
$godotBin = $null

# An engine gate is asked for its engine before anything is copied. A missing Godot is
# blocked (3), not failed (1): nothing was measured, so nothing is known about the
# mutation. Resolving it here also means the copy's import cannot fail halfway with a
# copy already on disk for a reason that has nothing to do with the demonstration.
if ($GateImportFirst -contains $Gate) {
    $godotBin = Resolve-GodotConsole
    if (-not $godotBin) {
        Write-Host ('  [ERROR] -Gate ' + $Gate + ' starts the engine and Get-GodotConsole found no Godot console executable')
        Write-Host '  nothing was copied and nothing was demonstrated'
        Write-Host 'prove-failure: blocked, the engine gate has no engine'
        exit 3
    }
}

$exitCode = 1

try {
    Write-Host ('  real tree:  ' + $RealRoot)
    Write-Host ('  copy root:  ' + $CopyRoot)
    Write-Host ('  mutation:   ' + $Case + ' - ' + $entry.Description)
    Write-Host ('  gate:       ' + $gateRel + ' (expects exit ' + $ExpectExit + ')')
    if ($godotBin) { Write-Host ('  engine:     ' + $godotBin) }
    Write-Host ''
    Write-Host '  real tree SHA-256, before:'
    Fill-TreeHashes -Hashes $beforeHashes -RelativePaths $entry.Paths -Root $RealRoot
    Write-Hashes -Hashes $beforeHashes -RelativePaths $entry.Paths -Label 'before'
    Write-Host ''

    if (Test-Path -LiteralPath $TempRoot) {
        Write-Host ('  temp root:  ' + $TempRoot + ' (pre-existing, left alone)')
    } else {
        [void](New-Item -ItemType Directory -Path $TempRoot -Force)
        $tempRootCreated = $true
        Write-Host ('  temp root:  ' + $TempRoot + ' (created by this run)')
    }

    if (Test-Path -LiteralPath $CopyRoot) {
        Write-Host ('  stale copy from an earlier run at ' + $CopyRoot + ' - removing it')
        Remove-Item -LiteralPath $CopyRoot -Recurse -Force
        if (Test-Path -LiteralPath $CopyRoot) { throw ('could not remove the stale copy at ' + $CopyRoot) }
    }

    New-Item -ItemType Directory -Path $CopyRoot -Force | Out-Null
    $copied = Copy-ProjectTree -Source $RealRoot -Destination $CopyRoot `
        -ExcludeDirs @('.git', '.godot', '.mutation-backup') `
        -ExcludeFiles @('.mutation-active')
    if ($copied -le 0) { throw ('the copy at ' + $CopyRoot + ' contains no files - copying the project failed') }
    Write-Host ('  copied:     ' + $copied + ' files (excluded: .git, .godot, .mutation-backup, .mutation-active)')

    $gateInCopy = Join-Path $CopyRoot $gateRel
    if (-not (Test-Path -LiteralPath $gateInCopy)) {
        throw ('the gate script does not exist in the copy: ' + $gateRel + ' - nothing was demonstrated')
    }

    # The pair is checked once the copy exists, not before it. A demonstration whose
    # gate and mutation do not belong together cannot prove anything, and this is
    # also the kind of refusal that must leave no copy behind - so it happens on the
    # path that has one to clean up, not on the cheap one that does not.
    if ($entry.Gates -notcontains $Gate) {
        throw ('"' + $Case + '" is a demonstration for -Gate ' + (@($entry.Gates) -join ' or ') + ', not -Gate ' + $Gate)
    }

    $resolved = Resolve-CopyStudioRoot -Copy $CopyRoot
    Write-Host ('  resolved:   $StudioRoot = ' + $resolved)
    if (Test-SamePath $resolved $RealRoot) {
        throw ('$StudioRoot resolved to the real tree (' + $RealRoot + ') - refusing to run: the gate would read an unmutated project')
    }
    if (-not (Test-SamePath $resolved $CopyRoot)) {
        throw ('$StudioRoot resolved to ' + $resolved + ', not the copy at ' + $CopyRoot + ' - refusing to run')
    }
    Write-Host ('  verified:   the gate in the copy resolves the copy, not the real tree')

    # `.godot/` is excluded from the copy, so the first engine run inside it has no
    # import cache: a test case cannot resolve res://scripts/tests/lib/suite.gd and the
    # suite fails with a parse error that has nothing to do with the mutation. Build the
    # cache first, in the copy, before anything is mutated.
    #
    # The exit code gates the run but is not a result: `--import` exits 0 even on a
    # parse error (L-033), so a zero here proves only that preparation happened. What
    # the gate then does with the mutated tree is the evidence, and the named-defect
    # check below is what refuses a gate that failed for the wrong reason.
    if ($GateImportFirst -contains $Gate) {
        $importRun = Invoke-Native -Exe $godotBin -Arguments @('--headless', '--path', $CopyRoot, '--import')
        Write-Host ('  import:     --headless --path <copy> --import exited ' + $importRun.ExitCode + ' (preparation only, not evidence)')
        if ($importRun.ExitCode -ne 0) {
            $tail = (@(($importRun.Output -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 4) -join ' | ')
            throw ('the copy''s import failed (exit ' + $importRun.ExitCode + ') before the mutation was applied: ' + $tail)
        }
        if (-not (Test-Path -LiteralPath (Join-Path $CopyRoot '.godot'))) {
            throw ('the copy''s import reported success but ' + (Join-Path $CopyRoot '.godot') + ' was not created')
        }
    }

    $detail = & $entry.Apply
    Write-Host ('  applied:    ' + $detail)

    $gateArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gateInCopy)
    if ($GateExtraArgs.ContainsKey($Gate)) {
        $gateArgs += $GateExtraArgs[$Gate]
        Write-Host ('  gate args:  ' + ($GateExtraArgs[$Gate] -join ' ') + ' - copy only; the real criterion is unchanged')
    }

    Write-Host ''
    $run = Invoke-Native -Exe 'powershell' -Arguments $gateArgs
    $lines = @($run.Output -split "`n" | Where-Object { $_.Trim() -ne '' })

    Write-Host ('  gate exit:  ' + $run.ExitCode)
    if ($lines.Count -eq 0) {
        Write-Host '  | (the gate printed nothing)'
    } else {
        foreach ($line in $lines) { Write-Host ('  | ' + $line.TrimEnd()) }
    }

    $failLines = @($lines | Where-Object { $_ -match '\[FAIL\s*\]' })
    Write-Host ''
    Write-Host ('  failure lines: ' + $failLines.Count)
    foreach ($f in $failLines) { Write-Host ('  > ' + $f.Trim()) }

    if ($run.ExitCode -ne $ExpectExit) {
        throw ('expected exit ' + $ExpectExit + ', got ' + $run.ExitCode + ' - the gate did not behave as this demonstration claims')
    }
    if ($ExpectExit -ne 0 -and $failLines.Count -eq 0) {
        throw ('the gate exited ' + $ExpectExit + ' with no [FAIL] line - it failed without naming a criterion')
    }

    $unnamed = @()
    foreach ($pattern in $entry.Expect) {
        $hit = @($lines | Where-Object { [regex]::IsMatch($_, $pattern) })
        if ($hit.Count -eq 0) { $unnamed += $pattern }
    }
    if ($unnamed.Count -gt 0) {
        $shown = @($unnamed | ForEach-Object { '/' + $_ + '/' }) -join ', '
        throw ('the gate exited ' + $run.ExitCode + ' but did not name this defect: no output line matched ' + $shown)
    }
    Write-Host ('  named:      every expected failure text was found against "' + $Case + '"')

    $exitCode = 0
}
catch {
    $exitCode = 1
    Write-Host ''
    Write-Host ('  [ERROR] ' + $_.Exception.Message)
    Write-Host '  the demonstration did not complete; cleanup and the real-tree check follow'
}
finally {
    Write-Host ''
    Write-Host '  cleanup:'
    try {
        if (Test-Path -LiteralPath $CopyRoot) {
            Remove-Item -LiteralPath $CopyRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $CopyRoot) {
            throw ('the copy survived deletion at ' + $CopyRoot)
        }
        Write-Host ('  removed:    ' + $CopyRoot + ' exists=' + (Test-Path -LiteralPath $CopyRoot))
        if ($tempRootCreated) {
            if (Test-Path -LiteralPath $TempRoot) {
                $left = @(Get-ChildItem -LiteralPath $TempRoot -Force)
                if ($left.Count -eq 0) { Remove-Item -LiteralPath $TempRoot -Force }
            }
            Write-Host ('  temp root:  ' + $TempRoot + ' exists=' + (Test-Path -LiteralPath $TempRoot) + ' (created by this run)')
        }
    } catch {
        $exitCode = 1
        Write-Host ('  [ERROR] cleanup failed: ' + $_.Exception.Message)
        Write-Host ('  [ERROR] a copy survived at ' + $CopyRoot + ' - do not trust a gate run until it is removed')
    }

    Write-Host ''
    Write-Host '  real tree SHA-256, after:'
    try {
        $afterHashes = [ordered]@{}
        Fill-TreeHashes -Hashes $afterHashes -RelativePaths $entry.Paths -Root $RealRoot
        Write-Hashes -Hashes $afterHashes -RelativePaths $entry.Paths -Label 'after'
        $changed = @()
        foreach ($rel in $entry.Paths) {
            if ($beforeHashes[$rel] -ne $afterHashes[$rel]) {
                $changed += ($rel -replace '\\', '/') + ' ' + $beforeHashes[$rel] + ' -> ' + $afterHashes[$rel]
            }
        }
        if ($changed.Count -gt 0) {
            $exitCode = 1
            Write-Host ('  [ERROR] the real tree changed during the demonstration: ' + ($changed -join '; '))
        } else {
            Write-Host '  REAL TREE UNCHANGED: true'
        }
    } catch {
        $exitCode = 1
        Write-Host ('  [ERROR] could not hash the real tree after the run: ' + $_.Exception.Message)
    }
}

Write-Host ''
if ($exitCode -eq 0) {
    Write-Host ('prove-failure: proven - ' + $gateRel + ' exits ' + $ExpectExit + ' on "' + $Case + '" in a copy, and the real tree is untouched')
} else {
    Write-Host 'prove-failure: FAILED - this run is not evidence (see the [ERROR] lines above)'
}
exit $exitCode
