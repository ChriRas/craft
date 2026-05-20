# Intent

> What we want and why. Keep this file under ~80 lines — it loads on every `/craft:prime`. Operational instructions (verifiable against State) belong in `rules.md`, not here.

## Product Vision

CRAFT is a Claude Code plugin that wraps a disciplined, language-agnostic coding
workflow into reusable slash commands and skills. Dropped into any repository — shell
script, library, REST API, full-stack app, infrastructure code — it guides the agent
through the same phased loop with the same controls every time. Core principle:
universality with constant control.

## Active Goals

- **Implement D27** — Personality Autoload: the Senior-Developer baseline skill and
  the monolithic stack-packs. Decided, not yet built.
- **Implement D28** — the Review phase (Phase 8, Commit → 9): `/craft:review`, the
  2-axis findings rubric, fresh-agent invocation.
- **Refresh the README** — it is stale (decision count, command count, phase count).

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

## Non-Goals

- No MCP server for CRAFT (D25) — commands, skills, and hooks suffice for now.
- No per-user profile / behavior-preset system (D11).
- No short-name command shims — the `/craft:` namespace is the only entry surface.

## Open Questions

- D28's review agent loads D27's Senior-Developer baseline and stack-pack. Must D27
  be fully implemented before the D28 slice, or should D28 degrade gracefully when a
  pack is absent? (Sequencing question between the two implementation slices.)
