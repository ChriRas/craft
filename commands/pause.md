---
description: Pause the active slice mid-phase. Records the pause note in the slice plan; slice stays open and resumable. Use when stepping away or context-switching.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /craft:pause — Pause the Active Slice

## Purpose

Cleanly stop work on a slice without abandoning it. The slice file stays in `.claude/plans/`, but is marked paused with a short note so that the next `/prime` and `/craft:continue` know where to pick up.

---

## Pre-flight

- `Glob` `.claude/plans/*.md`. Find the slice the user wants to pause:
  - If exactly one active → use it.
  - If multiple → ask which.
  - If none → tell user there is nothing to pause and stop.

---

## Procedure (Autonomy Level 1)

### 1. Capture a short pause note

Ask: *"Quick note on where we are and what's next? (one or two sentences — saves you re-deriving later)"*

If user provides nothing, the agent composes a minimal note from current state ("Paused at Phase X, sub-task Y/Z — next was: <agent's best guess>"). Show it, let user confirm or override.

### 2. Update the slice plan

<!-- craft:writes status=paused -->
- Set `Status: paused` in the frontmatter.
- Append (or overwrite) a `## Pause Note` section:

  ```markdown
  ## Pause Note

  > Paused: <ISO date>

  <user's or agent's note>
  ```

### 3. Confirm

```
✓ slice-<NNN> paused.

Pause note: <one-line excerpt>

Resume anytime with /craft:continue.
```

---

## Output Format

The status line above.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice is already `paused` | Update the note (with prior note preserved in an `## Earlier Pause Notes` rolling section). |
| Slice is in `committed` status | Stop with: *"Slice already closed. Nothing to pause."* |
| User wants to pause without any note | Allow, but write `(no note)` so the entry is still visible to the next session. |

---

## What This Command Does NOT Do

- It does **not** modify code, commits, or any project state outside the slice plan.
- It does **not** end the session. The user does that.
- It does **not** abort the slice. Use `/craft:abort` for that.
