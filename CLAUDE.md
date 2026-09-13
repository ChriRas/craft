# CRAFT

CRAFT is a Claude Code plugin — *Coding with Rules, Autonomy, Feedback, Tests*. This
repository is the plugin's own source, and it dogfoods CRAFT: its development runs
through the CRAFT workflow.

## Project Knowledge

- [`.claude/project/intent.md`](./.claude/project/intent.md) — Vision, goals, architectural decisions.
- [`.claude/project/rules.md`](./.claude/project/rules.md) — Stack, conventions, deployment, tabus.
- [`.claude/project/slices/`](./.claude/project/slices/) — Archived completed slices (Decision Log).

## Design Records

- [`brainstorm-decisions.md`](./brainstorm-decisions.md) — the full decision log (D1–D33).
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

# Plugin cache drift helper — scripts/check-plugin-cache-drift.sh decides whether the
# running plugin (the installed cache copy) matches this working tree, by content: the
# version cannot tell, it stays the same while the repo changes. /craft:prime step 5c
# reports it. Covers in-sync / diverged (modified, added, removed) / not-dev-repo /
# unknown, and that docs-only or gitignored edits raise no false alarm. Keep green.
bash scripts/test-plugin-cache-drift.sh

# Toolchain check — scripts/check-toolchain.sh reports bash (>= 5.0, one constant) and python3
# with an OS-aware install command (brew / apt / dnf / yum / pacman / apk / zypper / Windows), and
# compares the bash the SessionStart hook recorded in .claude/plans/.hook-env. /craft:prime runs
# it in pre-flight. The harness drives every platform via test-only overrides and runs the hook
# under /bin/bash (3.2 on macOS) — hooks/ and this helper must stay bash-3.2-compatible. Keep green.
bash scripts/test-toolchain-check.sh

# Run THIS working tree as the plugin for one session (replaces the installed craft@craft;
# verified with Claude Code 2.1.270):
claude --plugin-dir /path/to/this/repo
```

This repo has no build tooling and no conventional test framework — it ships Markdown
commands/skills, JSON manifests, and Bash hooks. The five harnesses above are the
exception: they cover the `hooks/` + `scripts/` Bash surface, the phase-transition
graph the command Markdown encodes, the published docs-site's sync with the
plugin surface, the plugin runtime's drift from the working tree, and the required toolchain.

## Dogfooding Is Not Self-Verification

A normal session executes the **installed** CRAFT (`~/.claude/plugins/cache/craft/craft/<version>/`,
copied from the GitHub marketplace), **not** the files in this repo. Command prose, hooks, agents
and plugin-resolved paths (`${CLAUDE_PLUGIN_ROOT}/…`) come from that installed copy, so editing them
changes nothing about the session that makes the edit — the reviewer reads the new file while the
runtime obeys the old one. The exception: files a command reads by a **relative** path (e.g.
`skills/senior-developer/SKILL.md` in `/craft:prime` step 1) resolve against the project root, and in
this repo that is the working tree. So:

- `/craft:prime` step 5c shows `⚠ Plugin runtime ≠ working tree` with the differing files — from the
  first release that ships step 5c, or right away in a `--plugin-dir` session.
- To exercise changed command behavior, start a fresh session with `claude --plugin-dir <repo>`.
  Push + `/craft:upgrade` alone does **not** refresh the installed copy: `plugin.json` pins
  `version`, and Claude Code skips an update whose version it already has — only a release
  (version bump + push) does.
- Phase 5 here runs on automated evidence (see `rules.md` → Workflow Rules): the running session
  can show scripts and harnesses only; changed runtime behavior is shown by a headless probe
  (`claude -p "<command>" --plugin-dir <repo>`, run from a scratch copy) — or stated as unshown.
- A nested `claude` probe started **inside** this repo runs the SessionStart hook, which deletes
  `.claude/plans/.primed` and un-primes the running session — start probes from another directory.

## Workflow

Every session starts with `/craft:prime`, auto-triggered by the SessionStart hook. To
plan new work: `/craft:plan <feature-name>`. To resume open work: `/craft:continue`.
