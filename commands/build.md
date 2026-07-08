---
description: Phase 4 — implement the active slice. Loads project-local specialist skills lazily, works sub-tasks in order, runs tests silently, bundles at sub-task boundaries.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:build — Implement the Active Slice

## Purpose

Phase 4 of the workflow: turn the slice plan into working code. Stay inside the plan's scope; lazy-load project specialists when needed; surface progress in bundled status messages.

Follow `skills/workflow/SKILL.md` Phase 4 mechanics and the autonomy matrix. Code edits inside plan scope run at Level 2; outside scope at Level 1.

---

## Pre-flight

### 1. Locate active slice

- `Glob` `.claude/plans/*.md`.
- If multiple slices → run `/craft:continue` to select one first, then this command.
- If none → tell user `No active slices. Run /craft:plan first.` and stop.

### 2. Load slice plan

`Read` the slice plan file. Hold in context:

- `Slice-ID`, `Started`, `Phase`, `Status`, `plugin-version`
- Goal / Vertical Slice Definition / Trigger / Effect / Test Strategy
- Sub-tasks (which are done, which next)
- Active Rule Overrides (apply them during this session)
- Bugs, Verification Protocols (relevant if `/craft:debug` was used here)

### 3. Update Status

If `Status` is `planning`, update it to `implementing` and write back.

If `Status` is already `implementing` or `paused`, resume without status change.

### 4. Load the stack-pack and detect specialists

First, load the project's declared stack-pack:

- `Read` the `## Personality` section of `.claude/project/rules.md`.
- If it declares a `Stack-Pack:` other than `none`, resolve the pack —
  `skills/<name>/SKILL.md` (plugin-shipped) or
  `~/.claude/craft-personalities/<name>/SKILL.md` (user-added). If found, `Read` it
  (and its `references/` files as the work needs) and emit `✓ Stack-pack loaded: <name>`.
- If a pack is declared but the file cannot be found, emit
  `⚠ Stack-pack <name> declared but not found — continuing with Senior-Developer baseline only`
  and continue.
- If no pack is declared (`none`, or no `## Personality` section), proceed on the
  Senior-Developer baseline alone — no stack-pack line.

Then identify any **project-local skills** that apply to the slice's work:

- Common patterns: PHP/Laravel, JavaScript/TypeScript, or Python project-local skills
  under `.claude/skills/` — `Read` them only when about to touch files in that stack.
- If no project-local skill matches, use general-purpose engineering judgment within
  the constraints of `rules.md`.

---

## Procedure (Autonomy Level 2 inside plan scope)

### 1. Identify next sub-task

- Find the first unchecked sub-task (`- [ ]`) in the slice plan.
- If all are checked → emit `All sub-tasks complete. Run /craft:test to start Phase 5.` and stop.

### 2. Plan the sub-task work

Briefly state the approach for the current sub-task. No long planning — this is implementation, not Phase 3.

### 3. Implement

- Make the smallest edits that satisfy the sub-task.
- Code edits inside slice scope: Level 2 (act, then bundle).
- Code edits outside slice scope (e.g., shared utility, unrelated file): drop to Level 1 — ask explicitly before editing.
- Run tests after meaningful changes. Test runs are Level 3 silent unless red.
- **Code comments** — write any code comments in the project's comment language: the `Comments` key of the `## Operational Language` block in `.claude/project/craft-profile.md` (default English when the profile, the block, or the key is absent). Applies only to comment prose, never to identifiers, keywords, or string literals required by the code.

### 4. Self-verification trigger awareness

- Track fix attempts. If you make a **2nd fix attempt on the same symptom** within this slice, **pause and offer `/craft:debug`**:

  *"I notice I'm cycling on this. Should we enter `/craft:debug` mode and agree on a verification protocol before more attempts?"*

  Do not force the user into `/craft:debug` — ask, wait, respect the answer.

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

Recommended next: /craft:test to start Phase 5 (you exercise the artifact).
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
| Slice plan missing required sections (Sub-Tasks, Test Strategy) | Refuse to start; recommend `/craft:plan` to repair. |
| Test fails red after a sub-task | Do not check off the sub-task. Try one fix attempt. If still red, offer `/craft:debug`. |
| User pauses during bundle countdown | Stop cleanly; do not start the next sub-task. Status remains `implementing`. |
| Slice file becomes unreadable mid-execute | Stop, surface error, do not silently overwrite. |
| Encounter a needed change outside plan scope | Drop to Level 1: ask explicitly. Either get approval, or stop and recommend re-planning. |

---

## Subagent Mode (when called by `/craft:execute`)

When the `slice-builder` subagent invokes `/craft:build` during an autonomous run, the main procedure runs unchanged — the build loop is mechanical and safe to automate. Four behavioral overrides apply:

- **Self-verification trigger** (Procedure step 4) — instead of asking the human "Should we enter `/craft:debug` mode?" on a 2nd same-symptom fix attempt, write `.craft/handoff.md` in the worktree with `Status: awaiting-protocol`, set the slice plan `Status: paused` plus a Pause Note describing the recurring symptom, and stop. The subagent does not negotiate a verification protocol with no human present.
- **Outside-scope edits** (Procedure step 3 / Error Handling row 5) — instead of asking the human for approval at Level 1, write a handoff with `Status: awaiting-scope-decision` and stop. The plan boundary is a contract; the subagent never expands scope unilaterally.
- **Out-of-scope blocker** (Problem-Playbook: an unforeseen dependency that exceeds minimal in-slice work) — when a *whole prerequisite* is missing (infra/API/service), or a `decision` / `access` / `external` wait stands in the way per the spawn-boundary heuristic, this is a blocker, not a scope-spill: follow the slice-builder's **Blocker detection & escalation** — classify, write the first-class `blocked` state, write `.craft/handoff.md` with `Status: awaiting-block-decision`, and stop. (The distinction from *Outside-scope edits*: that is permission to touch an unnamed file; this is a missing unit of work or a direction call the subagent must never make.)
- **Bundle countdowns** — the "[continuing in 3s — type 'pause' to stop]" line is omitted in subagent output. There is no human to type during the countdown.

On clean Phase-4 completion (all sub-tasks checked, tests green), Subagent Mode advances the slice plan `Status: testing` exactly as the main flow does — the slice-builder picks up at Phase 5 next.

---

## What This Command Does NOT Do

- It does **not** plan. If sub-tasks are missing, run `/craft:plan` first.
- It does **not** run user-facing tests (Phase 5). Automated tests in Phase 4 run silently as part of implementation.
- It does **not** commit. Phase 9 / `/craft:commit` does that.
- It does **not** refactor speculatively. Phase 7 / `/craft:refactor` is the refactor seat.
- It does **not** edit `intent.md` or `rules.md`. Decisions surfaced during implementation go into the slice plan's `## Decisions Made During This Slice` section for Phase 9 promotion.
