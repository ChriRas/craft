---
description: One-time project onboarding — bootstraps `.claude/project/` for fresh projects or migrates an existing `.claude/` setup. Detects existing content automatically and switches to migration sub-path.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:onboard — Set Up the Project for the Workflow

## Purpose

Get a project ready for the 9-phase workflow. Two distinct sub-paths share one entry point:

- **Greenfield path** — `.claude/project/` does not exist. Scan the repo, draft project knowledge files dialogically, validate.
- **Migration path** — `.claude/` exists with prior content (commands, agents, skills, CLAUDE.md). Classify each asset, move conflicts to `_legacy/`, split `CLAUDE.md` into `intent.md` / `rules.md` / `roadmap.md`.

This command is a **durable-state mutation** and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md`. Refer to that skill for the knowledge model (State / Intent / Rules); the migration classification scheme is described in the procedure below.

---

## Pre-flight

### Step 1 — Tool health (strict)

Same as `/craft:prime` — verify context-mode, agent-browser, git, gh are installed and runnable. Abort with install instructions if any are missing.

### Step 2 — Detect mode

- `Glob` `.claude/**/*` to detect prior content.
  - Any matches (other than `.claude/project/` itself) → **migration mode**.
  - No matches → **greenfield mode**.

Mode is informational at this stage; the Pre-Assertions decide whether onboarding may proceed at all.

---

## Pre-Assertions

Run all three. Any failure stops the command before any file is touched.

### A1 — Inside a git working tree

```
git rev-parse --show-toplevel
```

If non-zero exit → abort:

```
This directory is not a git repo. Onboarding writes files that should be
version-controlled. Initialize a git repo first (`git init`) or move to an
existing repository.
```

### A2 — Not already onboarded

`Read` `.claude/project/intent.md`.

- If the file exists and is non-empty → abort:

  ```
  Project is already onboarded. Run `/craft:prime` to load context, or
  `/craft:intent-update` to revise intent.
  ```

  No mutation occurs.

- If the file exists but is empty, treat as not-onboarded (proceed).

### A3 — Templates available

The plugin must ship the templates and base preset this command writes from. Confirm `Read`-ability of:

- `${CLAUDE_PLUGIN_ROOT}/templates/intent.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/rules.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/roadmap.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/claude-md-index.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/craft-profile.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/profiles/balanced.md` (base preset + the `[D]` fast-defaults source)
- `${CLAUDE_PLUGIN_ROOT}/templates/profiles/careful.md` (guided preset-name matching)
- `${CLAUDE_PLUGIN_ROOT}/templates/profiles/autonomous.md` (guided preset-name matching)

If any template is missing → abort: *"Plugin templates missing at `<path>`. The CRAFT install may be corrupted — re-install the plugin and re-run /craft:onboard."*

---

## Procedure — Greenfield Mode

### 1. Choose dialogic depth (Level 0)

Present two explicit options:

- **Heuristic-first (fast)** — scan existing repo artifacts (`README.md`, `package.json`, `composer.json`, `Cargo.toml`, `pyproject.toml`, `*.sh`, etc.), draft `intent.md` / `rules.md` from heuristics, then 3–5 clarifying questions for what cannot be inferred (product vision, tabus).
- **Grill-Me-intensive (deep)** — full interview-style alignment via `skills/grill-me/SKILL.md`. Recommended for greenfield projects whose structure is not yet clear.

Recommend heuristic-first as the default. User decides.

### 2. Heuristic scan

Read whichever exist:

- `README.md` → use to seed `## Product Vision` in `intent.md`.
- `package.json` / `composer.json` / `Cargo.toml` / `pyproject.toml` / `go.mod` → use to seed `## Stack & Tools` in `rules.md`.
- The same manifests yield a **candidate stack-pack** — map them with the Stack-Pack Detection table below; hold the candidate for the proposal in step 3.
- `.github/workflows/*.yml` → use to seed `## Deployment` in `rules.md`.
- `.editorconfig`, lint configs → use to seed `## Code Conventions` in `rules.md`.
- `*.sh` / `Makefile` / `Taskfile.yml` → record common developer commands in `rules.md`.

Build drafts into memory. Do not write files yet.

### 3. Dialogic clarification (Level 0)

Ask 3–5 targeted questions, one at a time:

- Product Vision (if README is silent or generic): "What is this project trying to achieve, in one sentence?"
- Active Goals: "What are the 1–3 things that need to happen in this project right now?"
- Architectural Decisions: "What major technical choice should the next agent know about? Why?"
- Tabus: "What patterns or actions should never happen here?"
- Roadmap (optional): "Do you have longer-term phases? If yes, name them. If no, skip."
- Stack-Pack: present the candidate from the heuristic scan and run the proposal in the Stack-Pack Detection sub-procedure — the confirmed value fills `## Personality` `Stack-Pack:` in `rules.md`.
- Language: run the Language Config sub-procedure — the confirmed values fill the `## Operational Language` block of the CRAFT profile (`.claude/project/craft-profile.md`).
- Profile: run the Profile Config sub-procedure — the `[D]` fast-defaults or `[G]` guided answers fill the Execution / Commit Policy / Merge Workflow / Epic Mode / Permissions blocks of the CRAFT profile, and the chosen permission scope drives the Permission Allowlist write in step 4.

### 4. Write project files

Generate using the plugin templates:

- `.claude/project/intent.md`
- `.claude/project/rules.md`
- `.claude/project/craft-profile.md` — rendered from `templates/craft-profile.md.template`: the `> Preset:` line and the Execution / Commit Policy / Merge Workflow / Epic Mode / Permissions placeholders take the **Profile Config sub-procedure's resolved values** (`[D]` fast-defaults → the `balanced` preset's literals from `templates/profiles/balanced.md`; `[G]` guided → the per-knob answers), the `## Operational Language` placeholders (`{{chat_language_or_system}}` etc.) take the Language Config sub-procedure's values, and `## Agent Model Overrides` is left at its default (empty). Immediately after writing the profile, run the Permission Allowlist sub-procedure to write the chosen scope's read-only allowlist into `.claude/settings.local.json`.
- `.claude/project/roadmap.md` (only if user provided roadmap content)
- `CLAUDE.md` in repo root — slim index pointing to the above

Do **not** pre-create an empty `.claude/project/design/` — the directory is the
**Durable Capture** home for cross-cutting design knowledge (domain model, scenario
catalogs, matrices) and is populated on demand, the first time such knowledge is
produced (see `skills/workflow/SKILL.md` → Knowledge Model → Durable Capture). The
generated `CLAUDE.md` index already points at it so the convention is discoverable — the
link is forward-looking; the directory appears the first time it is populated, exactly as
the `roadmap.md` link does.

#### Post-write size check

After writing, count lines for `intent.md` and `rules.md`. If either exceeds **80 lines**, emit the oversize warning (same text as in the migration knowledge-split sub-procedure). Warning only — no refusal.

### 5. Drift validation

Run the drift check from `/craft:prime` immediately.

- If no drifts and all manifests verifiable → record `drift = clean`.
- If manifests are absent for a stack mentioned in `rules.md` (e.g., `composer.json` missing for PHP rules) → record `drift = incomplete` with the incomplete-check note.
- If genuine drift exists → record `drift = <N>` with the list. The user must revise `rules.md` before continuing.

---

## Procedure — Migration Mode

### 1. Inventory and classify

`Glob` everything under `.claude/`. Categorize each asset into one of five classes:

| Class | Definition | Default action |
|---|---|---|
| **Universal conflict** | Commands that overlap with plugin commands (any of: `plan`, `plan-feature`, `plan-backlog`, `plan-parallel`, `review-plan`, `execute`, `co-review`, `commit`, `prime`, `create-prd`, `create-rules`, `onboard`, `debug`, `handoff`, `recap`, `refactor`, `test`, `pause`, `abort`, `intent-update`, `continue`, `status`, `brainstorm`, `grill-me` — or variants with the same intent) | Move to `.claude/commands/_legacy/` |
| **Plugin-already-provides** | A project-local **skill** with the same name as a plugin-shipped skill (e.g., `agent-browser`, `brainstorm`, `grill-me`, `debug`, `workflow`) | **Ask the user** — see step 2.5 below |
| **Specialist keep** | Language/stack-specific skills and agents whose names don't collide with plugin skills (e.g., `developer` for PHP, `code-review` for Laravel) | Leave in place |
| **Knowledge-split source** | `CLAUDE.md`, `README.md`, `PRD.md` containing mixed Vision/Stack/Phases content | Split into `intent.md` + `rules.md` + `roadmap.md` |
| **Project-local keep** | Project tooling commands (e.g., `init-project.md` that runs `task start`), allowlist files (`allowed-commands.md`), `settings.local.json` | Leave in place |

### 2. Inventory report (Level 0)

Present the classification to the user:

```
Found <N> assets in .claude/. Proposed actions:

[Universal conflict → _legacy/]
  - .claude/commands/craft:plan-feature.md
  - .claude/commands/execute.md
  - ...

[Plugin-already-provides — pending your decision]
  - .claude/skills/agent-browser/   (collides with plugin skill)
  - ...

[Specialist keep — leave in place]
  - .claude/agents/developer.md
  - .claude/skills/code-review/...

[Knowledge-split source → split into intent.md / rules.md / roadmap.md]
  - CLAUDE.md (281 lines)

[Project-local keep — leave in place]
  - .claude/commands/init-project.md
  - .claude/allowed-commands.md
  - .claude/settings.local.json

Confirm by class? (Y / override-by-item / cancel)
```

### 2.5 Resolve plugin-already-provides collisions

For each asset in the **Plugin-already-provides** class, ask explicitly — rendering the `[P]/[U]/[D]` menu with its full legend per the lettered-choice-prompt convention in `skills/workflow/SKILL.md`:

```
Skill collision: <name>
  Project version: .claude/skills/<name>/SKILL.md
  Plugin version:  ${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md

Pick one:
  [P] Keep project-local (the plugin version remains inactive — project wins per Claude Code precedence)
  [U] Use plugin version (project-local moves to _legacy/)
  [D] Diff them first — show me the differences before deciding
```

If `[D]`: show a unified diff of the two SKILL.md files. Then re-ask `[P]` or `[U]`.

Repeat for every collision before moving to step 3.

### 3. Confirm-by-class with override option

If user accepts wholesale: proceed.

If user says "override": let them flip individual items between classes one at a time:

```
> override
Which item? <e.g., .claude/commands/craft:plan-parallel.md>
Move to which class? [universal-conflict | plugin-already-provides | specialist-keep | knowledge-split | project-local-keep | delete]
```

Repeat until user types `done`.

### 3.5 Final preview (dry-run)

Before any file is moved or written, emit a final preview:

```
Final preview — about to execute:
  Move to _legacy/:        <N> files
  Skill collisions:        <N> resolved (P=<n>, U=<n>)
  Split source:            CLAUDE.md (<N> lines) → intent.md + rules.md [+ roadmap.md]
  Generate:                .claude/project/intent.md
                           .claude/project/rules.md
                           .claude/project/craft-profile.md
                           [.claude/project/roadmap.md]
                           [.claude/project/design/<topic>.md  (cross-cutting knowledge, if any)]
                           CLAUDE.md (replaced with index)
  Validate:                Rules ↔ State drift check after write

Type `apply` to proceed, or anything else to abort cleanly.
```

Only proceed if user types `apply` exactly. Anything else → abort with no file changes.

### 4. Execute

For each asset, apply its final class action:

- **Universal conflict** → `mv` to `.claude/commands/_legacy/<original-name>`. Create `_legacy/` if needed.
- **Plugin-already-provides** → per the user's `[P]` or `[U]` decision from step 2.5. On `[U]`, move project's skill dir to `_legacy/`. On `[P]`, no action.
- **Specialist keep** → no action.
- **Knowledge-split** → see knowledge-split sub-procedure below.
- **Project-local keep** → no action.

#### Knowledge-split sub-procedure

Parse the source file. Identify sections that map to:

- **Product Vision** → `intent.md` (auto-import; clean prose, low ambiguity)
- **Stack & Tools** → `rules.md` (auto-import; structured)
- **Personality / stack-pack** → `rules.md` `## Personality` block — the source file rarely declares one, so fill `Stack-Pack:` via the Stack-Pack Detection sub-procedure (propose-and-confirm).
- **Language settings** → the CRAFT profile (`.claude/project/craft-profile.md`) `## Operational Language` block. A migration source rarely declares language preferences, so fill the block with defaults (`Chat` = system language, `Commits` = English, `Comments` = English) without extra interrogation. Only run the full Language Config sub-procedure dialog if the source explicitly states a chat/commit/comment language preference.
- **Autonomy / commit / merge / permission settings** → the CRAFT profile's Execution / Commit Policy / Merge Workflow / Epic Mode / Permissions blocks. Run the Profile Config sub-procedure (`[D]` fast-defaults is the sensible migration default; `[G]` guided is available), then the Permission Allowlist sub-procedure to write the chosen scope's read-only allowlist into `.claude/settings.local.json`.
- **Architectural Decisions** → `intent.md` (auto-import)
- **Code Conventions / Patterns** → `rules.md` (auto-import)
- **Tabus / Anti-Patterns** → `rules.md` (auto-import)
- **Deployment** → `rules.md` (auto-import)
- **Phase Plans / Roadmap** → `roadmap.md` (auto-import)
- **Cross-cutting design knowledge** (domain model, scenario catalogs, matrices, or any
  hand-rolled concept doc such as a `concept.md` that spans multiple slices/epics) →
  `.claude/project/design/<topic>.md`, one focused file per topic — the **Durable
  Capture** home for design knowledge that is neither *why* (intent) nor *how* (rules).
- **Common Commands** → `CLAUDE.md` index (under `## Common Commands`)
- **Notes / Working Notes / freeform** → **dialogic triage** (see below)
- **Project Structure tree, Key Files table, State references** → **discard** (this is State; lives in code)

##### Notes-section dialog (Gap #5)

If the source contains a "Notes" / "Working Notes" / free-form section that mixes still-relevant decisions with dated working-notes, ask the user to triage **each bullet** one at a time — rendering the full `[I]/[R]/[O]/[K]/[D]` legend each time, per the lettered-choice-prompt convention in `skills/workflow/SKILL.md`:

```
Notes entry <N>/<M>:
"<verbatim text of the note>"

Where does this belong?
  [I]ntent     — promote to intent.md as a decision
  [R]ules      — promote to rules.md as a rule
  [O]admap     — promote to roadmap.md as a parked item
  [K]eep       — keep in CLAUDE.md under a freeform "Notes" section
  [D]iscard    — drop (note is stale or no longer relevant)
```

Walk through every entry. Default for skipped entries: `K`.

##### Post-split size check (Gap #4)

After writing `intent.md` and `rules.md`, count their lines:

- If either file exceeds **80 lines**, emit a warning:

  ```
  ⚠ <intent.md | rules.md> is <N> lines (soft limit 80).
     The file is loaded into context on every /craft:prime — keep it lean.
     Consider extracting the longest section (e.g., "Code Conventions") into a
     separate file like .claude/project/conventions.md and referencing it from rules.md.
  ```

- Warning only; do not refuse to write. The user decides whether to trim now or later.

### 5. Generate `CLAUDE.md` index

If `CLAUDE.md` did not previously exist, generate one from `templates/claude-md-index.template`. If it did exist and was the knowledge-split source, replace its content with the index template (the prior content has been distributed into `.claude/project/`).

### 6. Drift validation

Run the drift check from `/craft:prime` (same logic as in `/craft:prime` Step 3):

- No drifts → record `drift = clean`.
- Manifests absent for a stack mentioned in `rules.md` → record `drift = incomplete`.
- Genuine drift → record `drift = <N>` with the list; the user must revise `rules.md` before running anything else.

---

## Stack-Pack Detection (shared sub-procedure)

Both modes fill `rules.md`'s `## Personality` → `Stack-Pack:` field by detecting a
candidate from the project's manifests, then **proposing it for confirmation** — a
detected value is never written silently.

### Detection table

Inspect whichever manifest files exist; pick the first matching row:

| Manifest signal | Candidate stack-pack |
|---|---|
| `composer.json` with a `laravel/framework` dependency | `stack-php-laravel` |
| `composer.json` without Laravel | `stack-php` |
| `package.json` with a `next` dependency | `stack-ts-nextjs` |
| `package.json` with `react` but no `next` | `stack-ts-react` |
| `package.json` with TypeScript and none of the frameworks above | `stack-ts` |
| `Cargo.toml` | `stack-rust` |
| `pyproject.toml` or `requirements.txt` | `stack-python` |
| `go.mod` | `stack-go` |
| none of the above, or the stack is unclear | `none` |

A candidate is only a name. Just `stack-php-laravel` ships with the plugin today;
other names are valid for projects that add their own pack under
`~/.claude/craft-personalities/<name>/`. Proposing a not-yet-existing name is safe —
`/craft:prime` warns at session start whenever a declared pack is missing.

### Proposal (Level 0 — propose, never silently mutate)

Present the candidate and let the user decide — rendering the full `[C]/[O]/[N]` legend per the lettered-choice-prompt convention in `skills/workflow/SKILL.md`:

```
Detected stack-pack candidate: <name>
  [C] Confirm  — write `<name>` into rules.md `## Personality`
  [O] Override — name a different stack-pack
  [N] None     — this project uses no stack-pack
```

Write the chosen value into the `## Personality` `Stack-Pack:` field of the generated
`rules.md`. When detection yields `none`, still surface the prompt so the user can
override.

---

## Language Config (shared sub-procedure)

Both modes fill the `## Operational Language` block of the CRAFT profile
(`.claude/project/craft-profile.md`) with three independent settings. The block is
consumed downstream by `/craft:prime` (reports them), `/craft:commit` (commit-message
language), and `/craft:build` / `/craft:review` (code-comment language).

Detect the **system language** first (the language the user is currently writing in,
falling back to the host locale, e.g. `de-DE` → German). Then run the proposal —
rendering the full `[S]/[O]` legend for chat, per the lettered-choice-prompt
convention in `skills/workflow/SKILL.md`:

```
Language settings (detected system language: <lang>):

  Chat — how I converse with you:
    [S] System language (<lang>) — I converse with you in <lang>
    [O] Other                    — name a language; I use it for all chat
```

Then ask for commits and comments, each defaulting to English (just confirm or
override — no forced choice):

```
  Commits  — commit-message language  [default: English]
  Comments — code-comment language     [default: English]
```

Write the three confirmed values into the profile's `## Operational Language` block,
mapping them onto the `craft-profile.md.template` placeholders
`{{chat_language_or_system}}`, `{{commit_language_default_english}}`, and
`{{comment_language_default_english}}`:

- **Chat:** the chosen chat language (system language if `[S]`).
- **Commits:** the chosen commit language (English unless overridden).
- **Comments:** the chosen comment language (English unless overridden).

If the user skips the dialog entirely, write the defaults: `Chat` = system language,
`Commits` = English, `Comments` = English.

---

## Profile Config (shared sub-procedure)

Both modes populate the CRAFT profile's autonomy/commit/merge/epic/permission blocks
(`.claude/project/craft-profile.md`). Two paths render the **same** template — the choice
only decides how the knob values are sourced. The `## Operational Language` block is filled
by the Language Config sub-procedure and the `## Agent Model Overrides` block stays at its
default (empty); this sub-procedure covers everything else.

### Step 1 — Fast-defaults or guided (Level 0)

Render the full `[D]/[G]` legend per the lettered-choice-prompt convention in
`skills/workflow/SKILL.md`:

```
CRAFT autonomy / commit / merge / permission setup:
  [D] Defaults (fast) — apply the `balanced` preset: worktree builds · per-sub-task
      auto-commit · direct merge to trunk · parallel epics · standard (read-only)
      permission allowlist. CRAFT's out-of-the-box behaviour.
  [G] Guided — one multiple-choice question per knob; deviate wherever you want.
```

`[D]` → take every knob value from the `balanced` preset (`templates/profiles/balanced.md`),
set `Preset: balanced`, and skip to Step 3. `[G]` → run Step 2.

### Step 2 — Guided knob dialog (Level 0)

Ask one multiple-choice question per knob, in order, each rendering its full legend. Carry
the answers into memory for the render in Step 3 and enforce the cross-field rule as you go.

1. **Execution mode**
   ```
   Execution mode — how /craft:execute runs work:
     [W] worktree  — parallel-safe; slices build in throwaway git worktrees outside the repo (default)
     [I] in-place  — build on a branch in the main checkout so you can eyeball the raw diff in your IDE
   ```
2. **Auto-commit** — ask **only** when Execution mode = `in-place`. When `worktree`, force
   `on` and say so (the worktree merge model requires per-sub-task commits):
   ```
   Auto-commit (in-place only):
     [N] on  — commit each sub-task as it lands
     [F] off — hold everything uncommitted until you release it in Phase 9
   ```
3. **Merge workflow**
   ```
   Merge workflow — how a finished slice/epic lands:
     [D] direct       — merge straight to the trunk via /craft:commit (default)
     [P] pull-request — open a PR; on protected `main` you approve it and CRAFT merges via gh ("Freigabe ≠ Merge")
   ```
   On `[P]`, set `Type: pull-request`, `Protected-main: yes`, `Approval: github-pr-review`, then
   ask granularity; on `[D]`, set `Type: direct`, `Protected-main: no`, `Approval: chat`,
   `Approval-granularity: auto` and skip the granularity question:
   ```
   PR approval granularity:
     [A] auto      — sequential epic → per slice; parallel epic → once at epic end (default)
     [S] per-slice — a PR + approval for every slice
     [E] per-epic  — one PR + approval at the epic boundary
   ```
4. **Epic mode**
   ```
   Default epic execution for /craft:execute <epic>:
     [P] parallel   — independent slices run concurrently in worktrees (default)
     [S] sequential — slices run one-by-one in place, commit per slice, review halt between
   ```
5. **Permission scope** — selects how broad the **read-only** allowlist onboarding writes
   to `.claude/settings.local.json` is (see the Permission Allowlist sub-procedure). Every
   scope is read-only; mutating commands always keep prompting:
   ```
   Permission scope — size of the read-only default allowlist:
     [M] minimal  — smallest read-only set (git status/diff/log, ls)
     [S] standard — moderate read-only set (adds cat, grep, git show, read-only gh) (default)
     [B] broad    — widest read-only set (adds wc, head, tail, git blame, gh issue/run view)
   ```

**Cross-field validation:** `Auto-commit: off` is reachable only via `in-place`; a
`worktree` choice pins `Auto-commit: on`. Never write the invalid `off` + `worktree`
combination (the same rule `/craft:prime` warns on).

### Step 3 — Hold the resolved knob values + name the preset

Carry the resolved values (Execution Mode, Auto-commit, Merge Type, Protected-main,
Approval, Approval-granularity, Epic Default, Permission Scope) into memory. Set the
`> Preset:` field: `balanced` on the fast path; on the guided path, use a named preset if
the values match one exactly (`careful` / `balanced` / `autonomous`), otherwise `custom`.
The profile write (greenfield step 4 / migration knowledge-split) renders these onto the
`craft-profile.md.template` placeholders, and the Permission Allowlist sub-procedure writes
the matching allowlist into `.claude/settings.local.json`.

---

## Permission Allowlist (shared sub-procedure)

Onboarding writes a **read-only default permission allowlist** into
`.claude/settings.local.json` so common non-mutating commands stop prompting — without ever
auto-granting a mutating one. The Permission Scope chosen in Profile Config (or `standard`
on the fast-defaults path) selects the tier. The file is gitignored by repo convention; the
write is an **idempotent merge** — existing `permissions.allow` entries are preserved and
never duplicated, and nothing is removed.

### Tiers (all read-only — a mutating command is never added)

- **minimal** — `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(ls:*)`
- **standard** — the `minimal` set **plus** `Bash(cat:*)`, `Bash(grep:*)`,
  `Bash(git show:*)`, `Bash(gh pr view:*)`, `Bash(gh pr list:*)`
- **broad** — the `standard` set **plus** `Bash(wc:*)`, `Bash(head:*)`, `Bash(tail:*)`,
  `Bash(git blame:*)`, `Bash(gh issue view:*)`, `Bash(gh run view:*)`

Every entry is audited to have **no mutating mode under any flag** — which is exactly why
`find` is excluded (`find … -delete` / `-exec` mutate). No tier includes a mutating command
(`git add` / `commit` / `push`, `rm`, `mv`, package installs, test runners, formatters), nor
a read command that can mutate via a subcommand or flag — those keep prompting, so trust is
never widened silently. This matches CRAFT's Tabu against silent state changes.

### Write procedure

1. `Read` `.claude/settings.local.json` if it exists; otherwise start from `{}`.
2. Ensure `.permissions` is an object and `.permissions.allow` is an array (create either
   if absent).
3. Merge the chosen tier's entries into `.permissions.allow`, **de-duplicating** — an entry
   already present is not added again; entries already there for any other reason are left
   untouched. Never touch `.permissions.deny`, `.permissions.ask`,
   `.permissions.additionalDirectories`, or any unrelated key.
4. `Write` the merged JSON back (2-space indent, trailing newline).
5. Confirm `.claude/settings.local.json` is gitignored; if a project does not ignore it,
   note that in the output block but still write.

Re-running onboarding is safe: merging the same tier twice yields the identical allowlist
(the idempotency Post-Assertion P2c verifies this).

---

## Post-Assertions

Run all of the following after the chosen procedure completes. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback.

### P1 — `intent.md` written and well-formed

- `Read` `.claude/project/intent.md`. Must exist and be non-empty.
- Must contain a `## Product Vision` section header.

Failure → *"⚠ intent.md was not written or is malformed. Inspect `.claude/project/intent.md` manually before running /craft:prime."*

### P2 — `rules.md` written and well-formed

- `Read` `.claude/project/rules.md`. Must exist and be non-empty.
- Must contain a `## Stack & Tools` section header.

Failure → *"⚠ rules.md was not written or is malformed. Inspect `.claude/project/rules.md` manually."*

### P2b — `craft-profile.md` written and well-formed

- `Read` `.claude/project/craft-profile.md`. Must exist and be non-empty.
- Must contain a `## Operational Language` section header and a `> Preset:` line.

Failure → *"⚠ craft-profile.md was not written or is malformed. Inspect `.claude/project/craft-profile.md` manually before running /craft:prime."*

### P2c — Permission allowlist written to `settings.local.json`

- `Read` `.claude/settings.local.json`. `.permissions.allow` must exist as an array and
  contain every entry of the chosen scope's tier (Permission Allowlist sub-procedure).
- No entry written by onboarding may be a mutating command — the tier is read-only by
  construction; a mutating entry means the wrong set was written.
- Idempotency: each written entry appears exactly once (no duplicates), and any
  pre-existing `permissions.allow` entries are still present.

Failure → *"⚠ Permission allowlist missing, incomplete, or containing a mutating entry in `.claude/settings.local.json`. Inspect it against the chosen scope's tier before running /craft:prime."*

### P3 — `CLAUDE.md` index present

- `Read` `CLAUDE.md` in repo root. Must exist and reference at least `.claude/project/intent.md` and `.claude/project/rules.md`.

Failure → *"⚠ CLAUDE.md is missing or does not point at the new project knowledge files. Re-run /craft:onboard or write CLAUDE.md manually."*

### P4 — Migration cleanup completed (migration mode only)

For each asset classified as **Universal conflict** or as a `[U]`-resolved **Plugin-already-provides**:

- Confirm the original path no longer exists.
- Confirm the corresponding `.claude/commands/_legacy/<name>` (or `.claude/skills/_legacy/<name>/`) exists.

Failure → *"⚠ Migration cleanup incomplete: <N> assets were classified for `_legacy/` but the move did not complete. Inspect `.claude/` manually."*

### P5 — Drift report (informational, never a failure)

Surface the `drift` value recorded during Procedure step 5 / Migration step 6:

- `clean` → `✓ Rules ↔ State drift check: clean`
- `incomplete` → `⚠ Drift check incomplete — see note above. Re-run /craft:prime after dependencies are installed.`
- `<N>` → `⚠ <N> drift items — review and revise rules.md before continuing.`

P5 is reported but never blocks the post-assertion verdict — drift is a Rules↔State mismatch, not an onboarding bug.

---

## Output Format — Both Modes

Final status block, emitted once everything is written and post-assertions complete:

```
✓ Onboarding complete (<greenfield | migration>)
✓ Pre-assertions: in git repo, not previously onboarded, templates available
✓ Post-assertions: intent.md ✓, rules.md ✓, craft-profile.md ✓, settings.local.json ✓, CLAUDE.md ✓[, migration cleanup ✓]

Created:
  .claude/project/intent.md
  .claude/project/rules.md
  .claude/project/craft-profile.md
  .claude/settings.local.json  (created or updated — <scope> read-only allowlist merged, gitignored)
  [.claude/project/roadmap.md]
  [.claude/project/design/<topic>.md …]
  CLAUDE.md

[Migration only]
Moved to _legacy/:
  <N> files
Split source:
  CLAUDE.md → intent.md + rules.md [+ roadmap.md]

<drift line from P5>

Next: run /craft:prime to load context, then /craft:plan to start a slice.
```

Aborted:

```
Onboarding aborted — <reason>. No changes made.
```

Partial (post-assertion failure):

```
⚠ Onboarding partially complete — <which assertion(s) failed>.
   Files written so far are listed above. Inspect and reconcile manually
   before running /craft:prime.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| One or more tools missing | Abort in Pre-flight with install instructions. |
| A1 fails (not a git repo) | Abort with `git init` hint. |
| A2 fails (already onboarded) | Abort with `/craft:prime` / `/craft:intent-update` hint. |
| A3 fails (plugin templates missing) | Abort with plugin-reinstall hint. |
| Heuristic scan finds nothing usable | Fall through to dialogic clarification with default questions; do not silently produce empty drafts. |
| User cancels during inventory report | Clean abort; no file changes. |
| Migration: a target `_legacy/` file already exists with the same name | Append a numeric suffix (`-1`, `-2`) and continue. |
| Drift on final validation | Reported via P5; user revises `rules.md`. No auto-correction. |
| P1/P2/P2b/P2c/P3 fail after write | Warn loudly; emit partial-completion block; do not auto-rollback. |
| P4 fails (migration cleanup incomplete) | Warn loudly; user reconciles `.claude/` manually. |

---

## What This Command Does NOT Do

- It does **not** install missing tools — only checks them.
- It does **not** decide architectural questions for the user. The dialogic clarification asks; the user answers.
- It does **not** delete legacy files. Migration moves them to `_legacy/` for human review.
- It does **not** silently overwrite an existing `intent.md` or `rules.md`. A2 refuses to proceed in that case.
- It does **not** auto-rollback on post-assertion failure. Partial state is surfaced for human reconciliation.
