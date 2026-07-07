# Epic 002 — Blocked Slice Status

> Status: planning | decomposing | active | paused | completed
> Epic-ID: epic-002
> Epic-Slug: blocked-slice-status
> Started: 2026-07-07
> Phase: 3
> plugin-version: 1.3.0
> Handoff active: no

## Vision

A slice in flight can hit an obstacle whose fix lies outside its scope — classically, it
can't be tested because a prerequisite (deployment infrastructure) doesn't exist yet. CRAFT
today has only `pause`, `handoff`, and `debug`; none model "work cannot proceed until a
prerequisite — itself a unit of work or a decision — is resolved," so the running slice
risks silently absorbing a new direction (scope creep). This epic introduces a **first-class
`blocked` slice status** with a four-type taxonomy (`prerequisite-work` / `external` /
`decision` / `access`), a `/craft:block` command, a flat `Blocked-on` dependency edge,
automatic un-blocking when a prerequisite slice commits, and a `resume | re-plan | abort`
fork — surfaced distinctly in `prime`/`status`. When done, a blocker is a structured,
visible state under human control, never a silently grown slice.

Scope edges: no nested dependency stacks (flat edges only); the spawn-threshold is made
*configurable* but its model-tier-aware loosening is **D2, not here**; a dedicated
`/craft:unblock` command stays out unless the resume-fork proves insufficient.

## Slice Decomposition

> Initial decomposition into vertical slices. Each entry is a candidate `/craft:plan`
> invocation later; treat the list as a roadmap, not a contract. Update as slices land.

- [x] block-command-and-schema — `/craft:block` command + `blocked` frontmatter schema + spawn-boundary heuristic (incl. the Problem-Playbook baseline clause) — landed slice-023
- [x] unblock-wiring — auto-resurface in `/craft:commit` + `resume | re-plan | abort` fork (via new `/craft:unblock`) + `(pending)` back-fill — landed slice-024
- [ ] surfacing — blocked slices in `/craft:prime` + `/craft:status` + orphan detection
- [ ] autonomous-handoff — blocker classification in `.craft/handoff.md` / `slice-builder` for `/craft:execute`

## Review Checkpoints

> Optional. Controls where `/craft:execute` pauses for human review during the
> autonomous run. Default: end-of-epic only.
>
> Each entry takes the form `- after slice-NNN` and pauses after that slice's
> Phase-7 self-review completes, before merging into the epic-branch. Use
> sparingly — per-slice stops produce review fatigue.

- (none — review at end-of-epic only)

## Decisions Made During This Epic

> Architectural / product decisions that surface during epic shaping or while child
> slices execute. Each entry is walked with the `[K]/[I]/[R]/[D]` promotion dialog
> when the epic closes.

- **Design record** — the full converged design lives in
  [`.claude/project/design/d1-blocked-state.md`](../../project/design/d1-blocked-state.md);
  child slices take it as their spec.
- **Full taxonomy** — all four blocker types are first-class (`prerequisite-work` /
  `external` / `decision` / `access`), not just the spawnable one. One visible status for
  every "cannot proceed" situation.
- **Spawn-boundary heuristic (3 criteria)** — it's a blocker when the missing thing (a)
  would have its own test/observable effect, (b) exceeds the slice's declared scope, OR (c)
  is an unsanctioned direction; otherwise build it minimally in-slice; in doubt → escalate.
- **Flat topology** — the prerequisite is a normal top-level slice/epic; the blocked slice
  carries only a `Blocked-on` edge. No nesting/call-stack.
- **Dedicated `/craft:block` command** — not folded into `/craft:pause`; the lifecycles
  (dependency edge, resume condition, auto-resurface) differ.
- **Configurable threshold for D2** — the spawn-boundary threshold is built configurable so
  D2 (model-tier-aware loosening) becomes a config change, not a rewrite.
- **Baseline edit folded into slice 1** — the `skills/senior-developer` Problem-Playbook
  clause ships with the command-and-schema slice rather than as a separate 5th slice.

## Recap Draft

> Filled when the epic closes. Becomes the basis for the epic archive entry.

(not yet recorded)

## Handoff

> Filled by `/craft:handoff` when context-poisoned. Read by the next session's
> `/craft:prime`.

(none)

## Pause Note

> Filled by `/craft:pause` when work pauses mid-phase.

(none)
