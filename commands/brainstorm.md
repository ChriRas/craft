---
description: Phase 1 entry point. Wraps the brainstorm skill — structured, collaborative ideation using proven techniques (SCAMPER, Five Whys, First Principles, etc.). Output is a Markdown checkpoint that survives context reset.
argument-hint: "[topic]"
allowed-tools: ["Read", "Write"]
---

# /brainstorm — Phase 1 Brainstorm

## Purpose

Open Phase 1 of the workflow: use the agent as a creative facilitator to explore the problem space before any code is written. The agent does not generate ideas alone — it facilitates the user's exploration using structured techniques.

This command activates `skills/brainstorm/SKILL.md` and follows its methodology precisely (one question at a time, divergent before convergent, anti-bias domain pivots).

---

## Pre-flight

None strict. `/brainstorm` works in any project state, even pre-onboarding.

---

## Procedure

### 1. Activate the skill

Load and follow `skills/brainstorm/SKILL.md`. The skill defines the full session arc:

- Setup (4 questions, one at a time)
- Approach choice (4 modes — user-selected / recommended / random / progressive flow)
- Divergent ideation (with anti-bias domain pivots)
- One technique at a time
- Organize only after exploration
- Prioritize and action plan

### 2. Capture output as a Markdown checkpoint

When the session converges (user signals "organize" or "wrap up"), produce a Markdown summary using the skill's specified output format:

```markdown
## Brainstorming Session

**Topic:** …
**Goal:** …
**Constraints:** …
**Approach:** …

## Ideas
[as captured]

## Organized Themes
[after convergence]

## Top Priorities
[after prioritization]

## Action Plan
[if reached]
```

### 3. Save the checkpoint

If the user is inside a project with `.claude/project/`:

- If a slice plan is active, append the brainstorm summary to it under `## Brainstorm`.
- Otherwise, write to `.claude/brainstorm-<topic-slug>-<date>.md` at repo root for safekeeping. This file is ephemeral — delete when no longer useful.

If no project, the summary stays in chat — user copies it where they want.

### 4. Recommend next step

Typical post-brainstorm move is Phase 2 (Alignment):

```
✓ Brainstorm captured.
Recommended next: /grill-me to align on direction, or /plan if the path is already clear.
```

---

## Output Format

The full output follows the brainstorm skill's specification. This command does not impose additional structure.

---

## Error Handling

| Situation | Behavior |
|---|---|
| User wants the agent to "just give me ideas" without dialog | Push back once: *"The skill works by facilitating your thinking, not replacing it. One question at a time is the methodology — let's start."* If user insists, fall back to producing a quick list but flag that the methodology was bypassed. |
| User runs `/brainstorm` mid-slice | Allow, but warn: *"Brainstorming mid-slice can derail focus. If this is about the current slice, consider /grill-me instead. If it's a separate topic, fine — proceed."* |

---

## What This Command Does NOT Do

- It does **not** generate ideas autonomously. The user supplies the raw material; the skill structures.
- It does **not** make product decisions. Output is a checkpoint, not a commitment.
- It does **not** modify code, commits, or project knowledge files.
