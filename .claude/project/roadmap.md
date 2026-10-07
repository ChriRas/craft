# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | F6 | Feature | epic | Autopilot mode (D32): hands-off epic execution — planner/architect agents, one plan gate, sequential slice loop on an epic branch, ping-pong breaker, budget + cache guards, epic-end sign-off |
| 2 | B18 | Fix | small | Handoff-answer record (slice-042 R1-15): a resume records no answer to the handoff's question, so a subagent re-run — an autopilot re-run in particular — meets it again. Deferred by slice-049: build it when a real autopilot run shows a question that repeats (Phase-5 answers already live in `Status:`) |
| 3 | F7 | Feature | epic? | Idle cache guard (braindump): when the human stays away past the prompt-cache TTL, wake shortly before expiry, write the slice handoff, keep the cache warm a bounded number of times, and block a prompt into a cold session — avoids the full-history re-write on return |
| 4 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 5 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |
| 6 | F5 | Feature | slice | Windows support: require Git for Windows or WSL 2, detect a PowerShell-only setup — **untested, needs a Windows machine** |
| 7 | F8 | Feature | epic | **End of the chain.** Other AI coding agents: make CRAFT usable beyond Claude Code — e.g. OpenAI Codex CLI, OpenCode — **verify each tool's extension surface first** |

## Notes per item

**F6 complete, release held (user, 2026-10-06).** epic-003 landed on `main` with slice-060 (`ae0875c Merge epic-003:
Autopilot Mode`); every decomposition entry has a slice. The 2.0.0 release (rules.md → Deployment: autopilot ships as
2.0.0) is **deliberately not cut yet** — the user has a few more things to do first. No version bump, push or tag until
the user says so; nothing is pushed yet. Still owed from slice-060: human test (c) part B (real idle ≥ 1 h) and the
follow-ups R1-1 / R1-2 (archive → Follow-ups). Also owed before the cut: B25's human test on a scratch GitHub repo (see
the B25 note below).

**B27 shipped with slice-069 (2026-10-07)** — the autopilot's run-start briefing is printed by
`scripts/autopilot-briefing.sh` (the whole block, its "Stops for you at" lines included); `/craft:execute` a1 and the plan
gate only relay it unchanged, a helper error stops a1 (`⛔ … briefing failed`) and is one `⚠` line at the gate. Slice states
come from `execute-resume-state.sh`; the order puts a resume slice first, then topological by `Depends-On`, ties in
decomposition order (s1 states the same tie-break). `scripts/test-autopilot-briefing.sh` covers it.

**B25 shipped with slice-068 (2026-10-07)** — D39: under `pull-request` + `Protected-main: yes`, `/craft:commit`'s
Epic-close mode closes a finished epic in two passes. The first commits the decisions, the epic archive and the epic
plan's removal (`plan-landing.sh close --keep-copy`) on the branch the PR carries — the epic branch a5's PR left, or, for
a sequential epic and for an autopilot epic whose PR merged first, a close branch `<epic-id>-<slug>-close` cut from the
synced trunk with a close PR of its own — and sets the epic plan to `Status: awaiting-approval`; the second, after the
GitHub approval, is Step 6's second invocation (`gh pr merge --merge`, never `--admin`), `plan-landing.sh sync`,
`git branch -d` and Step 7b. `epic-close-state.sh` reads the plan at `awaiting-approval` as `STATE=closing` and a merged
`PR #<N> opened` epic as `closable`. a5's PR hand-over says to run `/craft:commit` first, then approve. Shown by
`scripts/test-epic-close-state.sh` (helper fixtures and pinned prose) only; the real effect on GitHub is not.
**Still owed before the 2.0.0 cut: a human test on a scratch GitHub repo with a protected trunk — an autopilot epic
closed through its open PR (first pass, approve, second pass), an autopilot epic whose PR merged first, and a sequential
epic, both through the close branch's PR.** Known limits: a squash or rebase merge of the epic's PR leaves no merge
commit for the helper to find, so the epic stays `pr-path`; a push after an approval can dismiss it, hence the order.

**B15 shipped with slice-067 (2026-10-07)**, including the worktree commit gap it uncovered — in parallel worktree mode
nothing ever committed in a slice worktree. `/craft:execute` step 5 hands the main checkout's plan into every new worktree
(`scripts/plan-roundtrip.sh in`, a record that hides itself through `.craft/.gitignore`), so a slice's plan needs no commit
and `plan_not_committed` is an epic-line reason only; step 6 commits the slice's work on its branch
(`tree-dirt-state.sh --scope slice-worktree`), reads the plan back (`back`) and only then merges or stashes; `/craft:commit`
A3 checks the slice worktrees, and Step 7 releases the handed-in copy (`release`, which also hides CRAFT's own files at the worktree: the `.primed` seed, `.hook-env`, a resolved handoff marker) before `git worktree remove`. Open
follow-ups, not built: (2) Epic-finalize — `/craft:commit` A1 accepts exactly one plan at `committing`, so a parallel epic
with N read-back slices still aborts there, and Mode Detection can match the epic worktree and a slice worktree at once;
(3) `/craft:abort` and `/craft:worktree-clean` still refuse a worktree that holds the handed-in plan, as they do for any
uncommitted work; (4) the epic line keeps `plan_not_committed` — a never-committed epic plan still stops a parallel epic;
(5) execute step 5 seeds `.primed` at the worktree root, not below a subdirectory project's prefix.

**B17 shipped with slice-065 (2026-10-07)** — the settings helpers (`ensure-readonly-context.sh`,
`ensure-worktree-trust.sh`) ask `ensure-gitignore.sh --verdict` from the repository root, so `GITIGNORED=` judges the
`settings.local.json` they write, also in a subdirectory project, and `/craft:execute`'s `GITIGNORED=no` line names that
file. Follow-up candidates, not built: (1) `ensure-gitignore.sh`'s CRAFT local-state path
`.claude/settings.local.json` is anchored to the project dir, so `/craft:prime` 4f and `/craft:onboard` cover a file
Claude Code ≥ 2.1.211 no longer uses in a subdirectory project, and never the repo-root one — a design decision about
the block's anchoring; (2) `ensure-readonly-context.sh` reads `rules.md` at the repository root while the guard
(`hooks/readonly-context-guard.sh`) reads it at the project dir, so the two can disagree on the declared connected
projects in a subdirectory project; (3) exceptions to the repo-root settings file — a linked git worktree (Claude Code
uses the main checkout's root file, the helpers take the worktree root) and the docs' other cases (repository root =
home directory, foreign ownership, Windows).

**B5 shipped with slice-064 (2026-10-07)** — `/craft:prime` shows a hook bash older than the Bash tool's as an
informational `· Hook bash:` line (the helper's `HOOK_REMEDY` says CRAFT's hooks are bash-3.2-compatible and unaffected;
`STATUS=hook-mismatch` / exit 10 are unchanged), and the status-graph harness's guard aborts only on `BASH=too-old`, with
a focused message — a missing python3 no longer stops it. `scripts/test-toolchain-check.sh` covers both.

**B23 shipped with slice-063 (2026-10-07)** — every `## Autopilot Log` line is written by `scripts/autopilot-log.sh`
(the helper's clock, placement and landed check; a slice step refused before this invocation's `run started`, keyed to
the execute lock's `SINCE=`); step 1c and a4 read the slice list through `execute-resume-state.sh --slices-from`, and a
conflict on a4's re-run stops before a5; `.craft/tmp/` is the master's one place for its own files. The a1 block's
content is still prose → **B27**.

**B26 shipped with slice-062 (2026-10-06)** — D38: every epic archive is written from `templates/epic-archive.md.template`
(commits only in the frontmatter, slice follow-ups by reference), and the mode, renamed Epic-close, closes a sequential or
hand-worked epic too — `/craft:execute` s5 hands over to `/craft:commit` like a5.

**B24 shipped with slice-061 (2026-10-06)** — D37: after a5 `[Y]` (`direct`), `/craft:commit`'s Epic-close mode (named Autopilot-epic-close until slice-062)
walks the epic decisions, writes and commits the epic archive, closes the epic plan and deletes the merged epic branch;
`scripts/epic-close-state.sh` decides whether an epic is ready. The PR path shipped as B25 (see its note above).

**F9 shipped with slice-059 (2026-10-06).** `/craft:prime` step 4h and `/craft:onboard` offer to wire the statusline tap
the budget guard reads (`scripts/ensure-statusline-tap.sh`, D36: only on a yes, with a backup, reversible). Its follow-up
R1-10 — a fail-open wired form, so the user's statusline survives an uninstalled CRAFT — is in
`.claude/project/slices/slice-059-statusline-tap-wiring.md` → Follow-ups. Still to show: the real-file test after the release.

**R1 shipped with slice-043 — CRAFT v1.5.0 (2026-09-15).** The installed runtime carries slice-032 … slice-042; a fresh
session's `/craft:prime` reports v1.5.0 without drift, and the D33 Dock launch showed the hook receiving the Homebrew bash
(details in `.claude/project/slices/slice-043-r1-release.md`). Still unshown by a real run: push / PR / backfill and the
worktree finalize modes under protected main (slice-040), `/craft:execute` A6 against a real epic (slice-041), the
interactive `/craft:continue` 4a dialog (slice-042). `test-docs-site.sh` does not check the required-tools list.

**B11 shipped with slice-042.** Its follow-up R1-15 (a resume records no answer to the handoff's question, so a
subagent re-run meets it again) is in `.claude/project/slices/slice-042-b11-handoff-resolution-from-paused.md` →
Follow-ups; it is roadmap **B18** now — slice-049 (the autopilot loop) deferred it until a real run shows a repeating question.

**B12 shipped with slice-041.** Its follow-up R1-9 (the other `## Slice Decomposition` readers — `/craft:commit`
Epic-finalize, `/craft:execute` s0, `/craft:continue` — still judge entries themselves) is in
`.claude/project/slices/slice-041-b12-epic-slice-id-link.md` → Follow-ups; worth folding into F6's orchestrator work.

**B19 shipped with slice-050 (2026-09-30)** — D34: CRAFT never goes around a user rule that denies or asks on removing
files. Closed plans move into the read-blocked `.claude/plans/.closed/` when such a rule applies (automatically, no
confirmation), a helper never deletes, the execute lock carries its state (a lock this very session holds goes to the
human), and `/craft:prime` hints a copy-ready cleanup command. Details and known limits in
`.claude/project/slices/slice-050-b19-delete-safe-cleanup.md`. Its follow-up — parallel mode's checkpoint removal — is
**shipped with slice-066** (the record stays as append-only state, hidden by a nested `.craft/.gitignore`). Still the user's own settings work: three tiers — recursive removal denied, single-file removal on `ask`, CRAFT's
move as the third; a rule for `rm -r` followed by a space does not match `-rf` or `-fr`, so tier 1 needs several patterns
and a test.

**B21 — slice-056 (2026-10-01).** The autopilot no longer stops at Phase 7: candidates become fixed-prefix decision lines,
carried into the archive and read into the a5 digest by command. The missing `⛔` line did **not** reproduce (probe run 2
logged its stop) — most likely the user's Esc. The other a5 / a1 drift probes 3 and 4 showed is **B22** — the digest itself included: it lists the candidates correct in
content but from memory, and a prose `grep -hF` instruction did not bind it.

**B22 — slice-057 (2026-10-02).** The epic-end digest is generated: `scripts/epic-digest.sh` prints the whole
*Autopilot — epic complete* block and a5 relays it unchanged, so the candidates, the UX demo script and its dates come
from the files. The lock is released only after `[Y]` / `[N]`; `▶ · <epic-id> · sign-off asked` precedes the question, and
an unanswered question writes no `■` line — a re-run asks again. B22's a1 and `/tmp` items moved to **B23**.

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
