# Intent

> What we want and why. Keep this file under ~80 lines — it loads on every `/craft:prime`. Operational instructions (verifiable against State) belong in `rules.md`, not here.

## Product Vision

CRAFT is a Claude Code plugin that wraps a disciplined, language-agnostic coding
workflow into reusable slash commands and skills. Dropped into any repository — shell
script, library, REST API, full-stack app, infrastructure code — it guides the agent
through the same phased loop with the same controls every time. Core principle:
universality with **human control concentrated at the hard phases** (planning,
recap, review, escalated bugs); execution is delegated to safe, parallel agent work —
or, in the opt-in **autopilot mode**, narrowed to one plan gate and an epic-end sign-off.

## Active Goals

All seven original capabilities have shipped — hierarchical planning (B, slice-007), bugfix
autonomy (F, `skills/debug`), parallel worktree execution (C+D+E, slice-009), per-phase model
switching (G, slice-010), and onboarding language config (A, slice-012).

**Next capability: autopilot mode (D32)** — hands-off epic execution behind one plan gate;
design record in `.claude/project/design/autopilot-mode.md`, to be built as an epic.

## Architectural Decisions

The full decision log (D1–D33, with reasoning) lives in `brainstorm-decisions.md`;
the build blueprint in `plugin-architecture.md`. Headline decisions:

- **Two-tier model** — the plugin ships the universal shell; projects keep
  language/framework specialists locally, lazy-loaded. *Why not one monolith:* a
  universal workflow must carry no stack-specific weight.
- **`/craft:` namespace + single `/craft` entry skill** — avoids collisions with
  reserved names (`/plan` vs. Plan-Mode) and project-local command overrides.
- **Personality Autoload (D27)** — 3 tiers: Senior-Developer baseline, monolithic
  stack-packs, project overlay in `rules.md`.
- **Review as its own phase (D28)** — code review precedes Commit, with a
  severity × fix-nature findings rubric. A re-review sees every earlier round and verifies it
  first (slice-037): independence comes from the fresh context window, not from blinding — a
  blind reviewer cannot check the previous round's fixes on purpose.
- **Concentrated-control execution (D29)** — human owns hard phases (planning,
  recap, review, escalated bugs); execution is delegated to parallel agents in
  git worktrees. *Why not constant per-step control:* the per-step model is too
  slow once finely planned work can be parceled out and run in parallel.
- **Autopilot as opt-in inversion (D32)** — in an explicitly started autopilot run the human
  touches only the epic definition, one plan gate and the epic-end sign-off (plus escalations);
  agents plan, build, verify, review and commit on an epic branch. *Why opt-in, not default:*
  product feel and direction calls still need a human — outside autopilot, D21/D28/D29 apply
  unchanged, except that this repo pilots an evidence-based Phase 5 (D21) with a two-pass
  review (D28) — see D33.
- **Durable Capture** — planning/design output is written to a durable artifact in
  the same turn it is produced ("chat is not storage"); a routing table sends each
  kind to its home, with cross-cutting design knowledge (neither *why* nor *how*)
  living in `.claude/project/design/`. *Why a canonical home:* projects were inventing
  ad-hoc concept docs; a named slot closes the gap instead of codifying the workaround.
- **Prose is not checkable — markers are (slice-031)** — CRAFT's commands are Markdown prompts,
  so the phase graph they implement cannot be verified by grepping them: a search for a status
  literal cannot tell the sentence that *prescribes* a write from the one that *forbids* it.
  Affirmative writes, reads and delegations therefore carry machine-readable markers, the graph is
  declared once in `skills/workflow/SKILL.md`, and a harness binds the two. *Why not just grep:*
  five review rounds proved it green while checking nothing — a deleted routing branch stayed
  green because its literal survived in a "never write this" sentence. **What a marker does not
  do:** it binds its own *presence*, never the *meaning* of the prose beneath it. Keep the marker
  and invert the sentence and the check still passes. That residual is deliberate and disclosed;
  the alternative is a checker that must understand English, which is not a thing we can build.
- **Derived state over cleanup (slice-036)** — a worktree handoff marker is not deleted by the
  commands that resolve it; whether it still means "human needed" is derived from the slice plan's
  status, which is the truth. One helper decides, and doubt means live. *Why not* "every resolver
  deletes the marker": six resolvers, and one forgotten one brings the stale marker back — a
  derivation cannot be forgotten. *Why doubt means live:* a wrongly hidden handoff makes a waiting
  slice invisible; a wrongly shown one only costs noise.
  A `/craft:execute` re-run follows the same rule (slice-038): what an earlier run left behind —
  worktrees, merges, a stopped slice — is derived by one helper and built on, never re-created, and a
  state nothing accounts for stops the run instead of being overwritten.
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
