# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | F6 | Feature | epic | Autopilot mode (D32): hands-off epic execution — planner/architect agents, one plan gate, sequential slice loop on an epic branch, ping-pong breaker, budget + cache guards, epic-end sign-off |
| 2 | B15 | Fix | slice | Parallel worktree mode needs the plan round-trip: hand the plan in, read its status back — slice-builder writes the plan status only into the worktree copy, so `/craft:commit` never detects a Slice-finalize, even for committed plans; a never-committed plan now stops at `plan_not_committed` (slice-039 R2-7) |
| 3 | B17 | Fix | small | Settings helpers in a subdirectory project write the repo-root `settings.local.json` but report the project-dir `GITIGNORED` verdict (slice-039 R1-13) |
| 4 | F7 | Feature | epic? | Idle cache guard (braindump): when the human stays away past the prompt-cache TTL, wake shortly before expiry, write the slice handoff, keep the cache warm a bounded number of times, and block a prompt into a cold session — avoids the full-history re-write on return |
| 5 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 6 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |
| 7 | F5 | Feature | slice | Windows support: require Git for Windows or WSL 2, detect a PowerShell-only setup — **untested, needs a Windows machine** |
| 8 | B5 | Fix | small | Toolchain polish: `⚠ Hook bash` line as informational when nothing is affected (R2); status-graph harness guard checks only the bash version, not the full helper (R3) |
| 9 | F8 | Feature | epic | **End of the chain.** Other AI coding agents: make CRAFT usable beyond Claude Code — e.g. OpenAI Codex CLI, OpenCode — **verify each tool's extension surface first** |

## Notes per item

**R1 shipped with slice-043 — CRAFT v1.5.0 (2026-09-15).** The installed runtime carries slice-032 … slice-042; a fresh
session's `/craft:prime` reports v1.5.0 without drift, and the D33 Dock launch showed the hook receiving the Homebrew bash
(details in `.claude/project/slices/slice-043-r1-release.md`). Still unshown by a real run: push / PR / backfill and the
worktree finalize modes under protected main (slice-040), `/craft:execute` A6 against a real epic (slice-041), the
interactive `/craft:continue` 4a dialog (slice-042). `test-docs-site.sh` does not check the required-tools list.

**B11 shipped with slice-042.** Its follow-up R1-15 (a resume records no answer to the handoff's question, so a
subagent re-run meets it again) is in `.claude/project/slices/slice-042-b11-handoff-resolution-from-paused.md` →
Follow-ups; F6's orchestrator must decide where an answer is stored.

**B12 shipped with slice-041.** Its follow-up R1-9 (the other `## Slice Decomposition` readers — `/craft:commit`
Epic-finalize, `/craft:execute` s0, `/craft:continue` — still judge entries themselves) is in
`.claude/project/slices/slice-041-b12-epic-slice-id-link.md` → Follow-ups; worth folding into F6's orchestrator work.

**B15, B17 — follow-ups from slice-039** (B16 shipped with slice-040). Details in
`.claude/project/slices/slice-039-b9-b10-b13-b14-tree-hygiene.md` → Follow-ups and Known limits. B15 is what parallel
worktree mode needs before anyone relies on it — no longer an F6 prerequisite, since the autopilot builder works in place.

**F6 — Autopilot mode.** Banked as D32 (2026-09-12); design record with verified facts, touchpoint
matrix and open spike items in `.claude/project/design/autopilot-mode.md`. F4 shipped (slice-033):
the bash ≥ 5.0 baseline its usage/cache sensor scripts assume is in place. B2 shipped (slice-032):
slices that change `commands/` / `agents/` are verified via headless `--plugin-dir` probes (D33),
not the running session. Starts with a spike slice (statusline refresh during subagent runs, blocked-prompt API behavior, subagent cache
TTL, `fable` alias vs. `model-defaults.md`). Couples to D2: planner/architect/reviewer vs. builder
are exactly the capability tiers D2 wants to name. **Prerequisites** (assessed 2026-09-14, updated 2026-09-15, design record §11): all done —
B12 (slice-041), B11 (slice-042), the R1 release (slice-043, v1.5.0); next is the F6 spike slice. **The autopilot builder works in place** on the epic branch (user,
2026-09-15, design record §9 Q7) — so B15 is no F6 prerequisite — and the run must show the human how it proceeds
(in place, branch, occupied checkout, slice order, stops, pause / resume).

**F7 — Idle cache guard (braindump, 2026-09-13).** *Problem:* a human who leaves mid-session (lunch,
a question the agent asked and nobody answers) returns after the prompt-cache TTL has expired; the next
prompt re-processes the whole conversation as uncached input, however full the window is — pure cost,
no progress. *Idea:* watch the idle time; shortly before expiry (~55 min on a 1 h TTL) the agent
notices the human is gone and secures the state, so a fresh session resumes exactly where they left.
*User decisions:* scope = **active slices only** (reuse `/craft:handoff` → slice plan; sessions
without a slice stay unguarded); on wake = **write handoff + keep the cache warm (bounded repeats) +
block a prompt into a cold session** with the restart instruction (`/clear` → `/craft:continue`);
placed **after F6**, and F6 §7 stays autopilot-specific. *Verified 2026-09-13 (code.claude.com
hooks + prompt-caching docs):* the main session gets 1 h TTL on a subscription within its included usage, 5 m
in overage and for subagents; async command hooks have no enforced timeout; an `asyncRewake` hook
exiting 2 wakes Claude immediately even when idle; `Notification` `idle_prompt` fires ~60 s after a
turn ends; hooks fire with no dedup across firings. *Mechanism sketch:* a turn-end hook spawns an
`asyncRewake` sleeper tagged with a generation token; `UserPromptSubmit` bumps the token so a returning
human silently cancels it; the woken turn reads the still-warm cache (cheap) and writes the handoff;
each further wake refreshes the TTL (cap N, then stop and let it go cold); the prompt block uses
`prompt_cache.expires_at` / `recache_tokens_if_cold` (statusline JSON — undocumented, may change).
*Spike items:* does an open `AskUserQuestion` / permission dialog end the turn (Stop) or not?
Does a rewake work while a dialog is open? Which hook event carries the sleeper best (Stop vs.
`idle_prompt`)? Cost of N keep-warm reads vs. one cold re-write (verify current pricing), and
what to do on a 5 m TTL (overage) — likely skip keep-warm and handoff early. Is the pre-emptive F6 §7
handoff enough to reuse, or should F6 §7 later adopt F7's sleeper? Opt-in via the CRAFT profile, or on by default?

**F5 — Windows support.** Official docs (2026-09-12): native Windows runs without Git for Windows;
Git Bash only *enables* the Bash tool, and hook commands run through Git Bash — or PowerShell when
Git Bash is absent. A PowerShell-only setup therefore breaks CRAFT: all three hooks call `bash …`
(the read-only guard would then fail open — a non-starting hook blocks nothing; verify), commands
prescribe bash syntax, `scripts/` is bash. No PowerShell port (it would describe every rule twice).
Instead: require Git for Windows or WSL 2, detect the PowerShell-only case in `/craft:prime`, document
it. Open risks even with Git Bash: `python3` often absent or a Store alias; hook `tool_input` paths
arrive with backslashes, and the read-only guard's normalizer is POSIX-shaped. Needs a real Windows
machine to test — until then, WSL 2 is the only setup that can be recommended with confidence.

**F3 — Cleanup skill.** Epic. Novel core = fidelity check: strip/condense comments → fresh-context review must reconstruct the same information breadth (fixed "why does this exist / what decision does this encode" battery, diffed before/after) → write back on loss. Scope param repo/epic/slice; uses archive context; interactive; may drop now-irrelevant historical decisions.

**D2 — Model tiers.** Bind roles to capability tiers, not model names; project maps tiers → models (Fable 5 becomes config, not code). Serves token-efficiency (expensive reasoning only at hard phases). Couples to D1's spawn-threshold (make it tier-configurable). Caveats: verify Fable 5's real behavior before rewriting policy; "open to other coding tools" is the separate, larger track F8.

**F8 — Other AI coding agents (braindump, 2026-09-14).** *Goal (user):* CRAFT's workflow and harness usable from AI
coding agents other than Claude Code — named: OpenAI Codex CLI, OpenCode — placed at the very end of the chain, after
F6 and everything before it. *Nothing about those tools is verified yet* — their extension points (instruction files,
custom commands, sub-agents, hooks, MCP, plugin packaging, headless mode) change fast; research each one before any
design. *What is Claude-Code-bound today (from the repo):* the plugin manifest + marketplace, `commands/` as slash
commands, `skills/`, `agents/` spawned via the Task tool, the three `hooks/` (SessionStart prime trigger, the read-only
guard, the hook-env record), `${CLAUDE_PLUGIN_ROOT}` path resolution, `AskUserQuestion`-style dialogs, `CLAUDE.md`,
headless `claude -p --plugin-dir` probes (D33), and for F6 the statusline JSON. *Already portable:* the Markdown
methodology, `scripts/` helpers and harnesses, git / gh. *Open questions:* one neutral core with generated per-tool
adapters vs. hand-written ports — the tabu "a rule is never described twice" rules out parallel copies; which
guarantees survive where a tool has no hooks (the read-only guard fails open) or no sub-agents (fresh-context review,
D28); how model tiers (D2) map onto non-Anthropic models; whether context-mode / agent-browser stay required.
