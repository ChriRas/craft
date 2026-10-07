# Slice 069 — b27-a1-briefing-helper

> Completed: 2026-10-07
> Commits: c402c66..cdd3b5f (branch only — epic-004-roadmap-fixes, no PR)

## What

The autopilot's run-start briefing — title, branch, occupied checkout, slice order, the "Stops for you at: …" lines and the Esc / resume line — is now printed by a new helper, `scripts/autopilot-briefing.sh`. `/craft:execute` a1 and the plan gate only relay its stdout unchanged, the way a5 relays `epic-digest.sh`, so the block's content is checked by command instead of left to the master.

## Why

- Slice-063's Phase-5 probe showed the master printing the a1 briefing without its "Stops for you at" lines: the log gate bound that a1 *runs*, not what it prints (roadmap B27, the slice-063 known limit).
- Moving the content into a helper with its own harness binds it.

## Decisions

- **A new helper `scripts/autopilot-briefing.sh` with its own harness**, following the house pattern (every helper has a contract harness written before it). *Why not* a mode of `epic-digest.sh`: it would mix a5's archive reader with a run-start view that has other inputs (git state, the trunk). *Why not* a mode of `autopilot-log.sh`: a log writer would print a view.
- **The slice states come from `execute-resume-state.sh`, never re-derived** — "what step 1c found" is decided in one place (B8); a second plan-Status → action table could drift from s1. On `RESULT=conflict` the helper errors and prints no guessed order.
- **Order rule: a resume slice first, then topological by `Depends-On:`, ties in decomposition order.** s1 states the same tie-break, so the briefing cannot promise an order the run does not keep. Dependencies outside the epic's open slices do not affect the order; A6 validates them.
- **a1 always prints the full block, even right after the plan gate.** The old rule "print only the order line after the gate" is dropped: keeping it would need a mode the master picks or a derivation from the log, a branch for the master to get wrong.
- **The gate relays the same helper output; a failure there is a `⚠` line, and at a1 it is a `⛔` stop.** `run started` stays a separate log call by the master, after the relay.
- **The wording of "Stops for you at" moves verbatim**; rewording it or filling in the profile's actual budget limits is not part of B27. It lives in two places by design: the helper's `STOPS` list (the one definition that prints) and the harness's case table (a bound copy, compared byte for byte). `execute.md` carries none; the three phrases `test-usage-state.sh` pins are kept byte for byte.
- **No headless probe in the verify block; the relay is stated as unshown** — the run uses a frozen plugin runtime, so the run's own a1 is not changed mid-run.
- **`rules.md` is not edited by this slice; its change is a proposal** (human, plan gate `[R]`; builders never edit `rules.md`) — carried into the epic's decisions: the harness count word becomes the number read off the tree at Epic close (24 with this slice; `CLAUDE.md` names twenty-four), and after the `test-autopilot-log.sh` entry: "Plus `bash scripts/test-autopilot-briefing.sh` (slice-069, B27) — the autopilot's run-start briefing: the whole block, its "Stops for you at" lines included, is printed by `autopilot-briefing.sh` and relayed unchanged by `/craft:execute` a1 and the plan gate."
- **No `CHANGELOG.md` line** (human, plan gate `[R]`) — the 2.0.0 cut writes them. **`test-usage-state.sh` joined the verify block** (plan gate revision 2).
- **Pins prove they bite:** a scratch-copy mutation run — 50 mutations, 48 correctly red, 2 equivalent mutants, 3 legitimate edits stay green.
- **Review round 1 (no Heavy, two Light, both fixed in-phase):** R1-1 a plan that is not valid UTF-8 made the helper's Python reader raise with a traceback and no `ERROR=` — it now exits 4 with `plan_unreadable:<path>`, the header table is updated and the harness has a case for it; R1-2 the "--trunk without a value" case repeated another case — it now runs `"$EPIC" --trunk`, and a redundant fixture call was dropped. Those two edits postdate the full verify run (run 1, 10/10); the master re-ran the briefing harness (70/0), status-graph, docs-site, execute-resume-state and autopilot-log on the final tree, all green; the 18-minute `test-model-enum.sh` was not repeated.
- Phase 7 skipped (project rule)
- **Durable capture:** nothing cross-cutting enough for `.claude/project/design/`.

## Commits

- `c402c66` — feat(autopilot): print the run-start briefing by a helper
- `6df3617` — feat(execute): relay the briefing helper's output at a1 and the plan gate
- `cdd3b5f` — docs(roadmap): close B27 and add the briefing harness to CLAUDE.md and the docs site

## Follow-ups

- The relay itself — the master printing the helper's stdout unchanged at a1 and at the plan gate — is shown by no command; the next autopilot run on a runtime that carries this slice shows it (stated unshown in the plan).
- One line of the helper's header error table is longer than the others (cosmetic, noted by the builder).
