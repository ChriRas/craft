# Changelog

All notable changes to this plugin will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-07-07

Epic-001 (Autonomy Profiles) plus the in-place / sequential execution and protected-`main` slices.

### Added
- **Portable CRAFT profile format** (slice-015) — a new `.claude/project/craft-profile.md` carrying autonomy, language, commit/merge, and per-agent model settings in one portable file, with named presets and sensible defaults. `/craft:prime` detects, validates, and reports the active profile; documented in the README and project index.
- **Guided onboarding profile wizard + read-only permission allowlist** (slice-017) — `/craft:onboard` now walks the user through profile creation and seeds a tiered read-only permission allowlist in `.claude/settings.local.json`, cutting the per-command permission prompts on common read-only tools.
- **In-place autonomous execution mode + `/craft:release`** (slice-018) — `/craft:execute` gains `Mode: in-place`, which builds a slice on a branch in the main checkout, makes no commits, and halts before Phase 5 so the raw uncommitted diff can be reviewed in the IDE. The new `/craft:release` command is the human "approve-to-proceed" gesture that lifts the halt and resumes the slice into Phase 5 and the rest of the flow.
- **Profile-driven protected-`main` PR merge gate** (slice-019) — on a project whose profile sets protected-`main` PR mode, `/craft:commit` runs `gh pr merge` itself, but **only after a real human GitHub PR approval** (never `--admin`, so branch protection genuinely gates it). "Approve ≠ merge": the human approves, the system merges.
- **Sequential epic mode** (slice-020) — `/craft:execute` gains `Epic Mode: sequential`, running an epic's slices one after another through the direct workflow instead of parallel worktrees; `/craft:commit` gains status-aware A1 handling and an in-place-finalize path.

### Changed
- **Language and per-agent model settings now live in `craft-profile.md`** (slice-016) — sourced by `/craft:prime`, `/craft:commit`, `/craft:build`, and `/craft:review`. The `## Operational Language` and `## Agent Model Overrides` blocks were removed from the `rules.md` template and this repo's own `rules.md`. **Migration:** projects that kept language or model-override settings in `rules.md` should move them into `.claude/project/craft-profile.md` — run `/craft:onboard` to generate one and migrate existing settings automatically.
- `intent.md` promotes "approve ≠ merge on protected `main`" to a headline architectural decision.

### Fixed
- `/craft:commit` awaiting-release recovery now points at `/craft:release` (it referenced a stale recovery path).

## [1.2.0] - 2026-06-07

### Added
- **Worktree trust via `additionalDirectories`** (slice-014) — `/craft:execute` now resolves the base directory of the configured `Worktree path pattern` and idempotently records it in `permissions.additionalDirectories` of `.claude/settings.local.json` before creating any worktree. This stops the per-path permission prompts that previously stalled autonomous runs (worktrees live outside the project root, which Claude Code does not trust by default). Ships `scripts/ensure-worktree-trust.sh`, which derives the base path platform-neutrally, merges without overwriting existing permissions, creates + gitignores the settings file when missing, and verifies the result is valid JSON. Durable-state contract preserved: announced once, applied on confirmation, then a silent no-op on every later run.

### Changed
- `## Worktree Settings` in the `rules.md` template (and this repo's own `rules.md`) documents that `/craft:execute` maintains the worktree base directory in `permissions.additionalDirectories`.

## [1.1.0] - 2026-06-03

### Added
- **Durable Capture** (slice-013) — a named methodological principle in the workflow Knowledge Model: an agent's context is ephemeral (cleared on `/clear`, compaction, or session end), so any analysis, decision, scenario, domain model, or proposal of lasting value produced during planning / design must be written to a durable artifact in the same turn it is produced. Maxim: *"Chat is not storage."* Ships a routing table mapping each kind of lasting output to its home, plus a worked example.
- **`.claude/project/design/` knowledge home** — a canonical, on-demand directory for cross-cutting design knowledge (domain model, scenario catalogs, matrices) that is neither *why* (intent) nor *how* (rules). Not loaded on `/craft:prime`, so it adds no session-context budget. Wired into `/craft:onboard` (greenfield documentation + migration knowledge-split routing) and the `CLAUDE.md` index template.
- **Closing-capture enforcement** in the planning commands — `/craft:plan` gains Procedure step 9 + Post-Assertion P5, and `/craft:epic` mirrors them as step 6 + P5. Each sweeps the planning dialog for material insight and routes it to its durable home before the command finishes: *"Do not end a planning turn leaving material insight only in chat."*

### Changed
- `skills/senior-developer/SKILL.md` workflow gates now cross-reference Durable Capture, so the principle applies session-wide, beyond the two planning commands.
- `intent.md` records Durable Capture as a headline architectural decision.

## [1.0.0] - 2026-05-29

First stable release — all seven original capabilities (A–G) shipped.

### Added
- **Plugin version display** (slice-011) — `/craft:prime` emits `✓ CRAFT plugin v<version>` and `/craft` prefixes its state-report headers with `CRAFT v<version>`; read from `plugin.json` (`${CLAUDE_PLUGIN_ROOT}` → project-root) with a soft `v?` fallback that never aborts.
- **Configurable language** (slice-012) — `/craft:onboard` captures chat / commit / comment language into a `## Operational Language` block in `rules.md`; consumed by `/craft:prime` (reports and adopts the chat language), `/craft:commit` (commit-message language), and `/craft:build` / `/craft:review` (code-comment language). Defaults: chat = system language, commits and comments = English; a missing block applies defaults and never aborts.

### Fixed
- `.claude/plans` glob path typo across 8 command/skill files (`prime`, `continue`, `status`, `build`, `test`, `commit`, `abort`, and the workflow skill) — they referenced a non-existent `.claude/craft:plans/` directory (slice-011 review follow-up).

### Changed
- `rules.md` doctrine note now admits operational, non-State-verifiable settings (the `## Operational Language` block) as a sanctioned exception.
- `intent.md` marks all seven capabilities (A–G) shipped; no capability work remains.

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
