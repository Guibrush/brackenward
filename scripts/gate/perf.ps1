#requires -Version 5.1
# G2.3 — performance within budget.
#
# Deliberately blocked rather than guessed. A headless frame-time measurement is
# not representative of a rendered frame, and a gate that measures the wrong
# thing is worse than a gate that admits it cannot measure yet.
#
# Method to implement at G2, once a benchmark scene exists:
#   1. scripts/perf/benchmark.tscn runs a fixed scripted sequence with a known
#      entity count, and prints one JSON line per 60 frames:
#        {"frame_ms_p50":..,"frame_ms_p99":..,"fps_avg":..}
#   2. Run windowed (not --headless) so the renderer is active, with --print-fps
#      as a cross-check.
#   3. Pass when fps_avg >= 60 and frame_ms_p99 <= 20 (1% low >= 45 fps).
#
# Budget lives in docs/gates/G2-vertical-slice.md. Do not loosen it here.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot 'gate.config.ps1')

Write-Host 'G2 - performance'

$benchmark = Join-Path $StudioRoot 'scripts\perf\benchmark.tscn'
if (-not (Test-Path $benchmark)) {
    Add-Result 'G2.3' 'Benchmark scene exists' 'blocked' 'scripts/perf/benchmark.tscn not created - see the method in this file'
    Complete-Gate 'G2 performance'
}

Add-Result 'G2.3' 'Benchmark measurement implemented' 'blocked' 'benchmark scene exists but the measurement harness is not written yet'
Complete-Gate 'G2 performance'
