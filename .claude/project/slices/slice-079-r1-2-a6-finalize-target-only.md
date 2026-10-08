# Slice 079 — R1-2: A6 steps aside only for a finalize target

> Completed: 2026-10-09
> Commits: 42d3b87..6c36e02 (direct on main, no PR)

## What

Under protected main, `/craft:commit` now stops a direct commit on `main` even while a CRAFT worktree that is not ready
exists elsewhere — a slice still building, or a worktree an aborted slice left. The message names that worktree with its
branch and plan status, so it is clear why no finalize ran. Follow-up R1-2 of slice-078.

## Why

- A6 used to count worktrees: any CRAFT worktree made it step aside, although only a worktree that is actually finalized
  brings a branch of its own for the PR. Mode Detection already knows whether a finalize target exists, so A6 now reads
  the detected mode — as A3 already does; a second count would have described the same rule twice.
- Step 2 used to let a CRAFT worktree that is no target fall through silently; it now names it, in every profile.
- Walk-through: `/craft:commit` runs in a fixed order — the worktree helper and step 0 (Epic-close), then A0, then Mode
  Detection steps 1–2, which decide the mode, then A1–A6. Step 2 finds `slice-090-x` with its plan at `implementing`,
  names it "no finalize target — not finalized by this run" and the mode stays Standard. A6 sees protected main,
  Standard mode and the branch `main`, stops before any commit and repeats the worktree line. The Phase-5 probe showed
  exactly that: no new commit (`git log`), and the message names slice-090.

## Decisions

- **A6 reads the detected mode, not a worktree count** (user, Phase 3): A6 fires when Mode Detection found Standard mode
  and the current branch is the trunk, under protected main — the way A3 already reads the detected mode. Finalize modes
  are excluded because they are not Standard. *Why not* a count of finalize targets only: a second wording of step 2's
  judgment, a rule described twice.
- **The message names the worktrees that are no finalize target** (user, Phase 3): branch and plan status, so the human
  sees why no finalize ran.
- **Step 2's fall-through becomes explicit, in every profile** (user, Phase 3): "anything else" leaves the mode at
  Standard, and each CRAFT worktree passed over is named in one `·` line. Under `direct` this changes no outcome.
- **Order of the Pre-Assertions**: *Which worktrees count* and step 0, then A0, then Mode Detection steps 1–2, then
  A1–A6. A0 guards Mode Detection, and A3 / A6 read the detected mode, so steps 1–2 sit between them.
- **A probe, not only pins** (user, Phase 3): the change is command prose, so Phase 5 showed it with a headless probe whose
  verdict came from `git log` and the transcript; A6 stops before any push, so no `gh` or remote was needed.
- **Phase 5 probe observation (not this slice's change)**: the probe's agent listed A0–A3 and A5 as passed but ran no
  visible A4 test command before A6 stopped it — A6 stops before any commit regardless; whether `/craft:commit` skips A4
  when a later pre-assertion will stop is worth a look (candidate follow-up).

## Commits

- `42d3b87` — fix(commit): let A6 read the detected mode, not a worktree count
- `6c36e02` — docs: record slice-079 in CLAUDE.md, rules, roadmap and the docs site

## Follow-ups

- R1-4 Light · Rethink · Step 7's In-place-finalize still decides by CRAFT_COUNT=0, so under direct an in-place slice built on its branch while another CRAFT worktree exists skips the merge into the trunk while the plan is closed and the slice archived; pre-existing, outside this diff, likely rule "Standard mode and current branch is not the trunk"
- R1-5 Light · Rethink · A6 does not exempt Status awaiting-approval, so a protected-main second pass of an in-place lone slice run from the trunk (the human left the PR branch) is stopped although the PR exists; now also while another CRAFT worktree exists; recoverable by checking out the branch, A3 already gives awaiting-approval precedence, needs a decision
