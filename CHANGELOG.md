# Changelog

All notable changes to this plugin will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-05-27

### Added
- **Hierarchical planning via `/craft:epic`** (slice-007) — multi-slice epics with `Depends-On:` graph and optional review checkpoints; epic plans templated separately from slice plans.
- **Parallel worktree execution** (slice-009) — `/craft:execute` orchestrator spawns one `slice-builder` subagent per runnable slice inside its own git worktree, merges slice branches into an epic branch (or `main` for a single slice), and stops for human review at the configured checkpoints. New helper commands `/craft:checkout`, `/craft:worktree-status`, `/craft:worktree-clean`. New `agents/slice-builder.md` subagent (Phase 4–7 autonomous executor).
- **Subagent Mode contracts on phase commands** — `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review` document how they behave when invoked by `slice-builder` (no user prompts; `.craft/handoff.md` on human-required pauses). Debug is handled by `slice-builder` itself writing a handoff and pausing, rather than by a Subagent-Mode debug skill.
- **Worktree-aware Phase 9** — `/craft:commit` understands the worktree layout and the orchestrator handoff state.
- **Per-Phase Model Switching** (slice-010) — subagents carry a `model:` frontmatter (`slice-builder: sonnet`, new `agents/code-reviewer.md: opus`); projects override per-agent in `.claude/project/rules.md` → `## Agent Model Overrides`. `/craft:prime` reports the effective Agent → Model map and soft-warns on invalid entries. Documented in new `model-defaults.md` (incl. one-shot Issue #173 verification procedure).
- New onboarding-template section for Agent Model Overrides; new template fields `Depends-On`, `Review Checkpoints`, `Worktree Settings`.
- README "Per-Phase Model Switching" section and autonomous-flow Quickstart entry.

### Changed
- **BREAKING:** `/craft:execute` renamed to `/craft:build` for the Phase-4-implementation role. The name `/craft:execute` is now the Phase 4–7 orchestrator (the new parallel-worktree command). Existing user-facing references must be updated.
- `/craft:review` Step 2 now delegates to the named `code-reviewer` subagent (with `subagent_type: "code-reviewer"`) instead of an ad-hoc Task call, so the reviewer runs on its pinned `opus` model.
- D-number (D1–D28) decision references removed from all shipped commands and skills (slice-008) — end-users don't see the decision log; the references rot.
- `intent.md` updated to mark goals B (epic), F (debug), C+D+E (parallel worktree execution) as shipped; phase-model open question resolved by slice-010.

## [0.3.0] - 2026-05-21

### Added
- **Personality Autoload (D27)** — a Senior-Developer baseline skill loaded on every session, plus monolithic stack-packs (ships `stack-php-laravel`). `/craft:onboard` detects the project stack and proposes a matching stack-pack; `/craft:prime` warns at session start when a declared pack is missing.
- **Code Review phase (D28)** — `/craft:review`, a new Phase 8 between Refactoring and Commit. A fresh-context subagent reviews the slice on a severity × fix-nature rubric, fixes bounded local edits in-phase, escalates needs-rethinking findings, and gates Commit.
- Lettered-choice prompt convention in `skills/workflow/SKILL.md` — every `[X]`-style menu is always rendered with its full legend.
- Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md` as the structural backbone of `feedback-human-control`.
- Pre/Post-Assertions retrofitted into `/craft:onboard`, `/craft:plan`, `/craft:commit`, `/craft:abort` per D24. Behavior on the happy path is unchanged; failure paths are louder and more consistent. Decision banked as D24 in `brainstorm-decisions.md`.

### Changed
- The coding loop is now **nine phases** — Review is Phase 8, Commit & Cleanup is Phase 9. The workflow skill and every phase command updated accordingly.
- README and the plugin / marketplace manifests refreshed for the nine-phase model and the marketplace-based install flow.

## [0.2.0] - 2026-05-19

### Added
- Initial plugin scaffolding: directory layout, manifest, README.
- Architecture spec and brainstorm-decisions captured in repo root.
- `/craft:upgrade` — syncs the marketplace clone from GitHub, with Pre/Post-Assertions, human-confirmed pull, and explicit session-restart hint. Does not touch the plugin cache or registry.

### Changed
- Pivoted to `/craft:` namespace with `/craft` as single entry-point skill.
- Migrated `/craft:debug`, `/craft:brainstorm`, `/craft:grill-me` from commands to skills.

### Changed
- Plugin named **CRAFT** — *Coding with Rules, Autonomy, Feedback, Tests*. Earlier working name `ai-coding-tools` is gone. README now opens with ASCII-art wordmark + tagline.
