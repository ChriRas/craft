# Slice 052 — Ping-Pong Breaker

> Completed: 2026-09-30
> Commits: 3a38072..a5900de (branch only, trunk-based)
> Epic: epic-003 (autopilot mode), entry `ping-pong-breaker`

## What

Inside an autopilot run a Heavy + needs-rethinking review finding no longer stops the run: it gets exactly one
autonomous loop-back to Phase 4. If the next round reopens it, or round 3 ends with a Heavy still open, the ping-pong
breaker trips and blocks the slice (`decision`) with an escalation package of at most 15 lines, shown at the run's ⛔
stop. Outside autopilot, Phase 8 is now calibrated plugin-wide: a finding is Heavy only with a realistic failure, a
slice gets at most 3 review rounds, and at the cap an open Heavy can be accepted as a known limit (archived with the
follow-ups), granted one extra round, or spun off.

## Why

- **Counters are derived, never stored** — `review-findings-state.sh` reads rounds and reopens from the findings
  record; a counter a writer forgets to bump cannot exist (derived state over cleanup, slice-036).
- **The first reopen trips, not the second** — read literally, a second reopen could fire no earlier than the round
  cap; "one autonomous attempt per finding" (design §3) is the distinction that carries information.
- **Only the latest round counts** — the record is append-only; an answered reopen must not trip every later round.
- **The calibration makes the breaker fair** — every Heavy costs a round, so a Heavy must name a realistic failure.
- **Scope cut** — the protocol freeze, the debug loop and the master judgment line moved to epic-003's
  `autonomous-debug-loop`, so this slice would not repeat slice-046's nine rounds.

## Decisions

- **Scope: breaker core + plugin-wide calibration** (user) — trip detection, one autonomous loop-back, the escalation
  package, the Heavy threshold and the round cap. The two-agent protocol freeze, the `/craft:debug` loop after a trip
  and for Phase 4's 2nd same-symptom fix, and the master judgment line went to the new epic entry
  `autonomous-debug-loop`. *Why not* the full entry: five parts in one slice.
- **Counters are derived, not stored** (user) — **promoted to `intent.md`** (derived state over cleanup).
- **Trip rules: round cap + first reopen** (user) — a Heavy reopen (`reopens <ID>:`) of a line resolved
  `escalated → Phase 4 loop-back`, in the latest Phase-8 round, or round 3 closing with a Heavy (or MALFORMED) line
  open. A reopen of an unknown or not-earlier ID trips as doubt. A line fixed in-phase and reopened is no ping-pong
  (review R1-3): it meets the next round and the cap. *Why not* the second reopen: it can fire no earlier than the cap.
- **No "builder disputes twice" rule** (user) — the record has no dispute mechanism; the Heavy threshold does the job.
  *Why not* add disputes: a new record format for a case the threshold covers.
- **The Heavy threshold's Light carve-out is scoped to crafted development artifacts** (review R1-2) — input an
  untrusted party can hand the shipped product is a realistic path, so security stays Heavy. The plugin-wide
  generalisation had dropped `rules.md`'s scope ("CRAFT's own tooling").
- **The round cap is one constant, `ROUND_CAP_BASE=3`** in the helper; a `- note · extra round granted: <why>` line
  raises it by one, written once per run (review R2-2). A profile setting is left to `budget-and-cache-guard` (Q6).
- **In the final round nothing loops back without a granted extra round** — Steps 4, 5 and 7 go through Step 7's cap
  route: open Light lines become follow-ups, an open Heavy gets known limit / extra round / new slice / pending. A
  fix-cap loop-back accepted in round 3 had reached `committing` unreviewed (review R1-1, reproduced).
- **`accepted → known limit` reaches the archive through `--followups`** (as `— known limit[: <why>]`), and the
  reviewer treats it as handed out of the slice (review R2-3), so a later round never reopens the human's decision.
- **The breaker is `/craft:review` Step 9**, not prose inside Subagent Mode — the status-graph harness forbids a status
  write in a delegating Subagent-Mode section (the B1 guard); Step 9 writes the block through `slice-builder`'s
  existing writer, so the handoff writer set is unchanged. New graph row `/craft:review` → `blocked` → `/craft:unblock`.
- **Autopilot loops back only this round's Heavy + Rethink findings**; a fix-cap batch or an earlier pending line still
  meets the Gate — that stop remains.
- **`rules.md`'s calibration block became a pointer** — **promoted to `rules.md`** in Phase 9 (`/craft:build` must not
  edit `rules.md`); the project-only bullets (no automatic new slice, harnesses as staleness detectors) stay.

## Evidence

- **Harnesses:** all fifteen green on the final tree (`test-review-findings-state.sh` 48 passed, status graph 94,
  handoff marker 90, model enum 117 checks); `claude plugin validate .` passed. The breaker fixtures were written first
  and ran red (12 cases) against the old helper; R1-3 and R2-2 each added a fixture. The status-graph harness bit twice
  during the build (a marker without its `Status: blocked` instruction, a status write in Subagent Mode).
- **Headless probe P1** (sonnet, scratch fixture `probe052` without hooks, `--permission-mode bypassPermissions`):
  `craft:slice-builder` in an autopilot context on a plan at `reviewing` with three Phase-8 rounds and R3-1 open. From
  the files: `blocked` / `decision` / `Blocked-status: reviewing`, a 10-line `## Blocker`, no fourth round, marker
  `awaiting-block-decision` with `Phase: 8` and `Episode` = `Blocked-since`, `handoff-marker-state.sh` → `STATE=LIVE`.
- **Phase 5:** `[W]` on the evidence report. **Unshown:** the interactive cap route (proposed human test T1, not
  reported as run), the `TRIP=none` autonomous loop-back and a reopen trip through a live reviewer (helper fixtures
  only), and the docs-site visual check.
- **Review:** two rounds, two passes each (rubric + scenario walk S1–S6). Round 1: 2 Heavy + 7 Light, all fixed
  in-phase (fix cap waived; R1-3 narrowed now on the user's decision instead of a follow-up). Round 2: all 9 held;
  0 Heavy + 5 Light, fixed in-phase. No third round.
- **Observed, outside this slice:** `CHANGELOG.md` → Unreleased carries no entry for slice-050 or slice-051.

## Commits

- `3a38072` — feat(scripts): derive the review ping-pong breaker from the findings record
- `59ea117` — test(scripts): cover the ping-pong breaker and the known-limit resolution
- `766edfe` — feat(review): cap review rounds, require a realistic failure for Heavy, break autopilot ping-pong
- `b1780fa` — docs: document the review ping-pong breaker and the round cap
- `e98a00a` — docs(design): record the ping-pong breaker as built
- `a5900de` — chore(plans): bump slice counter to 53
