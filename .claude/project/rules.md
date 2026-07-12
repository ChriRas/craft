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
  (`.claude-plugin/plugin.json`, `marketplace.json`); Bash for `hooks/`.
- **Test Framework:** none conventional — plugin integrity is checked with
  `claude plugin validate`. The read-only context guard + sync helper have a
  standalone Bash harness: `bash scripts/test-readonly-context.sh` (it also
  asserts the guard↔helper normalizer agreement — keep it green).
- **Lint / Format:** none enforced.
- **Static Analysis:** n/a.
- **Package Manager:** n/a — distributed as a Claude Code plugin.
- **Required companion tools:** context-mode, agent-browser, git, gh (verified by
  `/craft:prime` pre-flight).

## Workflow Rules

- This repo dogfoods CRAFT — its own development runs through the CRAFT phase loop.
- This is a plugin-authoring project — Markdown/JSON/Bash assets, not classic
  runtime software. Testing is minimized to what is technically meaningful
  (`claude plugin validate`, structural checks); there is no behavioral test suite.
- Phase 7 (Refactor) is dropped from this project's workflow — freshly authored
  Markdown rarely has accumulated structure to improve.
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
