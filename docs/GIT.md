# Git protocol

## Topology

```
main   ← only the human merges here. Stable, releasable.
 │
 └── dev           ← agents merge their PRs here once CI is green
      ├── task/T-0012-jump-tuning
      ├── task/T-0013-jump-arc
      └── task/T-0014-perf-profile
```

## Protection

| Branch | Direct push | PR required | Approvals | Status checks |
| --- | --- | --- | --- | --- |
| `main` | blocked | yes | 1 — the human | required |
| `dev` | blocked | yes | 0 — CI is the gate | required |
| `task/*` | allowed | — | — | — |

`dev` requires zero human approvals on purpose: an agent may merge its own pull
request, but only after CI passes. `main` requires a human signature, which is
where the release decision lives.

Protection is enforced by GitHub, not by our permission rules. The local policy
that denies `git push --force` is a convenience; the server is the authority.

## Creating the repository (first step of G1)

G1 starts with repository creation, and **the lead runs it, not the human**.

```powershell
powershell -NoProfile -File scripts/git/init-repo.ps1 -Name <codename> -Description "<one line>"
powershell -NoProfile -File scripts/git/init-repo.ps1 -Name <codename> -DryRun   # inspect first
```

The order inside the script is the point:

1. Validate the codename (lowercase, hyphens, 3–40 characters).
2. Check `gh` auth, `git` availability, and that `.gitignore` exists.
3. **Run the secret scan and abort if it fails** — nothing reaches GitHub before this passes.
4. `git init`, stage, one initial commit.
5. `gh repo create --public --source . --push`.
6. Create `dev` and push it.
7. Make `dev` the default branch: work lands there, releases live on `main`.
8. Run `protect.ps1` and report honestly if protection could not be applied.

The repository is public by convention. `-Visibility private` exists but branch
protection may be unavailable on a free private repository, which would leave
`main` unprotected.

Creating the repository is not the same as passing G1.1. The gate re-verifies
branches and protection independently via `repo.ps1`, because a script that
reports its own success is not evidence.

## Applying protection

```powershell
powershell -NoProfile -File scripts/git/protect.ps1 -DryRun   # show the payload
powershell -NoProfile -File scripts/git/protect.ps1           # apply and verify
```

Idempotent. It reports failure honestly when protection is unavailable on the
account tier, instead of implying it worked. Re-run it after any repository
settings change; `scripts/gate/repo.ps1` re-checks it independently.

Branch creation is scripted too, so the naming cannot drift:

```powershell
powershell -NoProfile -File scripts/git/new-task-branch.ps1 -TaskId T-0012 -Slug jump-tuning
```

## CI

`.github/workflows/gates.yml` runs on every pull request to `dev` or `main`, and on
every push to `dev`.

- **The runner is `windows-latest` on purpose.** The gate scripts use
  `System.Drawing` for the palette scan and shell out to `powershell -NoProfile -File`,
  exactly as the developer machine does. A Linux runner would exercise a different
  path and hide the divergence G1.7 exists to catch.
- **The engine is downloaded at run time**, at whatever the latest stable release
  is, matching `ADR-0001`. If the local engine is behind, `engine.ps1` fails
  locally — that is the policy working.
- **`CURRENT_GATE` in the workflow file** decides how far the suite runs. It is a
  visible line in the diff: raising the bar is a deliberate commit.
- **`repo.ps1` is skipped in CI** via `-Skip repo`. Reading branch protection needs
  admin scope a workflow token does not have. Protection is verified locally by the
  human, and G1.7 is worded accordingly.
- **The required status check name is `gates`**, which is what `protect.ps1`
  configures.

## Branch naming

`task/<task-id>-<slug>` — for example `task/T-0012-jump-tuning`. One branch per
task brief. If a branch outlives two integration cycles, the task was too big.

## Commits

Conventional Commits, one logical change per commit:

```
feat(gameplay): add coyote time and input buffer to jump
fix(audio): trim leading silence from music loops
docs(gates): define G2 vertical slice criteria
chore(tools): add ffmpeg path resolution to gate config
```

Body explains *why*, not what. The diff already says what.

## Pull requests

- Target `dev`, never `main`.
- Title matches the commit convention.
- Body contains: task ID, one-paragraph goal, definition of done, gate evidence,
  and spend if generation was involved.
- Rebase on `dev` before opening, so the diff is the work and nothing else.
- Squash merge. Delete the branch after.

## Conflicts

A merge conflict is a `BLOCKED` return to `studio-lead`, never a silent
resolution. A conflict almost always means two owners touched one path, which
violates `docs/OWNERSHIP.md` — the conflict is the symptom, and fixing the
symptom hides the cause.

## Secrets

Keys live in Windows environment variables or the credential manager. They never
appear in the repository, manifests, prompts, commit messages, or PR bodies.
`.gitignore` blocks `.env` files, and the `secrets` gate check scans staged
content for key-shaped strings.

## Releases

Tags are created on `main` by the human only. No agent creates or pushes tags.
