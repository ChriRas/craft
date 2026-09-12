# Roadmap

> Backlog beyond the shipped core. Loaded on `/craft:prime` — keep tight. Each item
> becomes a `/craft:plan` (slice) or `/craft:epic` when picked up. IDs are stable
> handles, not slice-IDs. Captured 2026-07-07 from a design brainstorm
> (8 raw ideas → 7 packages; "Research folder" + "connected projects" merged into F1).

## Backlog (priority order)

| # | ID | Type | Size | Item |
|---|----|------|------|------|
| 1 | B2 | Fix | slice | Dogfooding is not self-verification: the runtime loads the plugin **cache**, not the working tree — no slice touching `commands/` can be verified end-to-end in the session that writes it |
| 2 | F4 | Feature | slice | Modern-bash baseline: CRAFT scripts target current bash; `/craft:prime` checks the bash version and gives OS-aware install hints (macOS → Homebrew, Linux → detected distro's package manager) |
| 3 | F6 | Feature | epic | Autopilot mode (D32): hands-off epic execution — planner/architect agents, one plan gate, sequential slice loop on an epic branch, ping-pong breaker, budget + cache guards, epic-end sign-off |
| 4 | F3 | Feature | epic | Cleanup skill: losslessly condense source comments with a fresh-context fidelity check (repo/epic/slice scope) |
| 5 | D2 | Design | epic | Loosen fixed model rules → capability tiers (deep-reason / execute); open to Fable 5 & foreign models — **verify Fable 5 first** |
| 6 | F5 | Feature | slice | Windows support: require Git for Windows or WSL 2, detect a PowerShell-only setup — **untested, needs a Windows machine** |

## Notes per item

**B2 — Dogfooding is not self-verification.** Found in Phase 6 of slice-031, by noticing that the
`/craft:recap` text driving the session still asked "Ready for Phase 7?" while the working tree
carried the fixed branch. Claude Code executes the commands installed under
`~/.claude/plugins/cache/craft/craft/<version>/`, **not** the repo's `commands/`. Consequences:
(a) no slice touching `commands/` can be verified end-to-end in the session that writes it — the
fix only goes live after `/craft:upgrade` or a reinstall, so Phase 5 for such a slice can
demonstrate the *harness* but never the runtime behavior, and must say so; (b) worse, a CRAFT
session can silently run **older command logic than the repo shows**, which is a trap for any
dogfooding review — the reviewer reads the fixed file while the runtime obeys the stale one.
Candidate fix: have `/craft:prime` compare the cache's `plugin.json` version — ideally a content
hash — against the dev repo when the two are the same project, and warn on divergence; and state
the constraint in `CLAUDE.md` so the next agent does not re-learn it the hard way.

**F4 — Modern-bash baseline.** Decided 2026-09-12: CRAFT is a developer tool, so it may require a
current bash instead of staying compatible with macOS's frozen `/bin/bash` 3.2.57 (GPLv2-era, not
updated by Apple). Found when `scripts/test-workflow-status-graph.sh` failed to parse under 3.2
(heredoc inside `$( … )`) and passed 82/82 under Homebrew bash 5.3.15. Scope: pin a minimum major
version (proposal: 5) and state it in `rules.md` + README; extend the `/craft:prime` pre-flight
(next to context-mode / agent-browser / git / gh) with a bash-version check whose abort message is
OS-aware — `uname -s` = Darwin → `brew install bash`; Linux → read `/etc/os-release` `ID` /
`ID_LIKE` and print the matching `apt` / `dnf` / `pacman` / `apk` / `zypper` command. Also check
`python3`, which the helper scripts need. **Trap to verify:** hooks run `bash …` through `sh -c`
with Claude Code's `PATH`; when Claude Code is launched outside a login shell (desktop app, IDE),
`/opt/homebrew/bin` may be missing and the hooks would silently fall back to `/bin/bash` 3.2 — the
check must test the bash the hooks actually get, not the one in the user's terminal.

**F6 — Autopilot mode.** Banked as D32 (2026-09-12); design record with verified facts, touchpoint
matrix and open spike items in `.claude/project/design/autopilot-mode.md`. Ordered after B2 and F4 on
purpose: its slices change `commands/` / `agents/`, which B2 says cannot be verified live in the
writing session, and its new usage/cache sensor scripts assume the F4 bash baseline. Starts with a
spike slice (statusline refresh during subagent runs, blocked-prompt API behavior, subagent cache
TTL, `fable` alias vs. `model-defaults.md`). Couples to D2: planner/architect/reviewer vs. builder
are exactly the capability tiers D2 wants to name.

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
