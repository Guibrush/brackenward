# G0 — Concept — Result

> **Signature:** this gate was signed on 2026-11-04 by Guybrush Threepwood in
> `docs/gates/G0-concept.md`, which holds the canonical signature record. This file is the
> evidence snapshot and is not re-signed. See "Where the signature lives" in
> `docs/gates/README.md`.

Gate: G0 — Concept
Run date: 2026-11-04
Commit: none — project root is not a git repository (`git rev-parse HEAD` → `fatal: not a git repository or any of the parent directories`)
Run by: gatekeeper (automated). Human signature: **not granted**.

## Script criteria

| Check ID | Criterion (type) | Command | Exit code | Result |
| --- | --- | --- | --- | --- |
| G0.1 | Charter is complete: pitch, audience, three pillars, non-goals, core loop, fun hypothesis, scope budget, codename candidates (`script`) | `powershell -NoProfile -File scripts/gate/charter.ps1` | 0 | pass |
| G0.4 | Scope budget contains numbers, not intentions (`script`) | `powershell -NoProfile -File scripts/gate/charter.ps1` | 0 | pass |
| G0.5 | Non-goals has at least three entries (`script`) | `powershell -NoProfile -File scripts/gate/charter.ps1` | 0 | pass |
| G0.6 | Style is locked: palette hexes, tile size, outline rule, light direction, projection, max colours (`script`) | `powershell -NoProfile -File scripts/gate/style.ps1` | 0 | pass |
| G0.8 | Audio guide is complete: format rules, loudness targets, loop policy, naming, budgets (`script`) | `powershell -NoProfile -File scripts/gate/audio_spec.ps1` | 0 | pass |

All three named scripts were executed. Every sub-check reported PASS; none was skipped, errored, or missing. Exit codes were observed directly (`$LASTEXITCODE`), not inferred.

## Human criteria — UNSIGNED

These criteria cannot be evidenced by script and remain pending until a human signs.

| Check ID | Criterion (type) | Status |
| --- | --- | --- |
| G0.2 | "The three pillars are distinct and each names how the player feels it" (`human`) | UNSIGNED — pending human review |
| G0.3 | "The fun hypothesis could be proven wrong" (`human`) | UNSIGNED — pending human review |
| G0.7 | "The locked palette is coherent and the projection suits the intended gameplay" (`taste`) | UNSIGNED — pending human review. Note: the human has approved `art/style/anchor.png`; that approval is theirs and is not transferred to this report |
| G0.9 | "Three codename candidates exist, each valid as a repository name (lowercase, hyphenated, no trademark)" (`human`) | UNSIGNED — pending human review |
| G0.10 | "The charter's scope is believable for the stated calendar budget" (`taste`) | UNSIGNED — pending human review |

## Raw script output (verbatim)

### `powershell -NoProfile -File scripts/gate/charter.ps1` — exit 0

```
G0 - charter
  [PASS ] G0.1    Required sections present - 8 sections
  [PASS ] G0.4    No placeholders left in the document
  [PASS ] G0.5    Non-goals has at least three entries - 8 entries
  [PASS ] G0.4.b  Scope budget table is filled in - 9 rows
  [PASS ] G0.2.s  Three pillars are numbered - 3 entries

G0 charter: 5 pass, 0 fail, 0 blocked
```

### `powershell -NoProfile -File scripts/gate/style.ps1` — exit 0

```
G0 - style
  [PASS ] G0.6    All locked parameters are present - 7 parameters
  [PASS ] G0.6.p  Palette is a concrete hex list - 16 colours declared
  [PASS ] G0.6.t  No placeholders left in the style guide
  [PASS ] G0.6.a  Style anchor image present - 64x64

G0 style: 4 pass, 0 fail, 0 blocked
```

### `powershell -NoProfile -File scripts/gate/audio_spec.ps1` — exit 0

```
G0 - audio specification
  [PASS ] G0.8    Required sections present - 6 sections
  [PASS ] G0.8.f  WAV and OGG are both specified
  [PASS ] G0.8.l  Loudness targets are measurable - LUFS and dBTP present
  [PASS ] G0.8.o  Loop policy requires an after-processing check
  [PASS ] G0.8.t  No placeholders left in the audio guide

G0 audio spec: 5 pass, 0 fail, 0 blocked
```

## Context (not criteria)

- `docs/adr/0002-g2-slice-is-a-full-run.md` — Status: `proposed — awaiting human signature at G0`
- `docs/adr/0003-no-calendar-budget.md` — Status: `proposed — awaiting human signature at G0`
- `docs/adr/0001-engine-version-policy.md` — Status: `accepted`
- The G0 signature block in `docs/gates/G0-concept.md` is empty (Signed by / Date / Commit / Codename chosen all `—`).

## Verdict

G0 scripts: all pass (14/14 sub-checks across the three scripts). However, **the gate cannot pass until the human signs**: G0.2, G0.3, G0.7, G0.9, and G0.10 are human/taste criteria still unsigned, both G0 ADRs await human signature, and the G0 signature block is empty. This report does not sign and does not declare the gate passed.

## Spend

0 generations, 0 credits — this run cost nothing.
