---
description: One-time project onboarding — bootstraps `.claude/project/` for fresh projects or migrates an existing `.claude/` setup. Detects existing content automatically and switches to migration sub-path.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:onboard — Set Up the Project for the Workflow

## Purpose

Get a project ready for the 8-phase workflow. Two distinct sub-paths share one entry point:

- **Greenfield path** — `.claude/project/` does not exist. Scan the repo, draft project knowledge files dialogically, validate.
- **Migration path** — `.claude/` exists with prior content (commands, agents, skills, CLAUDE.md). Classify each asset, move conflicts to `_legacy/`, split `CLAUDE.md` into `intent.md` / `rules.md` / `roadmap.md`.

This command is a **durable-state mutation** and follows the Pre/Post-Assertion pattern documented in `skills/workflow/SKILL.md` (D24). Refer to that skill for the knowledge model (State / Intent / Rules) and `plugin-architecture.md` Decision D20 for the migration classification scheme.

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

The plugin must ship the four templates this command writes from. Confirm `Read`-ability of:

- `${CLAUDE_PLUGIN_ROOT}/templates/intent.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/rules.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/roadmap.md.template`
- `${CLAUDE_PLUGIN_ROOT}/templates/claude-md-index.template`

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

### 4. Write project files

Generate using the plugin templates:

- `.claude/project/intent.md`
- `.claude/project/rules.md`
- `.claude/project/roadmap.md` (only if user provided roadmap content)
- `CLAUDE.md` in repo root — slim index pointing to the above

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

For each asset in the **Plugin-already-provides** class, ask explicitly:

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
                           [.claude/project/roadmap.md]
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
- **Architectural Decisions** → `intent.md` (auto-import)
- **Code Conventions / Patterns** → `rules.md` (auto-import)
- **Tabus / Anti-Patterns** → `rules.md` (auto-import)
- **Deployment** → `rules.md` (auto-import)
- **Phase Plans / Roadmap** → `roadmap.md` (auto-import)
- **Common Commands** → `CLAUDE.md` index (under `## Common Commands`)
- **Notes / Working Notes / freeform** → **dialogic triage** (see below)
- **Project Structure tree, Key Files table, State references** → **discard** (this is State; lives in code)

##### Notes-section dialog (Gap #5)

If the source contains a "Notes" / "Working Notes" / free-form section that mixes still-relevant decisions with dated working-notes, ask the user to triage **each bullet** one at a time:

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

Present the candidate and let the user decide:

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

## Post-Assertions

Run all four after the chosen procedure completes. Any failure → warn loudly, surface to the user, do **not** pretend success. No auto-rollback.

### P1 — `intent.md` written and well-formed

- `Read` `.claude/project/intent.md`. Must exist and be non-empty.
- Must contain a `## Product Vision` section header.

Failure → *"⚠ intent.md was not written or is malformed. Inspect `.claude/project/intent.md` manually before running /craft:prime."*

### P2 — `rules.md` written and well-formed

- `Read` `.claude/project/rules.md`. Must exist and be non-empty.
- Must contain a `## Stack & Tools` section header.

Failure → *"⚠ rules.md was not written or is malformed. Inspect `.claude/project/rules.md` manually."*

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
✓ Post-assertions: intent.md ✓, rules.md ✓, CLAUDE.md ✓[, migration cleanup ✓]

Created:
  .claude/project/intent.md
  .claude/project/rules.md
  [.claude/project/roadmap.md]
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
| P1/P2/P3 fail after write | Warn loudly; emit partial-completion block; do not auto-rollback. |
| P4 fails (migration cleanup incomplete) | Warn loudly; user reconciles `.claude/` manually. |

---

## What This Command Does NOT Do

- It does **not** install missing tools — only checks them.
- It does **not** decide architectural questions for the user. The dialogic clarification asks; the user answers.
- It does **not** delete legacy files. Migration moves them to `_legacy/` for human review.
- It does **not** silently overwrite an existing `intent.md` or `rules.md`. A2 refuses to proceed in that case.
- It does **not** auto-rollback on post-assertion failure. Partial state is surfaced for human reconciliation.
