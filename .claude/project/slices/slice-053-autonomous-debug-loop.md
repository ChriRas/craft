# Slice 053 — Autonomous Debug Loop

> Completed: 2026-09-30
> Commits: fbbc5ed..d104895 (branch only, trunk-based)
> Epic: epic-003 (autopilot mode), entry `autonomous-debug-loop`

## What

Inside an autopilot run a bug no longer stops the run at once: when the builder is about to make a 2nd fix on the
same symptom in Phase 4, or a committed check fails in Phase 5, an autonomous `/craft:debug` loop tries up to
*Max attempts* fixes. Whether an attempt worked is never the agent's call — `verify-run.sh` decides. Only an exhausted
loop, a protocol rejected twice, a wrong red baseline, a refused check, a malformed block, or — in Phase 4 — no verify
block at all reaches the human, at the familiar `awaiting-protocol` / `awaiting-test` pause with the attempt log.

## Why

- **D35 holds inside the debug loop too** — an agent writing its own ✓ is a report, not evidence. The protocol becomes
  `- check` lines in the verify block and every attempt ends with a helper round; every autonomously fixed bug stays
  behind as a regression check.
- **Two agents freeze the protocol, the second is the existing `code-reviewer`** — a new agent would only add model-tier
  bindings. Probe 2 showed how delicate the criterion is: a bug check must fail today, a negative check must pass
  today; worded loosely, the reviewer rejected every sound protocol.
- **No loop after a breaker trip** — review findings are often not command-verifiable, and a trip already means one
  autonomous attempt failed.
- **The end stops are the existing pauses** — no new status, no new graph edge; `awaiting-protocol` / `awaiting-test`
  already mean "a human decides this bug".

## Decisions

- **Scope: Phase 4 + Phase 5** (user) — the loop runs for a 2nd same-symptom fix in Phase 4 and a failed committed
  check in Phase 5. **No loop after a breaker trip** (rejected; D32 annotated). **The master judgment line moved to
  `planning-pipeline`** — today every master decision is read off a helper (status, `TRIP=`, `RESULT=`, marker state).
  *Why* the Phase-5 trigger: slice-051 deferred "one debug attempt first" to this entry, and there the frozen protocol
  already exists — the committed check.
- **The second agent is `code-reviewer`** (user) — a delimited *Protocol Freeze* brief next to its Phase-8 brief.
  *Why not* a new agent: `test-model-enum.sh` binds every agent to the tier tables and several marked copies.
- **The verdict is `verify-run.sh`'s** (user, D35) — **promoted to `intent.md`** (the autopilot bullet). A Phase-4
  protocol's lines join the verify block; a red baseline run (`--only`, before attempt 1) must fail exactly the bug
  checks and no negative check (review R2-2), so a bug check that already passes can never make an attempt "pass".
- **What is frozen during the loop** (review R1-1, R2-1) — every check line of the verify block, and every file that
  *verifies* (a check's test, harness, fixture or verification script); not the code under test, even when a check runs
  it directly. This overrides the Senior-Developer Problem-Playbook's "adapt the test" inside the mode; a check the
  agent believes wrong is the end stop.
- **Drafts are validated before an irrevocable append** (review R1-4, R2-3) — names `bug-<id>-<n>` /
  `bug-<id>-neg-<n>`, unique in the block; each command judged byte-exact by `permission-rule-match.sh`; the reviewer
  rejects an unparseable or duplicate line. The protocol is recorded only on `freeze` (R1-5).
- **`verify-run.sh --only`** — a named subset, because in Phase 4 the rest of the block may legitimately fail on an
  unfinished slice; its round is marked ` · only:` and "selected checks", and `/craft:execute` a3 credits only a full
  run.
- **End stops are today's pauses** (user) — `awaiting-protocol` (Phase 4) / `awaiting-test` (Phase 5), with a ≤ 15-line
  package that maps to the resume path and names the frozen verify lines (review R1-7). *Why not* `blocked`: new rows
  and writers for no gain.
- **Refused, malformed and missing checks stay stops; no verify block, no autonomous mode** (Phase 4) — the loop is for
  a failing check, and a block of only bug checks would turn Phase 5's stop into a pass.
- **The new `code-reviewer` spawn site carries `model-defaults.md`'s obligations** (review R1-2) — the pointer and the
  fallback sentence. *Known limit:* `test-model-enum.sh` is frozen (`rules.md`), so its reader / spawn-site lists do not
  assert the skill's sentences; `model-defaults.md` says so.

## Evidence

- **Harnesses:** all fifteen green on the final tree (`test-verify-run.sh` 74 passed, `test-model-enum.sh` 117 checks);
  `claude plugin validate .` passed. The `--only` fixtures were written first and ran red (7 cases).
- **Probe 1** (sonnet, scratch fixture `probe053`, no hooks; probe limit: Phase 5 only): a seeded bug failing the
  committed check `greet`. From the files: evidence Run 1 `fail`, the agent's own `## Bugs` entry ("Aligned by:
  slice-builder"), Attempt 1 with "Verdict: verify-run.sh round 2 — pass", Run 2 written by the helper `pass 2/2`, the
  diff exactly the fix, the verify block untouched, `Status: review`, no pause.
- **Probe 2 / 2b** (`code-reviewer`, Protocol Freeze): the first brief rejected the weak draft but also the sound one
  (it read "must fail today" onto the negative check) — a surprising result, fixed in Phase 4; with the sharpened
  brief: sound → `freeze`, weak → `reject`. One run per case.
- **Phase 5:** `[W]` on the evidence report; probe 2b accepted for the surprising result. **Unshown:** the Phase-4
  trigger chain as a whole, the full autopilot path after Phase 5, the freeze judgment beyond one run per case, the
  docs-site visual check, and — on the final prose — the round-2 fixes (role-based freeze, red baseline, byte-exact
  matcher call), which no probe exercised.
- **Review:** two rounds, two passes each (rubric + scenario walk S1–S8). Round 1: 2 Heavy + 7 Light, all fixed
  in-phase (fix cap waived; D32 annotated on the user's decision). Round 2: all 9 held; 0 Heavy + 4 Light, fixed
  in-phase. No third round.

## Commits

- `fbbc5ed` — feat(scripts): let verify-run.sh run a named subset of checks
- `0c78a32` — test(scripts): cover verify-run.sh --only
- `2c8c382` — feat(autopilot): run an autonomous debug loop judged by verify-run.sh
- `d2f73f9` — docs: document the autonomous debug loop
- `fa0cf5a` — docs(design): record the debug loop as built and annotate D32
- `d104895` — chore(plans): bump slice counter to 54
