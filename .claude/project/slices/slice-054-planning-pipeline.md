# Slice 054 — Planning Pipeline

> Completed: 2026-10-01
> Commits: 24594df..9b2a79c (branch only, trunk-based)
> Epic: epic-003 (autopilot mode), entry `planning-pipeline`

## What

An autopilot run can now start on an epic that is not fully planned. Where `/craft:execute --autopilot` used to reject
every unplanned entry — every slice had to be planned by hand first — `slice-planner` agents now plan them, and the human
sees the whole package **once**, at the plan gate: run it (`[Y]`), have named slices revised with a note (`[R]`), or stop
(`[N]`). Nothing is built before the yes.

## Why

- **Planning stays the hard phase; it only moves.** The planners run on the deep-reason tier and answer the three
  universal questions from the epic's Vision, its design record and the code; what they cannot answer they write as
  `NEEDS-HUMAN:` instead of guessing, and the gate shows their judgment calls — the human sees what a plan rests on,
  not only its result.
- **The master judges no content.** On the execute tier it reads helper output only — which entries are unplanned,
  which IDs are free, whether the gate is owed — written down as *Who decides what in an autopilot run*; anything that
  table does not list stops the run.
- **Derived, not stored.** Whether the gate is owed comes from the plans' `Planned-by:` marker and the log's approval
  line, so it returns after `[N]`, Esc or a crash and never after `[Y]`.

## Walk-through

`/craft:execute epic-NNN --autopilot` → a0 checks foreground mode and settles the epic branch → A6 reads the entries;
in an autopilot run an unplanned (`unlinked` / `missing`) entry is work for the next stage, not a rejection → the lock
is taken → **ap**: step 0 asks about active plans no entry links (`ORPHAN`) before any planner runs; the master takes
one ID per unplanned entry from `.next-id` (written once), spawns every `slice-planner` in one message — each follows
`/craft:plan` → Subagent Mode, writes its plan with a verify block and `Planned-by: autopilot`, and returns one
`PLANNED` / `FAILED` line — links each entry through `epic-entry-link.sh`, and checks each plan (frontmatter, sections,
the three answers, the verify block, the `Depends-On` graph) → `plan-gate-state.sh` names the awaiting plans and open
`NEEDS-HUMAN:` lines → the gate shows per slice goal, trigger, effect, test, checks and judgment calls, then how the run
will go. `[Y]` (only when nothing is open or failed) logs the approval line, runs A6 again and continues through step 1c
and a1 into the build; `[R]` re-plans only the named slices and shows the gate again; `[N]` releases the lock and leaves
the plans for hand edits — the next run shows the gate again. A hand-planned epic carries no marker and skips ap.

## Decisions

- **Split: architect review is its own entry** (user) — this slice builds planner fan-out, plan gate, briefing and the
  judgment line; the `plan-architect` agent and its ≤ 2 revision rounds became epic-003's `plan-architect-review`.
  *Why not* both at once: two new agents in one diff, against the epic's "one stop removed per slice". Until it lands,
  the gate shows the planners' package without architect findings.
- **The stage lives in `--autopilot`** (user) — a planning stage inside `/craft:execute`'s Autopilot run, not a separate
  command: one entry point, and the gate and a1's briefing are the one place the human sees how the run will go
  (design §9 Q7). *Why not* a separate command: two steps, two briefings, and the gate would not be the run's one stop.
- **Gate answers `[Y] / [R] / [N]`** (user) — `[R]` re-plans the named slices with a note and shows the gate again; `[N]`
  stops with the plans kept, and a re-run shows the gate again. `[Y]` only when every plan passes its checks, no entry
  failed and no `NEEDS-HUMAN:` is open.
- **The master allocates the IDs** (user) — one `.next-id` write before the fan-out, IDs and paths handed to the
  planners, links written after they return. *Why not* planners allocating: parallel planners would race on `.next-id`.
  Probe P1 showed the foreground spawns run concurrently (planning span 69 s vs. 48.6 s + 57.6 s).
- **Planners follow `/craft:plan`, not a copy of it** — `commands/plan.md` → Subagent Mode delegates to step 7
  (`craft:delegates rule=plan-file to=step-7`, bound by `test-workflow-status-graph.sh`); the agent carries the brief,
  not the rules.
- **An unanswerable question is a gate item, not a guess** — `NEEDS-HUMAN:` lines, counted by `plan-gate-state.sh`
  (plain, bulleted, numbered, checkbox or bold), withhold `[Y]`.
- **The gate is derived, not stored** — `Planned-by:` marker + the `✓ · <epic-id> · plan gate approved: <ids>` line in
  `## Autopilot Log`; hand-planned plans never trigger it. Promoted to `intent.md` (derived state over cleanup).
- **The judgment line** (moved here by slice-053; design §10 resolved) — a table in `commands/execute.md` → *Who
  decides what in an autopilot run*: the master and `slice-builder` decide only what a helper reports; a plan's content
  is `slice-planner`'s, the package the human's at the gate, a review's findings `code-reviewer`'s.
- **ap runs after the lock; A6 lets `unlinked` / `missing` through in autopilot** — planning writes `.next-id`, plans and
  links, so it runs under the execute lock; A6 runs again after `[Y]` over all plans.
- **Orphans are asked about, never judged** (review R1-1) — slice-041 rejects an unlinked entry even when a plan for it
  exists; ap keeps that protection as a question: `plan-gate-state.sh` reports active plans no epic entry links as
  `ORPHAN`, and step 0 asks `[P]` plan anyway / `[N]` stop before any planner runs. *Why not* stop outright (the
  reviewer's first suggestion): an unrelated open slice would stop every run with unplanned entries.
- **Log glyphs** — planning lines `▶`, a failed entry `⛔`, step 0's and the gate's `[N]` `■`, the approval `✓` on the
  epic-ID; P7's "every `✓` names an archived slice" is narrowed to `✓` lines on a slice-ID; the Autopilot Log rules
  moved ahead of ap, and a1 runs before the first `slice-builder` (only its order line after a gate).
- **Intent Non-Goal corrected** — "dialogic phases are not delegated" now reads "outside an autopilot run"; inside one,
  planners (slice-054) and the debug loop (slice-053) run as agents. Promoted to `intent.md`.
- **Verify-block convention** (user) — a verify block names `test-model-enum.sh` only when the slice touches what it
  binds, with `timeout=1200` (it runs 8–12 min; every other harness takes seconds). In `rules.md`.
- **Known limit: the new spawn site is bound by nothing new** — `test-model-enum.sh` checks the spawn-site pointer and
  fallback per file, and `commands/execute.md` already carries both for `slice-builder`; the harness is frozen.
- **Roadmap B21** (user) — T1 showed an autopilot `slice-builder` still stopping at Phase 7
  (`awaiting-refactor-decision`), which no epic-003 entry removes, and that stop left no `⛔` log line.

## Evidence

- **Verify block, Run 1** (`verify-run.sh`, in the plan): 7/7 pass — plan-gate-state, epic-entry-link, status-graph,
  model-enum (121), docs-site, execute-resume, `claude plugin validate`. After the review fixes: plan-gate-state 39/0,
  status-graph 95/0, epic-entry-link 105/0, execute-resume 154/0, docs-site green, model-enum green (121).
- **Mutation checks** of `test-plan-gate-state.sh`: 9 helper mutations (log-section scope, glyph, frontmatter scope,
  NEEDS-HUMAN prefix, exit code, bold, checkbox, other-epic links, pipeline flag) all red; controls green.
- **Probe P1** (headless, Claude Code 2.1.286, Sonnet master, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, fixture with two
  unlinked entries): two plans with `Planned-by: autopilot` and verify blocks, `resolve` → both `STATE=plan`, `.next-id`
  1 → 3, planning / planned / gate-shown log lines, no approval line, `RESULT=gate`; planners on `claude-opus-5-5`,
  master on `claude-sonnet-5-5` (transcripts); both spawns in one message, foreground, concurrent. $1.07, 100 s.
- **Human test T1** (the user, interactive): `[R] slice-002 — --upper soll auch als letztes Argument funktionieren`,
  then `[Y]` — only slice-002 re-planned, the gate shown again, `plan gate approved: slice-001, slice-002` logged, the
  build started; `plan-gate-state.sh` → `RESULT=clear`. Phase 5: `[W]`.
- **Review**: round 1 — 1 Heavy + 8 Light, all Local, fixed in-phase (fix cap waived by the user); round 2 — all nine
  hold, 3 Light Local fixed in-phase; nothing open.

## Commits

- `24594df` — feat(agents): add slice-planner for the autopilot's planning stage
- `a122a9a` — feat(plan): add a Subagent Mode for autopilot planners
- `f869737` — feat(execute): plan unplanned epic entries behind one plan gate
- `6351530` — feat(scripts): derive the plan gate with plan-gate-state.sh
- `ab256e3` — docs: document the planning pipeline and plan gate
- `fc26b1f` — docs(design): record the judgment line as built
- `1cd9283` — docs(rules): add the plan-gate harness and the model-enum verify convention
- `52732dc` — docs(roadmap): add B21, the autopilot's Phase-7 stop
- `9b2a79c` — chore(plans): bump slice counter to 55
