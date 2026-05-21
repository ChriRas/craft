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

> **Core principle:** Universality with constant control. Same workflow, same control surface, regardless of stack.

---

## What the Plugin Gives You

A complete coding-loop scaffolding:

- **20 slash entry points** (16 commands + 4 slash-invocable skills) that move you through Brainstorm → Alignment → Planning → Implementation → Testing → Recap → Refactoring → Review → Commit & Cleanup, with explicit navigation cues at every session start.
- **6 universal skills**: the 9-phase workflow itself, the Senior-Developer baseline (loaded every session), bug-verification protocol (`/craft:debug`), structured brainstorming (`/craft:brainstorm`), interview-style alignment (`/craft:grill-me`), browser automation.
- **A two-tier architecture**: the plugin ships the universal shell; your project keeps its own language/framework specialists in `.claude/skills/` and `.claude/agents/`, lazy-loaded at runtime.
- **Personality autoload**: the Senior-Developer baseline above is the universal Tier 1; on top of it, optional **stack-packs** (e.g. `stack-php-laravel`) — language/framework idiom packs a project declares in `rules.md` — load automatically during the code-near phases.
- **A SessionStart hook** that auto-runs `/craft:prime` in Craft-onboarded projects so every fresh chat orients itself; stays silent in non-Craft projects.
- **A migration path** for projects that already have a `.claude/` setup — `/craft:onboard` detects the existing content and moves conflicting commands to `_legacy/` while preserving project-specific specialists.

---

## Installation

CRAFT is distributed as a Claude Code plugin from a marketplace — and this repository *is* the marketplace (it ships `.claude-plugin/marketplace.json`). Install it from inside Claude Code:

```
/plugin marketplace add <repo-url>
/plugin install craft@craft
```

The first command registers this repository as a plugin marketplace; the second installs the `craft` plugin from it (`craft@craft` — the `craft` plugin from the `craft` marketplace). Restart the session to activate the commands and skills.

To move to a later release, run `/craft:upgrade` — it syncs the marketplace clone and Claude Code re-installs the new version on the next session start.

After install, open Claude Code in any project and run `/craft:onboard` to set the project up.

All plugin commands are invoked through the `craft:` namespace — `/craft:onboard`, `/craft:plan`, `/craft:commit`, etc. The full namespace form is required: internal cross-references between commands rely on it to avoid collisions with Claude Code reserved names (e.g. `/plan` would otherwise collide with Plan-Mode) and with project-local `commands/<name>.md` overrides.

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
✓ Tools: context-mode ✓ (activated), agent-browser ✓, git ✓, gh ✓

Active slices:
  → slice-007 "PWA reservation button" — Phase 4, 3/7 sub-tasks done

Recommended next: continue slice-007 (Phase 4)
  → /craft:continue to resume, /craft:plan to start something new
```

In a project that has not been onboarded to Craft, the hook stays silent — no nudge. Invoke `/craft:onboard` yourself if you want to adopt the workflow there.

#### Building a feature

```
/craft:plan reservation button    # Phase 3 — dialogic planning
/craft:execute                    # Phase 4 — implementation
/craft:test                       # Phase 5 — you exercise the artifact
/craft:recap                      # Phase 6 — capture what was learned
/craft:refactor                   # Phase 7 — make it cleaner
/craft:review                     # Phase 8 — independent fresh-eyes review
/craft:commit                     # Phase 9 — atomic commits + slice archive
```

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

## Project Files

When you run `/craft:onboard`, the plugin creates:

```
<your-repo>/
├── CLAUDE.md                       # Slim index pointing to the files below
└── .claude/
    ├── project/
    │   ├── intent.md               # Vision, goals, architectural decisions
    │   ├── rules.md                # Stack, conventions, deployment, tabus
    │   ├── roadmap.md              # Long-term phases (optional)
    │   └── slices/                 # Archived completed slices (Decision Log)
    └── plans/                      # Active slice plans
```

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
