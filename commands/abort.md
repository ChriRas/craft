---
description: Abandon a slice. Asks confirmation, then deletes the plan file by default. Aborted slices have no archive value — they leave only their (possibly partial) commits behind, which the user manages separately.
argument-hint: "<slice-NNN>"
allowed-tools: ["Bash", "Read", "Glob"]
---

# /abort — Abandon a Slice

## Purpose

Discard work on a slice that won't be completed. The slice plan file is deleted by default — aborted slices are not archived (the archive is for completed slices that earned their place via Phase 8).

If partial commits exist, they remain in the git history and the user is responsible for cleanup (revert, branch reset, etc.) as appropriate.

---

## Pre-flight

- Argument `<slice-NNN>` is required (no defaulting to "the active slice" — abort is destructive and should be explicit).
- `Glob` `.claude/plans/slice-<NNN>-*.md`. If not found → tell user the slice is not in the active plans directory and stop.

---

## Procedure (Autonomy Level 0)

### 1. Show what would be aborted

`Read` the slice plan and surface:

```
About to abort:
  Slice: slice-<NNN> "<title>"
  Phase: <X>
  Status: <status>
  Sub-tasks done: <Y>/<Z>
  Started: <K> days ago
```

### 2. Check for partial commits

Run `git log --grep "Slice: slice-<NNN>"` to find commits already made for this slice. If any:

```
⚠ <N> commits already exist for this slice:
  <hash>  <subject>
  <hash>  <subject>
  ...

These commits will REMAIN in git history. If you want them removed, you must do that manually (git reset, git revert, branch operations).
```

### 3. Confirm

Ask:

```
Confirm abort? Type the slice ID exactly to confirm:
  > slice-<NNN>
```

Only proceed if the user types the exact slice ID. Anything else aborts the abort.

### 4. Delete the plan file

`rm .claude/plans/slice-<NNN>-<slug>.md`

If the slice plan had a `## Handoff` section that the user might still want, ask one more time before deletion: *"This slice has a Handoff section. Sure you want to delete it?"*

### 5. Confirm completion

```
✓ slice-<NNN> aborted. Plan file deleted.

[If commits existed:]
Note: <N> commits remain in git history. Manage manually if cleanup is needed.

Recommended next: /status to see remaining active slices, or /plan for new work.
```

---

## Output Format

The status line above. Nothing else.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Argument missing | Stop with: *"`/abort` requires a slice ID. Run `/status` to see active slices."* |
| User confirms with wrong slice ID | Stop with: *"Confirmation mismatch. Abort cancelled. Try again with the exact ID."* |
| Slice has unsaved work (status shows recent edits) | Surface the recency: *"This slice was last touched <N> minutes ago. Sure you want to abort?"* Ask once more. |
| User wants to move to `_aborted/` instead of deleting | Allow if the user explicitly says so — `mv` instead of `rm`. But never default to archiving aborted slices. |

---

## What This Command Does NOT Do

- It does **not** delete or modify commits. Git history is the user's responsibility.
- It does **not** clean up branches.
- It does **not** archive the aborted slice. Aborted work is not Decision-Log material.
- It does **not** abort silently. Always requires the typed slice-ID confirmation.
