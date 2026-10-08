# Slice 076 — click-and-flow-fixes

> Completed: 2026-10-08
> Commits: 638f2aa..0ba20ac (branch only — epic-005-comfort-and-flow, no PR)

## What

Every human-choice site in CRAFT's command prose (`commands/*.md` and `skills/debug/SKILL.md`) now names `AskUserQuestion` itself, in one sentence on a line marked `<!-- craft:choice -->`, so the click happens instead of being left to a pointer nobody follows. Under `Mode: auto`, `/craft:recap` asks `flow-state.sh --mode` first and asks no "Ready for Phase 7/8?". `/craft:commit` omits an attribution line the profile does not enable without a word about it.

## Why

- Human test T2 (2026-10-08) ran a whole phase loop with zero `AskUserQuestion` calls, recap's Phase-7 question and three attribution remarks. The click rule lived only in *Choice prompts*, and the sites only pointed there; no session read the target.
- D40 is amended: the site sentence is the one deliberate copy, bound by the new harness `scripts/test-choice-prompts.sh` (rules.md: a copy that cannot go is bound). The cache-guard stops of an autopilot run (orphan question, plan gate, a5 sign-off) stay typed, behind `<!-- craft:choice typed -->` in the block of their arm marker.

## Decisions

- **Source of the defects** (2026-10-08, from the epic's decision "Human test T2 failed for the clicks") — zero
  `AskUserQuestion` calls, recap's Phase-7 question, and three attribution remarks. The cause: the click rule lives only
  in *Choice prompts*, and the sites only point there; "ask as a click" without the tool's name was not enough even at the
  site (`test.md:97`). Onboard clicked in T1.
- **One marked sentence per site, bound by a harness, not a second copy of the rule** (2026-10-08, planner's judgment) —
  rules.md forbids describing a rule twice and allows a copy only when it cannot go and is bound. The site sentence is
  the case rules.md names for a pointer whose handler cannot live behind the pointer: the agent that needs it is the one
  that never read the target, so it is stated at each reader and bound there. The rule's body (limits, splitting,
  follow-ups, fallback, cache-guard exception) stays in *Choice prompts* only.
- **D40 is amended; D42 is not; no new D-entry** (2026-10-08, planner's judgment):
  - D40's "no command carries a second copy" changes, so it is amended first (sub-task 1).
  - Recap's question in auto flow is an implementation gap of slice-074 against D42 as decided ("human decisions stay
    human"; the recap hand-over is not one of them), so D42 needs no amendment.
  - No D-entry governs `Co-Authored-By` (grep of `brainstorm-decisions.md`). Silence refines commit.md Step 2's existing
    "the only source of an attribution line".
- **Scope is all of `commands/` plus `skills/debug/SKILL.md`, not only the seven phase commands** (2026-10-08, planner's
  judgment) — the reasons:
  - the epic's Vision ("every human decision a click") and the master's brief name review, refactor, pause, continue,
    abort, unblock, release, worktree-clean and onboard;
  - a harness that scans only part of `commands/` would need an allowlist, and an allowlist is the unbound hole this
    slice closes;
  - `/craft:debug` is the phase loop's `[B]` path.

  Not in scope: `brainstorm` / `grill-me` (dialog skills whose questions are open by nature) and `agents/` (subagents cannot
  click). *Cost:* many small, mechanical edits across about twenty files. *Alternative at the gate:* `[R]` to split this
  into a phase-loop slice and a slice for the other commands.
- **The marker and the tool name share one line** (2026-10-08, planner's judgment) — this is the simplest binding that
  needs no paragraph parsing, and the harness asserts it with one grep per marker. The legend scan is a staleness
  detector for the commonest unmarked form, not a proof. Prose stays unchecked (rules.md: markers are the contract), and
  an open question without a legend relies on the declared count.
- **The cache-guard exception is kept by a marker of its own** (2026-10-08, from D40's amendment and the master's brief)
  — `craft:choice typed` must share a block (rule (b)) with an existing `craft:cache-guard arm` marker in `execute.md`, so
  the typed stops cannot quietly turn into clicks, and a click marker cannot creep onto a guard stop.
- **Plan review P1-1 applied: rule (b) is stated precisely** (2026-10-08, autonomous revision round on the
  `plan-architect`'s P1-1; the reading of `commands/execute.md` that day). Three things changed:
  - The `AskUserQuestion` check reads the typed marker's own line only. A negated mention elsewhere in the block is
    allowed. The only `AskUserQuestion` text in `execute.md` is the guard section's Arm bullet (lines 828–841), slice-072's
    R1-1 "never as an `AskUserQuestion` click". It is the rule, not a question. It gets no choice marker, keeps its
    wording, and the harness does not read it. Before this revision, sub-task "Mark the remaining commands' sites" told
    the stops to "keep" a wording that only that bullet has. A builder following it would have rewritten slice-072's
    exception or turned the harness red.
  - "Paragraph" became a **block**, a run of non-blank lines cut at a list item no deeper than its first line. ap's
    steps 0–5 are one run of non-blank lines (lines 650–742). Under the old wording, a typed marker anywhere in ap shared a
    "paragraph" with every arm in ap, so the self-test "typed marker moved away from its arm" could not go red. The
    mutation now moves the marker into the next ap step, and a mutation that puts `AskUserQuestion` on the marker line was
    added.
  - The typed sites are named: the orphan question, the plan gate and the a5 sign-off. The `⛔` stops that arm the guard
    ask no choice and carry no marker. At the orphan question the `[P]` / `[N]` legend (line 654) precedes the arm (line
    658), so the typed marker sits at the top of step 0, inside rule (d)'s window above the legend.
- **Sub-task order: the two small fixes first** (2026-10-08, planner's judgment, prompted by plan review P1-2, a note
  for the gate). Recap's gate and commit's silence need neither the D40 amendment nor the new harness, so they now come
  before the click work. If the human cuts the slice at the gate, (1) recap gate + silent attribution and (2) click
  markers + harness + D40, the first two sub-tasks move out as they are. Whether to split is the human's call. This plan
  does not split.
- **Recap under auto flow asks `flow-state.sh --mode`; doubt means asking** (2026-10-08, from D42 and the `--mode` flag
  in `scripts/flow-state.sh`'s header) — the helper is the one judge of the mode, so recap does not read the profile itself.
  When the helper is in doubt, the question is asked: under the flow's rule "doubt means stop", that is the safe
  direction. Recap's per-paragraph confirm / correct and the diagram offer stay: they are the human's chance to correct
  the recap, which D42 keeps.
- **Attribution: silent at commit; prime and onboard unchanged; the PR body is out of scope** (2026-10-08, planner's
  judgment on the human's T2 wish "at most one mention at onboarding / prime, never at commit") —
  - `/craft:prime` already stays silent on `off`, and the remark the T2 session made there is allowed.
  - Whether Step 6's `gh pr create` body should also refuse a session's "Generated with" line is a separate behavior
    change for consumer projects. It is not in the T2 findings and not in this entry.
- **`allowed-tools` stays as it is** (2026-10-08, verified against code.claude.com/docs/en/slash-commands.md that day) —
  `allowed-tools` only pre-approves tools for the invoking turn and restricts nothing. `AskUserQuestion` was available in
  T2. Listing it would change nothing.
- **The silence sentence gets a verify-block check, not a permanent harness pin** (2026-10-08, planner's judgment) — it
  is prose with no marker contract, and the T2 re-run is its real evidence. The recap gate gets a permanent pin in
  `test-flow-state.sh`, because it is flow wiring that the flow harness already pins site by site.
- **The verify block leaves out `test-model-enum.sh`** (2026-10-08, rules.md rule plus the precedent of slice-074 and
  slice-075) — the slice touches neither `model-defaults.md` nor `agents/`. Its `docs/index.html` edit is the harness
  table, not a `craft:model-enum` line, the same as slice-074 and slice-075 did. Phase 8 and a release still run it in
  full.
- **Depends-On names slice-072, slice-074 and slice-075** (2026-10-08) — this slice corrects their effect. All three have
  landed (archives in `.claude/project/slices/`).
- **Non-goal: the chat-language enforcement gap** (2026-10-08, from the epic's decision line) — it has the same root
  cause (a rule in one file, only pointed to), but it stays a roadmap candidate.
- Phase 7 skipped (project rule)


## Commits

- `638f2aa` — docs(decisions): amend D40 for marked choice sites
- `66cdadf` — fix(recap): hand on through flow-state in auto flow
- `658a52c` — fix(workflow): name AskUserQuestion at every choice site
- `ffcfdc3` — test(choice-prompts): bind the choice sites
- `84f00ca` — docs(choice-prompts): document the harness in the docs page and changelog
- `0ba20ac` — docs(rules): list the choice-prompts harness
