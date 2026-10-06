# Slice 060 — cache-guard

> Completed: 2026-10-06
> Commits: dd8afc8..914f410 (on the autopilot epic branch epic-003-autopilot-mode, no PR)
> Epic: epic-003 (entry `cache-guard`, design record §7); landed by an autopilot run

## What

An autopilot session that waits on the human no longer re-writes its whole prompt cache for a late answer. A new
`UserPromptSubmit` hook, `hooks/cache-guard.sh`, blocks a human prompt that arrives after that session's cache expired —
when a re-write would cost at least the threshold (`Cache-guard-recache-tokens`, default 100000) — and names the restart,
`/clear` then `/craft:execute epic-NNN --autopilot`. Every human stop of the run (the orphan question, the plan gate, a `⛔`
stop, the a5 sign-off) first prints `Cache warm until HH:MM — answer later → <restart>`.

## Why

- Design record §7: a cold-cache answer costs a full context re-write for one "ja", and the human's reply to a stopped
  run is exactly such a prompt.
- The trigger (a prompt into an armed, waiting session after the cache expired) was confirmed by the user; the hook stays
  bash 3.2 and fails open on every doubt, because a wrong block is worse than a late re-write.

## Decisions

- **Scope = hook + expiry line** (user, 2026-10-06) — both halves of design record §7; the line shares the block's
  restart text. Autopilot only: the non-autopilot idle guard stays roadmap F7.
- **Threshold default 100 000 `recache_tokens_if_cold`** (user, 2026-10-06) — below it a cold re-write is cheaper than
  `/clear` + re-prime + re-loading `execute.md`; overridable in `craft-profile.md` → `## Autopilot`.
- **Restart instruction = `/clear`, then `/craft:execute epic-NNN --autopilot`** (planning, 2026-10-06) — design §7's
  `/craft:autopilot resume` never existed; a re-run resumes the epic (slice-038 / slice-049).
- **The marker is bound to the armed session** (planning, 2026-10-06) — it records the `session_id`, and the hook blocks
  only a prompt from that session, judged by a tap from that same session. The tap is shared across sessions
  (`statusline-tap.sh` header), so a foreign-session tap is "cannot judge" → pass. A stale marker after `/clear` then
  blocks nothing — provided `/clear` yields a new `session_id`, which probe (b) verifies.
- **Cold = the tap's `prompt_cache.expires_at` < now** (planning, 2026-10-06); no matching tap → pass, since the
  threshold cannot be judged without `recache_tokens_if_cold` either.
- **Marker path `.claude/plans/.cache-guard`** (planning, 2026-10-06) — next to `.execute.lock`, the other per-run state;
  `.craft/` is the worktree handoff directory and stays that. Costs one new local-state path in the gitignore and
  tree-dirt helpers.
- **Constraint: the hook stays bash-3.2-compatible** (rules.md → Bash baseline), so it cannot call `usage-state.sh`
  (bash ≥ 5) for the tap path. The tap path must still be defined once — settle in Phase 4 whether it moves to a shared
  constant or is bound by the harness, not copied silently.
- **The plan's verify block had invalid check names — corrected (names only)** (test, 2026-10-06) — `verify-run.sh` read the six
  `- check <name> :: …` lines as malformed (a name is `[a-z0-9][a-z0-9-]*`; the planner wrote "cache guard" with spaces), so
  Run 1 failed before anything ran. The names were hyphenated; commands and expectations are unchanged. The plan gate's
  checks (`/craft:plan` P1–P3, "a `<!-- craft:verify -->` block present") do not run `verify-run.sh`'s grammar — a follow-up
  for the planning pipeline.
- **Probe (b) result: headless direct, interactive indirect** (build, 2026-10-06) — a `-p` run on Claude Code 2.1.291 shows
  the payload fields (`session_id`, `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `hook_event_name`, `prompt`) and
  no hand-back in `-p`. The interactive facts (hand-back markup, `/clear` → new `session_id`) could not be driven by the
  builder: an interactive fixture needs its trust dialog answered, and the permission classifier refused the attempt to
  automate that answer, so it was not worked around. Evidence instead: the local transcripts of the user's own sessions
  (queued hand-back content still starts `<agent-message from=`; every `/clear` begins a new transcript with its own
  `sessionId`) and env-vars.md (`CLAUDE_CODE_SESSION_ID` "is updated on `/clear`", matches the hook's `session_id`).
  Neither shows a changed format, so the slice went on; recorded in design record §2. The human test (c) is the direct check.
- **A helper arms and disarms the marker: `scripts/cache-guard-marker.sh`** (build, 2026-10-06) — not in the plan's file list,
  but the master must not carry a session id or compute an expiry time by hand (rules.md: a number an agent states is read
  off a helper). It reads the session id from `CLAUDE_CODE_SESSION_ID` (a Bash-tool env var, documented to match the hook's
  `session_id`), refuses to arm without one (fail open: `ARMED=no`, the stop goes on), and prints the expiry line.
- **The marker is never removed — disarm writes `state=disarmed`** (build) — like `.execute.lock`: CRAFT keeps its state files
  (a user's removal rule must never be gone around, B19 / D34). The hook reads only `state=armed`.
- **One definition of the restart text: `hooks/cache-guard.sh --restart`** (build) — the block's reason and the helper's expiry
  line both use it; `commands/execute.md` carries no copy, only `LINE=` relays. The tap path, the default threshold and
  the stale age are copies in the (bash 3.2) hook, bound by `test-cache-guard.sh` to what `usage-state.sh` /
  `statusline-tap.sh` declare — the plan's "shared constant or bound by the harness" is settled as bound.
- **Disarm sites are wider than the plan's two** (build) — every human answer in ap and a5, the start of each invocation
  (right after the lock) and before every builder spawn; arm sites are the orphan question, the plan gate, every `⛔` stop after
  the lock and the a5 sign-off. A `⛔` stop is a run end that still waits on the human, so it arms; only a5's answer ends the
  run for good. The hook also passes `/clear`, `/exit`, `/quit` (the block names `/clear` as the way out).
- **Phase 7 skipped (project rule)** — rules.md → Workflow Rules drops Phase 7; the recap hands straight to review.
- **Expiry unknown prints `Cache expiry unknown — answer later → …`** (build) — instead of "Cache warm until unknown".
- **Human test (c) is owed, not run** (review R2-4, 2026-10-06) — this slice passed Phase 5 by command inside an autopilot
  run, so the real human test rules.md requires for a fail-open hook has not happened, and the interactive facts
  (hand-back markup, a new `session_id` after `/clear`, the tap refreshing during an idle wait) still rest on indirect
  evidence. It is the human's step before the epic merge: run Test Strategy (c) in a `claude --plugin-dir` session when
  a5's UX demo script reaches slice-060, and answer the sign-off only after it. If it is not run, it goes to the archive's
  follow-ups as owed.
- **Human test (c) part A passed** (user, 2026-10-06, at a5 before the sign-off) — in a `claude --plugin-dir` session on a
  test tap (`CRAFT_USAGE_TAP`, statusline neutralised by `--settings`), armed via `~/cache-guard-test/setup.sh`: a subagent's
  hand-back passed while the guard was armed and the tap cold; a human `hallo` was blocked with the restart text and got no
  answer; `/clear` passed and the next prompt passed (the marker stays bound to the old session). Confirms interactively
  what probe (b) could only show indirectly: the hand-back markup and the hook's `session_id` = `CLAUDE_CODE_SESSION_ID`.

## Commits

- `dd8afc8` — feat(hooks): add the autopilot cache guard hook and marker helper
- `07a97d2` — feat(profile): add the Cache-guard-recache-tokens autopilot key
- `7a86217` — feat(gitignore): treat the cache-guard marker as CRAFT local state
- `65e836b` — feat(execute): arm and disarm the cache guard at autopilot human stops
- `a0b300c` — fix(test): stop reading a capitalised "Arm" as an rm command
- `648d993` — docs(cache-guard): document the cache guard for users
- `46bba0a` — docs(project): record the cache guard in project knowledge
- `914f410` — chore(plans): bump slice counter to 61

## Follow-ups

- R1-1 Light · Rethink · A ⛔ stop arms the guard but nothing disarms it when the human answers (the run has ended), so after manual work in the same session an idle hour blocks every prompt with the autopilot restart text; a record of prompt_cache.requests at arm time could bind the guard to the stop (execute.md guard section, hook, design §7 As built)
- R1-2 Light · Rethink · The restart line is the same for every ⛔ stop, but a stop whose next step is a human action (blocked escalation, debug protocol, Handoff) needs that action before a re-run; the line and the hook's block reason name only the re-run (cache-guard.sh --restart is the one definition)
- Human test (c) part B owed — the real idle case (real tap, cache really expired after ≥ 1 h, no other Claude session open, since the tap is shared) was not run; part A covered the logic on a test tap.
