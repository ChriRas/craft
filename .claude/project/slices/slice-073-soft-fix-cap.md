# Slice 073 — soft-fix-cap

> Completed: 2026-10-08
> Commits: ef15480..c14bc5b (branch only — epic-005-comfort-and-flow, no PR)

## What

The review's in-phase fix cap (`Review in-phase fix cap`, default 5) is now a guide value. Once a round reaches it with
local-edit findings still open, `/craft:review` keeps fixing the findings that are small (one file, about 20 lines, no new
behavior, no interface / contract / test-expectation change, tests green) up to a hard ceiling of twice the cap. Each such
fix resolves `fixed in-phase: over the guide value — <why small>`, the round carries a `- note · fix cap (<N>) exceeded`
line, and the bundle reports the overrun. Findings that are not small, or beyond the ceiling, take the old route.

## Why

- The cap was soft only interactively: the human waived it again and again for rounds of seven to nine small fixes, and
  in Subagent Mode (every autopilot run) nobody could waive it, so the rest was recorded `open — fix cap, awaiting
  decision` and the run stopped.
- D41 keeps the bound on the unreviewed delta (the ceiling) but stops asking when the fix is plainly small.

## Decisions

- **D41 banked** (2026-10-08) — guide value + `2 × cap` ceiling + small-fix criteria; see `brainstorm-decisions.md`.
- **Ceiling at twice the guide value** (2026-10-08, human choice over "none" and "cap + 3") — keeps the unreviewed-delta
  bound and covers the observed rounds of seven to nine fixes.
- **Interactive mode continues and reports** (2026-10-08, human choice over "ask by click") — one rule for every mode.
- **No parser change** (2026-10-08) — `review-findings-state.sh` already skips `- note · …` lines and reads a resolution's
  note after `: `; the new record is `fixed in-phase` + note, so only a harness case is added. The note must not contain
  ` · ` (it would become the last field → `MALFORMED`).
- Phase 7 skipped (project rule)
- **Scope** — the debug loop's *Max attempts* and the review round cap stay as they are (epic-005 decision).

## Commits

- `ef15480` — feat(review): make the in-phase fix cap a guide value with a 2x ceiling
- `f302d00` — test(review): cover the over-the-guide-value findings record
- `c14bc5b` — docs(review): describe the fix cap as a guide value in the docs page and changelog
