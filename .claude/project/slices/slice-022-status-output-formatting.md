# Slice 022 — Improve /craft:status output formatting

> Completed: 2026-07-07
> Commits: 276bb77..967cd51 (branch-only, no PR — this repo runs `direct` merge)

## What

`/craft:status` now renders a scannable overview instead of a flat slice list: slices
split into `Active` and `Stale` groups with count headers, each line carrying a named phase
(`Phase 5 (Test)`), a 5-cell progress bar (`▓▓░░░ 2/5`), and a `⊹ handoff` flag when a slice
has a pending handoff. The change is confined to the command's Procedure and Output Format
sections; `/craft:prime`'s slice section is untouched.

## Why

- **Read at a glance over parse-a-wall** — the old flat list forced the reader to decode bare
  phase numbers and a raw `Y/Z` count; grouping, named phases, and bars make open work legible
  in one look.
- **Show the live phase, not dead metadata** — surfaced during Phase-5 testing: the `Phase:`
  frontmatter number is set once at plan time and advanced by no phase command, so it reads
  stale (the slice literally showed `Phase 3` while being tested). Deriving the label from the
  already-maintained `Status` field fixes the display without touching seven other commands.

## Decisions

- **Command-aligned phase names** — labels use the short names the user types (Build, Test,
  Review…), not the workflow's formal headers ("Implementation", "Testing & UX Feedback").
  *Why not* the SKILL headers: they don't map to the commands a reader invokes. Source of
  truth for phase order: the `### Phase N —` headers in `skills/workflow/SKILL.md`.
- **Phase label derived from `Status`, not the `Phase:` number** — the number is dead metadata
  no command maintains; `Status` tracks the live phase. Primary map is `Status → phase` (the 8
  workflow statuses, incl. `review`→Recap), verified against the phase commands' `Status:`
  writes and `commands/continue.md`; fallback to the `Phase:` number → name map only for
  `paused` / `awaiting-*` / unrecognized states, which append a `· <status>` suffix so a
  fallback label is not mistaken for a live phase. *Why not* fix the `Phase:` staleness at
  source: advancing the number in every phase command is a separate, larger change — out of
  scope for a formatting slice.
- **0-sub-task slices render an empty bar without divide-by-zero** — a `total == 0` guard
  short-circuits the fraction; the full 5-cell bar is reserved for `done == total` (a
  `min(4, …)` cap), so a full bar always means complete.

## Commits

- `276bb77` — feat(status): group overview with phase names, progress bars, handoff markers
- `967cd51` — chore(plans): bump slice counter to 23

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review.

- None — all five Phase-8 Review findings were Light · Local-edit and fixed in-phase.

## How (Diagram)

Not applicable — single-file slice, below the complexity threshold.
