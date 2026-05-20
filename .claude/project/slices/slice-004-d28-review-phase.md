# Slice 004 — Code Review Phase (D28)

> Completed: 2026-05-20
> Commits: 306c1e4 (main, no PR)

## What

D28 is fully implemented: the CRAFT workflow is now **nine phases**, with a standalone
**Review phase (Phase 8)** between Refactor and Commit (Commit moved to Phase 9). A new
`/craft:review` command runs an independent code review as a subagent with a fresh
context window — it classifies findings on a severity × fix-nature rubric, fixes
bounded local edits in-phase, escalates the rest, and gates Commit.

## Why

- Review sits *after* Refactor so it reviews the real shipped delta — an earlier
  review would be partly invalidated by the refactoring that follows it.
- The reviewer is a fresh-context subagent: independence comes from the clean window
  (four-eyes principle), not from withholding context. It is briefed with the
  Senior-Developer baseline, the stack-pack, the slice plan, prior decisions, the
  diff, and the Phase-6 Recap (the PR-description analogue).
- The 2×2 rubric separates two questions: severity decides whether a finding blocks
  Commit; fix-nature decides whether it is fixed in-phase or escalated. A soft cap
  guards against many small in-phase fixes summing to a large unreviewed delta.

## Decisions

- **Escalation mechanics** — findings go to a `## Review Findings` section of the
  slice plan. A Heavy + needs-rethinking finding is never auto-fixed; `/craft:review`
  recommends (Level 1) loop-back to Phase 4 or a new slice, and blocks Phase 9 until
  resolved.
- **Soft-cap settings key** — `## Self-Verification Settings` gains
  `Review in-phase fix cap` (default 5).
- **Findings / follow-up format** — `Severity · Fix-nature · description · resolution`;
  light + needs-rethinking follow-ups go into the slice archive's `## Follow-ups`
  section at Phase 9, not a separate global backlog.
- **Mid-flow invocability** — `/craft:review` is slash-invocable any time. As the
  Phase-8 step it reviews, fixes, and gates; invoked earlier it is advisory-only —
  findings, no fixes, no phase-state change.
- **Review-agent autonomy profile** — classifying = Level 3; in-phase fixes = Level 2;
  escalation and soft-cap breach = Level 1.
- **Status value for Phase 8** — Phase 8 uses `Status: reviewing`; the pre-existing
  `review` status (Phase-5-passed) is left untouched to avoid a risky rename.
- **slice-004 bootstrap** — the slice that introduces `/craft:review` was closed
  without a Phase-8 self-review (the command was not yet in the running plugin
  cache). Phase 8 takes effect for subsequent slices once the plugin is synced.

## Commits

- `306c1e4` — feat(workflow): add Review as Phase 8, shift Commit to Phase 9 (D28)

## Follow-ups

(none — no Phase-8 review ran on this bootstrapping slice)
