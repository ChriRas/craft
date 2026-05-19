---
description: Phase 4 — implement the active slice. Loads project-local specialist skills lazily, works sub-tasks in order, runs tests silently, bundles at sub-task boundaries.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /execute — Implement the Active Slice

## Purpose

Phase 4 of the workflow: turn the slice plan into working code. Stay inside the plan's scope; lazy-load project specialists when needed; surface progress in bundled status messages.

Follow `skills/workflow/SKILL.md` Phase 4 mechanics and the autonomy matrix. Code edits inside plan scope run at Level 2; outside scope at Level 1.

---

## Pre-flight

### 1. Locate active slice

- `Glob` `.claude/plans/*.md`.
- If multiple slices → run `/continue` to select one first, then this command.
- If none → tell user `No active slices. Run /plan first.` and stop.

### 2. Load slice plan

`Read` the slice plan file. Hold in context:

- `Slice-ID`, `Started`, `Phase`, `Status`, `plugin-version`
- Goal / Vertical Slice Definition / Trigger / Effect / Test Strategy
- Sub-tasks (which are done, which next)
- Active Rule Overrides (apply them during this session)
- Bugs, Verification Protocols (relevant if `/debug` was used here)

### 3. Update Status

If `Status` is `planning`, update it to `implementing` and write back.

If `Status` is already `implementing` or `paused`, resume without status change.

### 4. Detect stack and lazy-load specialists

- `Read` `.claude/project/rules.md` for the `## Stack & Tools` section.
- Identify which **project-local skills** apply to the slice's work. Common patterns:
  - PHP/Laravel → load `.claude/skills/developer/SKILL.md` if present
  - JavaScript/TypeScript → load any TS-specific skill if present
  - Python → load any Python-specific skill if present
- Lazy load means: read those skill files into context only when about to touch files in that stack.
- If no project-local skill matches, use general-purpose engineering judgment within the constraints of `rules.md`.

---

## Procedure (Autonomy Level 2 inside plan scope)

### 1. Identify next sub-task

- Find the first unchecked sub-task (`- [ ]`) in the slice plan.
- If all are checked → emit `All sub-tasks complete. Run /test to start Phase 5.` and stop.

### 2. Plan the sub-task work

Briefly state the approach for the current sub-task. No long planning — this is implementation, not Phase 3.

### 3. Implement

- Make the smallest edits that satisfy the sub-task.
- Code edits inside slice scope: Level 2 (act, then bundle).
- Code edits outside slice scope (e.g., shared utility, unrelated file): drop to Level 1 — ask explicitly before editing.
- Run tests after meaningful changes. Test runs are Level 3 silent unless red.

### 4. Self-verification trigger awareness

- Track fix attempts. If you make a **2nd fix attempt on the same symptom** within this slice, **pause and offer `/debug`**:

  *"I notice I'm cycling on this. Should we enter `/debug` mode and agree on a verification protocol before more attempts?"*

  Do not force the user into `/debug` — ask, wait, respect the answer.

### 5. Check off the sub-task

When verifiably complete (sub-task assertion met, no regression in tests): flip `- [ ]` to `- [x]` in the slice plan via `Edit`.

### 6. Bundle status

At the end of each sub-task, emit a compact bundle:

```
✓ Sub-Task <N>/<Total>: <name>
   Changed: <file list, comma-separated>
   Test: <status — "green" / "<N> passed" / "skipped">
   Level-3 silent ops: <one-line summary, e.g. "read 4 files, ran lint">
   Next: Sub-Task <N+1>/<Total> — <name>
   [continuing in 3s — type 'pause' to stop]
```

If user types anything during the countdown, pause. If silence, continue to the next sub-task.

### 7. Token brake

If the cumulative output since the last bundle exceeds **30,000 tokens** (Dumb-Zone protection), force a bundle even mid-sub-task. Format the bundle the same way but mark it `(token brake)`.

### 8. Phase-end bundle

When all sub-tasks are checked, emit a final bundle:

```
✓ All sub-tasks complete (Phase 4 ✓)
  Total commits-not-yet-made: <N> proposed
  Tests: <status>

Recommended next: /test to start Phase 5 (you exercise the artifact).
```

Update `Status: testing` in the slice plan.

---

## Bundling Rules (recap from `skills/workflow/SKILL.md`)

- Bundle at sub-task boundary OR 30k-token brake.
- Auto-continue with abort option at Level 2 — otherwise the model collapses to Level 1.
- Level 3 actions (reads, lint checks, status polls) summarized in one bundle line, never invisible.
- User can pre-empt with `pause after current sub-task`.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice plan missing required sections (Sub-Tasks, Test Strategy) | Refuse to start; recommend `/plan` to repair. |
| Test fails red after a sub-task | Do not check off the sub-task. Try one fix attempt. If still red, offer `/debug`. |
| User pauses during bundle countdown | Stop cleanly; do not start the next sub-task. Status remains `implementing`. |
| Slice file becomes unreadable mid-execute | Stop, surface error, do not silently overwrite. |
| Encounter a needed change outside plan scope | Drop to Level 1: ask explicitly. Either get approval, or stop and recommend re-planning. |

---

## What This Command Does NOT Do

- It does **not** plan. If sub-tasks are missing, run `/plan` first.
- It does **not** run user-facing tests (Phase 5). Automated tests in Phase 4 run silently as part of implementation.
- It does **not** commit. Phase 8 / `/commit` does that.
- It does **not** refactor speculatively. Phase 7 / `/refactor` is the refactor seat.
- It does **not** edit `intent.md` or `rules.md`. Decisions surfaced during implementation go into the slice plan's `## Decisions Made During This Slice` section for Phase 8 promotion.
