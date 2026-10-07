# Slice 070 — cache-guard-disarm-on-answer

> Completed: 2026-10-07
> Commits: 532a935..c93b2fe (branch only — main, no PR)

## What

The autopilot's cache guard now holds only the answer its stop waits for. When the session went on after a `⛔` stop —
the human answered, or worked on by hand — a late prompt after an idle hour is no longer blocked with the autopilot
restart text. And when a stop needs a step from the human before the re-run (a scope question to answer via
`/craft:continue`, a protocol, a blocker), the restart line names that step first instead of only "/clear, then re-run".
These are slice-060's follow-ups R1-1 and R1-2.

## Why

- R1-1: a `⛔` stop arms the guard, but nothing disarms it when the human answers — the run has ended. A record of the
  request count at arm time lets the read-only hook see whether anything happened since; where the count cannot be
  judged it passes — the guard's existing posture: the worst case is a costly re-write, never a wrong block.
- R1-2: the action is data in the marker; the restart's wording keeps its one definition in `cache-guard.sh --restart`,
  never a second sentence in `execute.md`. Both follow-ups touch the same marker, hook text and `execute.md` section, so
  one slice carries them.

## Decisions

- **R1-1 mechanism: a request-count record with a tolerance, in the read-only hook** (user). *Why not* the hook
  disarming itself: it would write, and the hook is read-only and bash 3.2; *why not* a time window: it needs a tap field
  nobody has verified. A plain "record `requests` at arm time" is not enough: the stopping turn's own final message is a
  request, and the tap may lag, so the tolerance is part of the contract.
- **R1-2 is in scope** (user): one slice for both follow-ups; the restart text keeps its single definition, the action
  is data in the marker.
- **Part B of slice-060's human test (a real idle hour) is dropped** (user, 2026-10-07): no release blocker.
- **Tolerance = 1, measured** (live tap, Claude Code 2.1.292, statusline `refreshInterval: 30`): three consecutive tool
  round trips read `requests` 12 → 13 → 14 with tap mtime age 0–1 s (no lag); after the turn ended and the human sent a
  prompt, the next turn's first tool call read 16 = 14 + 1 (the stopping turn's final message) + 1 (the new turn's first
  request) — no hidden request. The hook therefore sees N + 1 at a prompt answering the stop itself, at least N + 2 once
  any answer turn ran. *Why not* 2: it would block a session whose only activity after the stop was one text-only
  answer. Inferred, not read: the value at hook time (16 − 1). Unshown: a lagging tap at arm time (it would pass — fail
  open).
- **`requests=unknown` instead of omitting the key**: only a written placeholder tells "a count arm could not read"
  (pass) from "a marker armed before slice-070" (old rule, blocks) apart; a key that is absent means the latter.
- **The action is flattened, not refused**: the helper turns every run of whitespace / control characters into one
  blank and trims the ends; the hook only validates (`--restart` exits 2 on a control character, an `action=` holding
  one makes the marker malformed). *Why not* refuse in the helper: a stray newline would cost the stop its `LINE=`,
  and arm is fail-open by design.
- **Arm is the turn's last tool call — after the log line, the lock release and every other call of the stop** (review
  R1-1, fixed in-phase): each call after the arm moves the count, and the stop's own answer would then pass unguarded.
- **Harness flake fixed in passing**: `test-cache-guard.sh`'s `stamp()` gave `touch -t` minute resolution, so the
  "tap 240 s old → block" fixture aged past `STALE_S` (300 s) on a late second; the stamp now carries seconds.
- **Phase 5: `[W]` on automated evidence; the human test is dropped** (user). Evidence: the verify block's harnesses
  plus `test-toolchain-check.sh`, and a semi-live probe — `arm` against the session's real tap recorded `requests=40`;
  the working-tree hook under `/bin/bash` 3.2.57, fed the live tap with only `expires_at` forced into the past, blocked
  at 41 (reason led by the action) and passed at 42. Unshown: a real idle-hour block, the count at hook time, and the
  changed `execute.md` prose at runtime (no `--plugin-dir` probe; Phase 8's scenario walk-through covered it).
- **Review round 1** (one Heavy, three Light): R1-1 (arm order, Heavy · Local), R1-2 (Held-at-start wording) and R1-3
  (an apostrophe in `--action`) fixed in-phase; R1-4 a follow-up.
- Phase 7 skipped (project rule).

## Commits

- `532a935` — feat(cache-guard): block only the stop's own answer, name the human's step first
- `63c49fe` — feat(execute): arm the cache guard last, with --action at a2's human stops
- `1bc0979` — docs(design): record slice-070 in the cache guard's as-built notes
- `c93b2fe` — docs(roadmap): slice-060 follow-ups shipped with slice-070, part B dropped

## Follow-ups

- R1-4 Light · Rethink · R1-2 of slice-060 is covered for a2 only: other stops after the lock also need a human step before the re-run (step-1c conflict, a held slice, an a3 landing failure, an a5 merge conflict or failed gh pr create) and still arm with the plain restart
