# Slice 078 — B33: epic close blocked by an unrelated worktree

> Completed: 2026-10-08
> Commits: b9f53d7..3030df0 (direct on main, no PR)

## What

`/craft:commit` is no longer thrown off by a worktree that belongs to no slice or epic: a closable epic is found as
Epic-close even with a detached or foreign worktree beside it (the `CRAFT-runtime-epic-004` case of the epic-005 close),
and the protected-main guard A6 fires again. Foreign worktrees are not swallowed silently — each is named in one `·` line.
Which linked worktrees are CRAFT's is decided once, by `scripts/worktree-kinds.sh`; `/craft:commit` Mode Detection steps
0 and 1, A6 and Step 7's In-place-finalize, and `/craft:execute` P5–P7 read its `CRAFT_COUNT=`.

## Why

- Three sites in `commit.md` and three post-assertions in `execute.md` each asked on their own whether only the main
  worktree exists, and every answer counted *any* worktree, not CRAFT's. At the epic-005 close (2026-10-08) a detached
  worktree kept a closable epic out of Epic-close, and `/craft:commit` answered with A1/A2's slice messages; under
  protected main the same worktree switched A6 off.
- Following "prose is not checkable", one helper decides and the commands read only its count. The rule — a branch
  carrying a `slice-<NNN>` or `epic-<NNN>` token is CRAFT's — holds for custom branch patterns too, and "foreign" is the
  safe direction at every reader: Epic-close still checks that everything landed and merged, A6 stops rather than waving
  a commit through.
- Walk-through: before Mode Detection's step 0 the helper prints one `KIND=craft|foreign` line per linked worktree and
  `CRAFT_COUNT=`; the command names each foreign one. With `CRAFT_COUNT=0` and no slice at `committing`, step 0 asks
  `epic-close-state.sh`, which reads `closable`, and Epic-close takes over. A helper that gives no answer stops the
  command before any write.

## Decisions

- **Ignore and name, never stop** (user, Phase 3): a foreign worktree is ignored and named in one `·` line. *Why not*
  stop: the human would have to clean up something CRAFT does not own; silently ignoring would hide it.
- **A6 is in scope** (user, Phase 3): it used the same "only the primary worktree" predicate; with a foreign worktree
  present A6 did not fire, and a Standard commit landed on a protected trunk that cannot be pushed — a silent failure of
  the same class as B33, so one definition serves both sites (and step 1).
- **A helper decides, not prose** (user, Phase 3): the classification lives in `scripts/worktree-kinds.sh` and is shown
  by real git fixtures; the commands only read its counts (intent.md → "Prose is not checkable").
- **The classification rule**: a worktree is CRAFT's when its branch carries a `slice-<NNN>` or `epic-<NNN>` token — the
  ID `<slice-id>` puts into every branch, so a custom `Branch name pattern` (`feature/slice-012-x`) still counts.
  Detached worktrees and other branches are foreign. **Known limit:** a branch pattern without `<slice-id>` makes its
  worktrees read foreign.
- **Foreign is the safe direction at every reader**: step 0's `epic-close-state.sh` still requires every entry landed and
  the epic branch merged; A6 fires rather than steps aside; step 1 falls to Standard mode, where A3 or the human-reviewed
  split stops it. A slice worktree caught detached (mid-rebase) therefore errs safe.
- **A helper of its own, not a mode of `epic-close-state.sh`** — A6 and step 1 have nothing to do with epics.
- **Scope widened to `execute.md` P5–P7** (user, Phase 4): the post-assertions of the in-place, sequential and autopilot
  runs used the same predicate and warned falsely with a foreign worktree. They read the helper now; the harness pins
  them and holds the old predicate out of both command files.
- **The helper's failure stops `/craft:commit`** before any write: without its answer neither the mode nor A6 can be
  judged (doubt means stop). Step 0's own `epic-close-state.sh` failure still goes on with step 1, as before.

## Commits

- `b9f53d7` — fix(commit): judge worktrees through worktree-kinds.sh
- `3030df0` — docs(roadmap): close B33 and add the worktree-kinds harness to CLAUDE.md, rules and the docs site

## Follow-ups

- R1-2 Light · Rethink · A6 steps aside for any CRAFT worktree (CRAFT_COUNT above 0), not only a finalize target, so under protected main a not-ready slice worktree still lets a hand-built Standard commit land on the trunk; pre-existing (the old predicate was broader), the fix reorders A6 against Mode Detection steps 1/2
