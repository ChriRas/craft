# Slice 011 — Plugin version display in /craft:prime and /craft

> Completed: 2026-05-28
> Commits: a0fe01e (main, no PR)

## What

`/craft:prime` and the `/craft` entry skill now surface the running CRAFT plugin version at session start — previously the active release was invisible unless you opened `plugin.json`, which made re-install verification (e.g. 0.3.0 → 0.4.0) guesswork.

## Why

- Triggered by the 0.4.0 re-install, where neither session-start surface reported the version.
- Version display is informational/soft: a missing or malformed `plugin.json` falls back to `v?` / a soft warning and never blocks priming or the `/craft` menu — consistent with the report-never-abort pattern already used for the drift and stack-pack checks.
- Manifest lookup reuses the established `${CLAUDE_PLUGIN_ROOT}` → project-root (dogfood) order, identical to the agent-model resolution in prime Step 4b — no new convention introduced.

## Decisions

- **Soft version display** — version is reported, never enforced; an unreadable manifest degrades gracefully rather than aborting. *Why not* a hard precondition: surfacing the version is a convenience, not a gate — failing the session over a cosmetic line would contradict the established report-never-abort policy.

## Commits

- `a0fe01e` — feat(prime): display active plugin version in /craft:prime and /craft

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review. Each is a candidate for a future slice.

- Pre-existing (not introduced by this slice): `commands/prime.md` Step 6 globs `.claude/craft:plans/*.md` while the rest of the codebase uses `.claude/plans/` — a stray glob typo worth a small fix slice.

## How (Diagram)

(not needed — 2-file slice, no multi-layer interaction)
