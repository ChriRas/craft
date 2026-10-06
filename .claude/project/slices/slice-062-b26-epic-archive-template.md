# Slice 062 — b26-epic-archive-template

> Completed: 2026-10-06
> Commits: 7001b75..9efb23b (trunk-based on main, no PR)
> Roadmap: B26 (shipped), plus the sequential epic's missing close; follow-up B25 widened · Decision: D38 (amends D37)

## What

Every finished epic can now be closed by `/craft:commit` — not only an autopilot epic, but also a sequential one and
one worked slice by slice by hand — and every epic archive CRAFT writes follows one template,
`templates/epic-archive.md.template`. Until now each run invented the archive's layout, which the first, accidentally
old interactive run of this slice's human test showed live.

## Why

- Both gaps had one cause: the epic archive was defined in one sentence, and the sequential epic had no close at all
  (D38).
- A template, not a generator — the three hand-written archives show an agent fills a template well; what was missing
  was the template.
- No copies: the commits appear once, in the frontmatter; the slices' follow-ups only by reference; P3 checks against
  the template's own headings; the content rules live in Step 5 only.
- One mode for both kinds, renamed Epic-close while that was still cheap (nothing released). A sequential epic has no
  explicit human signal like a5's `[Y]`, so the mode asks once, alone, before anything is written — and checks the
  profile before it asks.

### Walk-through

s5 (sequential) or a5 (autopilot) recommends `/craft:commit` — under `pull-request` + `Protected-main: yes` both say to
close the epic by hand through a PR instead (B25). Step 0 runs the helper; it reads the kind from the autopilot log's
presence (`KIND=`), and a sequential epic is closable when every entry landed and no unmerged epic branch exists
(`BRANCH_STATE=none` when there is none). E2 records the target and names every other epic with its state, E3 checks
the profile, E4 asks `Close <EPIC> … now?` alone, then holds the slice-IDs and resumes at step 4 when the archive is
already committed. Then the walk, the archive from the template (Step 5 defines every field, `> Merge:` one of three
values), its commit, the plan close and — if there is one — `git branch -d`. P3 checks every `## ` heading of the
template with `awk` and that the archive has no `## Commits`; a second closable epic is recommended at the end.

## Decisions

- **Template + check, not a generator** (user, 2026-10-06) — `templates/epic-archive.md.template`, referenced by
  Epic-finalize and Epic-close; P3 checks the template's headings by command, as the slice archive's P3 does. *Why
  not* a generator helper (`epic-digest.sh --archive`): larger, and the defect was the missing template, not the
  filling.
- **Commits in the frontmatter only** (user, 2026-10-06) — one `> Merge:` line, no `## Commits`; the per-slice commits
  live in the slice archives (as in epic-001…003). Fixes slice-061's human test writing them twice.
- **Follow-ups by reference** (user, 2026-10-06) — `## Open follow-ups` names only epic-level items and points to the
  slice archives; collecting them would be an unbound second copy (tabu).
- **The sequential epic's close joins this slice** (user, 2026-10-06) — found while planning: `execute.md` s5 reported
  "Epic complete" and released the lock, but nothing wrote the archive or closed the plan (epic-001 / 002 were closed
  by hand). Same gap as B24, same mode.
- **The mode is renamed Epic-close** (user, 2026-10-06) — it closes both kinds; slice-061's name was not released yet,
  so the rename was cheap then and wrong later. A harness pin keeps the old name out of every shipped file.
- **Closable without an autopilot log = every entry landed and no unmerged epic branch** (user, 2026-10-06; promoted
  to `intent.md` → Derived state over cleanup) — covers a sequential run and an epic worked by hand; no new s5 log line.
  An existing epic branch must be merged (merge-commit rule), a missing one reads `BRANCH_STATE=none`. A parallel epic
  is never reached: step 0 runs only with no other worktree, and Epic-finalize keeps its epic worktree until it closes.
- **E2 asks before it closes** (agent, 2026-10-06; confirmed by the user in Phase 9) — a non-autopilot epic has no
  explicit human signal like a5's `[Y]`, and "every entry landed" can be true of an epic the human still means to
  extend; one `Close <EPIC> now? [Y] / [N]` keeps a mistaken `/craft:commit` from closing it. Asked for both kinds.
- **Not retrofitted:** the three existing epic archives stay as written — they are history, and the template is
  derived from them.
- **Phase 5: `[W]`** (user, 2026-10-06) — on the evidence report (harness 66/66, the sequential-branch mutation red,
  headless probe 1) plus an interactive run. The first interactive attempt ran the installed v1.7.0, not the scratch
  copy (its transcript names only `plugins/cache/craft`): the old command aborted and the agent closed the epic by hand,
  inventing the archive layout — no evidence about this slice, but a live demonstration of B26. The retry ran the
  scratch copy: the close question came before any write; the archive held every template heading, no `## Commits`,
  the three frontmatter keys and the slice follow-ups by reference; plan moved to `.closed/`, no branch deleted.
- **E2: the close question stands alone** (user, 2026-10-06, from the human test) — the session asked it together with
  the decisions walk; the prose now says to ask it alone, and Step 1 starts only after the `[Y]`.
- **A human test of command prose must prove it ran the working copy** (2026-10-06; promoted to `rules.md` → Workflow
  Rules) — the transcript's references to the `--plugin-dir` path versus `plugins/cache/craft` decided it here.
- **Phase 8, one round, clear** (2026-10-06) — seven Light + Local findings, all fixed in-phase (fix cap 5 waived by
  the user, R1-6 applied before the cap was asked and accepted afterwards): E3 before the close question, and the
  protected-main hand-overs point to a close by hand (R1-1); a third `> Merge:` value for Epic-finalize under protected
  main, the template line a bare placeholder (R1-2); `git branch -d` offered for a leftover branch with nothing to keep
  (R1-3); a second closable epic worded and recommended (R1-4); the content rules in Step 5 only (R1-5); a filled epic
  Recap Draft routed into the archive (R1-6); `commit.md`'s description and `skills/workflow/SKILL.md`'s mode list name
  Epic-close (R1-7, SKILL.md released by the user). Not shown by a probe after these fixes: the E3-before-E4 order and
  the protected-main hand-over wording — read in the scenario walk-through only; Epic-finalize writing from the template
  is not shown by any run (no parallel-epic fixture).

## Commits

- `7001b75` — docs(decisions): bank D38 — every finished epic closes through /craft:commit, its archive from one template
- `8befcb3` — feat(commit): close every finished epic, its archive from one template (Epic-close)
- `9d7ac2f` — docs: document the epic close for sequential epics and the archive template
- `729ba1b` — docs(pages): document Epic-close and the epic archive template
- `444e03b` — docs(roadmap): ship B26, widen B25 to sequential epics
- `9efb23b` — chore(plans): bump slice counter to 63
