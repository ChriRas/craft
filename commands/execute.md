---
description: Autonomously execute an epic or single slice. Parallel worktree mode (default) creates parallel git worktrees and delegates Phase 4–7 to subagents per slice, merging into an epic-branch; in-place mode builds a single slice on a branch in the main checkout, halts before Phase 5 for IDE review (resumed via /craft:release); sequential epic mode runs an epic's slices one-by-one in place, landing each per slice — committed directly on the trunk (direct) or via an approved PR (pull-request/protected-main) — with a review halt between.
argument-hint: "<epic-NNN | slice-NNN>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Task"]
---

# /craft:execute — Autonomous Build Orchestrator

## Purpose

Turn a planned epic (or a single planned slice) into shipped code without per-phase user intervention. Spawns one git worktree per runnable slice, runs Phases 4–7 inside each via the `slice-builder` subagent, merges slice-branches into a dedicated epic-branch as they complete, and stops for human review only at epic-end (or after each slice if the epic's `## Review Checkpoints` opts in).

This command is a **durable-state mutation** (creates worktrees, branches, merge commits; updates slice/epic plans) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`.

For a single slice without an epic, the orchestrator runs the same loop with one worktree; the final merge target is `main` rather than an epic-branch.

---

## Pre-flight

### Step 1 — Hold project knowledge

- `Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Hold both in context.
- `Read` the project's `## Worktree Settings` section in `rules.md`, if present. Note any overrides for `Worktree path pattern` or `Branch name pattern`; otherwise use defaults (`../<repo>-worktrees/<slice-id>-<slug>/` and `<slice-id>-<slug>`).
- `Read` `.claude/project/craft-profile.md`, if present. Note `Execution → Mode` (`worktree` | `in-place`), `Commit Policy → Auto-commit` (`on` | `off`), and `Epic Mode → Default` (`parallel` | `sequential`). When the profile or a field is absent, apply the documented defaults — `Mode: worktree`, `Auto-commit: on`, `Epic Mode: parallel` (see `craft-profile-defaults.md`). In Procedure step 1b, `Execution → Mode` selects the path for a **single-slice** target and `Epic Mode` for an **epic** target.

### Step 2 — Resolve target

The argument is `epic-NNN` or `slice-NNN`. If absent, abort: *"`/craft:execute` requires a target (`epic-NNN` or `slice-NNN`). Run `/craft:epic` or `/craft:plan` first, then call `/craft:execute <target>`."*

---

## Pre-Assertions

Run all of the following. Any failure stops the command before any worktree is created.

### A1 — Project is onboarded

`Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Both must exist and be non-empty.

Failure → abort: *"Project is not onboarded. Run `/craft:onboard` first."*

### A2 — Target plan exists

For `epic-NNN`: `Glob` `.claude/plans/epic-<NNN>-*.md` — exactly one match.
For `slice-NNN`: `Glob` `.claude/plans/slice-<NNN>-*.md` — exactly one match.

Failure → abort: *"No plan found for `<target>`. Run `/craft:plan` or `/craft:epic` first."*

### A3 — Working tree clean on `main`

`Bash` `git status --porcelain` must be empty, and the current branch must be `main` (or the project's configured trunk — read from `rules.md` `## Deployment` if specified).

Failure → abort: *"Working tree is not clean / not on main. Commit, stash, or move to main before `/craft:execute` — worktrees require a clean starting point."*

**Exception — protected-main sequential-epic resume.** When the target is an **epic** whose
profile is `Epic Mode: sequential` + `Merge → Type: pull-request` + `Protected-main: yes`, **and**
a slice listed in that epic's `## Slice Decomposition` has `Status: awaiting-approval` (its PR
was opened in a prior invocation), the working tree legitimately sits on **that slice's
`<slice-id>-<slug>` branch** rather than the trunk. A3 then passes when the tree is **clean** and
the current branch **is that awaiting-approval slice's branch** — the Sequential epic path's `s0`
merges the approved PR (its `/craft:commit` second pass runs from the PR branch, which
`/craft:commit`'s A6 requires) and returns to the trunk before the next slice. The git checkout
persists on that branch across `/clear` and new sessions, so the resume normally lands here with
no manual step.

If instead the tree is clean but the current branch is the **trunk** (or any other branch) while
such a mid-landing slice exists, do **not** proceed — `/craft:commit`'s second pass would trip its
A6 on the trunk. Abort with a directed hint: *"A protected-main sequential-epic slice
`<slice-id>` is mid-landing (its PR is open); check out its branch first — `git checkout
<slice-id>-<slug>` — then re-run `/craft:execute <epic-NNN>`."* (A3 aborts before the lock is
acquired, so nothing leaks.) This exception is scoped to exactly that combination; every other
target still requires a clean trunk.

### A4 — No concurrent execute run

Check for `.claude/plans/.execute.lock`. If present, abort: *"Another `/craft:execute` is in progress (lock file `<path>` exists with PID `<pid>`). Wait for it to finish or remove the lock manually if it crashed."*

### A5 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON with a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in epic/slice frontmatter. Re-install the plugin."*

### A6 — DAG resolvable

For an epic target: read every slice plan referenced in `## Slice Decomposition`. For each, read the `Depends-On:` frontmatter. Build the dependency graph. Reject if a cycle is detected, or if a referenced slice plan does not exist.

For a single slice target: trivially one-node graph. If the slice has `Depends-On: [...]` entries that are not yet committed (not present in `.claude/project/slices/`), abort: *"`slice-NNN` depends on slices that have not yet been committed: `<list>`. Either commit them, run them as an epic, or remove the dependency."* Note: lone-slice mode performs only a depth-1 dependency check; transitive cycles via already-archived slices are not re-validated because archived slices were cycle-checked at their own execute time.

Failure → abort with the specific issue: cycle, missing slice plan, or unresolved dependency.

### A7 — Epic targets use Epic Mode, not Execution Mode

`Execution → Mode` (`worktree` | `in-place`) governs **single-slice** targets only. For an
**epic** target the path is chosen by `Epic Mode` (step 1b): `parallel` → the worktree
fan-out; `sequential` → the epic's slices run one-by-one in place. So a project-wide
`Execution → Mode: in-place` setting does **not** conflict with an epic target — the epic
simply follows its `Epic Mode`. This assertion is informational: there is no invalid
Execution-Mode × target combination to reject.

---

## Procedure (Autonomy Level 2 inside plan scope, Level 0 for the final commit)

### 1. Acquire the lock

Write `.claude/plans/.execute.lock` containing the current PID and the resolved target. Lock is released in Post-Assertions (or on graceful abort).

### 1b. Branch on mode

Pick the path from the target kind and the profile:

- **Single-slice target** — branch on `Execution → Mode` (default `worktree`):
  - **`worktree`** (default) — continue with steps 2–10 below: the parallel, worktree-isolated path, unchanged. It always auto-commits per sub-task inside the worktree (its merge model depends on it — epic Decision C), so `Auto-commit: off` is ignored here.
  - **`in-place`** — skip steps 2–10 entirely and follow the **In-place path** sub-procedure. It builds the single slice on a branch in the main checkout, makes no commits, and halts before Phase 5 for human IDE review.
- **Epic target** — branch on `Epic Mode` (default `parallel`):
  - **`parallel`** (default) — continue with steps 2–10 below: the existing worktree fan-out + epic-branch merge, unchanged.
  - **`sequential`** — skip steps 2–10 entirely and follow the **Sequential epic path** sub-procedure. It runs the epic's slices **one-by-one in dependency order**, each built in the main checkout and landed per slice (committed on the trunk under `direct`, or via an approved PR under `pull-request` + `Protected-main: yes`), halting for review between slices. (`Execution → Mode` governs single-slice targets only; it does not apply to epic targets — an epic runs in place via `Epic Mode: sequential`, per A7.)

### 2. Trust the worktree base directory

Worktrees live **outside** the project root (`../<repo>-worktrees/…`), which Claude Code does not trust by default. Without this step every file operation a `slice-builder` performs inside a worktree raises a per-path permission prompt and stalls the autonomous run. The fix is one entry: the base directory that holds all worktrees goes into `permissions.additionalDirectories` of the project-local `.claude/settings.local.json`. Then the whole worktree tree inherits the project root's trust level.

This is a **durable-state mutation on user settings** — never silent. Follow the announce-then-apply flow:

1. **Resolve the pattern.** Use the project's `Worktree path pattern` from `rules.md` `## Worktree Settings`, or the default `../<repo>-worktrees/<slice-id>-<slug>/` when absent.

2. **Check (read-only).** `Bash`:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/ensure-worktree-trust.sh --check --pattern '<resolved-pattern>'
   ```

   The script prints `BASE_DIR=…` and `STATUS=present|absent` and exits `0` (already trusted) or `10` (absent). Any other non-zero exit is an error (e.g. `ERROR=python3_not_found`, `ERROR=settings_unparseable`) — surface it and fall back to telling the user to add `BASE_DIR` to `permissions.additionalDirectories` manually; do **not** proceed to worktree creation until trust is established.

3. **If `STATUS=present`** → already trusted (idempotent no-op on every subsequent run). Note it in one line and continue to step 3.

4. **If `STATUS=absent`** → announce the exact change and confirm once (Level 0):

   ```
   CRAFT will add the worktree base directory to permissions.additionalDirectories
   so per-worktree permission prompts don't interrupt the run:

     + <BASE_DIR>   →  .claude/settings.local.json

   This is a personal, gitignored override. Existing permissions are preserved.
   Proceed? [Y] add it (recommended)   [N] skip (expect per-path prompts)
   ```

   On `[Y]` (default), `Bash` the same script with `--apply`. It idempotently merges the entry (never overwriting existing `allow`/`deny`/`additionalDirectories`), creates `settings.local.json` if missing, ensures it is gitignored, and re-reads the file to verify it is valid JSON containing `BASE_DIR`. Confirm `STATUS=present` in the output before continuing. On `[N]`, continue but warn that per-worktree prompts are expected this run.

### 3. Create the epic-worktree (epic target only)

For an epic target:

- Branch name: `epic-<NNN>-<epic-slug>` (or pattern from `rules.md`).
- Worktree path: `../<repo>-worktrees/epic-<NNN>-<epic-slug>/`.
- `Bash`: `git worktree add <path> -b <branch>` rooted at `main`.

For a single slice: skip — the slice-branch is created directly from `main` in step 5 and will merge back to `main`.

### 4. Resolve the runnable frontier

A slice is "runnable" when every entry in its `Depends-On:` either:
- has been merged into the current epic-branch within this execute run, or
- is an archived slice (present in `.claude/project/slices/`) for a lone-slice run.

Initially the frontier is every slice with an empty `Depends-On:`.

### 5. Spawn slice-builders for the frontier

For each runnable slice in the frontier, in parallel:

- Determine branch name (`<slice-id>-<slug>` or pattern from `rules.md`).
- Determine worktree path (`../<repo>-worktrees/<slice-id>-<slug>/`).
- `Bash`: `git worktree add <path> -b <branch>` rooted at the epic-branch (epic target) or `main` (lone slice).
- Spawn a `slice-builder` subagent via `Task` with the worktree path as its working directory and the slice plan as its target. The subagent runs Phase 4 → 5 → 6 → (optional 7 — skipped if `rules.md` drops Phase 7) → 8 via the existing per-phase commands (`/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review`).

### 6. Collect slice outcomes

Each subagent ends in one of three states:

- **Success** — slice plan `Status: committing` (Phase 8 cleared, no Heavy + needs-rethinking findings open).
- **Handoff** — slice's worktree contains `.craft/handoff.md` with a stop reason. The subagent has stopped and surfaced a marker file.
- **Failure** — subagent crashed or returned an unstructured error.

For each success: merge the slice-branch into the epic-branch (epic target) or stash it for the user-approved final merge (lone slice — see step 8). Merge uses `--no-ff`:

```
git -C <epic-worktree> merge --no-ff <slice-branch> -m "Merge <slice-id> into epic-<NNN>"
```

After a successful merge, mark the slice's dependents as candidates for the next frontier and loop to step 5 until either the frontier is empty (all slices done) or a Handoff/Failure blocks progress.

### 7. Surface handoffs and failures

Whenever a slice ends in Handoff or Failure, **the orchestrator does not abort** — it continues spawning any other independent slices in the frontier, then stops once nothing else is runnable. The final output lists every Handoff/Failure with the slice-ID, the worktree path, and a one-line summary from the marker file.

### 8. Epic-ready or slice-ready prompt

When the frontier is exhausted:

- **Epic target, all slices succeeded** → epic-branch has every slice merged. Emit `Epic <epic-NNN> ready for review` with the checkout hint (`/craft:checkout epic-NNN` or `/craft:checkout slice-NNN`). Do **not** merge the epic-branch into `main` — that is the user's explicit step via `/craft:commit` after review.
- **Epic target, some slices stopped** → emit a partial-readiness block listing succeeded, handoff, and failed slices. The user resolves the handoff/failure slices (typically via `/craft:continue` inside the stopped worktree) and re-runs `/craft:execute <epic-NNN>` to pick up where it left off.
- **Lone slice succeeded** → emit `Slice <slice-NNN> ready for review` and the checkout hint. The slice-branch is not yet merged into `main`; `/craft:commit` does that after user review.
- **Lone slice handoff/failure** → emit the stop reason and recommend `/craft:continue <slice-NNN>` inside the slice worktree.

### 9. Respect per-slice review checkpoints

If the epic plan's `## Review Checkpoints` section lists `after slice-NNN`, the orchestrator pauses after that slice's Phase-7 self-review completes — **before** merging it into the epic-branch. Emit `Review checkpoint reached after slice-NNN — /craft:checkout slice-NNN to inspect, then re-run /craft:execute to continue`.

### 10. Release the lock

Delete `.claude/plans/.execute.lock` regardless of success or partial outcome — but only after the Post-Assertions have run.

---

## In-place path (Mode: in-place)

Followed instead of steps 2–10 when `Execution → Mode` is `in-place` (Procedure step 1b).
Single-slice only (A7). No worktree is created, no worktree-trust step runs, and nothing is
auto-committed — the slice's changes stay in the main checkout's working tree until you
release. The lock (step 1) is already held and is released at the end here, just as step 10
does for the worktree path.

### i1 — Create the slice branch in the main checkout

A3 guaranteed a clean tree on `main`. Create and check out the slice branch **in place** —
no worktree:

```
git checkout -b <slice-id>-<slug>
```

Use the `Branch name pattern` from `rules.md` `## Worktree Settings` if overridden. If the
branch already exists (e.g. a prior in-place run left it behind), abort: *"Branch
`<slice-id>-<slug>` already exists — a previous in-place run may not have finished. Resume it
with `/craft:release <slice-NNN>`, or delete the stale branch before re-running."* Never
overwrite it. Otherwise the main checkout is now on the slice branch with a still-clean tree.

### i2 — Run Phase 4 in place (no subagent, no commits)

Delegate Phase 4 to `/craft:build` **inline** — the main session follows `commands/build.md`
directly on the slice branch. There is no `slice-builder` subagent and no worktree: that
subagent exists for the isolation and parallelism a single in-place slice does not need, and
running inline is what lets you review the result in your own IDE afterwards. Build works the
sub-tasks to completion and leaves `Status: testing`. Build never commits, so the changes
simply accumulate **uncommitted** in the working tree — exactly the in-place contract.
`Auto-commit: off` is the consistent profile setting for in-place; the review-halt model
holds changes uncommitted until release regardless of the field's value.

If build stops early (a `/craft:debug` loop, an out-of-scope question), that pause stands —
in-place mode surfaces it to you directly (you are present), rather than writing a worktree
handoff.

### i3 — Halt before Phase 5

When Phase 4 completes, `/craft:build`'s phase-end bundle will have recommended
`/craft:test` — in in-place mode that recommendation is **superseded** by this halt; do
**not** follow it and do **not** proceed to Phase 5 (`Status: testing`). Instead:

1. Set the slice plan `Status: awaiting-release` — the dedicated in-place review-halt state.
2. Release the lock (delete `.claude/plans/.execute.lock`).
3. Emit the in-place halted block (see Output Format): the branch name, that the changes are
   uncommitted in the main checkout for IDE review, and the resume gesture
   `/craft:release <slice-NNN>`.

You do not run Phase 5–9. The human reviews the raw diff in their IDE, then releases with
`/craft:release`, which resumes the slice forward (Phase 5 onward) toward the commit — the
commit happens only after that release.

---

## Sequential epic path (Epic Mode: sequential)

Followed instead of steps 2–10 when the target is an **epic** and `Epic Mode` is `sequential`
(Procedure step 1b). It runs the epic's slices **one-by-one in dependency order**, each built in
the main checkout and landed per slice (the Merge Workflow note below picks the landing style),
halting for review between slices. No worktree is created and there is no epic-branch — each
slice lands on its own. The lock (step 1) is held for one execute invocation and released at the
end here.

> **Merge Workflow (two landing styles).** Sequential mode supports **both** the `direct` and
> the `pull-request` + `Protected-main: yes` workflows; the profile's `## Merge Workflow`
> selects which per-slice landing s2–s4 use:
> - **`direct`** (default) — each slice is built directly on the trunk and committed on `main`
>   per slice (no branch, no PR). The between-slices halt is s4.
> - **`pull-request` + `Protected-main: yes`** — each slice is built on its own
>   `<slice-id>-<slug>` branch in the main checkout and landed via an **approved** PR: `s3`
>   opens the PR (slice → `Status: awaiting-approval`) and the run halts for the human's GitHub
>   approval; the next invocation's `s0` merges the approved PR, syncs the local trunk with the
>   remote, and continues to the next slice. This is the **"Freigabe ≠ Merge"** gate applied
>   once per slice.

### s0 — Resume a mid-landing slice (protected-main workflow only)

Only under `Merge → Type: pull-request` + `Protected-main: yes`; the `direct` workflow lands
each slice synchronously in `s3` and never reaches this state, so skip s0 for `direct`.

Check whether any slice listed in the epic's `## Slice Decomposition` has
`Status: awaiting-approval` — a PR opened by a prior invocation's `s3`, not yet merged. If none,
skip to s1 (a fresh run, or the `direct` workflow). If one exists, it is the **mid-landing
slice** — complete its landing before starting any new slice by delegating to `/craft:commit`
(its **second invocation**, since the slice is `awaiting-approval`). `/craft:commit` reads the PR
and:

- **Approved → merged** — it runs `gh pr merge`, then its Step 7 *In-place-finalize* syncs the
  local trunk with the remote (`git checkout <trunk>`, `git fetch origin <trunk>`,
  `git merge --ff-only origin/<trunk>`), deletes the slice branch, and archives the plan. The
  slice is now **landed** and the working tree is back on the synced trunk. Continue to s1.
- **Not yet approved** (`reviewDecision` not `APPROVED`, PR still `OPEN`) — `/craft:commit`
  changes nothing and reports it. Release the lock (`rm .claude/plans/.execute.lock`) and
  re-emit the awaiting-approval halt (see Output Format): the human approves on GitHub, then
  re-runs `/craft:execute <epic-NNN>`. Do **not** start the next slice.
- **PR closed unmerged** — surface `/craft:commit`'s message, release the lock, and stop; the
  slice stays `awaiting-approval` for the human to resolve on GitHub.

### s1 — Resolve the order and the next runnable slice

Read the epic's `## Slice Decomposition` and each slice plan's `Depends-On:` (A6 validated the
DAG is acyclic). Topologically sort. The **next runnable slice** is the first slice, in that
order, whose plan is not yet archived under `.claude/project/slices/` (= not landed) and whose
`Depends-On:` are all landed. If every slice is landed → go to **s5**.

### s2 — Build the one slice in the main checkout

Build **only that single slice** through Phase 4–8 in the main checkout. **Where** it is built
depends on the Merge Workflow:

- **`direct`** — build directly on the trunk (the `direct` workflow commits per slice on `main`
  in s3 — no branch, so no branch→`main` gap).
- **`pull-request` + `Protected-main: yes`** — first create the slice branch off the trunk, so
  `s3`'s `/craft:commit` has a branch to open the PR from (a direct trunk commit is rejected by
  `/craft:commit`'s A6):

  ```
  git checkout -b <slice-id>-<slug>
  ```

  Use the `Branch name pattern` from `rules.md` `## Worktree Settings` if overridden. If the
  branch already exists (a prior invocation's build), abort: *"Branch `<slice-id>-<slug>` already
  exists — a previous invocation may not have finished. Resolve it (`/craft:continue
  <slice-NNN>`) or delete the stale branch before re-running."* Never overwrite it. Then build
  Phase 4–8 on that branch.

Then, on whichever line was set up above:

- **Delegate Phase 4–8** to the per-phase commands (`/craft:build → /craft:test → /craft:recap
  → /craft:review`; Phase 7 skipped when `rules.md` drops it). Execute drives the phases without
  a per-phase re-invocation, but the human touchpoints CRAFT already requires (the Phase-5
  `[W]/[B]/[U]` exercise, any review escalation) still halt the run — surface them directly; you
  are present; never fabricate them.
- **Mid-slice hard stop** (a `[B]` → `/craft:debug`, a Heavy+rethink escalation, a build
  early-stop) reaches neither s4 nor s5, so **release the lock** (`rm
  .claude/plans/.execute.lock`) and stop — otherwise the resume re-run trips A4. The slice's
  uncommitted work is on the trunk (`direct`) or on its `<slice-id>-<slug>` branch
  (`pull-request` + `Protected-main: yes`); the human resolves the slice, then re-runs
  `/craft:execute <epic-NNN>`.

When the slice clears Phase 8 (`Status: committing`), go to s3.

### s3 — Land the slice (per slice)

Land via `/craft:commit` — its A1 targets the single plan at `Status: committing`, so the
coexisting epic + sibling plans do not trip it. There is **no** epic-branch merge; each slice
lands on its own. The landing follows the Merge Workflow:

- **`direct`** — `/craft:commit` commits the per-slice work on `main` and archives the plan; the
  slice is now **landed**. Continue to s4. This is the "commit per slice" of sequential mode.
- **`pull-request` + `Protected-main: yes`** — this is `/craft:commit`'s **first invocation**: it
  commits the sub-task work on the slice branch, opens the PR, sets the slice
  `Status: awaiting-approval`, and does **not** merge (the "Freigabe ≠ Merge" gate). The slice is
  **not yet landed** — it awaits the human's GitHub approval. Release the lock (`rm
  .claude/plans/.execute.lock`) and emit the awaiting-approval halt (see Output Format): the PR
  URL and the resume gesture — approve on GitHub, then re-run `/craft:execute <epic-NNN>`, whose
  `s0` merges it and continues. `/craft:commit` prints its own PR-opened block ending in a
  `/craft:commit` resume gesture; for a sequential-epic slice that gesture is **superseded** by
  execute's halt — surface only `/craft:execute <epic-NNN>` (a lone `/craft:commit` merge would
  land the slice but strand the epic loop). Do **not** fall through to s4.

### s4 — Halt between slices (or finish) — `direct` workflow

Reached only on the `direct` workflow (under `pull-request` + `Protected-main: yes`, s3 already
halted at the awaiting-approval PR gate, and the next invocation's s0 continues the epic — so s4
is not reached).

After the slice lands, consult s1's order: **if an unlanded slice remains**, stop — release the
lock and emit the sequential-landed block (see Output Format): the slice that landed, the next
runnable slice, and the resume gesture — review, then re-run `/craft:execute <epic-NNN>`. On the
re-run, s1 skips the landed slice and continues. **If no unlanded slice remains** (this was the
last), go straight to **s5** — do not emit a halt with a phantom "next slice". (This is the
"review halt between them" of `Epic Mode: sequential`.)

### s5 — Epic complete

Reached from s1 (every slice landed) or s4. Emit `Epic <epic-NNN> complete — all <N> slices
landed sequentially` (there is no epic-branch to merge; each slice already landed on `main` —
directly on `direct`, or via its own approved PR on `pull-request` + `Protected-main: yes`, with
the local trunk synced). Release the lock.

---

## Post-Assertions

Run all of the following after the procedure completes. P1 and P3 apply to the parallel worktree path only; P5 to the in-place path; P6 to the sequential epic path. Any failure → warn loudly. No auto-rollback.

### P1 — Worktrees exist for every spawned slice

*(Worktree path only — in-place mode creates no worktrees; see P5.)*

`Bash` `git worktree list --porcelain` must show every slice-worktree created this run (or, for succeeded slices that have been merged, the worktrees must still exist — cleanup happens at Phase 9 `/craft:archive`).

Failure → *"⚠ Worktree accounting mismatch — expected `<list>`, found `<list>`. Run `/craft:worktree-status` and reconcile manually."*

### P2 — Slice plans have correct Status

Each succeeded slice's plan file has `Status: committing` (cleared review) or `Status: reviewing` (open finding); each stopped slice has `Status: paused` with the Pause Note filled. No slice is left with `Status: implementing`. In **in-place** mode the single slice ends at `Status: awaiting-release` (Phase 4 done, halted before Phase 5).

Failure → *"⚠ Slice `<id>` has Status `<X>` after execute — should be `<expected>`. Inspect `<path>`."*

### P3 — Epic-branch merge commits match succeeded slices

For an epic target: `Bash` `git -C <epic-worktree> log --merges --first-parent` must list one merge commit per succeeded slice. For a lone slice: skip.

Failure → *"⚠ Epic-branch is missing merge commits for slices: `<list>`. Re-running `/craft:execute` will retry."*

### P4 — Lock released

`.claude/plans/.execute.lock` must not exist after the command returns.

Failure → *"⚠ Execute lock not released. Remove `.claude/plans/.execute.lock` before the next `/craft:execute` run."*

### P5 — In-place slice halted correctly (in-place mode only)

For an in-place run: `Bash` `git branch --show-current` is the slice branch,
`git status --porcelain` is non-empty (the slice's uncommitted changes), the slice plan
`Status:` is `awaiting-release`, and no worktree exists for this slice
(`git worktree list --porcelain` shows only the main worktree).

Failure → *"⚠ In-place run did not halt cleanly — expected the slice branch checked out with
uncommitted changes and `Status: awaiting-release`. Inspect `git status` and the slice
plan."*

### P6 — Sequential epic landed cleanly (sequential mode only)

For a sequential epic run: `git worktree list --porcelain` shows **only the main worktree**
(no worktree created) and there is no epic-branch; and the run ended in one of these states,
per the Merge Workflow:

- **`direct`** — the slice handled this invocation is **landed** (plan archived under
  `.claude/project/slices/`, its per-slice commit(s) on `main`) or halted mid-flight with its
  plan `Status:` reflecting where it stopped; the run ended at a between-slices halt (s4) or at
  epic-complete (s5), with the current branch on the trunk.
- **`pull-request` + `Protected-main: yes`** — the run ended **either** at a per-slice
  awaiting-approval halt (exactly one epic slice has `Status: awaiting-approval`, the working
  tree is clean on that slice's `<slice-id>-<slug>` branch, and its PR is open) **or** at
  epic-complete (every slice archived under `.claude/project/slices/` via a merged PR, the
  current branch is the synced trunk, and no `<slice-id>-<slug>` branches or `awaiting-approval`
  plans remain).

Failure → *"⚠ Sequential epic run in an unexpected state — expected no worktrees/epic-branch
and the current slice landed, cleanly-halted, or awaiting-approval on its PR branch. Inspect
`git log`, `git branch`, the slice plans, and `.claude/project/slices/`."*

---

## Output Format

Epic, all slices succeeded:

```
✓ Epic <epic-NNN> ready for review
   Slices merged into epic-<NNN>-<slug>: <N>
     - slice-<id> — <title> (Phase 8 cleared, <H> heavy / <L> light findings, all in-phase fixes applied)
     - …

   Inspect:   /craft:checkout epic-<NNN>     (merged tree, full epic view)
              /craft:checkout slice-<id>     (per-slice worktree)

   Then:      /craft:commit                  (merges epic-<NNN>-<slug> → main with --no-ff)
```

Epic, partial:

```
⚠ Epic <epic-NNN> partially complete

   Merged into epic-<NNN>-<slug>: <N>
     - <list>

   Stopped:
     - slice-<id> — Handoff: "<reason from .craft/handoff.md>"  (worktree: <path>)
     - slice-<id> — Failure: <one-line subagent error>          (worktree: <path>)

   Resolve the stopped slices (typically /craft:continue inside the worktree)
   then re-run /craft:execute <epic-NNN> to pick up.
```

Lone slice succeeded:

```
✓ Slice <slice-NNN> ready for review
   Branch: <slice-NNN>-<slug>      (in worktree: <path>)
   Findings: <H> heavy / <L> light, all in-phase fixes applied.

   Inspect:   /craft:checkout <slice-NNN>
   Then:      /craft:commit         (merges <slice-NNN>-<slug> → main with --no-ff)
```

In-place slice halted for review:

```
✓ Slice <slice-NNN> built in place — halted before Phase 5 for your IDE review
   Branch: <slice-NNN>-<slug>   (in the main checkout; changes uncommitted)

   Review the raw diff in your IDE, then release:
   /craft:release <slice-NNN>    (resumes into Phase 5 → … → /craft:commit)
```

Sequential epic — slice landed, review halt before the next (`direct` workflow):

```
✓ Slice <slice-NNN> landed (sequential epic <epic-NNN>) — committed per slice
   Next runnable: slice-<MMM> "<title>"
   Review what landed, then continue:
   /craft:execute <epic-NNN>    (resumes at the next runnable slice)
```

Sequential epic — PR opened, awaiting approval (`pull-request` + `Protected-main: yes`):

```
⏸ Slice <slice-NNN> "<title>" (sequential epic <epic-NNN>) — PR opened, awaiting your GitHub approval
   PR:     <url>   (#N)
   Branch: <slice-NNN>-<slug> → <trunk>   (main NOT merged yet)
   Approve the PR on GitHub (a real review), then continue the epic:
   /craft:execute <epic-NNN>    (s0 merges this slice, then builds the next)
```

Sequential epic — complete:

```
✓ Epic <epic-NNN> complete — all <N> slices landed sequentially
   (no epic-branch; each slice already landed on main)

   Recommended next: /craft:prime to refresh, or /craft:plan for the next epic.
```

Aborted:

```
Execute aborted — <reason>. No worktrees created.
```

Review checkpoint reached:

```
⏸ Review checkpoint after slice-<id> (from epic-<NNN>'s ## Review Checkpoints)

   Inspect:   /craft:checkout <slice-id>
   Continue:  /craft:execute <epic-NNN>   (resumes after merging slice-<id>)
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A3 fails (dirty tree / not on main) | Abort. Do not stash automatically. |
| In-place (i1): slice branch already exists | Abort cleanly; hint to `/craft:release` the prior run or delete the stale branch. Never force-overwrite. |
| Sequential protected-main (s2): slice branch already exists | Abort cleanly; hint to `/craft:continue <slice-NNN>` the prior invocation or delete the stale branch. Never force-overwrite. |
| Sequential protected-main (s0): PR not yet approved on re-run | s0 reports it; release the lock and re-emit the awaiting-approval halt. The human approves on GitHub, then re-runs `/craft:execute <epic-NNN>`. |
| Sequential protected-main (s0): PR closed unmerged | Surface the message, release the lock, stop. The slice stays `awaiting-approval` for the human to resolve on GitHub. |
| A4 fails (lock exists) | Abort with lock path; user removes if crashed. |
| A6 fails (cycle / missing dep) | Abort. Name the cycle or missing slice. |
| `git worktree add` fails (path collision) | Abort the affected slice cleanly; other slices may still proceed. List the collision in the final output. |
| Subagent crashes mid-Phase | Treat as Failure (step 7). Continue with other independent slices. |
| Slice's `/craft:review` blocks with Heavy + needs-rethinking | Treat as Handoff. The slice's worktree is intact for `/craft:checkout`. |
| User interrupts (signal, `/craft:pause`) | Drop into pause: write Pause Note to every in-flight slice, release the lock, stop. |
| P1–P4 fail | Warn loudly. The user reconciles manually. Do not retry automatically. |

---

## What This Command Does NOT Do

- It does **not** plan. Run `/craft:plan` (slice) or `/craft:epic` (epic) first.
- It does **not** merge the epic-branch (or lone-slice-branch) into `main`. `/craft:commit` does that, after user review.
- It does **not** clean up worktrees. `/craft:archive` (Phase 9) does that after the user has confirmed merge-to-main.
- It does **not** auto-resolve Heavy + needs-rethinking findings. Those escalate to the user via Handoff.
- It does **not** modify `intent.md` or `rules.md`. Architectural decisions surfaced inside a slice live in that slice's `## Decisions Made During This Slice` for Phase 9 promotion.
- It does **not** push to remote. No `git push` happens here — that is a separate user step.
- In **in-place** mode (single-slice) it does **not** create a worktree, does **not** auto-commit, and does **not** run past Phase 4 — it halts before Phase 5 and hands off to `/craft:release`. An **epic** target follows its `Epic Mode` regardless of `Execution → Mode` (A7), running in place via `Epic Mode: sequential`.
- In **sequential epic** mode (`Epic Mode: sequential`) it does **not** create worktrees or an epic-branch, and does **not** run slices in parallel — it lands the epic's slices one-by-one in place and halts for review between slices (resume by re-running `/craft:execute <epic>`). Each slice lands per the Merge Workflow: committed directly on the trunk (`direct`), or via its own approved PR that the human merges through the "Freigabe ≠ Merge" gate (`pull-request` + `Protected-main: yes`), with the local trunk synced after each merge.
