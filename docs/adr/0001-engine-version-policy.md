# ADR-0001 — Engine version policy

Date: 2026-11-02
Status: accepted
Deciders: human

## Context

The project had no engine installed. An editor cache from Godot 4.5 existed,
which was mistaken for the current version until the download page was checked:
the current stable release is **4.7.2** (18 August 2026).

A gate criterion originally read "Godot 4.5 installed and pinned", which mixed two
different things: a one-time installation step, and an ongoing guarantee that the
engine used locally is the engine used in CI.

## Decision

1. Install the **latest stable** release at the time of installation, portable, at
   `%LOCALAPPDATA%\Programs\Godot\<version>\`.
2. The G1 criterion checks that the **latest stable release is installed**, by
   querying the Godot release API and comparing it with the local `--version`
   output. A mismatch fails the criterion.
3. The version actually in use is recorded in `docs/STATE.md` and used verbatim by
   CI, so local and CI cannot silently diverge.

## Consequences

**Intended:** when Godot ships a new stable release, G1 goes red until the engine
is upgraded. That is the policy working, not a bug. The remedy is always to
upgrade the engine — never to edit or bypass the criterion.

**Accepted cost:** a patch release can turn a gate red for reasons unrelated to
the work in progress. If this becomes noise, the fix is a documented change to
this ADR (for example, tolerating patch drift while requiring minor versions),
not a quiet edit to the script.

**Reproducibility:** CI pins the exact version recorded at the last gate, so a
gate result remains meaningful even after a newer release appears.

## Rejected alternatives

**Pin a fixed version forever.** More reproducible, but drifts from security and
platform fixes, and the human explicitly prefers tracking current releases.

**Remove the engine criterion entirely.** It was the only assertion that the
engine on this machine and the engine in CI are the same. Removing it would let
"works on my machine" back in through the front door.

## Technical findings from the installation

These shaped the gate scripts and are recorded so they are not rediscovered:

- On Windows, stdout requires `Godot_..._console.exe`; the main executable
  detaches from the console and prints nothing.
- `--headless --quit` fails with "no main scene defined" in a project that has no
  main scene. Use `--import` for asset import instead.
- **`--import` exits 0 even when a script has a parse error, and prints no
  error.** Import alone is therefore not a valid gate.
- `--headless --check-only --script res://path.gd` exits 1 on a parse error and
  prints `SCRIPT ERROR:`. This is the only reliable syntax gate.
