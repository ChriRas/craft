# Rules

> How we build, always. Most rules here must be verifiable against State (code,
> configs, manifests); non-verifiable conventions belong in `intent.md`. Exception:
> operational settings consumed by CRAFT commands (e.g. the `## Worktree Settings`
> block) may live here even though they are not State-verifiable. Keep this file
> under ~80 lines.
>
> Language, model-override, and autonomy/commit/merge settings live in the CRAFT
> profile (`.claude/project/craft-profile.md`), not here.

## Stack & Tools

- **Language:** Markdown (commands in `commands/`, skills in `skills/`) + JSON
  (`.claude-plugin/plugin.json`, `marketplace.json`); Bash for `hooks/` and `scripts/`.
- **Bash baseline:** `scripts/` may use bash ≥ 5.0 (the minimum is defined once, in
  `scripts/check-toolchain.sh`); `hooks/` and `scripts/check-toolchain.sh` stay
  **bash-3.2-compatible** — hooks run with whatever bash Claude Code hands them, and only an
  old-bash-safe hook and helper can report an old bash. `scripts/test-toolchain-check.sh`
  asserts it with **two independent detectors**: a bash-4-construct scanner and real
  `/bin/bash` 3.2 runs that fail on shell error text. `bash -n` is no evidence — it accepts
  bash-4 constructs, and a 3.2 run skips a failing command and carries on green.
- **Test Framework:** none conventional — plugin integrity is checked with
  `claude plugin validate`. Five standalone Bash harnesses cover what is
  mechanically checkable; keep all green:
  `bash scripts/test-readonly-context.sh` (read-only guard + sync helper, incl.
  the guard↔helper normalizer agreement),
  `bash scripts/test-workflow-status-graph.sh` — asserts the phase graph declared in
  `skills/workflow/SKILL.md` is closed under both Phase-7 configurations, that the
  commands' `craft:writes` / `craft:reads` markers and the table agree **in both
  directions**, and that `/craft:continue` routes each status to the graph's consumer
  (markers are the contract: prose is not checked, because a grep cannot tell a
  prescription from a prohibition),
  `bash scripts/test-docs-site.sh` (docs site in sync with the plugin surface),
  `bash scripts/test-plugin-cache-drift.sh` (plugin runtime vs. working tree, B2), and
  `bash scripts/test-toolchain-check.sh` (bash/python3 requirement, OS install hints, hook bash).
- **Lint / Format:** none enforced.
- **Static Analysis:** n/a.
- **Package Manager:** n/a — distributed as a Claude Code plugin.
- **Required companion tools:** context-mode, agent-browser, git, gh, bash ≥ 5.0, python3
  (verified by `/craft:prime` pre-flight).

## Workflow Rules

- This repo dogfoods CRAFT — its own development runs through the CRAFT phase loop.
- This is a plugin-authoring project — Markdown/JSON/Bash assets, not classic
  runtime software. Testing is minimized to what is technically meaningful
  (`claude plugin validate`, structural checks); there is no behavioral test suite.
- Phase 7 (Refactor) is dropped from this project's workflow — freshly authored
  Markdown rarely has accumulated structure to improve.
- Phase 5 runs on automated evidence, not a hands-on sandbox exercise: harnesses,
  helper runs and (where cheap) headless `claude -p --plugin-dir` probes are presented
  as an evidence report, and the human answers W/B/U on it. Compensated by a two-pass
  Phase 8 (rubric review + scenario walk-through of changed command prose). The agent
  must request a real human test for: fail-open hooks, destructive git/worktree paths,
  settings/permission writes, interactive-only behavior, and any surprising probe result.
- Headless probes run from a scratch copy, never inside this repo, **one at a time and one fixture
  per parent directory** (concurrent sessions knocked out context-mode in slice-033; a probe's
  reviewer strayed into a sibling fixture in slice-034). A probe that must write `.claude/plans/`
  needs `--permission-mode bypassPermissions` confined to the scratch fixture — `acceptEdits`
  refuses those writes. When the prime gate is not under test, the probe's plugin copy omits
  `hooks/` and the fixture pre-creates `.claude/plans/.primed`.
- Architectural decisions are banked in `brainstorm-decisions.md` as `D<N>` entries
  before they are implemented.
- Commit messages follow Conventional Commits — `<type>(scope): subject` (D9).
- No `Co-Authored-By` trailer in commits.
- Durable-state files are changed only with explicit human confirmation — the agent
  proposes, never silently mutates.

## Code Conventions

- Commands live in `commands/<name>.md`; skills in `skills/<name>/SKILL.md`.
- Commands that mutate durable state outside the session carry Pre/Post-Assertions (D24).
- All command cross-references use the full `/craft:` namespace.

## Tabus (Anti-Patterns)

- No short-name command shim files.
- No silent correction of Rules ↔ State drift — report, let the human decide.
- **A rule is never described twice.** When a command's interactive and Subagent-Mode paths
  share a rule, one of them defines it and the other **delegates** to it with a
  `<!-- craft:delegates -->` token. Two descriptions of one contract, with only one of them
  maintained, is how the Phase-7 routing bug (B1, slice-031) came about and survived — the
  subagent path handled the drop, the interactive one did not. Adding checks *on top of* a
  duplication does not make it safe; the second copy has to go.
- No skipping git hooks or signing (`--no-verify`, `--no-gpg-sign`).

## Deployment

- **Branch model:** trunk-based — commits land directly on `main`.
- **Release tagging:** SemVer; `CHANGELOG.md` follows Keep a Changelog.
- **Distribution:** a single GitHub repo hosts both the marketplace and the plugin;
  `/craft:upgrade` syncs the marketplace clone.
- **Pre-release check:** `claude plugin validate`.

## Worktree Settings (optional)

- **Worktree path pattern:** `../<repo>-worktrees/<slice-id>-<slug>/` (default)
- **Branch name pattern:** `<slice-id>-<slug>` (default)

> Worktrees live outside the project root, so `/craft:execute` adds their shared
> base directory to `permissions.additionalDirectories` in
> `.claude/settings.local.json` on first run — once, after a confirmation — to
> avoid per-path permission prompts. Idempotent; existing permissions are merged,
> never overwritten; the file stays gitignored.

## Read-Only Context Sources (optional)

> Reference material the agent may **read** but never **write**. A PreToolUse guard
> (`readonly-context-guard.sh`) denies Write/Edit/NotebookEdit targeting any path below.
> The in-repo `research/` folder is always protected by convention — no entry needed.
> Declare external "connected projects" as `- <absolute-path>` bullets; each is added
> read-only to `permissions.additionalDirectories` (idempotent, gitignored) so it stays
> readable but write-blocked.

(no connected projects declared)

## Self-Verification Settings (optional)

- **Max attempts:** 5
- **Auto-trigger threshold:** 2
- **Token brake during loop:** 15000
- **Stale slice threshold:** 7 days
