# Models

One table, so a swap is one line in one file. Prices are per million tokens in
USD, from OpenRouter's catalogue on 2026-11-02. Verify before trusting them.

## Assignment

| Agent | Model | In / Out | Why |
| --- | --- | --- | --- |
| `studio-lead` | `deepseek/deepseek-v4-pro#high` | — / 1.98 | Planning and arbitration need the strongest reasoning available |
| `leads/tech` | `deepseek/deepseek-v4-pro#high` | — / 1.98 | Same |
| `leads/design` | `deepseek/deepseek-v4-pro#high` | — / 1.98 | Same |
| `leads/art` | `deepseek/deepseek-v4-pro#high` | — / 1.98 | Same |
| `eng/*`, `design/*` | `deepseek/deepseek-flash#high` | — / 0.60 | Volume work; cheap, fast, adequate |
| `art/pixel` | `deepseek/deepseek-flash#high` | — / 0.60 | Writes prompts and manifests, not code |
| `audio/*` | `deepseek/deepseek-flash#high` | — / 0.60 | Writes prompts and manifests |
| `qa/critic` | `openrouter/moonshotai/kimi-k2.6#thinking` | 0.65 / 3.41 | Different vendor from every builder, vision-capable, 262k context |
| `qa/reviewer` | `openrouter/google/gemini-3.7-flash#high` | 0.75 / 3.75 | Third vendor, strong at document ambiguity |
| `art/director` | `openrouter/google/gemini-3.7-flash#high` | 0.75 / 3.75 | Must actually see the sprites |
| `gatekeeper` | `openrouter/z-ai/glm-5.3-flash#high` | 0.03 / 0.09 | Runs scripts; the evidence is the output, not the prose |
| `archivist` | `openrouter/z-ai/glm-5.3-flash#low` | 0.03 / 0.09 | Mechanical file maintenance |

## The two invariants

1. **A reviewer never shares a model with the thing it reviews.** Builders are on
   DeepSeek; critics are on Moonshot or Google. This is the entire value of the
   review step.
2. **No critical-path role runs on a free tier.** See `L-003`.

## Swapping

Change the `model:` line in the agent file. Config is watched, no restart needed.
Three granularities: the agent file (global), a project-level override in
`opencode.jsonc`, or replacing the file with a different role.

`#variant` is a second, independent knob — `low` costs less, `thinking`/`high`
reason more. Adjusting a variant is usually better than changing the model.

## After any swap

1. Verify the loaded config: `opencode api get /api/agent`
2. Run one dispatch smoke test and confirm the envelope comes back with every
   field present.
3. If the agent is a reviewer, spot-check that it still refuses unverifiable
   claims rather than accepting them.

## Known limits

- Free tiers are capped per account, not per model (`L-003`).
- Per-agent `request` overlays (temperature) are stored but not yet sent by the
  V2 runner, so behaviour is steered by prompt, not sampling settings.
- Model choice here is capability tier plus price, not a benchmark we ran. If a
  reviewer proves soft, the cheap experiment is two critics on one artifact and
  a diff of their findings.
