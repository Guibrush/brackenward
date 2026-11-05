# Gates

A gate is a set of criteria, each with evidence, evaluated together. A gate is
either open or closed; there is no partial pass.

## Criterion types

| Type | Decided by | Rule |
| --- | --- | --- |
| `script` | A command's exit code | No judgement. Non-zero, timeout, or missing script means **not satisfied** |
| `human` | The human, by direct observation | An agent may supply evidence, never the decision |
| `taste` | The human | Explicitly subjective. The gate does not pretend otherwise |

There is no `hybrid` type on purpose. A criterion that is "mostly measurable but
needs a judgement call" is two criteria, and splitting it is what keeps the gate
honest.

## Rules

1. **Any failing `script` criterion closes the gate**, regardless of how many
   human criteria pass.
2. **A `human` criterion with no stated observation is not passed.** "Looks
   fine" is not an observation.
3. **`gatekeeper` writes results; only the human writes the signature.** An
   agent that signs a gate has broken the process, not the tool.
4. **Gate definitions are human-owned.** Changing a criterion requires a human
   decision and an ADR in `docs/adr/`. Adjusting a gate to make work pass is the
   single most expensive habit a studio can develop.
5. **Gate results are immutable.** A re-run writes `G2-result-2.md`; it never
   overwrites the previous result.
6. **Scripts referenced here are implemented in `scripts/gate/`.** Until a script
   exists, its criterion reports `missing`, which is a failure.

## Where the signature lives

The **gate definition** (`docs/gates/G2-vertical-slice.md` and its siblings) holds
the canonical Signature block. That file is human-owned, and `gatekeeper` cannot
write to it, which is the point: the agent that produces evidence must not be able
to record the verdict.

The **result file** (`docs/gates/G2-result.md`) is the evidence snapshot written by
`gatekeeper`. It records what was run and what it returned, and it is **not
re-signed** afterwards. A result file that reads "awaiting human signature" means
"this was the state when the evidence was collected", not "this gate is unsigned".

If the two ever disagree, the definition file is authoritative.

## Result file format

`gatekeeper` writes `docs/gates/<gate>-result.md`:

```md
# G2 result

Date: 2026-11-14
Commit: a1b2c3d
Evaluated by: gatekeeper (evidence only)

| ID | Criterion | Type | Result | Evidence |
| --- | --- | --- | --- | --- |
| G2.1 | Playable for 5 minutes | script | pass | smoke.ps1 exit 0 |
| G2.8 | Fun hypothesis tested | human | pending | awaiting human |

Overall script result: pass
Signature: pending
```

The `Signature` line is written by the human, as:

```
Signature: <name> — 2026-11-14 — approved
```

## Which gates exist

| Gate | Question it answers |
| --- | --- |
| G0 Concept | Do we know what we are building and what we are not? |
| G1 Bootstrap | Can we build, test, and merge safely, end to end? |
| G2 Vertical slice | Is the core loop fun, at quality, at framerate? |
| G3 Alpha | Are all systems present and working together? |
| G4 Beta | Is the content complete and the game balanced? |
| G5 Gold | Can we ship it reproducibly and legally? |

G0 and G1 are fully specified. G2 is concrete. G3–G5 are deliberately less
detailed: writing beta criteria before the core loop exists produces paperwork
that has to be rewritten. They are reviewed and tightened at each preceding gate.
