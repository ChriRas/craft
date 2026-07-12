# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | B1 | Fix | slice | Phase-7-dropped projects can never reach `/craft:review`'s Phase-8 mode — `/craft:recap` only advances to `refactoring`, and only `/craft:refactor` sets `reviewing` |
| 2 | F1 | Feature | slice/epic | Read-only context sources: a `Research/` dump folder + declared connected projects — readable, never writable |
| 3 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 4 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |

## Notes per item

**B1 — Phase-8 unreachable when Phase 7 is dropped.** Found by dogfooding slice-030. A project
whose `rules.md` drops Phase 7 (as CRAFT's own does) can never reach `/craft:review`'s Phase-8
mode: `/craft:test` sets `Status: review` on `[W]`, `/craft:recap` only ever advances to
`refactoring`, and `reviewing` is set *exclusively* by `/craft:refactor`. With no Phase 7,
nothing performs that promotion, so `/craft:review` sees `review` and falls into **advisory
mode** — findings only, no in-phase fixes, no `Status:` change, Commit never gated. Worked around
in slice-030 by setting `Status: reviewing` by hand. Candidate fix: `/craft:recap` advances to
`reviewing` (not `refactoring`) when Phase 7 is dropped. Check the same gap for other
project-configurable phase skips.

**F1 — Read-only context sources.** Unifies "Research folder" + "connected projects": read-only sources declared at onboarding (or a `Research/` folder auto-detected). Agent may read/extract/copy-from, never write. Teeth = a PreToolUse hook blocking Write/Edit on declared paths; connected-project paths go into `additionalDirectories` read-only.

**F3 — Cleanup skill.** Epic. Novel core = fidelity check: strip/condense comments → fresh-context review must reconstruct the same information breadth (fixed "why does this exist / what decision does this encode" battery, diffed before/after) → write back on loss. Scope param repo/epic/slice; uses archive context; interactive; may drop now-irrelevant historical decisions.

**D2 — Model tiers.** Bind roles to capability tiers, not model names; project maps tiers → models (Fable 5 becomes config, not code). Serves token-efficiency (expensive reasoning only at hard phases). Couples to D1's spawn-threshold (make it tier-configurable). Caveats: verify Fable 5's real behavior before rewriting policy; "open to other coding tools" (Cursor etc.) is a separate, larger track — likely non-goal for now.
