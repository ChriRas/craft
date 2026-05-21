# Changelog

All notable changes to this plugin will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
