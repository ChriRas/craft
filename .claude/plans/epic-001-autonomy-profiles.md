# Epic 001 — Autonomy Profiles

> Status: planning | decomposing | active | paused | completed
> Epic-ID: epic-001
> Epic-Slug: autonomy-profiles
> Started: 2026-06-17
> Phase: 3
> plugin-version: 1.2.0
> Handoff active: no

## Vision

Today CRAFT's autonomy is effectively binary: either the manual phase-by-phase loop
(in-place on the current branch, never auto-committing — changes wait for Phase 9) or
`/craft:execute` (autonomous, but always in throwaway worktrees that auto-commit every
sub-task). There is no way to run *autonomously in-place* so you can eyeball the raw
diff in your IDE before any commit, no first-class workflow for a protected-`main` repo
where humans **approve** rather than **merge**, and no way to capture a project's chosen
autonomy/commit/permission setup and reuse it across similar projects — every repo
re-decides these defaults ad hoc.

When this epic is done, `/craft:onboard` offers a fast "give me the defaults" path and a
guided multiple-choice setup that writes a **portable CRAFT profile** (named presets,
free to deviate from the plugin defaults) covering language, model overrides, a default
permission allowlist, execution mode (worktree vs. in-place), commit policy, and the
PR/merge workflow — auto-read on every `/craft:prime`, copyable into sibling projects.
A new **Autonomous + In-place** mode builds on a branch in the main checkout without
auto-committing, halts before Phase 5 for your IDE review, and commits only on your
release. A **protected-`main` "Freigabe ≠ Merge"** mode gates the final merge on a real
GitHub PR approval after Phase 8, then merges via `gh`. Epics gain an **additive**
slice-by-slice sequential mode (commit per slice) alongside the existing parallel
worktree mechanic.

Scope edges — explicitly NOT in this epic: no "confirmed N times → auto-adopt
permission" escalation (deemed over-engineered); no removal or replacement of the
existing parallel worktree execution (it stays, the new modes are additive); no
per-user/global profile system (profiles stay per-project — D11 holds); no new MCP
server (D25 holds).

## Slice Decomposition

> Initial decomposition into vertical slices. Each entry is a candidate `/craft:plan`
> invocation later; treat the list as a roadmap, not a contract. Update as slices land.

- [x] profile-format — Portable CRAFT profile file + named presets, auto-read on `/craft:prime`; the single home for all per-project autonomy/commit/permission/execution knobs, incl. the full `## Operational Language` + `## Agent Model Overrides` schema (Decision A). Foundation: profile exists, is reported + validated by `prime`. Nothing acts on it yet.
- [x] settings-migration — Flip the language + model-override consumers (`commit`, `build`, `review`, `execute`) to read from the profile, and remove the two blocks from `rules.md` + its template (Decision A, full migration out of `rules.md`).
- [x] onboarding-wizard — Interactive setup in `/craft:onboard`: "defaults" fast-path vs. guided multiple-choice; writes the profile (incl. language + models) and a default permission allowlist (wildcards) into `.claude/settings.local.json` (Decisions A + B).
- [x] inplace-autonomous — Autonomous + In-place execution mode: build on a branch in the main checkout, no auto-commit, halt before Phase 5 for IDE review, commit on your explicit release; auto-commit stays mandatory in the worktree path (Decision C).
- [x] protected-main-pr — "Freigabe ≠ Merge": PR + GitHub approval gate after Phase 8, then the system merges via `gh`; project setting, protected-`main` detected/asked (Decision D). Verify `gh`/branch-protection mechanics before building.
- [ ] epic-sequential — Additive slice-by-slice sequential epic mode (commit per slice), running alongside — not replacing — the existing parallel worktree mechanic (Decision E).

## Review Checkpoints

> Optional. Controls where `/craft:execute` pauses for human review during the
> autonomous run. Default: end-of-epic only.
>
> Each entry takes the form `- after slice-NNN` and pauses after that slice's
> Phase-7 self-review completes, before merging into the epic-branch. Use
> sparingly — per-slice stops produce review fatigue.

- (none — review at end-of-epic only)

## Decisions Made During This Epic

> Architectural / product decisions that surface during epic shaping or while child
> slices execute. Each entry is walked with the `[K]/[I]/[R]/[D]` promotion dialog
> when the epic closes.

- **Config home (A):** A dedicated, portable profile file + plugin-shipped named presets — not extra `rules.md` blocks — chosen to satisfy reuse across projects. Auto-read like `rules.md`; may deviate from plugin defaults. **Includes language + model overrides** — these move *out* of `rules.md` entirely (per user direction). Schema lands in `profile-format`; the consumer switch + `rules.md` cleanup is the `settings-migration` slice.
- **Permissions scope (B):** Onboarding writes a default permission allowlist (wildcards) to `.claude/settings.local.json`. The "confirmed N times → auto-adopt" escalation is dropped as over-engineered.
- **Auto-commit coupling (C):** Auto-commit is bound to the **worktree**, not to autonomy. It is disable-able only in the in-place path; the worktree/parallel path must keep auto-committing (the merge model depends on it).
- **Freigabe ≠ Merge (D):** In protected-`main` mode the human gives a GitHub PR **approval** (a real review), not a manual merge; the system merges via `gh` once the approval exists. Gate sits **after Phase 8** — so code + Recap docs are already in the PR at approval time, collapsing the flow to "everything in PR → approve → auto-merge".
- **Approval granularity (open — recommended default, pending explicit confirmation):** sequential epic → PR + approval **per slice**; parallel epic → one PR + approval at the **epic end** (concentrated control at the epic boundary). Confirm before the protected-main-pr slice.
- **Verification debt:** `gh pr merge` behaviour under branch protection + required-review must be verified against the current GitHub/`gh` state at the start of the protected-main-pr slice (training knowledge is ~5 months stale).

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
