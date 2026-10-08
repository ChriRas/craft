# Epic 005 — Comfort and Flow

> Completed: 2026-10-08 (started 2026-10-08)
> Slices: 7/7 landed · one autopilot epic on epic-005-comfort-and-flow (five planned by hand, two fix slices planned by agents after the human tests), merged into main on the human's yes
> Merge: 4217a0e (Merge epic-005: Comfort and Flow)

## Vision

CRAFT asks the human for decisions in a mix of typed letters and free text, and a slice still needs the human to
type every phase command — friction that adds nothing at points where the answer is a choice. This epic makes every
human decision a click (AskUserQuestion) and makes "auto" the default slice flow: phases chain by themselves up to the
commit, stopping only where a human must decide, and a typed "pause" is picked up by a script so the running step
finishes, a handoff is written and the slice pauses normally. When it is done, a user works a slice by clicking answers
and can step away at any time with one word; the old manual flow stays selectable and `/craft:onboard` asks which one a
project wants. Two calibrations ride along: the cache guard's re-cache threshold rises to 150000 tokens, and the
review's in-phase fix cap becomes a guide value the agent may exceed when the remaining fixes are small. Out of scope:
autopilot's own stop / plan-gate logic, the debug loop's *Max attempts*, and any change to what counts as a human-only
decision.

## Slices (7/7)

- [slice-071 — cache-guard-150k](./slice-071-cache-guard-150k.md) — the cache guard re-caches only from 150000 tokens on, and Phase 4's context guideline says ~150k
- [slice-072 — clickable-choices](./slice-072-clickable-choices.md) — every interactive human choice is specified as an `AskUserQuestion` click (D40); the autopilot's cache-guard stops stay typed
- [slice-073 — soft-fix-cap](./slice-073-soft-fix-cap.md) — the review's in-phase fix cap is a guide value: small local fixes go on up to twice the cap, with the reason recorded (D41)
- [slice-074 — slice-auto-flow](./slice-074-slice-auto-flow.md) — `## Slice Flow` → `Mode: auto` (default) chains the phases through `flow-state.sh` up to the commit; `manual` keeps one command per phase (D42)
- [slice-075 — pause-watch](./slice-075-pause-watch.md) — a message that is only `pause` / `pausieren` / `/craft:pause` stops the auto flow at the next boundary: finish the step, handoff, pause
- [slice-076 — click-and-flow-fixes](./slice-076-click-and-flow-fixes.md) — the fix for human test T2: every choice site names `AskUserQuestion` on a marked line bound by `test-choice-prompts.sh`, recap asks no Phase-7 question in auto flow, commit omits the attribution silently
- [slice-077 — abort-and-pause-fixes](./slice-077-abort-and-pause-fixes.md) — the fix for the re-test: abort asks one question per click and offers the active slices; a pause word works the same in both modes; the hook's mid-turn limit is on record; `/craft:pause` writes the handoff once

## Epic Decisions

- **The "bug limit" is the review in-phase fix cap** (2026-10-08, human choice) — `Review in-phase fix cap` (default 5,
  `commands/review.md` Step 4, `skills/workflow/SKILL.md` Phase 8). It is already "soft" in interactive mode (a
  recommendation the user may waive), but in Subagent Mode / autopilot a breach leaves the rest
  `open — fix cap, awaiting decision`, i.e. it acts as a hard stop. The debug loop's *Max attempts* (5) and the review
  round cap (3) are **not** in scope.
- **Auto flow runs up to and including the commit** (2026-10-08, human choice) — phases chain without a typed command;
  every human-only decision (Phase 5 W/B/U, review escalations / cap routes, Phase 9 decision promotion, commit-message
  confirmation) stays a human decision, asked as a click, and the flow continues right after the answer. `manual`
  keeps today's behavior (one command per phase, `Recommended next:`).
- **Four slices, smallest first** (2026-10-08, human choice) — `cache-guard-150k` is an isolated quick win;
  `clickable-choices` precedes `slice-auto-flow` because auto flow's stops are those clicks.
- **Auto flow split in two** (2026-10-08, human choice while planning it) — `slice-auto-flow` (profile setting, onboard,
  prime, the flow helper, phase chaining) and `pause-watch` (hook, marker, pause → handoff + pause), which depends on it.
  *Why:* one slice would have spanned two helpers, a hook, the profile surface and seven phase commands — the size that
  reaches the review round cap — and the pause part rests on undocumented hook behavior that needs its own human test.
- **Research findings feeding slice planning** (2026-10-08, verified against code.claude.com docs):
  - A message the user submits while the agent runs tools is **queued** and delivered **within the same turn** once the
    running tool calls finish (`interactive-mode.md` → "Queue messages while Claude works"). So a typed "pause" reaches
    the agent at the next tool boundary, not only at turn end.
  - A `Stop` hook can return `decision: "block"` with a `reason` to keep Claude from stopping (`hooks.md` → "Stop
    decision control"). A research subagent reported the opposite; the docs contradict it. This is a possible
    enforcement path for auto flow (bounded via `stop_hook_active`) — to be weighed in `slice-auto-flow`'s plan.
  - Whether `UserPromptSubmit` fires for such a **queued** mid-turn message (and when) is **not documented** →
    `slice-auto-flow` must prove it with a real interactive human test (rules.md: fail-open hooks and interactive-only
    behavior need one) before relying on the hook; the fallback is the agent itself reading the queued "pause" at a
    phase boundary through a helper.
  - `AskUserQuestion` is **removed from subagents** and **unavailable in headless `claude -p`** (`sub-agents.md`,
    `headless.md`). Subagent paths keep writing handoffs (they never ask a human anyway); `clickable-choices` cannot be
    shown by a headless probe → its Phase 5 needs a real interactive test. Per its tool schema (this session) a
    question takes 2–4 options plus an automatic "Other", up to 4 questions per call — menus with more options must be
    split or grouped.
- **D-entries** — banked in `brainstorm-decisions.md` as each slice is planned (rules.md: decisions banked before
  implementation): `D40` clickable-choices (slice-072), `D41` soft-fix-cap (slice-073), `D42` slice-auto-flow + pause-watch (slice-074, slice-075).
- **Human test T2 failed for the clicks — a fix slice before the merge** (2026-10-08, human choice) — a `claude --plugin-dir`
  session (Sonnet, scratch project `craft-scratch-005`, transcript `e9f18de2-…`) ran plan → build → test → recap → refactor
  → review → commit: auto flow chained every phase through `flow-state.sh` (slice-074 holds), but **not one
  `AskUserQuestion` call** was made — plan's build-now / later, test 5c W/B/U, the commit split confirmation and K/I/R/D
  all came as typed text. Cause: the click rule lives only in `skills/workflow/SKILL.md` → *Choice prompts*; the phase
  commands only point at it (`test.md` says "ask as a click" without naming the tool), and that file was never read in
  the session (the text "Choice prompts" occurs 0 times in the transcript). Onboard (T1) clicked because its prose names
  the questions itself. Second defect: `commands/recap.md:90` still asks *"Ready for Phase 7 (refactor)?"* in auto flow.
  Third: the session remarked three times (prime, twice at commit) that it omits the Co-Authored-By trailer — the human
  wants it omitted silently, one mention at onboarding / prime at most, never at commit. Same root cause as the open
  chat-language gap (a rule in one file, only pointed to) — that one stays a roadmap candidate, not this slice's scope.
  T1 passed (clicks in onboard, the guided Slice-flow knob writes `Mode: manual`); T3–T5 wait for this fix.
- **Re-test after slice-076: T2 and T5 pass, T3 and T4 need a second fix slice** (2026-10-08, human choice) — sessions in
  `craft-scratch-005` (Sonnet, `--plugin-dir`, 0 cache loads): transcript `28434f44-…` (T2–T4) and `a0839886-…` (T5).
  - **T2 passed:** 13 `AskUserQuestion` calls, the flow chained to the commit, recap asked nothing, no attribution remark.
  - **T3 (pause, auto flow):** the queued `pause` reached the agent as a `queued_command` attachment mid-turn; **the
    `UserPromptSubmit` hook did not fire for it** — `.claude/plans/.pause-request` was never written (the file does not
    exist). The agent saw the word itself, finished sub-task 1, ran `/craft:pause` with a pause note, and `/craft:continue`
    resumed at sub-task 2 — but it neither recorded the request (`pause-request.sh request` never called) nor wrote the
    handoff (`/craft:handoff` never invoked). This is the finding slice-075 said to record in its archive: the hook covers
    only a "pause" sent while the agent is idle between turns.
  - **T4 (abort):** the slice-ID argument is required by design (`commands/abort.md` A1: no default, abort is
    destructive; the test sheet was wrong to omit it). Defect: the Step-3 recency warning and Step 5's two confirmations
    came in **one** `AskUserQuestion` call; the human answered No to the first confirmation and Yes to the second, and the
    agent correctly cancelled on the contradiction. The prose says "in a row" / "wait for the answer" but not "one call
    per question, never batched". Wish: without an argument, offer the active slices as a click instead of the A1 error.
  - **T5 (manual flow) passed** for what it checks: prime showed `flow=manual`, plan did not start build, no pause marker
    was written. But the typed `pause` made the agent stop at once, mid-sub-task — files written, tests not run, nothing
    checked off, no pause note, status left `implementing` — where auto flow finishes the running step first.
  - **Human decision `[G]`:** a pause word behaves the same in manual and auto flow — finish the running step, write the
    handoff and the pause note, pause the slice. Fix slice `abort-and-pause-fixes` before the merge.

## Open follow-ups

- Roadmap B28–B32 (recorded at the merge, `d6a8bd0`): the chat language is never enforced after `/craft:prime` (B28); a second pause of one slice meets the handoff question (B29, slice-077 R1-9); auto flow cannot tell a headless session (B30, slice-074 R1-6); the `--from` table is an unbound copy (B31, slice-074 R2-4); the re-test leftovers (B32).
- Roadmap B33: `/craft:commit` Mode Detection step 0 requires the main worktree to be the only one, so an unrelated detached worktree (here `CRAFT-runtime-epic-004`) makes a closable epic fall through to A1 — this close went on by the human's go-ahead.
- The interactive checks of a queued `/craft:pause` and of the debug countdown were not run in the human re-test (optional items).
