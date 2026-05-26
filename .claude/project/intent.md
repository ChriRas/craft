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

Two of the original seven capabilities have shipped: **hierarchical planning (B)**
via `/craft:epic` (slice-007) and **bugfix autonomy (F)** via `skills/debug`. The
remaining five-capability expansion, sequenced:

1. **Parallel worktree execution (C+D+E)** — agents build in parallel git
   worktrees; subagents report ready-for-checkout when user action is required;
   full checkout/provisioning at Recap/Review for environment testing.
2. **Model switching per phase (G)** — Opus for planning/review, Sonnet for
   execution; defined per role/phase.
3. **Onboarding language config (A)** — three independent settings (chat,
   commits, code comments) configurable at onboarding.

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

## Non-Goals

- No MCP server for CRAFT (D25) — commands, skills, and hooks suffice for now.
- No per-user profile / behavior-preset system (D11).
- No short-name command shims — the `/craft:` namespace is the only entry surface.

## Open Questions

- **Per-agent model selection mechanics** — config location and override scope
  for G. Resolved when G is planned.
- **Worktree lifecycle** — when are parallel worktrees created, merged back,
  and cleaned up? Resolved with C+D+E.
