# Slice 066 — b20-checkpoint-record-delete-safe

> Completed: 2026-10-07
> Commits: 38eaae4..f1aad84 (branch only — epic-004-roadmap-fixes, no PR)

## What

Parallel mode's review-checkpoint record `<epic-worktree>/.craft/checkpoints.md` is now append-only state. `/craft:execute` step 9 no longer deletes a merged slice's lines, the file or `.craft/`, so a user rule that denies or asks on removing files never meets the record (D34). Step 9 also writes a two-line `.craft/.gitignore` (`/.gitignore`, `/checkpoints.md`) next to the record when it is missing, so git hides both and `git worktree remove` of the epic worktree still succeeds and takes the record with it.

## Why

- Step 9 told the agent to delete the record after the merge so that no untracked leftover would block `/craft:commit`'s `git worktree remove`; on a machine with a deny / ask rule on `rm` that removal was refused or prompted (slice-050's follow-up, B20).
- Keeping the record as state and hiding it from git makes the removal unnecessary.

## Decisions

- **Keep the record as state rather than close it through `close-file.sh`** — D34: state lives in content, not in a file's existence; the record lives as long as the epic worktree. *Why not* `close-file.sh`: it refuses paths outside `--project` and the epic worktree sits outside the main checkout; widening its path contract for a file that dies with its worktree is not worth it.
- **The record hides itself through a two-line `.craft/.gitignore`** — verified 2026-10-07 on git 2.55.0: an untracked record makes `git worktree remove` fail (exit 128), an ignored one is removed with the worktree, the nested file leaves status empty even under a root `!.craft/` negation, other `.craft/` files still show, and an empty `.craft/` never blocked the removal. *Why not* `*` as the pattern: it would hide other `.craft/` files that must count as dirt. *Why not* `.git/info/exclude`: shared by every worktree and the user's clone, not CRAFT's to write. *Why not* moving the record into the worktree's git dir: too many sites change.
- **The self-ignore overrides a project's `!.craft/` negation for these two files only** — they are CRAFT's internal run state in the epic worktree; exposing them serves no project purpose.
- **The record becomes append-only; merged slices' lines stay** — they are inert (a merged slice never reaches step 9 again; slice-IDs are never reused).
- **`git worktree remove` taking the record with it does not go around a user rule** — D34 binds removals CRAFT issues; the worktree removal is git's, at the human-confirmed epic close.
- **No helper for the record** — a `scripts/checkpoint-record.sh` would grow a small fix into a new helper; the alternative if the human prefers "checked by command" here. The execute.md pin binds the prose's `.gitignore` lines to the fixture's.
- **No human test** — the destructive `git worktree remove` is unchanged and runs for real in the fixture. Unshown: the master following the new step-9 prose in a real parallel run.
- **Known limit:** a record a pre-slice runtime wrote and step 9 never reads again can still lack its `.gitignore` (checkpoint removed from `## Review Checkpoints` before the re-run); Epic-finalize's `git worktree remove` then fails as before, and `/craft:commit` surfaces it.
- **Review round 1 (three Light / Local findings, all fixed in-phase):** the delete-safe pin's verb check now crosses path dots; step 9 appends a missing line to an existing `.craft/.gitignore` (slice-067's `plan-roundtrip.sh` may write it first); the `!.craft/` negation fixture now holds `.craft/` then `!.craft/`.
- Phase 7 skipped (project rule)

## Commits

- `38eaae4` — fix(execute): keep the review-checkpoint record as state, hidden by a nested .gitignore
- `f1aad84` — docs(roadmap): close B20 and update the harness notes in CLAUDE.md
