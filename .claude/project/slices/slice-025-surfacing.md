# Slice 025 — Surfacing Blocked Slices

> Completed: 2026-07-08
> Commits: 7a2aa7f..3e456ee (branch main, trunk-based)
> Epic: epic-002 (Blocked Slice Status), slice 3 of 4

## What

Blocked slices are now visible where the user looks: `/craft:prime`'s session-start status block
and `/craft:status` mark each blocked slice with a `⛔` flag (its `Blocked-on` target +
`Blocker-type`) and flag orphaned blockers. Prime's "recommended next" gives a blocked slice its
own priority — routing to `/craft:unblock`, never offering it as a plain `/craft:continue`.

## Why

- An invisible blocked slice is a trap — forgotten, or worse, recommended for "continue" when it
  cannot proceed. Making it a first-class, marked state (with a route to `/craft:unblock`) keeps
  the human honestly informed.
- Orphan detection reuses the same `Blocker-type: prerequisite-work` guard slice-024 introduced,
  so the whole blocked feature is consistent about which blockers reference resolvable IDs. Full
  design spec: [`../design/d1-blocked-state.md`](../design/d1-blocked-state.md).

## Decisions

- **Prime recommendation = blocked gets its own priority** — a `Status: blocked` slice is never
  offered as a plain `/craft:continue`; it surfaces its blocker and recommends `/craft:unblock`,
  slotting into the recommended-next priority order after handoff/stale and able to co-fire with
  the workable-slice cases when blocked and unblocked slices coexist. *Why not* just mark it:
  recommending "continue" on a slice that cannot proceed is a trap.
- **Orphan scope = `prerequisite-work` with an unresolved ID only** — `(pending — …)` markers are
  intentional (not orphans); `external`/`decision`/`access` blockers carry free-text `Blocked-on`
  that is not ID-resolvable, so are never flagged. *Why:* mirrors slice-024's auto-resurface
  `Blocker-type` guard — only `prerequisite-work` puts a resolvable ID in `Blocked-on`.
- **Blocked phase label via `Blocked-status`** — both reporters resolve a blocked slice's phase
  from `Blocked-status` (an execution token), never rendering `blocked` as a phase, since `Status`
  is the live phase and `Phase:` reads stale.

## Commits

- `7a2aa7f` — feat(surfacing): show blocked slices in prime + status with orphan detection
- `3e456ee` — fix(surfacing): resolve blocked-rule overlap, co-fire header, phase-mapping xref

## Follow-ups

> Light / needs-rethinking findings carried over from Phase 8 Review.

- (none — all three Phase-8 findings were Local edits, fixed in-phase.)
