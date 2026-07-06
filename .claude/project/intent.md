# Intent

> What we want and why. Keep this file under ~80 lines — it loads on every `/craft:prime`. Operational instructions (verifiable against State) belong in `rules.md`, not here.

## Product Vision

CRAFT is a Claude Code plugin that wraps a disciplined, language-agnostic coding
workflow into reusable slash commands and skills. Dropped into any repository — shell
script, library, REST API, full-stack app, infrastructure code — it guides the agent
through the same phased loop with the same controls every time. Core principle:
universality with **human control concentrated at the hard phases** (planning,
recap, review, escalated bugs); execution is delegated to safe, parallel agent work.

## Active Goals

All seven original capabilities have shipped: **hierarchical planning (B)** via
`/craft:epic` (slice-007), **bugfix autonomy (F)** via `skills/debug`, the
**parallel worktree execution cluster (C+D+E)** via `/craft:execute` + the
`slice-builder` agent (slice-009), **model switching per phase (G)** via subagent
delegation with `rules.md` overrides (slice-010), and **onboarding language
config (A)** — three independent chat/commit/comment settings in the
`## Operational Language` block (slice-012).

No capability work remains; further slices are enhancements and maintenance.

## Architectural Decisions

The full decision log (D1–D28, with reasoning) lives in `brainstorm-decisions.md`;
the build blueprint in `plugin-architecture.md`. Headline decisions:

- **Two-tier model** — the plugin ships the universal shell; projects keep
  language/framework specialists locally, lazy-loaded. *Why not one monolith:* a
  universal workflow must carry no stack-specific weight.
- **`/craft:` namespace + single `/craft` entry skill** — avoids collisions with
  reserved names (`/plan` vs. Plan-Mode) and project-local command overrides.
- **Personality Autoload (D27)** — 3 tiers: Senior-Developer baseline, monolithic
  stack-packs, project overlay in `rules.md`.
- **Review as its own phase (D28)** — code review precedes Commit, with a
  severity × fix-nature findings rubric.
- **Concentrated-control execution (D29)** — human owns hard phases (planning,
  recap, review, escalated bugs); execution is delegated to parallel agents in
  git worktrees. *Why not constant per-step control:* the per-step model is too
  slow once finely planned work can be parceled out and run in parallel.
- **Durable Capture** — planning/design output is written to a durable artifact in
  the same turn it is produced ("chat is not storage"); a routing table sends each
  kind to its home, with cross-cutting design knowledge (neither *why* nor *how*)
  living in `.claude/project/design/`. *Why a canonical home:* projects were inventing
  ad-hoc concept docs; a named slot closes the gap instead of codifying the workaround.
- **Approve ≠ merge on protected `main` (epic Decision D)** — in a project whose profile
  sets protected-`main` PR mode, `/craft:commit` runs `gh pr merge` itself, but **only after
  a real human GitHub PR approval** (never `--admin`, so branch protection genuinely gates
  it). A deliberate reinterpretation of the Senior-Developer baseline's *"do not self-merge;
  the human decides on review and merge"*: the human **approves**, the system merges.
  *Why:* collapses the flow to "everything in the PR → approve → auto-merge" while the human
  stays the real gate.

## Non-Goals

- No MCP server for CRAFT (D25) — commands, skills, and hooks suffice for now.
- No per-user profile / behavior-preset system (D11).
- No short-name command shims — the `/craft:` namespace is the only entry surface.
- No per-command model frontmatter — Claude Code does not support it; per-phase
  model selection routes through subagents only. Dialogic phases (Plan, Debug
  autonomous loop) are NOT delegated either — their streaming/pause UX is
  incompatible with a subagent boundary (slice-010).

## Open Questions

(none currently)
