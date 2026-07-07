# Slice 025 — Surfacing Blocked Slices

> Status: reviewing
> Slice-ID: slice-025
> Slice-Slug: surfacing
> Started: 2026-07-07
> Phase: 3
> plugin-version: 1.3.0
> Handoff active: no
> Depends-On: [slice-023]

## Goal

Blocked slices are visible where the user looks: `/craft:prime` and `/craft:status` show each
blocked slice with its `Blocked-on` target and `Blocker-type`, flag orphaned blockers, and never
offer a blocked slice as a plain "continue".

## Vertical Slice Definition

Plugin-authoring slice spanning two read-only reporters: `commands/prime.md` (session-start
status block + recommended-next-action) and `commands/status.md` (lightweight overview). Reads
the `blocked` schema from slice-023; epic-002 slice 3 of 4. No mutation.

## Trigger

CLI invocation: running `/craft:prime` (including the SessionStart auto-prime) or
`/craft:status`.

## Effect

Stdout only (both commands are read-only):
- The active-slices block marks each blocked slice distinctly, showing its `Blocked-on` target
  and `Blocker-type`.
- `/craft:prime`'s "recommended next action" gives a blocked slice its **own priority line** —
  it shows the blocker and recommends `/craft:unblock` (or working the prerequisite), and never
  recommends a blocked slice as a plain `/craft:continue`.
- An **orphan warning** appears when a `prerequisite-work` blocker's `Blocked-on` ID resolves to
  neither an active plan nor an archived slice/epic (prerequisite aborted or never created).

## Test Strategy

This repo's convention — `claude plugin validate` + structural checks; no behavioral runner.
- Setup: scratch fixtures in `.claude/plans/` — (a) a blocked slice `Blocked-on: slice-0P`
  where slice-0P exists; (b) a blocked slice `Blocked-on: slice-0X` where slice-0X does not
  exist (orphan); (c) a blocked slice `Blocked-on: (pending — …)`.
- Surfacing: the `/craft:prime` / `/craft:status` slice scan marks (a)/(b)/(c) as blocked with
  their `Blocked-on` + `Blocker-type`.
- Orphan: only (b) raises an orphan warning; (a) and (c) do not.
- Recommendation: `/craft:prime` does not recommend a blocked slice as plain `/craft:continue`;
  it routes to `/craft:unblock`.
- Structural greps: `commands/prime.md` + `commands/status.md` carry the blocked-surfacing +
  orphan logic; prime's recommended-next priority includes a blocked case. `claude plugin
  validate` green.

## Sub-Tasks

- [x] `commands/prime.md` — surface blocked slices in the active-slices block (marker + `Blocked-on` + `Blocker-type`); add a blocked case to the "recommended next action" priority order that routes to `/craft:unblock` and never offers plain continue
- [x] `commands/status.md` — mark blocked slices in the overview with `Blocked-on` + `Blocker-type`
- [x] Orphan detection — in prime + status, flag a `prerequisite-work` blocker whose `Blocked-on` ID resolves to neither an active plan nor an archive (`(pending)` and free-text blockers excluded)
- [x] Validate + dry-run the surfacing, orphan, and recommendation scenarios; `claude plugin validate` green (interactive scenario dry-runs deferred to Phase 5)

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

- **Design record** — implements the Visibility line of the Unblocking & resume section in
  [`../project/design/d1-blocked-state.md`](../project/design/d1-blocked-state.md) (epic-002,
  slice 3 of 4).
- **Prime recommendation = blocked gets its own priority** — a blocked slice is never offered as
  a plain `/craft:continue`; it surfaces its blocker and recommends `/craft:unblock`. Slots into
  the existing recommended-next priority order near the handoff/stale cases.
- **Orphan scope = `prerequisite-work` with an unresolved ID only** — `(pending — …)` markers are
  intentional (not orphans); `external`/`decision`/`access` blockers carry free-text `Blocked-on`
  that is not ID-resolvable, so are never flagged. Mirrors the auto-resurface `Blocker-type` guard
  from slice-024.

## Recap Draft

> Filled by `/recap` (Phase 6). Becomes the basis for the slice archive in Phase 9.

### What
Blocked slices are now visible where the user looks: `/craft:prime`'s session-start status block
and `/craft:status` mark each blocked slice with a `⛔` flag (its `Blocked-on` target +
`Blocker-type`) and flag orphaned blockers. Prime's "recommended next" gives a blocked slice its
own priority — routing to `/craft:unblock`, never offering it as a plain `/craft:continue`.

### Why
An invisible blocked slice is a trap — forgotten, or worse, recommended for "continue" when it
can't proceed. Decisions: (1) prime's recommendation treats `blocked` as its own priority, so a
waiting slice is surfaced honestly with a route to `/craft:unblock`; (2) orphan detection is
scoped to `prerequisite-work` with an unresolvable ID only — `(pending)` is intentional and
`external`/`decision`/`access` carry free-text with no ID — mirroring slice-024's auto-resurface
`Blocker-type` guard so the feature is consistent about which blockers reference IDs.

### Walk-through
On `/craft:prime` or `/craft:status`, the slice scan reads each plan's frontmatter. For a
`Status: blocked` slice, the phase label is derived from `Blocked-status` (never rendered as
"blocked"), and a `⛔` marker with `Blocked-on` + `Blocker-type` is appended. If `Blocker-type`
is `prerequisite-work` and `Blocked-on` resolves to neither an active plan (`.claude/plans/`) nor
an archive (`.claude/project/slices/`), a `⚠ orphan` marker is added. In prime, a blocked slice
enters the recommended-next priority order as its own case → `/craft:unblock`.

### Diagram
(none — 2 files, single read-only reporting layer; below the complexity threshold)

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
