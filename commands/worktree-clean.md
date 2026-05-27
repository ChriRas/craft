---
description: Detect orphaned CRAFT worktrees (whose plan is archived or missing) and remove them after user confirmation. Durable-state mutation.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob"]
---

# /craft:worktree-clean — Reconcile Stale Worktrees

## Purpose

Filesystem hygiene. `/craft:archive` (Phase 9) normally removes a slice's worktree and branch as part of the commit cycle. But interrupted runs, manual experimentation, or git metadata corruption can leave orphaned worktrees behind. This command finds them, lists them, and removes them after the user confirms.

This is a **durable-state mutation** and follows the Pre/Post-Assertion pattern.

---

## Pre-flight

- `Bash` `git worktree list --porcelain` to enumerate worktrees.
- `Glob` `.claude/plans/*.md` and `.claude/project/slices/*.md` to know which slice IDs are still active vs already archived.

---

## Pre-Assertions

### A1 — Project is onboarded

`Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Both must exist and be non-empty.

Failure → abort: *"Project is not onboarded. Run `/craft:onboard` first."*

### A2 — Not currently inside a CRAFT worktree

`Bash` `git rev-parse --show-toplevel` must point to the main checkout, not a CRAFT worktree. Pruning the worktree you are inside would corrupt the session.

Failure → abort: *"Run `/craft:worktree-clean` from the main checkout, not from inside a worktree. `cd` to `<main-path>` first."*

### A3 — No `/craft:execute` lock present

`.claude/plans/.execute.lock` must not exist. A live execute-run may be using the worktrees this command would prune.

Failure → abort: *"An `/craft:execute` run is in progress (lock file present). Let it finish before cleaning."*

---

## Procedure (Autonomy Level 0 for each removal)

### 1. Classify each non-main worktree

For each worktree, determine its category:

- **Active** — branch matches a slice or epic with an open plan file under `.claude/plans/`. Skip — do not propose for removal.
- **Archived** — branch matches a slice that is already in `.claude/project/slices/` AND the slice-branch has been merged into `main`. Propose for removal.
- **Orphan** — branch matches a slice-pattern but no plan file (active or archived) exists. Propose for removal with a stronger warning.
- **Stale-path** — git metadata lists the worktree but the path is missing on disk. Propose for `git worktree prune` (metadata-only cleanup).
- **Non-CRAFT** — branch does not match CRAFT patterns. Skip and surface under "Other worktrees".

### 2. Present the report

Show the user the four categories explicitly:

```
CRAFT worktree cleanup — candidates:

Archived (safe to remove — slice already in archive, branch merged to main):
  - <slice-id> at <path>  (branch: <branch>)

Orphan (no plan or archive — review before removing):
  - <slice-id> at <path>  (branch: <branch>)

Stale-path (git metadata only — `git worktree prune` reconciles):
  - <path> (branch: <branch>)

Active (NOT removed — slice still open):
  - <slice-id> at <path>  (branch: <branch>)

Non-CRAFT worktrees (NOT touched):
  - <path>  (branch: <branch>)
```

### 3. Confirm per category

Ask three lettered questions in sequence (each rendered with full legend per `skills/workflow/SKILL.md`):

```
Remove all Archived worktrees and delete their branches?
  [Y] Yes — `git worktree remove <path>` + `git branch -d <branch>` for each
  [N] No  — leave them
```

```
Remove all Orphan worktrees and delete their branches?
  [Y] Yes — same as above (use this only if you know the branches are throwaway)
  [N] No  — leave them
```

```
Prune all Stale-path entries from git metadata?
  [Y] Yes — `git worktree prune`
  [N] No  — leave them
```

### 4. Execute confirmed removals

For each confirmed category, execute the removals in series (not parallel — keeps git metadata consistent). If any single removal fails, surface the error, skip that one, and continue with the rest.

---

## Post-Assertions

### P1 — Confirmed worktrees are gone

For each Archived/Orphan worktree the user confirmed, `Bash` `git worktree list --porcelain` must no longer list it.

Failure → *"⚠ Worktree `<path>` was confirmed for removal but still appears in `git worktree list`. Inspect manually — check for uncommitted changes that blocked `git worktree remove`."*

### P2 — Confirmed branches are deleted

For each removed worktree's branch, `Bash` `git branch --list <branch>` must return empty.

Failure → *"⚠ Branch `<branch>` was not deleted (likely unmerged commits). Inspect with `git log <branch>` and remove manually if intended."*

### P3 — Active worktrees untouched

Every "Active" worktree from step 1 must still exist in `git worktree list --porcelain`.

Failure → *"⚠ Active worktree `<path>` is missing after cleanup — this should not happen. Recreate via `/craft:execute` if needed."*

---

## Output Format

```
✓ Worktree cleanup complete

Removed:
  - <slice-id> at <path>   (Archived)
  - <slice-id> at <path>   (Orphan)
  Total: <N> worktrees, <M> branches deleted.

Pruned (metadata only): <K>

Kept (Active): <N>
Skipped (Non-CRAFT): <M>
```

Aborted:

```
Cleanup aborted — <reason>. No worktrees removed.
```

Partial (some removals failed):

```
⚠ Cleanup partially completed.
   Removed: <list>
   Failed:  <list with error per entry>
   Inspect failed entries manually.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A2 fails (inside a worktree) | Abort with cd-hint. |
| A3 fails (execute lock present) | Abort. |
| `git worktree remove` fails (uncommitted changes) | Skip that entry, surface the git message, continue. Do not pass `--force`. |
| `git branch -d` fails (unmerged) | Skip with warning. Do not use `-D` (force) — preserves the user's work. |
| User says No to every category | Emit `Nothing removed. No state changed.` and exit cleanly. |

---

## What This Command Does NOT Do

- It does **not** remove Active worktrees — those belong to open slices.
- It does **not** force-remove worktrees with uncommitted changes (`--force`) or force-delete unmerged branches (`-D`). Both would risk silent data loss.
- It does **not** clean ephemeral plan files in `.claude/plans/` — Phase 9 `/craft:archive` does that.
- It does **not** touch Non-CRAFT worktrees, even if they look stale.
