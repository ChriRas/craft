---
description: Phase 8 — atomic commits, decisions promotion dialog, slice archive write, plan file deletion. The slice closes here.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob"]
---

# /commit — Phase 8 Commit & Cleanup

## Purpose

Close the slice properly: split changes into atomic commits with Conventional Commits + `Slice:` footers, surface decisions for promotion to `intent.md` / `rules.md`, write the slice archive entry from the Phase 6 recap, and delete the ephemeral plan file.

Follow `skills/workflow/SKILL.md` Phase 8 mechanics.

---

## Pre-flight

### 1. Locate active slice

- `Glob` `.claude/plans/*.md`. Expect a slice in `Status: committing` (or `refactoring` if jumping here directly).
- If none → stop with `No slice ready for commit. Run /refactor first.`

### 2. Sanity checks

- Run `git status` — confirm there are uncommitted changes.
- Run project tests one final time. If red, stop and tell the user: *"Tests are red. Phase 8 does not commit red. Fix or revert before committing."*

### 3. Read recap draft

From the slice plan's `## Recap Draft` (written in Phase 6). It feeds the slice archive entry.

---

## Procedure (Autonomy Level 1)

### Step 1 — Propose atomic commit split

- `git diff --stat` to see scope.
- Map changes to the slice's sub-tasks. Propose one commit per logical change. Order: foundation first, leaves last.

Present the proposal as a list:

```
Commit 1: feat(api): add reservation endpoint
  - app/Http/Controllers/ReservationController.php
  - routes/api.php
  - tests/Feature/ReservationApiTest.php

Commit 2: feat(pwa): reservation button with optimistic UI
  - resources/views/...
  - resources/css/...
  - tests/Feature/ReservationPwaTest.php

Commit 3: refactor(http): extract common validation trait
  - app/Http/Validation/HasReservationFields.php
  - app/Http/Controllers/ReservationController.php (use trait)

Proceed with this split? (Y / propose-different / abort)
```

If user wants a different split, iterate.

### Step 2 — Compose commit messages

For each commit:

```
<type>(<scope>): <imperative description>

<optional body — what and why, not how>

Slice: slice-<NNN>
```

- `type` ∈ `feat | fix | refactor | test | docs | chore | perf | build | ci`
- `scope` optional but encouraged
- `Slice:` footer always present

The agent proposes each message; user can edit before staging.

### Step 3 — Stage and commit

For each proposed commit in order:

1. `git add` the listed files.
2. `git commit -m "$(cat <<'EOF' ... EOF)"` with the composed message (HEREDOC to preserve formatting).
3. Capture the resulting commit hash.

### Step 4 — Decisions promotion dialog

Walk through every entry in the slice plan's `## Decisions Made During This Slice` section, one at a time:

```
Decision: "<text of the decision>"
  Promote to: [K]eep in slice archive / [I]ntent / [R]ules / [D]iscard
```

- **K** — Default; record in slice archive only.
- **I** — Propose diff to `.claude/project/intent.md`. User confirms diff (Level 0) before writing.
- **R** — Propose diff to `.claude/project/rules.md`. User confirms diff (Level 0) before writing.
- **D** — Discard; not recorded anywhere.

Skipped entries default to K.

### Step 5 — Write the slice archive entry

Compose the archive entry from `templates/slice-archive.md.template`. Fill:

- Title from slice plan
- Completed date (today, ISO)
- Commits: `<first-hash>..<last-hash>` and PR number if one was created
- What (from `## Recap Draft`)
- Why (from `## Recap Draft`)
- Decisions (only those marked K or I; D is discarded; R lives in `rules.md`)
- Diagram (from `## Recap Draft` if present)

Write to `.claude/project/slices/slice-<NNN>-<slug>.md`.

### Step 6 — Optional: open a Pull Request

If the project workflow uses PRs (check `rules.md` `## Deployment` section), ask:

> Push and open a PR for this slice?

If yes:

- `git push -u origin <current-branch>` (Level 0 — push is external)
- `gh pr create` with body summarizing the slice (What / Why / Commits)
- Capture PR number; backfill the slice archive's `## Commits` line with it.

### Step 7 — Delete the active plan file

`rm .claude/plans/slice-<NNN>-<slug>.md`. The slice archive + commits are now the durable record.

### Step 8 — Final status

Emit:

```
✓ Slice slice-<NNN> "<title>" closed.

Commits:
  <hash>  <subject>
  <hash>  <subject>
  ...

Archive: .claude/project/slices/slice-<NNN>-<slug>.md
[PR: <url>]

Recommended next: /plan to start the next slice, or /prime to refresh status.
```

---

## Output Format

The status block above. Keep it under 15 lines for the common case.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Tests red at start | Stop, refuse to commit. |
| `git status` shows no changes | Tell user: *"Nothing to commit. Did Phase 4 / Phase 7 actually run?"* Stop. |
| User aborts during split proposal | Stop cleanly; make no commits. |
| Decisions promotion: user picks `[I]` or `[R]` but rejects the proposed diff | Drop that decision back to `[K]`; do not write `intent.md` / `rules.md`. |
| Push fails (network, auth) | Stop after writing the archive; tell user the commits exist locally and how to push manually. Do not delete the plan file yet. |
| PR creation fails | Same as push fail: archive written, plan kept, user told how to recover. |

---

## What This Command Does NOT Do

- It does **not** force-push, rebase, or amend prior commits.
- It does **not** silently promote decisions. Every promotion to `intent.md` / `rules.md` requires explicit `[I]` / `[R]` from the user and diff confirmation.
- It does **not** commit if tests are red.
- It does **not** open a PR by default — only on user confirmation.
- It does **not** delete `_legacy/` files or any project history.
