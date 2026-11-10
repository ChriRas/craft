# Slice 093 — budget guard: the last reading when the tap has none

> Completed: 2026-11-10
> Commits: 4347648..97dd44e (direct on main, no PR) · bugfix, built in a worktree on main during epic-006

## What

An autopilot run no longer stops after a slice only because the shared statusline tap holds no usage reading at that
moment. `statusline-tap.sh` now also keeps the last reading whose two windows each carry a numeric `used_percentage`
(`<tap>.last-reading.json`), and `usage-state.sh` falls back to it when the tap has none — at most 1800 s old, no window
reset since — judging it against a lower limit, `Budget-estimated` (default 80, never above `Budget-before-slice` /
`Budget-in-slice`), in every gate (`MODE=estimated`). With no usable reading at all the run still stops after the slice
and tells the human (`MODE=conservative`); exact readings keep 85 / 95 / 90.

## Why

- The tap is one file per user and every session's statusline refresh replaces it whole: a session without
  `rate_limits` (just started, just compacted) wiped another session's good reading, and epic-006's autopilot stopped
  twice on `usage unknown` with ample room in the window. High priority — it blocked the running epic.
- The user chose to go on with a margin rather than stop blind: 80 % lies far enough below 85 % that one slice on a
  slightly old reading does not overrun the window; the age and reset rules keep a reading from another window from
  standing in. Design record §6 is amended, not replaced — the conservative stop remains for no reading at all.

## Decisions

- **Fallback limit 80 % (user, 2026-11-10).** Without an exact reading the guard judges the last reading against
  `Budget-estimated` instead of stopping after every slice; no usable reading keeps the conservative stop, so the human
  is told. Review R1-1 added that it never exceeds the exact limits — a profile that lowers them lowers it. *Why not*
  stop as before: the stop was needless whenever another session had just blanked the tap.
- **The last reading is at most 30 minutes old and from the current windows (user, 2026-11-10).** Older, or a window
  reset since, is no reading. *Why not* the tap's 300 s: the point is to bridge another session's blank refreshes.
- **Built in a worktree on main and released (user, 2026-11-10).** The running autopilot executes the installed plugin,
  so the fix helps only once released; the epic-006 checkout stayed untouched. *Why not* on the epic branch: it would
  ship only with the epic.
- **The pre-existing model-enum failure is fixed here (user, 2026-11-10).** `.claude/project/craft-profile.md` carried a
  `craft:model-enum` marker since 90a92c5 without a `BOUND_FILES` entry; it is bound (`:1`) and seeded into the
  self-test fixture so the release ships with every harness green. *Why not* a slice of its own: a one-line binding.

## Commits

- `4347648` — fix(autopilot): judge the last usage reading when the tap has none
- `cd3fa67` — test(model-enum): bind the project's own profile
- `4b2aeb9` — docs: describe the estimated budget mode in the docs site, harness list and changelog
- `97dd44e` — chore(plans): bump slice counter to 94
