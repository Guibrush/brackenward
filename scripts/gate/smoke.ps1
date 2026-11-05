#requires -Version 5.1
# G2.1 — the main scene runs headlessly for 300 s without crashing, erroring, or
# reporting a stuck enemy.
#
# The exit code alone is not the gate (L-035). The arena quits cleanly on its own
# run timer, so a *broken* run still exits 0: with the walker's despawn handler
# disabled the scene printed three ARENA_STUCK lines and three ERROR: lines and
# exited 0. A pass therefore needs four independent facts, and every one is
# printed with the value it was decided on:
#
#   1. exit code 0                      the process did not crash
#   2. zero ERROR: lines                push_error and script errors both land here
#   3. "stuck": 0 in ARENA_SUMMARY      the scene's own despawn watchdog counter
#   4. at least `Duration` seconds      a scene that quits early with a clean
#                                       summary has not run for 300 s
#
# A scene that prints no ARENA_SUMMARY fails rather than passes: `stuck` cannot be
# evaluated, and a check that did not run is not a check that passed (L-021).
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

# The scene is left to resolve run/main_scene itself: that is the setting G2.1
# signs off, so it must be exercised rather than bypassed with a positional path.
$run = Invoke-BoundedRun -Exe $bin `
    -Arguments @('--headless', '--path', $StudioRoot, '--', ('--seconds=' + $Duration)) `
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

# 4. Duration. The criterion is "at least $RequiredSeconds seconds"; a scene that
# quits after two seconds with a clean summary satisfies 1-3 and must still not pass.
$reported = 0.0
if ($summary -and $null -ne $summary.seconds) { $reported = [double]$summary.seconds }
if ($reported -lt ($RequiredSeconds - 2)) {
    Add-Result 'G2.1.4' 'Ran for the full duration' 'fail' ('scene reported ' + [math]::Round($reported, 2) + 's of the ' + $RequiredSeconds + 's G2.1 requires')
} else {
    Add-Result 'G2.1.4' 'Ran for the full duration' 'pass' (([math]::Round($reported, 2)).ToString() + 's of ' + $RequiredSeconds + 's required')
}

Complete-Gate 'G2 smoke'
