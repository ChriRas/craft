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

# Read-only context guard + sync helper — self-contained Bash harness. It also
# asserts that the guard's normalize_path and the helper's os.path.normpath agree,
# which is the only thing keeping the two implementations from drifting. Keep green.
bash scripts/test-readonly-context.sh

# Workflow phase-transition graph — the Status graph declared in skills/workflow/SKILL.md
# (## Phase Transition Rules) must stay closed under both Phase-7 configurations, the
# commands' <!-- craft:writes --> / <!-- craft:reads --> markers must match the table in
# BOTH directions, and /craft:continue must route each status to the graph's consumer.
# The markers are the contract — prose is deliberately NOT checked, because a grep cannot
# tell a prescription from a prohibition. Mark any new Status write, or the graph goes
# blind. Run after touching any command's Status handling. Keep green.
bash scripts/test-workflow-status-graph.sh

# Docs-site consistency — docs/index.html (the bilingual GitHub Pages site) must stay
# in sync with the plugin surface: version badge == plugin.json, asset counts ==
# directory listings, EN/DE parity, anchors, tag balance. This is the staleness
# detector for the published docs. The editorial contract and regeneration guide live
# in .claude/skills/docs-site/SKILL.md. Run after touching docs/ or any plugin asset.
# Keep green.
bash scripts/test-docs-site.sh
```

This repo has no build tooling and no conventional test framework — it ships Markdown
commands/skills, JSON manifests, and Bash hooks. The three harnesses above are the
exception: they cover the `hooks/` + `scripts/` Bash surface, the phase-transition
graph the command Markdown encodes, and the published docs-site's sync with the
plugin surface.

## Workflow

Every session starts with `/craft:prime`, auto-triggered by the SessionStart hook. To
plan new work: `/craft:plan <feature-name>`. To resume open work: `/craft:continue`.
