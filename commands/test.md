---
description: Phase 5 — hands-on user verification. Prepares a demo (5a), the user exercises the artifact (5b), structured feedback is captured (5c). Bugs trigger /craft:debug; UX issues iterate.
allowed-tools: ["Bash", "Read", "Edit", "Glob"]
---

# /craft:test — User Verification of the Slice

## Purpose

Phase 5 of the workflow. The agent has no product-feel; this is the only phase where the human exercises the artifact. Even if Phase 4 automated tests are green, Phase 5 must run before Phase 6/7/8/9.

Follow `skills/workflow/SKILL.md` Phase 5 mechanics (the three sub-steps 5a / 5b / 5c).

---

## Pre-flight

### 1. Locate active slice

- `Glob` `.claude/craft:plans/*.md`. Expect exactly one in `Status: testing` or `implementing`. If multiple, ask the user which slice. If none, stop with `No slice ready for testing. Run /craft:execute first or /craft:plan to start a new slice.`

### 2. Load slice plan

Read the slice plan. Specifically the **trigger** answer from Phase 3 — it drives the demo-setup.

### 3. Update Status

If `Status` is not `testing`, set it to `testing` and write back.

### 4. Load the declared stack-pack

`Read` the `## Personality` section of `.claude/project/rules.md`:

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

## Procedure

### Sub-step 5a — Demo-Setup (Autonomy Level 1)

Derive the demo invocation from the slice's recorded trigger:

| Trigger type | Demo-setup |
|---|---|
| User interaction (UI click, etc.) | Start the dev server. Print the URL. List the click sequence. |
| CLI invocation | Print the exact command (with arguments). Show expected stdout snippet. |
| API call | Print the curl / HTTP request. Show expected response status and shape. |
| Event (queue, webhook, cron) | Print how to trigger the event manually (e.g., `redis-cli LPUSH ...`). |
| File / data drop | Print the path to drop the input file. Show expected output file location. |
| System state change | Print how to advance the state manually (e.g., trigger the timer). |

Emit a clear instruction block:

```
Phase 5a — Demo Setup

Trigger: <slice's recorded trigger, verbatim>

Try this:
  1. <step>
  2. <step>
  3. <step>

Expected observable effect:
  <slice's recorded effect, verbatim>
```

Then **wait** for the user to do it.

### Sub-step 5b — User Exercise

Do nothing. The user exercises the artifact. The agent may answer specific questions ("how do I reset the DB?") but does not iterate the artifact during 5b.

### Sub-step 5c — Feedback-Capture (Autonomy Level 0)

When the user comes back, ask the structured prompt:

```
How was it?
  [W] Works as expected → Phase 6
  [B] Found a bug      → enter /craft:debug
  [U] UX issue         → describe what should differ, then iterate
```

Capture the single-letter answer.

#### If `[W]` Works

- Update `Status: review` in the slice plan.
- Emit: `✓ Phase 5 passed. Recommended next: /craft:recap.`
- Stop.

#### If `[B]` Bug

- Append a bug entry to the slice plan's `## Bugs` section with the user's description.
- Tell the user:

  ```
  Bug recorded. Entering /craft:debug mode — we will agree on a verification protocol before any fix attempt.
  ```

- Invoke `/craft:debug` (or instruct the user to run it).

#### If `[U]` UX issue

Ask the user directly:

> What exactly should be different? Be concrete (color, position, wording, behavior).

Wait for the answer — do not interpret. Once the answer is captured, ask:

> Iterate now (one short fix + re-demo), or close the slice with the current behavior and revisit later (new slice)?

If iterate: go back to `/craft:execute` for a focused fix, then return here for 5a / 5c. Loop until `[W]`.

If close-and-revisit: capture the UX issue in `## Decisions Made During This Slice` for Phase 9 promotion consideration, then proceed to `/craft:recap`.

---

## Output Format

#### After 5a (demo setup emitted, awaiting user)

```
Phase 5a — Demo Setup ready. Awaiting your exercise.
```

#### After 5c W

```
✓ Phase 5 passed. Status: review.
Recommended next: /craft:recap
```

#### After 5c B

```
⚠ Bug captured: <one-line>
Entering /craft:debug — agree on a verification protocol before fix attempts.
Recommended next: /craft:debug "<bug-description>"
```

#### After 5c U → iterate

```
Iteration noted: <user's exact requested change>
Resuming Phase 4 for a focused fix.
Recommended next: /craft:execute
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| No `Status: implementing` or `testing` slice found | Stop, recommend `/craft:execute` or `/craft:plan`. |
| User reports "kind of works, but…" without picking W/B/U | Re-ask, force the single-letter choice. Do not interpret vague answers. |
| Demo-setup cannot be derived (trigger field empty in plan) | Tell user the slice plan is missing the Trigger answer; recommend re-running `/craft:plan` to repair, or ask the user inline. |
| User wants to skip Phase 5 because "tests are green" | Refuse politely: *"Phase 5 cannot be skipped — automated tests don't capture product feel. Take 60 seconds to run the demo."* |

---

## What This Command Does NOT Do

- It does **not** modify code. UX iterations bounce back to `/craft:execute`.
- It does **not** make the W/B/U decision for the user.
- It does **not** auto-interpret UX feedback. Always asks the user to be specific.
- It does **not** invoke `/craft:debug` automatically — it recommends, the user types.
