---
description: Plan a multi-slice epic — captures Vision and initial Slice Decomposition, writes an epic plan file under .claude/plans/.
argument-hint: "<epic-name>"
allowed-tools: ["Bash", "Read", "Write", "Glob"]
---

# /craft:epic — Plan a Multi-Slice Epic

## Purpose

Establish a hierarchical layer above slices. Where `/craft:plan` plans a single vertical slice, `/craft:epic` plans a body of work composed of several slices that share a common Vision and Decomposition.

This command is a **durable-state mutation** (writes an epic plan file, bumps the epic counter) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`. Epic and Slice ID-spaces are independent — `.claude/plans/.next-id` counts slices, `.claude/plans/.next-epic-id` counts epics.

This first version implements only the **create path**: it records Vision and an initial Decomposition list. Epic-to-slice linking, `decompose`, and `complete` sub-commands are deliberately out of scope.

---

## Pre-flight

### Step 1 — Hold project knowledge

- `Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Hold both in context for use during the dialogic phase.

This step is non-fatal on read errors — the Pre-Assertions decide whether to abort.

---

## Pre-Assertions

Run all four. Any failure stops the command before any file is touched.

### A1 — Project is onboarded

`Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Both must exist and be non-empty.

Failure → abort:

```
Project is not onboarded (intent.md and/or rules.md missing). Run
`/craft:onboard` first, then re-run /craft:epic.
```

### A2 — Epic template available

Confirm `Read`-ability of `${CLAUDE_PLUGIN_ROOT}/templates/epic-plan.md.template`.

Failure → abort: *"Plugin template `epic-plan.md.template` missing at `<path>`. The CRAFT install may be corrupted — re-install the plugin."*

### A3 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON and contain a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in epic frontmatter. Re-install the plugin."*

### A4 — Epic counter consistent

- `Read` `.claude/plans/.next-epic-id`. If missing, treat the next ID as `001` (allowed; the procedure will create it).
- If present, the file content must parse as a positive integer. If it does not (corrupted), abort:

  ```
  ⚠ .claude/plans/.next-epic-id contains a non-integer value: "<content>".
     /craft:epic will not guess. Inspect the file manually or reset it to the
     next epic number derived from the highest existing epic-NNN-*.md file.
  ```

---

## Procedure (Autonomy Level 1)

The command argument is the epic name. If absent, ask: *"Which epic should we plan? Short name in 3–6 words."*

Derive `<slug>` from the name: lowercase, hyphenated, no whitespace.

If a file `.claude/plans/epic-*-<slug>.md` already exists, append `-2`, `-3`, etc., to the slug to avoid collision.

### 1. Vision question

Ask, dialogically:

> What is the Vision for this epic? Three to six sentences that capture:
> - **Why** the epic exists (motivation, the gap it closes).
> - **What** the end-state looks like for the user when the epic is done.
> - **Scope edges** — what the epic deliberately does NOT include.

Capture the answer verbatim. Empty or one-line answers are rejected — ask again.

### 2. Decomposition question

Ask:

> Sketch the initial slice decomposition. Two to seven entries, each one line:
> `<short-name> — <one-line intent>`. This is a roadmap, not a contract; slices
> will be refined later via `/craft:plan`. Order matters — list them in the
> intended execution sequence.

Capture verbatim. At minimum two entries must be supplied — an epic with one
slice is just a slice. If the user offers only one, push back per Error Handling.

### 3. Allocate epic ID

- Epic ID = value from `.claude/plans/.next-epic-id` (or `001` if the file is missing), zero-padded to 3 digits.
- Hold the ID and the next-counter value in memory; both will be written atomically in step 4.

### 4. Generate the plan file

Use `templates/epic-plan.md.template`. Substitute:

- Title from `<epic-name>`
- `Epic-ID: epic-<NNN>`
- `Epic-Slug: <slug>`
- `Started: <ISO date>`
- `Phase: 3`
- `Status: planning`
- `plugin-version: <from plugin.json>`
- Vision content under `## Vision`
- Decomposition entries under `## Slice Decomposition` as `- [ ] <short-name> — <intent>`
- Leave default placeholders for `## Decisions Made During This Epic`, `## Recap Draft`, `## Handoff`, `## Pause Note` untouched (the template ships them as `- (none yet)` / `(not yet recorded)` / `(none)`)

Write to `.claude/plans/epic-<NNN>-<slug>.md`.

### 5. Increment epic counter

Write the next integer back to `.claude/plans/.next-epic-id`. If the file did not exist before, create it now with the value `2` (since epic `001` was just written).

---

## Post-Assertions

Run all four after the procedure completes. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback.

### P1 — Plan file exists with valid frontmatter

- `Read` `.claude/plans/epic-<NNN>-<slug>.md`. Must exist and be non-empty.
- Frontmatter must contain `Epic-ID: epic-<NNN>`, `Status: planning`, `Phase: 3`, `Started:` (ISO date), and `plugin-version:`.

Failure → *"⚠ Epic file missing or malformed at `<path>`. Inspect manually before continuing."*

### P2 — Required sections present

The epic file must contain these section headers:

- `## Vision`
- `## Slice Decomposition`
- `## Decisions Made During This Epic`

Failure → *"⚠ Epic file is missing required sections: `<list>`. The template may be malformed or the substitution failed."*

### P3 — Vision and Decomposition sections non-empty

- `## Vision` must contain at least one non-placeholder sentence.
- `## Slice Decomposition` must contain at least two `- [ ]` entries with non-placeholder content (no `{{…}}` markers).

Failure → *"⚠ Vision and/or Decomposition is empty or under-filled. The plan was written, but the epic is not actually shaped. Edit `<path>` before relying on it."*

### P4 — Counter incremented

- `Read` `.claude/plans/.next-epic-id`. Must equal the value held in memory after step 5 (old value + 1).
- If the file did not exist before, it must now exist with value `2`.

Failure → *"⚠ Epic counter not incremented — the next /craft:epic call may collide with this epic ID. Inspect `.claude/plans/.next-epic-id` and fix manually."*

---

## Output Format

Success:

```
✓ Epic: .claude/plans/epic-<NNN>-<slug>.md
✓ Pre-assertions: onboarded, template ✓, manifest ✓, counter ✓
✓ Post-assertions: frontmatter ✓, sections ✓, vision + decomposition non-empty, counter incremented

  Vision:        <one-line summary>
  Decomposition: <N> slices listed

Next:
  /craft:plan <name>          refine each decomposition entry into a regular slice
  /craft:execute epic-<NNN>   once every decomposition entry is planned, run the
                              epic autonomously through Phase 4–7 in parallel
                              worktrees (slices without dependencies run in
                              parallel; the orchestrator stops for review at the
                              epic-end or at any checkpoint declared in the epic
                              plan's `## Review Checkpoints`).
```

Aborted:

```
Epic aborted — <reason>. No changes made.
```

Partial (post-assertion failure):

```
⚠ Epic partially written — <which assertion(s) failed>.
   File: <path>
   Inspect and reconcile manually.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (not onboarded) | Abort with `/craft:onboard` recommendation. |
| A2 fails (template missing) | Abort with plugin-reinstall hint. |
| A3 fails (manifest unreadable) | Abort with plugin-reinstall hint. |
| A4 fails (corrupt `.next-epic-id`) | Abort; user inspects manually, no auto-reset. |
| User offers only one decomposition entry | Push back: *"An epic with a single slice is just a slice — run /craft:plan instead, or add at least one more entry."* Do not proceed to step 4. |
| Vision answer is empty or one short line | Re-ask, citing the three guiding bullets. Do not write the plan with a thin vision. |
| Slug collides with an existing epic file | Append `-2`, `-3`, etc., to the slug. Handled before step 1. |
| P1/P2/P3 fail after write | Warn loudly; emit partial-completion block; do not auto-rollback. |
| P4 fails (counter not incremented) | Warn loudly; user fixes `.next-epic-id` manually before the next /craft:epic. |

---

## What This Command Does NOT Do

- It does **not** plan individual slices. Use `/craft:plan <slice-name>` for that — typically taking entries from the epic's `## Slice Decomposition`.
- It does **not** link slices back to the epic. Slice-to-epic association is a future capability (separate slice).
- It does **not** execute, decompose interactively, or track epic completion. Those are future capabilities.
- It does **not** modify `intent.md` or `rules.md`. Decisions surfaced during epic shaping go into the epic's `## Decisions Made During This Epic` section.
- It does **not** auto-rollback on post-assertion failure. Partial state is surfaced for human reconciliation.
