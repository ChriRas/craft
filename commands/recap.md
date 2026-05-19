---
description: Phase 6 — explain what was built and why. Captures the slice's What / Why / Decisions; offers a Mermaid diagram for complex slices. Draft becomes the slice archive entry in Phase 8.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /recap — Phase 6 Recap

## Purpose

Force the user to retain mental ownership of the artifact. Without this phase, after 5–6 slices the user has silently handed product decisions to the agent. The recap is for the human, not for the machine.

Follow `skills/workflow/SKILL.md` Phase 6 mechanics.

---

## Pre-flight

- `Glob` `.claude/plans/*.md`. Find the slice in `Status: review` (or `testing` if Phase 5 just passed).
- If no such slice → tell user `No slice ready for recap. Run /test first.` and stop.

---

## Procedure (Autonomy Level 1)

### 1. Agent answers, dialogically

Tell the user:

> I'll walk through what we built and why, in plain language. Stop me if something feels off — that's a sign the slice isn't actually done.

Then the agent narrates, **without code**, in 3 short paragraphs:

1. **What** — In one or two sentences: what does this slice now enable that wasn't possible before?
2. **Why** — What product / architectural decisions drove the implementation?
3. **Walk-through** — How does the flow work from the trigger to the observable effect?

After each paragraph, pause and let the user confirm or correct.

### 2. Complexity check — offer a diagram

Count touched files and modules. If more than **3 modules / files** were touched in this slice, or if multiple architectural layers interact (e.g., frontend + API + DB + worker), offer:

> This slice touched <N> components — a diagram would help. Shall I add a Mermaid diagram to the recap?

If yes, produce a small Mermaid block — typically `sequenceDiagram` for request flows or `flowchart LR` for data flows. Keep it under 15 nodes.

If no, skip.

### 3. Draft the slice archive entry

Using `templates/slice-archive.md.template`, draft the entry in working memory (not yet written to disk — Phase 8 / `/commit` will finalize and write it). Fill:

- Title from the slice plan
- Completed date (today, ISO)
- Commits: placeholder, will be filled in `/commit` after the actual commits exist
- What (paragraph from step 1)
- Why (paragraph from step 2)
- Decisions: pull from the slice plan's `## Decisions Made During This Slice` section
- Diagram (only if produced in step 2)

Store the draft in the slice plan under a new section `## Recap Draft`:

```markdown
## Recap Draft

### What
<paragraph>

### Why
<paragraph>

### Walk-through
<paragraph>

### Diagram
<mermaid block, if produced>
```

### 4. Confirm and advance

Ask: *"Recap captured. Ready for Phase 7 (refactor)?"*

If yes, update `Status: refactoring` in the slice plan and emit `Recommended next: /refactor`.

If user wants to revise the recap, edit the `## Recap Draft` section in the slice plan based on their corrections.

---

## Output Format

```
Phase 6 — Recap

What:
  <paragraph>

Why:
  <paragraph>

Walk-through:
  <paragraph>

[Diagram block if produced]

Recap draft written to slice plan.
Recommended next: /refactor
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice not in `review` or `testing` status | Stop, recommend the appropriate prior phase command. |
| Slice plan has no `## Decisions Made During This Slice` section | Add an empty placeholder; the recap is still valuable. |
| User stops the recap mid-way, saying "we built the wrong thing" | Treat this as a serious signal. Recommend `/handoff` to summarize and re-think in a fresh session, or `/abort` if the slice should be discarded. |
| User asks for a diagram on a trivial slice | Produce one anyway — the user is asking. Just keep it minimal. |

---

## What This Command Does NOT Do

- It does **not** write the slice archive file. That happens in Phase 8 / `/commit`.
- It does **not** modify code. Refactoring is Phase 7.
- It does **not** promote decisions to `intent.md` or `rules.md`. That dialog is in Phase 8.
- It does **not** delete the slice plan. The plan stays alive until Phase 8 cleanup.
