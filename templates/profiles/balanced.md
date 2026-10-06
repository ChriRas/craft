# CRAFT Profile

> Per-project CRAFT operating profile — autonomy, commit, merge, language, and model
> settings consumed by CRAFT commands. **Portable:** copy this file into a sibling
> project to reuse the setup. Auto-read on every `/craft:prime`. This file **is** the
> effective config — when it is absent, the plugin defaults apply (see
> `craft-profile-defaults.md`). Generated/edited via `/craft:onboard`; safe to hand-edit.
>
> Lives at `.claude/project/craft-profile.md`. May freely deviate from any preset.
>
> **balanced** — CRAFT's out-of-the-box behaviour and the "just give me the defaults"
> choice: autonomous worktree builds with per-sub-task commits, direct merge to `main`,
> parallel epics, and a standard permission allowlist.

> Preset: balanced

## Execution

> How `/craft:execute` runs work. `worktree` is the parallel-safe path (slices build in
> throwaway git worktrees outside the repo). `in-place` builds on a branch in the main
> checkout so you can inspect the raw diff in your IDE.

- **Mode:** worktree

## Commit Policy

> `Auto-commit: off` holds all changes uncommitted until you release them — only valid
> in the `in-place` path. The `worktree` path **always** auto-commits (its merge model
> depends on per-sub-task commits), so `Auto-commit: off` + `Mode: worktree` is invalid.
>
> `Co-Authored-By: on` makes `/craft:commit` append the trailer
> `Co-Authored-By: Claude <noreply@anthropic.com>` to each commit message. Default `off`.

- **Auto-commit:** on
- **Co-Authored-By:** off

## Merge Workflow

> How a finished slice/epic lands. `pull-request` + `Protected-main: yes` is the
> "Freigabe ≠ Merge" flow: the human **approves** the PR (does not merge by hand) and
> the system merges via `gh` once the approval exists.

- **Type:** direct
- **Protected-main:** no
- **Approval:** chat
- **Approval-granularity:** auto

## Epic Mode

> Default decomposition execution for `/craft:execute <epic>`. `parallel` is the
> existing worktree mechanic; `sequential` runs slices one-by-one in place, committing
> per slice with a review halt between them.

- **Default:** parallel

## Permissions

> Records which permission-scope preset onboarding applied. The actual allowlist entries
> live in `.claude/settings.local.json` — this field is documentation only, never a
> duplicate of the allowlist.

- **Scope:** standard

## Autopilot

> The budget guard of an autopilot run (`/craft:execute <epic> --autopilot`): limits on your plan's
> 5-hour and weekly usage windows, in percent. Before a slice, the 5-hour usage plus the forecast (the
> mean of the slices landed so far) above `Budget-before-slice` → the slice does not start. During one,
> the 5-hour usage at or above `Budget-in-slice` → the builder stops at the next boundary of
> its run (a sub-task, a phase, a debug attempt). The
> weekly usage at or above `Budget-seven-day` → no further slice. An integer 1–100 each. Judged by the
> CRAFT plugin's `scripts/usage-state.sh` from the statusline tap you wire once (README → Requirements);
> without a tap the run stops after every slice. A window at 99 % while the cache TTL is 5 minutes
> (overage) always stops — not configurable.

- **Budget-before-slice:** 85
- **Budget-in-slice:** 95
- **Budget-seven-day:** 90

## Operational Language

> Three independent language settings. Consumed by `/craft:prime` (reports them),
> `/craft:commit` (commit-message language), and `/craft:build` / `/craft:review`
> (code-comment language). Defaults: Chat = system language, Commits = English,
> Comments = English.

- **Chat:** system
- **Commits:** English
- **Comments:** English

## Agent Model Overrides

> Override CRAFT subagent models (defaults in `model-defaults.md`).
> <!-- craft:model-enum -->
> Allowed values: `opus`, `sonnet`, `haiku`, `inherit`, `fable`, `<model-id>`
> An empty block means "use defaults". `/craft:prime` reports, per agent, the model CRAFT will
> **ask for** at spawn time, and warns on an unknown agent name.
> **Not every value above reaches an agent.** The spawn parameter carries a narrower set; a value
> outside it is dropped rather than passed — it does **not** fail at spawn time — and the agent
> runs on its own default. `/craft:prime` names such an override as `is inert` at every session
> start, which is where you find out. Which values arrive is declared in the CRAFT plugin's
> `model-defaults.md` → Spawn-Reachable Values; the plugin lives under
> `~/.claude/plugins/cache/craft/craft/<version>/`. The CRAFT docs site explains the distinction
> but does not list the set — the values live in that one file.
> Model values are otherwise **not** checked here: prime cannot tell a real model ID from a typo.
> `fable` is valid but human-chosen only — CRAFT never selects it, and prime flags it at
> every session start because it can bill to usage credits.

<!--
Examples (uncomment to use):

- slice-builder: opus     # heavier judgment for risky migrations
- code-reviewer: sonnet   # faster review for low-stakes slices
-->
