# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | B11 | Fix | slice | Handoff resolution from `paused`: `/craft:continue`, build resume, a refactor skip and `/craft:debug` write no status, so `paused`-paired markers (test, protocol, scope, refactor) stay live after the human answered; and a stale marker revives when the plan re-enters its paired status (slice-036 R2, R3) |
| 2 | B12 | Fix | slice | Epic decomposition ↔ slice-ID: `/craft:epic` writes entries without a slice-ID and nothing adds one, so `/craft:execute` A6 rejects an ordinary epic's re-run once its first slice has landed, until the entry is edited by hand; decide who links an entry to its slice (`/craft:plan` from an epic, `/craft:commit` on archive) or match a landed slice by slug (slice-038 R3-6) |
| 3 | B15 | Fix | slice | Parallel worktree mode needs the plan round-trip: hand the plan in, read its status back — slice-builder writes the plan status only into the worktree copy, so `/craft:commit` never detects a Slice-finalize, even for committed plans; a never-committed plan now stops at `plan_not_committed` (slice-039 R2-7) |
| 4 | B17 | Fix | small | Settings helpers in a subdirectory project write the repo-root `settings.local.json` but report the project-dir `GITIGNORED` verdict (slice-039 R1-13) |
| 5 | F6 | Feature | epic | Autopilot mode (D32): hands-off epic execution — planner/architect agents, one plan gate, sequential slice loop on an epic branch, ping-pong breaker, budget + cache guards, epic-end sign-off |
| 6 | F7 | Feature | epic? | Idle cache guard (braindump): when the human stays away past the prompt-cache TTL, wake shortly before expiry, write the slice handoff, keep the cache warm a bounded number of times, and block a prompt into a cold session — avoids the full-history re-write on return |
| 7 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 8 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |
| 9 | F5 | Feature | slice | Windows support: require Git for Windows or WSL 2, detect a PowerShell-only setup — **untested, needs a Windows machine** |
| 10 | B5 | Fix | small | Toolchain polish: `⚠ Hook bash` line as informational when nothing is affected (R2); status-graph harness guard checks only the bash version, not the full helper (R3) |

## Notes per item

**Next release (carry-over from slice-033, extended by slice-034 through slice-040).** Update `docs/index.html` (EN/DE)
via the docs-site skill — it still lists four required tools and `test-docs-site.sh` does not check the
list. Verify a real Dock/IDE launch of Claude Code live (the D33 hands-on test waived in slice-033). B3
shipped (slice-034): the review loop-back and the per-round findings record reach normal sessions only
with that release. B4 shipped (slice-035): add its CHANGELOG entry, and update the docs-site project tree
(`docs/index.html` ~l.1030–1040 — `.primed` / `.hook-env` / `.craft/` and the `.gitignore` block are missing,
`settings.local.json` still says "gitignored"). After the release `/craft:prime` offers the block in every
consumer repo — `settings.local.json` included, even where only a personal global excludes file covers it.
B7 shipped (slice-036): add its CHANGELOG entry — handoff markers count only while the slice plan waits;
this too reaches normal sessions only with the release.
B6 shipped (slice-037): add its CHANGELOG entry — a re-review verifies earlier rounds first, and which
findings are open is read by `scripts/review-findings-state.sh`; also release-gated.
B8 shipped (slice-038): add its CHANGELOG entry — a `/craft:execute` re-run reuses worktrees, skips merged
slices, resumes a stopped sequential slice and records a shown review checkpoint in the epic worktree, decided by
`scripts/execute-resume-state.sh`; release-gated like the rest.
B9, B10, B13, B14 shipped (slice-039): add their CHANGELOG entry — CRAFT's plans, counters and local state no longer
count as uncommitted work (`scripts/tree-dirt-state.sh`), `/craft:commit` commits its own archive and leaves the human's
changes alone, a worktree is created only for a committed plan (`plan_not_committed`), a project's `.gitignore` negation
is respected, and abort / worktree-clean show an open handoff before removal; release-gated like the rest.
B16 shipped (slice-040): add its CHANGELOG entry — under protected main a tracked plan's removal rides in the PR and the
second pass drops the local copy before it syncs the trunk (`scripts/plan-landing.sh`, harness `test-plan-landing.sh`);
release-gated like the rest. Still unshown by a real run: push / PR / backfill and the worktree finalize modes.

**B11 — review follow-ups from slice-036.** Details in
`.claude/project/slices/slice-036-b7-stale-handoff-marker.md` → Follow-ups (R8 folded into B8).

**B12 — follow-up from slice-038** (B13 and B14 shipped with slice-039). Details in
`.claude/project/slices/slice-038-b8-execute-rerun-semantics.md` → Follow-ups (R3-6). B12 is ordered before F6 on
purpose: autopilot re-runs a sequential epic unattended, and it stops exactly that loop.

**B15, B17 — follow-ups from slice-039** (B16 shipped with slice-040). Details in
`.claude/project/slices/slice-039-b9-b10-b13-b14-tree-hygiene.md` → Follow-ups and Known limits. B15 is what parallel
worktree mode needs before anyone relies on it.

**F6 — Autopilot mode.** Banked as D32 (2026-09-12); design record with verified facts, touchpoint
matrix and open spike items in `.claude/project/design/autopilot-mode.md`. F4 shipped (slice-033):
the bash ≥ 5.0 baseline its usage/cache sensor scripts assume is in place. B2 shipped (slice-032):
slices that change `commands/` / `agents/` are verified via headless `--plugin-dir` probes (D33),
not the running session. Starts with a spike slice (statusline refresh during subagent runs, blocked-prompt API behavior, subagent cache
TTL, `fable` alias vs. `model-defaults.md`). Couples to D2: planner/architect/reviewer vs. builder
are exactly the capability tiers D2 wants to name.

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

**D2 — Model tiers.** Bind roles to capability tiers, not model names; project maps tiers → models (Fable 5 becomes config, not code). Serves token-efficiency (expensive reasoning only at hard phases). Couples to D1's spawn-threshold (make it tier-configurable). Caveats: verify Fable 5's real behavior before rewriting policy; "open to other coding tools" (Cursor etc.) is a separate, larger track — likely non-goal for now.
