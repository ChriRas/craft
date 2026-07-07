# Slice 024 — Unblock Wiring

> Status: review
> Slice-ID: slice-024
> Slice-Slug: unblock-wiring
> Started: 2026-07-07
> Phase: 3
> plugin-version: 1.3.0
> Handoff active: no
> Depends-On: [slice-023]

## Goal

A blocked slice comes back to life: closing its prerequisite auto-clears the block, and
`/craft:continue` on the freed slice offers `resume | re-plan | abort` — restoring the slice
to the exact execution status it was blocked at.

## Vertical Slice Definition

Plugin-authoring slice spanning: `commands/commit.md` (auto-resurface on prerequisite close), a
new `commands/unblock.md` (the resume fork + `(pending)` → real-ID back-fill — the mutating
unblock surface), and a minimal read-only routing row in `commands/continue.md` (`blocked` →
`/craft:unblock`). Consumes the `blocked` schema from slice-023; epic-002 slice 2 of 4.

## Trigger

CLI invocation, two entry points:
1. `/craft:commit` closing a slice/epic that other slices declare `Blocked-on:`.
2. `/craft:continue <slice>` on a slice whose `Status` is `blocked`.

## Effect

Persistent state change:
- On prerequisite close (`/craft:commit`): every slice plan with `Blocked-on:` referencing the
  just-closed slice/epic ID has its block cleared — `Status: blocked` → its stored
  `Blocked-status`, the on-demand blocker frontmatter fields removed, the `## Blocker` section
  marked resolved (audit note), and a notification emitted listing the freed slice(s).
- On `/craft:continue` of a blocked slice: it **routes** (read-only) to `/craft:unblock`.
- `/craft:unblock <slice>` presents the `resume | re-plan | abort` fork — **resume** restores
  `Status: Blocked-status`; **re-plan** routes to reshape the slice; **abort** routes to
  `/craft:abort`. On a `Blocked-on: (pending — …)` slice it first offers the back-fill prompt
  (enter the created prerequisite's ID) so auto-resurface can later match it by ID.

## Test Strategy

This repo's convention — `claude plugin validate` + structural checks; no behavioral runner.
- Setup: two scratch slice plans — a prerequisite `slice-0P` at `committing`, and a dependent
  `slice-0D` at `Status: blocked`, `Blocked-on: slice-0P`, `Blocked-status: testing`.
- Auto-resurface: running `/craft:commit`'s new resurface step against `slice-0P` closing
  flips `slice-0D` to `Status: testing`, strips its blocker fields, and marks `## Blocker`
  resolved.
- Resume fork: `/craft:unblock` on a blocked scratch slice presents `resume | re-plan | abort`
  and, on resume, restores the recorded `Blocked-status`.
- Back-fill: `/craft:unblock` on a `Blocked-on: (pending — …)` scratch slice prompts for and
  writes the real prerequisite ID.
- Structural greps: `commands/commit.md` carries the auto-resurface step; `commands/unblock.md`
  exists with Pre/Post-Assertions, the fork, and the back-fill; `commands/continue.md` routes
  `blocked` → `/craft:unblock` and stays read-only (Read/Glob). `claude plugin validate` green.

## Sub-Tasks

- [x] `commands/commit.md` — add the auto-resurface step (after archive write / plan delete): scan `.claude/plans/*.md` for `Blocked-on:` referencing the closed slice/epic ID → clear block (Status → `Blocked-status`, strip blocker fields, mark `## Blocker` resolved), notify
- [x] `commands/unblock.md` (new) — mutating unblock command with Pre/Post-Assertions (D24): the `resume | re-plan | abort` fork (resume restores `Status: Blocked-status`) + the `(pending)` → real-ID back-fill/link
- [x] `commands/continue.md` — minimal read-only routing: add a `blocked` row to the Status table → recommend `/craft:unblock`; keep the read-only contract (Read/Glob, no mutation)
- [x] Validate + dry-run the auto-resurface, resume-fork, and back-fill scenarios; `claude plugin validate` green (interactive scenario dry-runs deferred to Phase 5)

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

- **Design record** — implements the Unblocking & resume section of
  [`../project/design/d1-blocked-state.md`](../project/design/d1-blocked-state.md) (epic-002,
  slice 2 of 4).
- **Dedicated `/craft:unblock` command** (build-phase architecture decision) — `/craft:continue`
  is contractually a read-only router (`Read`/`Glob`; "does not modify the plan / change
  Status"). The unblock mutations (resume-fork, back-fill) live in a new `/craft:unblock`
  instead; `continue.md` only gains a `blocked` → `/craft:unblock` routing row. Symmetric to
  `/craft:block`; resolves the design record's open question (yes, add `/craft:unblock`).
- **Back-fill owner = `/craft:unblock`** — the `(pending)` → real-ID link is written by
  `/craft:unblock` (routed from `/craft:continue`). *Why not* `/craft:commit` auto-scan or
  `/craft:plan` reverse-link: keeps linking inside the unblock domain and off commands that
  shouldn't need to know the blocked schema.
- **Unblock cleanup policy** — on auto-resurface, restore `Status: Blocked-status` and **remove**
  the four on-demand blocker frontmatter fields (they are on-demand by slice-023's decision);
  leave the `## Blocker` section as a resolved historical note (`> Resolved: <date>`) for audit
  rather than deleting it.
- **Back-fill must precede the prerequisite's commit** (coherence note) — auto-resurface matches
  `Blocked-on:` against the closing slice's ID, so a still-`(pending)` dependent cannot be
  matched. The `/craft:continue` back-fill has to run before the prerequisite reaches Phase 9.

## Recap Draft

> Filled by `/recap` (Phase 6). Becomes the basis for the slice archive in Phase 9.

(not yet recorded)

## Review Findings

> Filled by `/craft:review` (Phase 8). Audit trail — one line per finding: `Severity · Fix-nature · description · resolution`.

(none yet)

## Blocker

> Filled by `/craft:block` when the slice cannot proceed until an out-of-scope prerequisite
> or decision is resolved. On block, `/craft:block` also adds these on-demand frontmatter
> fields below `Status:` (absent on a normal slice):
> `Blocker-type:` (prerequisite-work | external | decision | access) ·
> `Blocked-on:` (slice/epic-ID, free text, or `(pending — create via /craft:plan)`) ·
> `Blocked-since:` (ISO date) · `Blocked-status:` (prior execution Status to restore on unblock).

(none)

## Handoff

> Filled by `/handoff` when context-poisoned. Read by the next session's `/prime`.

(none)

## Pause Note

> Filled by `/pause` when work pauses mid-phase.

(none)
