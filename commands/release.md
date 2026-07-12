---
description: Release an in-place slice halted for IDE review — the explicit "I've reviewed the raw diff, proceed" gesture that resumes the slice past the pre-Phase-5 halt toward the commit. Only for slices at Status awaiting-release (set by /craft:execute in in-place mode).
argument-hint: "<slice-NNN>"
allowed-tools: ["Bash", "Read", "Edit", "Glob", "Grep"]
---

# /craft:release — Release an In-place Slice for the Rest of the Flow

## Purpose

`/craft:execute` in `Mode: in-place` builds a slice on a branch in the main checkout, makes
no commits, and **halts before Phase 5** so you can eyeball the raw uncommitted diff in your
IDE. `/craft:release` is the dedicated gesture that says *"I have reviewed the raw diff —
proceed."* It lifts the review halt and resumes the slice into Phase 5, from where the normal
flow (`/craft:test → /craft:recap → … → /craft:commit`) carries it to the
commit. The commit happens only after this release — hence "commit only on your release".

This is a **durable-flow mutation** (advances the slice `Status:`) and follows the
Pre/Post-Assertion pattern in `skills/workflow/SKILL.md`. It is distinct from
`/craft:continue` (generic phase routing) and `/craft:pause` / `/craft:handoff` (context
breaks): release is a first-class human **approval-to-proceed** checkpoint that applies only
to the in-place review halt.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the four required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

- `Read` `.claude/project/intent.md` and `.claude/project/rules.md` to confirm onboarding. If
  either is missing, tell the user to run `/craft:onboard` and stop.

---

## Pre-Assertions

Run all of the following. Any failure stops the command before any state change.

### A0 — Running from the main checkout

`Bash` `git rev-parse --show-toplevel` must equal the first entry of
`git worktree list --porcelain` (the primary worktree). In-place slices live in the main
checkout, not a worktree.

Failure → abort: *"Run `/craft:release` from the main checkout where the in-place slice was
built, not from inside a worktree."*

### A1 — Target slice resolved

- If `<slice-NNN>` is given, `Glob` `.claude/plans/slice-<NNN>-*.md`.
<!-- craft:reads status=awaiting-release -->
- Otherwise `Glob` `.claude/plans/*.md` and select the single slice at
  `Status: awaiting-release`.
  - Zero → abort: *"No in-place slice is awaiting release. `/craft:release` only resumes a
    slice halted by `/craft:execute` in in-place mode."*
  - More than one → abort with the list and ask which slice to release.

### A2 — Slice is at the in-place review halt

The target slice's frontmatter `Status:` must be `awaiting-release`. Any other value →
abort: *"Slice `<id>` has `Status: <X>`, not `awaiting-release`. `/craft:release` only
applies to an in-place slice halted before Phase 5 — use `/craft:continue` for other
phases."*

### A3 — On the slice branch

`Bash` `git branch --show-current` must equal the slice's branch (`<slice-id>-<slug>`, or the
`Branch name pattern` from `rules.md` `## Worktree Settings`).

Failure → abort: *"Expected to be on branch `<branch>` (the in-place slice branch).
`git checkout <branch>` first, or the in-place build did not complete."*

---

## Procedure (Autonomy Level 1)

### 1. Show what is being released

`Bash` `git status --short` and `git diff --stat` — surface the uncommitted in-place changes
so the release is an informed one:

```
Releasing slice-<NNN> "<title>" (branch <branch>):
  <N> files changed, +<A> / -<D>   (uncommitted, in the main checkout)

This lifts the pre-Phase-5 halt and resumes the slice into Phase 5. Nothing is
committed now — the commit happens later at /craft:commit.
Proceed? [Y] release   [N] cancel
```

On `[N]` → clean exit, no state change. On `[Y]` → continue.

### 2. Lift the halt

<!-- craft:writes status=testing -->
Set the slice plan `Status: testing` via `Edit` (resume into Phase 5). Do **not** commit,
merge, or push — the changes stay uncommitted on the slice branch exactly as they were.

### 3. Recommend the continuation

Emit the resume block (see Output Format) pointing at `/craft:test` (Phase 5). The human
drives the remaining phases; the slice's changes are committed at Phase 9 / `/craft:commit`.

---

## Post-Assertions

Run both. Any failure → warn loudly; do not pretend success.

### P1 — Status advanced

The slice plan `Status:` is now `testing`.

Failure → *"⚠ Slice `<id>` Status was not advanced to `testing`. Inspect the plan
frontmatter."*

### P2 — Changes intact, nothing committed

`git branch --show-current` still equals the slice branch, and `git status --porcelain` still
shows the slice's uncommitted changes (release never commits).

Failure → *"⚠ Working state changed unexpectedly during release — expected the uncommitted
in-place changes to remain on `<branch>`. Inspect with `git status`."*

---

## Output Format

Success:

```
✓ Released slice-<NNN> "<title>" — in-place review halt lifted.
  Branch: <branch>   (changes still uncommitted in the main checkout)
  Status: testing

Recommended next: /craft:test   (Phase 5 — exercise the artifact)
```

Cancelled:

```
Release cancelled — no state change. Slice-<NNN> stays at Status awaiting-release.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A0 fails (inside a worktree) | Abort; `cd` to the main checkout. |
| A1 finds zero awaiting-release slices | Abort; `/craft:release` is only for the in-place halt. |
| A1 finds multiple | Abort with the list; ask which slice to release. |
| A2 fails (wrong Status) | Abort; recommend `/craft:continue` for other phases. |
| A3 fails (wrong branch) | Abort; `git checkout <branch>` first. |
| User cancels at the `[Y]/[N]` prompt | Clean exit; Status stays `awaiting-release`. |
| P1/P2 fail after the edit | Warn loudly; the human reconciles manually. |

---

## What This Command Does NOT Do

- It does **not** commit, merge, or push — it only lifts the review halt. `/craft:commit`
  (Phase 9) commits, after the remaining phases run.
- **Reaching `main`:** `/craft:release` only lifts the halt; the in-place branch reaches
  `main` in Phase 9 via `/craft:commit`'s Step 7 *In-place-finalize*. On a `direct` project it
  merges `<slice-id>-<slug>` → the trunk and deletes the branch; on `pull-request` +
  `Protected-main: yes` it opens a PR, and after your GitHub approval merges via `gh` and syncs
  the local trunk. Either way the work is not stranded on the branch.
- It does **not** run Phase 5 — it hands off to `/craft:test`.
- It does **not** apply to `worktree`-mode slices — those never halt for in-place review, and
  are resumed via `/craft:continue` / re-running `/craft:execute`.
- It does **not** modify `intent.md` or `rules.md`.
