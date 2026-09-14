---
description: Session-start context loader. Checks tools, loads project knowledge, validates Rules ↔ State, lists active slices, and recommends the next action. Auto-runs on SessionStart when the project is onboarded.
allowed-tools: ["Bash", "Read", "Glob", "Grep"]
---

# /craft:prime — Load Project Context

## Purpose

Bring a fresh chat session into the project's working context: verify the toolchain, activate context-mode, read project knowledge, detect any Rules ↔ State drift, surface active slices, and tell the user exactly where to continue.

`/craft:prime` is the navigation backbone of every session. It is invoked automatically by the SessionStart hook when `.claude/project/intent.md` exists. It can also be re-invoked manually after editing `rules.md` or `intent.md`.

Follow the methodology defined in `skills/workflow/SKILL.md` — in particular the autonomy taxonomy, knowledge model, and tool-dependency policy.

---

## Pre-flight

Before doing anything else, this command MUST run two checks in order. **If either fails, abort with install instructions — do not continue to context loading.**

### Step 1 — Tool health (strict — collect first, abort once)

**Collect every missing tool before aborting, then abort once with the complete list.** Never stop
at the first missing tool: a user must not need a second install round because a later check never
ran. Run both probes below in the same turn (as parallel tool calls), and decide only after both have
returned:

- **(a) context-mode** — call `mcp__plugin_context-mode_context-mode__ctx_stats`. If it cannot be
  called, context-mode is missing.
- **(b) everything else — one Bash command that always exits 0**, so no check is skipped by an `&&`
  chain and no parallel call is cancelled by a non-zero exit. Resolve the helper
  `scripts/check-toolchain.sh` like step 5c does: `${CLAUDE_PLUGIN_ROOT}/scripts/`; else
  `<project-root>/scripts/`, only when the project root holds a `.claude-plugin/plugin.json` whose
  `name` is `craft`. Put the resolved path in the command as-is — if it does not exist (or
  `${CLAUDE_PLUGIN_ROOT}` did not resolve), the command reports `HELPER=not-found` rather than
  failing.

  ```
  for t in agent-browser git gh bash; do command -v "$t" >/dev/null 2>&1 || echo "MISSING=$t"; done
  [ -f "<helper>" ] && { bash "<helper>" --project "<project-root>"; echo "HELPER_EXIT=$?"; } || echo "HELPER=not-found"
  ```

  `bash` here is the bash your shell PATH resolves — the same one CRAFT's scripts run with.

| Tool | Missing when | Add to the missing-tools list |
|---|---|---|
| **context-mode** | probe (a) fails | *"context-mode is required. Install via `claude /plugin install context-mode@claude-plugins-official`. See https://code.claude.com/docs/en/plugins for help."* |
| **agent-browser** | `MISSING=agent-browser` | *"agent-browser is required. Install per upstream documentation: https://github.com/snadi/agent-browser"* |
| **git** | `MISSING=git` | *"git is required. macOS: `brew install git`. Linux: use your distro package manager. Windows: https://git-scm.com/downloads"* |
| **gh** | `MISSING=gh` | *"gh (GitHub CLI) is required. macOS: `brew install gh`. Linux: see https://github.com/cli/cli#installation"* |
| **bash** | `MISSING=bash` (no `bash` on PATH at all), or `HELPER_EXIT=20` with `BASH=too-old` | too old → *"bash ≥ `<BASH_MIN>` is required (found `<BASH_VERSION>` at `<BASH_PATH>`). Install: `<INSTALL_BASH>`."* · too old **but `BASH_OFF_PATH` is reported** (a current bash is installed, just not on this session's PATH — typical for a desktop-app or IDE launch) → *"bash ≥ `<BASH_MIN>` is required (found `<BASH_VERSION>` at `<BASH_PATH>`). `<PATH_REMEDY>`."* — never an install command in that case · `MISSING=bash` → *"bash is required — none found on PATH. Install a current bash (see the CRAFT README → Requirements)."* |
| **python3** | `HELPER_EXIT=20` with `PYTHON3=missing` | *"python3 is required. Install: `<INSTALL_PYTHON3>`."* |

When the helper printed `INSTALL_NOTE`, add it **once**, after the last toolchain entry — not to
each entry. Render `<PATH_REMEDY>`, `<HOOK_REMEDY>` and `<INSTALL_NOTE>` **verbatim**: do not
shorten them or add your own example configuration (a settings `env.PATH` must hold a literal PATH).

The helper's other outcomes are **not** missing tools:

- `HELPER_EXIT=0` (`STATUS=ok`) — bash and python3 are present; report `BASH_VERSION` and
  `PYTHON3_VERSION` in the Tools line.
- `HELPER_EXIT=10` (`STATUS=hook-mismatch`) — **do not abort.** The Bash tool has a current bash, but
  the SessionStart hook recorded an older one when this session started (Claude Code's own PATH
  differs from your shell's). Report the versions in the Tools line and add the output-block line
  `⚠ Hook bash: <HOOK_REMEDY>`.
- `MISSING=bash` — the helper could not run at all (its `HELPER_EXIT=127` means exactly that);
  report bash as missing and ignore the helper line.
- `HELPER=not-found`, `HELPER_EXIT=2`, or no `STATUS=` line — emit
  `⚠ Toolchain check incomplete: <reason>` and render `bash ?, python3 ?` in the Tools line. It cannot
  confirm the tools, but it is not proof they are missing.

**Once (a) and (b) have both returned:** if the missing-tools list is non-empty, print every entry
and abort — stop and wait for the user to install them; do not partially proceed. Otherwise continue.

### Step 2 — Context-mode activation & currency

- Call `mcp__plugin_context-mode_context-mode__ctx_stats` once to confirm context-mode responds.
- If the response mentions an outdated version (e.g., "v1.0.118 outdated → v1.0.140 available"), surface the message and suggest the user run `/ctx-upgrade`. Continue priming for now — outdated context-mode is a warning, not a blocker.
- From this point forward in the session, use context-mode (`ctx_batch_execute`, `ctx_execute`, `ctx_execute_file`, `ctx_search`) for any operation that would otherwise produce large output. This is required, not a preference.

### Step 3 — Project onboarding check

- Use `Read` to check `.claude/project/intent.md`.
- If the file does not exist, the project has not been onboarded. Emit a single-line nudge:

  ```
  Project not onboarded — run /craft:onboard to set up project knowledge.
  ```

  Stop. Do not attempt to load missing files or guess at project state.

---

## Procedure

If pre-flight passes, perform the following in order. Use parallel reads where possible.

### 1. Load context — baseline and project knowledge

First, load the CRAFT Senior-Developer baseline:

- `Read` `skills/senior-developer/SKILL.md` — the universal engineering baseline:
  stance, quality hierarchy, workflow gates, test-discipline matrix, and
  problem-playbook. It stays active for the rest of the session.

Then read the project knowledge files (some are optional):

- `.claude/project/intent.md` (required at this point)
- `.claude/project/rules.md` (required)
- `.claude/project/roadmap.md` (optional)
- `CLAUDE.md` (optional, in repo root)

Hold all of the above in working memory for the rest of the session.

### 2. Summarize the project

Derive a one-line project summary from `intent.md` (vision) and `rules.md` (stack). Format:

```
Project: <name from intent.md or repo dir> (<stack tags from rules.md>)
```

Example: `Project: Cocktail Management (PHP 8.4 / Laravel 12 / Pest)`

### 3. Drift check — Rules ↔ State

For each rule in `rules.md` that is verifiable against State, run the check. The `rules.md` file should list verifiable rules in a parsable form (typically a `## Stack & Tools` section with bullet points like `- Test Framework: Pest`).

Procedure:
- Use `Glob` and `Read` (or `Grep` via Bash through context-mode for large outputs) to verify each claim against project files (`composer.json`, `package.json`, `Cargo.toml`, `pyproject.toml`, `.github/workflows/*.yml`, etc.).
- Report each drift as a single line: `⚠ Rules say <X>, State shows <Y>`.
- If no drifts, report `Rules ↔ State drift check: clean`.

**Graceful degradation for missing manifests:** If a rule references a stack (e.g., "Test Framework: Pest") but the corresponding manifest file (`composer.json` for PHP, `package.json` for JS, etc.) is absent, do not treat that as drift — emit an incomplete-check note instead:

```
⚠ Drift check incomplete — no <manifest-name> to verify <stack> rules against.
   This is expected if dependencies aren't installed yet. Re-run /craft:prime after <install command>.
```

**Never silently correct drift.** Reporting is the action; correction is a separate human-confirmed step.

### 4. Stack-pack availability check

The project may declare a CRAFT stack-pack in the `## Personality` block of
`rules.md`. `/craft:prime` does **not** load the pack — the code-near phases
(`/craft:build`, `/craft:test`, `/craft:refactor`, `/craft:review`) do that — but it verifies the
declaration early so a missing pack does not surprise the user mid-slice.

- Read the `## Personality` section of `.claude/project/rules.md`.
- If there is no `## Personality` section, or `Stack-Pack:` is `none`: emit no
  stack-pack line and continue.
- If a pack `<name>` is declared, resolve it the same way the code-near phases do —
  `skills/<name>/SKILL.md` (plugin-shipped) or
  `~/.claude/craft-personalities/<name>/SKILL.md` (user-added):
  - Found → status line `✓ Stack-pack <name> declared`.
  - Not found → status line `⚠ Stack-pack <name> declared but not found — code-near
    phases run on the Senior-Developer baseline only; add the pack or set Stack-Pack to none`.

Like the drift check, this is **reported, never corrected** — the human decides.

### 4b. Agent model resolution (informational + soft validation)

Build the effective `Agent → Model` map so the user can see which model each CRAFT subagent will run on this session.

1. **Defaults** — for every file in the plugin's `agents/` directory, read the frontmatter `model:` value. Missing `model:` means "session model". Resolve the plugin's `agents/` directory in this order, first match wins:
   - `${CLAUDE_PLUGIN_ROOT}/agents/` if the environment variable is set (the documented Claude Code path for an installed-plugin run);
   - else `<project-root>/agents/` if it exists (the CRAFT dev-repo dogfood case);
   - else emit `⚠ Could not locate plugin agents/ directory — model-resolution disabled this session` and skip step 2.
2. **Project overrides** — `Read` the `## Agent Model Overrides` section of `.claude/project/craft-profile.md` (the profile is the home for model overrides since slice-016; when the profile file or the block is absent, there are no overrides and the defaults from step 1 stand). Parse only lines that (a) are not inside an HTML `<!-- ... -->` comment block and (b) match `- <agent-name>: <model-value>`. The template's example entries live inside `<!-- ... -->` precisely so they are inert by default — uncommenting is the activation step. Allowed model values: `opus`, `sonnet`, `haiku`, `inherit`.
3. **Resolve** — for each agent, the override wins if present, else the default.
4. **Soft validation** (warnings only, never abort):
   - `⚠ Override for unknown agent '<name>' — typo or removed agent?`
   - `⚠ Override '<agent>: <value>' uses invalid model — allowed: opus, sonnet, haiku, inherit.`

Emit one status line per agent in the Output block (see Output Format). Format:

```
✓ Agent models: slice-builder=sonnet, code-reviewer=opus  [N overridden]
```

Collapse to a one-liner when nothing is overridden; expand to one line per overridden agent otherwise. See `model-defaults.md` for the design and the full default table.

### 4c. Language settings

Read the `## Operational Language` block of `.claude/project/craft-profile.md` and resolve the three settings so they govern this session and the consuming phases (the profile is the home for language settings since slice-016; when the profile file or the block is absent, apply the defaults below):

- **Chat** — the language the agent converses in. Adopt it for the rest of the session. Default when the key (or the whole block) is absent: the system language.
- **Commits** — the commit-message language, consumed by `/craft:commit`. Default: English.
- **Comments** — the code-comment language, consumed by `/craft:build` / `/craft:review`. Default: English.

Emit one status line reporting the three resolved values (see Output Format). Missing block → apply the defaults silently and still report them; never abort.

### 4d. CRAFT profile (detect, validate, report)

Detect and report the project's CRAFT profile — the portable per-project operating
config (autonomy, commit, merge, language, model settings). Like the drift and
stack-pack checks, this is **reported, never corrected**.

1. **Detect** — `Read` `.claude/project/craft-profile.md`.
   - **Absent** → emit the defaults line and stop this step:
     `✓ CRAFT profile: none — plugin defaults (balanced: execution=worktree, commit=on, merge=direct, epic=parallel, permissions=standard)`.
     The defaults are documented in `craft-profile-defaults.md`.
   - **Present** → parse the `> Preset:` line and the block fields below.

2. **Validate** (warnings only, never abort). Emit a `⚠` line for each issue found:
   - **Unknown block or field key** — `⚠ CRAFT profile: unknown key '<key>' — ignored.` The `## Operational Language` and `## Agent Model Overrides` blocks are expected profile members (their values are validated/reported by steps 4c/4b) — never flag them as unknown.
   - **Value outside its enum:**
     - `Execution → Mode` ∈ `worktree | in-place`
     - `Commit Policy → Auto-commit` ∈ `on | off`
     - `Commit Policy → Co-Authored-By` ∈ `on | off`
     - `Merge Workflow → Type` ∈ `direct | pull-request`; `Protected-main` ∈ `yes | no`; `Approval` ∈ `chat | github-pr-review`; `Approval-granularity` ∈ `per-slice | per-epic | auto`
     - `Epic Mode → Default` ∈ `parallel | sequential`
     - `Permissions → Scope` ∈ `minimal | standard | broad`
     - Out-of-enum → `⚠ CRAFT profile: '<block> → <field>: <value>' invalid — allowed: <list>.`
   - **Constraint** — `Auto-commit: off` with `Mode: worktree` → `⚠ CRAFT profile: Auto-commit=off requires Execution Mode=in-place (the worktree merge model needs per-sub-task commits).`
   - A missing block/field within an otherwise-present profile is **not** a warning — it falls back to the plugin default for that field.

3. **Report** — emit one status line with the active preset and the effective settings:
   `✓ CRAFT profile: <preset> — execution=<mode>, commit=<on|off>[+coauthored-by], merge=<type>[/protected/<approval>], epic=<mode>, permissions=<scope>`.
   Append the `/protected/<approval>` segment **only when `Protected-main: yes`**; otherwise emit just `merge=<type>`.
   Append the `+coauthored-by` suffix to the `commit=` segment **only when `Co-Authored-By: on`**; otherwise omit it (the default `off` stays silent).
   The profile's `## Operational Language` and `## Agent Model Overrides` are read and
   reported by steps 4c/4b respectively — this report line covers the autonomy/commit/
   merge/epic/permissions settings only, to avoid double-reporting.

### 4e. Read-only context sources sync

Declared external "connected projects" (the `## Read-Only Context Sources` block of
`.claude/project/rules.md`) must sit in `permissions.additionalDirectories` to be
*readable*; the PreToolUse guard (`readonly-context-guard.sh`) keeps them
*write-blocked* regardless. The in-repo `research/` folder needs no entry — it is inside
the project root and protected by convention.

Resolve the helper `scripts/ensure-readonly-context.sh` in this order, first match wins:
`${CLAUDE_PLUGIN_ROOT}/scripts/` (installed plugin); else `<project-root>/scripts/`, but **only**
when the project root holds a `.claude-plugin/plugin.json` whose `name` is `craft` (dev-repo
dogfood — never run a same-named script from another project, the same guard as steps 4f and 5c).
Run it in `--check` mode via Bash; it parses the declared paths and
reports each as present/absent in `additionalDirectories`, plus an aggregate `STATUS=` and
`DECLARED=<n>`.

- **`DECLARED=0`** → emit no line (nothing declared — silent, like the stack-pack check).
- **All present** (`STATUS=present`, exit 0) → status line
  `✓ Read-only context: N connected project(s) trusted + research/ (convention)`.
- **Some absent** (`STATUS=absent`, exit 10) → status line
  `⚠ Read-only context: M of N connected project(s) not yet readable`, then **offer** to run
  `--apply` (Level 1 — ask before it writes). On a yes, run
  `scripts/ensure-readonly-context.sh --apply` and report `CHANGED=`. This and step 4f are
  the only prime steps that may mutate durable state, and only after explicit confirmation —
  never silently. On a no, leave the `⚠` line and continue.
- **Helper error** (python3 missing, settings unparseable) → emit
  `⚠ Read-only context check incomplete: <ERROR>` and continue. Never abort prime.

Like the drift and stack-pack checks, the drift itself is **reported**; the write to
`settings.local.json` happens only on the human's yes.

### 4f. Local-state gitignore

CRAFT writes local, per-clone state into the project: `.claude/plans/.primed` (step 9), the
SessionStart hook's `.claude/plans/.hook-env`, the `/craft:execute` run lock,
`.claude/settings.local.json`, and the worktree handoff marker `.craft/`. Unignored, these show
as untracked files in every `git status` — noise for the human; CRAFT's own clean-tree checks do not
count them (`scripts/tree-dirt-state.sh`). `/craft:onboard` adds them for new projects; this step
reaches projects onboarded before it did.

Which paths count, when a path is covered, and how the `# CRAFT local state` block is written
are defined once, in the helper `scripts/ensure-gitignore.sh`. Only a rule from one of the
project's own `.gitignore` files counts; a personal global excludes file does not.

Resolve the helper in this order, first match wins: `${CLAUDE_PLUGIN_ROOT}/scripts/`; else
`<project-root>/scripts/`, but **only** when the project root holds a
`.claude-plugin/plugin.json` whose `name` is `craft` (never run a same-named script from another
project, the same guard as step 5c). Run it via Bash:

```
CLAUDE_PROJECT_DIR="<project-root>" bash "<helper>" --check
```

Map the result to one status line:

- **`STATUS=present`** (exit 0) → `✓ Local state gitignored`.
- **`STATUS=absent`** (exit 10) → `⚠ Local state not gitignored: <paths from the ENTRY=… STATUS=absent lines>`,
  then **offer** to run `--apply` (Level 1, ask before it writes), naming the file it changes:
  *"Add them to a `# CRAFT local state` block in `.gitignore`? Paths your `.gitignore` un-ignores
  on purpose stay untouched. Commit the change afterwards."* On a yes, run the same command with `--apply` and report
  `✓ .gitignore updated — <MISSING> path(s) added; commit .gitignore`. On a no, leave the `⚠`
  line and continue.
- **Any `ENTRY=<path> STATUS=negated` line** (with either status) → add
  `· <path> kept visible — your .gitignore un-ignores it (!rule); left as is`. The project decided
  it; neither the check nor `--apply` counts or appends it, and `/craft:execute` does not count it as
  uncommitted work.
- **Any `TRACKED=<path>` line** (with either status) → add
  `⚠ <path> is tracked by git — ignoring does not untrack it; review, then git rm --cached <path>`.
  Report only; never run it.
- **`--apply` exits 6** (`ERROR=post_write_uncovered:<path>`) → `⚠ .gitignore un-ignores <path> —
  left unchanged, resolve by hand`. The helper has already restored the file.
- **Helper not found, or any other error** → `⚠ Local-state gitignore check incomplete: <reason>`.

Never abort prime. The `.gitignore` write happens only on the human's yes.

### 5. Tool versions (informational)

After tools are confirmed installed, capture and report versions for the status block:

- `context-mode`: take from the `ctx_stats` response.
- `agent-browser`: `agent-browser --version` (if supported; otherwise just confirm `✓`).
- `git`: `git --version` (first line).
- `gh`: `gh --version` (first line).
- `bash`, `python3`: take `BASH_VERSION` and `PYTHON3_VERSION` from the Step 1 helper output (no extra call); render `?` when the toolchain check was incomplete.

### 5b. Plugin version (informational)

Resolve the CRAFT plugin manifest and extract its `version` field so the user always sees which release is active. Locate `.claude-plugin/plugin.json` in this order, first match wins:

- `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` if the env var is set (installed-plugin path);
- else `<project-root>/.claude-plugin/plugin.json` if it exists (CRAFT dev-repo dogfood case);
- else the version is unresolved (see below).

Parse the JSON; read `.version`. On success, the output block's version line renders as `✓ CRAFT plugin v<version>`. If the manifest is not found or is unreadable / malformed, the version is unresolved: replace that line with the soft warning `⚠ CRAFT plugin version unknown — plugin.json <not found | malformed>` and continue. Never abort.

### 5c. Plugin runtime drift (dev repo only, informational)

Claude Code executes the plugin's **installed copy** (`${CLAUDE_PLUGIN_ROOT}`, a cache directory
named by version), not the repository a plugin is developed in. When this project *is* the
plugin's source repo, a session can therefore run older command logic than the working tree
shows — and the version from step 5b stays the same, so it cannot reveal it. This step compares
content instead.

Resolve the helper `scripts/check-plugin-cache-drift.sh` in this order, first match wins:
`${CLAUDE_PLUGIN_ROOT}/scripts/`; else `<project-root>/scripts/`, but **only** when the project
root holds a `.claude-plugin/plugin.json` whose `name` is `craft` (a helper newer than the installed
copy only exists in CRAFT's own working tree — never run a same-named script from another project).
Run it via Bash:

```
bash "<helper>" --project "<project-root>" --plugin-root "${CLAUDE_PLUGIN_ROOT}"
```

Keep both paths in double quotes — an unquoted empty value would vanish from the command line.
Map the result to at most one status line:

- **`STATUS=not-dev-repo`** (exit 0) → emit no line — this project is not the plugin's source.
- **`STATUS=in-sync`** (exit 0) → `✓ Plugin runtime = working tree` (append `(loaded in place)`
  when `RUNTIME=working-tree`).
- **`STATUS=diverged`** (exit 10) → emit exactly this, as one line:

  ```
  ⚠ Plugin runtime ≠ working tree — <DIFF_COUNT> file(s) differ (<list>); this session runs the plugin at <plugin-root>. To run the working tree: restart with claude --plugin-dir <project-root>, or release (bump version + push), then /craft:upgrade.
  ```

  `<list>` is the first three `DIFF=` values exactly as the helper prints them (prefix included, e.g.
  `modified:commands/prime.md`), followed by `, …` only when `DIFF_COUNT` is greater than 3.
- **Anything else** — `STATUS=unknown` (exit 3), a usage error (exit 2), no output, the helper found
  in neither location, or `${CLAUDE_PLUGIN_ROOT}` left unresolved → emit
  `⚠ Plugin runtime drift check incomplete: <REASON or a one-line cause>` **only if** the project
  root holds a `.claude-plugin/plugin.json` whose `name` is `craft`; otherwise emit no line (a
  consumer project, or another plugin's source repo, is never nagged about CRAFT's runtime).

Reported, never corrected — the helper is read-only. Never abort prime.

### 6. Scan active slices

- `Glob` `.claude/plans/*.md`.
- For each slice plan file:
  - Read its frontmatter (`Status`, `Slice-ID`, `Started`, `Phase`).
  - Read its `## Sub-Tasks` section, count completed (`- [x]`) vs. total.
  - Compute days-since-`Started`.

Build a list of active slices with: `slice-NNN "<title>" — Phase <X>, <Y>/<Z> sub-tasks done`.

For any slice with `Status: blocked`, derive its phase from `Blocked-status` via the Status→phase
mapping in `/craft:status` (`commands/status.md` → **Phase label**) — never render `blocked` as a
phase; `Blocked-status` is an execution token that says where the slice resumes — and append a
**blocked marker** `⛔ blocked → <Blocked-on> (<Blocker-type>)`. **Orphan detection:** when
`Blocker-type` is `prerequisite-work` and `Blocked-on` resolves to neither an active plan
(`.claude/plans/`) nor an archive (`.claude/project/slices/`), append `· ⚠ orphan` — the
prerequisite was aborted or never created. A `Blocked-on: (pending — …)` marker and free-text
`Blocked-on` (the `external` / `decision` / `access` types) carry no resolvable ID and are
**never** orphans.

### 7. Stale-slice detection

Any slice with `Started` older than **7 days** (default — overridable in `rules.md` under `## Self-Verification Settings`) and not in Phase 9 is flagged:

```
⚠ slice-NNN untouched for <K> days — resume or discard?
```

### 8. Recommended next action

Pick one based on the state, in priority order — the first matching condition determines the primary recommendation. Exception: case 3 (blocked) may additionally **co-fire** with case 4/5 when blocked and unblocked slices coexist (surface the blocker *and* recommend the workable slice).

1. **Pending handoff** — if any active slice has `Handoff active: yes` in its frontmatter → surface it prominently:

   ```
   ⚠ Handoff waiting for slice-NNN — a previous session ended with /craft:handoff.
   Recommended next: /craft:continue slice-NNN → the handoff summary will be loaded.
   ```

2. **Stale slice flagged** — recommend resolving it first: `Recommended next: resolve stale slice-MMM (resume or /craft:abort) before continuing`.
3. **Blocked slice(s)** — a `Status: blocked` slice is never recommended as a plain `/craft:continue` (it cannot be worked until its blocker clears). Surface it with its blocker and route to `/craft:unblock`:

   ```
   ⛔ slice-NNN blocked on <Blocked-on> (<Blocker-type>)<· ⚠ orphan, if dangling>.
   Recommended next: /craft:unblock slice-NNN → resume | re-plan | abort (or resolve the prerequisite).
   ```

   For a `prerequisite-work` block whose prerequisite has since landed, note that `/craft:commit` auto-resurfaces it — `/craft:unblock` may just confirm. This case wins over 4/5 below when the only non-stale active slices are blocked; if some active slices are unblocked, surface the blocked one(s) here **and** fall through to 4/5 for the workable slice(s).
4. **Exactly one active (non-blocked) slice** → recommend continuing it: `Recommended next: continue slice-NNN (Phase X) → /craft:continue to resume`.
5. **Multiple active (non-blocked) slices** → list them and ask which to focus on: `Multiple active slices — pick one to focus: /craft:continue <slice-NNN>`.
6. **No active slice** → recommend planning new work: `Recommended next: /craft:plan <feature-name> to start a new slice`.

### 9. Mark the session primed

After the status block is emitted — i.e., pre-flight passed and context loaded
successfully — write the empty session marker so context-dependent commands know this
session is primed:

- Create `.claude/plans/.primed` via Bash: `mkdir -p .claude/plans && touch .claude/plans/.primed`. The `mkdir -p` guards the **first** prime right after `/craft:onboard` (which creates `.claude/project/` but not `.claude/plans/` — that directory is otherwise created lazily by the first `/craft:plan`).

This marker is **per-session** (the SessionStart hook clears it at the next session
start) and gitignored. It is the sentinel the **ensure-primed gate**
(`skills/workflow/SKILL.md` → *Session Priming Gate*) checks before every
context-dependent command. Write it **only on a successful prime**: when pre-flight
aborts (a required tool is missing, or the project is not onboarded), prime stops before
this step and the marker is not written, so the gate correctly re-primes next time.

---

## Output Format

The full status block — emit exactly this shape:

```
✓ Project: <name> (<stack tags>)
✓ CRAFT plugin v<version>   (or ⚠ CRAFT plugin version unknown — see step 5b)
<plugin-runtime line — only in CRAFT's own source repo; ✓ if runtime = working tree, ⚠ if it diverges, ⚠ drift check incomplete if the check could not run (see step 5c)>
✓ Rules ↔ State drift check: <clean | ⚠ N drifts>
  <one line per drift, if any>
✓ Tools: context-mode ✓ (<version>), agent-browser ✓, git ✓ (<version>), gh ✓ (<version>), bash ✓ (<version>), python3 ✓ (<version>)   (bash ?, python3 ? when the toolchain check was incomplete)
  ⚠ <Hook bash: … — only when the helper reports STATUS=hook-mismatch; or ⚠ Toolchain check incomplete: … (see Pre-flight Step 1)>
✓ Senior-Developer baseline loaded
<stack-pack line — only when a pack is declared; ✓ if found, ⚠ if missing (see step 4)>
✓ Agent models: <one-line summary if no overrides; one line per overridden agent otherwise (see step 4b)>
  ⚠ <override warning(s), if any>
✓ Language: chat=<lang>, commits=<lang>, comments=<lang>  (see step 4c)
✓ CRAFT profile: <preset — effective settings | none — plugin defaults>  (see step 4d)
  ⚠ <profile warning(s), if any>
<read-only-context line — only when connected projects are declared; ✓ if all trusted, ⚠ if some not readable (see step 4e)>
✓ Local state gitignored   (or ⚠ Local state not gitignored: <paths> + the --apply offer, or ⚠ … check incomplete — see step 4f)
  ⚠ <tracked-file warning(s), if any>
<.gitignore update line — only after a yes to the step-4f offer>


Active slices:
  → slice-NNN "<title>" — Phase X, Y/Z sub-tasks done
  → slice-QQQ "<title>" — Phase 5, 3/5 sub-tasks done  ⛔ blocked → slice-030 (prerequisite-work)
⚠ slice-PPP untouched for K days — resume or discard?

Recommended next: <action>
  → <follow-up command>
```

If no active slices, replace that section with `No active slices.`

Keep the block under 20 lines for the common case. If many slices are active and the block would exceed that, summarize older slices into a one-line collapse: `+ 4 more slices (run /craft:status for full list)`.

After emitting the block, prime silently writes the `.claude/plans/.primed` session marker (Procedure step 9) — no extra output line.

---

## Error Handling

| Situation | Behavior |
|---|---|
| One or more tools missing | Abort with concrete install instructions, do not proceed. |
| bash or python3 missing / too old, or a current bash only off PATH | Part of the one missing-tools abort; the messages are defined in Pre-flight Step 1 (table and helper outcomes). |
| Hooks ran an older bash than the Bash tool (`check-toolchain.sh` exit 10) | Emit the `⚠ Hook bash: …` line with the remedy and continue. Not a blocker. |
| `check-toolchain.sh` not found, exits 2, or prints something unexpected | Emit `⚠ Toolchain check incomplete: <reason>` and continue. |
| `context-mode` outdated | Warn, suggest `/ctx-upgrade`, continue priming. |
| `.claude/project/intent.md` missing | Emit onboarding nudge, do not proceed. |
| Declared stack-pack file missing | Emit the `⚠ Stack-pack …` status line; continue priming. Never a blocker. |
| `rules.md` missing but `intent.md` present | Treat as inconsistent onboarding. Tell user: *"intent.md exists but rules.md is missing. Run `/craft:onboard` to repair the setup."* and stop. |
| Slice plan file unreadable or malformed | Log it as `⚠ slice plan <file> unreadable — skipping`. Continue with other slices. |
| Drift check sub-command itself errors out (e.g., grep on missing manifest) | Report `⚠ drift check incomplete: <reason>`. Continue. Do not abort the whole prime. |
| `## Agent Model Overrides` section absent | Skip overrides; report defaults only. Not an error. |
| Override line malformed | Emit `⚠ Override line not parseable: '<line>'` and skip that line. Continue. |
| Override names an unknown agent or uses an invalid model value | Emit the soft warning (step 4b). Do not abort. |
| `.claude-plugin/plugin.json` missing or malformed | Emit `⚠ CRAFT plugin version unknown — plugin.json <not found\|malformed>` and continue. Not a blocker. |
| Plugin runtime diverges from the working tree (step 5c, dev repo only) | Emit `⚠ Plugin runtime ≠ working tree — …` with the differing files and continue. Not a blocker. |
| `check-plugin-cache-drift.sh` reports `STATUS=unknown`, exits 2, prints nothing, cannot be found, or `${CLAUDE_PLUGIN_ROOT}` is unresolved | In the CRAFT source repo (`.claude-plugin/plugin.json` `name` = `craft`) emit `⚠ Plugin runtime drift check incomplete: <reason>`; anywhere else emit nothing. Continue either way. Never abort. |
| `craft-profile.md` absent | Report `✓ CRAFT profile: none — plugin defaults`. Not an error (step 4d). |
| `craft-profile.md` malformed (unknown key, out-of-enum value, or `Auto-commit: off`+`Mode: worktree`) | Emit the `⚠ CRAFT profile: …` warning(s) from step 4d and continue. Never a blocker. |
| Declared connected project not yet in `additionalDirectories` (step 4e) | Emit the `⚠ Read-only context …` line and offer `--apply` (confirmation-gated). Not a blocker. |
| `ensure-readonly-context.sh` errors (python3 missing / settings unparseable) | Emit `⚠ Read-only context check incomplete: <reason>` and continue. Never abort. |
| CRAFT local state not gitignored (step 4f) | Emit the `⚠ Local state not gitignored …` line and offer `--apply` (confirmation-gated). Not a blocker. |
| `ensure-gitignore.sh` not found, errors, or `--apply` hits a conflicting rule (exit 6) | Emit the matching `⚠` line from step 4f and continue. Never abort. |

---

## What This Command Does NOT Do

- It does **not** edit `intent.md` or `rules.md`. Use `/craft:intent-update` for the former; `/craft:onboard` for repair of the latter.
- It does **not** decide what to do next on your behalf — it only **recommends**.
- It does **not** start a slice. Use `/craft:plan` for that.
- It does **not** activate any project-local skills. Those are loaded lazily by phase commands (`/craft:build`, `/craft:refactor`, etc.) when needed.
- It does **not** load or activate the declared stack-pack — it only checks that the pack's file exists. The code-near phases load it.
- It does **not** correct drift autonomously. Drift is reported; the human chooses Bend / Override / Repeal (see `skills/workflow/SKILL.md` rule-conflict policy).
