# Slice 006 — Lettered-Choice Prompt Convention

> Completed: 2026-05-21
> Commits: 56a390b (main, no PR)

## What

CRAFT now requires every lettered-choice menu (`[W]/[B]/[U]`, `[K]/[I]/[R]/[D]`,
`[P]/[U]/[D]`, …) to be rendered with its full legend — letter + meaning +
consequence — on every occurrence. A convention in `skills/workflow/SKILL.md` is the
single source of truth; the five lettered menus across `test.md`, `commit.md`, and
`onboard.md` reference it.

## Why

- Came directly from user feedback: the user answers with the bare letter, but seeing
  the legend each time genuinely aids the choice — and the agent had been
  inconsistent about showing it.
- Encoding the rule in the plugin removes it from agent discretion.
- A general convention (not just W/B/U) was chosen deliberately: the same principle
  applies to every lettered menu — one source, several references, rather than
  duplicating the rule.

## Decisions

- (none — implementation followed the Phase-3 plan directly; no new decisions
  surfaced)

## Commits

- `56a390b` — feat(workflow): mandate full legend for lettered-choice prompts

## Follow-ups

(none)
