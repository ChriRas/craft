---
description: Phase 3 — plan a new vertical slice. Dialogically forces the three universal questions (trigger / observable effect / test strategy) and writes a slice plan file.
argument-hint: "<feature-or-slice-name>"
allowed-tools: ["Bash", "Read", "Write", "Glob"]
---

# /craft:plan — Plan a New Vertical Slice

## Purpose

Open Phase 3 of the workflow: break the next chunk of work into a vertical slice that is end-to-end testable, minimal, self-contained, and standalone-experienceable.

This command is a **durable-state mutation** (writes a slice plan file, bumps the slice counter, and links an epic entry to the new slice-ID when the slice refines one) and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`. The three universal questions from Phase 3 are non-negotiable — every slice must answer them before any code is written.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

### Step 1 — Hold project knowledge

- `Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Hold both in context for use during the dialogic phase.

This step is non-fatal on read errors — the Pre-Assertions decide whether to abort. Pre-flight only loads what is needed.

---

## Pre-Assertions

Run all four. Any failure stops the command before any file is touched.

### A1 — Project is onboarded

`Read` `.claude/project/intent.md` and `.claude/project/rules.md`. Both must exist and be non-empty.

Failure → abort:

```
Project is not onboarded (intent.md and/or rules.md missing). Run
`/craft:onboard` first, then re-run /craft:plan.
```

### A2 — Slice template available

Confirm `Read`-ability of `${CLAUDE_PLUGIN_ROOT}/templates/slice-plan.md.template`.

Failure → abort: *"Plugin template `slice-plan.md.template` missing at `<path>`. The CRAFT install may be corrupted — re-install the plugin."*

### A3 — Plugin manifest readable

`Read` `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Must parse as JSON and contain a `version` string.

Failure → abort: *"Plugin manifest unreadable — version cannot be recorded in slice frontmatter. Re-install the plugin."*

### A4 — Slice counter consistent

- `Read` `.claude/plans/.next-id`. If missing, treat the next ID as `001` (allowed; the procedure will create it).
- If present, the file content must parse as a positive integer. If it does not (corrupted), abort:

  ```
  ⚠ .claude/plans/.next-id contains a non-integer value: "<content>".
     /craft:plan will not guess. Inspect the file manually or reset it to one
     above the highest slice-NNN found anywhere: plan files, slice archives
     (.claude/project/slices/) and the slice-IDs in epic plans' decomposition
     entries — an ID handed out twice would revive a dead epic link.
  ```

---

## Procedure (Autonomy Level 1)

The command argument is the feature or slice name. If absent, ask: *"Which slice should we plan? Short name in 3–6 words."*

Derive `<slug>` from the name: lowercase, hyphenated, no whitespace.

If a file `.claude/plans/slice-*-<slug>.md` already exists, append `-2`, `-3`, etc., to the slug to avoid collision.

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

If the user cannot articulate a test strategy, push back per Error Handling — do **not** write a plan with an empty test section.

### 4. Sub-task decomposition

Ask the user, or propose draft sub-tasks based on the trigger / effect / test answers. Sub-tasks should be small enough to bundle individually (≤ a logical work block).

Each sub-task is a single bullet under `## Sub-Tasks`. Use `- [ ]` for unchecked.

### 5. Optional: rough UI / interaction sketch

For UI-bearing slices, ask: *"Do you have a sketch or wireframe? You can describe it in words or paste a path to an image."* Capture if provided.

### 5b. Optional: dependency declaration

Ask:

> Does this slice depend on other slices that must finish first? Pass a comma-separated list of slice-IDs (e.g., `slice-005, slice-007`), or leave empty if independent.

The answer fills the `Depends-On:` frontmatter field. Default is `[]` (no dependencies — runs in parallel with other independent slices under `/craft:execute`). The list must reference plans that exist in `.claude/plans/` or `.claude/project/slices/`; unresolved references are rejected with a prompt to fix or remove them.

### 5c. Epic entry

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-entry-link.sh" candidates` from the project root. It lists the entries a
slice may be linked to, and any epic-plan lines it could not read as entries — the output lines and which entries
those are, and what an entry is, are defined in that helper's header.

- `IGNORED_COUNT` above 0 → name each `IGNORED` line in one line before anything else (*"`<EPIC_PLAN>` line `<n>` is
  not read as an entry: `<text>`"*) — `/craft:execute` A6 rejects that epic until it is fixed, and an unclosed fence
  there can hide every entry.
- `CANDIDATE_COUNT=0` → no entry to offer: skip the question (after the `IGNORED` lines, if any).
- The helper cannot run (non-zero exit, no `CANDIDATE_COUNT=`) → say so in one line (*"epic entries could not be read —
  this slice is planned without an epic link"*) and continue without a link.
- Otherwise ask, with the candidates as a numbered list plus a *none* choice. An entry with `LINK=<id>` was linked to a
  slice that no longer exists — show it as such. An entry with `DUP=yes` shares its short-name with another entry, and
  `link` refuses both until one is renamed — list it as not selectable, with that reason. Say that entries linked to a
  slice that is still open are not listed:

  > Does this slice refine an entry of an epic's `## Slice Decomposition`? Pick one, or none.
  > (Entries already linked to an open slice are not listed.)
  >   [1] epic-<NNN> · `<entry>` — <intent>
  >   [2] epic-<NNN> · `<entry>` — <intent>   (was <id>, aborted)
  >   –   epic-<NNN> · `<entry>` — <intent>   (shares its name with another entry — rename one first)
  >   …
  >   [N] none — a stand-alone slice

  Hold the chosen `EPIC_PLAN` and `ENTRY` for step 8b. *None* → no link.

### 6. Allocate slice ID

- Slice ID = value from `.claude/plans/.next-id` (or `001` if the file is missing), zero-padded to 3 digits.
- Hold the ID and the next-counter value in memory; both will be written atomically in step 7.

### 7. Generate the plan file

Use `templates/slice-plan.md.template`. Substitute:

<!-- craft:writes status=planning -->

- Title from `<feature-or-slice-name>`
- `Slice-ID: slice-<NNN>`
- `Started: <ISO date>`
- `Phase: 3`
- `Status: planning`
- `plugin-version: <from plugin.json>`
- Trigger, effect, and test answers in their sections
- Sub-tasks
- UI sketch reference (if any)
- `Depends-On: <list>` frontmatter (default `[]` from step 5b)
- Empty placeholders for `## Active Rule Overrides`, `## Bugs`, `## Verification Protocols`, `## Bug Fix Attempts`, `## Decisions Made During This Slice`

Write to `.claude/plans/slice-<NNN>-<slug>.md`.

### 8. Increment slice counter

Write the next integer back to `.claude/plans/.next-id`. If the file did not exist before, create it now with the value `2` (since slice `001` was just written).

### 8b. Link the epic entry

Only when step 5c chose an entry. The slice-ID exists now, so write it into the entry — this is what lets
`/craft:execute` A6 still resolve the entry after the slice has landed and its plan is gone:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-entry-link.sh" link "<EPIC_PLAN>" "<ENTRY>" slice-<NNN>
```

Run it from the project root (plan paths are relative to it). Whenever a command from this step is shown to the user,
print it with the plugin root resolved to its absolute path — their shell has no `${CLAUDE_PLUGIN_ROOT}`.

- `RESULT=linked`, `RESULT=relinked` (it replaced the dead ID named in `REPLACED=`) or `RESULT=unchanged` → note the
  epic plan in the output: it is modified. Nothing commits it — in a project that tracks its plans, the human commits it
  along with this slice's plan before `/craft:execute`, whose step 1c compares the epic plan with the trunk.
- `ERROR=` → the slice plan stands; surface the error with the guidance for its reason:
  - `entry_not_found` — the entry was renamed or removed meanwhile: run `candidates` again and link under its current
    short-name, or keep the slice stand-alone.
  - `entry_linked_elsewhere` — another live slice already claims that entry: two slices cannot share one entry. Keep
    this slice stand-alone, or `/craft:abort` the other one first and link again.
  - `slice_already_linked` / `slice_linked_in_other_epic` — an entry already carries this brand-new slice-ID, so the ID
    was handed out twice (a reset `.next-id`) and that entry's link is stale. `/craft:abort` this new slice, set
    `.next-id` above every slice-ID in plans, archives and epic entries (A4), and plan it again.
  - `slice_not_found` — this slice's plan is not where the helper looks (renamed, or several plans carry the ID):
    fix the plan file, then link again.
  - `entry_ambiguous` — two entries share the short-name; the human renames one in the epic plan, then link again.
  - `epic_plan_unreadable` — the epic plan was moved or removed meanwhile: run `candidates` again and pick the entry
    where it now lives, or keep the slice stand-alone.
  - `epic_plan_unwritable:<epic-plan>:read_only` — the epic plan is not writable: the human fixes its permissions,
    then link again. Nothing was changed.
  - `epic_plan_unwritable:<epic-plan>:copy_failed:<file>` — the copy over the epic plan failed part-way, so it may be
    damaged: `<file>` holds its complete new content — restore the epic plan from it.
  - any other `epic_plan_unwritable` (or a helper that cannot run) — nothing was changed; re-run the same command.

  Until linked, `/craft:execute` A6 rejects the entry. Do not edit an entry's slice-ID by hand around the helper.

### 9. Durable Capture — close the loop before finishing

Apply the **Durable Capture** principle (`skills/workflow/SKILL.md` → Knowledge Model →
Durable Capture): *chat is not storage.* Before this command finishes, sweep the planning
dialog for any material insight that surfaced but is not yet written to disk —
architectural or product decisions, trade-offs weighed, scenarios or edge cases
enumerated, a domain model or matrix sketched — and route each to its durable home:

- A decision or trade-off scoped to **this slice** → the plan's `## Decisions Made During
  This Slice` section.
- **Cross-cutting design knowledge** (a domain model, scenario catalog, matrix — anything
  spanning more than this slice) → a focused file under `.claude/project/design/`, and
  note the pointer in the Decisions section so the link is not lost.

**Do not end a planning turn leaving material insight only in chat.** If nothing of
lasting value surfaced beyond the three universal questions, this step is a no-op — say so
explicitly rather than skipping silently.

---

## Post-Assertions

Run all six after the procedure completes. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback.

### P1 — Plan file exists with valid frontmatter

- `Read` `.claude/plans/slice-<NNN>-<slug>.md`. Must exist and be non-empty.
- Frontmatter must contain `Slice-ID: slice-<NNN>`, `Status: planning`, `Phase: 3`, `Started:` (ISO date), and `plugin-version:`.

Failure → *"⚠ Plan file missing or malformed at `<path>`. Inspect manually before continuing to /craft:build."*

### P2 — Required sections present

The plan file must contain every `## ` section header of `templates/slice-plan.md.template` (the
template A2 read) — from `## Goal` through `## Pause Note`, including the sections later phases fill
(`## Recap Draft`, `## Review Findings`, `## Blocker`, `## Handoff`, `## Pause Note`). The template is
the one list; do not check a copy of it.

Failure → *"⚠ Plan file is missing required sections: `<list>`. The template may be malformed or the substitution failed."*

### P3 — Trigger / Effect / Test sections non-empty

The three universal-question sections must each contain user-captured content (not the template placeholder).

Failure → *"⚠ One or more of Trigger / Effect / Test sections is empty. The plan was written, but Phase 3 is not actually answered. Edit `<path>` before /craft:build."*

### P4 — Counter incremented

- `Read` `.claude/plans/.next-id`. Must equal the value held in memory after step 8 (old value + 1).
- If the file did not exist before, it must now exist with value `2`.

Failure → *"⚠ Slice counter not incremented — the next /craft:plan call may collide with this slice ID. Inspect `.claude/plans/.next-id` and fix manually."*

### P5 — Durable Capture closed

The planning dialog left no material insight stranded in chat (Procedure step 9 ran).
Verify one of two states holds:

- The `## Decisions Made During This Slice` section contains the decisions/trade-offs that
  surfaced in the dialog (not the `- (none yet)` placeholder), **and** any cross-cutting
  design knowledge produced was written under `.claude/project/design/` with a pointer
  recorded in that section; or
- the dialog genuinely produced nothing of lasting value beyond the three universal
  questions, and that was stated explicitly.

Failure → *"⚠ Durable Capture skipped — material insight from the planning dialog may
exist only in chat and will be lost on the next /clear or compaction. Review the dialog
and write decisions to `## Decisions Made During This Slice` (or cross-cutting knowledge
to `.claude/project/design/`) in `<path>` before continuing."*

### P6 — Epic entry linked

Only when step 5c chose an entry: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-entry-link.sh" resolve "<EPIC_PLAN>"`, run
from the project root, must print a line `SLICE=slice-<NNN> STATE=plan PLAN=.claude/plans/slice-<NNN>-<slug>.md
ENTRY=<ENTRY>`. No entry chosen → passes vacuously.

Failure → *"⚠ Epic entry `<ENTRY>` in `<EPIC_PLAN>` is not linked to slice-<NNN> — `/craft:execute` A6 will reject it."*,
followed by step 8b's guidance for the `ERROR=` reason `link` reported — or, when `link` succeeded, the entry's actual
`resolve` line (and any `IGNORED` line), so the human sees what the epic plan holds now.

---

## Output Format

Success:

```
✓ Plan: .claude/plans/slice-<NNN>-<slug>.md
✓ Pre-assertions: onboarded, template ✓, manifest ✓, counter ✓
✓ Post-assertions: frontmatter ✓, sections ✓, three universal questions answered, counter incremented, durable capture ✓[, epic entry linked]

  [Epic:    epic-<NNN> · entry `<ENTRY>` → slice-<NNN>   (epic plan modified)]
  Trigger: <one line>
  Effect:  <one line>
  Test:    <one line>
  Sub-tasks: <N>

Next: /craft:build
```

Aborted:

```
Plan aborted — <reason>. No changes made.
```

Partial (post-assertion failure):

```
⚠ Plan partially written — <which assertion(s) failed>.
   File: <path>
   Inspect and reconcile manually before running /craft:build.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (not onboarded) | Abort with `/craft:onboard` recommendation. |
| A2 fails (template missing) | Abort with plugin-reinstall hint. |
| A3 fails (manifest unreadable) | Abort with plugin-reinstall hint. |
| A4 fails (corrupt `.next-id`) | Abort; user inspects manually, no auto-reset. |
| User skips one of the three universal questions | Re-ask; do not write the plan with empty trigger / effect / test sections. P3 would catch a slip, but the dialog should not let it through in the first place. |
| Slug collides with an existing slice file | Append `-2`, `-3`, etc., to the slug. Handled in Procedure pre-step (before step 1). |
| User wants to plan with no clear test strategy | Push back: *"Phase 3 requires a test strategy before Phase 4. If we cannot articulate one, the slice may be too vague — let's break it down further or revisit the goal."* Do not proceed to step 7. |
| P1/P2/P3 fail after write | Warn loudly; emit partial-completion block; do not auto-rollback. |
| P4 fails (counter not incremented) | Warn loudly; user fixes `.next-id` manually before the next /craft:plan. |
| Step 8b `link` fails or P6 fails (epic entry not linked) | Warn loudly; the slice plan stands. Give step 8b's guidance for the helper's `ERROR=` reason; never hand-edit an entry's slice-ID. |
| P5 fails (Durable Capture skipped) | Warn loudly; the dialog's material insight may live only in chat. Capture it to the Decisions section (or `.claude/project/design/`) before /craft:build. |

---

## What This Command Does NOT Do

- It does **not** write any code.
- It does **not** start Phase 4. Update the slice plan's `Status:` to `implementing` only when `/craft:build` actually starts — not here.
- It does **not** commit anything.
- It does **not** modify `intent.md` or `rules.md`. Architectural insights surfaced during planning go into the plan's `## Decisions Made During This Slice` section (Durable Capture, Procedure step 9) — or, when cross-cutting, into `.claude/project/design/` — and are promoted (or not) in Phase 9.
- It does **not** auto-rollback on post-assertion failure. Partial state is surfaced for human reconciliation.
