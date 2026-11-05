#requires -Version 5.1
# G2.3 - performance within budget.
#
# Measures a rendered frame, not a headless one. scripts/perf/benchmark.tscn runs
# windowed at 1920x1080 with content scale 2, vsync disabled and no frame cap,
# prints one JSON line per 60 measured frames plus an aggregate, and this script
# compares the aggregate against the budget in docs/gates/G2-vertical-slice.md:
#
#   fps_avg >= 60   and   frame_ms_p99 <= 20  (i.e. 1 % low >= 45 fps)
#
# The budget is a read-only constant here and is cross-checked against the gate
# document, so neither can drift silently. The entity count is cross-checked the
# same way: the scene declares its canonical load, and a mismatch fails instead
# of quietly moving the goalposts.
#
# Parameters
#   -Stress          run the over-budget case: identical budget, more load
#   -StressEntities  entities for -Stress (default 30000; canonical is 1000)
#   -Windows         measured 60-frame windows (default 12)
#
# Exit codes: 0 pass, 1 fail, 3 blocked (no engine, or no benchmark scene).
param(
    [switch]$Stress,
    [int]$StressEntities = 30000,
    [int]$Windows = 12
)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

# --- Budget: read-only, owned by docs/gates/G2-vertical-slice.md, G2.3 --------
$BudgetFpsAvg    = 60
$BudgetP99Ms     = 20.0
$BudgetOnePctLow = 45.0

# Declared render conditions. art/STYLE.md: a 32px board at 2x in a 1080p window.
$DeclaredWidth    = 1920
$DeclaredHeight   = 1080
$DeclaredScale    = 2.0
$WindowFrames     = 60

# The scene's canonical load; benchmark.gd asserts the same number.
$CanonicalEntities = 1000

$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Format-Num {
    param([double]$Value, [string]$Format = '0.0')
    return $Value.ToString($Format, $inv)
}

Write-Host 'G2 - performance'

# --- The script must still measure what the gate document describes ------------
$gateDoc = Read-Text (Join-Path $StudioRoot 'docs\gates\G2-vertical-slice.md')
if ($gateDoc -and ($gateDoc -match '60\s*fps average') -and ($gateDoc -match '45\s*fps')) {
    Add-Result 'G2.3c' 'Budget matches the gate document' 'pass' ('60 fps average, 45 fps 1 % low, p99 <= ' + (Format-Num $BudgetP99Ms '0.0') + ' ms')
} else {
    Add-Result 'G2.3c' 'Budget matches the gate document' 'fail' 'docs/gates/G2-vertical-slice.md no longer declares 60 fps average and 45 fps 1 % low - the script and the document disagree, so this measurement would not be the gate criterion'
}

# --- Preconditions: blocked, not failed, when nothing can be measured ---------
$bin = Get-GodotConsole
if (-not $bin) {
    Add-Result 'G2.3' 'Performance within budget' 'blocked' 'no Godot console executable - a rendered frame cannot be measured'
    Complete-Gate 'G2 performance'
}

$scene = Join-Path $StudioRoot 'scripts\perf\benchmark.tscn'
if (-not (Test-Path $scene)) {
    Add-Result 'G2.3' 'Performance within budget' 'blocked' 'scripts/perf/benchmark.tscn does not exist'
    Complete-Gate 'G2 performance'
}

# --- Load. A stress switch may only add load. ---------------------------------
$load = 'canonical'
$expectedEntities = $CanonicalEntities
if ($Stress) {
    if ($StressEntities -le $CanonicalEntities) {
        $StressEntities = $CanonicalEntities * 2
    }
    $expectedEntities = $StressEntities
    $load = 'stress'
}

Write-Host ('  engine:  ' + $bin)
Write-Host '  scene:   res://scripts/perf/benchmark.tscn'
Write-Host ('  load:    ' + $load + ', ' + $expectedEntities + ' entities, ' + $Windows + ' windows of ' + $WindowFrames + ' frames')
Write-Host ('  budget:  fps_avg >= ' + $BudgetFpsAvg + ', frame_ms_p99 <= ' + (Format-Num $BudgetP99Ms '0.0') + ' ms (1 % low >= ' + (Format-Num $BudgetOnePctLow '0.0') + ' fps)')
Write-Host ('  display: requested ' + $DeclaredWidth + 'x' + $DeclaredHeight + ', content scale ' + (Format-Num $DeclaredScale '0.0') + ', vsync off, no frame cap')
Write-Host '  running windowed...'

$godotArgs = @(
    '--path', $StudioRoot,
    'res://scripts/perf/benchmark.tscn',
    '--',
    ('--entities=' + $expectedEntities),
    ('--windows=' + $Windows)
)
$r = Invoke-Native -Exe $bin -Arguments $godotArgs

# --- Parse the machine-readable lines the scene printed -----------------------
$info = $null
$aggregate = $null
$windowsSeen = 0
$phaseSeen = $false

foreach ($line in ($r.Output -split "`n")) {
    $t = $line.Trim()
    if ($t -match '^PERF_INFO\s+(\{.*\})$') {
        try { $info = $Matches[1] | ConvertFrom-Json } catch { $info = $null }
    } elseif ($t -match '^PERF_PHASE\s+measuring$') {
        $phaseSeen = $true
    } elseif ($t -match '^PERF_JSON\s+(\{.*\})$') {
        try { $obj = $Matches[1] | ConvertFrom-Json } catch { continue }
        if ($obj.PSObject.Properties.Name -contains 'aggregate') { $aggregate = $obj } else { $windowsSeen++ }
    }
}

$problems = @()
if ($r.ExitCode -ne 0) {
    if ($r.Output -match 'PERF_ERROR headless') {
        $problems += 'the scene refused to measure: it was run headless, and a headless frame time is not a rendered frame'
    } else {
        $problems += ('the scene exited ' + $r.ExitCode)
    }
}
if (-not $info) { $problems += 'no PERF_INFO line, so the load and render conditions are unknown' }
if (-not $phaseSeen) { $problems += 'never reached PERF_PHASE measuring, so nothing was measured' }
if (-not $aggregate) { $problems += 'no aggregate PERF_JSON line' }

if ($info) {
    if ([int]$info.declared_entity_count -ne $CanonicalEntities) {
        $problems += ('the scene declares ' + $info.declared_entity_count + ' canonical entities, the gate expects ' + $CanonicalEntities + ' - the load moved')
    }
    if ([int]$info.entity_count -ne $expectedEntities) {
        $problems += ('the scene ran ' + $info.entity_count + ' entities, expected ' + $expectedEntities)
    }
    if (-not $info.vsync_disabled) {
        $problems += 'vsync was on: fps is capped at the display refresh, so the number would not be a measurement'
    }
    if (([int]$info.viewport[0] -ne $DeclaredWidth) -or ([int]$info.viewport[1] -ne $DeclaredHeight)) {
        $problems += ('viewport ' + $info.viewport[0] + 'x' + $info.viewport[1] + ', expected ' + $DeclaredWidth + 'x' + $DeclaredHeight)
    }
    if ([math]::Abs([double]$info.content_scale[0] - $DeclaredScale) -gt 0.01) {
        $problems += ('content scale ' + (Format-Num ([double]$info.content_scale[0]) '0.0#') + ', expected ' + (Format-Num $DeclaredScale '0.0#'))
    }
    Write-Host ('  renderer: ' + $info.renderer + ' on Godot ' + $info.engine)
}
if ($windowsSeen -ne $Windows) {
    $problems += ('measured ' + $windowsSeen + ' windows, expected ' + $Windows)
}
if ($aggregate -and ([int]$aggregate.measured_frames -ne ($Windows * $WindowFrames))) {
    $problems += ('aggregate covers ' + $aggregate.measured_frames + ' frames, expected ' + ($Windows * $WindowFrames))
}

# --- The measurement ---------------------------------------------------------
$fps = 0.0
$p99 = 0.0
$onePctLow = 0.0
$budgetProblems = @()

if ($aggregate) {
    $fps = [double]$aggregate.fps_avg
    $p99 = [double]$aggregate.frame_ms_p99
    $onePctLow = [double]$aggregate.fps_1pct_low

    # Reported from the scene's own measurement of its window, not from the
    # constants above: if the run did not happen at the declared conditions the
    # line says so instead of repeating the request.
    $seenW = $DeclaredWidth
    $seenH = $DeclaredHeight
    $seenScale = $DeclaredScale
    $seenVsync = 'vsync state unknown'
    if ($info) {
        $seenW = [int]$info.viewport[0]
        $seenH = [int]$info.viewport[1]
        $seenScale = [double]$info.content_scale[0]
        if ($info.vsync_disabled) { $seenVsync = 'vsync off' } else { $seenVsync = 'vsync ON' }
    }
    Write-Host ('  measured at ' + $seenW + 'x' + $seenH + ', content scale ' + (Format-Num $seenScale '0.0#') + ', ' + $seenVsync)
    Write-Host ('  ' + $aggregate.measured_frames + ' frames, ' + $windowsSeen + ' windows, ' + $aggregate.entity_count + ' entities')
    Write-Host ('  fps_avg ' + (Format-Num $fps) + ' | frame_ms_p50 ' + (Format-Num ([double]$aggregate.frame_ms_p50) '0.00') + ' | frame_ms_p99 ' + (Format-Num $p99 '0.00') + ' | 1 % low ' + (Format-Num $onePctLow) + ' fps')

    if ($fps -lt $BudgetFpsAvg) {
        $budgetProblems += ('fps_avg ' + (Format-Num $fps) + ' < ' + $BudgetFpsAvg)
    }
    if ($p99 -gt $BudgetP99Ms) {
        $budgetProblems += ('frame_ms_p99 ' + (Format-Num $p99 '0.00') + ' ms > ' + (Format-Num $BudgetP99Ms '0.0') + ' ms')
    }
}

if ($problems.Count -gt 0) {
    Add-Result 'G2.3' 'Performance within budget' 'fail' ($problems -join '; ')
} elseif ($budgetProblems.Count -gt 0) {
    Add-Result 'G2.3' 'Performance within budget' 'fail' (($budgetProblems -join '; ') + ' at ' + $expectedEntities + ' entities, ' + $DeclaredWidth + 'x' + $DeclaredHeight + ' at ' + (Format-Num $DeclaredScale '0.0#') + 'x')
} else {
    Add-Result 'G2.3' 'Performance within budget' 'pass' ((Format-Num $fps) + ' fps avg >= ' + $BudgetFpsAvg + ', p99 ' + (Format-Num $p99 '0.00') + ' ms <= ' + (Format-Num $BudgetP99Ms '0.0') + ' ms, 1 % low ' + (Format-Num $onePctLow) + ' fps, ' + $expectedEntities + ' entities, ' + $DeclaredWidth + 'x' + $DeclaredHeight + ' at ' + (Format-Num $DeclaredScale '0.0#') + 'x')
}

Complete-Gate 'G2 performance'
