# Slice 001 — Senior-Developer Baseline (D27 Tier 1)

> Completed: 2026-05-20
> Commits: c234b0b (branch main — no PR)

## What

This slice shipped the Senior-Developer baseline as a loadable plugin skill
(`skills/senior-developer/SKILL.md`) and wired `/craft:prime` to load it at session
start. Every CRAFT session now begins with a consistent, stack-agnostic engineering
mindset active — stance, quality hierarchy, workflow gates, test-discipline matrix,
and problem-playbook — confirmed by a `✓ Senior-Developer baseline loaded` line in
the prime status block.

## Why

- Scope kept narrow — Tier 1 only, stack-packs deliberately deferred to later slices —
  to keep the slice small and end-to-end graspable.
- Content extracted, not rewritten: the universal portion was lifted out of the
  existing `real_live_projekt` `developer` skill, separated from the stack-specific
  and project-specific material the old monolithic skill mixed together.
- `disable-model-invocation: true` keeps the baseline from self-activating via
  description matching — it is loaded deliberately by `/craft:prime`.

## Decisions

- **Test and refactor waived for this slice, then promoted to a project rule** — the
  deliverable is freshly authored Markdown scaffolding, not runtime software, so the
  Phase-5 behavioral test and Phase-7 refactor were waived as slice-scoped overrides.
  They were then generalized into a standing rule in `rules.md`: testing minimized to
  technically meaningful checks, Phase 7 dropped from this project's workflow.

## Commits

- `c234b0b` — feat(skills): add Senior-Developer baseline loaded by /craft:prime
