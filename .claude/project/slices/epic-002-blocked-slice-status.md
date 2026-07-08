# Epic 002 — Blocked Slice Status

> Completed: 2026-07-08 (started 2026-07-07)
> Slices: 4/4 landed · trunk-based, no PR

## Vision

A slice in flight can hit an obstacle whose fix lies outside its scope — classically, it can't be
tested because a prerequisite (deployment infrastructure) doesn't exist yet. CRAFT had only
`pause`, `handoff`, and `debug`; none modelled "work cannot proceed until a prerequisite — itself
a unit of work or a decision — is resolved," so the running slice risked silently absorbing a new
direction (scope creep). This epic introduced a **first-class `blocked` slice status** with a
four-type taxonomy (`prerequisite-work` / `external` / `decision` / `access`), a `/craft:block`
command, a flat `Blocked-on` dependency edge, automatic un-blocking when a prerequisite slice
commits, and a `resume | re-plan | abort` fork — surfaced distinctly in `prime`/`status`. A
blocker is now a structured, visible state under human control, never a silently grown slice.

Scope edges held: no nested dependency stacks (flat edges only); the spawn-threshold was built
*configurable* (its model-tier-aware loosening is D2, not here); and the autonomous frontend
landed in the final slice.

## Slices (4/4)

- [slice-023 — Block Command and Schema](./slice-023-block-command-and-schema.md) — `/craft:block` command + `blocked` frontmatter schema + spawn-boundary heuristic, incl. the Problem-Playbook baseline clause.
- [slice-024 — Unblock Wiring](./slice-024-unblock-wiring.md) — auto-resurface in `/craft:commit` + the `resume | re-plan | abort` fork (new `/craft:unblock`) + `(pending)` back-fill; `/craft:continue` routes `blocked` → `/craft:unblock`.
- [slice-025 — Surfacing](./slice-025-surfacing.md) — blocked slices shown distinctly in `/craft:prime` + `/craft:status` + orphan detection.
- [slice-026 — Autonomous Handoff](./slice-026-autonomous-handoff.md) — blocker classification in `.craft/handoff.md` / `slice-builder` for `/craft:execute` (the autonomous frontend).

## Epic Decisions

- **First-class blocked state, full taxonomy** — all four blocker types are first-class
  (`prerequisite-work` / `external` / `decision` / `access`), not just the spawnable one. One
  visible status for every "cannot proceed" situation; only `prerequisite-work` creates new work.
- **Spawn-boundary heuristic (3 criteria)** — it's a blocker when the missing thing (a) would
  have its own test/observable effect, (b) exceeds the slice's declared scope, OR (c) is an
  unsanctioned direction; otherwise build it minimally in-slice. In doubt → escalate.
- **Flat topology** — the prerequisite is a normal top-level slice/epic; the blocked slice carries
  only a `Blocked-on` edge. No nesting/call-stack — avoids dependency stacks and half-done piles.
- **Dedicated `/craft:block` (and `/craft:unblock`) command** — not folded into `/craft:pause`;
  the lifecycles (dependency edge, resume condition, auto-resurface) differ. `/craft:continue`
  stays a read-only router that routes `blocked` → `/craft:unblock`.
- **Configurable spawn-threshold for D2** — the threshold is built configurable so D2
  (model-tier-aware loosening) becomes a config change, not a rewrite.
- **Baseline edit folded into slice-023** — the `skills/senior-developer` Problem-Playbook clause
  shipped with the command-and-schema slice rather than as a separate slice.
- **Two frontends, one state** — the interactive `/craft:block` and the autonomous `slice-builder`
  path (slice-026) write the *same* `blocked` schema; the autonomous path classifies the type but
  never fabricates the spawn/park/descope direction call.
- **Design record `d1-blocked-state.md`** — the converged design was the spec each child slice took.

## Open follow-up

- **D2 — model-tier-aware spawn-threshold loosening** — strong models may self-decide more before
  escalating. The threshold was built configurable precisely so this becomes a config change; a
  focused future slice/epic when D2 is taken up.
