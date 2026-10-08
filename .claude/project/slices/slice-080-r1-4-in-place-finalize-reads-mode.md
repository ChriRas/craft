# Slice 080 — R1-4: In-place-finalize reads the mode and the start branch

> Completed: 2026-10-09
> Commits: b9f4613..59bb6f2 (direct on main, no PR)

## What

A slice built in place on its own branch is now always merged into `main` by `/craft:commit` and its branch deleted —
also while another CRAFT worktree exists beside it. Before, the merge silently fell away in that case while the plan
was still closed and the slice archived. Follow-up R1-4 of slice-079.

## Why

- The same pattern as A6 in slice-079: whether a run is an in-place slice is in the detected mode, not in a worktree
  count.
- A second gap came with it: under protected main the sync has already moved the checkout to the trunk when Step 7 looks
  at "the current branch", so read literally the branch delete fell away there. Mode Detection therefore holds the
  branch the run started on (`<start-branch>`), and Step 7 reads that.
- Walk-through: `/craft:commit` starts on `slice-001-add-world`; Mode Detection holds it as `<start-branch>`, step 2
  names `slice-090-x` as no finalize target and the mode stays Standard. Tests, commits and the archive run as usual. In
  Step 7, In-place-finalize sees Standard mode and a start branch that is not `main`: it checks out `main`, merges
  `--no-ff`, deletes the branch and then closes the plan. The Phase-5 probe showed exactly that (by `git log` and
  `git branch`). Review round 1 made the commands name `<start-branch>` itself (custom branch patterns), an empty start
  branch (detached HEAD) never fire, and a failing merge stop before the plan is closed.

## Decisions

- **In-place-finalize reads the detected mode and the start branch** (user, Phase 3): it lands the branch when Mode
  Detection found Standard mode and `<start-branch>` is not the trunk. *Why not* only swap `CRAFT_COUNT=0` for the mode:
  under protected main the second pass's `plan-landing.sh sync` has already checked out the trunk when Step 7 reads "the
  current branch", so the `git branch -d` was skipped there. The start branch removes both gaps at once.
- **The same pattern as A6 (slice-079)**: the mode decides, never a worktree count of the step's own. Finalize modes are
  excluded because they are not Standard; the autopilot epic branch stays excluded by its own sentence.
- **A probe, not only pins** (user, Phase 3): the change is command prose; the probe's verdict came from git (the merge on
  `main`, the branch gone).
- **Phase 5 probe results beyond this slice**: (1) A4 ran in the full run (`true && echo tests-green`), so slice-079's
  observation was an artefact of A6 stopping first — no follow-up needed. (2) The closing output said "Co-Authored-By:
  off, per your profile and global rules", although `/craft:commit` Step 2 requires the omitted trailer to stay
  unmentioned (human test T2) — a candidate follow-up for the roadmap.

## Commits

- `b9f4613` — fix(commit): land in-place slices by the detected mode and start branch
- `59bb6f2` — docs: record slice-080 in CLAUDE.md, rules, roadmap and the docs site

## Follow-ups

- R1-4 Light · Rethink · no post-assertion checks an in-place landing (P6 covers the finalize modes only), so a later edit that skips the merge again would pass silently; only wording pins guard it
