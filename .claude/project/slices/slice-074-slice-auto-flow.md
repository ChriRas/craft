# Slice 074 — slice-auto-flow

> Completed: 2026-10-08
> Commits: f88823a..4c1d0dd (branch only — epic-005-comfort-and-flow, no PR)

## What

An interactive slice now moves from phase to phase by itself. With the new profile block `## Slice Flow` -> `Mode: auto`
(the plugin default; `manual` in the `careful` preset, asked by `/craft:onboard`, reported as `flow=<mode>` by
`/craft:prime`), each of `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor` and `/craft:review` ends by
asking the new helper `scripts/flow-state.sh` what comes next and starting that phase itself, up to and including
`/craft:commit`; `/craft:plan` ends with a "Build now / Later" click. `manual` keeps today's one-command-per-phase flow.

## Why

- Every phase already ended by naming the next command, yet the human typed it each time, although what needs the human
  are the decisions inside the phases.
- D42 makes the typed trigger the exception: the helper (mode, plan status, `--from`) is the only judge of "go on or
  stop", doubt means stop, and the human decisions stay human as clicks (D40), with the flow continuing right after the
  answer. No Stop hook (it could fight a legitimate stop); the pause request is slice-075, for which `STOP=` stays open.

## Decisions

- **D42 banked** (2026-10-08) — auto flow default, one helper, no Stop hook, pause by one word; see `brainstorm-decisions.md`.
- **Helper + rule, no Stop hook** (2026-10-08, human choice) — a Stop hook could fight legitimate stops; revisit on evidence.
- **`/craft:plan` asks "build now / later"** (2026-10-08, human choice over "start build" and "auto from build only").
- **Presets** (2026-10-08, human choice) — `careful` = manual, `balanced` / `autonomous` = auto; plugin default auto.
- **The status → command map is bound, not copied freely** (2026-10-08) — `/craft:continue`'s table and the graph in
  `skills/workflow/SKILL.md` already describe it; the helper's copy is bound to the graph by the status-graph harness
  (rules.md tabu: an unbound copy is the violation).
- **Doubt means stop** (2026-10-08) — unlike the handoff marker (doubt = live), a wrong automatic phase start costs more
  than an unnecessary halt.
- **Split from `pause-watch`** (2026-10-08, human choice) — this slice leaves the pause request to slice-075 but keeps
  `STOP=` open for it.
- **Scope** — `/craft:execute`, the autopilot and every Subagent Mode keep their own orchestration; auto flow is for
  interactive slices only. Depends on slice-072 because its stops are clicks.
- Phase 7 skipped (project rule)
- **Review round 1 → loop-back to Phase 4** (2026-10-08) — 1 Heavy + needs-rethinking finding (R1-1, `--from` anchored to the status before the command's own Pre-flight write) routed to Phase 4; route chosen by the autopilot rule (one autonomous loop-back per finding, slice-052).

## Commits

- `f88823a` — feat(flow): add flow-state.sh, the auto-flow verdict helper
- `29ebcfe` — feat(profile): add the Slice Flow setting, auto by default
- `b3163cd` — feat(workflow): chain the phases in auto flow
- `8edf42f` — feat(prime): report the flow mode; onboard asks it
- `c7a0df2` — docs(flow): document auto flow in the docs page and changelog
- `4c1d0dd` — docs(rules): list the flow-state harness

## Follow-ups

- R1-6 Light · Rethink · the headless exclusion is left to the agent's judgment although nothing tells helper or agent that the session is headless (a claude -p probe of one phase command may run on into later phases)
- R2-4 Light · Rethink · the --from table copies each command's Pre-flight status write and nothing binds it (test.md Pre-flight write has no craft:writes marker)
