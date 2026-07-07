# Design Record — D1: First-Class `blocked` Slice Status

> Status: designed, not yet implemented. Captured 2026-07-07 from a design discussion.
> Consumed by a future `/craft:epic` (D1). Epic-sized (~4–5 slices).
> Backlog: `roadmap.md` → D1.

## Problem

A slice in flight hits an obstacle whose resolution lies outside its scope — classically:
in Phase 5 (Test) the artifact can't be verified because a prerequisite (e.g. deployment
infrastructure) doesn't exist yet. General case: **an unexpected problem whose fix is a new
feature, task, or direction.** Invariant CRAFT must protect: *the running slice never
silently absorbs the new direction* — that is scope creep (a tabu) and a direction change is
the human's call under concentrated control.

## What is / isn't a blocker

Not a blocker (stays in-slice or elsewhere):
- Bug in own code → `/craft:debug`.
- Minor unforeseen dependency, buildable minimally → Problem-Playbook, in-slice.
- "I stepped away" → `/craft:pause`.

A blocker: a blocking prerequisite that is itself a unit of work or a direction decision.
**Spawn-boundary heuristic** — it's a blocker when the missing thing (a) would have its own
test/observable effect, (b) exceeds the slice's declared scope, OR (c) is an unsanctioned
direction. Otherwise build it minimally in-slice. **In doubt → escalate.**

## Blocker taxonomy (all four are first-class)

| Type | Example | Resolution |
|---|---|---|
| `prerequisite-work` | infra missing, API absent | spawns a slice/epic |
| `external` | third-party down, cert expired | wait on the world |
| `decision` | open direction question | human decides |
| `access` | credentials/permission missing | human acts |

Only `prerequisite-work` creates new work; the others are genuine waits but share the one
visible status.

## State schema (frontmatter + prose)

- `Status: blocked`
- `Blocker-type:` prerequisite-work | external | decision | access
- `Blocked-on:` slice/epic-ID (for prerequisite-work) or free text
- `Blocked-since:` date (staleness)
- `Blocked-status:` prior execution Status token to restore on unblock (captured from the
  live `Status:`, which tracks the phase — `Phase:` is a plan-time stamp and reads stale)
- Prose block (handoff-style): what's missing · what was tried · what "unblocked" looks
  like (the resume acceptance).

## Topology — flat, not nested

The prerequisite becomes a normal top-level slice/epic; the blocked slice carries only the
edge `Blocked-on`. No call-stack, no nesting → avoids dependency stacks and half-done-slice
piles; composes with existing epic machinery.

## Two frontends, one state

- Interactive (`/craft:build`, `/craft:test`): 3-option dialog — spawn prerequisite / park / descope.
- Autonomous (`/craft:execute` in a worktree): `slice-builder` can't ask — writes
  `.craft/handoff.md` with blocker classification and halts the worktree.

## Unblocking & resume

- Automatic: when a prerequisite slice reaches Phase 9, `/craft:commit` checks for any slice
  `Blocked-on: <this-id>` → clears the block, sets `Status` back to `Blocked-status`, notifies.
- Resume fork: a dedicated `/craft:unblock` offers *resume | re-plan | abort* (the prerequisite
  may have shown the original slice was mis-scoped → deferred descope); it also owns the
  `(pending)` → real-ID back-fill. `/craft:continue` stays a read-only router and just routes a
  `blocked` slice to `/craft:unblock`. *(Resolved in slice-024: a mutating unblock belongs in
  its own command, not in the read-only continue router — symmetric to `/craft:block`.)*
- Visibility: `/craft:prime` + `/craft:status` show blocked slices distinctly (like today's
  handoff marker) + orphan detection ("blocked on slice-NNN, but that was aborted").

## Baseline edit

`skills/senior-developer` Problem-Playbook ("unforeseen dependency → implement it minimally")
gets a clause: *if it exceeds minimal/in-scope → it's a blocker; escalate via `/craft:block`,
don't grow the slice.*

## D2 coupling

The spawn-threshold ("in doubt escalate") is the lever D2 will later make model-tier-aware
(strong models may self-decide more). Build the threshold **configurable** so D2 is a config
change, not a rewrite.

## Proposed slice decomposition (~4–5)

1. `/craft:block` command + `blocked` frontmatter schema + spawn-boundary heuristic.
2. Unblock wiring: auto-resurface in `/craft:commit` + a new `/craft:unblock` (resume fork +
   back-fill); `/craft:continue` routes `blocked` → `/craft:unblock`.
3. Surfacing in `/craft:prime` + `/craft:status` + orphan detection.
4. Autonomous-mode integration: blocker classification in `.craft/handoff.md` / `slice-builder`.
5. Baseline edit (Problem-Playbook) — may fold into slice 1.

## Open questions

- Configurable-threshold format for the spawn boundary (ties to D2 / craft-profile).
- ~~Does `decision`/`access` want a lightweight `/craft:unblock` gesture~~ — **resolved
  (slice-024): yes, a dedicated `/craft:unblock` owns all unblock mutation; `/craft:continue`
  stays read-only and routes to it.**
