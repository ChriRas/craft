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

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

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

`Bash` `bash "${CLAUDE_PLUGIN_ROOT}/scripts/tree-dirt-state.sh"` must report `DIRTY=no`, and the current branch must be `main` (or the project's configured trunk — read from `rules.md` `## Deployment` if specified). Which of CRAFT's own files — plans, ID counters, local state — do not count as uncommitted work is defined once, in that helper; its `DIRT=` lines name what does. A helper that cannot run (non-zero exit) fails A3.

Failure → abort: *"Working tree is not clean / not on main. Commit, stash, or move to main before `/craft:execute` — worktrees require a clean starting point."*

**Exception — a sequential epic target** (`Epic Mode: sequential`). Skip A3; Procedure step 1c
judges the tree and the branch instead. A re-run of a sequential epic legitimately finds the one
slice an earlier invocation left open — its uncommitted work on the trunk (`direct`), or its
`<slice-id>-<slug>` branch checked out (`pull-request` + `Protected-main: yes`, including a slice
mid-landing at `Status: awaiting-approval`) — and only the helper can tell that apart from a dirty
tree or a wrong branch nobody accounts for. Every other target still requires a clean trunk here.

### A4 — No concurrent execute run

Check for `.claude/plans/.execute.lock`. If present, abort: *"Another `/craft:execute` is in progress (lock file `<path>` exists with PID `<pid>`). Wait for it to finish or remove the lock manually if it crashed."*

### A5 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON with a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in epic/slice frontmatter. Re-install the plugin."*

### A6 — DAG resolvable

For an epic target: resolve every entry of `## Slice Decomposition` through the helper that defines the entry format —

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-entry-link.sh" resolve "<epic-plan>"
```

— run from the project root. Its output lines (per entry, per ignored line, the counts and `RESULT=`) and what each state means are defined in the helper's header. Here: `STATE=plan` resolves the entry to its `PLAN=` path, `STATE=landed` to its slice-ID. Anything else rejects the epic, naming the entry and its fix; print every command with the plugin root resolved to its absolute path and quoted arguments, to run from the project root:

- `ENTRY_COUNT=0` → *"no decomposition entries found in `<epic-plan>` — check its `## Slice Decomposition` heading"*.
- an `IGNORED LINE=<n> TEXT=<text>` line → *"line `<n>` of `<epic-plan>` is not read as an entry (`<text>`) — write it in the entry format, or close the fence"*; every such line is named.
- `unlinked` → *"entry `<ENTRY>` names no slice-ID — plan it with `/craft:plan` (which links it), or link the slice that already exists or has landed: `bash "<plugin-root>/scripts/epic-entry-link.sh" link "<epic-plan>" "<ENTRY>" <slice-id>`"*.
- `missing` → *"`<SLICE>` on entry `<ENTRY>` has neither a plan nor an archive — the slice was aborted; plan the entry again with `/craft:plan`, which offers it and replaces the dead ID — or, when a slice that refines it already exists (a re-plan), link that one: `bash "<plugin-root>/scripts/epic-entry-link.sh" link "<epic-plan>" "<ENTRY>" <slice-id>`"*.
- `ambiguous` → *"several plans carry `<SLICE>` — remove the stray plan"*.

A helper that cannot run rejects too. Then read each resolved plan's `Depends-On:` frontmatter, build the dependency graph and reject a cycle.

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
  - **`worktree`** (default) — continue with steps 1c–10 below: the parallel, worktree-isolated path. It always auto-commits per sub-task inside the worktree (its merge model depends on it — epic Decision C), so `Auto-commit: off` is ignored here.
  - **`in-place`** — skip steps 1c–10 entirely and follow the **In-place path** sub-procedure. It builds the single slice on a branch in the main checkout, makes no commits, and halts before Phase 5 for human IDE review.
- **Epic target** — branch on `Epic Mode` (default `parallel`):
  - **`parallel`** (default) — continue with steps 1c–10 below: the worktree fan-out + epic-branch merge.
  - **`sequential`** — run step 1c, then skip steps 2–10 and follow the **Sequential epic path** sub-procedure. It runs the epic's slices **one-by-one in dependency order**, each built in the main checkout and landed per slice (committed on the trunk under `direct`, or via an approved PR under `pull-request` + `Protected-main: yes`), halting for review between slices. (`Execution → Mode` governs single-slice targets only; it does not apply to epic targets — an epic runs in place via `Epic Mode: sequential`, per A7.)

### 1c. Read what an earlier run left behind

Not on the in-place path (its i1 keeps its own branch check). A re-run of `/craft:execute` builds on
the worktrees, branches, merges and stopped slices an earlier run left behind — it never re-creates
them (`git worktree add -b` aborts on an existing branch). What exists is decided in one place, the
helper. Run it once, read-only, before anything is created:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/execute-resume-state.sh" --trunk <trunk> [options] <slice>...
```

Each `<slice>` is what A6 resolved it to — its plan path, or its slice-ID once it has landed.

- worktree path, epic target — `--epic <epic-plan>` and every slice of the epic;
- worktree path, lone slice — its plan;
- sequential epic path — `--mode sequential --landing <direct|pull-request>` and every slice of the
  epic;
- `--branch-pattern '<p>'` / `--path-pattern '<p>'` when `rules.md` `## Worktree Settings` overrides them.

Which `ACTION=` / `REASON=` a situation yields is defined in the script's header, not here. Act on
the result:

- **`RESULT=conflict`** — abort before any write: release the lock, list every `ACTION=conflict`
  line and a `RESULT_REASON=` other than `-`, and change nothing — no worktree, branch, directory or
  plan. The reason names the fix: `branch_without_worktree` → attach it (`git worktree add <path>
  <branch>`) or delete the branch; `worktree_missing` → restore the directory or `git worktree
  prune`; `worktree_foreign_branch` / `path_taken` → move what sits at the path; `plan_unreadable` →
  repair the plan's `Slice-ID:` / `Slice-Slug:` (`Epic-ID:` / `Epic-Slug:`); `multiple_open` /
  `unknown_status` / `branch_missing` / `branch_exists` → resolve the named slices;
  `epic_merge_in_progress` → finish or abort the merge in the epic worktree; `epic_worktree_dirty` →
  commit or discard what sits uncommitted in the epic worktree; `plan_not_committed` → commit the
  plan on the trunk (and, when the epic branch already exists, bring it into that branch) — a new
  worktree is a checkout of its base, so an uncommitted, ignored or edited plan would reach
  `slice-builder` stale or not at all; `dirty_without_open_slice` → the
  changes belong to no slice in flight (a paused or blocked slice counts as in flight) — commit or
  stash them; `wrong_branch` → check out the in-flight slice's `BRANCH=` (`pull-request`) or the trunk.
  Then re-run `/craft:execute <target>`.
- **The helper cannot run** (not found, non-zero exit, no `RESULT=` line) → abort the same way.
  Never read a failing helper as a fresh run.
- **`RESULT=ok`** → hold every line. The worktree path acts on `ACTION=create`, `ACTION=reuse` and
  `ACTION=skip` (steps 3–6); the sequential path on `ACTION=skip`, `ACTION=resume`, `ACTION=held`
  and `ACTION=create` (s1–s2).

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

   This is a personal, local override. Existing permissions are preserved.
   Proceed? [Y] add it (recommended)   [N] skip (expect per-path prompts)
   ```

   On `[Y]` (default), `Bash` the same script with `--apply`. It idempotently merges the entry (never overwriting existing `allow`/`deny`/`additionalDirectories`), creates `settings.local.json` if missing, and re-reads the file to verify it is valid JSON containing `BASE_DIR`. Confirm `STATUS=present` in the output before continuing. It never writes `.gitignore` — a write here would dirty the main checkout mid-run, and `/craft:commit` A3 would later refuse to finalize on it. Its `GITIGNORED=` line reports `scripts/ensure-gitignore.sh`'s verdict for the settings file: on `no`, add one line `⚠ .claude/settings.local.json is not gitignored — /craft:prime offers the CRAFT local-state block (step 4f)` and continue; `yes`, `negated` (the project keeps it visible on purpose) and `unknown` add nothing. On `[N]`, continue but warn that per-worktree prompts are expected this run.

### 3. Create the epic-worktree (epic target only)

For an epic target, by the epic line from step 1c:

- `ACTION=create` — `Bash`: `git worktree add <WORKTREE> -b <BRANCH>` rooted at `main` (the line's
  `BRANCH=` and `WORKTREE=`: `epic-<NNN>-<epic-slug>` under `../<repo>-worktrees/`, or the patterns).
- `ACTION=reuse` — an earlier run created it; use `WORKTREE=` as it is. Do not add it again.

For a single slice: skip — the slice-branch is created directly from `main` in step 5 and will merge back to `main`.

### 4. Resolve the runnable frontier

A slice whose step-1c line is `ACTION=skip` is done — merged into the epic-branch by an earlier run
(or archived) — and is never spawned. A slice is "runnable" when every entry in its `Depends-On:`
either:
- has been merged into the epic-branch — within this run, or by an earlier one (`ACTION=skip` with
  `REASON=merged` or `REASON=archived`; a slice skipped as `awaiting_approval` is not in the
  epic-branch and satisfies no dependency), or
- is an archived slice (present in `.claude/project/slices/`) for a lone-slice run.

Initially the frontier is every slice that is not skipped and whose `Depends-On:` is empty or satisfied
throughout, by the rule above.

### 5. Spawn slice-builders for the frontier

For each runnable slice in the frontier, in parallel:

- By the slice's step-1c line:
  - `ACTION=create` — `Bash`: `git worktree add <WORKTREE> -b <BRANCH>` rooted at the epic-branch (epic target) or `main` (lone slice).
  - `ACTION=reuse` — the worktree an earlier run created; do not add it again. Whatever that run left in it — a plan status, a handoff marker — is the subagent's to judge: `slice-builder`'s step 0 decides whether it stops or continues, and where.
- `Bash`: seed the ensure-primed marker in the worktree (idempotent — a reused worktree may have it) — `mkdir -p <path>/.claude/plans && touch <path>/.claude/plans/.primed` — so the **ensure-primed gate** is a silent no-op for the slice-builder. The orchestrator has already primed on `main` and briefs the subagent with `intent.md` / `rules.md`; `SessionStart` hooks do not fire for `Task` subagents and the marker is gitignored (absent from the checkout), so without this seed every slice-builder would wrongly auto-run `/craft:prime` inside its worktree. See `skills/workflow/SKILL.md` → *Session Priming Gate → Under /craft:execute*.
- Spawn a `slice-builder` subagent via `Task` with the worktree path as its working directory and the slice plan as its target. The subagent runs Phase 4 → 5 → 6 → (optional 7 — skipped if `rules.md` drops Phase 7) → 8 via the existing per-phase commands (`/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review`).

### 6. Collect slice outcomes

Each subagent ends in one of four states:

- **Success** — slice plan `Status: committing` (Phase 8 cleared, no Heavy + needs-rethinking findings open). A reused slice an earlier run already brought there returns Success at once.
- **Handoff** — slice's worktree contains a **live** `.craft/handoff.md` with a stop reason: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-marker-state.sh" <worktree>` reports `STATE=LIVE` — live vs. stale, and the fallback when the helper cannot run, are defined in `skills/workflow/SKILL.md` → **Handoff marker lifecycle**; this check only reads (renaming a stale marker is `slice-builder`'s step 0). A `STALE` marker is an already-resolved handoff and does not make a slice a Handoff; classify it by its plan status like any other. The subagent has stopped and surfaced a marker file. One handoff variant is distinct: `Status: awaiting-block-decision` means the subagent hit an out-of-scope blocker and wrote the first-class `blocked` state — the slice plan is at `Status: blocked` (not `paused`), and its resolution routes to `/craft:unblock`, not a plain `/craft:continue`. A second is `Status: awaiting-rethink-decision`: the review handoff does not pause the plan — its plan status and resolution are defined in `/craft:review` → Subagent Mode.
- **Failure** — subagent crashed or returned an unstructured error.
- **Held at start** — the subagent stopped in its step 0 without a live marker and emitted the paused line with `reason=` (e.g. `plan-held`: a human holds the slice at `paused` / `blocked`). Surface it with the slice-ID, the worktree path and that reason, like a Handoff; the plan says what the human still has to do.

For each success: merge the slice-branch into the epic-branch (epic target) or stash it for the user-approved final merge (lone slice — see step 8). Merge uses `--no-ff`:

```
git -C <epic-worktree> merge --no-ff <slice-branch> -m "Merge <slice-id> into epic-<NNN>"
```

After a successful merge, mark the slice's dependents as candidates for the next frontier and loop to step 5 until either the frontier is empty (all slices done) or a Handoff/Failure blocks progress.

### 7. Surface handoffs and failures

Whenever a slice ends in Handoff or Failure, **the orchestrator does not abort** — it continues spawning any other independent slices in the frontier, then stops once nothing else is runnable. The final output lists every Handoff/Failure with the slice-ID, the worktree path, and a one-line summary from the (live) marker file.

### 8. Epic-ready or slice-ready prompt

When the frontier is exhausted:

- **Epic target, all slices succeeded** → epic-branch has every slice merged. Emit `Epic <epic-NNN> ready for review` with the checkout hint (`/craft:checkout epic-NNN` or `/craft:checkout slice-NNN`). Do **not** merge the epic-branch into `main` — that is the user's explicit step via `/craft:commit` after review.
- **Epic target, some slices stopped** → emit a partial-readiness block listing succeeded, handoff, and failed slices. The user resolves the handoff/failure slices (typically via `/craft:continue` inside the stopped worktree — a slice stopped on `awaiting-block-decision` is `blocked` and routes on to `/craft:unblock`) and re-runs `/craft:execute <epic-NNN>` to pick up where it left off — step 1c reuses the stopped worktrees and skips the merged slices.
- **Lone slice skipped** (step 1c `ACTION=skip`) → nothing to run. `REASON=merged`: emit that `<slice-NNN>-<slug>` is already merged into `main`. `REASON=awaiting_approval`: emit that its PR is open and waits for approval. Either way recommend `/craft:commit`, which completes the slice.
- **Lone slice succeeded** → emit `Slice <slice-NNN> ready for review` and the checkout hint. The slice-branch is not yet merged into `main`; `/craft:commit` does that after user review.
- **Lone slice handoff/failure** → emit the stop reason and recommend `/craft:continue <slice-NNN>` inside the slice worktree.

### 9. Respect per-slice review checkpoints

If the epic plan's `## Review Checkpoints` section lists `after slice-NNN`, the orchestrator pauses after that slice's Phase-7 self-review completes — **before** merging it into the epic-branch. Emit `Review checkpoint reached after slice-NNN — /craft:checkout slice-NNN to inspect, then re-run /craft:execute to continue` as part of the run's output, and only then record it as shown, as the last write of that pause: append the line `<slice-id> shown <ISO date> <tip>` — `<tip>` is the slice branch's commit (`git rev-parse <slice-branch>`) — to `<epic-worktree>/.craft/checkpoints.md`, at the epic worktree's **root** (where a slice worktree keeps its handoff marker). A run interrupted before that line pauses again next time, never merges unseen.

A checkpoint whose line names this slice-ID **and** the slice branch's current tip does not pause again: the re-run is the human's go-ahead, so that slice is merged like any other success. A line with an older tip does not count — the slice changed after it was shown (a loop-back, a `/craft:continue` in its worktree) — so the checkpoint pauses again and appends a new line. Once step 6 has merged the slice, delete its lines, and the file and an empty `.craft/` with them: a merged slice never reaches this step again, and a leftover untracked file would make `/craft:commit`'s `git worktree remove` of the epic worktree fail.

The record lives in the epic worktree, not in the epic plan — the plan sits in the main checkout, where an uncommitted mark would fail A3 in a project that tracks `.claude/plans/`, and stashing it would re-arm the checkpoint. `.craft/` is CRAFT local state; whether or not a project's `.gitignore` covers it at the worktree root (a project in a subdirectory anchors its CRAFT block below that), step 1c does not count the record as epic-worktree dirt. It lives no longer than the epic worktree, which is as long as its checkpoints matter.

### 10. Release the lock

Delete `.claude/plans/.execute.lock` regardless of success or partial outcome — but only after the Post-Assertions have run.

---

## In-place path (Mode: in-place)

Followed instead of steps 1c–10 when `Execution → Mode` is `in-place` (Procedure step 1b).
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

1. <!-- craft:writes status=awaiting-release --> Set the slice plan `Status: awaiting-release` — the dedicated in-place review-halt state.
2. Release the lock (delete `.claude/plans/.execute.lock`).
3. Emit the in-place halted block (see Output Format): the branch name, that the changes are
   uncommitted in the main checkout for IDE review, and the resume gesture
   `/craft:release <slice-NNN>`.

You do not run Phase 5–9. The human reviews the raw diff in their IDE, then releases with
`/craft:release`, which resumes the slice forward (Phase 5 onward) toward the commit — the
commit happens only after that release.

---

## Sequential epic path (Epic Mode: sequential)

Followed after step 1c, instead of steps 2–10, when the target is an **epic** and `Epic Mode` is `sequential`
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

- **Approved → merged** — it runs `gh pr merge`, then its Step 7 syncs the local trunk with the
  remote and drops the local plan copy (*Plans and the trunk under protected main* — the merged PR
  already removed a tracked plan from the trunk), and deletes the slice branch. The
  slice is now **landed** and the working tree is back on the synced trunk. Continue to s1.
- **Merged, but Step 7 stopped** (`/craft:commit` surfaced a `plan-landing.sh` `ERROR=`) — the slice
  is not landed locally: it stays `awaiting-approval` on its branch. Surface the error, release the
  lock (`rm .claude/plans/.execute.lock`) and stop; once the cause is cleared, a re-run of
  `/craft:execute <epic-NNN>` retries through `s0`. Do **not** continue to s1.
- **Not yet approved** (`reviewDecision` not `APPROVED`, PR still `OPEN`) — `/craft:commit`
  changes nothing and reports it. Release the lock (`rm .claude/plans/.execute.lock`) and
  re-emit the awaiting-approval halt (see Output Format): the human approves on GitHub, then
  re-runs `/craft:execute <epic-NNN>`. Do **not** start the next slice.
- **PR closed unmerged** — surface `/craft:commit`'s message, release the lock, and stop; the
  slice stays `awaiting-approval` for the human to resolve on GitHub.

### s1 — Resolve the order and the next runnable slice

Take the slices A6 resolved the epic's `## Slice Decomposition` to and each slice plan's `Depends-On:` (A6 validated the
DAG is acyclic). Topologically sort. Then take the step-1c lines — after s0 has landed a slice, run
the helper once more with the same arguments (that slice's plan is gone and its archive makes it
`ACTION=skip`; the tree is back on the trunk), and act on it exactly as step 1c does — a conflict or a
helper that cannot run aborts, and the abort names the slice s0 has already landed:

- A line is `ACTION=held` → a human holds that slice at `paused` / `blocked`. Stop: release the lock
  and route it to `/craft:continue` / `/craft:unblock`; the human re-runs `/craft:execute <epic-NNN>`
  afterwards.
- A line is `ACTION=resume` → that slice is the **next slice**, whatever its place in the order: an
  earlier invocation started it and stopped mid-slice.
- Otherwise the **next slice** is the first, in that order, whose line is `ACTION=create` and whose
  `Depends-On:` are all landed. `ACTION=skip` means landed (plan removed, archived under
  `.claude/project/slices/`).
  If every slice is landed → go to **s5**.

### s2 — Build the one slice in the main checkout

Build **only that single slice** through Phase 4–8 in the main checkout. By its step-1c line:

- **`ACTION=resume`** — create nothing. The slice's work is already where an earlier invocation
  left it: on the trunk (`direct`) or on its `BRANCH=`, which is checked out (`pull-request` +
  `Protected-main: yes` — step 1c's `wrong_branch` guarantees it). Resume at the plan's `Status:`,
  routed as `/craft:continue` Step 3 routes that status; a `committing` slice goes straight to s3.
  Never restart Phase 4.
- **`ACTION=create`** — **where** it is built depends on the Merge Workflow:
  - **`direct`** — build directly on the trunk (the `direct` workflow commits per slice on `main`
    in s3 — no branch, so no branch→`main` gap).
  - **`pull-request` + `Protected-main: yes`** — first create the slice branch off the trunk, so
    `s3`'s `/craft:commit` has a branch to open the PR from (a direct trunk commit is rejected by
    `/craft:commit`'s A6):

    ```
    git checkout -b <BRANCH>
    ```

    `BRANCH=` already follows the `Branch name pattern`. The branch does not exist yet — a
    leftover one is step 1c's `branch_exists` conflict — so this never overwrites a branch.

Then, on whichever line was set up above:

- **Delegate Phase 4–8** to the per-phase commands (`/craft:build → /craft:test → /craft:recap
  → /craft:review`; Phase 7 skipped when `rules.md` drops it). Execute drives the phases without
  a per-phase re-invocation, but the human touchpoints CRAFT already requires (the Phase-5
  `[W]/[B]/[U]` exercise, any review escalation) still halt the run — surface them directly; you
  are present; never fabricate them.
- **A review loop-back is not a stop.** When the human routes a finding back to Phase 4 in
  `/craft:review` (its Step 8 leaves the slice at `Status: implementing`), keep driving:
  `/craft:build` → … → `/craft:review` again, then s3. The route is the human's decision, already
  made, and the human is present.
- **Mid-slice hard stop** (a `[B]` → `/craft:debug`, a Heavy+rethink finding the human leaves
  pending, a build early-stop) reaches neither s4 nor s5, so **release the lock** (`rm
  .claude/plans/.execute.lock`) and stop — otherwise the resume re-run trips A4. The slice's
  uncommitted work stays on the trunk (`direct`) or on its `<slice-id>-<slug>` branch
  (`pull-request` + `Protected-main: yes`); the human resolves the slice, then re-runs
  `/craft:execute <epic-NNN>`, whose step 1c finds it as `ACTION=resume`.

When the slice clears Phase 8 (`Status: committing`), go to s3.

### s3 — Land the slice (per slice)

Land via `/craft:commit` — its A1 targets the single plan at `Status: committing`, so the
coexisting epic + sibling plans do not trip it. There is **no** epic-branch merge; each slice
lands on its own. The landing follows the Merge Workflow:

- **`direct`** — `/craft:commit` commits the per-slice work and its archive on `main` and closes the
  plan, leaving a clean tree (its Step 5b / Step 7); the slice is now **landed**. Continue to s4. This is the "commit per slice" of sequential mode.
- **`pull-request` + `Protected-main: yes`** — this is `/craft:commit`'s **first invocation**: it
  commits the sub-task work and the archive on the slice branch, opens the PR, sets the slice
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

`Bash` `git worktree list --porcelain` must show every slice-worktree created or reused this run (or, for succeeded slices that have been merged, the worktrees must still exist — cleanup happens at Phase 9 `/craft:archive`). A slice step 1c skipped needs no worktree.

Failure → *"⚠ Worktree accounting mismatch — expected `<list>`, found `<list>`. Run `/craft:worktree-status` and reconcile manually."*

### P2 — Slice plans have correct Status

Each succeeded slice's plan file has `Status: committing` (cleared review); each stopped slice has `Status: paused` with the Pause Note filled, **or** `Status: blocked` with the `## Blocker` section filled (a slice that escalated on `awaiting-block-decision`), **or** — for a slice stopped on `awaiting-rethink-decision` — the plan status `/craft:review` → Subagent Mode leaves it at, with open lines in `## Review Findings`. No slice is left with `Status: implementing`. In **in-place** mode the single slice ends at `Status: awaiting-release` (Phase 4 done, halted before Phase 5).

Failure → *"⚠ Slice `<id>` has Status `<X>` after execute — should be `<expected>`. Inspect `<path>`."*

### P3 — Epic-branch merge commits match succeeded slices

For an epic target: `Bash` `git -C <epic-worktree> log --merges --first-parent` must list one merge commit per succeeded slice. For a lone slice: skip.

Failure → *"⚠ Epic-branch is missing merge commits for slices: `<list>`. Re-running `/craft:execute` will retry."*

### P4 — Lock released

`.claude/plans/.execute.lock` must not exist after the command returns.

Failure → *"⚠ Execute lock not released. Remove `.claude/plans/.execute.lock` before the next `/craft:execute` run."*

### P5 — In-place slice halted correctly (in-place mode only)

For an in-place run: `Bash` `git branch --show-current` is the slice branch,
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/tree-dirt-state.sh"` reports `DIRTY=yes` (the slice's uncommitted changes), the slice plan
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
  plan `Status:` reflecting where it stopped (a slice resumed via step 1c counts as handled); the run
  ended at a between-slices halt (s4), at epic-complete (s5), or at s1's stop on a held slice (its plan
  untouched, nothing built), with the current branch on the trunk.
- **`pull-request` + `Protected-main: yes`** — the run ended at a per-slice awaiting-approval halt
  (exactly one epic slice has `Status: awaiting-approval`, the checkout is on that slice's
  `<slice-id>-<slug>` branch, and its PR is open), at a mid-slice hard stop or s1's stop on a held
  slice (the checkout on that slice's branch, its plan `Status:` reflecting where it stopped), **or** at
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
   [Re-run: <R> worktree(s) reused, <S> slice(s) skipped — merged by an earlier run]

   Inspect:   /craft:checkout epic-<NNN>     (merged tree, full epic view)
              /craft:checkout slice-<id>     (per-slice worktree)

   Then:      /craft:commit                  (merges epic-<NNN>-<slug> → main with --no-ff)
```

Epic, partial:

```
⚠ Epic <epic-NNN> partially complete

   Merged into epic-<NNN>-<slug>: <N>
     - <list>
   [Re-run: <R> worktree(s) reused, <S> slice(s) skipped — merged by an earlier run]

   Stopped:
     - slice-<id> — Handoff: "<reason from .craft/handoff.md>"  (worktree: <path>)
     - slice-<id> — Failure: <one-line subagent error>          (worktree: <path>)

   Resolve the stopped slices (typically /craft:continue inside the worktree; a slice whose
   marker is awaiting-block-decision is blocked and resolves via /craft:unblock)
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

Sequential epic — stopped on a held slice (s1):

```
⏸ Sequential epic <epic-NNN> — slice-<id> is held at <paused | blocked>; nothing was built
   Resolve it:  /craft:continue <slice-id>   (paused)   ·   /craft:unblock <slice-id>   (blocked)
   Then:        /craft:execute <epic-NNN>
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

Aborted — step 1c found a state it will not build on:

```
Execute aborted — step 1c found a state this run will not create over or overwrite. Nothing else was changed.
   slice-<id> — <REASON>   (<BRANCH> · <WORKTREE>)
   [run: <RESULT_REASON>]
   [helper: could not read the run state — <exit code / missing RESULT=>]
   [already landed by s0 before this abort: slice-<id> (PR #N merged, trunk synced)]

   Fix: <the reason's fix from step 1c>
   Then: /craft:execute <target>
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
| Step 1c: `RESULT=conflict` (a leftover branch, worktree or path; a dirty tree or wrong branch no open slice accounts for) | Abort before any write; list the conflict lines with the reason's fix. Never overwrite, prune or delete. |
| Step 1c: the helper cannot run | Abort the same way — never treat it as a fresh run. |
| Sequential protected-main (s0): PR not yet approved on re-run | s0 reports it; release the lock and re-emit the awaiting-approval halt. The human approves on GitHub, then re-runs `/craft:execute <epic-NNN>`. |
| Sequential protected-main (s0): PR closed unmerged | Surface the message, release the lock, stop. The slice stays `awaiting-approval` for the human to resolve on GitHub. |
| A4 fails (lock exists) | Abort with lock path; user removes if crashed. |
| A6 fails (cycle / missing dep) | Abort. Name the cycle or missing slice. |
| `git worktree add` fails despite step 1c (the state changed since, e.g. a concurrent manual `git worktree add`) | Abort the affected slice cleanly; other slices may still proceed. List the collision in the final output. |
| Subagent crashes mid-Phase | Treat as Failure (step 7). Continue with other independent slices. |
| Slice's `/craft:review` blocks with Heavy + needs-rethinking | Treat as Handoff. The slice's worktree is intact for `/craft:checkout`. |
| User interrupts (signal, `/craft:pause`) | Drop into pause: <!-- craft:writes status=paused --> pause every slice whose `slice-builder` is still running (not yet collected as Success, Handoff, Held or Failure) and that is not `blocked` — `Status: paused` with the pause record (`skills/workflow/SKILL.md` → **Pause record**) and a Pause Note — in the plan copy that slice is built from: the slice worktree's in parallel mode, the main checkout's in in-place and sequential mode. Slices already stopped keep their plan and marker untouched. Release the lock, stop. |
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
