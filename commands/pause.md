---
description: Pause the active slice mid-phase. Records the pause note in the slice plan; slice stays open and resumable. Use when stepping away or context-switching.
allowed-tools: ["Bash", "Read", "Edit", "Glob"]
---

# /craft:pause — Pause the Active Slice

## Purpose

Cleanly stop work on a slice without abandoning it. The slice file stays in `.claude/plans/`, but is marked paused with a short note so that the next `/prime` and `/craft:continue` know where to pick up.

---

## Pre-flight

- `Glob` `.claude/plans/*.md`. Find the slice the user wants to pause:
  - If exactly one active → use it.
  - If multiple → ask which. <!-- craft:choice --> Ask it with `AskUserQuestion` (one option per slice); where the tool is not available, a numbered list as text. A pick that names none of them (Cancel, no answer) pauses nothing: run Step 3 first, then stop.
  - If none → tell user there is nothing to pause, run Step 3 first, then stop.
- **The handoff, for a slice in flight.** When the picked slice is in flight (`skills/workflow/SKILL.md` → *The pause request*, rule 1: an interactive slice at `implementing`, `testing`, `review`, `refactoring`, `reviewing` or `committing`; inside a `/craft:execute` run, `commands/execute.md` handles `/craft:pause` and this bullet adds nothing), in either flow mode, the pause carries the handoff — written exactly once, before Step 2. Which call this is decides it:
  - **Sent as a prompt of its own** (idle, or queued and delivered at turn end), this command is itself the pause action's run (rule 3 of that section): nothing ran `/craft:handoff` before it, so run `/craft:handoff` for that slice now (a `## Handoff` section, `Handoff active: yes`); Step 1 then composes the note.
  - **Called by the pause action**, which ran `/craft:handoff` just before: write none again (a second `/craft:handoff` would ask "overwrite, append or cancel" in the middle of a pause).
  - A slice already `paused`, or still at `planning`, is outside rule 1: no handoff.

---

## Procedure (Autonomy Level 1)

### 1. Capture a short pause note

Ask: *"Quick note on where we are and what's next? (one or two sentences — saves you re-deriving later)"* <!-- craft:choice --> Offer the note composed from the current state as an `AskUserQuestion` option (plus one option "No note — compose a minimal one"); "Other" takes the user's own words; where the tool is not available, ask as text.

When this command is the pause action's run — the Auto flow's pause action calls it, or it arrives as a prompt of its own on a slice in flight (see Pre-flight's handoff bullet; `skills/workflow/SKILL.md` → *The pause request*) — do not ask: compose
the note from the current state and show it. Ask only outside rule 1's scope, for a slice already `paused` or at `planning`.

If user provides nothing, the agent composes a minimal note from current state ("Paused at Phase X, sub-task Y/Z — next was: <agent's best guess>"). Show it, let user confirm or override.

### 2. Update the slice plan

<!-- craft:writes status=paused -->
- Set `Status: paused` in the frontmatter, with the **pause record** (`Paused-status`, `Paused-since`) exactly as
  `skills/workflow/SKILL.md` → **Pause record** defines it — including what an already-`paused` slice keeps.
- Append (or overwrite) a `## Pause Note` section:

  ```markdown
  ## Pause Note

  > Paused: <ISO date>

  <user's or agent's note>
  ```

### 3. Settle a pause request

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pause-request.sh" consume --project "<project-root>"` (in CRAFT's own source repo
`scripts/pause-request.sh`). It settles a pause request recorded in either flow mode (`skills/workflow/SKILL.md` → *The
pause request*) — the marker `.claude/plans/.pause-request` becomes `consumed`, never removed — and is a no-op
(`CONSUMED=no`) without one. A helper that is missing or fails does not stop the pause: the slice is paused either way.

Every exit settles a request, not only the ones that pause: an exit that pauses nothing — "nothing to pause", a pick that names no slice, a `committed` or a `blocked` slice — runs this step before it stops, because a request the hook recorded for this prompt must not pause another slice later (slice A in flight, slice B blocked: the hook records for A, the user picks B, the command stops — without this step the request would pause A at its next boundary).

### 4. Confirm

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
| Slice is already `paused` | Update the note (with prior note preserved in an `## Earlier Pause Notes` rolling section). The pause record stays unchanged (**Pause record**: same episode). |
| Slice is in `committed` status | Run Step 3, then stop with: *"Slice already closed. Nothing to pause."* |
| Slice is `blocked` | Run Step 3, then stop with: *"Slice is blocked — a pause would drop the block. Use `/craft:unblock` (or `/craft:block` to re-word it)."* (**Pause record**: never over `blocked`.) |
| User wants to pause without any note | Allow, but write `(no note)` so the entry is still visible to the next session. |

---

## What This Command Does NOT Do

- It does **not** modify code, commits, or any project state outside the slice plan.
- It does **not** end the session. The user does that.
- It does **not** abort the slice. Use `/craft:abort` for that.
