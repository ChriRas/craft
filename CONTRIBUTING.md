# Contributing to CRAFT

*Auf Deutsch: [CONTRIBUTING.de.md](./CONTRIBUTING.de.md)*

Thank you for wanting to improve CRAFT. This guide explains how the plugin is built, how to run your copy of it, which
checks must stay green, and how a change reaches a release.

CRAFT is built with CRAFT: every change runs through the same phased loop the plugin ships — plan, build, verify, recap,
review, commit. You do not have to use CRAFT to send a fix, but knowing the loop explains why the repository looks the
way it does.

---

## Reporting a problem or proposing a change

- **Bugs and ideas:** open an issue at [github.com/ChriRas/craft/issues](https://github.com/ChriRas/craft/issues). Say
  what you ran, what you expected and what happened — the `/craft:prime` status block and the CRAFT version
  (`CRAFT plugin v…`) help a lot.
- **Small fixes** (a typo, a wrong path, a broken link): a pull request is welcome right away.
- **Larger changes** (a new command, a changed workflow rule, a new helper): open an issue first. CRAFT banks every
  architectural decision as a numbered entry (`D1`–`D42`) in [`brainstorm-decisions.md`](./brainstorm-decisions.md)
  *before* it is built, so a design talk up front saves you rework.

By contributing you agree that your work is released under the [MIT License](./LICENSE).

---

## What you need

The same tools CRAFT itself requires (see the README → *Requirements*): Claude Code, `git`, `gh`, `bash` ≥ 5.0,
`python3`, the `context-mode` plugin and the `agent-browser` CLI. The Bash harnesses run without Claude Code; only the
headless probes and `claude plugin validate .` need it.

---

## Run your working copy as the plugin

A normal Claude Code session runs the **installed** CRAFT — a copy in `~/.claude/plugins/cache/craft/craft/<version>/` —
not the files you are editing. Editing a command therefore changes nothing in the session that makes the edit. To run
your working tree instead, start a fresh session with:

```bash
claude --plugin-dir /path/to/your/craft/clone
```

In that session `/craft:prime` reports `✓ Plugin runtime = working tree (loaded in place)`. In a normal session inside
this repository it warns `⚠ Plugin runtime ≠ working tree` and names the files that differ.

**Headless probes** (`claude -p "/craft:<command>" --plugin-dir <copy>`) show what changed command prose actually does.
Run them from a scratch copy outside this repository, one at a time: a nested `claude` started inside the repository
runs the SessionStart hook and un-primes the session you are working in. Judge a probe by what it left behind — git
history, files, the transcript — never by the probed agent's own report. Never let a probe select a model that may bill
usage credits.

---

## Repository layout

| Path | What lives there |
|---|---|
| `commands/` | The slash commands (`/craft:<name>`), one Markdown file each. |
| `skills/` | Skills: the workflow, the Senior-Developer baseline, `/craft`, `/craft:debug`, brainstorm, grill-me, stack-packs. |
| `agents/` | Subagents: `slice-builder`, `code-reviewer`, `slice-planner`, `plan-architect`. |
| `hooks/` | Bash hooks and `hooks.json` (SessionStart, PreToolUse, UserPromptSubmit). |
| `scripts/` | Helper scripts the commands call, and the `test-*.sh` harnesses. |
| `templates/` | Templates `/craft:onboard`, `/craft:plan` and `/craft:commit` fill in, and the profile presets. |
| `docs/` | The bilingual documentation site (GitHub Pages). |
| `model-defaults.md`, `craft-profile-defaults.md` | The single declarations of model values and profile defaults. |
| `.claude/project/` | CRAFT's own project knowledge (intent, rules, roadmap) and the archive of every finished slice. |

---

## The checks that must stay green

There is no conventional test framework — CRAFT ships Markdown, JSON and Bash. Instead, standalone Bash harnesses in
`scripts/test-*.sh` cover the helpers, the hooks, the phase graph the command prose encodes, and the docs site. Each one
is described in [`CLAUDE.md`](./CLAUDE.md) → *Common Commands*. Run them all, plus the manifest check:

```bash
for f in scripts/test-*.sh; do bash "$f" >/dev/null 2>&1 || echo "RED: $f"; done
```

```bash
claude plugin validate .
```

`scripts/test-model-enum.sh` runs 8–10 minutes (it copies the repository for every mutation fixture); the others take
seconds. A change that touches `docs/` or any plugin asset must keep `scripts/test-docs-site.sh` green — it compares the
docs site with the plugin surface.

---

## Conventions

- **Commits** follow Conventional Commits: `<type>(<scope>): <subject>` — `feat`, `fix`, `docs`, `test`, `refactor`,
  `chore`. One logical change per commit; code and docs commit separately. No `Co-Authored-By` trailer.
- **Prose is not checkable — markers are.** Command files carry machine-readable markers (`<!-- craft:writes … -->`,
  `<!-- craft:reads … -->`, `<!-- craft:choice -->`, `<!-- craft:handoff … -->` …) that the harnesses bind. When you add
  a status write, a human choice or a handoff, add its marker, or a harness goes red.
- **A rule is never described twice.** When two places need the same rule, one defines it and the other points to it.
  Where a copy cannot go (a template, the docs site), it is *bound*: it carries a marker and a harness compares it with
  the one declaration.
- **Derived state over cleanup.** Whether something is still live is read from the slice plan or from git by one helper,
  not stored in a flag that every writer must remember to clear.
- **Hooks stay bash-3.2-compatible** (macOS `/bin/bash`), and so do the helpers a hook calls; the rest of `scripts/` may
  use bash ≥ 5.0.
- **No removal command in a line the agent issues** — a helper keeps its own `rm` inside the script file. A user's rule
  on removing files is their boundary.
- **Numbers are read off a run, never derived** — fixture counts, check counts, line counts.
- **Code comments and docs are in English**; the docs site is bilingual (English and German), and the two languages
  stay in parity.

---

## Documentation

- **README.md** — the overview and quickstart.
- **CHANGELOG.md** — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). New entries go under `[Unreleased]`,
  **one line per item**: the GitHub release notes are generated from that section, and a wrapped line would become a
  hard break there. `test-docs-site.sh` checks it.
- **docs/index.html** — the documentation site. Its editorial contract, structure and update procedure live in
  `.claude/skills/docs-site/SKILL.md`; `test-docs-site.sh` keeps its badge, counts and harness table in step with the
  tree.

---

## How a release happens

CRAFT follows [Semantic Versioning](https://semver.org/). The `version` in `.claude-plugin/plugin.json` is Claude Code's
update key — an update with a version it already has is skipped, so **every release bumps it**.

1. Move the CHANGELOG's `[Unreleased]` section under a new `## [X.Y.Z] - <date>` heading and keep an empty
   `## [Unreleased]` heading above it (`scripts/test-docs-site.sh` requires one); an interim release with a breaking
   behavior change opens its section with an upgrade note.
2. Bump `version` in `.claude-plugin/plugin.json`, both `version` fields in `.claude-plugin/marketplace.json` and the
   version badge on the docs site; run all harnesses.
3. Push `main` — the marketplace installs `main`'s HEAD, so **the push is the release**.
4. Tag the pushed commit and create the GitHub release from the CHANGELOG section:

```bash
git tag -a vX.Y.Z origin/main -m "vX.Y.Z"
```

```bash
git push origin vX.Y.Z
```

Users then update with `/craft:upgrade` (it syncs the marketplace clone) and `/plugin update craft@craft`; a new session
loads the new version.
