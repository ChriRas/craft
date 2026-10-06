# Epic 004 — Roadmap Fixes

> Status: planning
> Epic-ID: epic-004
> Epic-Slug: roadmap-fixes
> Started: 2026-10-07
> Phase: 3
> plugin-version: 1.7.0
> Handoff active: no

## Vision

The roadmap has accumulated six small fix items (B5, B15, B17, B20, B25, B27) — follow-ups from slice-039, -050,
-061/-062 and -063 and from the toolchain work that each close a known gap in an already-shipped capability. This epic
clears them in one autopilot run, so the backlog holds only features, design work and the one deliberately deferred
fix afterwards. End state: every listed fix has landed on `main` with its harness green, the roadmap's rows for them
are gone, and the known limits the archives name for them are closed or explicitly re-banked. Scope edges: no features
(F3, F5, F7, F8), no design work (D2), no B18 (still deferred until a real run shows a repeating question), and no
release — the 2.0.0 cut stays the user's call. A fix that turns out to need a design decision stops as `NEEDS-HUMAN`
instead of growing.

## Slice Decomposition

> Initial decomposition into vertical slices. Each entry is a candidate `/craft:plan`
> invocation later; treat the list as a roadmap, not a contract. Update as slices land.
> `/craft:plan` (or an autopilot run's planning stage) writes the slice-ID into an entry when it plans it — do not add or change it by hand. The entry
> format is defined by the CRAFT plugin's `scripts/epic-entry-link.sh`; `/craft:execute` A6 resolves entries through it.

- [ ] b5-toolchain-polish — the `⚠ Hook bash` line becomes informational when nothing is affected (R2), and the status-graph harness guard checks the full toolchain helper, not only the bash version (R3)
- [ ] b17-subdir-settings-verdict — settings helpers run in a subdirectory project report the `GITIGNORED` verdict for the repo-root `settings.local.json` they actually write (slice-039 R1-13)
- [ ] b20-checkpoint-record-delete-safe — parallel worktree mode keeps its merged-slice checkpoint record as state or closes it through `close-file.sh`, instead of removing it past a user rule on file removal (D34, slice-050 follow-up)
- [ ] b15-parallel-plan-roundtrip — parallel worktree mode hands the slice plan into the worktree and reads its status back, so `/craft:commit` detects a Slice-finalize (slice-039 R2-7)
- [ ] b25-epic-close-pr-path — Epic-close under `pull-request` + `Protected-main: yes` runs in two passes: archive + decisions into the open PR, then `plan-landing.sh sync` after the merge (D37 / D38)
- [ ] b27-a1-briefing-helper — the autopilot's a1 briefing block, "Stops for you at: …" included, is printed by a helper the master only relays, as `epic-digest.sh` does for a5

## Review Checkpoints

> Optional. Controls where `/craft:execute` pauses for human review during the
> autonomous run. Default: end-of-epic only.
>
> Each entry takes the form `- after slice-NNN` and pauses after that slice's
> Phase-7 self-review completes, before merging into the epic-branch. Once shown,
> `/craft:execute` records it in the epic worktree's `.craft/checkpoints.md`, and the
> next run merges instead of pausing again. Use sparingly — per-slice stops produce review fatigue.

- (none — review at end-of-epic only)

## Decisions Made During This Epic

> Architectural / product decisions that surface during epic shaping or while child
> slices execute. Each entry is walked with the `[K]/[I]/[R]/[D]` promotion dialog
> when the epic closes.

- **Scope = the roadmap's Fix rows minus B18** (user, 2026-10-07). B18 stays deferred: slice-049 tied it to a real
  autopilot run showing a repeating handoff question, and that has not happened. Features, design items and the
  2.0.0 release are out.
- **The run uses a frozen plugin runtime** (user, 2026-10-07). The autopilot runs with `--plugin-dir` pointing at a
  git worktree of `main` at the epic's start commit, outside this repo — not at this working tree (B27 and B15 change
  `commands/execute.md` and the slice-builder the run itself executes, so a live plugin dir would rewrite the master
  mid-run) and not at the installed 1.7.0 (it lacks slice-060 … slice-063: autopilot log, cache guard, Epic-close).
  The worktree is created when the run starts.
- **Order: small and independent first, autopilot internals last.** B5, B17 and B20 touch nothing the later slices
  depend on; B20 precedes B15 because both change parallel worktree mode (`commands/execute.md` step 9 and the plan
  round-trip); B25 and B27 change the epic-close and autopilot paths last, so the run's own machinery stays as
  planned for as long as possible.
- **Verification limits to expect at the plan gate:** B25's PR path needs a real GitHub approval under protected main
  and B15 a real parallel worktree run — neither can be shown by a command inside an autopilot run, so their plans are
  expected to carry a `NEEDS-HUMAN:` human-test item rather than a full verify block.

## Plan Review

> Appended by `/craft:execute <epic> --autopilot` (ap step 4b), one round per `plan-architect` review, one line per
> finding. Format and reader: `scripts/plan-gate-state.sh`'s header. Never rewritten but for a resolution.

(no plan review yet)

## UX Demo Script

> Appended by `/craft:execute <epic> --autopilot` (a3; the block format is defined there), one block per slice that
> landed — verified by command or passed by you. Walk it at the epic-end sign-off (a5): the product-feel check that
> verification by command does not replace (D35). Never rewritten.

(no slices landed yet)

## Autopilot Log

> Appended by `/craft:execute <epic> --autopilot`, one line per event (`▶` run, planning or slice started, `✓` landed on
> the epic branch or plan gate approved, `⛔` stopped for a human, `■` run ended). The run's durable record; never
> rewritten — `scripts/plan-gate-state.sh` reads the plan gate's approval line from it.

(no autopilot run yet)

## Recap Draft

> Filled when the epic closes. Becomes the basis for the epic archive entry.

(not yet recorded)

## Handoff

> Filled by `/craft:handoff` when context-poisoned. Read by the next session's
> `/craft:prime`.

(none)

## Pause Note

> Filled by `/craft:pause` when work pauses mid-phase.

(none)
