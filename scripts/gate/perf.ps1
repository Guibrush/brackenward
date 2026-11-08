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
# A capped display is diagnosed, never excused. G2.3 passed for weeks at 651 fps
# and then read ~59 fps with no code change: the screen had dropped to 59 Hz with
# a virtual display adapter in the path, and frame delivery paces to one refresh
# period even with vsync off (L-040). So the refresh rate the scene reports is
# printed with the numbers, and when the measured p50 lands on one refresh period
# this script prints a single advisory line naming it. The advisory changes no
# verdict: the budget below decides pass or fail on its own.
#
# Screen and GPU are pinned, not left to the driver. A window that lands on a
# virtual or streaming display measures the wrong thing, and a machine with two
# render devices measures whichever one the driver picked, so:
#
#   * the harness asks the engine to enumerate its screens (a --probe-screens run)
#     and chooses one before it launches anything, because --screen is an engine
#     argument: highest reported refresh rate, ties by area, ties by index. A
#     screen reporting no refresh rate is never chosen while one that does report
#     one exists. If no screen reports a rate the gate blocks, loudly, instead of
#     measuring on a display nobody can name;
#   * the measurement runs with --screen <chosen> and --gpu-index 0, and the gate
#     reads back the window's actual screen and the engine's own "Using Device #0"
#     line. A window that landed elsewhere, or a GPU pin the engine did not honour
#     ("Falling back to automatic device selection"), fails the run: the number
#     would not belong to the display and device it claims.
#
# Parameters
#   -Stress          run the over-budget case: identical budget, more load
#   -StressEntities  entities for -Stress (default 30000; canonical is 1000)
#   -Windows         measured 60-frame windows (default 12)
#   -Screen          measure on this screen index instead of the chosen one. An
#                    operator diagnostic, never a way to get a number: a screen
#                    that cannot carry a measurement is refused, not measured on
#                    silently.
#
# Exit codes: 0 pass, 1 fail, 3 blocked (no engine, no benchmark scene, no screen
# that reports a refresh rate, or a -Screen that cannot carry the measurement).
param(
    [switch]$Stress,
    [int]$StressEntities = 30000,
    [int]$Windows = 12,
    [int]$Screen = -1
)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

# --- Budget: read-only, owned by docs/gates/G2-vertical-slice.md, G2.3 --------
$BudgetFpsAvg    = 60
$BudgetP99Ms     = 20.0
$BudgetOnePctLow = 45.0

# --- Capped-display diagnostic: advice, never a verdict -----------------------
# Below 120 Hz a screen paces frame delivery to one refresh period, so a p50 that
# sits on that period describes the machine, not the frame. Above 120 Hz the
# pacing is the target the gate is measuring against itself, so it is not named a
# cap. Both numbers are printed, so a reader can redo the arithmetic.
$CapDiagnosticMargin  = 0.10   # p50 within 10 % of one refresh period
$CapDiagnosticMaxHz   = 120.0  # only a display below this can be the cap

# Declared render conditions. art/STYLE.md: a 32px board at 2x in a 1080p window.
$DeclaredWidth    = 1920
$DeclaredHeight   = 1080
$DeclaredScale    = 2.0
$WindowFrames     = 60

# The scene's canonical load; benchmark.gd asserts the same number.
$CanonicalEntities = 1000

# The render device this gate measures on, passed to the engine as --gpu-index.
# Device #0 is the adapter Godot already selects on the target machine; pinning it
# means a second device cannot take the measurement over quietly.
$GpuIndex = 0

$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Format-Num {
    param([double]$Value, [string]$Format = '0.0')
    return $Value.ToString($Format, $inv)
}

# Is the measured p50 one refresh period away from the display's own cadence?
#
# Pure function of the two numbers the run reported, so it can be exercised with
# a synthetic p50 without starting an engine. An unknown refresh rate (0.0) is
# never a cap: this returns false and the caller says the rate is unknown rather
# than inventing a diagnosis (L-040 - a red result must be attributable from the
# output alone, not by guessing).
function Test-CappedDisplay {
    param(
        [double]$P50Ms,
        [double]$RefreshHz,
        [double]$Margin,
        [double]$MaxRefreshHz
    )
    if ($RefreshHz -le 0.0) { return $false }
    if ($RefreshHz -ge $MaxRefreshHz) { return $false }
    if ($P50Ms -le 0.0) { return $false }
    $period = 1000.0 / $RefreshHz
    $delta = [math]::Abs($P50Ms - $period)
    return ($delta -le ($period * $Margin))
}

function Get-ScreenArea {
    param($Screen)
    return ([int]$Screen.size[0]) * ([int]$Screen.size[1])
}

# Chooses the screen the measurement may run on.
#
# A pure function of the table the engine reported, so the rule can be exercised
# with a synthetic table - including a 0 Hz virtual adapter this machine does not
# expose - without starting an engine.
#
# Rule:
#   * only a screen that reports a refresh rate is eligible. A screen reporting
#     none (0 Hz, or the -1 "unknown" the API returns; typical for a virtual or
#     streaming adapter) is never chosen while a screen that does report one
#     exists;
#   * the highest reported refresh rate wins: a display at 59 Hz paces frame
#     delivery to one refresh period, so measuring on it cannot exceed that rate;
#   * ties go to the larger screen, then to the lower index, so the same table
#     always produces the same answer.
#
# Returns Index (-1 when nothing is eligible), Reason (why, either way), and the
# chosen screen's Width, Height and RefreshHz, plus Skipped (the screens that
# reported no rate and were therefore ineligible).
function Select-BenchmarkScreen {
    param([object[]]$Screens)

    if ($null -eq $Screens -or $Screens.Count -eq 0) {
        return @{ Index = -1; Reason = 'the engine enumerated no screens'; Width = 0; Height = 0; RefreshHz = 0.0; Skipped = @() }
    }

    $skipped = @()
    $eligible = @()
    foreach ($s in $Screens) {
        $rate = 0.0
        if ($s.PSObject.Properties.Name -contains 'refresh_hz') { $rate = [double]$s.refresh_hz }
        $reported = $false
        if ($s.PSObject.Properties.Name -contains 'refresh_reported') { $reported = [bool]$s.refresh_reported }
        if ($reported -and ($rate -gt 0.0)) {
            $eligible += $s
        } else {
            $skipped += ('screen ' + [int]$s.index + ' (' + [int]$s.size[0] + 'x' + [int]$s.size[1] + ') reports no refresh rate')
        }
    }

    if ($eligible.Count -eq 0) {
        return @{
            Index   = -1
            Reason  = 'no screen reports a refresh rate - every enumerated screen looks virtual or unreported, so there is no physical display to measure on'
            Width   = 0
            Height  = 0
            RefreshHz = 0.0
            Skipped = $skipped
        }
    }

    $best = $eligible |
        Sort-Object -Property @{ Expression = { [double]$_.refresh_hz }; Descending = $true },
                              @{ Expression = { Get-ScreenArea $_ }; Descending = $true },
                              @{ Expression = { [int]$_.index }; Ascending = $true } |
        Select-Object -First 1

    $reason = ('screen ' + [int]$best.index + ' reports the highest refresh rate (' + (Format-Num ([double]$best.refresh_hz) '0.0#') + ' Hz)')
    if ($eligible.Count -gt 1) {
        $reason = $reason + (', ahead of ' + ($eligible.Count - 1) + ' other screen(s) that also report a rate')
    }
    return @{
        Index   = [int]$best.index
        Reason  = $reason
        Width   = [int]$best.size[0]
        Height  = [int]$best.size[1]
        RefreshHz = [double]$best.refresh_hz
        Skipped = $skipped
    }
}

# --- Guard: dot-sourcing this file must define its functions and nothing else ---
# The chooser above is the one decision that can silently measure the wrong
# display, so it has to be demonstrable against a synthetic table on a machine
# with a single screen. Dot-sourcing stops here; running the file as a script
# (which is how the gate invokes it) continues. Verified both ways.
if ($MyInvocation.InvocationName -eq '.') { return }

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

# --- Which display, and which GPU, this number belongs to ---------------------
# --screen is an engine argument, so the screen has to be chosen before the
# measurement starts. A probe run enumerates the screens from inside the engine
# (same build, same GPU pin), prints one PERF_SCREENS line and quits without
# building the load: it costs about a second and makes the choice checkable from
# the log instead of implied by the window's behaviour.
$probeArgs = @(
    '--path', $StudioRoot,
    '--gpu-index', $GpuIndex,
    'res://scripts/perf/benchmark.tscn',
    '--',
    '--probe-screens'
)
$probe = Invoke-Native -Exe $bin -Arguments $probeArgs
$probeGpuFallback = ($probe.Output -match 'Falling back to automatic device selection')

$screenReport = $null
foreach ($line in ($probe.Output -split "`n")) {
    if ($line.Trim() -match '^PERF_SCREENS\s+(\{.*\})$') {
        try { $screenReport = $Matches[1] | ConvertFrom-Json } catch { $screenReport = $null }
    }
}
$screens = @()
if ($screenReport -and ($screenReport.PSObject.Properties.Name -contains 'screens')) {
    $screens = @($screenReport.screens)
}

if ($screens.Count -eq 0) {
    $why = 'the engine enumerated no screen (no PERF_SCREENS line; probe exit ' + $probe.ExitCode + ')'
    if ($probe.Output -match '(?m)^PERF_ERROR\s+(.+)$') { $why = 'the engine refused the probe: ' + $Matches[1].Trim() }
    Write-Host ('  screens: none - ' + $why)
    Add-Result 'G2.3' 'Performance within budget' 'blocked' ($why + '; no display can be chosen, so nothing was measured')
    Complete-Gate 'G2 performance'
}

$choice = Select-BenchmarkScreen -Screens $screens
$chosen = [int]$choice.Index
$chosenW = [int]$choice.Width
$chosenH = [int]$choice.Height
$chosenHz = [double]$choice.RefreshHz
$choiceWhy = $choice.Reason

# A forced screen is a diagnostic. It is checked like any other candidate, and
# refused - never measured on - when it cannot carry the measurement.
if ($Screen -ge 0) {
    $forced = @($screens | Where-Object { [int]$_.index -eq $Screen })
    if ($forced.Count -eq 0) {
        $ids = (@($screens | ForEach-Object { [string][int]$_.index }) -join ', ')
        $why = 'refusing to measure: -Screen ' + $Screen + ' does not exist, the engine sees screen(s) ' + $ids
        Write-Host ('  REFUSED ' + $why)
        Add-Result 'G2.3' 'Performance within budget' 'blocked' ($why + '; nothing was measured')
        Complete-Gate 'G2 performance'
    }
    $forcedRate = 0.0
    if ($forced[0].PSObject.Properties.Name -contains 'refresh_hz') { $forcedRate = [double]$forced[0].refresh_hz }
    $forcedReported = $false
    if ($forced[0].PSObject.Properties.Name -contains 'refresh_reported') { $forcedReported = [bool]$forced[0].refresh_reported }
    if (-not ($forcedReported -and ($forcedRate -gt 0.0))) {
        $rawRate = $forcedRate
        if ($forced[0].PSObject.Properties.Name -contains 'refresh_hz_raw') { $rawRate = [double]$forced[0].refresh_hz_raw }
        $why = 'refusing to measure on screen ' + $Screen + ': it reports no refresh rate (raw ' + (Format-Num $rawRate '0.0#') + ')'
        if ($choice.Index -ge 0) {
            $why = $why + ', while screen ' + $choice.Index + ' reports ' + (Format-Num $choice.RefreshHz '0.0#') + ' Hz - a virtual or streaming display would produce a number about the wrong screen'
        } else {
            $why = $why + ', and no other screen reports one either - there is no display whose refresh rate is known'
        }
        Write-Host ('  REFUSED ' + $why)
        Add-Result 'G2.3' 'Performance within budget' 'blocked' ($why + '; nothing was measured')
        Complete-Gate 'G2 performance'
    }
    $chosen = [int]$forced[0].index
    $chosenW = [int]$forced[0].size[0]
    $chosenH = [int]$forced[0].size[1]
    $chosenHz = $forcedRate
    $choiceWhy = 'forced with -Screen, not chosen by the rule'
}

if ($chosen -lt 0) {
    foreach ($s in $choice.Skipped) { Write-Host ('    ! ' + $s) }
    Write-Host ('  REFUSED ' + $choice.Reason)
    Add-Result 'G2.3' 'Performance within budget' 'blocked' ($choice.Reason + '; nothing was measured rather than measuring on a display that cannot be named')
    Complete-Gate 'G2 performance'
}

# The table, printed whether or not the run goes on to measure: this is the line
# that lets a reader tell which display produced a number, or why none did.
Write-Host ('  screens: ' + $screens.Count + ' seen from inside the engine, GPU ' + $screenReport.renderer)
foreach ($s in $screens) {
    $row = '    [' + ([int]$s.index).ToString().PadLeft(2) + '] ' + ([int]$s.size[0]).ToString() + 'x' + ([int]$s.size[1]).ToString()
    $row = $row.PadRight(20)
    if ([bool]$s.refresh_reported) { $row = $row + (Format-Num ([double]$s.refresh_hz) '0.0#') + ' Hz' }
    else { $row = $row + 'refresh not reported' }
    $row = $row.PadRight(40)
    $tags = @()
    if ([bool]$s.primary) { $tags += 'primary' }
    if ([int]$s.index -eq $chosen) { $tags += 'CHOSEN' }
    elseif (-not [bool]$s.refresh_reported) { $tags += 'not eligible: no refresh rate' }
    if ($tags.Count -gt 0) { $row = $row + ' ' + ($tags -join ', ') }
    Write-Host $row
}
Write-Host ('  chosen:  screen ' + $chosen + ', ' + $chosenW + 'x' + $chosenH + ', ' + (Format-Num $chosenHz '0.0#') + ' Hz - ' + $choiceWhy)
foreach ($s in $choice.Skipped) {
    Write-Host ('    ! ' + $s + ' - not eligible')
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
Write-Host ('  pin:     --screen ' + $chosen + ', --gpu-index ' + $GpuIndex + ' (a fallback to automatic device selection fails the run)')
Write-Host '  running windowed...'

$godotArgs = @(
    '--path', $StudioRoot,
    '--gpu-index', $GpuIndex,
    '--screen', $chosen,
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
$perfWarn = @()
$deviceIndex = -1
$gpuFallback = $false

foreach ($line in ($r.Output -split "`n")) {
    $t = $line.Trim()
    if ($t -match '^PERF_INFO\s+(\{.*\})$') {
        try { $info = $Matches[1] | ConvertFrom-Json } catch { $info = $null }
    } elseif ($t -match '^PERF_PHASE\s+measuring$') {
        $phaseSeen = $true
    } elseif ($t -match '^PERF_JSON\s+(\{.*\})$') {
        try { $obj = $Matches[1] | ConvertFrom-Json } catch { continue }
        if ($obj.PSObject.Properties.Name -contains 'aggregate') { $aggregate = $obj } else { $windowsSeen++ }
    } elseif ($t -match '^PERF_WARN\s+(.+)$') {
        $perfWarn += $t
    }
    # The engine's own startup line, "… - Using Device #0: NVIDIA - …". This is
    # direct evidence of which render device the frame was drawn on; the script
    # cannot read the flag back (OS.get_cmdline_args() hides Godot's own options).
    if ($t -match 'Using Device #(\d+)') { $deviceIndex = [int]$Matches[1] }
    if ($t -match 'Falling back to automatic device selection') { $gpuFallback = $true }
}

$problems = @()
if ($r.ExitCode -ne 0) {
    if ($r.Output -match 'PERF_ERROR headless') {
        $problems += 'the scene refused to measure: it was run headless, and a headless frame time is not a rendered frame'
    } elseif ($r.Output -match '(?m)^PERF_ERROR\s+(.+)$') {
        $problems += ('the scene refused to measure: ' + $Matches[1].Trim())
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

    # --- Did the run land on the display and device that were asked for? ------
    # Recorded, not assumed: the engine reports the screen its window is actually
    # on, and prints the device index it selected. A mismatch means the number
    # belongs to something other than what the result block would claim.
    $seenScreen = -1
    if ($info.PSObject.Properties.Name -contains 'screen') { $seenScreen = [int]$info.screen }
    if ($seenScreen -ne $chosen) {
        $problems += ('the window landed on screen ' + $seenScreen + ', the harness asked for screen ' + $chosen + ' with --screen - the number would describe a display that was not chosen')
    }
    if ($gpuFallback -or $probeGpuFallback) {
        $problems += ('the engine did not honour --gpu-index ' + $GpuIndex + ' ("Falling back to automatic device selection"), so the render device was not pinned')
    }
    if ($deviceIndex -lt 0) {
        $problems += 'the engine never printed "Using Device #N", so which GPU rendered this frame is unknown'
    } elseif ($deviceIndex -ne $GpuIndex) {
        $problems += ('the engine rendered on device #' + $deviceIndex + ', --gpu-index asked for #' + $GpuIndex)
    }
    if ($screenReport -and $screenReport.renderer -and $info.renderer -and ([string]$screenReport.renderer -ne [string]$info.renderer)) {
        $problems += ('the probe and the measurement ran on different adapters ("' + $screenReport.renderer + '" then "' + $info.renderer + '"), so the GPU was not stable between the two runs')
    }

    Write-Host ('  renderer: ' + $info.renderer + ' (' + $info.renderer_vendor + ') on Godot ' + $info.engine)
    if ($deviceIndex -ge 0) {
        $deviceNote = '  device:   GPU #' + $deviceIndex + ' requested as --gpu-index ' + $GpuIndex
        if ($gpuFallback -or $probeGpuFallback) { $deviceNote = $deviceNote + ' - FALLBACK to automatic selection' }
        Write-Host $deviceNote
    } else {
        Write-Host '  device:   not named by the engine'
    }
}
foreach ($w in $perfWarn) { Write-Host ('  ' + $w) }
if ($windowsSeen -ne $Windows) {
    $problems += ('measured ' + $windowsSeen + ' windows, expected ' + $Windows)
}
if ($aggregate -and ([int]$aggregate.measured_frames -ne ($Windows * $WindowFrames))) {
    $problems += ('aggregate covers ' + $aggregate.measured_frames + ' frames, expected ' + ($Windows * $WindowFrames))
}

# --- Display provenance: which machine this number belongs to ----------------
# Read from PERF_INFO, which the scene filled from the platform. A missing field
# or 0.0 means unknown: reported as unknown and never invented (L-040). An
# unknown rate is not a failure - a machine that will not state its refresh rate
# has not broken the budget, so this changes no exit code.
$refreshHz = 0.0
if ($info -and ($info.PSObject.Properties.Name -contains 'refresh_hz')) {
    $refreshHz = [double]$info.refresh_hz
}
$refreshKnown = ($refreshHz -gt 0.0)
$refreshPeriodMs = 0.0
if ($refreshKnown) { $refreshPeriodMs = 1000.0 / $refreshHz }

# --- The measurement ---------------------------------------------------------
$fps = 0.0
$p50 = 0.0
$p99 = 0.0
$onePctLow = 0.0
$cappedDisplay = $false
$budgetProblems = @()

if ($aggregate) {
    $fps = [double]$aggregate.fps_avg
    $p50 = [double]$aggregate.frame_ms_p50
    $p99 = [double]$aggregate.frame_ms_p99
    $onePctLow = [double]$aggregate.fps_1pct_low

    # Reported from the scene's own measurement of its window, not from the
    # constants above: if the run did not happen at the declared conditions the
    # line says so instead of repeating the request.
    $seenW = $DeclaredWidth
    $seenH = $DeclaredHeight
    $seenScale = $DeclaredScale
    $seenVsync = 'vsync state unknown'
    $seenMaxFps = 'frame cap unknown'
    if ($info) {
        $seenW = [int]$info.viewport[0]
        $seenH = [int]$info.viewport[1]
        $seenScale = [double]$info.content_scale[0]
        if ($info.vsync_disabled) { $seenVsync = 'vsync off' } else { $seenVsync = 'vsync ON' }
        if ($info.PSObject.Properties.Name -contains 'max_fps') {
            if ([int]$info.max_fps -eq 0) { $seenMaxFps = 'no frame cap' } else { $seenMaxFps = ('max fps ' + $info.max_fps) }
        }
    }
    Write-Host ('  measured at ' + $seenW + 'x' + $seenH + ', content scale ' + (Format-Num $seenScale '0.0#') + ', ' + $seenVsync + ', ' + $seenMaxFps)
    Write-Host ('  screen:  ' + $chosen + ' (' + $chosenW + 'x' + $chosenH + ', chosen) reported ' + $seenScreen + ', on GPU #' + $deviceIndex)
    if ($refreshKnown) {
        Write-Host ('  display refresh ' + (Format-Num $refreshHz '0.0#') + ' Hz, one period is ' + (Format-Num $refreshPeriodMs '0.00') + ' ms')
    } else {
        Write-Host '  display refresh not reported by the platform'
    }
    Write-Host ('  ' + $aggregate.measured_frames + ' frames, ' + $windowsSeen + ' windows, ' + $aggregate.entity_count + ' entities')
    Write-Host ('  fps_avg ' + (Format-Num $fps) + ' | frame_ms_p50 ' + (Format-Num $p50 '0.00') + ' | frame_ms_p99 ' + (Format-Num $p99 '0.00') + ' | 1 % low ' + (Format-Num $onePctLow) + ' fps')

    # One advisory line, printed before the budget is applied and remembered by
    # nothing: it explains a number, it never decides one. A reader can check the
    # arithmetic because the p50, the rate and the period are all on screen.
    $cappedDisplay = Test-CappedDisplay -P50Ms $p50 -RefreshHz $refreshHz -Margin $CapDiagnosticMargin -MaxRefreshHz $CapDiagnosticMaxHz
    if ($cappedDisplay) {
        Write-Host ('  ADVISORY p50 ' + (Format-Num $p50 '0.00') + ' ms is one ' + (Format-Num $refreshHz '0.0#') + ' Hz refresh period (' + (Format-Num $refreshPeriodMs '0.00') + ' ms, tolerance ' + (Format-Num ($refreshPeriodMs * $CapDiagnosticMargin) '0.00') + ' ms) - the display is pacing frame delivery; this is not a code regression. The budget is unchanged and still decides the verdict.')
    } elseif (-not $refreshKnown) {
        Write-Host '  ADVISORY no refresh rate in PERF_INFO, so a capped display cannot be ruled out from this run - record the rate to make a red result attributable'
    }

    if ($fps -lt $BudgetFpsAvg) {
        $budgetProblems += ('fps_avg ' + (Format-Num $fps) + ' < ' + $BudgetFpsAvg)
    }
    if ($p99 -gt $BudgetP99Ms) {
        $budgetProblems += ('frame_ms_p99 ' + (Format-Num $p99 '0.00') + ' ms > ' + (Format-Num $BudgetP99Ms '0.0') + ' ms')
    }
}

# What the verdict line says about the machine, so the number carries its
# provenance into the result block: which screen, at what refresh, on which GPU.
# Purely descriptive - the budget above alone decides pass or fail.
$gpuNote = 'GPU unknown'
if ($info -and ($info.PSObject.Properties.Name -contains 'renderer') -and ([string]$info.renderer -ne '')) {
    $gpuNote = [string]$info.renderer
    if ($deviceIndex -ge 0) { $gpuNote = $gpuNote + ' (GPU #' + $deviceIndex + ')' }
}

$screenNote = 'screen unknown'
if ($chosen -ge 0) {
    $screenNote = 'screen ' + $chosen + ' (' + $chosenW + 'x' + $chosenH + ' @ ' + (Format-Num $chosenHz '0.0#') + ' Hz)'
    if ($cappedDisplay) { $screenNote = $screenNote + ', pacing frames' }
    if (-not $refreshKnown) { $screenNote = $screenNote + ', refresh not reported at measurement time' }
}
$displayNote = $screenNote + ' on ' + $gpuNote

if ($problems.Count -gt 0) {
    Add-Result 'G2.3' 'Performance within budget' 'fail' (($problems -join '; ') + ' (' + $displayNote + ')')
} elseif ($budgetProblems.Count -gt 0) {
    Add-Result 'G2.3' 'Performance within budget' 'fail' (($budgetProblems -join '; ') + ' at ' + $expectedEntities + ' entities, ' + $DeclaredWidth + 'x' + $DeclaredHeight + ' at ' + (Format-Num $DeclaredScale '0.0#') + 'x, ' + $displayNote)
} else {
    Add-Result 'G2.3' 'Performance within budget' 'pass' ((Format-Num $fps) + ' fps avg >= ' + $BudgetFpsAvg + ', p99 ' + (Format-Num $p99 '0.00') + ' ms <= ' + (Format-Num $BudgetP99Ms '0.0') + ' ms, 1 % low ' + (Format-Num $onePctLow) + ' fps, ' + $expectedEntities + ' entities, ' + $DeclaredWidth + 'x' + $DeclaredHeight + ' at ' + (Format-Num $DeclaredScale '0.0#') + 'x, ' + $displayNote)
}

Complete-Gate 'G2 performance'
