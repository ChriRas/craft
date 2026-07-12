---
description: Phase 6 — explain what was built and why. Captures the slice's What / Why / Decisions; offers a Mermaid diagram for complex slices. Draft becomes the slice archive entry in Phase 9.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /craft:recap — Phase 6 Recap

## Purpose

Force the user to retain mental ownership of the artifact. Without this phase, after 5–6 slices the user has silently handed product decisions to the agent. The recap is for the human, not for the machine.

Follow `skills/workflow/SKILL.md` Phase 6 mechanics.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the four required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

<!-- craft:reads status=review -->
- `Glob` `.claude/plans/*.md`. Find the slice in `Status: review` (or `testing` if Phase 5 just passed).
- If no such slice → tell user `No slice ready for recap. Run /craft:test first.` and stop.

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

Using `templates/slice-archive.md.template`, draft the entry in working memory (not yet written to disk — Phase 9 / `/craft:commit` will finalize and write it). Fill:

- Title from the slice plan
- Completed date (today, ISO)
- Commits: placeholder, will be filled in `/craft:commit` after the actual commits exist
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

Where Phase 6 hands off depends on whether the project keeps Phase 7. Read the
`## Workflow Rules` section of `.claude/project/rules.md` and apply the **Phase-7-dropped
rule** defined in `skills/workflow/SKILL.md` (Phase Transition Rules): the project drops
Phase 7 when a `## Workflow Rules` bullet declares Phase 7 (Refactor) dropped or skipped.

<!-- craft:writes status=refactoring when=phase7-kept -->
- **Phase 7 kept (default)** — ask: *"Recap captured. Ready for Phase 7 (refactor)?"* If yes,
  update `Status: refactoring` in the slice plan and emit
  `Recommended next: /craft:refactor`.

<!-- craft:writes status=reviewing when=phase7-dropped -->
- **Phase 7 dropped** — there is no refactor seat to hand to, so Phase 6 hands **directly to
  Phase 8**. Ask: *"Recap captured. Ready for Phase 8 (review)?"* If yes, update
  `Status: reviewing` in the slice plan and emit `Recommended next: /craft:review`.
  Do not hand this slice to `/craft:refactor`: that command never runs in this project, so the
  hand-off would dangle — the slice either sits in a phase that does not exist, or stays at
  `review`, which `/craft:review` reads as pre-Phase-8 and answers with advisory mode (findings
  only, Commit never gated). That is the slice-030 failure.

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
Recommended next: /craft:refactor      (Phase 7 kept  → Status: refactoring)
Recommended next: /craft:review        (Phase 7 dropped → Status: reviewing)
```

Emit whichever of the two `Recommended next:` lines applies — never both.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice not in `review` or `testing` status | Stop, recommend the appropriate prior phase command. |
| Slice plan has no `## Decisions Made During This Slice` section | Add an empty placeholder; the recap is still valuable. |
| User stops the recap mid-way, saying "we built the wrong thing" | Treat this as a serious signal. Recommend `/craft:handoff` to summarize and re-think in a fresh session, or `/craft:abort` if the slice should be discarded. |
| User asks for a diagram on a trivial slice | Produce one anyway — the user is asking. Just keep it minimal. |

---

## Subagent Mode (when called by `/craft:execute`)

When invoked by the `slice-builder` subagent during an autonomous run, there is no human to narrate to. The subagent drafts the What / Why / Walk-through from the slice plan plus the diff:

- **What** — derived from `## Goal` and `## Effect` in the slice plan.
- **Why** — derived from `## Trigger` and any entries in `## Decisions Made During This Slice`.
- **Walk-through** — derived from the ordered `- [x]` sub-tasks and the actual code diff.

The draft is written to `## Recap Draft` and clearly flagged at the top with `> Drafted by subagent — review at /craft:checkout`. The human reviews and edits the draft when they check out the worktree.

No diagram is auto-generated in subagent mode (low signal/effort ratio without dialog).

---

## What This Command Does NOT Do

- It does **not** write the slice archive file. That happens in Phase 9 / `/craft:commit`.
- It does **not** modify code. Refactoring is Phase 7.
- It does **not** promote decisions to `intent.md` or `rules.md`. That dialog is in Phase 9.
- It does **not** delete the slice plan. The plan stays alive until Phase 9 cleanup.
