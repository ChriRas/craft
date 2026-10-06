# CRAFT

```
 ██████╗██████╗  █████╗ ███████╗████████╗
██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
██║     ██████╔╝███████║█████╗     ██║   
██║     ██╔══██╗██╔══██║██╔══╝     ██║   
╚██████╗██║  ██║██║  ██║██║        ██║   
 ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   
        Coding with Rules, Autonomy, Feedback, Tests
```

A Claude Code plugin that wraps a disciplined, language-agnostic coding workflow into reusable slash commands and skills. Drop it into any repository — shell script, library, REST API, full-stack web app, data pipeline, infrastructure code — and the agent will guide you through the same 9-phase loop with the same controls every time.

📖 **Documentation:** [chriras.github.io/craft](https://chriras.github.io/craft/) — illustrated guide to the 9-phase loop, every branch-off, and all configuration knobs (English & German).

> **Core principle:** Universality with constant control. Same workflow, same control surface, regardless of stack.

---

## What the Plugin Gives You

A complete coding-loop scaffolding:

- **28 slash entry points** (24 commands + 4 slash-invocable skills) that move you through Brainstorm → Alignment → Planning → Implementation → Testing → Recap → Refactoring → Review → Commit & Cleanup, with explicit navigation cues at every session start.
- **7 universal skills**: the 9-phase workflow itself, the Senior-Developer baseline (loaded every session), the state-aware `/craft` entry point, bug-verification protocol (`/craft:debug`), structured brainstorming (`/craft:brainstorm`), interview-style alignment (`/craft:grill-me`), browser automation.
- **A two-tier architecture**: the plugin ships the universal shell; your project keeps its own language/framework specialists in `.claude/skills/` and `.claude/agents/`, lazy-loaded at runtime.
- **Personality autoload**: the Senior-Developer baseline above is the universal Tier 1; on top of it, optional **stack-packs** (e.g. `stack-php-laravel`) — language/framework idiom packs a project declares in `rules.md` — load automatically during the code-near phases.
- **A SessionStart hook** that auto-runs `/craft:prime` in Craft-onboarded projects so every fresh chat orients itself; stays silent in non-Craft projects.
- **A read-only context guard** — keep reference material the agent may *read* but never *write*: the in-repo `research/` folder (protected by convention) and external "connected projects" declared in `rules.md`. A PreToolUse hook blocks `Write`/`Edit`/`NotebookEdit` on those paths, while `/craft:prime` keeps declared projects *readable* via `additionalDirectories`.
- **Delete-safe closing** — if your Claude Code settings deny or ask on removing files (say `Bash(rm:*)`), CRAFT never goes around that rule: it moves closed and aborted plans into the gitignored `.claude/plans/.closed/` instead of removing them, and the guard keeps the agent from reading them. `/craft:prime` says when this mode is on and, once `.closed/` holds 20 plans or one older than 30 days, hands you a one-line command to empty it. Without such a rule, the agent removes the plan itself and Claude Code's permission check judges it.
- **A migration path** for projects that already have a `.claude/` setup — `/craft:onboard` detects the existing content and moves conflicting commands to `_legacy/` while preserving project-specific specialists.

---

## Installation

CRAFT is distributed as a Claude Code plugin from a marketplace — and this repository *is* the marketplace (it ships `.claude-plugin/marketplace.json`). Install it from inside Claude Code:

```
/plugin marketplace add ChriRas/craft
/plugin install craft@craft
```

The first command registers this repository as a plugin marketplace; the second installs the `craft` plugin from it (`craft@craft` — the `craft` plugin from the `craft` marketplace). Restart the session to activate the commands and skills.

To move to a later release, run `/craft:upgrade` — it syncs the marketplace clone. Claude Code installs the new version by auto-update (if enabled for the marketplace) or on `/plugin update craft@craft`; a new session loads it.

After install, open Claude Code in any project and run `/craft:onboard` to set the project up.

All plugin commands are invoked through the `craft:` namespace — `/craft:onboard`, `/craft:plan`, `/craft:commit`, etc. The full namespace form is required: internal cross-references between commands rely on it to avoid collisions with Claude Code reserved names (e.g. `/plan` would otherwise collide with Plan-Mode) and with project-local `commands/<name>.md` overrides.

#### Requirements

`/craft:prime` checks these on every session start and stops with an install command for your OS
when one is missing:

| Tool | Notes |
|---|---|
| `context-mode`, `agent-browser`, `git`, `gh` | Companion plugin and CLIs the workflow relies on. |
| **bash ≥ 5.0** | macOS still ships `/bin/bash` 3.2 — `brew install bash`. Linux distributions mostly package 5.x; RHEL/Alma/Rocky 8, openSUSE Leap 15.6 and Amazon Linux 2 ship 4.x and need a newer release or a source build. |
| `python3` | Used by the helper scripts. |

Windows: use WSL 2 (Git Bash is untested). If Claude Code is started from a desktop app or IDE, it
may not see your shell's `PATH` and pick up an older bash even though a current one is installed —
`/craft:prime` detects that and names the fix instead of an install command (start from a terminal,
or set `env.PATH` in `~/.claude/settings.json`).

#### Usage tap for autopilot runs (optional)

An autopilot run (`/craft:execute <epic> --autopilot`) watches your plan's 5-hour and weekly usage windows so it
does not start a slice it cannot finish, and stops a running one before the window runs out. The only place a
session can read those windows is the JSON Claude Code pipes into your statusline, so CRAFT ships a small wrapper
that keeps a copy of it and hands the same input on to your own statusline command.

A plugin cannot wire it on install, so `/craft:prime` (and `/craft:onboard`) does it for you when you say yes: it
shows the change to `statusLine` in your user settings, backs the file up and only then writes it — your own command
chained behind the tap, wrapped in `sh -c '…'` when it is more than one command, `refreshInterval` added. A tap wired
to a working tree or a versioned plugin cache is re-routed the same way. To take it out again, run
`scripts/ensure-statusline-tap.sh --remove` from your CRAFT marketplace clone (by default
`bash ~/.claude/plugins/marketplaces/craft/scripts/ensure-statusline-tap.sh --remove`) — it backs the file up too and
restores your own command. **Run it before you uninstall CRAFT or remove its marketplace:** the wired line points into
that clone, and once the clone is gone your statusline stays empty. Prime offers
nothing while your marketplace clone predates the tap (run `/craft:upgrade` first) or a project / local settings file
sets its own `statusLine`.

To wire it by hand instead, in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "refreshInterval": 30,
  "command": "sh ~/.claude/plugins/marketplaces/craft/scripts/statusline-tap.sh <your current statusline command>"
}
```

- Use the marketplace clone's path shown above, not the installed plugin cache: the cache directory is named by
  version and moves with every release.
- Keep `refreshInterval`: without it the statusline goes quiet while the run waits on a builder, and the reading
  goes stale.
- Without a statusline command of your own, end the line after `statusline-tap.sh` — the statusline then stays
  empty.
- If your current command is more than a single command — `a; b`, `a && b`, a pipe, `$(cat)` — wrap it as
  `… statusline-tap.sh sh -c '<your command>'`, or move it into a script file first: otherwise the outer shell runs
  part of it before the tap and your statusline breaks.
- The copy lives in `~/.claude/craft/usage-tap.json` (or under `CLAUDE_CONFIG_DIR`); `/craft:prime` reports
  the reading as *Autopilot budget*.

Without the tap an autopilot run still works, but blind: it stops after every slice and you re-run it. The limits
(one for the 5-hour window before a slice, one within a slice, one for the weekly window) and their defaults live in
`craft-profile.md` → `## Autopilot`. The strongest
protection against usage-credit billing stays outside CRAFT: turn off extra usage in your account settings.

#### Cache guard for autopilot runs

A session that waits on you keeps a prompt cache that expires after an hour; an answer that arrives later makes
Claude Code re-write the whole context at the full input price. So every stop of an autopilot run where it waits
on you — the plan gate, a `⛔` stop, the end-of-epic sign-off — first says until when the cache is warm and how to
restart if you answer later, and a `UserPromptSubmit` hook (`hooks/cache-guard.sh`) blocks a
prompt of that session that arrives after the cache expired — before any request is sent — and names the restart
instead (the re-run resumes the epic). It blocks only when re-writing would cost at least
`Cache-guard-recache-tokens` tokens (its default lives in `craft-profile.md` → `## Autopilot`), and it lets everything else
through: a builder's hand-back, a task notification, `/clear`, a prompt of another session, and anything it cannot
judge (fail open). It judges from the usage tap above, so it needs the tap with `refreshInterval`; without a tap
it never blocks, and the expiry line says `unknown`. The tap is shared by every open Claude Code session: when
another session refreshes it, this one's guard cannot judge and passes your prompt (fail open).

---

## Quickstart

#### First time in a project

```
/craft:onboard
```

`/craft:onboard` either bootstraps a fresh `.claude/project/` setup or migrates an existing `.claude/` configuration. It generates `intent.md`, `rules.md`, and optional `roadmap.md` either from heuristics (fast path) or via the interview-style "Grill-Me" mode (deeper).

#### Every subsequent session

In a Craft-onboarded project, the SessionStart hook fires `/craft:prime` automatically. You'll see a status block:

```
✓ Project: <name> (<stack summary>)
✓ Rules ↔ State drift check: clean
✓ Tools: context-mode ✓ (activated), agent-browser ✓, git ✓, gh ✓, bash ✓ (5.3.15), python3 ✓ (3.12.1)

Active slices:
  → slice-007 "PWA reservation button" — Phase 4, 3/7 sub-tasks done

Recommended next: continue slice-007 (Phase 4)
  → /craft:continue to resume, /craft:plan to start something new
```

In a project that has not been onboarded to Craft, the hook stays silent — no nudge. Invoke `/craft:onboard` yourself if you want to adopt the workflow there.

#### Planning a multi-slice epic

When the next chunk of work is too large for a single vertical slice, capture it as an epic first:

```
/craft:epic hierarchical planning    # records Vision + initial Slice Decomposition
/craft:plan first-slice-from-epic    # refine each entry into a regular slice
```

Epic and slice ID-spaces are independent — `.claude/plans/.next-id` counts slices, `.claude/plans/.next-epic-id` counts epics. Epics are a roadmap, not a contract: refine and reorder the decomposition as the work lands.

#### Building a feature — interactive flow

```
/craft:plan reservation button    # Phase 3 — dialogic planning
/craft:build                      # Phase 4 — implementation
/craft:test                       # Phase 5 — you exercise the artifact
/craft:recap                      # Phase 6 — capture what was learned
/craft:refactor                   # Phase 7 — make it cleaner
/craft:review                     # Phase 8 — independent fresh-eyes review
/craft:commit                     # Phase 9 — atomic commits + slice archive
```

#### Building a feature — autonomous flow (epic-scale)

When you have an epic with multiple slices that can run in parallel, hand the build off to the orchestrator. CRAFT spawns one git worktree per runnable slice, runs Phase 4 → 7 inside each via the `slice-builder` subagent, merges slice-branches into a dedicated epic-branch as they clear review, and stops for human review at epic-end.

```
/craft:epic reservation flow      # Phase 3 (epic-level) — Vision + Slice Decomposition
/craft:plan slice-A               # Phase 3 (slice-level) — repeat for each entry
/craft:plan slice-B               # — entries can declare Depends-On: [slice-A] in their frontmatter
/craft:execute epic-001           # autonomous: parallel worktrees, Phase 4–7 per slice

# When "Epic ready for review" surfaces:
/craft:checkout epic-001          # cd into the merged-epic worktree to exercise the whole thing
/craft:checkout slice-A           # — or inspect a single slice in isolation
/craft:commit                     # merges epic-branch → main with --no-ff, archives every slice

# Or, for a single slice under a profile with Execution Mode: in-place:
/craft:execute slice-A            # in-place: branch in the main checkout, no commits, halts before Phase 5
                                  # review the raw uncommitted diff in your IDE, then:
/craft:release slice-A            # lift the halt → Phase 5 → … → /craft:commit

# Or, on a protected-`main` project (profile Merge: pull-request + Protected-main: yes):
/craft:commit                     # opens a PR (branch → main), halts — main NOT merged
                                  # approve the PR on GitHub (a real review), then:
/craft:commit                     # detects the approval and merges via gh ("Freigabe ≠ Merge")

# Or, on a profile with Epic Mode: sequential (slices one-by-one, in place):
/craft:execute epic-001           # runs the next slice in-place, commits it, halts for review
/craft:execute epic-001           # re-run continues at the next slice … until the epic is complete

# Or hands-off, per run (start the session with CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1):
/craft:execute epic-001 --autopilot   # unplanned entries first: slice-planner agents plan them, you approve the
                                      # package once at the plan gate after a plan-architect review
                                      # ([Y] run / [R] revise / [N] stop); then,
                                      # in place on epic-001-<slug>: builds, commits and logs each slice with
                                      # no halt between them; Phase 5 is verified by command from the plan's
                                      # <!-- craft:verify --> block (your deny/ask rules checked first); stops only where
                                      # a human is needed (re-run to resume) — and before your usage windows
                                      # run out (usage tap, see Requirements); at the end a generated digest
                                      # (scripts/epic-digest.sh) with the UX demo script as written and
                                      # "merge into main?" — main is untouched and the run locked until you answer

# Side tools:
/craft:worktree-status            # overview of all active worktrees
/craft:worktree-clean             # remove orphaned worktrees after manual aborts
```

Phase 5 (UX feedback), refactor decisions, and Heavy + needs-rethinking review findings always pause autonomous runs via a `.craft/handoff.md` marker — agents never fabricate human judgment. The exceptions are in an autopilot run: a refactor decision — up to two candidates are recorded, none applied, and listed in the epic-end digest; a slice that passes its committed `<!-- craft:verify -->` checks by command (D35) — its product feel comes to you in the epic-end UX demo script — and a Heavy + needs-rethinking finding, which gets one autonomous loop-back; if the next review round reopens it, or round 3 ends with a Heavy open, the ping-pong breaker blocks the slice and hands you a package of at most 15 lines. A bug in an autopilot run — a 2nd fix on the same symptom, or a failed committed check — first gets an autonomous `/craft:debug` loop whose every attempt `verify-run.sh` judges; you are asked only at its end stop (attempts exhausted, the protocol rejected twice, a check refused). To answer one, run `/craft:checkout <slice-id>`, open a session in the worktree it names, and run `/craft:continue`: a paused slice is resumed there (the only time it writes the plan) and routed to the command that takes your answer; a review handoff stays at `reviewing` and is routed to `/craft:review`; a blocked slice goes to `/craft:unblock`. An answered marker stops counting on its own — nothing needs deleting — except a `failure` marker, which counts until the retry.

#### Stuck on a bug

```
/craft:debug "reservation button doesn't show toast"
```

Triggers a 4-step verification loop: agree on the bug → agree on the verification protocol → autonomous fix attempts (max 5, with stricter token brake) → escalation if unresolved. Auto-offered when the agent detects ≥2 fix attempts on the same symptom.

---

## How It Differs From "Just Coding With an Agent"

This plugin assumes you've seen the failure mode of unstructured agent coding: after two hours, the agent has refactored things that already worked, the context window is in its dumb zone, and you no longer remember what was decided yesterday. The plugin enforces four disciplines:

| Discipline | What it does |
|---|---|
| **Context resets between phases** | Every phase ends with a Markdown checkpoint so a fresh session can pick up cleanly. |
| **Vertical slicing** | Every slice is end-to-end testable on its own. No "frontend now, backend later" splits. |
| **Knowledge layering** | State (code) is derived; Intent (`intent.md`) and Rules (`rules.md`) are explicit; agent proposes durable changes, you confirm. |
| **Explicit autonomy levels** | Reads run silent. Code edits in scope auto-continue. Rule mutations require confirmation. Pushes/deploys always ask. |

---

## Per-Phase Model Switching

The cognitively heaviest phases delegate to named subagents pinned at the right model:

| Phase | Subagent | Model |
|---|---|---|
| Execute (Phase 4 via `/craft:execute` orchestrator) | `slice-builder` | `sonnet` |
| Review (Phase 8) | `code-reviewer` | `opus` |
| Plan (Phase 3, autopilot run only) | `slice-planner` | `opus` |
| Plan review (autopilot run only) | `plan-architect` | `opus` |

The single-slice command `/craft:build` runs in-session and is **not** routed through a subagent — only the orchestrator path (`/craft:execute`, which spawns one `slice-builder` per slice in its own worktree) pins Sonnet.

Dialogic phases — Plan (Phase 3) and the Debug autonomous loop — stay on the active session model because their value lives in the interaction with you. Switch the session model yourself if you want Opus for those. Inside an autopilot run there is no one to ask: `slice-planner` plans each unplanned epic entry, `plan-architect` reviews the package as a whole, and you approve it once at the plan gate.

Projects can override any agent's model in `.claude/project/craft-profile.md` under `## Agent Model Overrides`:

```markdown
## Agent Model Overrides

- slice-builder: opus   # heavier judgment for a risky migration
- code-reviewer: sonnet # faster review for low-stakes slices
```

`/craft:prime` reports, per agent, the model CRAFT will ask for at spawn time. Model values are not validated — prime cannot tell a real model ID from a typo. A value the spawn parameter cannot carry is **dropped** rather than passed, so it does not fail at spawn time either; prime reports such an override as inert and the agent runs on its own default. See [`model-defaults.md`](./model-defaults.md) for which values a project override reaches, for the sources that can still decide the model outside CRAFT's reach, and for the full default table, the override resolution rules and the one-shot Issue-#173 verification procedure.

---

## CRAFT Profile

Each project gets a portable **operating profile** that bundles its autonomy, commit, merge, language, and model settings into one file — `.claude/project/craft-profile.md`. It is auto-read on every `/craft:prime`, may deviate freely from the shipped defaults, and is **portable**: copy it into a sibling project to reuse a setup.

Three named presets ship with the plugin (`/craft:onboard` copies one in; "give me the defaults" picks `balanced`):

| Preset | Execution | Auto-commit | Merge | Epic | Permissions |
|---|---|---|---|---|---|
| `careful` | in-place | off | protected-`main` PR you approve | sequential | minimal |
| `balanced` *(defaults)* | worktree | on | direct | parallel | standard |
| `autonomous` | worktree | on | direct | parallel | broad |

When no profile file is present, the implicit profile equals `balanced`, so adopting the profile system changes nothing until you edit it. `/craft:prime` reports the active profile and soft-warns on malformed values. See [`craft-profile-defaults.md`](./craft-profile-defaults.md) for the full field reference, resolution rules, and validation.

> **Rolling out.** The profile file format, presets, `/craft:prime` reporting, the guided `/craft:onboard` write-out, permission-scope allowlists, **in-place autonomous builds** (`/craft:execute` in-place → `/craft:release`), and the **"Freigabe ≠ Merge" PR flow** (`/craft:commit` on a `pull-request` + protected-`main` profile) all ship now. **Sequential epics** (`Epic Mode: sequential`, `direct` merge workflow) now ship too — the `autonomy-profiles` epic is complete (protected-main × sequential is a follow-up). Drop a preset at `.claude/project/craft-profile.md` (or run `/craft:onboard`) to use them.

---

## Project Files

When you run `/craft:onboard`, the plugin creates:

```
<your-repo>/
├── CLAUDE.md                       # Slim index pointing to the files below
├── .gitignore                      # + a "# CRAFT local state" block (see below)
└── .claude/
    ├── project/
    │   ├── intent.md               # Vision, goals, architectural decisions
    │   ├── rules.md                # Stack, conventions, deployment, tabus
    │   ├── craft-profile.md        # Portable operating profile (optional; autonomy/commit/merge/lang/models)
    │   ├── roadmap.md              # Long-term phases (optional)
    │   └── slices/                 # Archived completed slices (Decision Log)
    └── plans/                      # Active slice plans
```

CRAFT also writes local, per-clone state that must never be committed: the per-session prime
marker `.claude/plans/.primed`, the hook's `.claude/plans/.hook-env`, the `/craft:execute` run lock
`.claude/plans/.execute.lock` (never removed — its content says `held` or `released`), the autopilot's
cache-guard marker `.claude/plans/.cache-guard` (never removed either — `armed` or `disarmed`), the closed-plans
directory `.claude/plans/.closed/`, `.claude/settings.local.json`, and the worktree handoff marker
`.craft/`. `/craft:onboard` adds whichever of them your `.gitignore` files do not already cover to one
`# CRAFT local state` block. In a project onboarded before that, `/craft:prime` reports the uncovered
paths and offers to add them, and writes only after you say yes. Commit the `.gitignore` change.
Unignored, these files only clutter `git status` — CRAFT's own clean-tree checks do not count them, nor
its plans. Only rules in the project's own `.gitignore` files count; a personal global excludes file
does not, because teammates and CI don't have it. A path your `.gitignore` un-ignores on purpose
(`!.claude/settings.local.json`) is left as it is.

---

## Recommended Companion Plugins

CRAFT works standalone, but two adjacent plugins make Phases 3 and 4 noticeably smoother:

| Plugin | What it does | When CRAFT benefits |
|---|---|---|
| `context7` | On-demand library / framework / SDK docs lookup via MCP. Pulls authoritative API references for any library the agent is touching. | **Phase 3 (Plan)** and **Phase 4 (Execute)** — kills hallucinated library calls. The CRAFT workflow itself was validated using `context7`. |
| `context-mode` | Routes large command output (logs, test runs, doc fetches, page snapshots) into a sandboxed knowledge base; only summaries enter the conversation. | **Phase 4 (Execute)** and **Phase 5 (Test)** — keeps context-window pressure low on long-running implementations and test suites. `/craft:prime` already detects and reports its presence. |

Neither is required. CRAFT does not depend on either, and `/craft:prime` stays useful without them.

---

## Architecture

Detailed design rationale lives in this repository:

- [`brainstorm-decisions.md`](./brainstorm-decisions.md) — 28 architectural decisions with explicit reasoning
- [`plugin-architecture.md`](./plugin-architecture.md) — concrete build blueprint

---

## Acknowledgements

The 9-phase loop is inspired by Benjamin Thorstensen's *"Was ich nach 900 Stunden KI-Coding komplett anders mache"*.

The `brainstorm` and `grill-me` skills are adopted 1:1 from [benithors/skills](https://github.com/benithors/skills) (MIT-licensed), which in turn builds on Matt Pocock and Brian Madison's agent workflow methodology. Upstream copies of those skills' license live alongside each adopted skill as `LICENSE.upstream`.

---

## License

MIT — see [LICENSE](./LICENSE).
