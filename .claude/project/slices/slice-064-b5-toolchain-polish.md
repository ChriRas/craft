# Slice 064 — b5-toolchain-polish

> Completed: 2026-10-07
> Commits: 9b81945..f029a8b (branch only — epic-004-roadmap-fixes, no PR)

## What

Roadmap B5 is closed. `/craft:prime` now shows a hook bash older than the Bash tool's as an informational `· Hook bash:` line, and the status-graph harness's toolchain guard stops a run only for a too-old bash, with a short focused message.

## Why

- Nothing CRAFT ships is affected by an older hook bash (hooks and their helpers are bash-3.2-compatible), so a permanent `⚠` for every desktop-app or IDE user was noise (R2).
- The guard ran the full toolchain helper and dumped its whole output, and stopped for a missing python3 although only an old bash gives the harness a cryptic parse error (R3).

## Decisions

- **R3 direction: bash-only guard** — the guard aborts only on `BASH=too-old` and still reads the minimum from `check-toolchain.sh`, as slice-033's archive (R3) and roadmap row B5 ask. The epic entry's line had it inverted. Source: the human at the plan gate.
- **No `CHANGELOG.md` `[Unreleased]` line, no rules.md edit by the builder, roadmap row closed in this slice** — human answers at the plan gate (P1-2, P1-4, P1-5). Proposed rules.md wording (not applied): the `test-toolchain-check.sh` parenthetical becomes `(bash/python3 requirement, OS install hints, hook bash — informational in /craft:prime —, the status-graph harness's bash-only guard)`.
- **Still call the helper, judge only `BASH=`** — a bare `BASH_VERSINFO` check would add a second copy of `5.0`. *Why not* parsing `BASH_MIN_MAJOR=` out of the helper's source or a hardcoded minimum: fragile, and a second copy.
- **python3 is out of the guard's scope** — a missing python3 shows a readable `python3: command not found`, and `/craft:prime` already aborts on it.
- **The remedy is relayed as the helper words it** — rewording `PATH_REMEDY` per caller would give one remedy two definitions; the guard drops only the key=value dump.
- **The guard stays fail-open when the helper cannot run** — unchanged; blocking a working bash-5 run would be a regression.
- **The line is always informational (R2)** — every CRAFT hook is bash-3.2-compatible (rules.md → Bash baseline, enforced by `test-toolchain-check.sh`); only other hooks could be affected. *Why not* a runtime condition keeping `⚠`: it would grow a cosmetic fix into a new check. The helper's contract (`STATUS=hook-mismatch`, exit 10) is unchanged.
- **`·` is the informational marker** — already used by prime's Output Format.
- **No headless prime probe in the verify block** — a nested session for a cosmetic line, and run from this repo it would un-prime the master. Known limit: prime's live rendering of `· Hook bash:` is pinned as prose only.
- **Mutation proof (run once at build, not kept)** — guard trigger back to `STATUS=missing-tools`: 64 passed / 1 failed; `⚠ Hook bash` back in `prime.md`: 63 / 2. Both restored.
- Phase 7 skipped (project rule)

## Commits

- `9b81945` — fix(toolchain): show a hook bash older than the Bash tool's as informational
- `883991b` — test(toolchain): stop the status-graph harness only for a too-old bash
- `f029a8b` — docs(roadmap): close B5 and name the toolchain guard in CLAUDE.md

## Follow-ups

- R1-5 Light · Local · the epic-004 decomposition entry still states R3 inverted (outside this slice's diff — the epic plan is the master's file). Suggested wording: "… and the status-graph harness guard stops only for a too-old bash, not for the full toolchain (R3)"; keep the `slice-064 — b5-toolchain-polish` prefix.
