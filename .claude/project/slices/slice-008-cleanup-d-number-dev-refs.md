# Slice 008 — Cleanup `(D<N>)` Dev-Refs in commands/

> Completed: 2026-05-26
> Commits: d8aa629 (main, no PR)

## What

Removed all `(D<N>)` parenthetical dev-references from the four shipped command
files (`commands/{plan,onboard,commit,abort}.md`), bringing them in line with the
"no dev-refs in shipped artifacts" tabu. Slice scope was extended in-phase
(user-confirmed) to also clean a non-parenthesized sister-violation
(`Decision D20` + `plugin-architecture.md`) in `onboard.md:15`.

## Why

- The follow-up was opened by slice-007's Phase 8 review: that slice fixed the
  pattern in its newly authored `commands/epic.md`, but the review surfaced
  that four pre-existing command files inherited the same violation.
- End-users installing the plugin from the marketplace do not receive
  `brainstorm-decisions.md` or `plugin-architecture.md` — the D-references
  were dangling pointers for them.
- The fix preserves substantive content (Pre/Post-Assertion pattern, knowledge
  model, migration scheme references) by re-anchoring to artifacts that **are**
  shipped — `skills/workflow/SKILL.md` for the pattern, the procedure body of
  `onboard.md` itself for the migration classification scheme.

## Decisions

- **Scope extension in-phase for identical-character sister-violations** —
  during Phase 4 the bare `Decision D20` + `plugin-architecture.md` reference
  in `onboard.md:15` surfaced. The slice's grep regex `\(D[0-9]+\)` did not
  match it, so it was strictly out-of-scope. User confirmed extending scope
  to fix it in-slice rather than spinning a separate slice. *Why not* a
  separate slice: cross-slice consistency on the same tabu outweighs strict
  scope hygiene when the extra change is one-line, same-tabu, and
  human-confirmed. *Why not* promote this to a rule: it was a one-time
  judgment call, not yet a recurring pattern — kept here for the next slice
  that hits the same trade-off to reference.

## Commits

- `d8aa629` — chore(commands): remove (D<N>) dev-refs from shipped commands

## Follow-ups

(none — Phase 8 review returned 0 findings)
