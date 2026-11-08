# ADR-0007 — G2.1 measures the session, not one arena

Date: 2026-11-08
Status: accepted (studio-lead; human approved the option)
Deciders: human, on studio-lead's recommendation

## Context

`G2.1` reads: *"a headless run of at least 300 s completes without a crash or an error
line"*. `smoke.ps1` implements it by taking the **last** `ARENA_SUMMARY` line and comparing
its `seconds` field against 298.

That worked while the main scene *was* one arena. It stops working now that the game boots
into a menu and a run can be won or lost: `seconds` is the lifetime of one arena instance,
and with `--autostart` restarting finished runs inside a session, the last arena is young.
Measured: a **300 s session reported `seconds 12.70`**. The gate would fail on a number that
is telling the truth about an arena and not the truth about the run.

The criterion's own wording describes the **session** — "a headless run of at least 300 s" —
not one arena instance.

## Decision

1. The **boot scene reports the session**: on quit it prints
   `BOOT_SESSION {"seconds": <elapsed>, "runs": <runs started>, "restarts": <n>}`.
2. **`smoke.ps1` reads `BOOT_SESSION.seconds`** when present and compares it to 298, exactly
   as it compared `ARENA_SUMMARY.seconds` before. When `BOOT_SESSION` is absent — an older
   build, or a scene run directly — it falls back to `ARENA_SUMMARY.seconds` so the script
   keeps working against either entry point.
3. **`G2.1.2` (no error lines) and `G2.1.3` (`stuck == 0`) are unchanged**, and still read
   `ARENA_SUMMARY` — those are properties of a level, and the last level is the right place
   to read them.
4. **The 300 s requirement stays 300 s**, and remains a constant no flag can lower.

## Consequences

**Intended:** the gate measures what the criterion says. A session that plays 17 runs for
300 s and never crashes passes; a build that dies at 40 s fails, whether it died in a run, a
restart, or the menu.

**Accepted cost:** the gate now depends on a line the boot must print. If someone removes
it, `smoke.ps1` silently falls back to arena age and the criterion quietly weakens. Mitigated
by the gate printing **which source it used** in its own output, so a fallback is visible
rather than assumed.

**Not changed:** the criterion text in `docs/gates/G2-vertical-slice.md`. This ADR changes
the measurement source, not the requirement.

## Rejected alternatives

**Keep one arena alive for the whole session.** Would restore the old semantics but requires
the arena to survive 300 s, which today's difficulty curve does not allow — runs end at
about 17 s. That is a tuning decision masquerading as a gate decision.

**Have `smoke.ps1` run `scenes/main.tscn` directly.** Cheapest, and rejected because the
gate would then test a scene the player never sees first: the menu and the boot are part of
what must not crash for 300 s.
