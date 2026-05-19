# Changelog

All notable changes to this plugin will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
