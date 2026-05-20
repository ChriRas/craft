# CRAFT

CRAFT is a Claude Code plugin — *Coding with Rules, Autonomy, Feedback, Tests*. This
repository is the plugin's own source, and it dogfoods CRAFT: its development runs
through the CRAFT workflow.

## Project Knowledge

- [`.claude/project/intent.md`](./.claude/project/intent.md) — Vision, goals, architectural decisions.
- [`.claude/project/rules.md`](./.claude/project/rules.md) — Stack, conventions, deployment, tabus.
- [`.claude/project/slices/`](./.claude/project/slices/) — Archived completed slices (Decision Log).

## Design Records

- [`brainstorm-decisions.md`](./brainstorm-decisions.md) — the full decision log (D1–D28).
- [`plugin-architecture.md`](./plugin-architecture.md) — the build blueprint.
- [`README.md`](./README.md) — plugin overview and command reference.

## Active Work

- [`.claude/plans/`](./.claude/plans/) — currently active slice plans (ephemeral; deleted on Phase 8 cleanup).

## Common Commands

```bash
# Validate the plugin manifest + asset structure
claude plugin validate
```

This repo has no build or test tooling — it ships Markdown commands/skills, JSON
manifests, and Bash hooks.

## Workflow

Every session starts with `/craft:prime`, auto-triggered by the SessionStart hook. To
plan new work: `/craft:plan <feature-name>`. To resume open work: `/craft:continue`.
