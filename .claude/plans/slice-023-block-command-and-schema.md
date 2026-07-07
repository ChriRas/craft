# Slice 023 — Block Command and Schema

> Status: planning | implementing | testing | review | refactoring | reviewing | committing | paused | committed
> Slice-ID: slice-023
> Slice-Slug: block-command-and-schema
> Started: 2026-07-07
> Phase: 3
> plugin-version: 1.3.0
> Handoff active: no
> Depends-On: []

## Goal

A `/craft:block` command exists that records a first-class `blocked` state onto the active
slice — with a four-type blocker taxonomy, on-demand frontmatter, a `## Blocker` prose
section — and the Senior-Developer baseline carries the escalation clause that routes
scope-exceeding obstacles here instead of growing the slice.

## Vertical Slice Definition

Plugin-authoring slice spanning: a new command (`commands/block.md`), the slice-plan
template schema (`templates/slice-plan.md.template`), and the baseline skill
(`skills/senior-developer/SKILL.md`). Foundation of epic-002 — the state this slice writes
is consumed by later slices (unblock-wiring, surfacing, autonomous-handoff).

## Trigger

CLI invocation: the user runs `/craft:block` while a slice is active (typically mid Build /
Test), optionally naming the blocker type. This is the interactive front-end of the
`blocked` state (the autonomous `.craft/handoff.md` front-end is a later slice).

## Effect

Persistent state change on the active slice plan file:
- `Status: blocked`
- On-demand frontmatter written by the command: `Blocker-type:` (prerequisite-work |
  external | decision | access), `Blocked-on:` (slice/epic-ID or free text), `Blocked-since:`
  (ISO date), `Blocked-phase:` (the phase to resume into).
- A `## Blocker` prose section, handoff-style: what's missing · what was tried · what
  "unblocked" looks like (the resume acceptance).
- For `prerequisite-work`, the 3-option dialog runs (spawn → route to `/craft:plan` /
  `/craft:epic` / park / descope); the command records and routes, it does not itself create
  the prerequisite slice.
- Plus a stdout confirmation of the recorded block.

Schema/baseline side-effects: the template's `Status:` enum gains `blocked` and documents
the four optional fields + the `## Blocker` section; `skills/senior-developer/SKILL.md`
Problem-Playbook carries the escalation clause.

## Test Strategy

This repo's convention — `claude plugin validate` + structural checks; no behavioral runner.
- Setup: a scratch slice plan file in a state that `/craft:block` can act on.
- Assertions (structural greps): (a) `commands/block.md` exists and carries Pre/Post-Assertions
  (D24 — mutates durable state) and the full `/craft:` namespace in cross-refs; (b) the
  template `Status:` enum contains `blocked` and documents the four blocker fields + the
  `## Blocker` section; (c) `skills/senior-developer/SKILL.md` contains the escalation clause
  with the 3-criteria heuristic.
- End-to-end: running the `/craft:block` procedure against the scratch slice yields
  `Status: blocked` with the four fields populated and a filled `## Blocker` section, and
  `claude plugin validate` stays green.

## Sub-Tasks

- [ ] Author `commands/block.md` — Pre/Post-Assertions, 4-type taxonomy dialog, `prerequisite-work` 3-option fork (spawn→route / park / descope), writes blocker frontmatter + `## Blocker` prose on-demand, sets `Status: blocked`
- [ ] Extend `templates/slice-plan.md.template` — add `blocked` to the Status enum; document the four optional blocker fields + a `## Blocker` section (commented schema, on-demand fields)
- [ ] Edit `skills/senior-developer/SKILL.md` — Problem-Playbook escalation clause with the 3-criteria heuristic (folds in the epic's baseline-edit item)
- [ ] Register/validate — confirm command discovery, run `claude plugin validate` green

## Active Rule Overrides

> Stage-2 overrides for this slice. Cleared automatically on Phase 9 cleanup.

(none)

## Bugs

> Filled by `/test` (Phase 5 [B] feedback) or `/debug`.

(none)

## Verification Protocols

> Filled by `/debug` Step 2 (PROTOCOL). Frozen — no mid-loop mutation.

(none)

## Bug Fix Attempts

> Filled by `/debug` Step 3 (AUTONOMOUS LOOP). Audit trail of each attempt.

(none)

## Decisions Made During This Slice

> Captured as architectural / product decisions surface. Phase 9 walks each entry with `[K]/[I]/[R]/[D]` promotion dialog.

- **Design record** — this slice implements the spec in
  [`.claude/project/design/d1-blocked-state.md`](../project/design/d1-blocked-state.md)
  (epic-002, slice 1 of 4).
- **Blocker prose = dedicated `## Blocker` section** — not reusing `## Handoff`, which has its
  own semantics (context-poisoned restart). Keeps the two concepts separate.
- **Blocker frontmatter fields = on-demand** — the four fields are absent on a normal slice
  and written only when `/craft:block` fires; the template documents them as a commented
  schema. *Why:* keeps clean slices unburdened; parsers (prime/status) treat the fields as
  optional.
- **`/craft:block` records & routes, does not spawn** — for `prerequisite-work` it writes the
  `blocked` state and points the user to `/craft:plan` / `/craft:epic`; the prerequisite ID
  is back-filled into `Blocked-on`. *Why:* keeps command boundaries clean and this slice lean.
- **Baseline-edit folded in** — the epic's separate baseline-edit item ships as sub-task 3 of
  this slice rather than a standalone 5th slice.

## Recap Draft

> Filled by `/recap` (Phase 6). Becomes the basis for the slice archive in Phase 9.

(not yet recorded)

## Review Findings

> Filled by `/craft:review` (Phase 8). Audit trail — one line per finding: `Severity · Fix-nature · description · resolution`.

(none yet)

## Handoff

> Filled by `/handoff` when context-poisoned. Read by the next session's `/prime`.

(none)

## Pause Note

> Filled by `/pause` when work pauses mid-phase.

(none)
