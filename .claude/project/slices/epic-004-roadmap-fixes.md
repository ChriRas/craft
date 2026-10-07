# Epic 004 — Roadmap Fixes

> Completed: 2026-10-07 (started 2026-10-07)
> Slices: 6/6 landed · one autopilot run on epic-004-roadmap-fixes, merged into main on the human's yes
> Merge: 4fd6408 (Merge epic-004: Roadmap Fixes)

## Vision

The roadmap has accumulated six small fix items (B5, B15, B17, B20, B25, B27) — follow-ups from slice-039, -050,
-061/-062 and -063 and from the toolchain work that each close a known gap in an already-shipped capability. This epic
clears them in one autopilot run, so the backlog holds only features, design work and the one deliberately deferred
fix afterwards. End state: every listed fix has landed on `main` with its harness green, the roadmap's rows for them
are gone, and the known limits the archives name for them are closed or explicitly re-banked. Scope edges: no features
(F3, F5, F7, F8), no design work (D2), no B18 (still deferred until a real run shows a repeating question), and no
release — the 2.0.0 cut stays the user's call. A fix that turns out to need a design decision stops as `NEEDS-HUMAN`
instead of growing.

## Slices (6/6)

- [slice-064 — b5-toolchain-polish](./slice-064-b5-toolchain-polish.md) — `/craft:prime` shows an older hook bash as an informational `·` line, and the status-graph harness's guard stops only for a too-old bash.
- [slice-065 — b17-subdir-settings-verdict](./slice-065-b17-subdir-settings-verdict.md) — the settings helpers report the `GITIGNORED=` verdict for the repo-root `settings.local.json` they actually write, also in a subdirectory project.
- [slice-066 — b20-checkpoint-record-delete-safe](./slice-066-b20-checkpoint-record-delete-safe.md) — parallel mode's review-checkpoint record is append-only state, hidden by a nested `.gitignore`, so no removal command meets a user's file-removal rule.
- [slice-067 — b15-parallel-plan-roundtrip](./slice-067-b15-parallel-plan-roundtrip.md) — a slice run in a worktree can be landed from start to finish: the plan is handed in, the slice's work committed, the plan read back and released.
- [slice-068 — b25-epic-close-pr-path](./slice-068-b25-epic-close-pr-path.md) — Epic-close closes a finished epic under pull-request + Protected-main in two passes, on the epic's open PR or its own close PR.
- [slice-069 — b27-a1-briefing-helper](./slice-069-b27-a1-briefing-helper.md) — the autopilot's run-start briefing is printed by `autopilot-briefing.sh` and only relayed by the master.

## Epic Decisions

- **Scope = the roadmap's Fix rows minus B18** (2026-10-07) — B18 stays deferred: slice-049 tied it to a real autopilot run showing a repeating handoff question, and that has not happened. Features, design items and the 2.0.0 release are out.
- **The run uses a frozen plugin runtime** (2026-10-07) — the autopilot ran with `--plugin-dir` on a git worktree of `main` at the epic's start commit, outside this repo: B27 and B15 change `commands/execute.md` and the slice-builder the run itself executes, so a live plugin dir would have rewritten the master mid-run, and the installed 1.7.0 lacks slice-060 to slice-063. That worktree, `CRAFT-runtime-epic-004`, is still there.
- **Order: small and independent first, autopilot internals last** (2026-10-07) — B5, B17 and B20 touch nothing later slices depend on; B20 precedes B15 because both change parallel worktree mode; B25 and B27 change the epic-close and autopilot paths last, so the run's own machinery stayed as planned for as long as possible.
- **Verification limits** (2026-10-07) — B25's PR path needs a real GitHub approval under protected main and B15 a real parallel worktree run; neither can be shown by a command inside an autopilot run, so both stay owed as human tests.
- **Promoted to `rules.md`** (2026-10-07, `[R]`) — the harness count reads twenty-four; the entries for `test-toolchain-check`, `test-readonly-context`, `test-execute-resume-state` and `test-epic-close-state` name what slices 064, 065, 067 and 068 added; `test-plan-roundtrip` and `test-autopilot-briefing` are listed.
- **Promoted to `intent.md`** (2026-10-07, `[I]`) — only an epic worktree is still created from a base that holds its plan byte-identical; a slice's plan is handed into its worktree and read back since slice-067.
- **Open follow-up from slice-064 (R1-5)** (2026-10-07) — the slice-064 entry in the epic's decomposition stated R3 inverted; the epic plan closes with it. Kept as a note, the slice's own archive holds the follow-up.

## Open follow-ups

- Owed before 2.0.0: a human test of slice-067's real parallel worktree run (`/craft:execute <slice>`, then `/craft:commit`) and of slice-068's real GitHub effect (a scratch repo with a protected trunk) — see the roadmap's B15 and B25 notes.
- slice-067: Epic-finalize with N read-back slices, `/craft:abort` and `/craft:worktree-clean` on a worktree holding the handed-in plan, the epic line's `plan_not_committed`, and the `.primed` seed below a subdirectory project's prefix — named in the roadmap's B15 note.
- slice-068: a PR merged by squash or rebase leaves no merge commit for the helper to read; Epic-close cannot close such an epic and says so.
- slice-069: the master's relay of `autopilot-briefing.sh` at a1 and the plan gate is shown by no command; the next autopilot run on a runtime that carries it shows it.
- Not an epic item, raised during the run: a handoff marker that an interactive `/craft:review` resolves is left behind when the slice is then landed, and holds the next slice's builder (`handoff-marker-state.sh` reads it `LIVE` / `plan_not_found`). Whether `/craft:commit` should rename it when it closes the plan is a design question.
