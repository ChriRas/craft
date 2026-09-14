---
description: Phase 9 — atomic commits, decisions promotion dialog, slice archive write, plan file deletion. On a pull-request + Protected-main profile it opens a PR and merges via gh only after a GitHub approval ("Freigabe ≠ Merge"). The slice closes here.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob"]
---

# /craft:commit — Phase 9 Commit & Cleanup

## Purpose

Close the slice properly: split changes into atomic commits with Conventional Commits + `Slice:` footers, surface decisions for promotion to `intent.md` / `rules.md`, write the slice archive entry from the Phase 6 recap, and delete the ephemeral plan file.

This command is a **durable-state mutation** (git history, project knowledge files, slice archive, plan deletion) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`. Follow that skill for Phase 9 mechanics.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

### Step 1 — Locate active slice

<!-- craft:reads status=committing -->
- `Glob` `.claude/plans/*.md`. Identify the slice expected to be in `Status: committing` (or `awaiting-approval`, completing a protected-main PR). Pre-Assertion A2 below aborts on anything else.

This step is informational. The Pre-Assertions enforce that a single, valid slice plan is present.

### Step 2 — Hold the recap draft

If a slice plan is found, read its `## Recap Draft` section (written in Phase 6). It will feed the slice archive entry. Empty/missing recap is caught by the Pre-Assertions.

---

## Pre-Assertions

Run all of the following. Any failure stops the command before any commit, archive write, or deletion happens.

### A0 — Running from the main checkout

`Bash` `git rev-parse --show-toplevel` and compare against the path of the **first** entry in `git worktree list --porcelain` (the primary worktree). They must match.

Failure → abort: *"Run `/craft:commit` from the main checkout, not from inside a worktree. `cd` to `<main-path>` first."*

This guards the Mode-Detection logic below — every mode requires `main` as the operating context.

### A1 — Exactly one active slice ready for commit

`Glob` `.claude/plans/*.md`.

- Zero matches → abort: *"No active slice plan found. Phase 9 requires a slice in `Status: committing`. Did the earlier phases actually run?"*
- More than one match → the target is the **single plan at `Status: committing` or `awaiting-approval`** (the other plans are not ready to land — e.g. a parent epic plan, or sibling slices during a `sequential`-epic run). If **exactly one** plan is at that status, record it as `<slice-plan>` and continue. If **zero or more than one** plan is at that status, abort with the list and ask the user to specify which slice to commit (this command does not auto-pick).
- Exactly one match → record the plan path as `<slice-plan>`.

### A2 — Plan frontmatter is valid

Parse the frontmatter of `<slice-plan>`. Required fields: `Slice-ID:`, `Status:`, `Phase:`.

<!-- craft:reads status=awaiting-approval -->
- `Status:` must be `committing` (a slice cleared by `/craft:review`) **or** `awaiting-approval` (completing an already-opened protected-main PR — Step 6, second invocation). Any other value → abort: *"Plan `<plan>` has `Status: <X>`. Phase 9 requires `committing` (reached when `/craft:review` clears the slice) or `awaiting-approval` (a protected-main PR waiting for its approval to be merged). Run `/craft:review` first (or, when `Status: awaiting-release`, `/craft:release` then the remaining phases)."*

### A3 — Working state matches the detected mode

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tree-dirt-state.sh"
```

Which of CRAFT's own files — plans, ID counters, local state — do not count as uncommitted work is defined once, in that helper (`DIRTY=yes|no`, one `DIRT=` line per counted change). A helper that cannot run (non-zero exit) fails A3.

- **Standard mode**: it must report `DIRTY=yes` (there are uncommitted changes to commit). Hold its `DIRT=` lines — P2 needs them to tell a change the human keeps out of Step 1's split from one Phase 9 left behind. If `DIRTY=no` → abort: *"Nothing to commit. Did Phase 4 / Phase 7 / Phase 8 actually run?"*
- **Slice-finalize / Epic-finalize mode**: it must report `DIRTY=no` AND the corresponding worktree+branch from Mode Detection must exist. If `main` has uncommitted work AND a finalize mode was detected → abort: *"Working tree on `main` has uncommitted changes while a finalize-mode worktree is also present. Commit or stash the main-side changes before finalizing."*
- **Protected-main PR completion** (any mode; **takes precedence** whenever `Status: awaiting-approval` — Step 6, second invocation): the commits + archive already landed on the first invocation, so the tree is expected **clean**. Skip the non-empty check; this invocation only detects the PR approval and merges via `gh`.

### A4 — Tests green

Run the project's test command (derived from `rules.md` `## Test Strategy` / `## Stack & Tools`, or asked from the user if not derivable).

- Tests green → continue.
- Tests red → abort: *"Tests are red. Phase 9 does not commit red. Fix or revert before committing."*
- Test command cannot be determined → ask the user once; if no answer, abort with *"Test strategy unclear — Phase 9 cannot verify green. Add a test command to `rules.md` or run tests manually and re-invoke."*

### A5 — Recap draft present and non-empty

The slice plan must contain a `## Recap Draft` section with content.

- Empty or missing → abort: *"Recap draft missing from `<plan>`. Run `/craft:recap` (Phase 6) before /craft:commit."*

### A6 — Protected-main needs a branch to open a PR from

This catches only the **Standard-mode-on-the-trunk** case — a direct commit on the trunk
with no branch to open a PR from. Abort **before any commit** only when **all** hold: the
profile's `Merge → Type` is `pull-request` with `Protected-main: yes`; **and**
`git worktree list --porcelain` shows **only the primary worktree** (no finalize worktree);
**and** `git branch --show-current` equals the trunk (`main` or the configured trunk):
*"Protected-main opens a PR from a branch, but you are on `<trunk>` directly with no branch
to land. Run the slice via `/craft:execute` (worktree) or in-place so there is a branch, or
set `Merge → Type: direct`."*

The **worktree guard is essential**: a finalize-mode run executes from the primary checkout
(A0), whose current branch **is** the trunk, but its slice/epic branch lives in a *separate*
worktree — the second worktree's presence excludes it from A6 (it genuinely has a branch to
PR). An in-place run is on its own branch in the primary checkout (current branch ≠ trunk),
so it passes. A slice already at `Status: awaiting-approval` likewise sits on its PR branch
(in-place) or still has its finalize worktree — it passes. Only a genuine Standard commit
directly on the trunk trips A6. Running this before Step 1 ensures no commits land on a trunk
that then cannot be pushed.

---

## Mode Detection

`/craft:commit` runs in one of three modes. Run this detection **before Step 1** and pick the matching procedure path. Run it from the **main checkout**, not from inside a worktree.

- **Standard mode** — changes are uncommitted on the **current branch**: usually `main` with no `/craft:execute` run, but also a `<slice-id>-<slug>` branch when a slice was built in-place on a branch in the main checkout (an in-place single slice, or a sequential-epic slice under `pull-request` + `Protected-main: yes` — A6 needs that branch to open the PR from). Follow Steps 1–7 exactly as written below.
- **Slice-finalize mode** — `/craft:execute <slice-NNN>` has completed; a worktree at `../<repo>-worktrees/<slice-id>-<slug>/` holds the slice-branch with `Status: committing` (first pass) or `awaiting-approval` (protected-main PR completion, second pass) and a clean tree. Follow Steps 1a, 2, 4, 5, 5b, 6, 7 (with the merge in Step 1a replacing Step 1's atomic split — the orchestrator already committed the sub-task work inside the worktree).
- **Epic-finalize mode** — `/craft:execute <epic-NNN>` has completed; an `epic-<NNN>-<slug>` worktree exists with every contained slice already merged in. Follow Steps 1b, 2, 4, 5, 5b, 6, 7. The decisions walk in Step 4 runs once per included slice.

Detection logic:

1. `Bash` `git worktree list --porcelain`. If only the main worktree exists, mode = Standard.
2. Otherwise, for each non-main worktree, look up the matching plan file under `.claude/plans/`.
   - Branch starts with `epic-` and the epic plan exists with all decomposition entries archived/merged → Epic-finalize mode (the matching epic-worktree is the merge source).
   - Branch matches `slice-<NNN>-<slug>` and the slice plan has `Status: committing` **or** `awaiting-approval` (protected-main PR completion) → Slice-finalize mode.
   - Anything else → fall through. If multiple plausible modes match, ask the user which one to finalize (defensive — should not happen in normal flow).

When the protected-main PR gate has opened a PR (Step 6, first pass), the finalize target's
plan carries `Status: awaiting-approval`: the slice plan for lone-slice / Slice-finalize, or
the epic plan for Epic-finalize (that plan is the Epic-finalize target for the second pass).

If the user invokes `/craft:commit` from inside a worktree, refuse: *"Run `/craft:commit` from the main checkout, not from inside a worktree. `cd` to `<main-path>` first."*

---

## Procedure (Autonomy Level 1)

### Step 0 — Protected-main PR completion short-circuit

**If the finalize target's plan (the slice plan, or the epic plan in Epic-finalize) has
`Status: awaiting-approval`**, this invocation is the **second pass** of the protected-main
PR gate (Step 6): the commits, the decisions promotion, and the archive already landed on the
first pass. **Skip Steps 1–5b entirely** and go straight to Step 6's
*Second invocation* branch, then Step 7. Do **not** re-propose a commit split, re-walk the
`[K]/[I]/[R]/[D]` dialog, or re-write and re-commit the archive.

Otherwise (`Status: committing`) run Steps 1–7 normally.

### Step 1 — Propose atomic commit split (Standard mode only)

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

### Step 1a — Slice-branch merge (Slice-finalize mode)

The slice-branch already contains all sub-task commits authored inside the worktree by `/craft:execute`. There is nothing to split.

**Protected-main gate:** if the profile's `Merge → Type` is `pull-request` with `Protected-main: yes`, do **not** run the direct merge below — leave the slice-branch unmerged and land it via the Step 6 PR gate instead (continue with Step 2, Steps 4–5b, then Step 6). Otherwise (`Type: direct`, the default) merge the branch into `main`:

```
git checkout main
git merge --no-ff <slice-id>-<slug> -m "Merge <slice-id>: <slice-title>"
```

If the merge produces conflicts (rare — main should be ahead of the slice's fork point only by other merges, not by hand-edits), surface them and stop. Do not auto-resolve. The user inspects the slice worktree and decides whether to rebase the slice-branch onto current main and retry, or escalate.

After a clean merge, skip directly to Step 2 with the merge commit as the single commit hash to record. Decisions promotion (Step 4) still runs.

### Step 1b — Epic-branch merge (Epic-finalize mode)

The epic-branch already contains the per-slice merge commits authored by `/craft:execute` (slice-branches merged with `--no-ff` into the epic-branch inside its worktree).

**Protected-main gate:** if the profile's `Merge → Type` is `pull-request` with `Protected-main: yes`, do **not** run the direct merge below — leave the epic-branch unmerged and land it via the Step 6 PR gate instead (one PR for the whole epic-branch → `main`, per `Approval-granularity: auto`; continue with Step 2, Steps 4–5b, then Step 6). Otherwise merge the epic-branch into `main`:

```
git checkout main
git merge --no-ff epic-<NNN>-<slug> -m "Merge epic-<NNN>: <epic-title>"
```

Conflict handling is the same as Step 1a. After a clean merge, skip to Step 2; record the epic-branch's merge commit plus all contained slice-merge commits as the slice/epic's commit footprint. Decisions promotion (Step 4) walks each included slice's `## Decisions Made During This Slice` section in turn, and additionally walks the epic plan's `## Decisions Made During This Epic`.

### Step 2 — Compose commit messages

For each commit:

```
<type>(<scope>): <imperative description>

<optional body — what and why, not how>

Slice: slice-<NNN>
<Co-Authored-By: Claude <noreply@anthropic.com> — only when the profile enables it>
```

- `type` ∈ `feat | fix | refactor | test | docs | chore | perf | build | ci`
- `scope` optional but encouraged
- `Slice:` footer always present
- **Co-Authored-By trailer** — read the `Co-Authored-By` field of the `## Commit Policy` block in `.claude/project/craft-profile.md` (default `off` when the profile, the block, or the field is absent). When `on`, append the literal trailer line `Co-Authored-By: Claude <noreply@anthropic.com>` below the `Slice:` footer of **every** commit in this run; when `off`/absent, omit it entirely. The trailer is always literal, regardless of the commit language.
- **Language** — write the description and body in the project's commit language: the `Commits` key of the `## Operational Language` block in `.claude/project/craft-profile.md` (default English when the profile, the block, or the key is absent). The `type`, `scope`, and `Slice:` footer are always literal regardless of language.

The agent proposes each message; user can edit before staging.

### Step 3 — Stage and commit

For each proposed commit in order:

1. `git add -- <listed files>`.
2. `git commit -m "$(cat <<'EOF' ... EOF)" -- <listed files>` with the composed message (HEREDOC to preserve formatting) — a pathspec commit, like Step 5b's, so anything else already staged (a human's change, a leftover staged deletion) stays out of the slice's commits.
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

**A promotion target the human is already editing.** Before writing an `[I]` / `[R]` diff, check A3's held `DIRT=`
lines: when `intent.md` / `rules.md` already carries an uncommitted change of the human's, Step 5b would commit that
change together with the promotion under a `docs(...)` subject the human never saw. Say so and let the human commit or
stash their edit first, or keep the decision as `[K]`.

**Where Steps 4 and 5 write.** Into the checkout of the branch that lands, so Step 5b can commit
there: the main checkout, except in a **finalize mode under `Type: pull-request` + `Protected-main:
yes`**, where the slice/epic worktree holds the branch the PR carries — write the `intent.md` /
`rules.md` promotions and the archive entry in that worktree instead.

### Step 5 — Write the slice (and, in Epic-finalize mode, epic) archive entry

For each closing slice, compose the archive entry from `templates/slice-archive.md.template`. Fill:

- Title from slice plan
- Completed date (today, ISO)
- Commits: `<first-hash>..<last-hash>` and PR number if one was created
- What (from `## Recap Draft`)
- Why (from `## Recap Draft`)
- Decisions (only those marked K or I; D is discarded; R lives in `rules.md`)
- Follow-ups → `## Follow-ups` — the lines `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-findings-state.sh" <slice plan> --followups` prints (`FOLLOWUP=<ID> <severity> · <fix-nature> · <description>[ — <note>]`, one per `follow-up → slice archive` line of `## Review Findings`); none → omit the section. A `FOLLOWUP_MALFORMED=<ID>` line, or a helper that cannot run, means a follow-up could not be read — surface it and ask the human for the line before writing the archive, never drop it silently
- Diagram (from `## Recap Draft` if present)

Write each to `.claude/project/slices/slice-<NNN>-<slug>.md`.

In **Epic-finalize mode**, also write an epic-level archive entry at `.claude/project/slices/epic-<NNN>-<slug>.md` summarizing the epic's Vision, the list of included slices (linked by ID), and any epic-level decisions promoted in Step 4. The per-slice archive entries link back to the epic archive.

### Step 5b — Commit the record

`/craft:commit` leaves no file of its own uncommitted — Post-Assertion P2 requires a clean tree,
and a `/craft:execute` re-run after `s0` must not find this slice's record as dirt (B13). Commit
what Steps 4 and 5 wrote, in the checkout they wrote it in, as separate `docs` commits composed
and confirmed like Step 2's:

1. Each promoted file — `docs(intent): <subject>` for `.claude/project/intent.md`,
   `docs(rules): <subject>` for `.claude/project/rules.md` (only when Step 4 wrote it).
2. The archive — `docs(slices): archive slice-<NNN> (<short title>)` with every archive entry
   Step 5 wrote (in Epic-finalize mode, the epic archive in the same commit).

Commit each with a pathspec — `git add -- <files>` then `git commit -m "…" -- <files>` — never
`-A` and never a bare `git commit`: a human's unrelated change, staged or not, stays theirs. Capture each hash
into the commit-log buffer (the archive's `Commits:` range keeps naming the work commits from
Steps 1–3, not these). A failing `git commit` stops like Step 3 does.

Under `Type: direct` the commits land on the trunk (Standard mode, and a finalize mode after its
Step 1a/1b merge) or on the in-place branch that Step 7 merges. Under `pull-request` +
`Protected-main: yes` they land on the PR branch **before** Step 6 pushes it, so the record reaches
the trunk with the approved merge and not as a direct commit.

### Step 6 — Land the branch (Merge Workflow — direct vs. protected-main PR)

How a finished slice/epic reaches `main` is driven by the profile's `## Merge Workflow`
(`Type`, `Protected-main`, `Approval`; documented defaults `direct` / `no` / `chat` when the
profile or a field is absent). The commit split / decisions / archive above already ran;
this step only decides the *landing*.

- **`Type: direct` (default)** — the branch was already merged into `main` by Step 1a/1b
  (finalize modes), or the changes were committed directly on `main` (Standard mode). Nothing
  more to do; proceed to Step 7. (`rules.md` `## Deployment` may still opt into an ad-hoc PR —
  if so, ask before pushing; that is a convenience, not the protected-main gate.)

- **`Type: pull-request` + `Protected-main: yes`** — the **"Freigabe ≠ Merge"** gate: the
  human *approves* the PR (a real review); the system merges via `gh` once the approval
  exists. (`Approval: github-pr-review` is implied by this gate — a `chat` approval is
  meaningless under branch protection.) A **two-invocation** flow (open-then-resume), keyed
  off the slice `Status:`. It needs a branch distinct from the trunk — a finalize-mode
  slice/epic branch, or an in-place branch. A Standard commit directly on the trunk has no
  branch to PR, but that case is already rejected by Pre-Assertion A6, so by Step 6 there is
  always a branch.

  Verified `gh` mechanics (`gh` 2.95.0 — never `--admin`; a plain merge *failing* until the
  approval exists **is** the gate, not a bypass):

  **First invocation** (slice `Status: committing`):
  1. `git push -u origin <branch>` (Level 0 — external).
  2. `gh pr create --base <trunk> --title "<slice/epic title>" --body "<What / Why / Commits summary>"`. Capture the PR number `#N` and URL. On the PR path there is no merge commit, so the slice archive's `## Commits` records the branch's own commit range (`<first>..<last>` on the branch) plus the PR `#N` — backfill `#N` into that line, then commit and push the backfill on the PR branch, in the checkout Steps 4–5 wrote in: `git commit -m "docs(slices): record PR #N for slice-<NNN>" -- <archive path>` and `git push`. It lands before any approval, so it dismisses no review, and the archive is not left modified for Step 7's checkout or worktree removal. A failing commit or push is handled like a failing `gh pr create` below.
  3. <!-- craft:writes status=awaiting-approval --> Set the slice plan `Status: awaiting-approval` and record `> PR: #N <url>` in the plan frontmatter — a fresh-context second invocation reads `#N` from there (failing that, derives it via `gh pr list --head <branch> --json number -q '.[0].number'`). Do **not** merge and do **not** run Step 7 — the plan file stays.
  4. Emit the awaiting-approval block (Output Format): the PR URL, that `main` is not merged, and the resume gesture — approve the PR on GitHub, then re-run `/craft:commit`.

  If `git push` or `gh pr create` fails here: do **not** set `awaiting-approval`; the commits +
  archive stand and the plan file is kept — the user reconciles manually.

  **Second invocation** (slice `Status: awaiting-approval`):
  1. Read the PR number `<N>` from the plan's `> PR:` frontmatter (or `gh pr list --head <branch> --json number -q '.[0].number'`), then `gh pr view <N> --json state,reviewDecision` — read **both** fields.
  2. `state` is `MERGED` (a prior pass merged it, or it was merged on GitHub) → skip the merge and proceed to Step 7 (cleanup). `state: CLOSED` (closed unmerged) → surface *"PR #N is closed without merging — inspect on GitHub."* and stop; the slice stays `awaiting-approval`.
  3. `state: OPEN` and `reviewDecision: APPROVED` → `gh pr merge <N> --merge` (no `--admin`; no `--delete-branch` — Step 7 owns branch/worktree cleanup, and the branch is still checked out here). On success, proceed to Step 7. Re-checking `reviewDecision` is deliberate: a code-modifying push after approval dismisses it (stale-review dismissal).
  4. `state: OPEN` but not `APPROVED` (`REVIEW_REQUIRED` / `CHANGES_REQUESTED` / `null`) → report *"PR #N not yet approved (reviewDecision=`<X>`) — approve it on GitHub, then re-run `/craft:commit`."* Change nothing; the slice stays `awaiting-approval`.
  5. `gh pr merge` fails despite `APPROVED` (e.g. a required check still pending) → surface the `gh` error and stop; the slice stays `awaiting-approval` for another re-run.

  **Granularity** (`Approval-granularity: auto`, the default): a lone slice opens one PR; a
  parallel epic opens one PR at the epic-finalize (the whole epic-branch → `main`); a
  **sequential epic opens one PR per slice** — `s3` in `/craft:execute`'s Sequential epic path
  opens it (first invocation, from the slice's `<slice-id>-<slug>` branch), and the next
  `/craft:execute <epic>` invocation's `s0` completes it (second invocation → `gh pr merge` +
  the Step 7 In-place-finalize local↔remote sync). Each slice lands on its own approved PR.

### Step 7 — Delete the active plan files and clean up worktrees

> **Protected-main PR gate:** Step 7 runs only on the **second** invocation, after `gh pr merge` succeeds (Step 6). On the first invocation the slice is left at `Status: awaiting-approval` with its plan intact — do not reach Step 7.

In **Standard mode**: `rm .claude/plans/slice-<NNN>-<slug>.md`. The slice archive + commits are now the durable record. No worktree to remove (none was created).

> **A tracked plan** (`git ls-files --error-unmatch <plan>` succeeds — the project versions its
> plans): delete it with `git rm -f` instead of `rm`, in every mode (Standard included) — `-f`
> because the plan always carries uncommitted status edits by now, and its content lives on in the
> archive — and commit the deletions of this run with a pathspec,
> `git commit -m "chore(plans): close slice-<NNN>" -- <plan paths>` (Epic-finalize: `close epic-<NNN>`),
> on the trunk, after any merge this step performs — under `Type: direct` only. Under `pull-request` +
> `Protected-main: yes` the trunk takes no direct commit: leave the staged deletion and name it in
> the output; `scripts/tree-dirt-state.sh` does not count a plan as dirt, so it blocks neither P2 nor
> a re-run. An untracked or ignored plan is simply removed.

> **In-place-finalize (a slice built in-place on a non-trunk branch):** when the landed slice
> was built in-place on a `<slice-id>-<slug>` branch in the main checkout (slice-018 in-place,
> or a `sequential`-epic slice under a `pull-request` workflow) — i.e. only the primary
> worktree exists **and** the current branch is not the trunk — return to the trunk after
> landing, so the next run starts clean on `main`:
> - `direct` workflow → the commits are on the branch; land them on the trunk:
>   `git checkout <trunk>` then `git merge --no-ff <slice-id>-<slug>`, then
>   `git branch -d <slice-id>-<slug>`.
> - `pull-request` + protected-main → the Step 6 `gh pr merge` landed the merge on the
>   **remote**, so sync local first: `git checkout <trunk>`, then `git fetch origin <trunk>`
>   and `git merge --ff-only origin/<trunk>` (so local `<trunk>` contains the merged work),
>   then `git branch -d <slice-id>-<slug>`.
> Then continue the Standard-mode cleanup (`rm` the plan). If `git branch -d` fails (unmerged
> — should not happen post-land), surface it and skip the delete. Never `-D` (force).
> (A `direct` **sequential**-epic slice builds directly on the trunk with no branch, so it
> skips this entirely — it is already on `main`.)

> **Finalize modes under `pull-request` + `Protected-main: yes`** (second pass): the approved merge
> landed on the remote only. Before removing any worktree, bring the local trunk up to date in the
> main checkout the way *In-place-finalize* above does (fetch, `--ff-only`) — that is how the archive
> and promotions Steps 4–5 wrote in the worktree reach the main checkout, where P3/P4 read them and
> a later `/craft:execute` A6 finds the archive.

In **Slice-finalize mode**: `rm` the slice plan. Then remove the worktree and delete the slice-branch:

```
git worktree remove ../<repo>-worktrees/<slice-id>-<slug>
git branch -d <slice-id>-<slug>
```

In **Epic-finalize mode**: `rm` every included slice's plan AND the epic plan. Then remove the slice-worktrees, the epic-worktree, and delete all the branches:

```
for each <slice-id>-<slug>: git worktree remove ../<repo>-worktrees/<slice-id>-<slug>
                            git branch -d <slice-id>-<slug>
git worktree remove ../<repo>-worktrees/epic-<NNN>-<slug>
git branch -d epic-<NNN>-<slug>
```

If any `git branch -d` fails (unmerged commits — should not happen at this point), surface the warning, skip the delete, and let the user inspect. Never `-D` (force).

### Step 7b — Auto-resurface blocked dependents

A slice/epic that just closed may have been the prerequisite another slice was blocked on. Once
the close is durable (Step 7 done), free the dependents:

1. Collect the **closed ID(s)**: the slice-ID just archived (Standard / Slice-finalize), or in
   Epic-finalize the epic-ID **and** every included slice-ID.
2. `Glob` `.claude/plans/*.md` and read each remaining plan's frontmatter. Match any plan whose
   `Blocker-type:` is `prerequisite-work` **and** whose `Blocked-on:` value equals one of the
   closed IDs. The `Blocker-type` guard is essential: only `prerequisite-work` puts a slice/epic-ID
   in `Blocked-on` — `external` / `decision` / `access` blockers carry **free text**, which must
   never be auto-cleared even if it happens to string-equal a closed ID (those clear only via
   `/craft:unblock`). (A `Blocked-on: (pending — …)` marker holds no ID and never matches — it must
   be back-filled via `/craft:unblock` before its prerequisite closes, or it will not
   auto-resurface. Surface a one-line reminder if a `(pending)` dependent exists for a closed
   prerequisite the user likely meant to link.)
3. For each matched dependent plan, clear the block:
   - if the plan's `Blocked-status` is not one of the six execution tokens (`implementing`,
     `testing`, `review`, `refactoring`, `reviewing`, `committing`), **skip it and warn** rather
     than restoring blindly — a corrupt resume token would strand the slice (mirrors
     `/craft:unblock` Pre-Assertion A2);
   - set `Status:` back to the plan's `Blocked-status` value;
   - remove the four on-demand blocker frontmatter fields (`Blocker-type`, `Blocked-on`,
     `Blocked-since`, `Blocked-status`);
   - mark its `## Blocker` section resolved — prepend `> Resolved: <ISO date> — <closed-id> landed`
     and keep the prose as an audit note (do not delete it).
4. Emit a notification listing each freed slice and the status it resumed at:

   ```
   ↻ Unblocked by this close:
     slice-<NNN> "<title>" → resumed at <status>   (was Blocked-on <closed-id>)
   ```

   If nothing was blocked on the closed ID(s), this step is a silent no-op.

This step never deletes or commits — it only rewrites the dependents' frontmatter/`## Blocker`
section. It is safe to run in every mode; the closed ID set is what scopes it.

---

## Post-Assertions

Run all of the following. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback (git history is durable). On the protected-main PR **first** invocation (Step 6 halts at `awaiting-approval` before Step 7), only P1–P4 apply; P5–P6 run on the second invocation after `gh pr merge`.

### P1 — All proposed commits landed

For each commit proposed in Step 1 and confirmed by the user — and each record commit (Step 5b) and plan-closing commit (Step 7) — verify the commit hash exists:

```
git cat-file -e <hash>
```

Failure → *"⚠ Commit `<hash>` (`<subject>`) is not present in git history. The split may have been interrupted. Inspect `git log` manually."*

### P2 — Working tree clean

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tree-dirt-state.sh"
```

It must report `DIRTY=no` — the work commits (Step 3), the record commits (Step 5b) and the plan-closing commit (Step 7) leave nothing of this slice behind. A remaining `DIRT=` line whose path A3 already listed and that no commit of this run touched is the human's own change, kept out of the split on purpose: report it as `ℹ Left uncommitted (yours): <paths>` — not a failure. Any other `DIRT=` line → *"⚠ Working tree is not clean after Phase 9: `<DIRT= lines>`. Uncommitted changes remain — Phase 9 commits the sub-task changes, the archive and the promotions. Inspect manually."*

### P3 — Slice archive entry exists

- `Read` `.claude/project/slices/slice-<NNN>-<slug>.md` in the checkout Steps 4–5 wrote in (**Where Steps 4 and 5 write**, Step 4): the main checkout, or — on the first pass of a protected-main finalize — the slice/epic worktree; on that mode's second pass, the main checkout after Step 7's trunk sync. Must exist and contain the headers `## What`, `## Why`, `## Commits`, `## Decisions`.

Failure → *"⚠ Slice archive entry missing or malformed at `<path>`. The plan file has not been deleted yet — recover the recap manually."*

### P4 — Decisions promotions executed as recorded

For each decision promoted to `[I]` or `[R]` in Step 4, in the same checkout P3 reads:

- `[I]` → confirm `.claude/project/intent.md` now contains the promoted text (or the user explicitly rejected the diff at Level 0, which down-grades to `[K]`).
- `[R]` → confirm `.claude/project/rules.md` now contains the promoted text (same caveat).

Failure → *"⚠ Decision `<text>` was marked for promotion to `<intent.md | rules.md>` but the file does not contain it. The decision is preserved in the slice archive; reconcile manually if needed."*

### P5 — Plan files deleted

Every plan file removed in Step 7 must no longer exist:

- **Standard / Slice-finalize**: `.claude/plans/slice-<NNN>-<slug>.md`.
- **Epic-finalize**: every included slice's plan AND `.claude/plans/epic-<NNN>-<slug>.md`.

Failure → *"⚠ Plan file still present at `<path>`. The slice did not fully close. Delete manually after confirming the archive is correct."*

### P6 — Worktrees and branches removed (finalize modes)

In Slice-finalize and Epic-finalize modes: every worktree removed in Step 7 must no longer appear in `git worktree list --porcelain`, and every deleted branch must not appear in `git branch --list <name>`.

Failure → *"⚠ Worktree `<path>` or branch `<name>` was not cleaned up. Inspect with `git worktree list` and `git branch` — `/craft:worktree-clean` can reconcile orphans."*

### P7 — Auto-resurfaced dependents are consistent (Step 7b)

For every dependent freed in Step 7b: it was a `prerequisite-work` blocker (no `external` /
`decision` / `access` blocker was cleared), its restored `Status:` equals the `Blocked-status`
it recorded **and** is one of the six execution tokens, the four on-demand blocker fields are
gone, and its `## Blocker` section carries the `> Resolved:` marker. If no dependent was blocked
on the closed ID(s), this passes vacuously.

Failure → *"⚠ Dependent `<slice>` was matched for auto-resurface but its state is inconsistent
(Status/blocker-fields/Blocker-marker). Inspect its plan before resuming it."*

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

Archive: .claude/project/slices/slice-<NNN>-<slug>.md   (committed in <hash>)
[PR: <url>]
[Plan deletion staged, not committed — protected main takes no direct commit; it is not dirt]

Recommended next: /craft:plan to start the next slice, or /craft:prime to refresh status.
```

Protected-main PR opened (awaiting approval — first invocation):

```
⏸ Slice slice-<NNN> "<title>" — PR opened, awaiting your GitHub approval
   PR:     <url>   (#N)
   Branch: <branch> → <trunk>   (main NOT merged yet)
   The commits are in the PR. Approve it on GitHub (a real review), then:

   Complete: /craft:commit    (detects the approval and merges via gh)
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
- It does **not** open a PR unless the profile asks for it. A `direct` profile never opens a PR; a `pull-request` + `Protected-main: yes` profile opens one automatically as the profile-driven landing (Step 6) — but even then it **never merges without a real GitHub approval** (no `--admin`).
- It does **not** delete `_legacy/` files or any project history.
- It does **not** auto-rollback on post-assertion failure. Git history is durable; partial state is surfaced for human reconciliation.
