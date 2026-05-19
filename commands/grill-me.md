---
description: Phase 2 entry point (or anytime). Wraps the grill-me skill — interview-style stress-testing of a plan or design until shared understanding is reached. One question at a time.
argument-hint: "[plan-or-subject]"
allowed-tools: ["Read", "Write", "Glob"]
---

# /grill-me — Phase 2 Alignment Interview

## Purpose

Open Phase 2 of the workflow: surface and resolve hidden assumptions before any code is written. The agent interviews the user relentlessly, walking down each branch of the decision tree, providing its recommended answer for each question.

Also usable anytime outside Phase 2 — e.g., to stress-test a slice plan in Phase 3, or to pressure-test an architectural decision mid-implementation.

This command activates `skills/grill-me/SKILL.md`.

---

## Pre-flight

If the subject of the grilling is the active slice plan, the agent should read it first:

- `Glob` `.claude/plans/*.md`. If exactly one active and the user's argument matches its scope, `Read` it before starting the interview.
- Otherwise, the subject is whatever the user provides in `<plan-or-subject>` or describes in the first exchange.

---

## Procedure

### 1. Activate the skill

Load `skills/grill-me/SKILL.md`. The skill's prompt is concise:

> Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.
>
> Ask the questions one at a time.
>
> If a question can be answered by exploring the codebase, explore the codebase instead.

Follow it literally. One question per response. For each question, propose a recommended answer (so the user can accept, override, or refine — never a Socratic-only ask).

### 2. Codebase exploration over user-asking

Where the answer can be derived from the code (e.g., "what testing framework do you use?" — look in `composer.json` / `package.json`), explore the codebase via `Read` / `Glob` / `Grep` instead of asking. This respects the user's time.

### 3. Capture decisions

As the interview progresses, maintain an internal log of decisions reached. When the interview converges (user signals "enough" or the decision tree is fully resolved):

- If aligning on a slice plan: append the resolutions to the slice plan under `## Alignment` (or merge into existing sections like `## Goal`, `## Vertical Slice Definition` if they were vague).
- If aligning on a project decision: append to `.claude/grill-me-<subject-slug>-<date>.md` at repo root, or recommend promotion to `.claude/project/intent.md` via `/intent-update`.

### 4. Recommend next step

```
✓ Alignment captured.
Recommended next: <appropriate step>
```

Typical "appropriate step":

- Phase 2 of a new feature → `/plan`
- Mid-slice grill → `/execute` or `/continue`
- Project-level decision → `/intent-update` if a decision should be promoted

---

## Output Format

The interview itself is a back-and-forth — one question per agent turn, one answer per user turn. Final block:

```
✓ Grill complete.

Decisions reached:
  - <one-line>
  - <one-line>
  - <one-line>

Captured to: <file or slice section>
Recommended next: <command>
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| User says "you decide" repeatedly | Surface the pattern: *"I'm providing recommendations for every question, but I need your input on at least the strategic ones (X, Y, Z). Without that, alignment is hollow."* |
| Codebase exploration returns ambiguous results | Surface the ambiguity to the user and ask. Don't pick silently. |
| Interview drags into ground already covered | Recognize convergence; offer to close the session. |

---

## What This Command Does NOT Do

- It does **not** ask multiple questions per response. One at a time, always.
- It does **not** decide on the user's behalf. It recommends; the user picks.
- It does **not** modify `intent.md` or `rules.md`. Promotions happen via `/intent-update` or Phase 8's promotion dialog.
