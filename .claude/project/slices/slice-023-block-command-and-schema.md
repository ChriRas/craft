# Slice 023 — Block Command and Schema

> Completed: 2026-07-07
> Commits: 2a2abfd..be6c22c (branch main, trunk-based)
> Epic: epic-002 (Blocked Slice Status), slice 1 of 4

## What

Added a first-class `blocked` slice status via a new `/craft:block` command: a slice in flight
can now be recorded as blocked on an out-of-scope prerequisite or decision — with a four-type
taxonomy, on-demand frontmatter, and a `## Blocker` prose section — where before the only exits
(pause / handoff / debug / abort) modeled no external prerequisite.

## Why

- A running slice must never silently absorb a new direction — that is scope creep (a tabu),
  and a direction change is the human's call under concentrated control. Blocking is therefore
  a structured, visible state, not an ad-hoc note.
- The `blocked` state is consumed by the rest of epic-002 (slice-2 unblock wiring, slice-3
  prime/status surfacing, slice-4 autonomous handoff); getting the schema right here is the
  foundation. Full design spec: [`../design/d1-blocked-state.md`](../design/d1-blocked-state.md).

## Decisions

- **Full 4-type taxonomy** — `prerequisite-work` / `external` / `decision` / `access` are all
  first-class. *Why not* only the spawnable one: one visible status should cover every "cannot
  proceed" situation, not just missing work.
- **Flat topology** — the prerequisite becomes a normal top-level slice/epic; the blocked slice
  carries only a `Blocked-on` edge. *Why not* nesting: a call-stack of blocked slices breeds
  dependency stacks and half-done-slice piles.
- **Record-and-route, not spawn** — `/craft:block` writes the blocked state and points to
  `/craft:plan` / `/craft:epic`; it does not create the prerequisite. *Why not* inline spawn:
  it blurs command boundaries and bloats the slice.
- **On-demand frontmatter** — the four blocker fields are absent on a normal slice, written only
  when blocking; the template documents them as a commented schema. *Why not* always-present
  `(n/a)` fields: noise in every clean slice's frontmatter.
- **Dedicated `## Blocker` section** — not reused from `## Handoff`. *Why not* overload Handoff:
  it has its own semantics (context-poisoned restart).
- **`Blocked-status`, not `Blocked-phase`** (Phase-5 test finding) — the resume field stores the
  prior execution Status token (e.g. `testing`), not a phase number. *Why not* a phase number:
  `Status` tracks the live phase and `/craft:continue` routes on it, while `Phase:` is a
  plan-time stamp that reads stale. Blocking leaves `Phase:` untouched.
- **`Blocked-status` always holds an execution token** (Phase-8 heavy finding, loop-back) —
  step 4 handles the two non-execution statuses A1 allows: `paused` → ask the user (pick-list +
  Pause-Note default); re-block → preserve the existing `Blocked-status`. *Why*: else unblock
  would resume into `paused`/`blocked` and strand the slice.
- **Baseline-edit folded in** — the Problem-Playbook escalation clause shipped as sub-task 3
  here rather than a standalone slice.

## Commits

- `2a2abfd` — feat(block): add /craft:block command + blocked slice schema + baseline escalation clause
- `42fb8c0` — fix(block): store Blocked-status token instead of Blocked-phase, leave Phase untouched
- `df4266e` — fix(block): review in-phase fixes — P1/P3 contradiction + echo-before-write gate
- `9a05494` — fix(block): Blocked-status always holds an execution token
- `be6c22c` — fix(block): round-2 review fixes — re-block path, paused pick-list, A1 catch-all

## Follow-ups

> Light / needs-rethinking findings carried over from Phase 8 Review.

- **Parked-pending back-fill contract** (Light · Rethink) — nothing yet owns updating
  `Blocked-on: (pending — create via /craft:plan)` → `slice-NNN` once the prerequisite is
  created. Belongs to slice-2 (unblock-wiring); recorded so it is wired, not left implicit.
