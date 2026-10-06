# Slice 058 — Autopilot Budget Guard

> Completed: 2026-10-06
> Commits: faf2471..85f6f88 (branch only, trunk-based)
> Roadmap: F6 (epic-003, autopilot mode) — the budget half of `budget-and-cache-guard`; the cache guard is the epic's own `cache-guard` entry

## What

An autopilot run now watches the plan's usage windows. It starts a slice only while the 5-hour usage plus the forecast
(the mean of the slices landed so far, rounded up) stays within the profile's before-slice limit, a builder stops at the
next boundary of its spawn — a Phase-4 sub-task, a phase step, an autonomous debug attempt — at the in-slice limit or
when overage shows (a window at 99 % with the cache TTL at 5m), and no further slice starts past the weekly limit. Every
stop is one `⛔ … budget:` log line, and the stopped block says when to re-run: after the reset, at once (no reading),
after wiring the tap, or after fixing a failed check. Without a reading the run still works but stops after every
slice; a reading from before a window's reset counts as no reading. Before, an autopilot run could run blind into the
plan limit or into usage-credit billing.

## Why

- **No agent judges numbers in its head**: one helper, `scripts/usage-state.sh`, reads them and states
  `VERDICT=go|stop`, and the master and the builder act on that alone. A gate that cannot judge stops — the master's
  and, after review round 1, the builder's too: going on would switch the in-slice guard off unnoticed.
- **The in-slice stop lives in the builder**, because a master blocked on a foreground builder cannot watch anything,
  and it covers every boundary of the spawn, so D32's "stops immediately on the overage signal" holds at the next
  boundary (review R1-1).
- **A budget stop is Held, not a pause**: it waits for time, not for an answer, so a plain re-run resumes and the
  uncommitted work stays in the checkout.
- **What the master carries verbatim is checked by command** — the reading at the start, the Δ at the landing are
  checked by the helper (`--check-line`), not trusted (rules.md; review R1-3), and only a slice built start to end in
  one invocation gives a forecast sample (R1-16).
- **The limits live once**, in the helper's `DEFAULTS`; the profile templates, the defaults doc and the docs row are
  bound to it, README and docs prose point at the profile block. CRAFT ships the statusline tap but never writes the
  user's settings.

## Decisions

- **Split of `budget-and-cache-guard` (user, 2026-10-06):** this slice is the budget guard only; the `UserPromptSubmit`
  cache guard (design §7) is its own epic entry `cache-guard`. *Why:* two independent mechanisms, each testable on its
  own; the sensor alone would be a horizontal slice.
- **In-slice stop lives in the builder (user, 2026-10-06) — resolves the §9 Q8 consequence for the budget guard:** the
  `slice-builder` asks the helper at every sub-task boundary and stops there; D32 stays unamended. *Why not* stops
  between spawns only: a long slice could run past 95 % or into overage unchecked. Per-sub-task commits make the
  boundary a safe stop point.
- **Sensor = a shipped tap wrapper the user wires (user, 2026-10-06):** CRAFT ships `scripts/statusline-tap.sh`, which
  writes the tap and passes the JSON on to the user's own statusline command; CRAFT never writes the user's
  `statusLine` setting. *Why not* only read a configured tap path: every other user would have to build a tap.
  The documented path is the marketplace clone (`~/.claude/plugins/marketplaces/craft/scripts/`), not the installed
  cache — the cache directory is named by version, so a wired path would break on the next release.
- **Q6 resolved (user, 2026-10-06):** thresholds 85 (before) / 95 (during) / 90 (seven-day) in a new `## Autopilot`
  block of `craft-profile.md`, validated by `/craft:prime` 4d; the overage heuristic (≥ 99 % and TTL 5m) is fixed.
- **Tap, staleness, forecast (proposed by the agent in planning, confirmed by the user in review round 1, 2026-10-06):**
  the tap file is user-level (one per account, `rate_limits` are account-wide), not per project; a tap older than
  300 s is stale; the forecast is the mean of the epic's `Δ five_hour` samples, rounded up, and the first slice has
  none (forecast 0).
- **A budget stop is Held, not a pause (user, 2026-10-06, in build):** the builder changes nothing and reports
  `reason=budget`; a plain re-run resumes. *Why not* a pause with a new handoff status: it would touch the marker
  lifecycle table, its helper and harness, and make the human run `/craft:continue` before the re-run — for a stop
  that needs no answer, only time. *Correction:* the plan and design §6 said per-sub-task commits make the boundary
  safe; an autopilot builder never commits (`agents/slice-builder.md` → never `git commit`, `/craft:commit` lands at
  a3). The boundary is still safe: the uncommitted work stays in the checkout and step 1c accounts for it as the open
  slice's.
- **`cache-guard` is epic-003's first real autopilot run (user, 2026-10-06):** this slice is built by hand, because the
  budget guard it builds is not there yet to protect a run, and this repo's Phase-5 human tests (settings write) and
  two-pass review are not part of an autopilot run; `cache-guard` then runs under the landed budget guard.
- **Sensor schema read off a live tap (2026-10-06, Claude Code 2.1.289):** `rate_limits.{five_hour,seven_day}.
  {used_percentage,resets_at}` (epoch seconds), `prompt_cache.{ttl,expires_at}`; no `spend_limit` on this account —
  the helper must not require it.
- **Human test T1, wiring done by the agent on the user's request (2026-10-06):** `~/.claude/settings.json` backed up to
  `~/.claude/settings.json.bak-slice058-20261006-005037`, then `statusLine` given `refreshInterval: 30` and the tap
  chained in front of the user's own tap (`sh <repo>/scripts/statusline-tap.sh sh ~/.claude/statusline-tap.sh`).
  Claude Code picked the change up without a restart; the tap refreshed every ~20 s while the session sat in a
  blocking tool call, and `usage-state.sh` with no `--tap` read it (`MODE=normal`). **Follow-up after the release:**
  point the command at `~/.claude/plugins/marketplaces/craft/scripts/statusline-tap.sh` — the working-tree path is a
  test wiring.
- **Review round 1 → loop-back to Phase 4** (2026-10-06) — 1 Heavy + needs-rethinking finding (R1-1) routed to Phase 4 and
  the 14 local-edit findings plus three Light + needs-rethinking ones (R1-16, R1-17, R1-18) routed with it, none fixed
  in-phase; route chosen by the user.
- **A builder whose budget gate cannot judge stops (R1-17, in loop-back, 2026-10-06):** no `VERDICT=` → the same
  `reason=budget` stop with `budget check failed: …`, the master's rule. *Why not* go on: a builder-only failure would
  switch the in-slice guard off for every slice unnoticed. D32's "immediately" reads as the next boundary of the
  spawn — sub-task, phase step, debug attempt; nothing interrupts a running tool call.
- **Known gap carried over, not closed here:** whether usage-credit spend shows in `rate_limits`, and whether subagent
  requests move it at all (design §10) — the overage heuristic stays a heuristic; the strongest protection remains
  extra usage disabled in the account (a human action, named in the wiring docs).
- **Harness isolation fix found by Phase 9's A4 (2026-10-06):** `test-usage-state.sh`'s `chk()` did not pin
  `CLAUDE_PROJECT_DIR` (its `run()` did), so a caller that exports it — the context-mode sandbox — made the helper
  resolve the fixture epic plan against the real repo: 5 `--check-line` positives red (178/183). `chk()` now sets
  `CLAUDE_PROJECT_DIR="$P"`; 183/183 with and without a foreign value. The helper was right; only the harness leaked.

## Commits

- `faf2471` — feat(scripts): add the autopilot budget guard and its statusline tap
- `7567f9e` — feat(profile): add the Autopilot budget block
- `d414270` — feat(execute): stop autopilot runs on the usage budget
- `896bd87` — feat(prime): report the autopilot budget at session start
- `4e73886` — docs: document the usage tap and the budget guard
- `8273cc1` — docs(rules): add the usage-state harness
- `85f6f88` — docs(design): record the budget guard as built

## Follow-ups

- R2-11 Light · Rethink · a debug loop does not resume after a budget stop (ALIGN and PROTOCOL run again, Max attempts restarts) — a real resume touches slice-053's debug flow

## How (Diagram)

On every statusline refresh (every ~20–30 s with `refreshInterval`) Claude Code pipes the JSON into
`statusline-tap.sh`, which writes the tap `~/.claude/craft/usage-tap.json` first and then hands the same bytes to the
user's own statusline command — a statusline killed mid-command leaves no temp file. Before each builder spawn (a2)
the master runs `usage-state.sh --gate before`: the helper reads the tap, the profile limits and the `Δ five_hour`
fields of the epic's `## Autopilot Log`. A `stop` logs `⛔ · budget: …` and ends the run; a `go` logs the `▶` line with
the slice-ID and `five_hour <p> % until <HH:MM>` last, and `--check-line start` checks it at once. Inside the spawn
the builder runs `--gate during` at every boundary; a stop, or a gate that cannot judge, ends it with `reason=budget`,
and the master writes one `⛔` line and the stopped block. After the landing (a3) the master runs `--gate after --slice
<id>`: the slice's Δ comes from its `▶` line when it was created in this invocation, else `?`; the `✓` line carries it
last and `--check-line landed` checks it. a4 stops on `stop` with the *stopped after a landed slice* block, except after
the epic's last slice. `/craft:prime` 4d reports the limits and the usage, telling a missing tap from an old one.

```mermaid
flowchart LR
  SL[Claude Code statusline JSON] -->|every ~20–30 s| TAP[statusline-tap.sh]
  TAP -->|1. write first| FILE[(usage-tap.json)]
  TAP -->|2. same bytes| USR[user's statusline command]
  PROF[(craft-profile.md ## Autopilot)] --> HELP
  LOG[(epic ## Autopilot Log: ▶ start, ✓ Δ)] --> HELP
  FILE --> HELP[usage-state.sh]
  HELP -->|before| A2[a2 master: spawn or ⛔ budget]
  HELP -->|during, every boundary| SB[slice-builder: go on or reason=budget]
  HELP -->|after + Δ| A3[a3/a4 master: ✓ line, go on or ⛔]
  HELP -->|before| PR[/craft:prime 4d report]
  A2 -->|▶ line| LOG
  A3 -->|✓ line| LOG
  LOG -->|--check-line start / landed| HELP
```
