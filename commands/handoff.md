---
description: Fresh-context restart. Summarizes problem + attempts into the slice plan's ## Handoff section so a new chat session can pick up cleanly. Useful when context is poisoned or progress stalls.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /craft:handoff — Hand Off Work to a Fresh Session

## Purpose

When the current chat session has accumulated too much noise (context-poisoning, false trails, dead-end attempts), `/handoff` writes a condensed summary into the active slice plan and instructs the user to start a fresh chat. The next `/craft:prime` reloads the slice plan, and a fresh agent picks up where the worn-out one left off.

This is not bug-specific; use it whenever a fresh perspective would help.

---

## Pre-flight

- `Glob` `.claude/plans/*.md`. Pick the active slice. If multiple, ask which slice to hand off.
- If none → tell user: *"No active slice to hand off. If you want to capture session-only state, write it to a notes file manually."* and stop.

---

## Procedure (Autonomy Level 1)

### 1. Compose the handoff summary

Build a tight summary covering:

1. **Where we are** — current phase, sub-task in flight, latest passing test state.
2. **What was tried** — short list of attempts and outcomes (bullets, one line each).
3. **What was ruled out** — hypotheses or approaches we now know don't work.
4. **What's the next thing to try** — the agent's current best guess for direction, or "uncertain — fresh look needed."
5. **Verification protocol(s) in play** — if `/craft:debug` was used, the frozen verification command + expected output.
6. **Outstanding open questions** — anything the agent should ask the user when picking up.

Keep the whole summary under 50 lines. Goal: enough context to resume without re-deriving, but not so much that the fresh session inherits the poison.

### 2. Append to slice plan

Add or overwrite the `## Handoff` section in the slice plan:

```markdown
## Handoff

> Written: <ISO date> | Session: previous

### Where we are
<…>

### Tried
- <…>
- <…>

### Ruled out
- <…>

### Best guess for next step
<…>

### Verification protocol(s)
<…>

### Outstanding questions for user
- <…>
```

### 3. Instruct the user

Emit:

```
✓ Handoff written to .claude/plans/slice-<NNN>-<slug>.md (## Handoff section)

Action required from you:
  1. End this chat session (close the window or run /clear).
  2. Open a fresh chat in the same project directory.
  3. The SessionStart hook will auto-run /craft:prime, which will surface the handoff.

The fresh agent will read the handoff and continue from "Best guess for next step."
```

### 4. Set status

Update `Status:` to whatever it was, plus add a note in the slice plan's frontmatter or top region: `Handoff active: yes`. The next `/craft:prime` uses this flag to surface the handoff prominently.

---

## Output Format

```
✓ Handoff captured.

Slice: slice-<NNN> "<title>"
Where: Phase <X>, sub-task <Y>/<Z>
Length: <N> lines

Next: start a fresh chat session; /craft:prime will pick up.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice plan does not exist | Stop with the message in Pre-flight. |
| User wants to hand off without summarizing | Push back gently: *"A handoff without a summary is just a context reset. Either write a summary, or use /clear directly."* |
| `## Handoff` section already exists from a prior handoff | Offer: *"There is already a Handoff section from a prior session. Overwrite, append, or cancel?"* |

---

## What This Command Does NOT Do

- It does **not** clear the chat. The user does that explicitly (close window or `/clear`).
- It does **not** abort the slice. The slice stays open; only the conversation context resets.
- It does **not** delete prior `## Bug Fix Attempts` or similar log sections — those are part of the slice's audit trail and stay intact.
