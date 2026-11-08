#requires -Version 5.1
# G2.1 — the game runs headlessly for 300 s without crashing, erroring, or
# reporting a stuck enemy.
#
# The exit code alone is not the gate (L-035). The entry point quits cleanly on its
# own session timer, so a *broken* run still exits 0: with the walker's despawn
# handler disabled the scene printed three ARENA_STUCK lines and three ERROR: lines
# and exited 0. A pass therefore needs four independent facts, and every one is
# printed with the value it was decided on:
#
#   1. exit code 0                      the process did not crash
#   2. zero ERROR: lines                push_error and script errors both land here
#   3. "stuck": 0 in ARENA_SUMMARY      the scene's own despawn watchdog counter
#   4. at least `Duration` seconds      a session that quits early with a clean
#                                       summary has not run for 300 s
#
# Check 4 measures the *session*, not one level (ADR-0007). The criterion reads "a
# headless run of at least 300 s", and since the main scene is the boot
# (res://scenes/boot.tscn) that run outlives every level inside it: the boot prints
# `BOOT_SESSION {"seconds","runs","restarts"}` once at quit, and `seconds` is the
# process's lifetime. When that line is absent -- a level scene run directly, an
# older build -- check 4 falls back to the last `ARENA_SUMMARY`'s `seconds`, and the
# gate prints `source: session` or `source: arena` before the number it decided on,
# so a fallback can never quietly weaken the criterion. Checks 2 and 3 always read
# ARENA_SUMMARY: they are properties of a level, so the last level is the right
# place to read them.
#
# A scene that prints no ARENA_SUMMARY fails rather than passes: `stuck` cannot be
# evaluated, and a check that did not run is not a check that passed (L-021).
#
# The entry point is driven with `--autostart` (src/ui/boot.gd): without it the boot
# sits on the menu, no level opens, and check 3 has nothing to read. Autostart keeps
# a run on screen for the whole session, replacing a finished one until the time
# runs out (T-0053), so this gate exercises gameplay rather than an idle menu.
#
# The scene is expected to end its own run; it is asked to with `--seconds=<n>`
# (the arena's documented interface, src/gameplay/arena.gd). If it does not end,
# the process is killed at `Duration + 60` s and reported as a fail, so this gate
# can never hang on the scene it is measuring.
#
# This is not a substitute for playing the game. It catches crashes, error lines
# and a despawn regression; it cannot tell you whether the game is any good.
#
# Exit codes: 0 pass, 1 fail, 3 blocked (no engine, no project, no main scene, or
# a main scene whose file is missing). Blocked is not failure.
#
#   powershell -NoProfile -File scripts/gate/smoke.ps1
param(
    # The run length requested from the scene. The G2.1 criterion is fixed at
    # `$RequiredSeconds`; a shorter run is accepted as a probe of this script's
    # plumbing but fails check 4, so this parameter can never turn a 20 s run into
    # a pass for a 300 s criterion.
    [int]$Duration = 300
)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

# G2.1 as written in docs/gates/G2-vertical-slice.md: "a headless stability run of
# at least 300 s". The criterion is a constant here, not a parameter, so no flag
# can lower the bar the gate signs.
$RequiredSeconds = 300

# How long the scene may outlive its requested run before it is killed.
$KillGraceSeconds = 60

Write-Host 'G2 - smoke'

$bin = Get-GodotConsole
if (-not $bin) {
    Add-Result 'G2.1' 'Engine available' 'blocked' 'no Godot console executable'
    Complete-Gate 'G2 smoke'
}

$projectPath = Join-Path $StudioRoot 'project.godot'
$project = Read-Text $projectPath
if (-not $project) {
    Add-Result 'G2.1' 'Project exists' 'blocked' 'project.godot missing'
    Complete-Gate 'G2 smoke'
}

$m = [regex]::Match($project, '(?m)^run/main_scene\s*=\s*"([^"]+)"')
if (-not $m.Success) {
    Add-Result 'G2.1' 'A main scene is configured' 'blocked' 'run/main_scene is not set - nothing to run'
    Complete-Gate 'G2 smoke'
}
$sceneRes = $m.Groups[1].Value

# Checked against the filesystem before the engine is started, so "the scene was
# deleted" reports as blocked instead of as an engine error that looks like a
# crash. Never a pass, never a fail.
$sceneRel = $sceneRes -replace '^res:/+', ''
$sceneDisk = Join-Path $StudioRoot ($sceneRel -replace '/', '\')
if (-not (Test-Path -LiteralPath $sceneDisk)) {
    Add-Result 'G2.1' 'Main scene exists' 'blocked' ($sceneRes + ' is configured but not on disk: ' + $sceneRel)
    Complete-Gate 'G2 smoke'
}

# Runs the engine with a hard bound. Not common.ps1's Invoke-Native, which waits
# forever: a main loop that hangs is a result this gate must report, not something
# it may wait on. The pipe handling is the same, for the reason written there -
# redirected native stderr must not become a PowerShell ErrorRecord in a caller
# running with -ErrorActionPreference = 'Stop'.
function Invoke-BoundedRun {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]') { $quoted += ('"' + ($a -replace '"', '\"') + '"') }
        else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        return [pscustomobject]@{
            ExitCode = 127
            TimedOut = $false
            Seconds  = 0.0
            Output   = ('executable not found or not runnable: ' + $Exe)
        }
    }

    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $p.Kill() } catch { }
        # Drain the pipes so the read tasks can complete and the output is kept.
        [void]$p.WaitForExit(5000)
    }
    $clock.Stop()

    $code = $p.ExitCode
    $text = $outTask.Result + $errTask.Result

    return [pscustomobject]@{
        ExitCode = $code
        TimedOut = $timedOut
        Seconds  = [math]::Round($clock.Elapsed.TotalSeconds, 1)
        Output   = (Remove-Ansi $text)
    }
}

# Reads a JSON "seconds" field as a double, or $null when it is not a number. A
# malformed field must fall back and say so, not throw inside the gate or be
# silently read as zero: zero would be a fail for the wrong reason.
function ConvertTo-Seconds {
    param($Value)
    if ($null -eq $Value) { return $null }
    $parsed = 0.0
    $ok = [double]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )
    if ($ok) { return $parsed }
    return $null
}

# The scene is left to resolve run/main_scene itself: that is the setting G2.1
# signs off, so it must be exercised rather than bypassed with a positional path.
# `--autostart` is the entry point's documented headless mode: without it the boot
# stops on the menu and no level ever reports a summary.
$run = Invoke-BoundedRun -Exe $bin `
    -Arguments @('--headless', '--path', $StudioRoot, '--', '--autostart', ('--seconds=' + $Duration)) `
    -TimeoutSeconds ($Duration + $KillGraceSeconds)

$lines = @($run.Output -split "`n")
$errorLines = @($lines | Where-Object { $_ -match '^\s*(ERROR:|SCRIPT ERROR:)' })

# Last summary wins: the scene guards against printing twice, and an earlier line
# would be a stale copy if that guard ever broke.
$summary = $null
$summaryLines = @($lines | Where-Object { $_ -match '^ARENA_SUMMARY\s' })
if ($summaryLines.Count -gt 0) {
    $json = $summaryLines[$summaryLines.Count - 1] -replace '^ARENA_SUMMARY\s+', ''
    try { $summary = $json | ConvertFrom-Json } catch { $summary = $null }
}

# The session's own measurement (ADR-0007), printed once and last by the entry
# point. Last line wins, for the same reason as the summary. A line that is present
# but blank or unparseable is treated as absent and reported as such: it is not a
# number the criterion can be judged on.
$session = $null
$sessionLineCount = 0
$sessionLines = @($lines | Where-Object { $_ -match '^BOOT_SESSION\b' })
if ($sessionLines.Count -gt 0) {
    $sessionLineCount = $sessionLines.Count
    $sessionJson = ($sessionLines[$sessionLines.Count - 1] -replace '^BOOT_SESSION\s*', '').Trim()
    if ($sessionJson -ne '') {
        try { $session = $sessionJson | ConvertFrom-Json } catch { $session = $null }
    }
}

# Which number check 4 is judged on, and why. Named here, printed below, and used
# by the check itself: the source and the verdict cannot disagree.
$durationSource = 'arena'
$fallbackWhy = 'no BOOT_SESSION line in the output'
$sessionSeconds = $null
if ($sessionLineCount -gt 0) {
    if ($session -eq $null) {
        $fallbackWhy = 'the BOOT_SESSION line carries no usable JSON'
    } else {
        $sessionSeconds = ConvertTo-Seconds $session.seconds
        if ($sessionSeconds -eq $null) {
            $fallbackWhy = 'the BOOT_SESSION line has no usable "seconds" field'
        } else {
            $durationSource = 'session'
        }
    }
}

# The numbers the verdict is made of, printed whether they pass or not.
Write-Host ('  scene:    ' + $sceneRes)
Write-Host ('  exit:     ' + $run.ExitCode + ' (killed at ' + ($Duration + $KillGraceSeconds) + 's: ' + $run.TimedOut + ')')
Write-Host ('  wall:     ' + $run.Seconds + 's, requested ' + $Duration + 's')
if ($summary) {
    Write-Host ('  summary:  seconds ' + $summary.seconds + ', spawned ' + $summary.spawned +
        ', leaked ' + $summary.leaked + ', despawned ' + $summary.despawned +
        ', live ' + $summary.live + ', stuck ' + $summary.stuck +
        ', hq ' + $summary.hq_before + ' -> ' + $summary.hq_after)
} else {
    Write-Host '  summary:  none - no ARENA_SUMMARY line in the output'
}
# The source of the duration number, printed before the number it decided: a
# fallback is visible here or it does not exist (ADR-0007, accepted cost).
if ($durationSource -eq 'session') {
    Write-Host ('  duration: source: session - ' + [math]::Round($sessionSeconds, 2) + 's, runs ' +
        $session.runs + ', restarts ' + $session.restarts + ' (BOOT_SESSION)')
} else {
    Write-Host ('  duration: source: arena - ' + $fallbackWhy +
        '; judged on the last ARENA_SUMMARY.seconds, which measures one level, not the session (ADR-0007)')
}
Write-Host ('  errors:   ' + $errorLines.Count + ' matching line(s)')

# 1. Exit code.
if ($run.TimedOut) {
    Add-Result 'G2.1.1' 'Exit code is 0' 'fail' ('did not end within ' + ($Duration + $KillGraceSeconds) + 's - killed')
} elseif ($run.ExitCode -ne 0) {
    $tail = ($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 4) -join ' | '
    Add-Result 'G2.1.1' 'Exit code is 0' 'fail' ('exit ' + $run.ExitCode + ': ' + $tail)
} else {
    Add-Result 'G2.1.1' 'Exit code is 0' 'pass' 'exit 0'
}

# 2. Error lines. Independent of the exit code on purpose: the whole point of the
# criterion is that these two disagree when the scene is broken.
if ($errorLines.Count -gt 0) {
    Add-Result 'G2.1.2' 'No error output' 'fail' ($errorLines.Count.ToString() + ' line(s), first: ' + $errorLines[0].Trim())
} else {
    Add-Result 'G2.1.2' 'No error output' 'pass' '0 error lines'
}

# 3. The scene's own stuck counter.
if (-not $summary) {
    Add-Result 'G2.1.3' 'No enemy left alive after arriving' 'fail' 'no ARENA_SUMMARY line - the stuck count cannot be read'
} elseif ($null -eq $summary.stuck) {
    Add-Result 'G2.1.3' 'No enemy left alive after arriving' 'fail' 'ARENA_SUMMARY has no "stuck" field'
} elseif ([int]$summary.stuck -ne 0) {
    Add-Result 'G2.1.3' 'No enemy left alive after arriving' 'fail' ('stuck ' + $summary.stuck + ', despawned ' + $summary.despawned + ', live ' + $summary.live)
} else {
    Add-Result 'G2.1.3' 'No enemy left alive after arriving' 'pass' ('stuck 0, despawned ' + $summary.despawned + ' of ' + $summary.spawned + ' spawned')
}

# 4. Duration, from the session when the entry point reports one. The criterion is
# "at least $RequiredSeconds seconds"; a run that quits after two seconds with a
# clean summary satisfies 1-3 and must still not pass. The source is in the detail
# so a fallback fail reads as a fallback fail, not as a broken session.
$reported = 0.0
if ($durationSource -eq 'session') {
    $reported = [double]$sessionSeconds
} elseif ($summary -and $null -ne $summary.seconds) {
    $reported = [double]$summary.seconds
}
if ($reported -lt ($RequiredSeconds - 2)) {
    Add-Result 'G2.1.4' 'Ran for the full duration' 'fail' ('duration ' + [math]::Round($reported, 2) +
        's from source: ' + $durationSource + ', of the ' + $RequiredSeconds + 's G2.1 requires')
} else {
    Add-Result 'G2.1.4' 'Ran for the full duration' 'pass' (([math]::Round($reported, 2)).ToString() +
        's from source: ' + $durationSource + ', of ' + $RequiredSeconds + 's required')
}

Complete-Gate 'G2 smoke'
