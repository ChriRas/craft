---
description: Session-start context loader. Checks tools, loads project knowledge, validates Rules ↔ State, lists active slices, and recommends the next action. Auto-runs on SessionStart when the project is onboarded.
allowed-tools: ["Bash", "Read", "Glob", "Grep"]
---

# /prime — Load Project Context

## Purpose

Bring a fresh chat session into the project's working context: verify the toolchain, activate context-mode, read project knowledge, detect any Rules ↔ State drift, surface active slices, and tell the user exactly where to continue.

`/prime` is the navigation backbone of every session. It is invoked automatically by the SessionStart hook when `.claude/project/intent.md` exists. It can also be re-invoked manually after editing `rules.md` or `intent.md`.

Follow the methodology defined in `skills/workflow/SKILL.md` — in particular the autonomy taxonomy, knowledge model, and tool-dependency policy.

---

## Pre-flight

Before doing anything else, this command MUST run two checks in order. **If either fails, abort with install instructions — do not continue to context loading.**

### Step 1 — Tool health (strict)

Verify each of the four required tools is installed and runnable. Run these in a single batched check:

| Tool | Detection | If missing |
|---|---|---|
| **context-mode** | The MCP namespace `mcp__plugin_context-mode_context-mode__*` is available. If you cannot call `mcp__plugin_context-mode_context-mode__ctx_stats`, treat context-mode as missing. | Tell the user: *"context-mode is required. Install via `claude /plugin install context-mode@claude-plugins-official`. See https://code.claude.com/docs/en/plugins for help."* and abort. |
| **agent-browser** | Run `command -v agent-browser` via Bash. | *"agent-browser is required. Install per upstream documentation: https://github.com/snadi/agent-browser"* and abort. |
| **git** | Run `command -v git` via Bash. | *"git is required. macOS: `brew install git`. Linux: use your distro package manager. Windows: https://git-scm.com/downloads"* and abort. |
| **gh** | Run `command -v gh` via Bash. | *"gh (GitHub CLI) is required. macOS: `brew install gh`. Linux: see https://github.com/cli/cli#installation"* and abort. |

After listing all missing tools, stop and wait for the user to install them. Do not partially proceed.

### Step 2 — Context-mode activation & currency

- Call `mcp__plugin_context-mode_context-mode__ctx_stats` once to confirm context-mode responds.
- If the response mentions an outdated version (e.g., "v1.0.118 outdated → v1.0.140 available"), surface the message and suggest the user run `/ctx-upgrade`. Continue priming for now — outdated context-mode is a warning, not a blocker.
- From this point forward in the session, use context-mode (`ctx_batch_execute`, `ctx_execute`, `ctx_execute_file`, `ctx_search`) for any operation that would otherwise produce large output. This is required, not a preference.

### Step 3 — Project onboarding check

- Use `Read` to check `.claude/project/intent.md`.
- If the file does not exist, the project has not been onboarded. Emit a single-line nudge:

  ```
  Project not onboarded — run /onboard to set up project knowledge.
  ```

  Stop. Do not attempt to load missing files or guess at project state.

---

## Procedure

If pre-flight passes, perform the following in order. Use parallel reads where possible.

### 1. Load project knowledge

Read these files (some are optional):

- `.claude/project/intent.md` (required at this point)
- `.claude/project/rules.md` (required)
- `.claude/project/roadmap.md` (optional)
- `CLAUDE.md` (optional, in repo root)

Hold their contents in working memory for the rest of the session.

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
   This is expected if dependencies aren't installed yet. Re-run /prime after <install command>.
```

**Never silently correct drift.** Reporting is the action; correction is a separate human-confirmed step.

### 4. Tool versions (informational)

After tools are confirmed installed, capture and report versions for the status block:

- `context-mode`: take from the `ctx_stats` response.
- `agent-browser`: `agent-browser --version` (if supported; otherwise just confirm `✓`).
- `git`: `git --version` (first line).
- `gh`: `gh --version` (first line).

### 5. Scan active slices

- `Glob` `.claude/plans/*.md`.
- For each slice plan file:
  - Read its frontmatter (`Status`, `Slice-ID`, `Started`, `Phase`).
  - Read its `## Sub-Tasks` section, count completed (`- [x]`) vs. total.
  - Compute days-since-`Started`.

Build a list of active slices with: `slice-NNN "<title>" — Phase <X>, <Y>/<Z> sub-tasks done`.

### 6. Stale-slice detection

Any slice with `Started` older than **7 days** (default — overridable in `rules.md` under `## Self-Verification Settings`) and not in Phase 8 is flagged:

```
⚠ slice-NNN untouched for <K> days — resume or discard?
```

### 7. Recommended next action

Pick one based on the state, in priority order — first matching condition wins:

1. **Pending handoff** — if any active slice has `Handoff active: yes` in its frontmatter → surface it prominently:

   ```
   ⚠ Handoff waiting for slice-NNN — a previous session ended with /handoff.
   Recommended next: /continue slice-NNN → the handoff summary will be loaded.
   ```

2. **Stale slice flagged** — recommend resolving it first: `Recommended next: resolve stale slice-MMM (resume or /abort) before continuing`.
3. **Exactly one active slice** → recommend continuing it: `Recommended next: continue slice-NNN (Phase X) → /continue to resume`.
4. **Multiple active slices** → list them and ask which to focus on: `Multiple active slices — pick one to focus: /continue <slice-NNN>`.
5. **No active slice** → recommend planning new work: `Recommended next: /plan <feature-name> to start a new slice`.

---

## Output Format

The full status block — emit exactly this shape:

```
✓ Project: <name> (<stack tags>)
✓ Rules ↔ State drift check: <clean | ⚠ N drifts>
  <one line per drift, if any>
✓ Tools: context-mode ✓ (<version>), agent-browser ✓, git ✓ (<version>), gh ✓ (<version>)

Active slices:
  → slice-NNN "<title>" — Phase X, Y/Z sub-tasks done
  → slice-MMM "<title>" — Phase X, Y/Z sub-tasks done
⚠ slice-PPP untouched for K days — resume or discard?

Recommended next: <action>
  → <follow-up command>
```

If no active slices, replace that section with `No active slices.`

Keep the block under 20 lines for the common case. If many slices are active and the block would exceed that, summarize older slices into a one-line collapse: `+ 4 more slices (run /status for full list)`.

---

## Error Handling

| Situation | Behavior |
|---|---|
| One or more tools missing | Abort with concrete install instructions, do not proceed. |
| `context-mode` outdated | Warn, suggest `/ctx-upgrade`, continue priming. |
| `.claude/project/intent.md` missing | Emit onboarding nudge, do not proceed. |
| `rules.md` missing but `intent.md` present | Treat as inconsistent onboarding. Tell user: *"intent.md exists but rules.md is missing. Run `/onboard` to repair the setup."* and stop. |
| Slice plan file unreadable or malformed | Log it as `⚠ slice plan <file> unreadable — skipping`. Continue with other slices. |
| Drift check sub-command itself errors out (e.g., grep on missing manifest) | Report `⚠ drift check incomplete: <reason>`. Continue. Do not abort the whole prime. |

---

## What This Command Does NOT Do

- It does **not** edit `intent.md` or `rules.md`. Use `/intent-update` for the former; `/onboard` for repair of the latter.
- It does **not** decide what to do next on your behalf — it only **recommends**.
- It does **not** start a slice. Use `/plan` for that.
- It does **not** activate any project-local skills. Those are loaded lazily by phase commands (`/execute`, `/refactor`, etc.) when needed.
- It does **not** correct drift autonomously. Drift is reported; the human chooses Bend / Override / Repeal (see `skills/workflow/SKILL.md` rule-conflict policy).
