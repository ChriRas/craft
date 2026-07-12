# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | B2 | Fix | slice | Dogfooding is not self-verification: the runtime loads the plugin **cache**, not the working tree — no slice touching `commands/` can be verified end-to-end in the session that writes it |
| 2 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 3 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |

## Notes per item

**B2 — Dogfooding is not self-verification.** Found in Phase 6 of slice-031, by noticing that the
`/craft:recap` text driving the session still asked "Ready for Phase 7?" while the working tree
carried the fixed branch. Claude Code executes the commands installed under
`~/.claude/plugins/cache/craft/craft/<version>/`, **not** the repo's `commands/`. Consequences:
(a) no slice touching `commands/` can be verified end-to-end in the session that writes it — the
fix only goes live after `/craft:upgrade` or a reinstall, so Phase 5 for such a slice can
demonstrate the *harness* but never the runtime behavior, and must say so; (b) worse, a CRAFT
session can silently run **older command logic than the repo shows**, which is a trap for any
dogfooding review — the reviewer reads the fixed file while the runtime obeys the stale one.
Candidate fix: have `/craft:prime` compare the cache's `plugin.json` version — ideally a content
hash — against the dev repo when the two are the same project, and warn on divergence; and state
the constraint in `CLAUDE.md` so the next agent does not re-learn it the hard way.

**F3 — Cleanup skill.** Epic. Novel core = fidelity check: strip/condense comments → fresh-context review must reconstruct the same information breadth (fixed "why does this exist / what decision does this encode" battery, diffed before/after) → write back on loss. Scope param repo/epic/slice; uses archive context; interactive; may drop now-irrelevant historical decisions.

**D2 — Model tiers.** Bind roles to capability tiers, not model names; project maps tiers → models (Fable 5 becomes config, not code). Serves token-efficiency (expensive reasoning only at hard phases). Couples to D1's spawn-threshold (make it tier-configurable). Caveats: verify Fable 5's real behavior before rewriting policy; "open to other coding tools" (Cursor etc.) is a separate, larger track — likely non-goal for now.
