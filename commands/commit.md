---
description: Phase 9 — atomic commits, decisions promotion dialog, slice archive write, plan file deletion. The slice closes here.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob"]
---

# /craft:commit — Phase 9 Commit & Cleanup

## Purpose

Close the slice properly: split changes into atomic commits with Conventional Commits + `Slice:` footers, surface decisions for promotion to `intent.md` / `rules.md`, write the slice archive entry from the Phase 6 recap, and delete the ephemeral plan file.

This command is a **durable-state mutation** (git history, project knowledge files, slice archive, plan deletion) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`. Follow that skill for Phase 9 mechanics.

---

## Pre-flight

### Step 1 — Locate active slice

- `Glob` `.claude/craft:plans/*.md`. Identify the slice expected to be in `Status: committing` (or `refactoring` if jumping here directly).

This step is informational. The Pre-Assertions enforce that a single, valid slice plan is present.

### Step 2 — Hold the recap draft

If a slice plan is found, read its `## Recap Draft` section (written in Phase 6). It will feed the slice archive entry. Empty/missing recap is caught by the Pre-Assertions.

---

## Pre-Assertions

Run all five. Any failure stops the command before any commit, archive write, or deletion happens.

### A1 — Exactly one active slice ready for commit

`Glob` `.claude/craft:plans/*.md`.

- Zero matches → abort: *"No active slice plan found. Phase 9 requires a slice in `Status: committing`. Did the earlier phases actually run?"*
- More than one match → abort with the list and ask the user to specify which slice to commit (this command does not auto-pick).
- Exactly one match → record the plan path as `<slice-plan>`.

### A2 — Plan frontmatter is valid

Parse the frontmatter of `<slice-plan>`. Required fields: `Slice-ID:`, `Status:`, `Phase:`.

- `Status:` must be `committing` — the state `/craft:review` (Phase 8) writes when a slice clears review. Any other value → abort: *"Slice `<plan>` has `Status: <X>`. Phase 9 requires `committing`, reached when `/craft:review` (Phase 8) clears the slice. Run `/craft:review` first."*

### A3 — Uncommitted changes present

```
git status --porcelain
```

If the output is empty → abort: *"Nothing to commit. Did Phase 4 / Phase 7 / Phase 8 actually run?"*

### A4 — Tests green

Run the project's test command (derived from `rules.md` `## Test Strategy` / `## Stack & Tools`, or asked from the user if not derivable).

- Tests green → continue.
- Tests red → abort: *"Tests are red. Phase 9 does not commit red. Fix or revert before committing."*
- Test command cannot be determined → ask the user once; if no answer, abort with *"Test strategy unclear — Phase 9 cannot verify green. Add a test command to `rules.md` or run tests manually and re-invoke."*

### A5 — Recap draft present and non-empty

The slice plan must contain a `## Recap Draft` section with content.

- Empty or missing → abort: *"Recap draft missing from `<plan>`. Run `/craft:recap` (Phase 6) before /craft:commit."*

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

If user wants a different split, iterate. Abort → clean exit, no mutation.

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
3. Capture the resulting commit hash. Record in the commit-log buffer.

If any `git commit` fails (e.g., pre-commit hook), stop immediately. The commits made so far stand; record the failure and emit a partial-completion block in Output Format.

### Step 4 — Decisions promotion dialog

Walk through every entry in the slice plan's `## Decisions Made During This Slice` section, one at a time. Present the `[K]/[I]/[R]/[D]` menu with its full legend — each letter, its meaning, its effect — every time, per the lettered-choice-prompt convention in `skills/workflow/SKILL.md`:

```
Decision: "<text of the decision>"
  Promote to: [K]eep in slice archive / [I]ntent / [R]ules / [D]iscard
```

- **K** — Default; record in slice archive only.
- **I** — Propose diff to `.claude/project/intent.md`. User confirms diff (Level 0) before writing.
- **R** — Propose diff to `.claude/project/rules.md`. User confirms diff (Level 0) before writing.
- **D** — Discard; not recorded anywhere.

Skipped entries default to K. Record the chosen disposition for each decision; Post-Assertion P4 verifies the writes that should have happened.

### Step 5 — Write the slice archive entry

Compose the archive entry from `templates/slice-archive.md.template`. Fill:

- Title from slice plan
- Completed date (today, ISO)
- Commits: `<first-hash>..<last-hash>` and PR number if one was created
- What (from `## Recap Draft`)
- Why (from `## Recap Draft`)
- Decisions (only those marked K or I; D is discarded; R lives in `rules.md`)
- Follow-ups → `## Follow-ups` (the light + needs-rethinking findings from the slice plan's `## Review Findings`, if any)
- Diagram (from `## Recap Draft` if present)

Write to `.claude/project/slices/slice-<NNN>-<slug>.md`.

### Step 6 — Optional: open a Pull Request

If the project workflow uses PRs (check `rules.md` `## Deployment` section), ask:

> Push and open a PR for this slice?

If yes:

- `git push -u origin <current-branch>` (Level 0 — push is external)
- `gh pr create` with body summarizing the slice (What / Why / Commits)
- Capture PR number; backfill the slice archive's `## Commits` line with it.

If push or PR creation fails: do **not** proceed to Step 7. The commits exist locally, the archive is written, the plan file is still present — the user reconciles manually.

### Step 7 — Delete the active plan file

`rm .claude/craft:plans/slice-<NNN>-<slug>.md`. The slice archive + commits are now the durable record.

---

## Post-Assertions

Run all five. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback (git history is durable).

### P1 — All proposed commits landed

For each commit proposed in Step 1 and confirmed by the user, verify the commit hash exists:

```
git cat-file -e <hash>
```

Failure → *"⚠ Commit `<hash>` (`<subject>`) is not present in git history. The split may have been interrupted. Inspect `git log` manually."*

### P2 — Working tree clean

```
git status --porcelain
```

Output must be empty. Anything else → *"⚠ Working tree is not clean after Phase 9: `<porcelain output>`. Uncommitted changes remain — Phase 9 expected all sub-task changes to be staged. Inspect manually."*

### P3 — Slice archive entry exists

- `Read` `.claude/project/slices/slice-<NNN>-<slug>.md`. Must exist and contain the headers `## What`, `## Why`, `## Commits`, `## Decisions`.

Failure → *"⚠ Slice archive entry missing or malformed at `<path>`. The plan file has not been deleted yet — recover the recap manually."*

### P4 — Decisions promotions executed as recorded

For each decision promoted to `[I]` or `[R]` in Step 4:

- `[I]` → confirm `.claude/project/intent.md` now contains the promoted text (or the user explicitly rejected the diff at Level 0, which down-grades to `[K]`).
- `[R]` → confirm `.claude/project/rules.md` now contains the promoted text (same caveat).

Failure → *"⚠ Decision `<text>` was marked for promotion to `<intent.md | rules.md>` but the file does not contain it. The decision is preserved in the slice archive; reconcile manually if needed."*

### P5 — Plan file deleted

`.claude/craft:plans/slice-<NNN>-<slug>.md` must no longer exist.

Failure → *"⚠ Plan file still present at `<path>`. The slice did not fully close. Delete manually after confirming the archive is correct."*

---

## Output Format

Success:

```
✓ Slice slice-<NNN> "<title>" closed.
✓ Pre-assertions: slice ✓, tests green, recap present
✓ Post-assertions: <N> commits ✓, working tree clean, archive ✓, plan deleted

Commits:
  <hash>  <subject>
  <hash>  <subject>
  ...

Archive: .claude/project/slices/slice-<NNN>-<slug>.md
[PR: <url>]

Recommended next: /craft:plan to start the next slice, or /craft:prime to refresh status.
```

Aborted:

```
Phase 9 aborted — <reason>. No mutation occurred.
```

Partial (commit landed but post-assertions surfaced issues):

```
⚠ Phase 9 partially complete — <which assertion(s) failed>.

Commits already in history:
  <hash>  <subject>
  ...

[Archive written | plan file still present | promotion incomplete — details above]

Inspect and reconcile manually before starting the next slice.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (no slice / multiple slices) | Abort with the diagnostic message. |
| A2 fails (wrong `Status:` in plan) | Abort with hint to run the proper phase command first. |
| A3 fails (nothing to commit) | Abort. |
| A4 fails (tests red) | Abort, refuse to commit. |
| A5 fails (no recap) | Abort with `/craft:recap` recommendation. |
| User aborts during split proposal | Clean abort; no commits, no mutations. |
| `git commit` mid-loop fails (pre-commit hook) | Stop; the partial commits stand; emit the partial-completion block. Do not auto-revert. |
| Decisions promotion: user picks `[I]` or `[R]` but rejects the proposed diff | Down-grade that decision to `[K]`; do not write `intent.md` / `rules.md`. P4 treats this as expected, not a failure. |
| Push fails (network, auth) | Stop after Step 6; archive written, plan kept, user told how to push manually. Do not proceed to Step 7. |
| PR creation fails | Same as push fail: archive written, plan kept, recovery instructions emitted. |
| P1–P5 fail after the procedure | Warn loudly; emit partial-completion block; do not auto-rollback. |

---

## What This Command Does NOT Do

- It does **not** force-push, rebase, or amend prior commits.
- It does **not** silently promote decisions. Every promotion to `intent.md` / `rules.md` requires explicit `[I]` / `[R]` from the user and diff confirmation.
- It does **not** commit if tests are red.
- It does **not** open a PR by default — only on user confirmation.
- It does **not** delete `_legacy/` files or any project history.
- It does **not** auto-rollback on post-assertion failure. Git history is durable; partial state is surfaced for human reconciliation.
