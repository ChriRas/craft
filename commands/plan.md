---
description: Phase 3 — plan a new vertical slice. Dialogically forces the three universal questions (trigger / observable effect / test strategy) and writes a slice plan file.
argument-hint: "<feature-or-slice-name>"
allowed-tools: ["Bash", "Read", "Write", "Glob"]
---

# /plan — Plan a New Vertical Slice

## Purpose

Open Phase 3 of the workflow: break the next chunk of work into a vertical slice that is end-to-end testable, minimal, self-contained, and standalone-experienceable.

Follow `skills/workflow/SKILL.md` Phase 3 mechanics. The three universal questions are non-negotiable — every slice must answer them before any code is written.

---

## Pre-flight

### 1. Require onboarding

- `Read` `.claude/project/intent.md`. If missing → tell the user *"Project not onboarded. Run `/onboard` first."* and stop.
- `Read` `.claude/project/rules.md`. Hold both in context.

### 2. Allocate slice ID

- `Read` `.claude/plans/.next-id`. If missing, treat the next ID as `001` and create the file.
- The slice ID is the value in that file, zero-padded to 3 digits (e.g., `007`).
- After writing the plan file, increment the counter and write back.

### 3. Determine plugin version (for slice frontmatter)

- `Read` `.claude-plugin/plugin.json` from the installed plugin directory (via `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`). Extract the `version` field. Store as `plugin-version` for the slice frontmatter.

---

## Procedure (Autonomy Level 1)

The command argument is the feature or slice name. If absent, ask: *"Which slice should we plan? Short name in 3–6 words."*

Derive `<slug>` from the name: lowercase, hyphenated, no whitespace.

### 1. Trigger question

Ask, dialogically:

> What is the external trigger for this slice? Pick one or describe yours:
> - User interaction (click, gesture, voice)
> - CLI invocation (command + args)
> - API call (HTTP / RPC / library function)
> - Event (queue message, webhook, cron)
> - File / data drop (input file appearing in a folder)
> - System state change (timer, threshold)

Capture the answer verbatim.

### 2. Observable-effect question

Ask:

> What is the observable effect when this slice succeeds? Pick or describe:
> - UI update (text, color, position, new element)
> - Stdout / log line
> - HTTP / function response
> - Persistent state change (DB row, file written)
> - Side effect (email sent, message published, deployment triggered)

Capture verbatim.

### 3. Test strategy question

Ask:

> How will we test this end-to-end? The test must exercise from the trigger to the observable effect.
> - Test runner / framework to use
> - What setup is needed before the test runs
> - What the assertion looks like (one line of pseudo-test)

Capture verbatim. The test strategy is **committed before any code is written**.

### 4. Sub-task decomposition

Ask the user, or propose draft sub-tasks based on the trigger / effect / test answers. Sub-tasks should be small enough to bundle individually (≤ a logical work block).

Each sub-task is a single bullet under `## Sub-Tasks`. Use `- [ ]` for unchecked.

### 5. Optional: rough UI / interaction sketch

For UI-bearing slices, ask: *"Do you have a sketch or wireframe? You can describe it in words or paste a path to an image."* Capture if provided.

### 6. Generate the plan file

Use `templates/slice-plan.md.template`. Substitute:

- Title from `<feature-or-slice-name>`
- `Slice-ID: slice-<NNN>`
- `Started: <ISO date>`
- `Phase: 3`
- `Status: planning`
- `plugin-version: <from plugin.json>`
- Trigger, effect, and test answers in their sections
- Sub-tasks
- UI sketch reference (if any)
- Empty placeholders for `## Active Rule Overrides`, `## Bugs`, `## Verification Protocols`, `## Bug Fix Attempts`, `## Decisions Made During This Slice`

Write to `.claude/plans/slice-<NNN>-<slug>.md`.

### 7. Increment slice counter

Write the next integer back to `.claude/plans/.next-id`.

### 8. Confirm and hand off

Tell the user:

```
✓ Slice slice-<NNN> "<title>" planned. Status: planning → ready for Phase 4.

Next: /execute to start implementation.
```

Update the slice plan's `Status:` to `implementing` only when `/execute` actually starts — not here.

---

## Output Format

After the plan file is written, emit:

```
✓ Plan: .claude/plans/slice-<NNN>-<slug>.md

  Trigger: <one line>
  Effect:  <one line>
  Test:    <one line>
  Sub-tasks: <N>

Next: /execute
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Not onboarded | Stop with `/onboard` recommendation. |
| User skips one of the three universal questions | Re-ask; do not write the plan with empty trigger / effect / test sections. |
| `.claude/plans/.next-id` is corrupt (non-integer) | Tell user, ask whether to reset to the next ID derived by scanning existing slice files; do not silently overwrite. |
| Slug collides with an existing slice file | Append `-2`, `-3`, etc., to the slug. |
| User wants to plan with no clear test strategy | Push back: *"Phase 3 requires a test strategy before Phase 4. If we cannot articulate one, the slice may be too vague — let's break it down further or revisit the goal."* |

---

## What This Command Does NOT Do

- It does **not** write any code.
- It does **not** start Phase 4.
- It does **not** commit anything.
- It does **not** modify `intent.md` or `rules.md`. Architectural insights surfaced during planning go into the plan's `## Decisions Made During This Slice` section and are promoted (or not) in Phase 8.
