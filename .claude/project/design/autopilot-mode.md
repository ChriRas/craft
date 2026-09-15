# Autopilot Mode — Design Draft

> Status: banked as **D32** in `brainstorm-decisions.md` (2026-09-12) and carried into `intent.md` (Architectural
> Decisions → Autopilot as opt-in inversion). Being built as **epic-003** (`.claude/plans/epic-003-autopilot-mode.md`).
> The spike slice-044 (2026-09-15) resolved Q5 and §10's spike items for background subagents; the spike slice-045
> (2026-09-15) probed foreground builders and the builder's return path — verdicts in §2 / §4 / §6 / §7, probe recipes in
> §12; what stays open is listed in §10.
> Cross-cutting design knowledge for a future epic; on-demand reference, not loaded on prime.

## 1. Goal

A mode in which the human defines an epic (Vision + rough decomposition) and then hands the
**entire** remaining cycle to agents: slice planning → cross-slice architecture review →
sequential slice implementation (build → verify → review → fix → commit) → epic digest.
The human talks **only to the master agent** (the main session). Target: maximum code yield
per token, controlled and resumable, never spilling into paid extra usage.

## 2. Verified facts (2026-09-12; re-verified 2026-09-15 by the spikes slice-044 and slice-045, Claude Code 2.1.272)

Probe recipes: §12; raw numbers: the slice-044 and slice-045 archives. "docs" = code.claude.com, fetched 2026-09-15.

| Fact | Source | Confidence |
|---|---|---|
| Statusline input JSON carries `rate_limits.{five_hour, seven_day, spend_limit}.{used_percentage, resets_at}` (Pro/Max; docs: after the first API response — observed already at session start in probes 6 / 6b), `prompt_cache.{warm, ttl, expires_at, requests, recache_tokens_if_cold, …}` (**main conversation only** — subagent requests not counted), `context_window.*`, `cost.total_cost_usd` | statusline.md (v2.1.251+) + live JSON 2.1.271 / 2.1.272 | **documented + primary evidence** — the earlier "not in the official docs" no longer holds; still degrade gracefully |
| Official docs claim no in-session access to the 5h/7d window | monitoring-usage.md (2026-09-12) | **refuted** — statusline.md documents `rate_limits` |
| Statusline runs on events and "can go quiet while the main session is idle, e.g. waiting on background subagents"; `refreshInterval` (≥ 1 s) adds a timer | statusline.md + probe 6 (37 calls in 180 s at 5.0 s during a background subagent, all on the timer grid) + slice-045 runs 2, 3 (5.0 s grid also while the master was blocked on a foreground subagent; `cost` rose, `prompt_cache.requests` stayed) | `refreshInterval` cadence **confirmed** for background and foreground; going quiet without it — docs, not probed (no run without `refreshInterval`) |
| `cost.total_cost_usd` includes a running subagent's spend, live | probe 6 (rose in steps while `prompt_cache.requests` stayed) | **primary evidence** |
| Whether subagent requests move `rate_limits` | probe 6 (no change in ~5 min; ≈ $0.095 spent in the subagent window, $0.27 in the session) | **inconclusive** — whole-percent steps too coarse for a small run |
| Main-conversation TTL = 1 h on a subscription within plan (interactive turns **and `-p` runs**); 5 m on usage credits / API key | prompt-caching.md + probe 4 (a `-p` request wrote 21 860 tokens `ephemeral_1h`) | **documented + primary evidence** |
| Subagent / workflow / teammate / compaction requests default to 5 m; `subagentPromptCacheTtl` and a subagent's `experimental: {cacheTtl}` switch to 1 h — **also for plugin agents**; the frontmatter `1h` is ignored while the subscription uses usage credits (the setting is not) | prompt-caching.md, sub-agents.md + probe 5 (default re-wrote its ~5.4 k agent prefix — 5 917 written incl. the new turn — after a 5 min 53 s gap, while a 4.4 k base, likely left warm by the earlier 1 h runs, was read; plugin agent with `cacheTtl: 1h` read 12 329 tokens after 5 min 53 s) | **confirmed** |
| Subagent nesting depth 3 by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `1` disables) | env-vars.md | docs — master→builder→reviewer = depth 2, fits |
| Plugin agents support `model`, `effort`, `maxTurns`, `isolation`, `background`, `skills`, `experimental`; ignore `hooks`, `mcpServers`, `permissionMode` | sub-agents.md + probe 5 (`experimental` honoured) | docs + primary evidence |
| Subagent `model` ∈ `sonnet \| opus \| haiku \| fable \| <full model ID> \| inherit`; the Agent tool offers `sonnet \| opus \| haiku \| fable` | sub-agents.md + the Agent tool schema | documented + primary evidence; `claude plugin validate` checks no model value (accepts `not-a-model`) |
| `fable` (Fable 5.1) can, depending on plan and seat tier, bill to usage credits instead of plan limits (on this account: beyond its own Fable allotment, per the user); `-p` and the Agent SDK bill it **without asking**; a background session holds the consent prompt for `dialogExpiry` (5 min), then ends the turn | model-config.md | docs — not probed (cost) |
| Per-run token and cache counts: the subagent transcript's per-request `usage` (`cache_creation.{ephemeral_5m, ephemeral_1h}_input_tokens`, `cache_read_input_tokens`, `model`) | probes 3, 5, 6b | **primary evidence** (the task notification's `subagent_tokens` stays a second source). Internal helper agents leave **no** transcript (their `agent_transcript_path` does not exist) — about a third of the subagent-window spend in probe 6 (26.7 k master context), each helper costing about one cache read of the master prefix, so likely proportional to the master context — so a transcript sum undercounts; only `cost.total_cost_usd` holds all of it |
| A `UserPromptSubmit` block (`decision: "block"`) sends **no main-conversation request**; in `-p` the session-title helper (Haiku 4.5, ~900 tokens) still runs | hooks.md + probe 4 (headless) + probes 6 / 6b (interactive: `requests`, `cost` unchanged) | **confirmed** |
| `UserPromptSubmit` also fires for a subagent's hand-back and an async subagent's task notification; no payload field tells them from a human prompt — only the prompt text starts with `<agent-message from="…"> [Subagent hand-back]` / `<task-notification>`. The hand-back arrives **in every mode, foreground included** | probes 6, 6b + slice-045 runs 1–3 | **primary evidence** — markup undocumented, may change |
| In an interactive session a subagent delivers its report through a **`SubagentHandback` tool** (a start reminder: "Only a SubagentHandback call reaches your caller"); a subagent that ends a turn its caller started without calling it gets `[handback-send-enforce] Your report has not been delivered…` — so **a subagent must report before it can end such a turn**. After its report a **background** subagent can end its turn and be woken by its own background command (run 1: no enforcement on that wake) — an idle wait that costs an early report the master takes as the result, plus one delivery per wake. Not seen in `-p` | slice-045 runs 1–3 (tool, reminder, hand-back message in every interactive subagent transcript); enforcement **only in run 2** (3×: the first foreground turn, two `SendMessage` resumes); run 1 (the wake); smoke 3 | **primary evidence** — undocumented; enforcement in the default / background-tasks-off modes inferred, not observed (no hit in sub-agents / hooks / env-vars / statusline / tools-reference / interactive-mode) |
| `PostToolUse` on the Agent tool: `tool_response.status` = `completed` (foreground) / `async_launched` (background) — the documented, markup-free way to tell the modes apart | hooks.md → Agent + slice-045 smokes 1–3, runs 1–3 | **documented + primary evidence** |
| **`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`** → foreground in an interactive session: master blocked until the return (`completed` after 1 m 54 s), **one** delivery (the hand-back; the Agent result's `content` only points to it), no task notification, 2 main requests for the run ($0.29 — not like-for-like: this worker skipped the background path); Bash `run_in_background` gone (env-vars.md; the worker reported no such parameter — its own report, not checked against the tool schema); no helper agent during the 1 m 54 s spawn | slice-045 run 3 | **primary evidence** (one run) |
| **`CLAUDE_CODE_FORK_SUBAGENT=0`** → Claude chose foreground when the prompt needed the result (blocked, `completed`); but once the worker returned unfinished, the master resumed it with `SendMessage` — each resume ran in the **background** with hand-back + task notification again (4 hand-backs, 3 notifications, 12 main requests; $0.72, not like-for-like) | slice-045 run 2 | **primary evidence** (one run) — the choice is Claude's, not deterministic |
| **Default (fork mode on)** → `async_launched`, master turn ends at once; one worker produced **three** deliveries (hand-back, task notification, and a second task notification after its own background command woke it) — not a ceiling: each further wake or resume adds one | slice-045 run 1 | **primary evidence** (one run) |
| A background command outlives its subagent's final response only for a **background** subagent — it completed and **re-started the worker** (same `agent_id`); a **foreground** subagent's background command was killed (`[killed]`) | tools-reference.md → Background commands + slice-045 runs 1, 2 | **documented + primary evidence** |
| A background subagent keeps a narrower built-in tool set than a foreground one (both keep Bash, Monitor, TaskStop); `Monitor` reaches subagents as a **deferred** tool (ToolSearch first) — a subagent's own "no Monitor" report is unreliable | sub-agents.md → Available tools + slice-045 transcripts (`deferred_tools_delta`), smoke 2, run 2 | docs + primary evidence |
| Bash timeout ceiling `BASH_MAX_TIMEOUT_MS` (default 10 min); subagent stall abort `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS` (default 10 min without "progress") | env-vars.md | docs — **not probed** (a > 10 min wait) |
| `SubagentStart` / `SubagentStop` fire for plugin agents from plugin hooks; matcher = scoped `plugin:agent` (anchor `^…$` — filtering probed, exactness documented only); Stop carries `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `effort` — no token counts. Internal helper agents (≈ every 30 s while a background agent runs) also fire `SubagentStop`, with `agent_type: ""`; **none fired during the 1 m 54 s foreground spawns** of slice-045 runs 2 and 3 (first helper after the return; longer spawns not probed) | hooks.md + probes 3, 6b + slice-045 runs 1 (9 helpers), 2, 3 | **confirmed** |
| In an interactive session the Agent tool ran the subagent **asynchronously** (no `run_in_background`, no `background:` frontmatter): the main turn ends, the result returns as a hand-back message **and** a task notification — two or more deliveries for one result (three in slice-045 run 1, default row above); **also for a direct delegation to CRAFT's own `craft:code-reviewer`** | probes 6, 6b + slice-045 run 1 (P2) | **primary evidence** — for the default |
| Why: fork mode is on by default in interactive sessions, and then every Agent-tool subagent runs in the background ("Claude can't ask for the foreground"); it is off in `-p` / the SDK. `CLAUDE_CODE_FORK_SUBAGENT=0` turns it off (Claude then picks foreground when it needs the result), `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` forces foreground everywhere (and also removes Bash `run_in_background`) | sub-agents.md + slice-045 runs 2, 3 | **documented + primary evidence** (rows above; `FORK_SUBAGENT=0`'s choice was not deterministic — resumes went to the background) |
| Claude Code blocks a standalone `sleep` and `sleep N; …` in subagent Bash calls (the message points to Monitor / `run_in_background` and says not to chain shorter sleeps); other loop forms failed the headless permission check; `for n in $(seq 1 70); do sleep 5; done` passed — a workaround the block message discourages, which an update may close | probe 5 (runs a, a2, b, a3) | **primary evidence** |
| Workflow tool exists; plugins may ship `workflows/`; resume only same-session | workflows.md + tool description | docs (not re-checked) |

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
- **Model tiers — proposal** (user, 2026-09-15, slice-044; decided in epic planning; couples to roadmap D2). List prices
  per MTok input / output / cache hit: Opus 5 $5 / $25 / $0.50, Sonnet 5 $2 / $10 / $0.20 — Opus costs 2.5× Sonnet on
  every token class (how models weigh against the 5h / 7d windows is not documented).

  | Role | Model | Why |
  |---|---|---|
  | Master / orchestrator | **Sonnet** — *decided by the user* (effort medium: proposal) | reads helper output and digests; long cached context, where 2.5× hurts most. **Condition:** every decision needing real judgment goes to the human or a short-lived Opus agent — epic planning draws that line; Opus is the fallback if it cannot be drawn |
  | slice-planner | Opus (Fable only when the human chooses it) | planning is the hard phase |
  | plan-architect | Opus, effort high | overlaps, contracts, order |
  | slice-builder | Sonnet, effort high | bulk of the tokens; executes an approved plan |
  | builder after a ping-pong trip | Opus | a stronger round beats more Sonnet rounds |
  | E2E verification | Sonnet | runs a committed Test Strategy |
  | code-reviewer | Opus (as today) | independent judgment |
  | digests / recap | Sonnet | Haiku saves too little for the risk |

  Model names stand for D2 tiers (Opus = deep-reason, Sonnet = execute). **How "master on Sonnet" is realised:** the
  master is the main session, and a command's `model` frontmatter switches only that turn, re-reads the whole context
  uncached and reverts on the next prompt (prompt-caching.md) — so CRAFT cannot hold the master on Sonnet (hand-backs
  would come back on the session model anyway): the human starts the session on Sonnet and `/craft:autopilot` checks it. The per-spawn overrides (builder after a trip, a human-chosen
  Fable planner) are a resolution source beyond `model-defaults.md` → Resolution Order ("no further sources") — decided in
  epic planning.

  **Fable is never called automatically** (user, 2026-09-15): on this account it has its own allotment (about half a
  weekly limit, per the user), usage beyond it bills to credits, and `-p` bills without asking. Efficiency levers beside
  the model: a lean master, a tight reviewer brief, per-agent `effort`, per-agent cache TTL (§6), no model switch inside
  the master run. `model-defaults.md` still allows only `opus|sonnet|haiku|inherit`, and the enum is copied in seven
  files (`model-defaults.md` twice, `commands/prime.md` step 4b, `templates/craft-profile.md.template`, three profile
  templates, `docs/index.html`) — define it once and add `fable` / full model IDs for a human-chosen override (a D2
  item, §8).
- **How a builder returns — three modes, probed** (slice-044 probes 6 / 6b; slice-045 runs 1–3, §2):
  - *Default (fork mode on):* background. The master's turn ends, and one builder reached it **three times** in run 1
    (hand-back, task notification, and another notification when a background command the builder left running woke it
    after its report) — not a ceiling: each further wake or resume adds one. The master must de-duplicate on `agent_id` and pays one main request per duplicate. The builder
    keeps `run_in_background` + Monitor; it can wait idle only after its report (below), and a command it leaves running
    re-starts it.
  - *`CLAUDE_CODE_FORK_SUBAGENT=0`:* Claude picks. Foreground when it needs the result, but a builder that returns
    unfinished is resumed with `SendMessage` in the background, and the duplicates come back. Not deterministic — the
    most main requests of the three (12).
  - *`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`:* foreground. The master blocks until the builder's report, which arrives
    **once**; no task notification, no helper agent during the 1 m 54 s spawn, the fewest main requests (2, vs. 5 for the
    default's worker part). The builder's only wait path is a blocking foreground command (≤ `BASH_MAX_TIMEOUT_MS`,
    default 10 min), and the switch is session-wide — it also takes `run_in_background`, auto-backgrounding and Ctrl+B
    from the master (env-vars.md; the run-3 worker reported no such parameter — not checked against the tool schema).
  - *Numbers* are one run per mode, and the workers took different paths (run 3's skipped the background command, run 1
    also carried the P2 delegation), so compare main requests and deliveries — the dollar figures are not like-for-like.
  - *Every mode:* the report goes through the undocumented `SubagentHandback` tool and reaches the master as a
    `UserPromptSubmit` hand-back message; ending a turn its caller started without it triggers `[handback-send-enforce]` (seen in
    run 2), so **a builder must report before it can wait idle**. Only a background builder can wait idle after its report
    (run 1), and then its report is early and each wake adds a delivery — useless for a builder whose report *is* the
    result. A builder that must wait for its result waits inside a tool call. `PostToolUse` on the Agent tool
    (`status: completed | async_launched`) tells the master which mode a spawn actually ran in.
  - **Decided — Q8 (§9): foreground via `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`.**
- **This reaches today's CRAFT, not only autopilot** (slice-044 review; **confirmed for the agent by slice-045**): by
  default (fork mode on) a direct delegation to `craft:code-reviewer` — the agent `/craft:review` spawns; a trivial brief
  from a plain prompt, not a `/craft:review` run — received its result twice (hand-back + task notification, one extra main
  request). `/craft:review` and `/craft:execute`'s `slice-builder` are expected to behave alike (not run).
  `model-defaults.md` is stale in two statements — "Subagents block their parent on a single return" (async by default
  now) and "exact model IDs … not officially documented" (sub-agents.md documents them).

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
    (per-sub-task commits make this safe); handoff. *Under Q8 (§9) the master is blocked during a spawn, so this rule
    and the overage stop need a home inside the builder or a D32 amendment — `budget-and-cache-guard` decides.*
  - `seven_day ≥ 90%` → stop after the current slice.
  - overage heuristic: window ≥ 99% **and** `prompt_cache.ttl == 5m` → immediate stop + loud warning.
- Strongest protection is outside CRAFT: disable extra usage in the account settings (human action).
- **Sensor facts (slice-044):** the statusline command needs `refreshInterval` — its event triggers go quiet while the
  master idles on a background builder. `cost.total_cost_usd` is a live spend signal that includes subagents;
  `rate_limits` moves in whole percent and did not visibly react to a small subagent run, so per-slice calibration
  measures Δ over whole slices, not per request. Token and cache counts per agent come from the subagent transcript
  (`agent_transcript_path` in `SubagentStop`) — but internal helper agents (about every 30 s while a background agent
  works) leave no transcript: about a third of the subagent-window spend in probe 6 (26.7 k master context), visible only
  in `cost.total_cost_usd`, so calibration uses `cost` and treats a transcript sum as a lower bound.
  **Foreground builders (slice-045 runs 2, 3):** the `refreshInterval` timer keeps ticking while the master is blocked,
  and `cost` rises live while `prompt_cache.requests` stays flat — the sensor works unchanged. No helper agent fired during
  a 1 m 54 s foreground run, so their spend (and whatever cache refresh they give, next bullet) is absent there.
- **The master's cache on long builds — unverified:** the statusline's `expires_at` counts main requests only and goes
  stale while the master idles (it held for 175 s of helper activity in probe 6). Whether the server-side cache also
  expires is open: each helper in probe 6 cost ≈ one read of the main prefix (≈ $0.0056 vs. 26.7 k × $0.20/MTok ≈
  $0.0053), and forks read the parent's cache (prompt-caching.md), so the helpers likely read — and refresh — the master's
  cache about every 30 s. Then a long build does not cost a master re-write, but the helpers' spend scales with the master
  context (≈ $2.4/h for a 100 k Sonnet master while a builder runs) — another reason for a lean master. With a
  **foreground** builder no helper read was seen during a 1 m 54 s spawn (slice-045 runs 2, 3); if that holds for long
  spawns, the master's cache rests on its 1 h TTL alone, so a single builder spawn longer than 1 h likely meets a cold
  master — unverified, not probed.
- **Overage beyond Fable stays open:** whether usage-credit spend shows in `rate_limits` at all is unverified. Never
  selecting `fable` (§4) closes the Fable path only; the general overage path (Opus / Sonnet past the plan limit with
  extra usage enabled) still rests on the thresholds above, the 5 m-TTL heuristic — whose reliability this gap leaves
  open — and extra usage disabled in the account.
- **Cache TTL per agent (Q5, slice-044):** default subagent TTL 5 m re-writes the agent's prefix after every gap > 5 min;
  `experimental: {cacheTtl: 1h}` in the agent file works for plugin agents. With API list multipliers — writes 1.25× (5 m)
  / 2× (1 h), reads 0.1× — a gap costs the 5 m agent 1.25× its context and the 1 h agent a 0.1× read, so 1 h pays off once
  the contexts re-written at gaps sum to more than ≈ 0.65 × the final context: one long wait after the context reached
  about two thirds of its size, or two waits in the second half; without such waits 1 h costs ~60 % more on writes. How
  cache writes count against the 5h / 7d windows is not documented — calibration decides. So: 1 h for a builder that runs
  long test suites or waits on services, 5 m for short-burst agents; the frontmatter `experimental` may change and its
  `1h` is ignored on usage credits (the `subagentPromptCacheTtl` setting is not), so the choice must degrade to a
  re-write, not an error. A builder that must wait needs an explicit wait path — a plain `sleep` is blocked in subagent
  Bash calls, and `run_in_background` + Monitor is the path the block message names.
- **The builder's wait path (slice-045):** a builder **cannot wait idle before its report** — in an interactive session the
  `SubagentHandback` enforcement forces a report first (seen in run 2, §2, §4), and idling after the report (possible only
  in the background, run 1) hands the master an unfinished result. It waits inside a tool call: a blocking foreground Bash command
  worked in every mode (45 s — a script wrapping `sleep`; a direct `sleep` stays blocked, §2; ceiling
  `BASH_MAX_TIMEOUT_MS`, default 10 min, not probed beyond). `run_in_background` +
  Monitor only helps a builder that keeps working meanwhile — Monitor returns at once, and its events arrive as queued
  notifications at the builder's next tool boundary (smoke 2); with `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`
  `run_in_background` is gone. A command a foreground builder leaves running is killed at its report; one a background
  builder leaves running outlives the report and re-starts the builder when it ends. Rule for builder prompts: **never
  leave a background command running at the report, and wait by blocking.** Whether a blocking command near the 10 min
  stall window (`CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`) aborts the builder is open (§10).

## 7. Cache guard (idle human answer)

- Before **any** turn that ends waiting on the human, the master writes the handoff **first**
  (pre-emptive — no timer needed) and states the cache expiry from `prompt_cache.expires_at`:
  "Cache warm until HH:MM. Answer later → `/clear`, then `/craft:autopilot resume epic-NNN`."
- Optional `UserPromptSubmit` hook (plugin hooks are allowed): if an autopilot marker is active and
  `now > expires_at` **and** `recache_tokens_if_cold > threshold` → block the prompt (no API call)
  with the restart instruction. A lean master makes the threshold rarely hit.
- **Buildable, with two constraints (slice-044):** a blocked prompt sends no main request — confirmed headless and
  interactive; the cost is at most a session-title helper call. But `UserPromptSubmit` also fires for a builder's
  hand-back (in every mode, foreground included — slice-045 run 3) and an async builder's task notification, and the
  payload has no source field. The hook must let through every prompt starting
  with `<agent-message from=` or `<task-notification>` — otherwise it blocks the very result the master waits for — and,
  since that markup is undocumented, **fail open**: anything it cannot classify as a plain human prompt passes.
- **Arming rule (slice-044 review):** the marker is armed only by a turn that ends waiting on the **human**, and disarmed
  when the master spawns a builder — a builder running longer than 1 h would otherwise meet an armed guard that reads the
  stale statusline `expires_at` as cold at its hand-back, in the normal loop (possibly while helper reads keep the server
  cache warm, §6). The markup pass-through is the second line of defence. *Residual:* a
  hand-back format that drops the leading markup would be blocked while the marker is armed; §12 recipe 6 re-checks the
  format on each Claude Code update. With foreground builders (§4) the pass-through **is still needed** — the hand-back
  arrives as a `UserPromptSubmit` there too (slice-045 run 3), though no task notification does.

## 8. Candidate epic decomposition (rough)

> Superseded by epic-003's seven entries (2026-09-15): item 1 was already done, 2a became `model-tiers`, item 8 is kept in
> sync per slice and the 2.0.0 release follows the epic; a `builder-return-probe` spike (slice-045) leads. Kept for history.

1. D32 + intent update (autopilot as opt-in inversion of concentrated control)
2. Usage & cache sensor (tap reader script + harness) — with `refreshInterval`; live spend from `cost.total_cost_usd`,
   per-agent tokens / cache writes from the subagent transcript via a `SubagentStop` hook keyed on `agent_id` (a lower
   bound — helpers leave no transcript); per-agent TTL choice (§6)
   - **2a. Model tiers (roadmap D2):** per-agent models (§4), the model enum defined once with `fable` / full IDs, the
     stale `model-defaults.md` statements — shipped surface, not only autopilot
3. Planning pipeline: `slice-planner` + `plan-architect` agents, plan gate
4. Slice loop orchestrator `/craft:autopilot` + digest + commit policy + status-graph rows/markers
5. Autonomous verification (Phase-5 replacement) + two-agent protocol freeze
6. Ping-pong breaker (finding IDs, round counters)
7. Budget guard + cache guard hook (armed only while waiting on the human, hand-back pass-through, fail open — §7) +
   handoff/resume
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
- **Q7 → The autopilot builder works in place** (user, 2026-09-15). Slices are built in the main checkout on the
  epic branch — no slice worktrees. The plan status then lives in the one checkout the master and `/craft:commit` read,
  so the worktree plan round-trip (roadmap B15) is not needed for autopilot; parallel worktree mode keeps B15 for
  itself. *Cost:* the main checkout is occupied for the whole run — the human must not edit files or switch branches
  there while it runs.
  - **Requirement — the run is made visible** (user). The human is shown how the process runs: at the plan gate
    (before approving) and at the start of the run — that it builds in place, on which branch, that the checkout is
    occupied and what not to do meanwhile, the slice order, where it will stop for the human (escalations, budget stop,
    epic-end sign-off), and how to pause, resume and stop it; while it runs, a progress line per slice (which slice,
    which phase, what landed on the epic branch). Wording and exact place are for the epic's planning slice.
  - **Open for epic planning:** each slice committed directly on the epic branch, or on a short-lived
    `<slice-id>-<slug>` branch in the same checkout merged `--no-ff` into the epic branch (Q3's "one merge per slice");
    how this relates to the existing sequential epic mode (in place, landing per slice on the trunk) — likely autopilot
    reuses that path with the epic branch as the landing target.
- **Q8 → Builders run in the foreground** (user, 2026-09-15, on slice-045's evidence and recommendation). The autopilot
  session runs with `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (set at launch or through a settings `env` entry — §10), and
  `/craft:autopilot` checks it before the run and confirms each spawn ran in the foreground (how — §10). *Why:* one
  delivery per builder, deterministic, the fewest main requests (slice-045, one run per mode: 1 delivery / 2 requests vs.
  3 / 5 in the default's worker part and 7 / 12 with fork mode off), no helper agent during the 1 m 54 s foreground spawns.
  The background mode buys a builder no usable idle wait either: it must report before ending a turn its caller started,
  so waiting idle in the background means an early report the master takes as the result (§4).
  *Why not* the default with de-duplication: three deliveries per builder in run 1 and no ceiling, a master request each,
  and a builder's leftover background command re-starts it; *why not* `CLAUDE_CODE_FORK_SUBAGENT=0`: Claude's choice,
  resumes fall back to the background (run 2, the most requests). *Consequences:* builders wait by blocking commands only (no
  `run_in_background`, no auto-backgrounding; tests beyond `BASH_MAX_TIMEOUT_MS` need the setting raised); the master is
  unresponsive during a spawn, so pause / stop mid-spawn is Esc — its resulting state is for `autopilot-loop`; the §7
  hand-back pass-through stays; duplicate handling and a builder's Monitor path are not needed. Open risks in §10 (stall
  timeout, spawns longer than the master's 1 h TTL, the undocumented `SubagentHandback`).
  - **Consequence for D32's budget guard and Q7's progress line** (slice-045 review R1-1; the user kept Q8, 2026-09-15): a
    master blocked inside the Agent call cannot watch usage or stop a builder mid-slice, so §6's in-slice rules (`≥ 95%`
    → stop at the next sub-task boundary; overage → immediate stop) and Q7's progress line (which slice, which phase) cannot live in the
    master during a spawn. Where they live instead is open — a check inside the builder at its sub-task boundaries (e.g.
    reading a usage tap file), a hook firing inside the builder, or amending D32 to stops between spawns only — and is
    decided by epic-003's `budget-and-cache-guard` (the in-slice stop) and `autopilot-loop` (the progress line). The
    before-a-slice and after-a-slice rules are unaffected: they run between spawns.

## 10. Still open

- ~~**Q5** Subagent cache TTL `1h` vs. `5m`~~ — **resolved by slice-044**: per agent, by the break-even in §6.
- **Q6** Threshold defaults (85 / 95 / 90) and whether they live in `craft-profile.md` (new `## Autopilot` block).
- **Master / judgment line** (from §4): which decisions the Sonnet master may take from helper output alone, and which go
  to the human or a short-lived Opus agent — epic planning.
- **Open after slice-044:**
  - ~~foreground builders: whether `CLAUDE_CODE_FORK_SUBAGENT=0` / `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` give the master
    a foreground return, the statusline cadence, hook events and duplicate hand-back in that case, and which wait path a
    builder keeps under each~~ — **resolved by slice-045** (§2, §4, §6); the mode is decided — Q8 (§9): foreground;
  - whether the internal helper agents read and keep warm the master's cache (§6), and whether they run for foreground
    builders (slice-045: none during 1 m 54 s foreground spawns; longer spawns not probed);
  - whether subagent requests move `rate_limits` at all (needs a larger run than a probe);
  - whether usage-credit spend shows in `rate_limits` (§6 overage);
  - what a `model: fable` subagent spawned by the master does (consent prompt, 5-min `dialogExpiry`, silent credit
    billing) — decide before a human-chosen Fable planner is allowed in Stage A;
  - the hand-back / task-notification markup is undocumented and must be re-checked on Claude Code updates (§12 recipe 6);
  - what the runtime does with an invalid frontmatter `model`;
  - the Workflow tool evaluation (D32 engine, §9 Q4) — deliberately not part of slice-044.
- **Open after slice-045:**
  - `SubagentHandback` and its `[handback-send-enforce]` are undocumented and appeared only in interactive sessions —
    re-check on Claude Code updates (§12 recipe 7), and whether `-p` gains them;
  - Q8's mechanics (`autopilot-loop`): whether the switch is set at launch or through a settings `env` entry, and how the
    master confirms a spawn ran in the foreground — the synchronous Agent result, or a `PostToolUse` hook, which as a
    plugin hook would fire in every CRAFT session;
  - how a builder waits on a service under `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` if an update closes the script
    workaround: a direct `sleep` is blocked, and the block message's alternative (`run_in_background` + Monitor, §12
    recipe 5) does not exist in that mode — not probed;
  - whether a blocking builder command near 10 min trips `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`, and what a test suite
    longer than `BASH_MAX_TIMEOUT_MS` needs (raise the setting, split the suite);
  - whether a foreground spawn longer than the master's 1 h TTL leaves the master cold (§6);
  - where D32's in-slice budget stop and Q7's progress line (which slice, which phase) live while the master is blocked on a foreground
    builder (§9 Q8 consequence) — `budget-and-cache-guard` / `autopilot-loop`;
  - how the human pauses or stops a master blocked on a foreground builder (Esc / Ctrl+C mid-spawn) and what state that
    leaves — `autopilot-loop`;
  - an unexplained 51 s delay on one builder `echo` in run 3 (auto-mode classifier latency suspected, unverified), and
    which permission mode an autopilot session runs in;
  - `/craft:execute`'s `slice-builder` under fork mode (expected to deliver twice like `craft:code-reviewer`; not run).
- **Outside autopilot** (slice-044 review, §4): `model-defaults.md` is stale on subagents blocking their parent and on
  full model IDs, and interactive delegations receive each result twice (**confirmed for a direct `craft:code-reviewer`
  delegation, slice-045**; `/craft:review` and `/craft:execute` expected alike, not run) — fixes for the shipped surface,
  not only F6: the stale statements belong to epic-003 `model-tiers` / roadmap D2, the duplicate delivery is recorded as
  an epic-003 deferred decision (not in `model-tiers`' scope).
  The intent Non-Goal "no per-command model frontmatter — Claude Code does not support it" rests on a premise the docs now
  contradict (a command's `model` switches one turn, prompt-caching.md) — its conclusion for autopilot stands (§4).
- **Observed 2026-09-13 (slice-033 probes):** two headless Claude Code *sessions* started concurrently
  left the context-mode MCP server "failed" (cached, ~15 min) for later child sessions. Fan-out across
  separate sessions can knock out a shared MCP dependency; in-session subagents share the parent's
  connections — another argument for Q4's master + subagents engine. Verify before any parallel design.
- **Spike items** — resolved by slice-044 (§2, §4, §6, §7): ~~statusline refresh cadence during a subagent~~ (for a
  **background** subagent with `refreshInterval`; foreground resolved by slice-045), ~~whether a blocked `UserPromptSubmit`
  prompt really makes no API call~~, ~~`fable` alias vs. `model-defaults.md` enum~~.

## 11. Prerequisites before the epic (assessed 2026-09-14, after slice-040; updated 2026-09-15, after slice-045)

Open roadmap fixes weighed against §3–§5 and Q3/Q4. Autopilot runs unattended, so a gap that today
costs a human one manual step stops or misroutes the whole run.

| Item | Why it blocks autopilot | Verdict |
|---|---|---|
| **B12** epic decomposition ↔ slice-ID | Every resume re-validates the epic (`/craft:execute` A6); an entry without a slice-ID is rejected once its first slice has landed, so the run halts after slice 1 until a human edits the entry. The `slice-planner` agent (§4 Stage A) also needs the rule for who links an entry to its slice. | **done — slice-041**: `/craft:plan` links, A6 resolves through `scripts/epic-entry-link.sh`; the planner agent should link through the same helper. Follow-up R1-9 (commit / s0 / continue still read entries themselves) is worth folding into the orchestrator work |
| **B11** handoff resolution from `paused` + marker revival (slice-036 R2, R3) | The master consumes every `.craft/handoff.md` (§4). A `paused`-paired marker stays live after its answer (a re-run stops at step 0), and a stale marker revives when the plan re-enters its paired status — exactly what the ping-pong breaker's loop-back to `reviewing` does repeatedly (§5). Result: phantom escalations or a stuck loop. | **done — slice-042**: pauses record `Paused-status` / `Paused-since`, `/craft:continue` 4a is the one resume, and markers carry `Episode:` (stamp or review round), so a loop-back into `reviewing` gives `episode_mismatch`. Follow-up R1-15 (a resume records no answer, so a re-run meets the question again) belongs to the orchestrator work |
| **B15** plan round-trip in worktree mode (slice-039 R2-7) | Would block only a builder in a slice worktree, which writes plan status into the worktree copy while the master reads the main checkout. | **not needed** — Q7: the autopilot builder works in place. Stays a fix for parallel worktree mode |
| **Release** (slice-033 … slice-042 unreleased) | Not a fix: the installed 1.4.0 lacks the handoff liveness, findings record, execute re-run, tree hygiene and plan landing that autopilot builds on, plus the docs-site / CHANGELOG carry-over. Dogfooding against the old runtime tests a foundation that does not exist there. | **done — slice-043**: CRAFT v1.5.0 released and installed; a fresh session's `/craft:prime` reports v1.5.0 without drift |
| **B17** subdirectory-project settings helpers | Only a project below its repository root; not this repo. | after |
| **B5** toolchain polish | Cosmetic. | after |

**Order:** ~~builder location~~ (Q7: in place) → ~~B12~~ (slice-041) → ~~B11~~ (slice-042) → ~~release~~ (slice-043, v1.5.0) → ~~F6 spike slice~~ (slice-044) → ~~epic planning~~ (epic-003, 2026-09-15). Further order: epic-003's decomposition (first entry: the builder-return probe, slice-045 → Q8).

**Versioning** (user, 2026-09-15): the prerequisite release is **1.5.0**, an interim release that only lays the
foundation; **autopilot mode ships as 2.0.0** — the big new feature carries the major bump.

## 12. Probe recipes (slice-044, slice-045; re-run after Claude Code updates)

All probes run from scratch fixtures outside the repo, one at a time, one fixture per parent directory, on `--model
sonnet` (never `fable`: `-p` bills credits without asking). A throwaway plugin (`.claude-plugin/plugin.json`, `agents/`,
`hooks/hooks.json`) is loaded with `--plugin-dir`; results are read from the hook log, `--output-format json` and the
session / subagent transcripts under `~/.claude/projects/<fixture>/<session>[/subagents/agent-<id>.jsonl]`.

1. **Docs pass** — fetch hooks, statusline, prompt-caching, sub-agents, model-config, settings-reference, env-vars
   (`https://code.claude.com/docs/en/<page>.md`) and pricing, models/overview
   (`https://platform.claude.com/docs/en/about-claude/<page>.md`); compare with §2 and §4's prices.
2. **Model values** — plugin agents with `model:` `opus` / `fable` / a full ID / `not-a-model` through `claude plugin
   validate` (the negative shows validate checks nothing); Agent-tool enum from the session's tool schema.
3. **Subagent hooks** — plugin hooks for `SubagentStart` (matcher `^<plugin>:<agent>$`, a never-matching matcher as the
   negative, one without) and `SubagentStop`, each logging stdin; `claude -p "delegate to <plugin>:<agent> …"`.
   Expect: start + stop for the agent, nothing for the negative matcher (that shows filtering; to test exactness add a
   near-miss such as `^<agent>$` without the plugin prefix).
4. **Blocked prompt** — `UserPromptSubmit` hook returning `{"decision":"block","reason":…}` for a marker word; two `-p`
   runs, blocked and allowed. Expect: blocked `num_turns 0`, no main-model usage; allowed writes the main cache.
5. **Subagent TTL** — agent doing `echo` → `for n in $(seq 1 70); do sleep 5; done` → `echo`, the agent prompt setting
   the Bash tool timeout to 420000 ms (the loop runs ~350 s); `claude -p … --allowedTools "Bash(echo:*)" "Bash(sleep:*)"`;
   runs: default, `experimental: {cacheTtl: 1h}`, `--settings '{"subagentPromptCacheTtl":"1h"}'`. Expect, on the request
   after the gap: default re-writes the agent prefix at 5 m; 1 h reads it. A plain `sleep` is blocked, and the loop form
   works around a block whose message says not to chain sleeps — if an update blocks it too, wait via
   `run_in_background` + Monitor (not available under Q8's `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, §10). Earlier 1 h runs can leave a shared base prefix warm; read the agent-specific part.
6. **Statusline + async subagent, interactive (human-run)** — `claude --settings <file> --plugin-dir <plugin> --model
   sonnet` with a statusline command logging every call (`refreshInterval: 5`), a settings file that also allows
   `Bash(sleep:*)`, `Bash(echo:*)`, `Bash(for:*)`, `Bash(seq:*)`, and hooks logging `UserPromptSubmit` /
   `SubagentStart` / `SubagentStop` **with full payloads** (6b); sequence: delegate a ~2–3 min worker → wait → a blocked
   prompt → `/exit`. Expect: calls every 5 s during the worker, `cost` rising with it, `prompt_cache.requests` flat;
   hand-back and task notification arriving as `UserPromptSubmit` prompts with their leading markup; helper
   `SubagentStop`s with `agent_type: ""`; no change after the blocked prompt.
7. **Builder return per mode, interactive (human-run, slice-045)** — three fixtures in separate parent directories, one per
   environment: none (fork mode on), `CLAUDE_CODE_FORK_SUBAGENT=0`, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`; launch
   `claude --plugin-dir ./plugin --model sonnet` (the slice-045 runs used the user's auto permission mode — record the mode) and accept the trust dialog (headless `-p` ignores an untrusted project's
   `permissions.allow`). Project settings allow `Bash`, `Monitor`, `Read`, `TaskStop` and set the statusline logger
   (`refreshInterval: 5`); plugin hooks log the full payload **plus both env vars** for `UserPromptSubmit`,
   `SubagentStart`, `SubagentStop`, `PreToolUse`, `PostToolUse`, `Stop`, `Notification`. Worker (`model: sonnet`): a 45 s
   blocking Bash command, a Bash `echo PARTIAL …` line (evidence that survives a lost report), then a 45 s
   `run_in_background` command + Monitor and **end the turn** with a marker text, continuing only after the notification.
   Prompt: delegate to the worker, reply with its result line only; in the default run add a delegation to
   `craft:code-reviewer` (`model` sonnet, trivial brief). Read: `PostToolUse` Agent `tool_response.status`; count
   `UserPromptSubmit` prompts starting with `<agent-message from=` / `<task-notification>` per `agent_id`;
   `prompt_cache.requests` and `cost` per run; `SubagentHandback` and `[handback-send-enforce]` in the subagent transcript;
   whether the background command's marker file exists (killed vs. completed) and whether a second `SubagentStart` for the
   same `agent_id` follows it. Expect (2.1.272): default `async_launched` + two or more deliveries (3 in slice-045 run 1); fork off: foreground, then
   background resumes with duplicates; background tasks off: `completed`, one hand-back, no `run_in_background`. Do not
   trust the worker's own report on tools or waits — check the transcript.
