# Slice 077 — abort-and-pause-fixes

> Completed: 2026-10-08
> Commits: f346bb8..54723ae (branch only — epic-005-comfort-and-flow, no PR)

## What

`/craft:abort` now asks each of its questions in an `AskUserQuestion` call of its own (the next one only after the answer, a No ends the abort) and, without an argument, offers the active slices as a click. A pause word (`pause`, `pausieren`, `/craft:pause`) now works under `Mode: manual` as under `Mode: auto`: the agent records the request first, finishes the running step, writes the handoff and pauses the slice — also at `/craft:debug`'s attempt countdown, where any other input still halts only the loop. The hook's limit is written down (it does not fire for a message delivered mid-turn), and `/craft:pause` writes the handoff first for a slice in flight and settles a pending request at every exit.

## Why

- The 2026-10-08 human re-test found T4 (abort's warning and both confirmations came in one call, so the later ones were answered before the first could end the abort), T3 (the hook did not fire for a queued `pause`, and the agent paused without `request` and without the handoff) and T5 (under `manual` a pause word stopped the agent mid-sub-task). Decision `[G]` makes the word behave the same in both modes; the sentence the agent needs is stated at each site that can be running (the same cause and remedy as D40's slice-076 amendment) and bound by a harness. D40 and D42 are amended; no new D-entry.

## Decisions

- **`/craft:pause` stays a pause word; its turn-end effect is documented** (2026-10-08, human choice at the plan gate,
  `[R]`: "/craft:pause bleibt Pause-Wort, Wirkung erst am Turn-Ende dokumentieren"). This answers the plan's former
  `NEEDS-HUMAN:` question (keep it, or count only `pause` / `pausieren`) with the keep branch.
  - *The basis:* the interactive-mode docs, checked 2026-10-08 (*When Claude Code sends what you queued*: "Commands …
    Claude Code holds them until the turn ends"). Under auto flow, which chains phases inside one turn, a queued
    `/craft:pause` therefore cannot stop the flow mid-turn. The rule and the docs now say so.
  - *The edge case the question named, re-checked:* the question's premise was that a `/craft:pause` held past the
    commit makes the hook record a request that nothing consumes. That does not hold for the single slice. The hook
    records only with a slice in flight (WHAT condition 4), and after `/craft:commit` Step 7 the plan is closed. Rule 1
    keeps the agent to the same scope. `/craft:commit` consumes a pending request, and so does any `STOP=` (Auto flow
    step 5).
  - *What is still missing:* another slice of the checkout in flight. The hook then records for the prompt, and
    `/craft:pause` stops without Step 3 when it pauses nothing. That happens at four exits: "If none", a pick that
    names no slice, and, since plan review P6-1, the Error Handling rows for a `committed` and a `blocked` slice. The
    request would then pause that other slice at its next boundary. The plan closes all four exits in
    `commands/pause.md`, with harness pins.
  - *The handoff:* superseded by the decision below (revision round 6). The planner's earlier judgment ("no handoff
    in `commands/pause.md`", with an `[R]` alternative) is withdrawn; it is kept here as history.
- **`/craft:pause` writes the handoff when it pauses a slice in flight** (2026-10-08, human decision at the plan gate,
  second `[R]`: "P6-2: /craft:pause schreibt die Übergabe"). It answers plan review P6-2.
  - *The basis:* decision `[G]` (a pause word behaves the same everywhere: finish the step, handoff, pause note,
    pause) and the landed rule 3 of *The pause request*. Rule 3 already runs the handoff for a pause word that
    arrives while no step runs. Without this change, `pause` sent as a prompt would write a handoff while
    `/craft:pause` sent the same way would not: T3's defect, kept for one word.
  - *How it is done (planner's judgment, corrected in revision round 7):* one Pre-flight bullet in
    `commands/pause.md` that points at rule 3 and does not restate it. The earlier "the rule itself needs no edit" was
    wrong (P7-1): rule 3 gets one pointer clause for a `/craft:pause` sent as a prompt of its own (decision below).
    The six marked pause-word sentences keep naming `/craft:handoff` and then `/craft:pause`.
  - *The guard (planner's judgment):* `pause.md` skips its own handoff when the pause action called it. Without the
    guard the pause action would write the handoff twice, and the second `/craft:handoff` would ask "overwrite,
    append or cancel" (its Error Handling row) in the middle of a pause. *The alternative, rejected:* let the pause
    action call only `/craft:pause`. It would rewrite rule 3, the six marked sentences and their pins, which is more
    review surface for the same effect.
  - *Scope (planner's judgment, corrected in revision round 7):* "in flight" is rule 1's status list, in either flow
    mode (`[G]`). A slice at `planning` or already `paused` gets no handoff, and only there does Step 1 still ask for
    the note. The earlier "Step 1 still asks for the note when the human typed the command; only the pause action
    composes it" is withdrawn (P7-1). A `/craft:pause` the human sends as a prompt of its own on a slice in flight is
    the pause action's run, so its note is composed, not asked for (decision below). The frontmatter `description` of
    `pause.md` stays as it is, because it is still true. The docs command-reference row and the CHANGELOG entry name
    the handoff.
- **A `/craft:pause` sent as a prompt of its own is the pause action's run** (2026-10-08, human decision at the plan
  gate, third `[R]`: "P7-1 übernehmen", adopting the resolution the master proposed at the gate). It answers plan
  review P7-1.
  - *The defect it closes:* for that one prompt, rule and command gave two procedures, and nothing told the agent
    which call it was in. Rule 3's last sentence says a pause word that arrives while no step runs is recorded and the
    pause action runs at once (`/craft:handoff`, then `/craft:pause`, the note composed), and rule 1's word list names
    `/craft:pause`. The plan said Step 1 asks when the human typed the command, and that the rule needs no edit.
    Following rule 3 and then pause.md would write the handoff twice. The second `/craft:handoff` would ask "overwrite,
    append or cancel" mid-pause, and the planned pin did not catch it.
  - *The answer:* sent idle, or queued and delivered at turn end, `/craft:pause` **is** the pause action's run. It
    writes the handoff once, in its Pre-flight bullet; no separate `/craft:handoff` runs before it. It composes the
    pause note without asking, like `pause`. The agent tells the calls apart by what it ran itself: called by the
    pause action, it ran `/craft:handoff` just before; sent as a prompt, nothing ran.
  - *The basis:* the landed rule 3 (`skills/workflow/SKILL.md`, *The pause request*, "the pause note composed by you
    and shown, not asked for"; "A pause word that reaches you while no step is running … run the pause action at
    once") and decision `[G]` (a pause word behaves the same everywhere).
  - *Stated once, pointed at (planner's judgment on where):* pause.md's Pre-flight bullet says what the run does, and
    rule 3 only points at it with one clause (rules.md: a rule is never described twice). The definition sits in
    pause.md because that is the text the agent has in front of it when the human sends `/craft:pause`. Claude Code
    expands the command as the prompt, and the rule may not be loaded. This follows the slice's own remedy for T3 (the
    action stated at the site) and rules.md's *A pointer's own unreachability handler cannot live behind that
    pointer*. The rule keeps the clause because an agent working from rule 3 is the one that would run
    `/craft:handoff` first. Step 1's existing no-ask sentence widens and points at the bullet. *The alternative,
    rejected:* the definition in rule 3, with pause.md pointing. An agent that only has pause.md in front of it would
    then not know to compose the note.
  - *Bound:* by fixed phrases on one line each, with three mutation fixtures (sub-task *`/craft:pause` stays a pause
    word*). The binding holds the text, not the behavior; re-test item 6 shows the behavior.
  - No `NEEDS-HUMAN:` line: the reading agrees with rule 3 and `[G]`, and the human adopted it.
- **Source of the defects** (2026-10-08, from the epic's decision "Re-test after slice-076") — the source has three
  parts:
  - T4: Step 3's warning and Step 5's two confirmations came in one `AskUserQuestion` call.
  - T3: the hook did not fire for the queued `pause`. The agent paused without `request` and without `/craft:handoff`.
  - T5: under manual flow, `pause` stopped the agent at once, mid-sub-task.

  The human's decision `[G]`: a pause word behaves the same in both modes.
- **Revision round 3** (2026-10-08, plan review P3-1 and P3-2, applied; the open `/craft:pause` question stays for
  the gate).
  - *P3-1:* debug's attempt countdown joins the pause-word sites. Changed: Goal, Vertical Slice Definition, Trigger 4,
    Effect, re-test item 5, the pause-watch check, the D42 amendment, the rule's Rule 1, the debug sub-task, the site
    set (six), and the corrected sites decision.
  - *P3-2:* the drop branch now lists every copy, with a grep done-check. The marked sentences name no words.
- **Revision round 4** (2026-10-08, plan review P4-1, applied; the open `/craft:pause` question stays for the gate).
  - *The problem:* the drop branch's done-check grepped `pausieren` and asked for no `/craft:pause` on the hit lines.
    It could not pass, because `docs/index.html:1289` (the command reference's `/craft:pause` row, "Slice pausieren")
    matches. That row stays after the drop. The rule's new sentence and the CHANGELOG Fixed entry could match the
    same way.
  - *What changed:* only that done-check. It now greps the list form (`pausieren` quoted, a list separator, then
    `/craft:pause` quoted). Before any edit, that grep was run on the tree: it prints each listed copy (except the split
    one in `CLAUDE.md`) and not line 1289. The list of copies is unchanged, as the finding says.
  - *Why a pattern, not exemptions:* a list of exempt lines would have to name lines that do not exist yet (the new
    sentences), and their line numbers would drift. The pattern describes what a copy is.
- **Revision round 5** (2026-10-08, the human's `[R]` at the plan gate, plus plan review P5-1).
  - *The human's note:* `/craft:pause` stays a pause word, and its effect only at turn end is documented (decision
    above). Changed: Goal (a fourth bullet), Vertical Slice Definition (`commands/pause.md`), Trigger 5, Effect (the
    `/craft:pause` bullet), re-test item 6, the pause-watch check, the D42 amendment, the hook sub-task (WHY), Rule 1's
    scope (now explicit: only "under `Mode: auto`" goes), the rule's turn-end sentence, the docs paragraphs. The
    conditional sub-task is now the keep branch, and the drop branch, its list of copies and its grep done-check are
    gone. No `NEEDS-HUMAN:` line is left.
  - *P5-1:* moot, because the drop branch it corrects is gone. The finding said the list-form grep also matched
    `.craft/tmp/epic-005-digest.txt` (lines 8 and 40) and the `.claude/plans/.closed/` copy of slice-075. It also said
    that round 4's line on what the grep printed (below) was incomplete. That line stays as the history of round 4, and
    this note corrects it. No done-check grep is left in the plan: the keep branch's check reads three named sites and
    one harness pin. So no grep can hit `.craft/tmp/`, and no `--exclude-dir=.craft` is needed.
- **Revision round 6** (2026-10-08, the human's `[R]` at the plan gate: "P6-1 übernehmen; P6-2: /craft:pause schreibt
  die Übergabe").
  - *P6-1, applied:* the Effect's and the sub-task's "every exit settles a pending request" was not true: the Error
    Handling rows for a `committed` and a `blocked` slice stopped before Step 3. Both rows now run Step 3 too, and the
    four exits are listed. Changed: Goal (bullet 4), Vertical Slice Definition, Effect (the `/craft:pause` bullet), the
    pause-watch check, the `/craft:pause` sub-task (exits, pins, two mutations), the first decision's "still
    missing" line.
  - *P6-2, the human's decision:* `/craft:pause` writes the handoff first (decision above). It replaces the planner's
    "no handoff" judgment. Changed: Goal (bullet 4), Vertical Slice Definition, Trigger 5 (the click at turn end, an
    idle prompt), Effect, the Test Strategy intro, re-test item 6 (the handoff at turn end), the pause-watch check, the
    D42 amendment, the `/craft:pause` sub-task (the Pre-flight bullet, its pin and mutation), the docs sub-task (the
    command-reference row, the CHANGELOG entry). Kept: the turn-end documentation of a queued `/craft:pause`.
  - No `NEEDS-HUMAN:` line was added.
- **Revision round 7** (2026-10-08, the human's `[R]` at the plan gate: "P7-1 übernehmen").
  - *P7-1, applied:* a `/craft:pause` sent as a prompt of its own is the pause action's run (decision above).
  - *Changed:* Vertical Slice Definition (the rule, `commands/pause.md`); Effect (the `/craft:pause` handoff bullet,
    now by call); the pause-watch check; re-test item 6 (one handoff, none before `/craft:pause`, no question for the
    note, and the idle case); the D42 amendment; the rule sub-task (rule 3's pointer clause, where it said "no edit");
    the `/craft:pause` sub-task (the bullet's two calls, Step 1's widened sentence, the pins, three more mutations,
    Done when); the decisions *How it is done* and *Scope*, corrected in place with the old text named.
  - *Not changed:* the six marked pause-word sentences, the hook, the helpers, the docs paragraphs and the CHANGELOG
    entry. Their text still holds.
  - No `NEEDS-HUMAN:` line was added.
- **Same root cause as T2, same remedy** (2026-10-08, planner's judgment, from D40's slice-076 amendment and rules.md →
  *A pointer's own unreachability handler cannot live behind that pointer*).
  - *The cause:* the pause rule told the agent to record the word "before anything else". It lives only in
    `skills/workflow/SKILL.md`, and build.md only points there. The T3 agent ran `/craft:pause` and nothing else.
  - *The remedy:* the record-and-pause action is stated at the site, in one marked sentence per command that can be
    running when the word arrives, and bound by `test-pause-watch.sh` (sites declared, both directions, mutations). The
    rule's body stays in *The pause request*.
- **Pause-word sites: build (the countdown), test, recap, refactor, review, debug (the attempt countdown)**
  (2026-10-08, planner's judgment; debug added in revision round 3, P3-1) — these six are where a slice is in flight
  and a pause word can arrive while the agent works. Two are left out:
  - `plan`: planning is excluded by slice-075's hook scope.
  - `commit`: a pending request is settled by commit, per the rule's rule 4. A pause while the slice lands is not
    offered.
  - *Alternative at the gate:* `[R]` to add commit.
- **The debug countdown: a bare pause word pauses the slice; any other input halts the loop** (2026-10-08, revision
  for plan review P3-1, planner's judgment on `[G]`).
  - *The corrected premise:* the earlier plan said debug's countdown "pauses the loop, not the slice, unchanged". That
    was wrong. The loop runs while the slice is in flight (`implementing` or `testing`). Since slice-075, a `pause`
    typed there under auto flow is already a request, and after this slice it is one under manual too. So the next
    boundary would pause the whole slice, though the countdown told the user `pause` halts the loop.
  - *Why the [G] reading:* the human's `[G]` says a pause word behaves the same everywhere. The hook and `request`
    cannot tell which countdown the word answered, so an exception would rest on the agent remembering to `consume` a
    request the hook may already have recorded. The user keeps a loop-only halt in any other input; `stop` is
    deliberately no pause word, so it still halts the loop. The countdown line now says both.
  - *Consequence:* a resumed slice comes back to its phase, not into the loop. The pause note carries the attempt count
    and the frozen protocol, and the human re-enters `/craft:debug`. No resume-into-loop mechanism is added (it would
    grow the entry).
  - *Alternative at the gate:* `[R]` for the exclusion reading. The debug countdown's answer is no request: the agent
    does not run `request` there and consumes one the hook wrote. The countdown keeps "type 'pause' to stop", and debug
    stays off the site set with this reason in the harness header. Not a `NEEDS-HUMAN:` question, because `[G]`
    already settles the meaning of the word. This is the plan's reading of `[G]`, open to `[R]`.
- **The drop branch lists every copy** (2026-10-08, revision for plan review P3-2, planner's judgment; superseded in
  revision round 5: the human kept `/craft:pause`, so no copy changes, kept as history). The words are
  defined twice in effect (the hook's `WORDS`, the rule's list), and slice-075 left ten prose copies plus D42's
  history line. One defining
  place with bound copies would need a new binding mechanism (a marker and a harness check across HTML and JSON) for
  a list of three words. That grows the entry. So the sub-task lists every copy, taken by grep, with a grep done-check.
  The new marked sentences name no words, so they add no copy.
- **`manual` and the pause request in `flow-state.sh`: the request wins only for a plan in flight** (2026-10-08,
  planner's judgment). Putting the whole pause check ahead of the mode stops would make a manual-mode plan at
  `committed`, or a missing one, print `STOP=committed` or `STOP=no-plan`. Under `manual` those are silent today. So
  the early check covers only the statuses today's check covers, and every other manual verdict stays `STOP=manual`.
  - It also wins over `invalid-mode`, because the request no longer depends on the mode. Otherwise rule 5 ("any `STOP=`
    settles a pending request") would swallow the word.
- **The hook stays, and drops its profile read** (2026-10-08, planner's judgment). For a pause word sent as a prompt
  of its own (the agent idle), the hook is still the early path. With `[G]` it has no mode to check, and the copy of
  the Mode reading that `test-pause-watch.sh` bound to `flow-state --mode` goes with it: one copy fewer.
- **The finding, in slice-075's terms** (2026-10-08, from the epic's decision line and slice-075's archive decision
  "record the finding in the slice archive"). It rests on one session (T3). The re-test adds the idle-prompt case (Test
  Strategy, item 4), so that "the hook never fires at all" (a load or registration fault) is not mistaken for the
  finding.
- **One call per question: a marker attribute, not prose alone** (2026-10-08, planner's judgment on the master's brief).
  - *How:* `<!-- craft:choice sequence -->` plus a fixed phrase on the marked line, bound like slice-076's tool name
    (a declared count in both directions, mutations).
  - *What it does not do:* it does not prove the agent's behavior. Like rule (a), it only makes a later edit that
    drops the phrase go red. A new dependent site without the attribute is caught by nothing; that becomes a known
    limit in the harness header. The behavior is shown by the T4 re-test only.
- **Sequence sites: `/craft:abort` only** (2026-10-08, planner's judgment, after reading every confirmation chain the
  brief names):
  - abort's Steps 2b → 3 → 4 → 5 and the new no-argument pick are a chain of questions with no work between them, so
    an agent can collect them into one call, and T4 did.
  - `worktree-clean` Step 3 asks three independent per-category questions, which may share a call under the new
    bullet, so no edit.
  - In `unblock` (fork → go-ahead), `commit` (split → messages; `[I]` → its diff confirmation) and `release`, the later
    question shows a result of the earlier answer, so it cannot be composed before it.
  - The *Choice prompts* bullet covers them all as the rule. *Alternative at the gate:* `[R]` to mark these sites too.
- **Abort without an argument: a click, still explicit** (2026-10-08, the human's T4 wish and the master's brief) —
  A1's "no defaulting" stays. A pick names the slice, and Step 5's second question names its ID again. Exactly one
  active slice still asks, with **Cancel** as the second option (the tool needs two). A malformed argument is still
  refused, because a typo is not the same as no argument.
- **D40 and D42 are amended; no new D-entry** (2026-10-08, planner's judgment).
  - D42's "Pause by one word … during auto flow" changes scope under `[G]`, and its "undocumented" reason is replaced
    by the finding.
  - D40 gains the dependent-question rule and abort's pick.
  - Both are extensions of decisions already taken, not new architecture.
- **Sizing — two parts, one entry** (2026-10-08, planner's judgment prompted by plan review P1-2 of round 1).
  - *Size:* about twenty files, two helpers, a hook and three harnesses.
  - *The natural cut:* (1) abort (sub-tasks 2–3 plus the D40 half of sub-task 1) and (2) pause (sub-tasks 4–6 plus the
    D42 half). The docs sub-task splits along the same line.
  - The abort part comes first so a cut at the gate takes it as it stands. A cut needs a new epic entry and is the
    human's call; this plan does not split.
- **The verify block leaves out `test-model-enum.sh`** (2026-10-08, rules.md, plus the precedent of slices 074–076) —
  the slice touches neither `model-defaults.md` nor `agents/`. Its `docs/index.html` edit is prose and harness rows,
  not a `craft:model-enum` line. Phase 8 and a release still run it in full.
- **Depends-On names slice-074, slice-075 and slice-076** (2026-10-08) — this slice corrects their effect (`flow-state.sh`,
  the pause request, the choice markers). All three have landed (archives in `.claude/project/slices/`).
- **Non-goal: the chat-language enforcement gap** (2026-10-08, from the master's brief) — it stays a roadmap candidate.
- Phase 7 skipped (project rule).

## Commits

- `f346bb8` — docs(decisions): amend D40 and D42 after the re-test
- `9fba4a3` — fix(abort): ask one question per click, offer the active slices
- `d957c72` — fix(pause): pause words in both modes, recorded by the agent, handoff first
- `30a661d` — docs(pause): document pause in both modes in the docs page and changelog
- `54723ae` — docs(rules): record the pause-watch finding in the harness notes

## Follow-ups

- R1-9 Light · Rethink · The handoff exactly once does not hold across pause episodes: a written ## Handoff and Handoff active: yes are never cleared on resume, so the second pause of one slice makes /craft:handoff ask overwrite or append or cancel mid-pause, pause.md does not say what a cancel does, and prime or status keep showing Handoff waiting; the pause word's action had the gap since slice-075 and /craft:pause now shares it
