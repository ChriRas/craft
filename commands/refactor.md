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

- `Glob` `.claude/plans/*.md`. Expect a slice in `Status: refactoring` (or `review` if jumping here directly after Phase 6).
- If none → stop with `No slice ready for refactor. Run /craft:recap first.`
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

## What This Command Does NOT Do

- It does **not** add new functionality. Refactor preserves behavior.
- It does **not** commit. Phase 9 / `/craft:commit` does.
- It does **not** review. Phase 8 / `/craft:review` does.
- It does **not** promote decisions to `intent.md` / `rules.md`. That's Phase 9.
