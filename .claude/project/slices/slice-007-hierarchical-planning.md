# Slice 007 — Hierarchical Planning (Epic Create-Path)

> Completed: 2026-05-26
> Commits: a63463d..9a86289 (main, no PR)

## What

CRAFT now has a `/craft:epic` command and an `epic-plan.md.template`. In an
onboarded project, a user can create an epic plan file under
`.claude/plans/epic-<NNN>-<slug>.md` that captures a Vision and an initial Slice
Decomposition. Epic ID-allocation uses a dedicated counter `.next-epic-id`,
independent from the slice counter `.next-id`.

## Why

- Bootstraps the hierarchical-planning capability (intent.md Goal #1 / Decision B),
  which in turn enables the remaining four open Active Goals to be sketched at
  epic level without forcing them into a single slice.
- The slice was deliberately the smallest viable cut: create-path only — no
  decompose sub-command, no slice-to-epic linking, no retrofit of `/craft:plan`.
  Each of those is a candidate future slice that fits naturally under the same
  epic theme.
- `/craft:epic` was modeled 1:1 on `/craft:plan` (Pre-Assertions, dialog steps,
  Post-Assertions, output blocks) — keeps the cognitive load on a user who
  already knows the slice workflow near zero.

## Decisions

- **Independent ID-spaces for epics and slices** — two counter files
  (`.claude/plans/.next-id`, `.claude/plans/.next-epic-id`) rather than one
  shared namespace. *Why not* a single shared counter: epic and slice numbering
  are different nouns with different lifecycles, and coupling them would force
  awkward interleaved IDs. *Why not* derive epic IDs from the highest existing
  `epic-*.md` filename: matches the existing slice-counter pattern, avoids a
  filesystem-scan race when concurrent invocations happen.
- **Slice Decomposition lives as a markdown section, not a frontmatter field** —
  `- [ ]` bullets under `## Slice Decomposition`, parallel to the `## Sub-Tasks`
  convention in slice plans. *Why not* a YAML list in frontmatter: would have
  been syntactically fragile, hidden from casual readers, and harder to edit
  in-place when the decomposition shifts mid-epic.

## Commits

- `a63463d` — feat(commands): add /craft:epic for hierarchical planning
- `9a86289` — docs(readme): document /craft:epic in Quickstart

## Follow-ups

- Pre-existing `(D<N>)` dev-refs persist in `commands/{plan,onboard,commit,abort}.md`
  — slice-007 only surfaced the issue by inheriting the pattern (and fixed it in
  the new `commands/epic.md`). A dedicated cleanup slice should sweep the
  remaining four files to bring them in line with the "no dev-refs in shipped
  artifacts" tabu.
