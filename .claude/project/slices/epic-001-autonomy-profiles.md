# Epic 001 — Autonomy Profiles

> Completed: 2026-07-06 (started 2026-06-17)
> Slices: 6/6 landed · trunk-based, no PR

## Vision

CRAFT's autonomy was effectively binary: the manual phase-by-phase loop, or `/craft:execute`
in throwaway auto-committing worktrees. There was no way to run *autonomously in-place*
(eyeball the raw diff before any commit), no first-class protected-`main` "approve ≠ merge"
workflow, and no way to capture a project's autonomy/commit/permission setup and reuse it.
This epic turned that binary into a **portable, profile-driven** system: `/craft:onboard`
writes a portable CRAFT profile (presets + a read-only permission allowlist); a new
**autonomous + in-place** mode halts before Phase 5 for IDE review and commits on release; a
**protected-`main` "Freigabe ≠ Merge"** mode opens a PR and merges via `gh` only after a real
GitHub approval; and epics gain an **additive sequential** mode (commit per slice). The
parallel worktree mechanic stays untouched throughout (additive by design).

## Slices (6/6)

- [slice-015 — Profile Format](./slice-015-profile-format.md) — portable profile file + `careful`/`balanced`/`autonomous` presets + defaults; `/craft:prime` detects/validates/reports (Decision A foundation).
- [slice-016 — Settings Migration](./slice-016-settings-migration.md) — language + model settings move out of `rules.md` into the profile; consumers read from it (Decision A complete).
- [slice-017 — Onboarding Wizard](./slice-017-onboarding-wizard.md) — guided `/craft:onboard` setup (fast-defaults vs. per-knob) + a read-only default permission allowlist into `settings.local.json` (Decisions A + B).
- [slice-018 — Inplace Autonomous](./slice-018-inplace-autonomous.md) — `/craft:execute` in-place mode: build on a branch in the main checkout, no commits, halt before Phase 5; `/craft:release` resumes (Decision C).
- [slice-019 — Protected-main PR](./slice-019-protected-main-pr.md) — "Freigabe ≠ Merge": `/craft:commit` opens a PR and merges via `gh` only after a GitHub approval (Decision D; promoted to `intent.md`).
- [slice-020 — Epic Sequential](./slice-020-epic-sequential.md) — `Epic Mode: sequential`: run an epic's slices one-by-one in place, commit per slice, review halt between (Decision E; `direct` workflow — protected-main × sequential deferred).

## Epic Decisions (A–E)

- **Config home (A)** — a portable profile file + named presets, not extra `rules.md` blocks; includes language + model overrides (moved out of `rules.md` entirely). Landed across slice-015/016/017.
- **Permissions scope (B)** — onboarding writes a default permission allowlist (wildcards) to `settings.local.json`; the "confirmed N times → auto-adopt" escalation was dropped as over-engineered. Landed in slice-017 (read-only tiers).
- **Auto-commit coupling (C)** — auto-commit is bound to the worktree, not to autonomy; disable-able only on the in-place path. Landed in slice-018.
- **Freigabe ≠ Merge (D)** — the human gives a GitHub PR **approval**, the system merges via `gh`; gate after Phase 8. Landed in slice-019 and **promoted to `intent.md`** as an architectural decision.
- **Sequential additive (E)** — an additive slice-by-slice sequential epic mode alongside the unchanged parallel worktree mechanic. Landed in slice-020 (`direct` workflow).
- *Resolved along the way:* slice-018's in-place-finalize follow-up and slice-019's A1/epic follow-up were both **implemented in slice-020**.

## Open follow-up

- **protected-main × sequential epic** — a sequential epic under a `pull-request` + `Protected-main` profile (needs the in-place PR-branch resume vs. A3 + local↔remote sync). Guarded and deferred by slice-020; a focused future slice.
