# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | B1 | Bug | slice | Epic counter resets to 1 once old epics live only as archived slices — persist a monotonic epic counter like the slice counter |
| 2 | B2 | Bug/Default | slice | `Co-Authored-By` trailer off by default; `/craft:onboard` asks (recommend: no) |
| 3 | F2 | Feature | slice | Auto-prime fallback for context-dependent commands in an unprimed session + tool-availability guard |
| 4 | D1 | Design→Epic | epic | First-class `blocked` slice status for blockers needing a new direction — **designed → design/d1-blocked-state.md** |
| 5 | F1 | Feature | slice/epic | Read-only context sources: a `Research/` dump folder + declared connected projects — readable, never writable |
| 6 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 7 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |

## Notes per item

**B1 — Epic counter.** A slice counter is already persisted (`chore(plans): bump slice counter`); the epic counter derives from visible epics and resets when they archive. Fix = persist it the same way. Back-fill so the next epic ≥ 002.

**B2 — Co-Authored-By default.** Target is *consumer-project* behavior (this repo already forbids the trailer in `rules.md`). `/craft:onboard` asks once, default off, recommend off. Consumed by `/craft:commit`.

**F2 — Auto-prime + tool-guard.** Classify commands: context-free (`onboard`, `prime`, `upgrade`) vs. context-dependent. A context-dependent command in an unprimed session auto-runs prime first (with notice). BUT gate on tools: context-mode (etc.) missing → loud `⚠️`, repair hint (`/ctx-doctor`, `/ctx-upgrade`, re-install), ask before proceeding. Needs a "primed" sentinel (marker file) — chat context isn't inspectable.

**F1 — Read-only context sources.** Unifies "Research folder" + "connected projects": read-only sources declared at onboarding (or a `Research/` folder auto-detected). Agent may read/extract/copy-from, never write. Teeth = a PreToolUse hook blocking Write/Edit on declared paths; connected-project paths go into `additionalDirectories` read-only.

**F3 — Cleanup skill.** Epic. Novel core = fidelity check: strip/condense comments → fresh-context review must reconstruct the same information breadth (fixed "why does this exist / what decision does this encode" battery, diffed before/after) → write back on loss. Scope param repo/epic/slice; uses archive context; interactive; may drop now-irrelevant historical decisions.

**D2 — Model tiers.** Bind roles to capability tiers, not model names; project maps tiers → models (Fable 5 becomes config, not code). Serves token-efficiency (expensive reasoning only at hard phases). Couples to D1's spawn-threshold (make it tier-configurable). Caveats: verify Fable 5's real behavior before rewriting policy; "open to other coding tools" (Cursor etc.) is a separate, larger track — likely non-goal for now.
