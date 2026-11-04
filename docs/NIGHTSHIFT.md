# Night shift (not implemented)

A design stub, deliberately unimplemented. Autonomy without trustworthy gates is
just a faster way to break things, so this waits until G2.

## What it would do

Run `opencode run` on a schedule against a queue of pre-approved task types,
overnight, producing branches and pull requests that the human reviews in the
morning.

## Prerequisites before building it

1. Gates are green on demand and have been for a full milestone.
2. CI reproduces the local gate result on a clean machine.
3. `scripts/gate/*` covers every criterion that matters, so an unattended agent
   cannot declare success on unverified work.
4. A dedicated `nightshift` agent exists with the constraints below.

## Allowed unattended

Reproduce and write up a bug. Write tests for existing behaviour. Refactor
behind a green suite. Generate asset prompt lists. Triage issues. Update docs.

## Forbidden unattended

Merge to `dev` or `main`. Change gate criteria. Make design decisions. Touch a
signed-off milestone. Push, delete, or rewrite history.

## Required guardrails

- Worktree-only edits, never the main checkout.
- `git push` denied by policy for this agent.
- Cheap model, low step cap, per-run budget.
- No-progress detector: two iterations without a diff stops the run and writes a
  report instead of looping.
- Every run leaves a report at `docs/reports/nightshift-<date>.md`.

## Trigger condition

Build this only when the human has skipped a night of work because the queue was
empty, twice. Before that, the bottleneck is the brief, not the hours.
