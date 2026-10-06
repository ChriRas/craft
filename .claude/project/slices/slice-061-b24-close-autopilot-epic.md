# Slice 061 — b24-close-autopilot-epic

> Completed: 2026-10-06
> Commits: 76c5fa1..8da07db (trunk-based on main, no PR)
> Roadmap: B24 (shipped); follow-ups B25 (PR path), B26 (epic archive format) · Decision: D37

## What

An autopilot epic can now be closed by CRAFT itself: after a5's `[Y]` merged the epic branch (`direct`),
`/craft:commit` runs its new Autopilot-epic-close mode — it walks the epic decisions, writes and commits the epic
archive, closes the epic plan and deletes the merged epic branch. Until now a human did that by hand (epic-003).

## Why

- Under `pull-request` the merge happens on GitHub after a5, so a5 cannot close in every case; a `/craft:commit` mode
  reuses Epic-finalize's decisions walk, archive and plan closing by delegation instead of describing them twice (D37).
- Whether an epic is ready is derived, never stored, by one helper, `scripts/epic-close-state.sh`, and only a real
  merge commit counts as a merge — a branch without own commits is an ancestor of every trunk (the ancestor trap).
- The walk covers the epic's own decisions only; the PR path (B25) and a fixed epic archive format (B26) went to the
  roadmap.

### Walk-through

`/craft:commit` on the trunk finds no slice at `committing`, so Mode Detection step 0 runs the helper. It reads the
epic plan's `## Autopilot Log` (only the last `■` line counts, fences ignored), resolves every decomposition entry
through `epic-entry-link.sh resolve` and looks for the epic branch's merge commit on the trunk. At `STATE=closable` the
mode takes over: E1–E4 check the checkout, the target, the profile and the tree, name every other epic with its state
before anything is written, hold the resolved slice-IDs and resume at step 4 when an earlier close already committed
the archive; then Step 4 (walk), Step 5 (archive), Step 5b (its commit), the plan close through `close-file.sh`,
`git branch -d`, Step 7b — and the post-assertions check the archive against the held slice-IDs by `grep` and that
the helper no longer lists the epic. With no epic closable and no slice to commit, step 0 stops with the epics'
states instead of a slice message. a5's `[Y]` hands over with `Recommended next: /craft:commit`; a Standard-mode commit
that leaves a closable epic behind recommends it too.

## Decisions

- **Close lives in `/craft:commit`, not in a5** (user, 2026-10-06) — under `pull-request` the merge happens on GitHub
  after a5, so a5 cannot close in every case; a commit mode reuses Epic-finalize's Steps 4 / 5 / 7 instead of
  describing them a second time (tabu: a rule is never described twice). Banked as D37.
- **Closability is derived by a helper** (user, 2026-10-06; promoted to `intent.md` → Derived state over cleanup) —
  `scripts/epic-close-state.sh` with its own harness, not prose in Mode Detection: merged into the trunk and every
  entry landed (`epic-entry-link.sh resolve`), nothing stored. "Is an ancestor" alone is no merge; the helper uses
  `execute-resume-state.sh`'s rule — a merge commit with the branch tip as a non-first parent.
- **The walk covers epic decisions only** (user, 2026-10-06) — `## Decisions Made During This Epic`; the slice
  decisions the autopilot recorded as `[K]` stay in their archives (promotion stays open to the human by hand).
- **The merged epic branch is deleted with `git branch -d`** (user, 2026-10-06) — as Epic-finalize does; `-d` refuses
  an unmerged branch. A destructive git path, so Phase 5 requested a real human test for it.
- **`direct` only; the PR path goes to the roadmap** (user, 2026-10-06) — under `pull-request` + `Protected-main: yes`
  the archive commit may not land on the trunk directly; it would need Epic-finalize's two passes (archive into the
  open PR, `plan-landing.sh` sync after the merge). The mode stops there with a clear line; roadmap B25 carries it.
- **Not in this slice:** `/craft:prime` / `/craft:continue` recommending the close for a merged epic — a5's
  `Recommended next:` line is the one hand-over (plus R1-4's line after a Standard-mode commit).
- **Phase 5: `[W]`** (user, 2026-10-06) — on the evidence report (harnesses, three helper mutations that each turned
  the harness red, headless probe 1) plus the human test of the branch deletion: an interactive `/craft:commit`
  (`--plugin-dir` scratch copy) on a fixture with a closable epic-900 and a not-signed-off epic-901. Checked by git and
  files: walk with `[I]` rejected → `[K]`, intent/rules unchanged, one commit `docs(slices): archive epic-900 (Demo)`,
  plan moved to `.closed/`, `epic-900-demo` deleted with `-d`, `epic-901-open` untouched, helper afterwards
  `CLOSABLE_COUNT=0`.
- **E2 wording sharpened** (user, 2026-10-06, from the human test) — the session named epic-901 only in its closing
  summary, because E2 said "below the choice" and with one closable epic there is no choice. E2 now prints the other
  epics' lines before Step 1, in either case.
- **Epic archive format → roadmap B26** (user, 2026-10-06) — Step 5 defines the epic archive in one sentence and no
  template exists: probe 1 wrote no `## Commits`, the human test wrote them twice. Not this slice's scope.
- **Phase 8, one round, clear** (2026-10-06) — six Light + Local findings, all fixed in-phase (fix cap 5 waived by the
  user): step 0 stops itself instead of leaving the epic plan to A1/A2 (R1-1), a re-run after a part-way close resumes
  at step 4 (R1-2), P3 checks the archive against held `resolve` IDs by command (R1-3), a closable epic left behind by
  a Standard-mode commit is recommended (R1-4), a run stopped before a5 reads `not-signed-off / run_stopped` (R1-5),
  step 4's reason reworded (R1-6). Not shown by a probe after these fixes: step 0's stop and the resume path — read in
  the scenario walk-through only; the helper part (`run_stopped`) is in the harness.

## Commits

- `76c5fa1` — docs(decisions): bank D37 — closing an autopilot epic is a /craft:commit mode
- `fceaf2e` — feat(commit): close a merged autopilot epic (Autopilot-epic-close mode)
- `4e081f6` — docs: document the autopilot epic close
- `47be043` — docs(pages): document the autopilot epic close
- `4fa18ce` — docs(roadmap): ship B24, add B25 (PR path) and B26 (epic archive format)
- `8da07db` — chore(plans): bump slice counter to 62
