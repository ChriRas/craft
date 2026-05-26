---
description: Abandon a slice. Asks confirmation, then deletes the plan file by default. Aborted slices have no archive value — they leave only their (possibly partial) commits behind, which the user manages separately.
argument-hint: "<slice-NNN>"
allowed-tools: ["Bash", "Read", "Glob"]
---

# /craft:abort — Abandon a Slice

## Purpose

Discard work on a slice that won't be completed. The slice plan file is deleted by default — aborted slices are not archived (the archive is for completed slices that earned their place via Phase 9).

If partial commits exist, they remain in the git history and the user is responsible for cleanup (revert, branch reset, etc.) as appropriate.

This command is a **durable-state mutation** (file deletion) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`.

---

## Pre-flight

### Step 1 — Argument capture

Capture `<slice-NNN>` from the command argument. No defaulting to "the active slice" — abort is destructive and must be explicit.

---

## Pre-Assertions

Run both. Any failure stops the command before any deletion happens.

### A1 — Slice ID argument present

The command argument `<slice-NNN>` must be present and match the pattern `slice-\d{3}`.

Failure → abort: *"`/craft:abort` requires a slice ID (e.g., `/craft:abort slice-007`). Run `/craft:status` to see active slices."*

### A2 — Slice plan file exists

`Glob` `.claude/craft:plans/slice-<NNN>-*.md`.

- Zero matches → abort: *"No active slice plan found for `slice-<NNN>`. Run `/craft:status` to see active slices."*
- Multiple matches → abort with the list: *"Multiple plan files match `slice-<NNN>-*`: `<list>`. This should not happen — inspect `.claude/craft:plans/` manually."*
- Exactly one match → record the path as `<slice-plan>`.

---

## Procedure (Autonomy Level 0)

### Step 1 — Show what would be aborted

`Read` `<slice-plan>` and surface:

```
About to abort:
  Slice: slice-<NNN> "<title>"
  Phase: <X>
  Status: <status>
  Sub-tasks done: <Y>/<Z>
  Started: <K> days ago
```

### Step 2 — Check for partial commits

Run `git log --grep "Slice: slice-<NNN>"` to find commits already made for this slice. If any:

```
⚠ <N> commits already exist for this slice:
  <hash>  <subject>
  <hash>  <subject>
  ...

These commits will REMAIN in git history. If you want them removed, you must
do that manually (git reset, git revert, branch operations).
```

### Step 3 — Recency warning

If the slice was last modified within the past 60 minutes (`stat`/`ls -lT` on the plan file), surface it:

```
⚠ This slice was last touched <N> minutes ago. Sure you want to abort?
```

Wait for a clear answer before continuing. Ambiguity → clean abort.

### Step 4 — Handoff warning

If the slice plan contains a non-empty `## Handoff` section, surface it:

```
⚠ This slice has a Handoff section that you may still want. Sure you want
   to delete it?
```

Wait for a clear answer.

### Step 5 — Confirm by typed slice ID

Ask:

```
Confirm abort? Type the slice ID exactly to confirm:
  > slice-<NNN>
```

Only proceed if the user types the exact slice ID (`slice-<NNN>`, including the `slice-` prefix and three-digit number). Anything else → clean abort with: *"Confirmation mismatch. Abort cancelled. Try again with the exact ID."*

### Step 6 — Delete (or, by explicit user request, move)

Default action:

```
rm <slice-plan>
```

If the user explicitly requested archival earlier ("move to `_aborted/` instead"), substitute:

```
mkdir -p .claude/craft:plans/_aborted/
mv <slice-plan> .claude/craft:plans/_aborted/
```

Archival is never the default — only on explicit user request during this command run.

---

## Post-Assertions

Run both after Step 6. Any failure → warn loudly, surface to the user, do **not** pretend success.

### P1 — Slice plan removed from active path

`Glob` `.claude/craft:plans/slice-<NNN>-*.md`.

- Zero matches → P1 passes.
- One or more matches → *"⚠ Slice plan still present at `<path>` after abort. The `rm`/`mv` may have failed silently. Inspect manually."*

### P2 — If archival was requested: archive copy exists

Only runs when Step 6 used the `_aborted/` path:

- `Glob` `.claude/craft:plans/_aborted/slice-<NNN>-*.md`. Must yield exactly one match.

Failure → *"⚠ Archival was requested but the moved file is not at `.claude/craft:plans/_aborted/`. The slice plan may have been lost. Inspect manually."*

---

## Output Format

Success (default delete):

```
✓ slice-<NNN> aborted. Plan file deleted.
✓ Pre-assertions: argument ✓, plan file located
✓ Post-assertions: plan removed

[If commits existed:]
Note: <N> commits remain in git history. Manage manually if cleanup is needed.

Recommended next: /craft:status to see remaining active slices, or /craft:plan for new work.
```

Success (archival requested):

```
✓ slice-<NNN> aborted. Plan file moved to .claude/craft:plans/_aborted/.
✓ Pre-assertions: argument ✓, plan file located
✓ Post-assertions: plan removed from active path, archive copy present

[If commits existed:]
Note: <N> commits remain in git history. Manage manually if cleanup is needed.

Recommended next: /craft:status to see remaining active slices.
```

Aborted:

```
Abort cancelled — <reason>. Slice plan untouched.
```

Partial (post-assertion failure):

```
⚠ Abort partially complete — <which assertion(s) failed>.
   Inspect `.claude/craft:plans/` manually to confirm the state.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (argument missing or malformed) | Abort with `/craft:status` hint. |
| A2 fails (no matching plan / multiple matches) | Abort with the diagnostic message. |
| User confirms with wrong slice ID | Clean abort: *"Confirmation mismatch. Abort cancelled. Try again with the exact ID."* |
| User answers "no" to the recency or handoff warning | Clean abort, plan untouched. |
| User wants to move to `_aborted/` instead of deleting | Allow only when explicitly requested during this command run — `mv` instead of `rm`. Never default to archiving. |
| P1 fails (file still present after rm/mv) | Warn loudly; user inspects manually. No auto-retry. |
| P2 fails (archival requested but file missing in `_aborted/`) | Warn loudly; user inspects manually. |

---

## What This Command Does NOT Do

- It does **not** delete or modify commits. Git history is the user's responsibility.
- It does **not** clean up branches.
- It does **not** archive the aborted slice by default. Aborted work is not Decision-Log material; archival happens only on explicit user request.
- It does **not** abort silently. Always requires the typed slice-ID confirmation.
- It does **not** auto-rollback on post-assertion failure. Partial state is surfaced for human reconciliation.
