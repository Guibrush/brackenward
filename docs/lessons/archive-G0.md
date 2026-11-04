# Lessons archive — through G0 (entries L-001 … L-008)

Moved from `docs/LESSONS.md` on 2026-11-04 when the file exceeded its line budget
after the G0 retro. Rules remain in force; consult this file when an old rule may
apply.

## L-001 — 2026-11-02 — Environment variables do not reach running processes
Situation: `PIXELLAB_API_KEY` was set at machine scope, yet every MCP call
returned `401 Missing Authorization header`. Restarting the app and the service
changed nothing.
Worked: sending a deliberately invalid literal token returned `401 Invalid API
token`, which proved headers were transmitted and isolated the fault to an empty
`{env:...}` substitution.
Failed: assuming a restart re-reads the environment. Windows snapshots the
environment at logon, and a service started from a stale parent inherits the
stale snapshot.
Rule: after setting an environment variable on Windows, set it with `setx`
(which broadcasts the change) and restart the entire application tree; if it
still fails, sign out or reboot before debugging further.
Evidence: `401 Missing Authorization header` versus `401 Invalid API token`.

## L-002 — 2026-11-02 — Verify a vendor's MCP surface before designing around it
Situation: the audio pipeline was planned against the ElevenLabs hosted MCP
server, which turned out to expose agent-management tools only. The local MCP
server that did generate audio was archived in September 2026.
Worked: reading the vendor docs and the archived repository's warning before
writing any scripts.
Failed: assuming "vendor provides an MCP server" implies "the creative APIs are
exposed through it".
Rule: enumerate the server's tools and confirm the exact capability you need
before committing a pipeline to it. Prefer a stable REST endpoint over a young
or archived MCP server.
Evidence: `elevenlabs.io/docs/agents-platform/operate/hosted-mcp`;
`github.com/elevenlabs/elevenlabs-mcp` deprecation notice.

## L-003 — 2026-11-02 — Free model tiers cannot sit on a critical path
Situation: the reviewer agent was configured on a free model. Its first real
dispatch failed with "Free usage limit reached", before any review happened.
Worked: catching it with a smoke dispatch before nine more agents were written
against that assumption.
Failed: planning four roles (critic, reviewer, art director, archivist) on free
models without checking quota behaviour.
Rule: no critical-path role — reviewer, gate, verifier — may depend on a free
tier. Free models are for optional helpers only.
Evidence: subagent error `Free usage limit reached`.

## L-004 — 2026-11-02 — Verify loaded agent config from the server, not the file
Situation: needed to confirm agents had parsed correctly, but the CLI has no
agent-listing command and the TUI list only shows primary agents.
Worked: `opencode api get /api/agent` returns each agent's resolved model,
variant, step cap, and fully merged permission list.
Failed: treating a file that looks correct as proof that the loader accepted it.
Rule: after writing or editing an agent, verify it with the API and compare the
resolved model, mode, and permissions against intent.
Evidence: `/api/agent` response showing `studio-lead` with 49 merged rules.

## L-005 — 2026-11-02 — A tool's exit code is not evidence until you have seen it fail
Situation: the import gate was designed around `godot --headless --import`,
assuming it would fail on a project containing a broken script.
Worked: probing a clean project and a deliberately broken one before writing the
gate script.
Failed: `--import` returned exit 0 and printed no error for a script with a parse
error. Separately, `--headless --quit` failed outright with "no main scene
defined", which would have looked like a project problem rather than a wrong flag.
Rule: before gating on an exit code, observe the command fail at least once. In
Godot 4.7 the only reliable script-syntax signal is
`--check-only --script res://path.gd`, which exits 1 and prints `SCRIPT ERROR:`.
Evidence: clean exit 0 with no error, versus exit 1 with `SCRIPT ERROR: Parse Error`.

## L-006 — 2026-11-02 — Single-pass loudnorm undershoots the target
Situation: normalising a fixture to -16 LUFS with a single `loudnorm=I=-16` pass
produced -19.33 LUFS, and the audio gate correctly rejected it.
Worked: the gate measured the shipped file rather than trusting the conversion
step that produced it.
Failed: assuming the filter hits its target. Single-pass loudnorm estimates from
a short window and misses by several LU, more on short clips.
Rule: normalise in two passes — measure with `loudnorm=print_format=json`, then
apply the measured values — and always verify the result with the gate.
Evidence: `audio.ps1` reporting -19.33 LUFS against a -16 target.

## L-007 — 2026-11-02 — Measure the format you actually ship
Situation: the audio pipeline measured a stereo file, then encoded it to mono,
and the delivered clip landed 3 dB below its target. The correction had been
computed against audio that no longer existed.
Worked: comparing the measured value against the produced value exposed the
discrepancy immediately.
Failed: treating channel count as an encoding detail rather than part of the
signal being measured.
Rule: fix sample rate and channel layout before measuring loudness, and never put
a format conversion between the measurement and the encode.
Evidence: measured -14.9 LUFS, corrected by -1.1 dB, delivered -19.1 LUFS.

## L-008 — 2026-11-03 — PowerShell variable names are case-insensitive
Situation: the scaffold script took a `-Pack` parameter, then assigned the parsed
pack metadata to `$pack`. The assignment silently overwrote the parameter, and
every field read back empty.
Worked: printing the parsed values exposed `pack: v` with no name or version,
which no amount of reading the code had revealed.
Failed: assuming a conventionally lowercase local variable can sit safely next to
a capitalised parameter with the same letters.
Rule: never shadow a parameter with a different-case name; give parsed or derived
values distinctly different names.
Evidence: `new-project.ps1` reporting `pack: v` instead of `godot-2d v1.0.0`.
