# Slice 067 — b15-parallel-plan-roundtrip

> Completed: 2026-10-07
> Commits: 70e74b0..756f81f (branch only — epic-004-roadmap-fixes, no PR)

## What

A slice run in a worktree can now be landed from start to finish. `/craft:execute` copies the main checkout's plan into every worktree it creates (`plan-roundtrip.sh in`), commits the slice's work on its branch when the builder reports `committing`, copies the finished plan back to the main checkout (`back`), and `/craft:commit` releases the handed-in copy (`release`) before `git worktree remove`. A slice's plan no longer has to be committed; `plan_not_committed` is an epic-line reason only.

## Why

- Parallel worktree mode could not complete: the plan status was written only into the worktree copy, so `/craft:commit` never detected a Slice-finalize (roadmap B15, slice-039 R2-7).
- A never-committed plan stopped at `plan_not_committed`, and the handed-in copy would block `git worktree remove`.
- Nothing ever committed inside a slice worktree, although three documents promised it; the plan gate's `[R]` round widened the slice to close that commit gap.

## Decisions

- **The orchestrator commits, in `/craft:execute` step 6, at Level 2 without a message edit.** What is committed is decided by `tree-dirt-state.sh --scope slice-worktree` (the one definition of the slice's work); the split and messages follow `/craft:commit` Steps 1–3 as its Autopilot Mode applies them. No commit, or no commits ahead of the base, is a Failure.
- **Commit before read-back before the checkpoint**, so a checkpoint's recorded tip is the slice's committed work.
- **A record guards both directions.** `<worktree>/.craft/plan-roundtrip` holds the hashes of the last hand-in or read-back and hides itself through `.craft/.gitignore`, as slice-066's record does. `back` conflicts (`main_changed`, a missing record, another Slice-ID) write nothing; a main plan identical to the worktree's reads `unchanged`.
- **A closed copy hides itself through `.closed/.gitignore` = `*`** when git does not already ignore it there, so a move-mode close leaves nothing git sees.
- **The hand-in replaces `plan_not_committed` for slice lines.** The guard's purpose (no stale plans in a worktree, slice-039 R1-1) is served by copying the live plan; plans stay "excluded, not ignored or tracked". *The epic line keeps `plan_not_committed`:* the epic plan's worktree copy is the one `plan-landing.sh close` acts on under protected main.
- **Read-back on Success only; `/craft:execute` reads back, `/craft:commit` does not.** The worktree plan stays the truth while a slice is in flight. No `craft:writes` marker: the graph already holds the transitions.
- **New helper with its own harness** (helper-plus-harness convention). *One slice, not split* (human, `[R]` round).
- **Build-time additions, beyond the plan's literal text:** `release` hides every CRAFT file left in the worktree (seeded `.primed`, a session's `.hook-env`, a resolved handoff marker under `.craft/`), only once the release goes through; `tree-dirt-state.sh --scope slice-worktree` excludes the whole local-state list at the worktree root, otherwise step 6 would commit a `.hook-env`; `in` refuses to overwrite a plan copy that is not the worktree HEAD's version when there is no record, and step 5 hands the plan in on a reused worktree without one.
- **Review round 1 → loop-back to Phase 4** (autopilot rule, one autonomous loop-back per finding): R1-1 (Heavy, rethink) — `git worktree remove` still refused after a real Phase-5 handoff, because the renamed `.craft/handoff-resolved-*.md` and `.hook-env` stay visible to git in subdirectory projects and in root projects without the CRAFT block. R1-2 (Heavy, local, fixed in-phase): step 5 handed the plan in only on `ACTION=create`. R1-3 to R1-6 fixed in-phase; R1-7 rode along on the fix cap. Round 2: all seven hold; R2-1 to R2-3 fixed in-phase.
- **No `CHANGELOG.md` line** (human, `[R]` round) — the 2.0.0 cut writes them.
- **The human test runs after the epic** (epic Decisions → *Verification limits*): the destructive worktree path is shown by real-git fixtures, a real parallel run following the new prose is not.
- **Promotion note:** `intent.md` → *CRAFT's own files are not the human's work (slice-039)* says a worktree is created only from a base that holds its plan byte-identical; since this slice that holds for the epic plan only. Recorded `[K]`; carried into the epic's decisions with the proposed `rules.md` wording (harness count, `test-execute-resume-state.sh` entry, new `test-plan-roundtrip.sh` entry).
- **Out of scope, named as follow-ups (roadmap B15 note):** (2) Epic-finalize with N read-back slices: `/craft:commit` A1 accepts exactly one plan at `committing`, so a parallel epic with N read-back slices still aborts at A1; a real parallel epic run reaches its merged epic branch but not yet its Epic-finalize. (3) `/craft:abort` and `/craft:worktree-clean` still refuse a worktree that holds the handed-in plan (known limit). (4) the epic line's `plan_not_committed`. (5) step 5 seeds `.primed` at the worktree root, not below a subdirectory project's prefix.
- Phase 7 skipped (project rule)

## Commits

- `70e74b0` — feat(execute): hand a slice plan into its worktree and read it back
- `01aeb08` — feat(execute): commit slice work in the worktree and route the plan round trip
- `756f81f` — docs(roadmap): close B15, add the round-trip harness to CLAUDE.md and the docs site

## Follow-ups

- Epic-finalize with N read-back slices (A1 accepts one plan at `committing`), `/craft:abort` / `/craft:worktree-clean` refusing a worktree that holds the handed-in plan, the epic line's `plan_not_committed`, and the `.primed` seed below a subdirectory project's prefix — named in the roadmap's B15 note.
- A hands-on human test of a real parallel `/craft:execute <slice>` followed by `/craft:commit` (destructive worktree path) is owed after the epic.
