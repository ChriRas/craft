---
description: Autonomously execute an epic or single slice. Parallel worktree mode (default) creates parallel git worktrees and delegates Phase 4–7 to subagents per slice, merging into an epic-branch; in-place mode builds a single slice on a branch in the main checkout, halts before Phase 5 for IDE review (resumed via /craft:release); sequential epic mode runs an epic's slices one-by-one in place, landing each per slice — committed directly on the trunk (direct) or via an approved PR (pull-request/protected-main) — with a review halt between; `--autopilot` runs an epic's slices one-by-one in place on its epic branch with foreground slice-builders and no halt between them — planning unplanned entries with slice-planner agents behind one plan gate first — stopping only where a human is needed and asking at the end whether to merge into main.
argument-hint: "<epic-NNN [--autopilot] | slice-NNN>"
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

A second argument `--autopilot` selects the **Autopilot run** (below) and is valid on an epic target only. On a
slice target, abort: *"`--autopilot` runs an epic. Run the slice with `/craft:execute <slice-NNN>`, or list it in an
epic."* It is chosen per run, never read from the profile: an autopilot run is one the human starts on purpose (D32).

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

**Exception — a sequential epic target** (`Epic Mode: sequential`) **or an autopilot run**. Skip A3; Procedure step 1c
judges the tree and the branch instead (an autopilot run first settles its epic branch in a0, which runs after A4 and before A6 — see A6). A re-run of a sequential epic legitimately finds the one
slice an earlier invocation left open — its uncommitted work on the trunk (`direct`), or its
`<slice-id>-<slug>` branch checked out (`pull-request` + `Protected-main: yes`, including a slice
mid-landing at `Status: awaiting-approval`) — and only the helper can tell that apart from a dirty
tree or a wrong branch nobody accounts for. Every other target still requires a clean trunk here.

### A4 — No concurrent execute run

`Bash` `bash "${CLAUDE_PLUGIN_ROOT}/scripts/execute-lock.sh" check --project "<project-root>"`. The lock is state, never
removed (B19): whether a new run may take it is the helper's fixed rule, not a judgment of yours — act only on its
`DECISION=`. `proceed` or `takeover` → continue (step 1 takes it). `confirm` (`REASON=own_process`) → the lock is held
by this very Claude Code session, and only the human knows whether that run has ended: its builders may still work in
the background. Ask, Level 0 — *"The run lock is held by this session (target `<TARGET>`, since `<SINCE>`). Is a
`/craft:execute` run from this session still working? [N] no, it ended (e.g. interrupted with Esc) — release it and go
on · [Y] yes — stop"*. Only on `[N]`: release the lock (step 1 — the plain release, which this process may run because
it owns the lock; never `--force`), then continue. Any other answer → abort: *"A `/craft:execute` run from this session
is still working (target `<TARGET>`). Re-run `/craft:execute` once it has ended and answer [N]."* — no `--force` line:
the lock is this session's, and forcing it would free a running run's lock. `stop`, or a helper that cannot run →
abort:
*"Another `/craft:execute` may be in progress — the run lock is held by process `<OWNER_PID>` (target `<TARGET>`, since
`<SINCE>`; reason `<REASON>`). Wait for that run to end. If you are sure no run is active, release it yourself:"* — and
after the message, as its own top-level code block (never inside the quoted sentence), the command
`bash "<plugin-root>/scripts/execute-lock.sh" release --force --project "<project-root>"` with both paths resolved to
absolute paths. Never run that `--force` yourself — it is the human's.

### A5 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON with a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in epic/slice frontmatter. Re-install the plugin."*

### A6 — DAG resolvable

**An autopilot run settles its epic branch first:** run the Autopilot run's **a0** after A4 and before this assertion.
The helper below reads archives from the working tree, and a slice that landed on the epic branch has no plan and no
archive on the trunk — read from there it is `missing`, and the rejection would send the human to re-plan work that
has landed (slice-049 review R1). Because a0 has already changed the checkout, **every A6 rejection in an autopilot run
also says so**: the checkout is now on `<epic-branch>` — go back with `git checkout <trunk>` to work elsewhere, or fix
the epic and re-run, which keeps the branch.

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

**In an autopilot run, `unlinked` and `missing` do not reject:** those entries are the planning stage's work (Autopilot
run → **ap**, after the lock), which plans them and runs this assertion again once the human has approved the plans.
Every other rejection above stands, and the dependency graph here covers the entries that already resolve.

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

The run lock is `.claude/plans/.execute.lock`, and `scripts/execute-lock.sh` is its only reader and writer — its header
defines the lock's states and the takeover rule. It is **never removed** (a user may deny removing files, and a lock
that could only be released by removal was never released — slice-049): its content says `held` or `released`.

- **Take it:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/execute-lock.sh" acquire --project "<project-root>" --target
  <epic-NNN|slice-NNN>`. `RESULT=acquired` or `taken_over` → go on (a takeover names the stale owner in `REASON=`; say
  so in one line). `RESULT=refused` → abort with A4's message; `REASON=no_identity` means this Claude Code gave the
  command no `CLAUDE_PID`, so no owner can be recorded — abort and say so: *"update Claude Code to v2.1.214 or later
  (the first release that sets `CLAUDE_PID`)"*. No `RESULT=` line, or a non-zero exit other than 10 (`ERROR=write_failed`:
  the lock could not be written) → abort as A4 does, naming the error; nothing is running yet.
- **Release it** — wherever this command says *release the lock*: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/execute-lock.sh"
  release --project "<project-root>"`. `RESULT=released`, `unchanged` or `absent` → released. `RESULT=refused` → surface
  it (`⚠ Execute lock not released: <REASON>`) and go on; P4 reports it. Never delete the lock file, and never run
  `release --force`.

Release only a lock **this invocation** took (step 1 `RESULT=acquired` or `taken_over`): at the release points of its
path, and on any abort after step 1 (one exception: a5's closing log line that did not land keeps it held). An abort in A4 or at step 1's refusal releases nothing — in this session a plain
release would succeed on a running run's lock (both share `CLAUDE_PID`) and free it.

### 1b. Branch on mode

Pick the path from the target kind and the profile:

- **Single-slice target** — branch on `Execution → Mode` (default `worktree`):
  - **`worktree`** (default) — continue with steps 1c–10 below: the parallel, worktree-isolated path. It always auto-commits per sub-task inside the worktree (its merge model depends on it — epic Decision C), so `Auto-commit: off` is ignored here.
  - **`in-place`** — skip steps 1c–10 entirely and follow the **In-place path** sub-procedure. It builds the single slice on a branch in the main checkout, makes no commits, and halts before Phase 5 for human IDE review.
- **Epic target with `--autopilot`** — follow the **Autopilot run** below, whatever `Epic Mode` says: its a0 has
  already settled the epic branch (before A6), so step 1c runs with that branch as the trunk; then skip steps 2–10 and
  follow the Sequential epic path with the autopilot deltas.
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
- autopilot run — `--mode sequential --landing direct --trunk <epic-branch> --slices-from <epic-plan>` and **no**
  slice list: the helper reads the epic's slices off its entries, so the master cannot pass a wrong one (slice-057's
  probe 1 passed the epic plan itself as a slice, B23). The epic branch is where each slice lands, so to the helper it
  is the trunk (a `wrong_branch` then means the checkout is not on the epic branch);
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

   On `[Y]` (default), `Bash` the same script with `--apply`. It idempotently merges the entry (never overwriting existing `allow`/`deny`/`additionalDirectories`), creates `settings.local.json` if missing, and re-reads the file to verify it is valid JSON containing `BASE_DIR`. Confirm `STATUS=present` in the output before continuing. It never writes `.gitignore` — a write here would dirty the main checkout mid-run, and `/craft:commit` A3 would later refuse to finalize on it. Its `GITIGNORED=` line reports `scripts/ensure-gitignore.sh`'s verdict for the repository root's `.claude/settings.local.json` (the file it writes, also when the project is a subdirectory of the repository): on `no`, add one line `⚠ <repo-root>/.claude/settings.local.json is not gitignored — cover it from the repository root's .gitignore (when the project is the repository root, /craft:prime offers the CRAFT local-state block, step 4f)` and continue; `yes`, `negated` (the project keeps it visible on purpose) and `unknown` add nothing. On `[N]`, continue but warn that per-worktree prompts are expected this run.

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
- **Before spawning**, settle the subagent's model: follow `model-defaults.md` → **Spawn-Reachable Values** → *What a spawn site must do*, for the agent `slice-builder`. That procedure decides whether this project's override travels with the spawn or is dropped; it is defined once, there. `/craft:prime` reports the value this step will ask for, and this step is what makes that report true — `model-defaults.md` → **Resolution Order** names the project override as source 2, and a source that no spawn site applies is a claim, not a rule. **If that file cannot be resolved** — neither `${CLAUDE_PLUGIN_ROOT}/model-defaults.md` nor `<project-root>/model-defaults.md` exists — spawn `slice-builder` with **no** `model` parameter, and emit `⚠ Could not read model-defaults.md — spawning slice-builder without a model; a project override, if any, was dropped.` That sentence is stated here on purpose and is **not** a second copy of the procedure: it is the one case the pointer cannot deliver, because the file it points into is the file that is missing (B-R7-1).
- Spawn a `slice-builder` subagent via `Task` with the worktree path as its working directory and the slice plan as its target, passing the `model` the bullet above resolved (or none). The subagent runs Phase 4 → 5 → 6 → (optional 7 — skipped if `rules.md` drops Phase 7) → 8 via the existing per-phase commands (`/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review`).

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

Release the lock (step 1) regardless of success or partial outcome — after Post-Assertions P1–P3 have run and before
P4, which checks this release and therefore runs last.

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
handoff. Release the lock (step 1) before you surface it: the run ends there.

### i3 — Halt before Phase 5

When Phase 4 completes, `/craft:build`'s phase-end bundle will have recommended
`/craft:test` — in in-place mode that recommendation is **superseded** by this halt; do
**not** follow it and do **not** proceed to Phase 5 (`Status: testing`). Instead:

1. <!-- craft:writes status=awaiting-release --> Set the slice plan `Status: awaiting-release` — the dedicated in-place review-halt state.
2. Release the lock (step 1).
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

Check whether any slice A6 resolved to a plan (`STATE=plan` — the epic's entries are read through
`scripts/epic-entry-link.sh`, never here) has `Status: awaiting-approval` — a PR opened by a prior invocation's `s3`,
not yet merged. If none,
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
  lock (step 1) and stop; once the cause is cleared, a re-run of
  `/craft:execute <epic-NNN>` retries through `s0`. Do **not** continue to s1.
- **Not yet approved** (`reviewDecision` not `APPROVED`, PR still `OPEN`) — `/craft:commit`
  changes nothing and reports it. Release the lock (step 1) and
  re-emit the awaiting-approval halt (see Output Format): the human approves on GitHub, then
  re-runs `/craft:execute <epic-NNN>`. Do **not** start the next slice.
- **PR closed unmerged** — surface `/craft:commit`'s message, release the lock, and stop; the
  slice stays `awaiting-approval` for the human to resolve on GitHub.

### s1 — Resolve the order and the next runnable slice

Take the slices A6 resolved the epic's `## Slice Decomposition` to and each slice plan's `Depends-On:` (A6 validated the
DAG is acyclic). Topologically sort. Then take the step-1c lines — after s0 has landed a slice, run
the helper once more with the same arguments (that slice's plan is gone and its archive makes it
`ACTION=skip`; the tree is back on the trunk), and act on it exactly as step 1c does — a conflict or a
helper that cannot run aborts, and the abort names the slice s0 has already landed. An autopilot run does the same
after every slice a3 lands (a4):

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
  pending, a build early-stop) reaches neither s4 nor s5, so **release the lock** (step 1)
  and stop — otherwise the resume re-run trips A4. The slice's
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
  **not yet landed** — it awaits the human's GitHub approval. Release the lock (step 1)
  and emit the awaiting-approval halt (see Output Format): the PR
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
the local trunk synced). Release the lock, and end with `Recommended next: /craft:commit` — it closes the epic: its
decisions, its archive and its plan (its Epic-close mode, D38). Under `pull-request` + `Protected-main: yes` end instead
with `<epic-NNN> is finished — close it by hand, through a PR (B25)`: Epic-close would refuse it, because its archive
commit would land on the trunk directly.

---

## Autopilot run (`--autopilot`)

An epic run the human starts on purpose and then leaves (D32): the epic's slices are built one-by-one **in place on
the epic branch** by a foreground `slice-builder`, landed there by `/craft:commit` at Level 2, and the run moves on to
the next slice without a halt. It **is** the Sequential epic path — order, resume, held slices and landing are s1–s3's,
and are not restated here. This section lists only where an autopilot run differs. `main` does not move until the
human says yes at the end (a5).

**Every human stop stays, but one.** A review escalation, a debug protocol, a scope question, a blocker and a builder
failure all stop the run (a2), and so does Phase 5's `[W]/[B]/[U]` — unless the slice's committed checks pass by command
(`/craft:test` → Subagent Mode step 0a, D35); the product feel then goes to the human at a5 through `## UX Demo Script`.
What the run takes over is only what needs no judgment: the order, the resume, the spawn, the commit split and the `[K]`
default. Planning an entry nobody planned is no longer a rejection either: `slice-planner` agents plan it and the
human approves the package once, at the plan gate (**ap**) — the run's one stop before it builds. Removing further
stops is the work of later epic-003 slices.

### a0 — Preconditions and the epic branch (after A4, before A6 and before the lock)

a0 runs inside the Pre-Assertions (A6 says where), so a stop here has created nothing and holds no lock yet — the
relaunch its message asks for does not trip A4.

1. **Foreground builders.** `Bash` `printenv CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` must print `1`. Otherwise stop before
   anything is created: *"Autopilot needs foreground builders. Quit this session and start it with
   `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude`, then run `/craft:execute <epic-NNN> --autopilot` again."* — the
   master delivers each builder's result once only in the foreground (design record §9 Q8).
2. **Model note.** If this session does not run on Sonnet, say so in one line and continue: the master mostly reads
   helper output and digests, and on Opus it costs 2.5× for that (design record §4). Never switch the model yourself.
3. **The epic branch** — `epic-<NNN>-<slug>` from the epic plan's `Epic-ID:` / `Epic-Slug:` (`Branch name pattern`
   does not apply; it names slice branches). By the current branch:
   - **the epic branch** → a re-run; keep it.
   - **the trunk**, `tree-dirt-state.sh` reports `DIRTY=no`, the epic branch does not exist → `git checkout -b <epic-branch>`.
   - **the trunk**, `DIRTY=no`, the epic branch exists → `git checkout <epic-branch>` (an earlier run stopped, and the
     human went back to the trunk).
   - anything else (another branch, or a dirty trunk) → stop and name it: the run builds on the epic branch only, and
     never carries changes it cannot account for onto it. A dirty trunk while the epic has a slice plan at an execution
     status is most likely that slice's work, carried along when the human left the epic branch: name
     `git checkout <epic-branch>` as the fix, which carries it back — never "commit or stash", which would put slice
     work on the trunk. Name commit or stash only when no slice of the epic is in flight.
4. **Then** A6–A7 run, the lock is taken (Procedure step 1; the cache guard is disarmed right after it — *The cache guard*), **ap** plans what A6 left unplanned, and step 1c runs with
   the epic branch as the trunk (step 1c, *autopilot run*). A `wrong_branch` or `dirty_without_open_slice` there aborts
   as step 1c says.

### The Autopilot Log — every line through the helper

Every step from ap on logs to the epic plan's `## Autopilot Log` — one line per event, never rewritten. It is the run's
durable record: a new session re-reads it instead of any chat history, and `plan-gate-state.sh`, `usage-state.sh` and
`epic-close-state.sh` read it. **The master never writes a log line itself** — the helper does, run from the project root:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-log.sh" append "<epic-plan>" <glyph> <id> '<text>'
```

It reads the clock, places the line as the section's last line (inserting a missing section, dropping its
`(no autopilot run yet)` line) and checks that it landed; the line's format and its placement are defined once, in its
header. Wherever this command says *log `<glyph> · <id> · <text>`*, it means this call with those three arguments —
`<text>` single-quoted, each `'` in it written `'\''`, and one line — fold a line break (a human's note, an error's
later lines) into a space; the helper refuses a text with one. slice-049's master logged round, invented times; slice-057's probe
1 stamped a line five seconds after the file was last written — the clock is the helper's, not the master's.

- **Exit 0** → print the `LINE=` value — **write the log line first, then print it**: every `▶ / ✓ / ⛔ / ■` the master
  prints has its line, on every invocation, a resume included (a probe's re-run printed its `✓` and logged nothing,
  slice-049).
- **`ERROR=gate:no_run_started`** → a1 was skipped in this invocation: run a1 now, then the refused call again (a1).
- **No `LINE=` line** — any other non-zero exit, a call the permission check denied (slice-057's BUG-1: no exit code
  at all), no output. Where a step names its own handling (a5), that holds; everywhere else the run stops: print
  `⛔ · <epic-id> · not logged: <ERROR=, or a one-line cause>` — printed only, the log is what failed — release the
  lock, and tell the human what the line needs, by its kind:
  - an epic-ID line, or any `⛔` / `■` line (the gate never holds them) → print the refused call as its own code
    block, the plugin root resolved, to run once the cause is fixed;
  - a2's `▶` line → nothing: the re-run writes a fresh one;
  - a3's `✓` line → it is lost: the slice has landed, a re-run reads it `skip` and never writes it again — say so; only
    the budget forecast misses this slice's sample.
  After `ERROR=not_landed` the plan was written but the line did not check out: name the log section for the human to
  look at before anything is run again — a second call could write the line twice.

### The master's own files

The master writes no file outside the project. A file it needs for itself — a brief for a spawn, a command's output kept
for a later step — goes to `.craft/tmp/` in the project root: CRAFT local state, gitignored with `.craft/` and never
tree dirt (`scripts/tree-dirt-state.sh`). Never `/tmp`, `$TMPDIR` or another path outside the project (slice-056's
probe 3 left helper files there). Files in `.craft/tmp/` are left in place — the master issues no removal command, which
a user's rule on removing files would refuse (D34); helpers keep and remove their own temp files.

### ap — Plan the unplanned entries, then the plan gate (after the lock, before step 1c)

The one human stop an autopilot run keeps before it builds (design record §9 Q1): agents plan, the human approves the
package once. Whether the gate is still owed is derived, never stored —

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-gate-state.sh" "<epic-plan>"
```

— run from the project root; its output lines and what each state means are defined in its header. **Skip ap** when A6
found no `unlinked` or `missing` entry **and** the helper prints `RESULT=clear`: a hand-planned epic, or one whose plans
the human already approved, runs as before. A helper that cannot run stops the run `⛔` (release the lock): without
it, nothing can say the gate was passed.

0. **Plans no entry links — ask first.** Only when A6 found an `unlinked` or `missing` entry and the helper reports
   `ORPHAN_COUNT` above 0: an active plan no epic entry links may already plan one of those entries (a hand re-plan, a
   failed link, a planner cut off by Esc), and planning the entry again would build it twice. Whether it does is a
   content call, so ask — Level 0, before any planner runs — listing each `ORPHAN` line with the plan's title:
   `[P]` plan the unplanned entries anyway (the orphans are unrelated) · `[N]` stop, release the lock, and link or
   abort them first (`bash "<plugin-root>/scripts/epic-entry-link.sh" link "<epic-plan>" "<entry>" <slice-id>`, or
   `/craft:abort <slice-id>`). Log `▶ · <epic-id> · orphan plans: plan anyway — <slice-ids>` for `[P]`, or
   `■ · <epic-id> · orphan plans: stopped — <slice-ids>` for `[N]`. Arm the cache guard before asking
   <!-- craft:cache-guard arm --> and disarm it when the answer arrives <!-- craft:cache-guard disarm --> (*The cache guard*).
   **No `unlinked` or `missing` entry** (a re-run that owes only the gate) → skip 0–3 and go to 4.
1. **Allocate.** For every `unlinked` or `missing` entry, in decomposition order: take the next slice-ID from
   `.claude/plans/.next-id` (its A4 rule in `/craft:plan`: a missing file means `001`, a non-integer stops the run) and
   the plan path `.claude/plans/slice-<NNN>-<short-name>.md` (a taken path gets `/craft:plan`'s `-2`, `-3` suffix). Write
   `.next-id` **once**, past the last ID. Log `▶ · <epic-id> · planning <k> entries: <slice-id> (<entry>), …`.
2. **Spawn the planners.** Settle the model: follow `model-defaults.md` → **Spawn-Reachable Values** → *What a spawn site
   must do*, for the agent `slice-planner` — defined once, there. **If that file cannot be resolved** — neither
   `${CLAUDE_PLUGIN_ROOT}/model-defaults.md` nor `<project-root>/model-defaults.md` exists — spawn `slice-planner` with
   **no** `model` parameter, and emit `⚠ Could not read model-defaults.md — spawning slice-planner without a model; a
   project override, if any, was dropped.` (stated here because the pointer cannot deliver it, B-R7-1). Then spawn one
   `slice-planner` per entry via `Task`, all in one message, each with: the epic plan path, its entry (short-name and
   intent), its slice-ID and plan path, the other entries' IDs, and the plugin root `${CLAUDE_PLUGIN_ROOT}` resolved to
   its absolute path. Each spawn must return in the foreground, as a2's does. Correctness does not depend on the spawns
   running side by side: every file they write was allocated to them in 1.
3. **Link.** For each `PLANNED slice-<NNN> <path>` line, link its entry —
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-entry-link.sh" link "<epic-plan>" "<entry>" slice-<NNN>` — and log
   `▶ · <slice-id> · planned from entry <entry>`. A `FAILED` line, a missing line, or a link `ERROR=` leaves that entry
   **failed**: log it `⛔`, keep its ID reserved (IDs are never handed out twice), and carry it to the gate.
4. **Check the package.** Per awaiting plan: `/craft:plan`'s P1–P3 on the file, and a `<!-- craft:verify -->` block in
   `## Test Strategy`. Over all the epic's plans: A6's dependency rule — every `Depends-On:` ID resolves, and the graph
   has no cycle; a violation is a failed check on the plans it names. Then run `plan-gate-state.sh` again; its `PLAN … GATE=awaiting` lines are the package, its
   `NEEDS_HUMAN=` counts are the open questions.
4b. **The plan review** — one `plan-architect` spawn per round (slice-055). The round's kind: `first` right after
   steps 1–3 ran in this invocation, `auto` right after an autonomous revision (below), `review-only` otherwise (after
   `[R]`, or when steps 0–3 were skipped). Settle the model: follow `model-defaults.md` → **Spawn-Reachable Values** →
   *What a spawn site must do*, for the agent `plan-architect` — defined once, there. **If that file cannot be
   resolved** — neither `${CLAUDE_PLUGIN_ROOT}/model-defaults.md` nor `<project-root>/model-defaults.md` exists — spawn
   `plan-architect` with **no** `model` parameter, and emit `⚠ Could not read model-defaults.md — spawning
   plan-architect without a model; a project override, if any, was dropped.` (the pointer cannot deliver it, B-R7-1).
   Spawn it in the foreground with: the epic plan path; every plan of the epic the helper lists, each marked
   **revisable** (`GATE=awaiting`) or **not** (`GATE=hand` — hand-planned — or `GATE=approved` — passed an earlier gate,
   perhaps already building): only a `GATE=awaiting` plan is revised autonomously; the round number (`ARCH_NEXT_ROUND`)
   and kind; the earlier findings (their `P<n>-<k>` lines in `## Plan Review`, each with its resolution); the plugin
   root resolved to its absolute path. Record its
   answer in the epic plan's `## Plan Review`, in the format `plan-gate-state.sh`'s header defines (a missing section
   goes directly above `## UX Demo Script`, else above `## Autopilot Log`; drop its `(no plan review yet)` line): this
   round's heading, one finding line per `FINDING` numbered `P<n>-1`, `P<n>-2`, … with the resolution `open`, and a
   `- note · <ID> still open: <text>` line per `VERDICT … open`. A `VERDICT <ID> holds` sets that earlier line's
   resolution to `resolved in round <n>` in place — besides the gate's `accepted at gate` (5, `[Y]`), the only change
   ever made to an earlier line. Log
   `▶ · <epic-id> · plan review round <n> (<kind>): <f> finding(s), <r> to revise`. A spawn that returns no `RESULT`
   line is retried once; failing again, log `⛔ · <epic-id> · plan review failed` and go to 5, where the gate says the
   review did not run.
   **Autonomous revision** — only when this round is `first` or `auto`, the helper (run again) reports
   `ARCH_AUTO_LEFT` above 0, and a `revise` finding **raised in this round** names a `GATE=awaiting` plan: log
   `▶ · <epic-id> · plan review → revise: <slice-ids>`, spawn **one** `slice-planner` per awaiting plan a `revise`
   finding names — its slice list names exactly the plans that must change — with the notes and IDs of **every** such
   finding that names that plan, never two planners on one plan (step 2's model rule;
   `/craft:plan` → Subagent Mode, *An `[R]` round*, the note coming from the architect), then back to 4 and 4b as an
   `auto` round. Otherwise go to 5. To the gate go: a `revise` finding on a plan that is not revisable; an earlier
   `revise` finding this round's `VERDICT` keeps open — its planner already applied the note or recorded why not, and
   asking again is the human's call; a `review-only` round's findings; and those left when the two autonomous rounds
   are spent.
5. **The gate** — Level 0, a stop that waits on the human. Log `▶ · <epic-id> · plan gate shown: <slice-id>, …`, arm the
   cache guard <!-- craft:cache-guard arm --> (the last tool call before the block is printed; the human's answer
   disarms it <!-- craft:cache-guard disarm -->, *The cache guard*), then emit *Autopilot — plan gate*
   (Output Format): per awaiting plan its title, the `## Goal` sentence, Trigger / Effect / Test in one line each, the
   sub-task count, `Depends-On`, the verify-check count, every `NEEDS-HUMAN:` line as written and every failed check;
   every failed entry with its reserved ID; the plan review — its rounds, and every open finding (`ARCH FINDING=… OPEN=yes`
   and `ARCH_MALFORMED` lines) as written in `## Plan Review`, or that the review did not run; an `ARCH_MALFORMED` line
   with *"⚠ unreadable plan-review line <n> — correct it by hand in `## Plan Review`; autonomous revision stays off
   until then"*; then how the run will go (a1's briefing lines, with the order from `Depends-On`). Offer `[Y]` only
   when no plan failed a check, no entry failed, and `NEEDS_HUMAN_COUNT=0` — open plan-review findings do not withhold it:
   whether the package is right is the human's call:
   - **`[Y]`** → log `✓ · <epic-id> · plan gate approved: <every awaiting slice-id, comma-separated>` — the line
     `plan-gate-state.sh` reads, so it names every plan the human saw. With open plan-review findings, log next
     `▶ · <epic-id> · approved with open plan-review findings: <IDs>` — a line of its own, so the approval line keeps
     the one shape `plan-gate-state.sh` reads — and set each of those findings' resolution to `accepted at gate` in
     place, so a later planning pass of the epic neither shows nor re-checks them (an `ARCH_MALFORMED` line has no ID
     and stays as it is). Then run A6 again (every entry must resolve now, the dependency graph over all plans) and go
     on with step 1c.
   - **`[R] <slice-id>[, …] — <note>`** — a failed entry is named by the reserved ID the gate shows on its line; a plan
     that is not `GATE=awaiting` (hand-planned, or approved at an earlier gate and perhaps building) is refused with
     *"<slice-id> is not awaiting this gate — edit it by hand, or `[N]`"* and the gate shown again, since a revised
     approved plan would keep its approval unseen → log `▶ · <epic-id> · plan gate revise: <slice-ids> — <note>`, spawn
     `slice-planner` again for each named slice with the note and the plan to revise — a failed entry that has no plan
     file is planned fresh at its reserved ID and path, the note as context (step 2's model rule) — link a failed entry
     that now returns `PLANNED` (3), then back to 4 — whose 4b runs a `review-only` round.
   - **`[N]`** → log `■ · <epic-id> · plan gate: stopped, plans kept`, release the lock, and name the plan paths: edit
     them by hand, then `/craft:execute <epic-NNN> --autopilot` shows the gate again.

The master judges none of the plans' content — see *Who decides what* below. Esc during ap leaves what was written:
allocated IDs stay spent, linked plans await the gate, and a re-run plans only the entries still unlinked. A plan
written but not yet linked when Esc came has no entry: the re-run reports it as an `ORPHAN` and step 0 asks.

### Who decides what in an autopilot run

The master and `slice-builder` run on the execute tier (a0 item 2, `model-defaults.md`) and decide **only what a helper
reports**; judgment goes to a
deep-reason agent or to the human (design record §4, the master's condition). A decision this table does not list is
not the master's: it stops the run and asks.

| Decision | Made by | Read off |
|---|---|---|
| Which entries need planning, which slice runs next, resume or create | master | `epic-entry-link.sh resolve`, `execute-resume-state.sh` |
| Which slice-IDs to use | master | `.claude/plans/.next-id` |
| What a plan says — trigger, effect, test, sub-tasks, dependencies | `slice-planner` (deep-reason) | its sources; open questions as `NEEDS-HUMAN:` |
| Whether the gate is owed | master | `plan-gate-state.sh` |
| Whether the package holds together — overlaps, contracts, order, sizing | `plan-architect` (deep-reason) | the epic's open plans, its design record and archives |
| Whether to revise autonomously | master | the finding's route and round, the plan's `GATE=`, `plan-gate-state.sh` (`ARCH_AUTO_LEFT`) |
| Whether the package is right | **the human**, at the gate | the gate block, open plan-review findings included |
| Whether Phase 5 passed | `slice-builder` (execute tier), in its spawn | `verify-run.sh`'s result line (`/craft:test` → Subagent Mode 0a) |
| What a review finds, whether a fix holds | `code-reviewer` (deep-reason) | the diff and the plan |
| Loop back or escalate after a review | `slice-builder` (execute tier), in its spawn | `review-findings-state.sh` (`TRIP=`, `/craft:review` → Step 9) |
| Whether a debug attempt fixed it | `slice-builder` (execute tier), in its spawn | `verify-run.sh` against the frozen protocol |
| How the slice passed Phase 5, for the landed line | master, at a3 | the plan's `## Verification Evidence` |
| Whether the usage windows allow the next slice, or the next sub-task | master (a2, a3); `slice-builder`, in its spawn | `usage-state.sh` (`VERDICT=`) |
| Scope, blockers, direction | **the human** | the `⛔` stop |
| Merge into the trunk | **the human**, at a5 | the digest |

### The budget guard — `usage-state.sh` (a2, a3, a4)

The run must not start a slice the plan's 5-hour window cannot carry, nor go on past the weekly limit (D32, design
record §6). The master never judges the numbers: `scripts/usage-state.sh` reads them off the statusline tap and the
profile's `## Autopilot` limits and prints `VERDICT=go|stop` — its header defines the gates, the limits, the forecast
and the conservative mode, and is not restated here. Run it from the project root:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-state.sh" --gate <before|after> --epic-plan <epic plan> [--slice <slice-id>]
```

- **`go`** → the run goes on — a `MODE=conservative` one too: its `after` gate then stops the run.
- **A `stop`** → print and log `⛔ · <epic-id> · budget: <REASON>` (the helper's `REASON=`, verbatim), release the lock
  and emit *Autopilot — stopped* with `budget` as its status. Nothing is undone: a stop before a slice leaves it
  unstarted, one after a slice leaves it landed. The human's step is the re-run — **when** depends on the stop, and
  *Autopilot — stopped* names it: a limit or overage stop → after the reset time `REASON` names; a stop with no reading
  (`MODE=conservative`, after a slice) → at once, or after wiring the tap when `UNKNOWN` starts with `no tap at`; a
  check that failed (no `VERDICT=`, a log check) → after fixing what it names.
- **No `VERDICT=` line** (the helper not found, a non-zero exit) → the same stop, logged
  `⛔ · <epic-id> · budget check failed: <ERROR= or a one-line cause>` — a guard that cannot judge stops the run.
- **The log check** — the forecast and every Δ are read from the `▶` and `✓` lines a2 and a3 write, so the master's
  carry of `LOG_FIELD=` into them is checked by command, not trusted (rules.md: what an agent must carry verbatim is
  checked by command). Right after writing either line run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-state.sh" --check-line <start|landed> --epic-plan <epic plan> --slice <slice-id> --expect "<LOG_FIELD>"`.
  `LINE_OK=yes` → go on. `LINE_OK=no`, or no `LINE_OK=` line → the same stop as a `stop`, logged
  `⛔ · <epic-id> · budget: log line not readable — <REASON>` (no `LINE_OK=` line: `<ERROR=` or a one-line cause`>`).
  Which block and what the human does depends on the check:
  - `start` → *Autopilot — stopped* for that slice. No correction is needed: the re-run writes a fresh `▶` line, and an
    earlier invocation's line never feeds a Δ. The human re-runs (after fixing the helper, when it gave no line).
  - `landed` → the slice has landed: *Autopilot — stopped after a landed slice*, or — after the epic's last slice —
    a5 runs as usual. The human corrects the `✓` line by hand (`usage-state.sh`'s header shows its shape) so its Δ counts.
  - When the gate before it gave no `VERDICT=` (the helper is broken), the line was never the cause: log the gate's
    `budget check failed: …` instead, as above.
- `WARN=` lines are printed, not logged; they never change what the master does.
- The builder runs the `during` gate itself, at every boundary of its spawn (`agents/slice-builder.md` → *The budget
  guard*); a2 reads its stop.

### The cache guard — `cache-guard-marker.sh` (every human stop)

A session that waits on the human keeps a prompt cache that expires after an hour, and a prompt that arrives after that
re-writes the whole context at the full input price (design record §7). The `UserPromptSubmit` hook
`hooks/cache-guard.sh` blocks such a prompt before any request is sent and names the restart; this section is how the
master arms it and what the stop prints. The hook's header defines when it blocks — the marker
`.claude/plans/.cache-guard`, its format, the threshold (`craft-profile.md` → `## Autopilot`), what passes — and is not
restated here. The master never writes the marker itself — the helper binds it to this session and reads the expiry off
the statusline tap:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cache-guard-marker.sh" arm <epic-NNN> --project "<project-root>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cache-guard-marker.sh" disarm --project "<project-root>"
```

`<project-root>` resolved to the absolute path, as A4's lock calls do: a Bash call has no `CLAUDE_PROJECT_DIR` and its cwd
can drift, while the hook reads the marker under the project the session started in.

- **Arm** as the last tool call of every turn that ends waiting on the human, and print its `LINE=` verbatim as the last
  line of that turn's message — `Cache warm until HH:MM — answer later → <the restart>`, or `Cache expiry unknown — …`
  when the tap cannot say. The sites: the orphan question and the plan gate (ap), the a5 sign-off question, and every
  `⛔` stop after the lock is taken (a0 and the Pre-Assertions stop before anything ran, and their message is the restart
  already): <!-- craft:cache-guard arm --> write the log line first, as the log rule says, then arm, then print the stop's
  block with the line last.
- **Disarm** <!-- craft:cache-guard disarm --> at the start of every invocation, right after the lock is taken — an
  earlier invocation's stop may have left it armed — and, in ap and a5, when the human's answer arrives. A builder
  spawn disarms it too (a2): a hand-back that met an armed guard after an hour would read the stale expiry as cold. The
  hook passes a hand-back by its markup as a second line of defence, not as the plan.
- **The restart meets A4's own-process question.** `/clear` keeps the Claude Code process, so at a stop that still holds
  the lock (the plan gate, a5) the re-run's A4 asks whether the run from this session still works — the human answers
  `[N]`, it ended.
- **A guard that cannot arm is never a stop.** `ARMED=no`, a non-zero exit or no output costs only a late re-write: print
  one line `⚠ cache guard not armed: <REASON, or the ERROR=>` — and `LINE=` when the helper still gave it — and go on
  with the stop as it was.

### a1 — Run-start briefing (once per invocation, before its first slice step — a2's spawn, or a3 for a slice resumed at `committing`)

Emit the briefing block (Output Format → *Autopilot — briefing*): builds in place on `<epic-branch>`, `main` untouched
until the end; the checkout is occupied — do not edit files or switch branches in it while the run lasts; the slice
order with what step 1c found (to build, to resume, landed); where it stops for you; how to stop (Esc — a re-run of
the same command resumes from disk) and that a stopped run is resumed the same way. When ap showed the plan gate in
this invocation, the human has just read those lines there: print only the order line. Then log
`▶ · <epic-id> · run started`.

**Every invocation, a re-run included** — slice-056's probe 3 re-ran without the briefing. The log helper holds it: a
slice step (a2's `▶` line, a3's `✓` line) is refused with `ERROR=gate:no_run_started` until the log holds this
invocation's `run started` — one at or after the lock's `SINCE=`. A refusal means a1 was skipped: emit the briefing,
log `run started`, then write the refused line again. Any other `gate:` error (the lock not held for this epic) stops the
run as *The Autopilot Log* says.


### a2 — Build a slice: s2 with a foreground builder

Replaces s2's *Delegate Phase 4–8* bullet — the master never runs the phase commands itself. Before the spawn run the
budget guard's `before` gate (above); a stop ends the run there. A `go` with `MODE=conservative` → print its `REASON`
once, before the spawn, so the human knows this run stops after this slice (the `▶` line's `usage unknown` is the
record). Otherwise — and then — log
`▶ · <slice-id> · slice <k>/<n> "<title>" — <create | resume at <Status>> · <LOG_FIELD>` — the slice-ID
as its ID, the budget helper's `LOG_FIELD=` verbatim as the text's **last** ` · ` field (`five_hour <p> % until
<HH:MM>`, or `usage unknown`): a3's `after` gate reads the slice's Δ five_hour from it — then run the budget guard's
log check (`start`), and only then print the line. For `ACTION=create` nothing is set up: the checkout is already on
the epic branch.

Disarm the cache guard first <!-- craft:cache-guard disarm --> (*The cache guard*). Spawn `slice-builder` via `Task` exactly as step 5 does — the model settled per step 5's model bullet, the slice plan as
its target — with the **main checkout** as its working directory and the note that this is an autopilot run on
`<epic-branch>` (the agent's *In an autopilot run* paragraph). No worktree is created and no `.primed` marker is
seeded: this checkout is already primed.

- **The spawn must return in the foreground.** The Agent result is final (`completed`). If it came back launched in
  the background instead, do not start anything else: wait for the builder's report, then stop the run as below with
  `⛔ … background spawn — check CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`.
- **Classify the outcome** as step 6 does — its four states, the live marker read with `handoff-marker-state.sh .`
  in the main checkout. **A budget stop** is Held: the builder's paused line carries `reason=budget` and the guard's
  `REASON`, no marker was written and the plan is still at its execution status → print and log
  `⛔ · <slice-id> · stopped: budget — <REASON>` — this one `⛔` line, not the Handoff line below — then release the lock
  and emit *Autopilot — stopped* with status `budget`. The human's step is only the re-run, as the budget guard's
  stop bullet says (step 1c resumes the slice, its work still uncommitted in this checkout). **Success** (`Status: committing`) → a3.
  **Handoff, Failure, Held at start** → stop the run:
  print and log `⛔ · <slice-id> · stopped: <marker Status or plan Status> — <what the human does>`, release the lock and
  emit *Autopilot — stopped*. What the human does is what step 8 says for a stopped slice, run in the main checkout
  (no `/craft:checkout`: the slice is built here). A slice stopped at `blocked` shows its plan's `## Blocker` below the
  `⛔` line, as written — for a review the ping-pong breaker tripped (`commands/review.md` → Step 9) that is the
  escalation package, at most 15 lines. Name a file for the human to remove or edit only after checking,
  in this invocation, that it exists — slice-049's human test was sent to remove a file that was already gone — and
  never the lock: its only human path is A4's `release --force` line; afterwards `/craft:execute <epic-NNN> --autopilot` resumes it —
  step 1c reads it as `ACTION=resume`. Every stop this bullet classifies arms the cache guard <!-- craft:cache-guard arm -->
  once its `⛔` line is logged, before the stopped block is printed (*The cache guard*).

### a3 — Land the slice on the epic branch: s3 at Level 2

**First, record the slice for the human** — every slice that reaches a3, from a2's Success or from s2's resume at
`committing`, and before `/craft:commit` closes its plan:

1. **How Phase 5 was passed.** Read the slice plan's `## Verification Evidence`. Its last round counts as *verified by
   command* when it is a full run — its heading carries no ` · only:` (a subset round of the debug loop never
   counts, and a full run always follows it) — its result line reads `- result · pass · <p>/<n> checks passed` **and** no review loop-back came after
   it: its heading carries `review rounds: <N>` (the review rounds the plan held when it ran), and no
   `**Review round <R> → loop-back to Phase 4**` decision in the plan has `<R>` greater than `<N>` — a pass before a later
   loop-back never saw the code that lands. A heading without `review rounds:` counts only when the plan holds no
   loop-back decision at all. Otherwise Phase 5 was passed by the human (`[W]`). Hold the phrase for the landed line:
   `verified by command (<p>/<n>, run <r>, <round datetime>)` or `Phase 5 by you ([W])`.
2. **The demo block** — skip it when `## UX Demo Script` already holds a `### <slice-id> —` block (a re-run). Otherwise
   append it as the last lines of that section, never rewriting an earlier block. A missing section goes directly above
   `## Autopilot Log`, or at the end of the file. On the first append, drop the section's `(no slices landed yet)` line
   (or an older `(no slices verified yet)`):

   ```
   ### <slice-id> — <title>
   - Trigger: <the slice plan's ## Trigger, verbatim>
   - Try this: <the steps `/craft:test` 5a derives from that trigger — its Demo-Setup table: the click sequence, the
     exact command, the request, …>
   - Expected: <the slice plan's ## Effect, verbatim>
   - Checked by: <the verify block's check names, comma-separated — or "none">
   - Phase 5: <the phrase from 1>
   ```

Then land it. Run `/craft:commit` following its **Autopilot Mode** section: the split without confirmation,
every decision `[K]`, the commits and the archive on the epic branch, the plan closed, and no landing step — the epic
branch **is** the landing. **Any** `/craft:commit` stop — a pre- or post-assertion, a failing `git commit` (a
pre-commit hook), a Step-7 failure — stops the run like a Handoff (a2). Only when `/craft:commit` completed, run the
budget guard's `after` gate with `--slice <slice-id>`, then log
`✓ · <slice-id> · landed on <epic-branch> (<first>..<last>) · <the phrase from 1> · <LOG_FIELD>` — one
`✓` per landed slice, the slice-ID as its ID, the budget helper's `LOG_FIELD=` (`Δ five_hour <+n|?> %`) verbatim as the
text's **last** field: the forecast of every later `before` gate is the mean of these. No `LOG_FIELD=` line → write
`Δ five_hour ? %`, and check against that. Run the budget guard's log check (`landed`), then print the line. Hold the
`after` gate's `VERDICT=` for a4.

### a4 — No halt between slices: s4

Replaces s4. **First the budget:** when a slice of the epic is still to build, a3's `after` verdict `stop` (or no
`VERDICT=` line) stops the run as the budget guard says — with the *stopped after a landed slice* block — without a reading the run stops after every slice
(conservative mode), and the human's re-run is the answer. After the epic's last slice it does not stop: a5 follows.
Without a halt, **run the step-1c helper once more** — the same command, `--slices-from <epic-plan>` and no slice
list — the slice just landed now reads `ACTION=skip` — and act on it exactly as step 1c does. **A `RESULT=conflict`
or a helper that cannot run stops the run here** — log `⛔ · <epic-id> · re-run state: <each conflict's SLICE and REASON,
or RESULT_REASON, or the ERROR=>`, release the lock and emit *Autopilot — stopped after a landed slice* with status
`re-run state` and step 1c's fix for each REASON — it replaces step 1c's abort message here — and never
goes on to a5: a5 is reached only from s1, over lines that read `RESULT=ok` (slice-057's probe 1 read a conflict and
went on to a5). Then go back to s1 with those fresh lines; the step-1c lines from before the landing still name the landed slice
`resume`, and s1 would pick it again (slice-049 review R1). s1 sends the run to a5 once every slice has landed. (s0
does not apply: an autopilot slice never waits on a PR.) s1's stop on a held slice is a stop like a2's: log it `⛔`.

### a5 — Epic end: digest and sign-off

Replaces s5. Every slice of the epic now reads `ACTION=skip`. **The digest is generated, never written** — run the
helper `scripts/epic-digest.sh` from the project root,

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-digest.sh" "<epic-plan>"
```

and print its stdout **unchanged**: every line, in order, nothing added inside it, nothing left out, no summary in its
place. That output is the *Autopilot — epic complete* block; what it holds is defined once, in the helper's header.
slice-056's probes wrote this block from context: the candidates paraphrased, the demo script retold, a verification
dated `2021-…`. The human decides here whether a candidate becomes a later slice. An `ERROR=` (a
non-zero exit) stops the run instead: print and log `⛔ · <epic-id> · digest failed: <reason>` and release the lock —
nothing was asked, nothing merged.

Then — **the lock still held** — log `▶ · <epic-id> · sign-off asked`. The log helper checks that the line landed, so
its exit 0 **is the check by command** before you ask. Any other exit — the write was refused or never landed (a human
test's auto-mode classifier denied it, slice-057 BUG-1) — stops the run instead: print
`⛔ · <epic-id> · sign-off not logged: <ERROR=>` — printed only, the log is what failed — and release the lock —
nothing was asked, nothing merged. Otherwise arm the cache guard <!-- craft:cache-guard arm --> (*The cache guard*) and ask, Level 0 — the question's last
line is the helper's `LINE=`. The UX demo script is the product-feel check the verification did not replace: walk it
before you answer.

```
Merge <epic-branch> into <trunk>?
  [Y] yes — direct: git checkout <trunk> + git merge --no-ff <epic-branch>;
            pull-request + Protected-main: push <epic-branch> and open the PR (you approve and merge on GitHub)
  [N] no  — leave <epic-branch> as it is; nothing else changes
```

Only the human's answer ends the run, and it disarms the cache guard first <!-- craft:cache-guard disarm -->. Each answer writes its `■` line, **checks it by command** — the
log helper's exit 0 — and **then** releases the lock (step 1). An answer whose action
failed writes the `⛔` line its bullet names instead, checked the same way, and the run stops there. A `■` or `⛔` line
that did not land stops the run with the lock **held** — the one exception to step 1's release on an abort: print
`⛔ · <epic-id> · not logged — run this once the cause is fixed:` — printed only, the log is what failed —
then the refused log call, then A4's `release --force` command, each as its own code block, both paths resolved — the
answer it records has been acted on or attempted, and the log must say so before the lock is released. P4 then reports
the held lock; that is expected, and the calls above are the remedy. Every `<reason>` in an a5 line is one line — the
error's first line — since the log helper refuses a text with a line break (*The Autopilot Log*).

- **[Y], `direct`** → `git checkout <trunk>` then `git merge --no-ff <epic-branch> -m "Merge <epic-NNN>: <epic title>"`.
  A conflict: surface it, never resolve it, and log `⛔ · <epic-id> · merge into <trunk> conflicted`; the checkout is
  left on `<trunk>` mid-merge, and the human chooses the way out — `git merge --abort`, then a re-run asks again; or
  resolve, `git commit`, and log `■ · <epic-id> · merged into <trunk>` with the log helper's call — print that call as its
  own code block, the plugin root resolved, since the human's shell has no `${CLAUDE_PLUGIN_ROOT}`. Otherwise log
  `■ · <epic-id> · merged into <trunk>`, then release the lock, and end with `Recommended next: /craft:commit` — it closes
  the epic (its Epic-close mode, D37).
- **[Y], `pull-request` + `Protected-main: yes`** → `git push -u origin <epic-branch>`, then
  `gh pr create --base <trunk> --head <epic-branch> --title "Merge <epic-NNN>: <epic title>" --body "$(printf '~~~~~~\n'; bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-digest.sh" "<epic-plan>"; printf '~~~~~~\n')"`
  — the body is the helper's output, generated again and never retyped, fenced so that GitHub keeps its lines and
  indents. A failed push or `gh pr create`: log
  `⛔ · <epic-id> · PR not opened: <reason>`. Otherwise log `■ · <epic-id> · PR #<N> opened`, then release the lock.
- **[N]** → log `■ · <epic-id> · complete, not merged`, then release the lock.

**No answer is no answer.** When the session ends at the question — the human closes it, a `-p` run is over — nothing
more is written: no `■` line, the lock stays `held`, and the Post-Assertions have not run (they follow an answer). A
`▶ … sign-off asked` line with no `■` or `⛔` line after it is exactly that state. A re-run of `/craft:execute <epic-NNN>
--autopilot` finds every slice `ACTION=skip`, comes straight back here and asks again; its lock step takes the ended
session's lock over (`execute-lock.sh`'s takeover rule — the owner no longer runs). Never log `■` for a question
nobody answered, and never release the lock before the answer: a later `[Y]` would merge unlocked (slice-056's probes 3
and 4 did both).

The epic plan stays in `.claude/plans/` when the run ends — the run itself never closes the epic. After a `direct`
merge, `/craft:commit` does (its Epic-close mode, D37): the epic's decisions, its archive, its plan and its
branch. After `[N]` or a PR it does not.

---

## Post-Assertions

Run all of the following after the procedure completes. P1 and P3 apply to the parallel worktree path only; P5 to the in-place path; P6 to the sequential epic path; P7 to an autopilot run. Any failure → warn loudly. No auto-rollback.

### P1 — Worktrees exist for every spawned slice

*(Worktree path only — in-place mode creates no worktrees; see P5.)*

`Bash` `git worktree list --porcelain` must show every slice-worktree created or reused this run (or, for succeeded slices that have been merged, the worktrees must still exist — cleanup happens at Phase 9 `/craft:archive`). A slice step 1c skipped needs no worktree.

Failure → *"⚠ Worktree accounting mismatch — expected `<list>`, found `<list>`. Run `/craft:worktree-status` and reconcile manually."*

### P2 — Slice plans have correct Status

Each succeeded slice's plan file has `Status: committing` (cleared review); each stopped slice has `Status: paused` with the Pause Note filled, **or** `Status: blocked` with the `## Blocker` section filled (a slice that escalated on `awaiting-block-decision`), **or** — for a slice stopped on `awaiting-rethink-decision` — the plan status `/craft:review` → Subagent Mode leaves it at, with open lines in `## Review Findings`. No slice is left with `Status: implementing` — except, in an autopilot run, a
slice the budget guard stopped (`reason=budget`): it stays at the execution status it stopped at, which the re-run
resumes, and P7 checks it. In **in-place** mode the single slice ends at `Status: awaiting-release` (Phase 4 done, halted before Phase 5).

Failure → *"⚠ Slice `<id>` has Status `<X>` after execute — should be `<expected>`. Inspect `<path>`."*

### P3 — Epic-branch merge commits match succeeded slices

For an epic target: `Bash` `git -C <epic-worktree> log --merges --first-parent` must list one merge commit per succeeded slice. For a lone slice: skip.

Failure → *"⚠ Epic-branch is missing merge commits for slices: `<list>`. Re-running `/craft:execute` will retry."*

### P4 — Lock released

Only when this invocation took the lock (step 1) — an abort in A4 or at step 1's refusal leaves another run's lock as it
is. After the command returns, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/execute-lock.sh" check --project "<project-root>"`
must report `LOCK=released`.

Failure → *"⚠ Execute lock not released (`LOCK=<state>`, `REASON=<reason>`). The next `/craft:execute` run in this
Claude Code session asks you whether this run has ended; from another process, release it with"* — followed by A4's `release --force` command,
printed the way A4 prints it: its own top-level code block.

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

### P7 — Autopilot run ended cleanly (autopilot run only)

`git worktree list --porcelain` shows only the main worktree; the trunk points where it pointed before the run, unless
a5 merged on the human's yes; the epic plan's `## Autopilot Log` and the epic branch agree **in both directions** —
every `✓` on a slice-ID names a slice whose archive exists and whose `Slice:` commits are on the epic branch (`git log <epic-branch>
--grep "Slice: <slice-id>"`), and every slice landed in this invocation has its `✓` line, ending in a `Δ five_hour` field;
every `▶ slice` line this invocation wrote ends in the `before` gate's `LOG_FIELD`; and the run ended
at a `⛔` stop (the checkout on the epic branch, the stopped slice's plan at the status it stopped at), at ap step 0's
or the plan gate's `[N]`, or at a5. When **ap** ran in this invocation: `.next-id` lies past every ID its `planning` line allocated, every `planned from
entry` line this invocation wrote names a plan that `epic-entry-link.sh resolve` reports `STATE=plan` or `landed`, and a slice was built only
after a `plan gate approved` line that `plan-gate-state.sh` reads as covering every pipeline plan (`RESULT=clear`).
When **4b** ran: every `plan review round <n>` log line has its `### Round <n>` in `## Plan Review`, the `auto` rounds
after the last `first` round number at most two, and no `ARCH_MALFORMED` line `plan-gate-state.sh` reports lies in a
round this invocation wrote (an older one the gate already showed the human).

Failure → *"⚠ Autopilot run in an unexpected state — inspect `git log <epic-branch>`, the trunk, `## Autopilot Log`
and the slice plans."*

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

Autopilot — plan gate (ap):

```
▶ Autopilot plan gate — epic-<NNN> "<title>": <k> slice(s) planned by agents, awaiting your approval
   slice-<a> "<title>" — <## Goal sentence>
      Trigger: <one line>   Effect: <one line>   Test: <one line>
      Sub-tasks: <n>   Depends-On: <ids or none>   Checks: <n verify checks>
      NEEDS-HUMAN: <the question, as written>          (only when open)
      ⚠ <failed check>                                 (only when one failed)
   …
   ⛔ slice-<NNN> (entry `<entry>`) could not be planned: <reason>   (only for a failed entry — its reserved ID)
   Plan review: <ARCH_ROUNDS> round(s), <ARCH_AUTO_LEFT> autonomous revision(s) left   (or: ⚠ the plan review did not run)
      P<n>-<k> · <slice-ids> · <kind> · <revise|note> · <text>   (every open finding — they do not withhold [Y])
      ⚠ unreadable plan-review line <n> — correct it by hand in `## Plan Review`; autonomous revision stays off until then
   How the run will go: <a1's briefing lines — branch, occupied checkout, order from Depends-On, stops, Esc / resume>
   [Y] approve and run   [R] <slice-id>[, …] — <note>: revise these   [N] stop, keep the plans
   ([Y] is offered only when no check, entry or NEEDS-HUMAN above is open or failed — plan-review findings do not withhold it.)
   <the cache guard's LINE=, verbatim — the block's last line>
```

Autopilot — briefing (a1):

```
▶ Autopilot run — epic-<NNN> "<title>"
   Builds in place on <epic-branch>; <trunk> is not touched until you say yes at the end.
   This checkout is occupied: do not edit files or switch branches here until the run stops.
   Order: slice-<a> (build) → slice-<b> (resume at <Status>) → …   [landed: slice-<x>, …]
   Stops for you at: Phase-5 checks that are refused or missing, a bug the autonomous debug loop could not fix, review
   ping-pong (a finding whose one autonomous loop-back did not hold, or the round cap), scope questions, blockers,
   failures, the usage budget (the limits in craft-profile.md → ## Autopilot; without a usage reading after every
   slice) — and at the end (with the UX demo script).
   Stop:   Esc.   Resume after any stop:   /craft:execute epic-<NNN> --autopilot
```

Autopilot — stopped (a2):

```
⛔ Autopilot stopped at slice-<id> "<title>" — <status | budget>
   <the plan's ## Blocker, as written — only for a blocked slice>
   <what you do, from the marker or the plan — in this checkout, no /craft:checkout; for budget: the REASON, then
    when to re-run — after <the reset time it names> | now (no usage reading) | after wiring the tap | after fixing <what failed>>
   Landed so far on <epic-branch>: <N> of <M>
   Then:   /craft:execute epic-<NNN> --autopilot    (resumes this slice)
   <the cache guard's LINE=, verbatim>
```

Autopilot — stopped after a landed slice (a4: budget, or re-run state):

```
⛔ Autopilot stopped after slice-<id> "<title>" landed — <budget | re-run state>
   <budget: the REASON, then when to re-run, as above · re-run state: each conflict with step 1c's fix for its REASON>
   Landed so far on <epic-branch>: <N> of <M>
   Then:   /craft:execute epic-<NNN> --autopilot    (resumes the run)
   <the cache guard's LINE=, verbatim>
```

Autopilot — epic complete (a5): the stdout of `scripts/epic-digest.sh`, relayed unchanged — its header defines the
block, so it is not restated here — followed by a5's merge question:

```
<epic-digest.sh's output, every line as printed>
Merge <epic-branch> into <trunk>?   [Y] yes   [N] no
<the cache guard's LINE=, verbatim>
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
| A4 stops (lock held by another live process, or unreadable) | Abort with the owner, target and reason, plus the copy-ready `execute-lock.sh release --force` line; only the human runs it, and only when no run is active. The lock file is never removed. |
| A4 `confirm` (lock held by this session) not answered `[N]` | Abort: a run from this session is still working — re-run once it has ended and answer `[N]`. No `--force` line, and nothing is released. |
| A6 fails (cycle / missing dep) | Abort. Name the cycle or missing slice. |
| `git worktree add` fails despite step 1c (the state changed since, e.g. a concurrent manual `git worktree add`) | Abort the affected slice cleanly; other slices may still proceed. List the collision in the final output. |
| Subagent crashes mid-Phase | Treat as Failure (step 7). Continue with other independent slices. |
| Slice's `/craft:review` blocks with Heavy + needs-rethinking | Treat as Handoff. The slice's worktree is intact for `/craft:checkout`. |
| User interrupts (signal, `/craft:pause`) | Drop into pause: <!-- craft:writes status=paused --> pause every slice whose `slice-builder` is still running (not yet collected as Success, Handoff, Held or Failure) and that is not `blocked` — `Status: paused` with the pause record (`skills/workflow/SKILL.md` → **Pause record**) and a Pause Note — in the plan copy that slice is built from: the slice worktree's in parallel mode, the main checkout's in in-place and sequential mode. Slices already stopped keep their plan and marker untouched. Release the lock, stop. |
| P1–P4 fail | Warn loudly. The user reconciles manually. Do not retry automatically. |
| Autopilot (a0): background tasks not disabled, or the checkout is on neither the epic branch nor a clean trunk | Stop before anything is created — a0 runs before the lock, so none is held — with the launch command or the branch to fix (for a dirty trunk while a slice is in flight: `git checkout <epic-branch>`, a0 item 3). |
| Autopilot (ap): `plan-gate-state.sh` cannot run, `.next-id` is not an integer, or the second A6 after `[Y]` rejects | Stop `⛔` and release the lock; nothing is built. The gate is never assumed passed. |
| Autopilot (ap): a planner returns `FAILED`, returns nothing, or its entry cannot be linked | The entry is *failed*: logged `⛔`, its ID stays reserved, and the gate lists it and withholds `[Y]` — `[R]` re-plans it, `[N]` leaves it to the human. A link that failed leaves its written plan behind unlinked: the next run reports it as an `ORPHAN` (ap step 0) — link it by hand or `/craft:abort` it. |
| Autopilot (ap 4b): `plan-architect` returns no `RESULT` line twice | Log `⛔ · <epic-id> · plan review failed`; the gate shows that the review did not run and still offers `[Y]` when nothing else withholds it — the human decides whether to run without it. |
| Autopilot (ap): active plans no entry links while entries are unplanned | Step 0 asks before any planner runs: `[P]` plan anyway, `[N]` stop and link or abort them first. The master never decides that a plan refines an entry. |
| Autopilot (a2): a spawn came back in the background | Wait for that builder's report, then stop the run (`⛔`); start nothing else. |
| Autopilot: the human presses Esc during a spawn | The exception to the interrupt row above: the run ends where it was, and nothing is paused or rewritten for it — a paused slice would be `held` and need a `/craft:continue` before the re-run, where a slice left at its execution status simply resumes: the slice plan keeps the status the builder last wrote and the lock stays held — a re-run from the same Claude Code session finds it `DECISION=confirm` (`REASON=own_process`) and A4 asks whether the run ended — it did, so answer `[N]` — from another one A4 names it; re-run `/craft:execute epic-<NNN> --autopilot`; step 1c reads the slice as `ACTION=resume`. |
| Autopilot (a5): the merge into the trunk conflicts, or the push / `gh pr create` fails | Stop; surface it, log and check its `⛔` line, then release the lock (a5). Never resolve a conflict; the epic branch is intact, the checkout stays on the trunk mid-merge — `git merge --abort` and re-run, or resolve, commit and log `■` through the log helper's call a5 prints (a5). |
| Autopilot (a5): `epic-digest.sh` reports `ERROR=` | Stop `⛔` and release the lock before anything is asked; the `ERROR=` names the slice, archive or section to fix. Never write the digest by hand instead. |
| Autopilot (a5): the session ends before the merge question is answered | Nothing more is written — no `■` line, the lock stays held. A re-run asks again and takes the lock over (a5, *No answer is no answer*). |

---

## What This Command Does NOT Do

- It does **not** plan — outside an autopilot run. Run `/craft:plan` (slice) or `/craft:epic` (epic) first. (An autopilot run plans an epic's unplanned entries in **ap**, behind the plan gate.)
- It does **not** merge the epic-branch (or lone-slice-branch) into `main`. `/craft:commit` does that, after user review. The one exception is an autopilot run's a5, and only on the human's `[Y]`.
- In an **autopilot run** it does **not** remove a human stop, run the phase commands in the master, judge a plan's content (the planners and the human at the gate do — *Who decides what*), build anything the plan gate has not approved, write `intent.md` / `rules.md`, push anything but the epic branch on a5's `[Y]` under protected main, or close the epic plan.
- It does **not** clean up worktrees. `/craft:archive` (Phase 9) does that after the user has confirmed merge-to-main.
- It does **not** auto-resolve Heavy + needs-rethinking findings. Those escalate to the user via Handoff.
- It does **not** modify `intent.md` or `rules.md`. Architectural decisions surfaced inside a slice live in that slice's `## Decisions Made During This Slice` for Phase 9 promotion.
- It does **not** push to remote. No `git push` happens here — that is a separate user step.
- In **in-place** mode (single-slice) it does **not** create a worktree, does **not** auto-commit, and does **not** run past Phase 4 — it halts before Phase 5 and hands off to `/craft:release`. An **epic** target follows its `Epic Mode` regardless of `Execution → Mode` (A7), running in place via `Epic Mode: sequential`.
- In **sequential epic** mode (`Epic Mode: sequential`) it does **not** create worktrees or an epic-branch, and does **not** run slices in parallel — it lands the epic's slices one-by-one in place and halts for review between slices (resume by re-running `/craft:execute <epic>`). Each slice lands per the Merge Workflow: committed directly on the trunk (`direct`), or via its own approved PR that the human merges through the "Freigabe ≠ Merge" gate (`pull-request` + `Protected-main: yes`), with the local trunk synced after each merge.
