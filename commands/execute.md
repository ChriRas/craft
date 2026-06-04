---
description: Autonomously execute an epic or single slice — creates parallel git worktrees, delegates Phase 4–7 to subagents per slice, merges slice-branches into an epic-branch, stops for human review at epic-end.
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

### Step 2 — Resolve target

The argument is `epic-NNN` or `slice-NNN`. If absent, abort: *"`/craft:execute` requires a target (`epic-NNN` or `slice-NNN`). Run `/craft:epic` or `/craft:plan` first, then call `/craft:execute <target>`."*

---

## Pre-Assertions

Run all six. Any failure stops the command before any worktree is created.

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

### A4 — No concurrent execute run

Check for `.claude/plans/.execute.lock`. If present, abort: *"Another `/craft:execute` is in progress (lock file `<path>` exists with PID `<pid>`). Wait for it to finish or remove the lock manually if it crashed."*

### A5 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON with a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in epic/slice frontmatter. Re-install the plugin."*

### A6 — DAG resolvable

For an epic target: read every slice plan referenced in `## Slice Decomposition`. For each, read the `Depends-On:` frontmatter. Build the dependency graph. Reject if a cycle is detected, or if a referenced slice plan does not exist.

For a single slice target: trivially one-node graph. If the slice has `Depends-On: [...]` entries that are not yet committed (not present in `.claude/project/slices/`), abort: *"`slice-NNN` depends on slices that have not yet been committed: `<list>`. Either commit them, run them as an epic, or remove the dependency."* Note: lone-slice mode performs only a depth-1 dependency check; transitive cycles via already-archived slices are not re-validated because archived slices were cycle-checked at their own execute time.

Failure → abort with the specific issue: cycle, missing slice plan, or unresolved dependency.

---

## Procedure (Autonomy Level 2 inside plan scope, Level 0 for the final commit)

### 1. Acquire the lock

Write `.claude/plans/.execute.lock` containing the current PID and the resolved target. Lock is released in Post-Assertions (or on graceful abort).

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

## Post-Assertions

Run all four after the procedure completes. Any failure → warn loudly. No auto-rollback.

### P1 — Worktrees exist for every spawned slice

`Bash` `git worktree list --porcelain` must show every slice-worktree created this run (or, for succeeded slices that have been merged, the worktrees must still exist — cleanup happens at Phase 9 `/craft:archive`).

Failure → *"⚠ Worktree accounting mismatch — expected `<list>`, found `<list>`. Run `/craft:worktree-status` and reconcile manually."*

### P2 — Slice plans have correct Status

Each succeeded slice's plan file has `Status: committing` (cleared review) or `Status: reviewing` (open finding); each stopped slice has `Status: paused` with the Pause Note filled. No slice is left with `Status: implementing`.

Failure → *"⚠ Slice `<id>` has Status `<X>` after execute — should be `<expected>`. Inspect `<path>`."*

### P3 — Epic-branch merge commits match succeeded slices

For an epic target: `Bash` `git -C <epic-worktree> log --merges --first-parent` must list one merge commit per succeeded slice. For a lone slice: skip.

Failure → *"⚠ Epic-branch is missing merge commits for slices: `<list>`. Re-running `/craft:execute` will retry."*

### P4 — Lock released

`.claude/plans/.execute.lock` must not exist after the command returns.

Failure → *"⚠ Execute lock not released. Remove `.claude/plans/.execute.lock` before the next `/craft:execute` run."*

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
