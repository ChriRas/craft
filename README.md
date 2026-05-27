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

- **21 slash entry points** (17 commands + 4 slash-invocable skills) that move you through Brainstorm → Alignment → Planning → Implementation → Testing → Recap → Refactoring → Review → Commit & Cleanup, with explicit navigation cues at every session start.
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

# Side tools:
/craft:worktree-status            # overview of all active worktrees
/craft:worktree-clean             # remove orphaned worktrees after manual aborts
```

Phase 5 (UX feedback), refactor decisions, and Heavy + needs-rethinking review findings always pause autonomous runs via a `.craft/handoff.md` marker — agents never fabricate human judgment.

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

The single-slice command `/craft:build` runs in-session and is **not** routed through a subagent — only the orchestrator path (`/craft:execute`, which spawns one `slice-builder` per slice in its own worktree) pins Sonnet.

Dialogic phases — Plan (Phase 3) and the Debug autonomous loop — stay on the active session model because their value lives in the interaction with you. Switch the session model yourself if you want Opus for those.

Projects can override any agent's model in `.claude/project/rules.md` under `## Agent Model Overrides`:

```markdown
## Agent Model Overrides

- slice-builder: opus   # heavier judgment for a risky migration
- code-reviewer: sonnet # faster review for low-stakes slices
```

`/craft:prime` reports the effective model per agent and flags invalid entries. See [`model-defaults.md`](./model-defaults.md) for the full default table, the override resolution rules, and the one-shot Issue-#173 verification procedure.

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
