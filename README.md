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

A Claude Code plugin that wraps a disciplined, language-agnostic coding workflow into reusable slash commands and skills. Drop it into any repository — shell script, library, REST API, full-stack web app, data pipeline, infrastructure code — and the agent will guide you through the same 8-phase loop with the same controls every time.

> **Core principle:** Universality with constant control. Same workflow, same control surface, regardless of stack.

---

## What the Plugin Gives You

A complete coding-loop scaffolding:

- **17 slash commands** that move you through Brainstorm → Alignment → Planning → Implementation → Testing → Recap → Refactoring → Commit & Cleanup, with explicit navigation cues at every session start.
- **5 universal skills**: the 8-phase workflow itself, bug-verification protocol, structured brainstorming, interview-style alignment, browser automation.
- **A two-tier architecture**: the plugin ships the universal shell; your project keeps its own language/framework specialists in `.claude/skills/` and `.claude/agents/`, lazy-loaded at runtime.
- **A SessionStart hook** that auto-runs `/prime` so every fresh chat orients itself before you type anything.
- **A migration path** for projects that already have a `.claude/` setup — `/onboard` detects the existing content and moves conflicting commands to `_legacy/` while preserving project-specific specialists.

---

## Installation

> The plugin is not yet in the official marketplace. For now, clone and install locally.

```bash
git clone <repo-url> ~/.claude/plugins/craft
```

After install, open Claude Code in any project and run `/onboard` to set the project up.

---

## Quickstart

#### First time in a project

```
/onboard
```

`/onboard` either bootstraps a fresh `.claude/project/` setup or migrates an existing `.claude/` configuration. It generates `intent.md`, `rules.md`, and optional `roadmap.md` either from heuristics (fast path) or via the interview-style "Grill-Me" mode (deeper).

#### Every subsequent session

The SessionStart hook fires `/prime` automatically. You'll see a status block:

```
✓ Project: <name> (<stack summary>)
✓ Rules ↔ State drift check: clean
✓ Tools: context-mode ✓ (activated), agent-browser ✓, git ✓, gh ✓

Active slices:
  → slice-007 "PWA reservation button" — Phase 4, 3/7 sub-tasks done

Recommended next: continue slice-007 (Phase 4)
  → /continue to resume, /plan to start something new
```

#### Building a feature

```
/plan reservation button          # Phase 3 — dialogic planning
/execute                          # Phase 4 — implementation
/test                             # Phase 5 — you exercise the artifact
/recap                            # Phase 6 — capture what was learned
/refactor                         # Phase 7 — make it cleaner
/commit                           # Phase 8 — atomic commits + slice archive
```

#### Stuck on a bug

```
/debug "reservation button doesn't show toast"
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

When you run `/onboard`, the plugin creates:

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

## Architecture

Detailed design rationale lives in this repository:

- [`brainstorm-decisions.md`](./brainstorm-decisions.md) — 22 architectural decisions with explicit reasoning
- [`plugin-architecture.md`](./plugin-architecture.md) — concrete build blueprint

---

## Acknowledgements

The 8-phase loop is inspired by Benjamin Thorstensen's *"Was ich nach 900 Stunden KI-Coding komplett anders mache"*.

The `brainstorm` and `grill-me` skills are adopted 1:1 from [benithors/skills](https://github.com/benithors/skills) (MIT-licensed), which in turn builds on Matt Pocock and Brian Madison's agent workflow methodology. Upstream copies of those skills' license live alongside each adopted skill as `LICENSE.upstream`.

---

## License

MIT — see [LICENSE](./LICENSE).
