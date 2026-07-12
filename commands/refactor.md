---
description: Phase 7 — small structural improvements before Review (Phase 8). Asks the three Thorstensen prompts dialogically. Max 2–3 refactor items per slice; larger refactor = its own slice.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:refactor — Phase 7 Refactoring

## Purpose

Apply small, immediate structural improvements before commit. Deferring refactor means the next slice builds on a worse foundation; that is the discipline this phase enforces.

Follow `skills/workflow/SKILL.md` Phase 7 mechanics. **Max 2–3 refactor items per slice.** A larger refactor is its own slice.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the four required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

**Phase-7-dropped gate — runs FIRST, before any status write.** Read the `## Workflow Rules`
section of `.claude/project/rules.md` and apply the **Phase-7-dropped rule** defined in
`skills/workflow/SKILL.md` (Phase Transition Rules). If the project drops Phase 7, this command
has no seat — but it still may not move a slice that has not reached the hand-off.

`Glob` `.claude/plans/*.md` and check the active slice's `Status:`:

- **`review` / `reviewing` / `refactoring`** — the slice is at (or past) the Phase-6 hand-off, so
  the skip applies. Append `Phase 7 skipped (project rule)` to its `## Decisions Made During This
  Slice`, and

  <!-- craft:writes status=reviewing when=phase7-dropped -->
  set `Status: reviewing`, then stop with

  ```
  Phase 7 is dropped by this project's rules.md — skipping. Status: reviewing.
  Recommended next: /craft:review
  ```

- **any other status** (`planning`, `implementing`, `testing`, `committing`, `awaiting-*`), a
  `blocked` / `paused` slice, or no active slice at all → **do not touch the status.** Stop with
  `No slice ready for refactor. Run /craft:recap first.` The allow-list above is closed: anything
  not on it lands here. A slice at `implementing` or `testing` has not passed the Phase-5 human
  demo, and Phase 5 cannot be skipped (`skills/workflow/SKILL.md` → *Phase 5 cannot be skipped*).
  Yanking it to `reviewing` would jump that gate.

The gate is checked before the lookup below on purpose: once `/craft:recap` hands a Phase-7-dropped
slice straight to Phase 8, that slice sits at `reviewing`, which the Phase-7-kept lookup does not
expect — so a human running `/craft:refactor` out of habit would otherwise be told "No slice ready
for refactor" and never reach this skip.

**This gate is the single definition of the Phase-7-dropped behavior for this command.** Subagent
Mode does not restate it — it delegates here (see below). The interactive and autonomous paths
therefore cannot drift apart, which is exactly how B1 came about.

Otherwise (Phase 7 kept):

<!-- craft:reads status=refactoring -->
- `Glob` `.claude/plans/*.md`. Expect a slice in `Status: refactoring`, or `review` if jumping here directly after Phase 6. **Not `reviewing`** — in a Phase-7-keeping project that can only mean Phase 8 has already started, and pulling such a slice back to `refactoring` would yank it out of a running review.
- If none → stop with `No slice ready for refactor. Run /craft:recap first.`

<!-- craft:writes status=refactoring when=phase7-kept -->
- Update `Status: refactoring` if not already.

Then load the declared stack-pack — `Read` the `## Personality` section of
`.claude/project/rules.md`:

- If it declares a `Stack-Pack:` other than `none`, resolve the pack —
  `skills/<name>/SKILL.md` (plugin-shipped) or
  `~/.claude/craft-personalities/<name>/SKILL.md` (user-added). If found, `Read` it
  (and its `references/` files as the work needs) and emit `✓ Stack-pack loaded: <name>`.
- If a pack is declared but the file cannot be found, emit
  `⚠ Stack-pack <name> declared but not found — continuing with Senior-Developer baseline only`
  and continue.
- If no pack is declared (`none`, or no `## Personality` section), proceed on the
  Senior-Developer baseline alone — no stack-pack line.

---

## Procedure (Autonomy Level 1)

### 1. Surface candidates with the three Thorstensen prompts

Ask the user, one at a time:

1. **"What would be the smallest step that makes this codebase better right now?"**
2. **"Could a new developer follow the flow from trigger to effect without mental leaps?"**
3. **"Which refactor would preserve behavior but improve structure?"**

For each, capture the user's answer. If the user has no answer to a prompt, the agent may suggest one based on the recent slice's code — but the user picks what gets done.

### 2. Filter to 2–3 items

If the candidate list exceeds 3:

> We have <N> candidates. Phase 7 allows 2–3 to keep the slice focused. Pick the top items, the rest become a future refactor slice.

Capture the user's pick.

### 3. Implement each item

For each chosen item, in order:

- State the change in one sentence.
- Apply the edit.
- **Run the tests.** Refactoring must preserve behavior — green tests are the proof.
- If tests fail: this is part of the refactor's cost. Fix tests in the same slice (or revert the refactor).

Bundle per item:

```
✓ Refactor 1/N: <name>
   Changed: <files>
   Tests: <status>
   [continuing in 3s — type 'pause' to stop]
```

### 4. Handle larger discoveries

If during refactor the user (or agent) realizes a much bigger structural improvement is warranted: **do not expand the current slice's refactor scope**. Instead:

> Larger refactor surfaced: <description>. Captured for a future slice. Continuing with the current 2–3 items.

Append to the slice plan's `## Decisions Made During This Slice` (so Phase 9 can promote it to roadmap or surface it next planning).

### 5. Advance to Phase 8 (Review)

<!-- craft:writes status=reviewing when=phase7-kept -->
After the chosen items are done and tests are green, update `Status: reviewing` and emit:

```
✓ Phase 7 complete (<N> refactor items).
Recommended next: /craft:review
```

---

## Output Format

```
Phase 7 — Refactoring

Candidates surfaced: <N>
Applied: <N>

[per-item bundles]

✓ All green
Recommended next: /craft:review
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Tests turn red after a refactor item | Revert the item OR fix the test in this slice. Do not commit red. |
| User wants to do more than 3 items | Push back once: *"More than 3 makes the slice unfocused. Capture extras for a future slice?"* If user insists, allow but warn that the slice has expanded beyond its plan. |
| User wants to skip Phase 7 entirely | Allow, but record `Phase 7 skipped` in the slice plan's `## Decisions Made During This Slice` so the omission is auditable. |
| Refactor touches files outside the slice's code scope | Drop to Level 1: ask explicitly. Outside-scope refactor is usually a sign of a separate refactor slice. |

---

## Subagent Mode (when called by `/craft:execute`)

When invoked by the `slice-builder` subagent during an autonomous run:

<!-- craft:delegates rule=phase7-dropped to=preflight -->
- If the project's `rules.md` declares Phase 7 dropped (e.g., this very repo), apply the
  **Phase-7-dropped gate defined in Pre-flight above** — the same gate, the same status
  precondition, the same status write. No separate rule is restated here on purpose: two
  descriptions of one contract, with only one of them maintained, is exactly the defect this slice
  exists to fix (it is how B1 survived — the subagent path handled the drop while the interactive
  path did not). One route, one marker, one row.
- Otherwise, the subagent surveys the slice's code change for the three Thorstensen prompts on its own (no user dialog), proposes up to 2 candidates, and **does not apply them**. It writes the candidate list to `.craft/handoff.md` with `Status: awaiting-refactor-decision` and pauses the slice. The human picks at `/craft:checkout` time, then runs `/craft:refactor` interactively (or skips with a Decision-log note).

Refactor must never be silently applied without human judgment — it changes structure, and unsupervised structural change is a known failure mode of agent-driven development.

---

## What This Command Does NOT Do

- It does **not** add new functionality. Refactor preserves behavior.
- It does **not** commit. Phase 9 / `/craft:commit` does.
- It does **not** review. Phase 8 / `/craft:review` does.
- It does **not** promote decisions to `intent.md` / `rules.md`. That's Phase 9.
