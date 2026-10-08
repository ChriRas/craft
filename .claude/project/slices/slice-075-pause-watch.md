# Slice 075 — pause-watch

> Completed: 2026-10-08
> Commits: 3e9c25e..4a300f3 (branch only — epic-005-comfort-and-flow, no PR)

## What

During auto slice flow, a message that is only `pause`, `pausieren` or `/craft:pause` now stops the flow: the agent
finishes the running step, writes the handoff and pauses the slice the normal way; `/craft:continue` resumes it.

## Why

- Auto flow (slice-074, D42) removes the typed phase commands, so the human needs one cheap way to say "stop here".
- The word is recorded in a marker (`.claude/plans/.pause-request`, kept as state like the cache guard's) by a silent
  `UserPromptSubmit` hook and — because it is undocumented whether the hook fires for a message queued mid-turn — also
  by the agent itself; `flow-state.sh` reads it at the next boundary. A marker it cannot read is no request: a phantom
  pause costs more than one more step.

## Decisions

- **D42 governs** (banked 2026-10-08 with slice-074) — pause words, hook + agent recording, marker kept as state.
- **Pause words** (2026-10-08, human choice) — whole message `pause`, `pausieren`, `/craft:pause`; `stop` / `halt` are
  deliberately excluded (too easily meant otherwise).
- **Pause = handoff + normal pause** (2026-10-08, the human's request) — finish the running step, `/craft:handoff`,
  `/craft:pause`; no new pause mechanism.
- **Hook and agent both record** (2026-10-08) — whether `UserPromptSubmit` fires for a queued mid-turn message is
  undocumented (Claude Code docs checked 2026-10-08); the agent path makes the feature work either way, and the human
  test settles the hook. If it never fires for queued messages, the hook still covers a "pause" sent while the agent
  is idle between turns — record the finding in the slice archive.
- **Doubt for this helper** (2026-10-08) — a marker the helper cannot read is no pause request (`flow-state.sh` then
  continues its own doubt rule): a phantom pause would halt a flow the human did not stop; a missed one costs one more
  step, and the human can type again.
- **Split from `slice-auto-flow`** (2026-10-08, human choice) — depends on slice-074's `flow-state.sh`.
- **"Older than the plan's resume" is derived, not stored** (2026-10-08, slice-builder) — `/craft:continue` 4a already writes
  `> Resumed: <datetime> →` into the `## Pause Note`; `pause-request.sh state --plan` reads the latest such line and a request
  with an older `SINCE` is not live. No new write in `/craft:continue`.
- **Sub-task boundary asks `flow-state.sh --from implementing`** (2026-10-08, slice-builder) — `STOP=pause-requested` wins over
  `no-progress`, so the same helper answers at a sub-task boundary; there only that STOP matters, anything else continues the build.
- **The hook carries its own writer** (2026-10-08, slice-builder) — it is bash 3.2 and cannot call the bash >= 5 helper; the
  marker format (`STATE`/`SESSION`/`SINCE`) is defined in `pause-request.sh`, the hook writes the same lines (harness round trip binds them).
- **Hook scope** (2026-10-08, slice-builder) — records only under `Mode` not `manual` and with a slice at implementing / testing /
  review / refactoring / reviewing / committing (`planning` is excluded: a planning dialogue answer "pause" is too easily meant otherwise).
- Phase 7 skipped (project rule)
- **Review round 1** (2026-10-08) — 1 Heavy/Local (an unread request leaking into the next slice) and 7 Light/Local, all fixed
  in-phase: unread requests are settled by any other `STOP=`, `/craft:commit` and `/craft:abort` (rule 4); `request` and the hook
  always restamp `SINCE` (so the word typed again after a resume counts — this replaces the earlier "first SINCE stays" idea);
  an unparseable `> Resumed:` stamp is `LIVE=no`; the hook's copies are bound in the harness.
- **Unshown (Phase 5, autopilot):** whether `UserPromptSubmit` fires for a message queued mid-turn — only the interactive test
  in a `claude --plugin-dir` session shows it; verified by command here: all six checks of the verify block (round 1, pass).

## Commits

- `3e9c25e` — feat(pause): add the pause-watch hook and pause-request.sh
- `71694af` — feat(flow): stop the auto flow on a pause request
- `7c96b7f` — feat(gitignore): treat the pause request as CRAFT local state
- `2874a41` — docs(pause): document the pause request in the docs page, README and changelog
- `4a300f3` — docs(rules): list the pause-watch harness
