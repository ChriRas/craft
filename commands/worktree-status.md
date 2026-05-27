---
description: List every active CRAFT-managed git worktree with slice/epic-ID, branch, path, last activity, and handoff-marker presence. Read-only.
allowed-tools: ["Bash", "Read", "Glob"]
---

# /craft:worktree-status — Overview of Parallel Work

## Purpose

When several slices are running in parallel via `/craft:execute`, this command gives the user a one-screen overview: which worktrees exist, what slice or epic each belongs to, how recent the activity is, and whether any have written a `.craft/handoff.md` marker requesting human input.

Read-only — no Pre/Post-Assertions.

---

## Pre-flight

- `Bash` `git worktree list --porcelain` to enumerate all worktrees attached to the current repository.
- The main worktree (the one you are calling from) is filtered out — this command only lists secondary worktrees.

---

## Procedure

### 1. Enumerate worktrees

Parse the porcelain output. For each non-main entry, capture: path, HEAD commit, branch name.

### 2. Resolve each worktree to a CRAFT target

Match branch names against the patterns from `## Worktree Settings` in `rules.md` (defaults: `<slice-id>-<slug>` and `epic-<NNN>-<slug>`). For each match, surface:

- The corresponding plan file under `.claude/plans/` (or the archive under `.claude/project/slices/` if the slice has already been committed).
- Last-modified timestamp of the plan file (or the worktree's HEAD commit, whichever is more recent) — drives the "Last activity" column.
- Presence of `<worktree-path>/.craft/handoff.md` — drives the handoff flag.

Worktrees whose branches don't match CRAFT patterns are listed too, under a separate "Other worktrees" group — they may be user-created and unrelated.

### 3. Emit the status block

---

## Output Format

```
Worktrees attached to <repo-name>:

  slice-<id>     — <title>
                   branch: <branch>
                   path:   <absolute path>
                   last:   <K> minutes/hours/days ago
                   <⚠ handoff marker present — see <path>/.craft/handoff.md if so>

  epic-<NNN>     — <title>
                   branch: <branch>
                   path:   <absolute path>
                   last:   <K> minutes/hours/days ago
                   merged: <N> slices

Other worktrees (not CRAFT-managed):
  <branch> at <path>

Total: <N> CRAFT worktrees, <M> other.
```

If no worktrees exist beyond the main checkout:

```
No active CRAFT worktrees. Run /craft:execute <epic-or-slice> to start one.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| `git worktree list` fails | Surface the git error and stop. |
| Worktree's plan file cannot be located | List the worktree under "Other worktrees" with a `⚠ no matching plan file` note. Do not guess. |
| Worktree path missing on disk (stale git metadata) | Mark it `⚠ stale — path missing` and recommend `/craft:worktree-clean`. |
| Handoff marker file unreadable | Note `⚠ handoff marker present but unreadable` and continue. |

---

## What This Command Does NOT Do

- It does **not** modify any worktree or branch.
- It does **not** open or attach to a worktree — `/craft:checkout` does that.
- It does **not** clean up stale entries — `/craft:worktree-clean` does that.
- It does **not** show full commit logs or diffs — use `git -C <worktree-path> log` directly.
