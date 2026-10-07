# Slice 068 — b25-epic-close-pr-path

> Completed: 2026-10-07
> Commits: 3ae7050..911aad7 (branch only — epic-004-roadmap-fixes, no PR)

## What

Under `Merge → Type: pull-request` with `Protected-main: yes`, `/craft:commit`'s Epic-close mode now closes a finished epic instead of stopping at `STATE=pr-path` / E3 with "close it by hand". It runs in two passes. The first commits the epic's decisions, its archive and its plan's removal on the branch whose PR carries them — the epic branch a5's PR left open, or a close branch `<epic-id>-<slug>-close` with its own PR for a sequential epic and for an autopilot epic whose PR merged first — and sets the epic plan to `awaiting-approval`. The second pass, after the GitHub approval, merges with `gh`, syncs the trunk with `plan-landing.sh sync` and deletes the branch. `epic-close-state.sh` reads an epic plan at `awaiting-approval` as the new `STATE=closing`, and a `PR #<N> opened` epic whose branch the trunk now holds as `closable`.

## Why

- The archive and the plan removal cannot be committed on a protected trunk, and Epic-finalize already has the two-pass shape (D37 named it for this path).
- Everything the passes run is reused by delegation: Step 6's first and second invocation, `plan-landing.sh close --keep-copy` and `sync`, Step 7b.
- The close rides on the open epic PR so the record reaches the trunk with the one approved merge; where no open PR exists the close opens its own. D39 banks it. a5's PR hand-over now says to run `/craft:commit` before approving, because a push after an approval can dismiss it.

## Decisions

- **The close opens its own PR when no open PR can carry it** (human at the plan gate): a sequential epic, or an autopilot epic whose PR merged first, gets `<epic-id>-<slug>-close` cut from the synced trunk. *Why not* only the epic branch: no open PR exists to ride on in those cases.
- **The autopilot epic's close rides on its open epic PR** (the entry's intent); the first pass runs on the branch the close rides on and does not switch branches itself.
- **The second pass reuses Step 6's second invocation and `plan-landing.sh sync` unchanged** and is detected by the epic plan's `Status: awaiting-approval`, as Epic-finalize does; it asks no E4 question (the first pass asked) and deletes the branch `gh pr view` names.
- **A PR-path epic whose branch is merged into the trunk reads `closable`**; a merged PR whose branch is gone reads `closable` / `deleted` through GitHub's `Merge pull request #<N> from …` subject next to a5's `Merge <epic-id>: …`. Another PR's number does not count. A squash or rebase merge leaves neither proof and stays at `pr-path`; E3 names that limit.
- **The close is meant to run before the approval:** a5's PR hand-over says so; a first pass that finds the PR already `APPROVED` says, in one line before it pushes, that the approval may be asked for again; the second pass re-reads `reviewDecision` as Step 6 always does.
- **One `craft:writes status=awaiting-approval` marker per command** (`test-workflow-status-graph.sh` fails on a second one): Epic-close delegates to Step 6's first-invocation item 3, and the harness pins the delegation and the marker count of one. This replaces the plan's pin "Epic-close carries the marker".
- **`pr-path` lines carry `BRANCH=`** so Mode Detection and E3 match the line to the current branch without deriving the name. Step 0 also runs on `epic-<NNN>-<slug>` and `epic-<NNN>-<slug>-close`. The close branch name matches the autopilot epic-branch pattern; Epic-close tells them apart by state.
- **`> Merge:` has four values, defined once in Step 5** (review round 2): the PR-merged value `<hash> (<its subject>)` is found by the branch tip, or, the branch deleted, by GitHub's merge subject.
- **Review round 1 (1 Heavy, 10 Light, all local; 5 fixed in-phase, then the cap):** R1-1 (Heavy) an epic whose merge the helper could not prove looped between two wordings — the helper now also accepts GitHub's merge subject for an existing branch, E3 and the state row name the squash limit; R1-2 a `grep -q` early exit under pipefail made a match read as none; R1-3 the merged local epic branch is deleted by the second pass too; R1-5 the untracked-plan warning and the three branches the second pass runs on; R1-6 a resumed first pass reuses an open close PR.
- **Review round 2 (the human ran an interactive `/craft:review`, fix cap waived):** R1-4, R1-7 to R1-11 and the new R2-1 fixed in-phase — the fourth `> Merge:` value moved to Step 5; E3 names an outcome for a `headRefName` that differs from `BRANCH=`; a close PR closed without merging gets a named way out; Autopilot Mode is narrowed against Epic-close; D39's Amends line names D37's first bullet; CLAUDE.md's harness block names GitHub's merge subject; the check for an existing close branch runs in E3, before E4. The six earlier lines read `resolved in round 2`, not re-verified by a reviewer.
- **Proposed `rules.md` wording, not applied by the builder** — carried into the epic's decisions: Workflow Rules' harness entry for the epic close reads *Plus `bash scripts/test-epic-close-state.sh` (slice-061, slice-062, slice-068) — whether `/craft:commit` may close a finished epic (autopilot or sequential) and whether its close is already in flight (`closing`): the helper `epic-close-state.sh` against real git fixtures, the epic archive template, and the sites in `commit.md` (both passes of the PR path, the close branch) / `execute.md` a5 and s5.* The harness count does not change.
- **No `CHANGELOG.md` entry** (human at the plan gate) — the 2.0.0 cut writes them.
- Phase 7 skipped (project rule)

## Commits

- `3ae7050` — feat(epic-close): read a close in flight and a merged PR-path epic as states
- `55f209f` — feat(commit): close a finished epic on the PR path in two passes
- `911aad7` — docs(roadmap): bank D39, close B25 and update README, docs site and CLAUDE.md

## Follow-ups

- A human test of the real GitHub effect — a scratch repo with a protected trunk: a5's PR, `/craft:commit` on the epic branch, approve, `/craft:commit` again — is owed before 2.0.0 (roadmap, B25 note).
- A PR merged by squash or rebase leaves no merge commit for the helper to read; the mode cannot close such an epic and says so (E3). Record it by hand.
