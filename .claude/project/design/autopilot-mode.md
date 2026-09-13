# Autopilot Mode — Design Draft

> Status: banked as **D32** in `brainstorm-decisions.md` (2026-09-12). `intent.md` update pending
> (`/craft:intent-update`). Open items in §10 are resolved by the epic's spike slice.
> Cross-cutting design knowledge for a future epic; on-demand reference, not loaded on prime.

## 1. Goal

A mode in which the human defines an epic (Vision + rough decomposition) and then hands the
**entire** remaining cycle to agents: slice planning → cross-slice architecture review →
sequential slice implementation (build → verify → review → fix → commit) → epic digest.
The human talks **only to the master agent** (the main session). Target: maximum code yield
per token, controlled and resumable, never spilling into paid extra usage.

## 2. Verified facts (2026-09-12)

| Fact | Source | Confidence |
|---|---|---|
| Statusline input JSON carries `rate_limits.five_hour.{used_percentage,resets_at}`, `rate_limits.seven_day.{…}`, `prompt_cache.{ttl,expires_at,warm,recache_tokens_if_cold}`, `context_window.*`, `cost.total_cost_usd` | live `~/.claude/statusline-last.json`, Claude Code 2.1.269 | primary evidence — but not in the official hooks/monitoring docs; treat as **may change**, degrade gracefully |
| Official docs claim no in-session access to the 5h/7d window | code.claude.com/docs/en/monitoring-usage.md (via research agent) | contradicted by the live JSON above |
| Main-session cache TTL on subscription = 1h; drops to 5m in extra-usage/overage | code.claude.com/docs/en/prompt-caching.md + harness tool description | high |
| Subagent/workflow requests default to 5m TTL; `subagentPromptCacheTtl` (`5m`/`1h`) configurable | prompt-caching.md | docs — verify in a spike |
| Subagent nesting depth 3 by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`) | sub-agents.md | docs — master→builder→reviewer = depth 2, fits |
| Plugin agents support `model`, `effort`, `maxTurns`, `isolation`, `background`, `skills`; ignore `hooks`, `mcpServers`, `permissionMode` | sub-agents.md | docs |
| Agent results report `subagent_tokens` per run | observed in this session's task notification | primary evidence |
| `UserPromptSubmit` hooks can block a prompt | hooks.md | docs — verify that a blocked prompt triggers **no** API call |
| Workflow tool exists; plugins may ship `workflows/`; resume only same-session | workflows.md + tool description | docs |
| `SubagentStart`/`SubagentStop` hook events | not found in official reference | UNVERIFIED |
| Statusline refresh cadence while a foreground subagent runs | — | UNVERIFIED — user's `usage-watch.py` already handles STALE |

## 3. Where CRAFT today deliberately stops for a human

Autopilot must decide, per touchpoint, **agent-resolves** or **escalate to master → human**.

| Touchpoint (today) | Where | Autopilot proposal |
|---|---|---|
| Phase 3 three universal questions (dialogic) | `/craft:plan` | slice-planner agents answer from Vision + codebase; architect agent reviews |
| Epic → slice planning | `/craft:epic` + manual `/craft:plan` | planner fan-out |
| Phase 5 human exercise `[W]/[B]/[U]` ("cannot be skipped") | `/craft:test` → `awaiting-test` | **intent conflict** — agent-run E2E verification from the committed Test Strategy (+ agent-browser for UI); human UX check batched at epic end (open question Q2) |
| Phase 6 recap dialog | `/craft:recap` | subagent draft already exists; becomes the per-slice digest source |
| Phase 7 candidates never applied unsupervised | `/craft:refactor` → `awaiting-refactor-decision` | skip in autopilot; candidates → epic digest |
| Phase 8 Heavy+Rethink → human routing | `/craft:review` → `awaiting-rethink-decision` | one autonomous loop-back to build; ping-pong breaker (§5) before escalation |
| 2nd same-symptom fix → debug protocol negotiated with human | `/craft:build` → `awaiting-protocol` | protocol drafted by builder, **frozen by the reviewer agent** (two-agent freeze replaces human freeze) |
| Out-of-scope blocker | `awaiting-block-decision` | always escalate (direction call stays human) |
| Phase 9 commit split confirm (Level 1) | `/craft:commit` | autonomous (Level 2) inside autopilot |
| Phase 9 `[K]/[I]/[R]/[D]` promotion | `/craft:commit` | default `[K]`; `[I]`/`[R]` candidates collected for the human at epic end — `intent.md`/`rules.md` stay Level 0 |
| Push / PR / merge to main | Level 0 | stays human (open question Q3) |

**Intent impact:** this relaxes "Phase 5 cannot be skipped" and "human control concentrated at the
hard phases (planning, recap, review, escalated bugs)". It needs a banked decision (D32) and an
`/craft:intent-update` — autopilot is an explicit, opt-in inversion, not a silent erosion.

## 4. Architecture proposal

```
Human ──(epic vision + decomposition)──▶ MASTER (main session, lean context, never codes)
                                          │
  Stage A  Planning                       ├─▶ slice-planner ×N  (fresh ctx, writes slice plans + Touches: forecast)
                                          ├─▶ plan-architect ×1 (fresh ctx: overlaps, contracts, deps/order, sizing)
                                          │     └─ max 2 revision rounds, then → human plan gate (Q1)
  Stage B  Slice loop (sequential)        │
     for each slice in dependency order:  ├─ budget guard (§6) — start only if forecast fits
                                          ├─▶ slice-builder (build + autonomous verification + recap draft)
                                          ├─▶ code-reviewer (fresh ctx) ⇄ builder fix rounds  (ping-pong breaker §5)
                                          ├─ commit (atomic, Slice: footer) + archive + digest line
                                          └─ escalation? → blocked + master asks human (cache guard §7)
  Stage C  Epic end                       └─▶ epic digest: per-slice summary, heavy findings fixed,
                                              follow-ups, promotion candidates, UX demo script, token spend
```

- **Master keeps only digests**, never raw diffs or logs. State lives on disk
  (`epic plan → ## Autopilot Log`), so a restart costs ≈ prime + log, not the whole history.
- **Reuse, don't duplicate** (D31, "a rule is never described twice"): phase commands keep their
  `## Subagent Mode`; they still write `.craft/handoff.md`. The master consumes each handoff and
  applies the §3 resolution matrix — the matrix lives in **one** place.
- **Model tiers** (couples to roadmap D2): planner/architect/reviewer on the strong tier, builder on
  the execution tier, master on the session model. The Agent tool now offers a `fable` alias;
  `model-defaults.md` allows only `opus|sonnet|haiku|inherit` → must be revisited.

## 5. Ping-pong breaker

- Every review finding gets a stable ID (`F<round>-<n>`). From round 2 on, the reviewer receives
  the previous findings and must mark each `resolved | still-open | disputed` before adding new ones.
- **Deterministic trip rules** (counters written to the slice plan, not held in prose):
  - a finding `still-open` in two consecutive rounds, **or**
  - review rounds > `Max review rounds` (default 3), **or**
  - builder disputes the same finding twice.
- On trip: convert the finding into a **verification protocol** (command + expected + negative
  check), frozen by builder + reviewer, run the `/craft:debug` autonomous loop (max 5 attempts).
  Still red → slice `blocked` (`decision`), master escalates with a ≤15-line package
  (finding, attempts, hypotheses ruled out, options).
- Same path for Phase 4: 2nd same-symptom fix → autonomous protocol instead of `awaiting-protocol`.

## 6. Budget guard (5h / 7d window)

- **Sensor:** statusline JSON (CRAFT would ship a tap script or document it; the user already runs
  `statusline-tap.sh` + `usage-watch.py`). Degrade: no/stale data → conservative mode
  (stop after every slice and ask).
- **Calibration:** per slice, record `Δ five_hour %` and `subagent_tokens`. Rolling average = forecast.
- **Rules (defaults, profile-configurable):**
  - before a slice: `used% + forecast > 85%` → do not start; write handoff; report `resets_at`.
  - during a slice (usage-watch band event): `≥ 95%` → stop at the next sub-task boundary
    (per-sub-task commits make this safe); handoff.
  - `seven_day ≥ 90%` → stop after the current slice.
  - overage heuristic: window ≥ 99% **and** `prompt_cache.ttl == 5m` → immediate stop + loud warning.
- Strongest protection is outside CRAFT: disable extra usage in the account settings (human action).

## 7. Cache guard (idle human answer)

- Before **any** turn that ends waiting on the human, the master writes the handoff **first**
  (pre-emptive — no timer needed) and states the cache expiry from `prompt_cache.expires_at`:
  "Cache warm until HH:MM. Answer later → `/clear`, then `/craft:autopilot resume epic-NNN`."
- Optional `UserPromptSubmit` hook (plugin hooks are allowed): if an autopilot marker is active and
  `now > expires_at` **and** `recache_tokens_if_cold > threshold` → block the prompt (no API call)
  with the restart instruction. A lean master makes the threshold rarely hit.

## 8. Candidate epic decomposition (rough)

1. D32 + intent update (autopilot as opt-in inversion of concentrated control)
2. Usage & cache sensor (tap reader script + harness)
3. Planning pipeline: `slice-planner` + `plan-architect` agents, plan gate
4. Slice loop orchestrator `/craft:autopilot` + digest + commit policy + status-graph rows/markers
5. Autonomous verification (Phase-5 replacement) + two-agent protocol freeze
6. Ping-pong breaker (finding IDs, round counters)
7. Budget guard + cache guard hook + handoff/resume
8. Docs site / README / CHANGELOG

Note roadmap **B2**: runtime executes the plugin cache, not the working tree — autopilot slices that
touch `commands/` cannot be verified end-to-end in the session that writes them.

## 9. Decisions taken (user, 2026-09-12)

- **Q1 → Plan gate: yes.** After the architect review the human gets the compact slice package +
  architect findings and approves **once**; from then on the run is hands-off. Planning stays the one
  hard phase in human hands.
- **Q2 → Agent E2E + batched UX check at epic end.** Each slice is verified by the agent executing its
  committed end-to-end Test Strategy (agent-browser for UI), evidence logged; the epic digest ships a
  bundled demo script for the human product-feel check.
- **Q3 → Epic branch, human merges at the end.** Agents commit atomically on `epic-<NNN>-<slug>`
  (one `--no-ff` merge per slice); `main` stays untouched until the human's go-ahead at epic end.
- **Q4 → Master session + subagents.** Builds on `slice-builder` / `code-reviewer`, resumable across
  sessions via handoff; ping-pong counters live in the slice plan and are harness-checked. The
  Workflow tool is evaluated later in a spike, not the foundation.

## 10. Still open

- **Q5** Subagent cache TTL `1h` vs. `5m` — measure in a spike (1h writes cost more, 5m misses on long test runs).
- **Q6** Threshold defaults (85 / 95 / 90) and whether they live in `craft-profile.md` (new `## Autopilot` block).
- **Observed 2026-09-13 (slice-033 probes):** two headless Claude Code *sessions* started concurrently
  left the context-mode MCP server "failed" (cached, ~15 min) for later child sessions. Fan-out across
  separate sessions can knock out a shared MCP dependency; in-session subagents share the parent's
  connections — another argument for Q4's master + subagents engine. Verify before any parallel design.
- **Spike items:** statusline refresh cadence during a foreground subagent; whether a blocked
  `UserPromptSubmit` prompt really makes no API call; `fable` alias vs. `model-defaults.md` enum.
