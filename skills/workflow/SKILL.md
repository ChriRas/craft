---
name: workflow
description: The 8-phase coding loop — the methodological backbone of this plugin. Loaded by every phase command. Defines phase semantics, transition rules, knowledge model, autonomy taxonomy, and the rule-conflict policy. Use whenever a slash command needs to know "what phase am I in and what is allowed here?".
---

# Workflow — The 8-Phase Coding Loop

This skill is the operational specification of the plugin's universal coding workflow. Every phase command (`/craft:brainstorm`, `/craft:grill-me`, `/craft:plan`, `/craft:execute`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:commit`) reads this skill to know what it owes the user and what it is allowed to do.

The workflow is **language- and stack-independent**. The same eight phases apply whether you are writing a shell script, a Python library, a Rust CLI, a Laravel monolith, or a Terraform module.

---

## Core Principle

> **Universality with constant control.** Same workflow, same control surface, regardless of stack.

Two failure modes the loop is designed to prevent:

1. **The unstructured-agent failure**: agent runs free, refactors things that worked, drifts into the context-window dumb zone, loses product direction after ~5 iterations.
2. **The waterfall-with-AI failure**: agent over-plans a feature it doesn't understand yet; the product-feel only emerges through iterations the plan can't predict.

The 8-phase loop solves both by keeping each iteration short, end-to-end testable, and disciplined about what knowledge persists between iterations.

---

## The Eight Phases

| # | Phase | Default Autonomy | Owns | Produces |
|---|---|---|---|---|
| 1 | **Brainstorm** | Level 0 | Idea exploration before code | A short Markdown checkpoint of explored ideas |
| 2 | **Alignment** | Level 0 | Shared understanding (human ↔ agent, or human ↔ team) | A short Markdown checkpoint of decisions and constraints |
| 3 | **Planning** | Level 1 | Vertical-slice plan with test strategy | `.claude/craft:plans/slice-NNN-<slug>.md` |
| 4 | **Implementation** | Level 2 | Code that satisfies the slice | Code changes, green automated tests |
| 5 | **Testing & UX feedback** | Level 1 | Human hands-on verification | Confirmation or bug/UX-issue feedback |
| 6 | **Recap** | Level 1 | Explanation of what was built and why | Slice archive entry draft |
| 7 | **Refactoring** | Level 1 | Small structural improvements | Cleaner code, same green tests |
| 8 | **Commit & Cleanup** | Level 1 | Atomic commits + slice archive promotion + plan deletion | Commits, slice archive entry, deleted plan file |

After Phase 8, the loop returns to Phase 3 for the next slice. Phases 1 and 2 are typically only run at project start or when entering a major new domain — not every slice.

---

### Phase 1 — Brainstorm

**Purpose:** Use the agent as a sparring partner to explore the problem space *before* code exists.

**Mechanics:** Use the `brainstorm` skill. Pick or have the agent suggest a structured ideation technique (Question Storming, SCAMPER, First Principles, …). Stay divergent before converging.

**Output:** A Markdown checkpoint summarizing explored ideas. After the checkpoint is written, **reset the context** before moving to Phase 2 (or skip if the brainstorm already produced a clear path).

---

### Phase 2 — Alignment

**Purpose:** Build shared understanding. Anything not said explicitly gets invented by the agent — Alignment is where that gap is closed.

**Mechanics:** Use the `grill-me` skill. The agent interviews the user, resolving each branch of the decision tree before any plan is drafted.

**Output:** A Markdown checkpoint of the agreed direction, constraints, and acceptance criteria. **Reset context** afterwards.

---

### Phase 3 — Planning (Vertical Slicing)

**Purpose:** Break the work into a vertical slice — the smallest code change that realizes a complete use-case path from external trigger to observable effect, end-to-end testable.

#### The three universal questions

Every Phase-3 planning session must answer these dialogically. Do not let the user skip them.

1. **What is the trigger?** (User click, CLI invocation, API call, event, file drop)
2. **What is the observable effect?** (UI update, stdout, response, state change, output file)
3. **How do we test it end-to-end?** (Test strategy is committed *before* Phase 4 begins, so the slice has a definition of done.)

#### Slice properties

A valid vertical slice satisfies:

- End-to-end testable (test runs from outermost entry gate to outermost exit gate).
- Standalone-experienceable (delivers clear new caller-value).
- Minimal (no speculative scaffolding for "the day after tomorrow").
- Self-contained (could be merged without anything else waiting).

#### Granularity note

In single-developer agent-coding, slices are **feature-shaped**, not component-shaped. A REST endpoint plus its UI binding is one slice if a single end-to-end test simulates the outermost user action. Team development would split them; we don't.

#### Output

`.claude/craft:plans/slice-NNN-<slug>.md` using the slice plan template. Includes the plugin version in the frontmatter for later mid-slice update safety.

---

### Phase 4 — Implementation

**Purpose:** Realize the plan in code.

**Mechanics:**
- New chat, fresh context (the plan is read into the fresh context).
- Agent loads any project-local specialist skills relevant to the stack (e.g., `developer` skill for PHP/Laravel).
- Sub-tasks from the plan are executed in order.
- Tests run silently (Level 3) and surface only on red.
- Bundles surface at the end of each sub-task or at the 30k-token brake, whichever comes first.

**Context discipline:** Keep the implementation session under ~100k tokens. If the slice is too big for one session, that is a signal that the slice was too big for Phase 3 — re-slice next time.

---

### Phase 5 — Testing & UX Feedback

**Purpose:** Human-in-the-loop verification. The agent has no product-feel; this is the only phase where the human actually exercises the artifact.

#### Sub-steps

| Step | Autonomy | Description |
|---|---|---|
| **5a Demo-Setup** | Level 1 | Agent prepares hands-on instructions derived from the slice's recorded trigger: starts the server, prints the URL/command, lists "try this" steps. |
| **5b User-Exercise** | (Human) | User exercises the artifact. No agent intervention. |
| **5c Feedback-Capture** | Level 0 | Agent asks structured: `[W]orks → Phase 6 / [B]ug → trigger /craft:debug / [U]X issue → iterate` |

#### UX issue handling

When the user reports `[U]`, the agent asks **directly** ("What exactly should be different?"). It never interprets autonomously — that is the largest pitfall in agent-driven UX work.

#### Bug discovery in Phase 5

Reporting `[B]` triggers `/craft:debug` automatically. The agent says: "User reported bug — entering `/craft:debug` mode for verification protocol." The slice plan is appended with the bug description and the verification protocol negotiated next.

#### Phase 5 cannot be skipped

Even if automated tests in Phase 4 are green, Phase 5 must run. This is constitutive for "human keeps product-feel control."

---

### Phase 6 — Recap

**Purpose:** Force the user to retain mental ownership of the artifact. Without this, after five iterations the user has handed product decisions to the agent silently.

**Mechanics:** Agent answers, dialogically:
- "How does what we built work?"
- "Walk me through the flow from trigger to effect."
- For complex slices (>3 modules or files touched), agent offers to produce a Mermaid diagram. User decides.

**Output:** A draft of the slice archive entry (will be finalized in Phase 8). Plain-text What/Why/Decisions by default; diagram only on confirmation.

---

### Phase 7 — Refactoring

**Purpose:** Small, immediate structural improvements. Do not defer — refactoring later means the next slice builds on a worse foundation.

**Mechanics:** Agent asks the three Thorstensen prompts dialogically:

1. "What is the smallest step that would make this codebase better?"
2. "Could a new developer follow the flow without mental leaps?"
3. "Which refactor preserves behavior but improves structure?"

**Discipline:** Maximum **2–3 refactor items per slice**. A larger refactor is its own slice — opens after the current slice closes.

**Test impact:** If refactor breaks tests, the test fixes belong to the same slice.

---

### Phase 8 — Commit & Cleanup

**Purpose:** Atomic commits, harvested knowledge, ephemeral artifacts deleted.

#### Sub-steps

1. **Atomic commit split** — agent maps sub-tasks to commits and proposes the split (Level 1, user confirms).
2. **Commit messages** — Conventional Commits + `Slice:` footer (see [Commit Convention](#commit-convention) below).
3. **Decisions promotion dialog** — agent walks each item in the plan's "Decisions Made During This Slice" section. Per item:
   - `[K]eep in archive` (default for skipped items)
   - `[I]ntent` (promote to `.claude/project/intent.md` — human confirms diff)
   - `[R]ules` (promote to `.claude/project/rules.md` — human confirms diff)
   - `[D]iscard`
4. **Slice archive entry** — agent writes `.claude/project/slices/slice-NNN-<slug>.md` from the Phase 6 recap draft and the harvested decisions.
5. **Plan deletion** — `.claude/craft:plans/slice-NNN-<slug>.md` is deleted. The slice archive plus commit history is the durable record.

#### Commit convention

```
<type>(<scope>): <imperative description>

<optional body — what and why, not how>

Slice: slice-NNN
```

- `type` ∈ `feat | fix | refactor | test | docs | chore | perf | build | ci`
- `scope` optional (e.g. `pwa`, `api`, `admin`)
- `Slice:` footer always present when working in a slice
- No separate `Phase:` footer — `type` already signals phase (`refactor` ≈ Phase 7, `test` ≈ Phase 5, `feat`/`fix` ≈ Phase 4)

**Enforcement:** Recommendation only, not blocking. Real development is non-linear; the agent suggests a corrected message but never blocks the commit on style.

---

## Knowledge Model

Three layers, distinct sources of truth, distinct discipline.

| Layer | Content | Ground truth | Persisted in |
|---|---|---|---|
| **State** | What exists today | Code, git, configs | Not duplicated; read on demand |
| **Intent** | What we want & why | Human-authored | `.claude/project/intent.md` (≤80 lines) |
| **Rules** | Operational distillation | Derived from State + Intent, **materialized** | `.claude/project/rules.md` (≤80 lines) |

Plus three supporting files:

- `.claude/project/roadmap.md` — long-term phases / releases (optional)
- `.claude/project/slices/slice-NNN-<slug>.md` — archived completed slices (Decision Log)
- `.claude/craft:plans/slice-NNN-<slug>.md` — currently active slice plans (ephemeral)

#### Rules discipline

`prime` validates Rules against State on every session start. If a Rule says "tests use Pest" but `composer.json` shows PHPUnit, that drift is **reported** — never silently corrected.

#### Update discipline

For any persistent change to `intent.md` or `rules.md`:

- Agent proposes the diff.
- Human confirms before write.
- Never silently mutated. Phase 8 cleanup may surface promotion candidates but never writes without explicit `[I]` or `[R]` confirmation.

---

## Autonomy Taxonomy

Four levels. Phase defaults are above; action-type overrides apply across phases.

| Level | Name | Behavior |
|---|---|---|
| **0** | Ask-Always | Ask explicitly, wait for "yes" |
| **1** | Propose-Confirm | Propose, wait for confirmation |
| **2** | Auto-Notify | Act, then notify compactly at block boundary — pause/rollback possible |
| **3** | Auto-Silent | Act without interrupting (always summarized in next bundle, never invisible) |

#### Action-type force-overrides

| Action | Forced level | Reason |
|---|---|---|
| File read, grep, lint check, status poll | **3** | Pure information gathering |
| Code edit **inside** plan scope | Phase default (typically 2) | Standard flow |
| Code edit **outside** plan scope | **1** | Plan boundary is a contract |
| Test run / lint run | **3** | Read-only effect |
| `rules.md` / `intent.md` mutation | **0** | Sacred (see update discipline) |
| Git commit | **1** | Meaningful |
| Git push, PR, deploy | **0** | External, irreversible |
| Branch ops (local, non-destructive) | **2** | Recoverable |
| Branch delete, force-push | **0** | Destructive |

#### Bundling

- **Bundle boundary**: end of a sub-task in the active plan.
- **Token brake**: at 30k tokens since the last bundle (15k inside `/craft:debug`), force a bundle even mid-sub-task — Dumb-Zone protection.
- **Phase-end bundle**: every phase transition produces an explicit status check.
- **Auto-continue with abort option** at Level 2 — otherwise Level 2 collapses into Level 1.
- **Level 3 visibility**: every bundle summarizes Level 3 actions in one line ("read 12 files, ran 3 lint checks"). Never invisible.

---

## Rule-Conflict Resolution

When `/craft:prime` reports drift or human/agent disagreement appears during the loop:

| Conflict | Default winner | Action |
|---|---|---|
| State vs. Intent | Intent | Agent builds toward Intent (loop purpose) |
| Rules vs. State | Rules | Agent corrects State autonomously |
| Rules vs. Intent | Rules (default); **override offered to human** | Agent flags, asks |

#### Three-stage rule override

When the human wants to bypass a rule:

| Stage | Scope | Persistence | Example |
|---|---|---|---|
| **1. Bend** | Single exchange | None — forgotten | "Push without lint this once" |
| **2. Override** | **Slice-scoped** | Recorded in slice plan under "Active Rule Overrides"; cleared at Phase 8 cleanup | "During this migration slice, direct main pushes allowed" |
| **3. Repeal** | Permanent | Edit `rules.md` (human confirms) | "We drop Pint in favor of Rector-format" |

Agent never silently bends a rule. When a conflict is detected, the agent presents the three options explicitly and waits.

---

## Self-Verification (Bugs)

When a bug is reported (Phase 5 `[B]`) or when the agent detects it has made **≥2 fix attempts on the same symptom** during a slice, the agent offers `/craft:debug`. The skill `self-verify` defines the four-step protocol:

1. **ALIGN** (Level 0) — Capture bug: expected vs. actual.
2. **PROTOCOL** (Level 0) — Agree on the verification command + expected result + negative check, before any fix attempt.
3. **AUTONOMOUS LOOP** (Level 2 + 15k-token brake) — Up to **5 attempts**: hypothesize → edit → run protocol → log → next.
4. **ESCALATION** (Level 0) — After 5 failed attempts, full attempt log + suggested options (handoff, recap, re-negotiate protocol).

On success, the agent proposes promoting the ad-hoc verification command to a permanent regression test (user confirms).

For context-poisoned cases unrelated to a specific bug, `/craft:handoff` writes a summary into the slice plan; user starts a fresh chat; the next `/craft:prime` reloads.

---

## Tool Dependencies

The plugin assumes the following tools are installed and current. `/craft:prime` checks them at every session start and **aborts with install instructions** if any are missing.

| Tool | Why |
|---|---|
| **context-mode** | Activated by `/craft:prime` on every session; preserves the dumb-zone discipline. |
| **agent-browser** | Browser automation for Phase 5a demos in web stacks. |
| **git** | Slice tracking, commit history is the durable archive layer. |
| **gh** | PR creation in Phase 8 for hosted repos. |

The plugin cannot declare these as installable dependencies in the Claude Code plugin manifest. Detection and abort happen at `/craft:prime` runtime.

---

## Cross-Slice Memory

After Phase 8 deletes the plan file, the slice's surviving signal lives in three places:

- **Code** — the implementation itself.
- **Commits** — the chronology, with `Slice:` footers for reverse-tracing.
- **Slice archive** — pruned summary at `.claude/project/slices/slice-NNN-<slug>.md`: What / Why / Decisions / Commits, optionally a Mermaid diagram.

The slice archive is the Decision Log, emergent from Phase 6 + 8 — there is no separate decision-log file. Archive contents are by construction non-stale: past-tense facts, original-time justifications, and immutable commit references.

---

## Mid-Phase Abort

If a slice is paused or abandoned mid-phase:

- `/craft:pause` saves state; the plan file remains with its current `Status:` field.
- `/craft:abort <slice>` asks confirmation (Level 0), then deletes the plan file. Aborted slices have no archive value.
- `/craft:prime` detects stale slices (untouched for >N days) and asks: resume or discard.

---

## When Phases 1 and 2 Run

Phases 1 and 2 are **not run every slice**. They are appropriate when:

- A project is brand new (Phase 1 = product brainstorm; Phase 2 = alignment with the human).
- A major new domain opens inside an existing project (e.g., adding a recommendation engine to an e-commerce site).
- A slice plan in Phase 3 reveals fundamental disagreement that planning cannot resolve — kick back to Alignment.

For routine feature slices, the loop starts at Phase 3 and runs through Phase 8.

---

## How Phase Commands Use This Skill

Every `/`-command that drives a phase reads this SKILL.md to know:

- Its phase-default autonomy level.
- The structured outputs it owes (e.g., `/craft:plan` must answer the three universal questions).
- The transition criterion to the next phase.
- The token-brake / bundle rules for its session window.

Commands that span phases (`/craft:debug`, `/craft:handoff`, `/craft:pause`, `/craft:abort`, `/craft:intent-update`, `/craft:status`) use this skill for the knowledge model and autonomy taxonomy, not the phase semantics.

`/craft:onboard` references this skill when generating the initial `rules.md` to inform the user about workflow conventions that apply to their project.
