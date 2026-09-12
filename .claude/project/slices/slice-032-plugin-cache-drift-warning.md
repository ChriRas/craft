# Slice 032 — Plugin cache drift warning

> Completed: 2026-09-13
> Commits: 2d01055..6b5c9af (branch only — direct-to-main)
> Review rounds: **2** (two-pass round 1 per D33, fresh re-review of the fix delta)
> Roadmap: B2 — "Dogfooding is not self-verification"

## What

When CRAFT is primed inside its own source repo, `/craft:prime` now states plainly whether the
session executes the working tree or an older installed copy of the plugin — and, when they
diverge, names the differing files and how to run the current state. Before, a dogfooding session
silently ran old command logic while the new file sat in front of the reader.

`scripts/check-plugin-cache-drift.sh` compares the runtime surface by content;
`/craft:prime` step 5c renders its result as one status line; `scripts/test-plugin-cache-drift.sh`
(20 cases) guards it. The slice also produced D33: this repo's Phase 5 runs on automated evidence.

## Why

- **The version cannot reveal the drift.** Claude Code copies marketplace plugins into
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` and runs that copy; the directory stays
  `1.4.0` while the repo changes. Only a content comparison names what actually runs stale.
- **A remedy must be verified before it is recommended.** `claude --plugin-dir <repo>` was probed
  headlessly and replaces the installed `craft@craft` cleanly; the docs showed that a push without a
  version bump refreshes nothing, because Claude Code skips an update whose version it already has.
- **A reported drift that is wrong is worse than none.** Every listing or read failure ends in
  `STATUS=unknown` — an incomplete listing never passes for a real diff, and projects that are not
  CRAFT's source are never nagged.

## Decisions

- **Content comparison, not version or commit SHA** — needs no internal Claude Code schema
  (`installed_plugins.json`) and catches uncommitted edits. *Why not the SHA:* undocumented file,
  blind to working-tree changes.
- **Runtime surface is an allowlist, pre-seeded with future component names** (`workflows/`,
  `monitors/`, `.mcp.json`, …). *Why not a denylist:* every docs commit would raise a false alarm;
  absent-on-both-sides costs nothing.
- **`--plugin-dir` verified (Claude Code 2.1.270)** — headless `stream-json` init event: without the
  flag one `craft` from the cache (`craft@craft`), with it exactly one `craft` from the repo
  (`craft@inline`), 31 commands, no duplicates. Named as the primary remedy.
- **Probe hygiene** — nested `claude` probes run from a scratch copy: the SessionStart hook deletes
  `.claude/plans/.primed` in whatever project a session starts in, and would un-prime the running one.
- **Link-mode dev marketplace not adopted** — a `command` source reloads on changed content, but in
  link mode the plugin is not loaded at all in a session started inside the printed directory (this
  repo), and link mode is unsupported on Windows.
- **Phase 5 on automated evidence (D33)** — harness 11→20/20, helper vs. real cache, static check of
  the installed `prime.md` (no step 5c), two headless `/craft:prime` probes ($0.53 / $0.64) showing
  `✓ … (loaded in place)` and `⚠ … 1 file(s) differ`; the human answered `[W]` on the report. The
  probes also caught a real `rules.md` drift the session's own opening prime had missed.
- **Phase-5 `[U]` iteration** — the first remedy text ("push, then /craft:upgrade") was wrong and the
  line claimed "installed copy" even under `--plugin-dir`; both corrected before `[W]`.
- All 17 plan decisions were kept `[K]`: everything that belonged in `intent.md` / `rules.md` /
  `CLAUDE.md` was written there in-slice with user confirmation (D33, the Phase-5 rule, the four-harness
  list, the dev-loop notes).

## Commits

- `2d01055` — chore(plans): bump slice counter to 33
- `fe21614` — feat(prime): report plugin runtime drift from the working tree
- `6b5c9af` — docs: bank D33 evidence-based Phase 5 and document the runtime drift check

## Follow-ups

- (none from review — every finding was a local edit and was fixed in-phase)

## Known limits (disclosed, not closed)

- **The new prime line is invisible until a release.** The installed 1.4.0 has no step 5c; a normal
  session shows it only after a version-bumped release — or in a `--plugin-dir` session.
- **Plan `Phase:` vs. prime step 6** — `Phase:` is defined as a plan-time stamp (`agents/slice-builder.md`,
  `commands/block.md`), yet prime step 6 reads it as the current phase. Pre-existing, outside this slice.
- **`/craft:test` and `skills/workflow/SKILL.md` still say "Phase 5 cannot be skipped"** — deliberately
  unchanged (D33); the general evidence-based Phase 5 belongs to the autopilot epic (F6).
- **Harness portability** — the drift harness runs under bash 3.2 and without GNU `timeout`; other CRAFT
  scripts need a current bash (roadmap F4).
- **Candidate** — the headless probe setup (scratch copy + `claude -p "/craft:prime" --plugin-dir`)
  could become a reusable script for evidence reports (~$0.60 per run); not built here.

## Phase-8 Review Record

- **Round 1** — pass 1 rubric review + pass 2 scenario walk-through (12 scenarios, empirical fixtures):
  2 Heavy · Local (H1 helper looped forever on a trailing value-less flag — reachable from prime via an
  unquoted empty `${CLAUDE_PLUGIN_ROOT}`; H2 the Phase-5 rule contradicted D32/intent and was unbanked →
  D33), 9 Light · Local (tool checks before manifest, unhandled exit paths, output/guidance mix, list
  format, over-strong runtime claims, git failure as false diff, listing asymmetry, present-tense docs
  claim, stale rules.md harness list), 1 recorded for Phase 9 (commit split), 1 not applied (plan
  `Phase:`). Fix cap (5) waived by the user on condition of a fresh re-review.
- **Round 2** — fresh re-review of the fix delta: all checkable fixes verified by sabotaged helpers;
  4 Light · Local (cache-side read failures, newline names, imprecise decision references, prime 5c
  template/fallback) — all fixed; no third round (Light-only, deterministic tests).
