---
name: workflow
description: The 9-phase coding loop — the methodological backbone of this plugin. Loaded by every phase command. Defines phase semantics, transition rules, knowledge model, autonomy taxonomy, and the rule-conflict policy. Use whenever a slash command needs to know "what phase am I in and what is allowed here?".
---

# Workflow — The 9-Phase Coding Loop

This skill is the operational specification of the plugin's universal coding workflow. Every phase command (`/craft:brainstorm`, `/craft:grill-me`, `/craft:plan`, `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review`, `/craft:commit`) reads this skill to know what it owes the user and what it is allowed to do.

The workflow is **language- and stack-independent**. The same nine phases apply whether you are writing a shell script, a Python library, a Rust CLI, a Laravel monolith, or a Terraform module.

---

## Core Principle

> **Universality with constant control.** Same workflow, same control surface, regardless of stack.

Two failure modes the loop is designed to prevent:

1. **The unstructured-agent failure**: agent runs free, refactors things that worked, drifts into the context-window dumb zone, loses product direction after ~5 iterations.
2. **The waterfall-with-AI failure**: agent over-plans a feature it doesn't understand yet; the product-feel only emerges through iterations the plan can't predict.

The 9-phase loop solves both by keeping each iteration short, end-to-end testable, and disciplined about what knowledge persists between iterations.

---

## The Nine Phases

| # | Phase | Default Autonomy | Owns | Produces |
|---|---|---|---|---|
| 1 | **Brainstorm** | Level 0 | Idea exploration before code | A short Markdown checkpoint of explored ideas |
| 2 | **Alignment** | Level 0 | Shared understanding (human ↔ agent, or human ↔ team) | A short Markdown checkpoint of decisions and constraints |
| 3 | **Planning** | Level 1 | Vertical-slice plan with test strategy | `.claude/plans/slice-NNN-<slug>.md` |
| 4 | **Implementation** | Level 2 | Code that satisfies the slice | Code changes, green automated tests |
| 5 | **Testing & UX feedback** | Level 1 | Human hands-on verification | Confirmation or bug/UX-issue feedback |
| 6 | **Recap** | Level 1 | Explanation of what was built and why | Slice archive entry draft |
| 7 | **Refactoring** | Level 1 | Small structural improvements | Cleaner code, same green tests |
| 8 | **Review** | Level 1 | Independent fresh-eyes review of the slice artifact | Severity-graded findings, bounded in-phase fixes, a Commit gate |
| 9 | **Commit & Cleanup** | Level 1 | Atomic commits + slice archive promotion + plan deletion | Commits, slice archive entry, deleted plan file |

After Phase 9, the loop returns to Phase 3 for the next slice. Phases 1 and 2 are typically only run at project start or when entering a major new domain — not every slice.

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

`.claude/plans/slice-NNN-<slug>.md` using the slice plan template. Includes the plugin version in the frontmatter for later mid-slice update safety.

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

**Output:** A draft of the slice archive entry (will be finalized in Phase 9). Plain-text What/Why/Decisions by default; diagram only on confirmation.

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

### Phase 8 — Review

**Purpose:** An independent, fresh-eyes review of the artifact that will actually be committed. Review sits *after* Refactor deliberately — it reviews the post-refactor delta, the real shipped code. One late review is enough: CRAFT slices are small by design and Phase 7 refactoring is bounded (max 2–3 items), so the post-refactor delta is small. For an unusually large slice the agent **may recommend** an extra ad-hoc `/craft:review` earlier — an opt-in escape hatch, not a phase.

**Fresh-agent invocation:** Review runs as a **subagent with a fresh context window** — the four-eyes principle. Independence comes from the clean window, not from blinding the reviewer. The review agent is loaded with:

- the Senior-Developer baseline (Tier 1) and the project's stack-pack (Tier 2 — review is code-near work, like Execute/Refactor);
- the slice's task / intent and plan;
- all prior project decisions (to catch silent revocation of an earlier decision);
- the final code / diff under review;
- the **Phase-6 Recap** as the developer's "thinking trace" — a what/why summary, mirroring a human PR description, not the raw Execute logs;
- the findings rubric below.

**Findings rubric — two orthogonal axes:**

- **Severity** — must this be resolved before Commit?
  - *Heavy*: architecture violation, security issue, a test that passes but is task-wise wrong, silent revocation of a prior decision.
  - *Light*: code style, a small missing test case, cosmetics.
- **Fix-nature** — where is it resolved?
  - *Local edit*: a paged-in developer could finish it in ~half an hour. → fixed **in Phase 8**.
  - *Needs rethinking*: genuinely wrong; the original developer must reconsider it. → **escalated**, never fixed in Phase 8.

| | Local edit (in-phase) | Needs rethinking (escalated) |
|---|---|---|
| **Heavy** | review agent fixes in Phase 8 | escalated — **blocks Commit** |
| **Light** | review agent fixes in Phase 8 | recorded as a **follow-up**; Commit proceeds |

**Soft volume cap:** once in-phase fixes exceed **N** (default 5; `Review in-phase fix cap` in `rules.md` `## Self-Verification Settings`), the agent stops and **recommends** escalating the whole batch rather than fixing it. Soft = a recommendation, not a hard block.

**Escalation:** a Heavy + needs-rethinking finding is never auto-fixed. The agent **recommends** (Level 1), per finding, one of two routes — loop back to Phase 4 (`/craft:build`) if the fix is in slice scope, or spin off a new slice (`/craft:plan`) if it is separate work. Phase 9 (Commit) is blocked until every Heavy + needs-rethinking finding is resolved.

**Findings record:** all findings are written to the slice plan's `## Review Findings` section — an audit trail, format `Severity · Fix-nature · description · resolution`.

**Autonomy profile:** classifying findings — Level 3 (silent analysis, surfaced in the findings bundle); in-phase fixes — Level 2 (act, then bundle); escalation decisions and soft-cap breach — Level 1 (recommend, human decides).

**Ad-hoc mode:** `/craft:review` is slash-invocable at any time. Invoked *before* Phase 8 it is **advisory only** — it produces findings, fixes nothing, and changes no phase state; the developer folds the findings into ongoing work.

**Output:** severity-graded findings in `## Review Findings`, bounded in-phase fixes applied, and Phase 9 either gated (a Heavy + needs-rethinking finding is open) or cleared.

---

### Phase 9 — Commit & Cleanup

**Purpose:** Atomic commits, harvested knowledge, ephemeral artifacts deleted.

#### Sub-steps

1. **Atomic commit split** — agent maps sub-tasks to commits and proposes the split (Level 1, user confirms).
2. **Commit messages** — Conventional Commits + `Slice:` footer (see [Commit Convention](#commit-convention) below).
3. **Decisions promotion dialog** — agent walks each item in the plan's "Decisions Made During This Slice" section. Per item:
   - `[K]eep in archive` (default for skipped items)
   - `[I]ntent` (promote to `.claude/project/intent.md` — human confirms diff)
   - `[R]ules` (promote to `.claude/project/rules.md` — human confirms diff)
   - `[D]iscard`
4. **Slice archive entry** — agent writes `.claude/project/slices/slice-NNN-<slug>.md` from the Phase 6 recap draft and the harvested decisions; any Phase-8 light / needs-rethinking findings are folded in under `## Follow-ups`.
5. **Plan deletion** — `.claude/plans/slice-NNN-<slug>.md` is deleted. The slice archive plus commit history is the durable record.

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

Plus supporting files:

- `.claude/project/roadmap.md` — long-term phases / releases (optional)
- `.claude/project/design/*.md` — cross-cutting design knowledge (domain model, scenario
  catalog, matrices); on-demand reference, **not** loaded on `/craft:prime` (see Durable
  Capture below)
- `.claude/project/slices/slice-NNN-<slug>.md` — archived completed slices (Decision Log)
- `.claude/plans/slice-NNN-<slug>.md` — currently active slice plans (ephemeral)

### Durable Capture

An agent's context is **ephemeral** — it is wiped on `/clear`, on compaction, and at
session end. Therefore any analysis, decision, scenario, domain model, or proposal of
lasting value produced during planning, brainstorm, or design **must be written to a
durable artifact in the same turn it is produced**.

> **Chat is not storage.**

Route each kind of lasting output to its home:

| Lasting output | Durable home |
|---|---|
| Why we want it | `.claude/project/intent.md` |
| How we build it | `.claude/project/rules.md` |
| Long-term phases / releases | `.claude/project/roadmap.md` |
| Per-slice decisions | slice archive (`.claude/project/slices/`) |
| Per-epic decisions | epic plan's `## Decisions Made During This Epic` |
| Cross-cutting design knowledge (domain model, scenario catalog, matrices) | `.claude/project/design/` |

The last row is the catch-all for design knowledge that is neither *why* (Intent) nor
*how* (Rules) and spans more than one slice or epic. These docs are reference material —
loaded **on demand**, not on every `/craft:prime` like the core trio — so the directory
can hold as many focused documents as the project needs (`domain-model.md`,
`scenario-catalog.md`, an email-handling matrix, …) without inflating session context.

**Worked example.** In a planning session a full scenario catalog and an email-handling
matrix were worked out in chat but never written to any file. They would have been lost
on the next `/clear`. Under Durable Capture they are written to `.claude/project/design/`
in the same turn they are produced — before the planning turn ends. The planning
commands enforce this (see `/craft:plan` and `/craft:epic`): **a planning turn never ends
leaving material insight only in chat.**

#### Rules discipline

`prime` validates Rules against State on every session start. If a Rule says "tests use Pest" but `composer.json` shows PHPUnit, that drift is **reported** — never silently corrected.

#### Update discipline

For any persistent change to `intent.md` or `rules.md`:

- Agent proposes the diff.
- Human confirms before write.
- Never silently mutated. Phase 9 cleanup may surface promotion candidates but never writes without explicit `[I]` or `[R]` confirmation.

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

#### Lettered-choice prompts

Several commands offer the user a lettered-choice menu — `[W]/[B]/[U]` (Phase 5 feedback), `[K]/[I]/[R]/[D]` (Phase 9 decision promotion), `[P]/[U]/[D]` (onboard migration), and others. Whenever such a menu is presented, render it **in full**: every option as its letter **plus its meaning plus its consequence / next-step**, on **every** occurrence — not just the first. The user may answer with the bare letter, but the agent always shows the full legend. Never present bare letters and rely on the user recalling what they mean.

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
| **2. Override** | **Slice-scoped** | Recorded in slice plan under "Active Rule Overrides"; cleared at Phase 9 cleanup | "During this migration slice, direct main pushes allowed" |
| **3. Repeal** | Permanent | Edit `rules.md` (human confirms) | "We drop Pint in favor of Rector-format" |

Agent never silently bends a rule. When a conflict is detected, the agent presents the three options explicitly and waits.

---

## Self-Verification (Bugs)

When a bug is reported (Phase 5 `[B]`) or when the agent detects it has made **≥2 fix attempts on the same symptom** during a slice, the agent offers `/craft:debug`. The skill `debug` (slash-invocable as `/craft:debug`) defines the four-step protocol:

1. **ALIGN** (Level 0) — Capture bug: expected vs. actual.
2. **PROTOCOL** (Level 0) — Agree on the verification command + expected result + negative check, before any fix attempt.
3. **AUTONOMOUS LOOP** (Level 2 + 15k-token brake) — Up to **5 attempts**: hypothesize → edit → run protocol → log → next.
4. **ESCALATION** (Level 0) — After 5 failed attempts, full attempt log + suggested options (handoff, recap, re-negotiate protocol).

On success, the agent proposes promoting the ad-hoc verification command to a permanent regression test (user confirms).

For context-poisoned cases unrelated to a specific bug, `/craft:handoff` writes a summary into the slice plan; user starts a fresh chat; the next `/craft:prime` reloads.

---

## Pre/Post-Assertions (Durable-State Commands)

Commands that mutate durable state outside the running session (filesystem files Claude Code reads on the next start, git history, plugin registry, project knowledge) follow a structured **Pre/Post-Assertion** pattern. The pattern is the structural backbone of `feedback-human-control` — silent drift is forbidden; failures are loud.

### Required commands

The pattern is mandatory for:

- `/craft:onboard` — creates `.claude/project/intent.md` + `rules.md`.
- `/craft:plan` — creates `.claude/plans/slice-NNN-<slug>.md`.
- `/craft:commit` — git commit + plan deletion + slice archive write.
- `/craft:abort` — plan file deletion.
- `/craft:upgrade` — marketplace clone sync (reference implementation).

### Exempt commands

The pattern is **not** applied to:

- **Read-only commands** (`/craft:status`, `/craft:prime`, `/craft`) — no mutation, no assertions.
- **Phase-execution commands** (`/craft:build`, `/craft:test`, `/craft:refactor`, `/craft:review`) — open-ended code changes; assertions would be ceremonial.
- **Pure-conversation commands** (`/craft:brainstorm`, `/craft:grill-me`, `/craft:debug`) — no filesystem mutation outside the slice plan body itself.

Commands with small contained mutations (`/craft:continue`, `/craft:pause`, `/craft:handoff`, `/craft:intent-update`, `/craft:recap`) are currently out of scope. Extending the pattern to them requires a new banked decision.

### Structural shape

Every command in the required scope is organized as:

```
## Pre-flight        (optional — environment/tool discovery)
## Pre-Assertions    (REQUIRED — checks that must hold before any mutation)
   ### A1 — <name>
   <check>
   On failure: <abort message, no mutation occurs>
   ### A2 — ...

## Procedure         (REQUIRED — the actual work, step-numbered)

## Post-Assertions   (REQUIRED — checks that confirm the mutation landed)
   ### P1 — <name>
   <check>
   On failure: <warn loudly, surface to user, do not pretend success>
   ### P2 — ...

## Output Format     (REQUIRED — success / aborted / partial shapes)
## Error Handling    (REQUIRED — situation → behavior table)
```

### Failure semantics

- **Pre-Assertion failure** → stop *before* any mutation. No partial state. The output line names the failed assertion (`A2 — Working tree clean: failed`) so the user can target the fix.
- **Post-Assertion failure** → the mutation already happened. Warn loudly, surface to user, do **not** pretend success. Never auto-rollback; recovery is human-initiated.
- **Never silent.** A skipped assertion (e.g., tool unavailable) emits one informational line, not silence.

### Why

- Aligns with `feedback-human-control`: durable mutations require explicit guardrails in code, not just prompt discipline.
- Aligns with `feedback-recommendation-over-blocking`: strict only at the boundary of durable state changes, not for style.
- Mirrors context-mode's defensive update pattern without adopting its build complexity.
- Creates a testable contract: each assertion is a discrete check that future integration tests can drive against.

### Reference

`commands/upgrade.md` (introduced in v0.2.0) is the canonical example. Decision: D24 in `brainstorm-decisions.md`.

---

## Tool Dependencies

The plugin assumes the following tools are installed and current. `/craft:prime` checks them at every session start and **aborts with install instructions** if any are missing.

| Tool | Why |
|---|---|
| **context-mode** | Activated by `/craft:prime` on every session; preserves the dumb-zone discipline. |
| **agent-browser** | Browser automation for Phase 5a demos in web stacks. |
| **git** | Slice tracking, commit history is the durable archive layer. |
| **gh** | PR creation in Phase 9 for hosted repos. |

The plugin cannot declare these as installable dependencies in the Claude Code plugin manifest. Detection and abort happen at `/craft:prime` runtime.

---

## Session Priming Gate

A CRAFT command is only safe to run once the session is **primed** — project context
(intent / rules / Senior-Developer baseline) is loaded **and** the four required tools
are verified. `/craft:prime` does both. To guarantee that no context-dependent command
ever runs on unloaded context or an unverified toolchain, those commands self-protect
with a shared **ensure-primed gate** in their pre-flight.

### Session marker

`/craft:prime` writes an empty sentinel `.claude/plans/.primed` on successful
completion. The SessionStart hook (`hooks/session-start.sh`) deletes it at the start of
every session, so the marker is **per-session**: present only after prime has run in the
current session, and correctly cleared after `/clear` (context is genuinely wiped then,
so re-priming is the right behavior). The marker is ephemeral session state — gitignored,
never committed. Its path is exactly `.claude/plans/.primed` everywhere it appears.

### Command classification

| Class | Needs priming? | Commands |
|---|---|---|
| **Context-free** | No — safe on unloaded context | `prime`, `onboard`, `upgrade`, the `craft` entry skill, the Phase 1/2 ideation commands `brainstorm` / `grill-me`, and the lightweight standalone read-only / single-file / maintenance commands `status`, `worktree-status`, `worktree-clean`, `checkout`, `pause`, `handoff`, `abort` |
| **Context-dependent** | Yes — gated | the 9-phase commands `build`, `test`, `recap`, `refactor`, `review`, `commit`; the planning commands `plan`, `epic`; the execution command `execute`; the flow-resumption commands `continue`, `release`; the blocked-state commands `block`, `unblock`; the `debug` skill; and `intent-update` |

What unites the context-free set is that **none needs the project's loaded context**
(intent / rules / baseline) to do its job correctly: they either *are* prime, bootstrap
the project (`onboard`), or are quick read-only / single-file / worktree-maintenance
operations — including durable-state maintenance like `worktree-clean`, which self-checks
onboarding in its own Pre-Assertions — where forcing a full prime would cost more than it
protects. The Phase 1/2 ideation commands `brainstorm` and `grill-me` are context-free
too: they precede both code and the plan, run divergently as a sparring partner, and
`brainstorm` in particular may open a **green-field, pre-onboarding** session — where
`/craft:prime` (which requires onboarding) could not run anyway, so gating them would
block a legitimate entry point. Context-dependent commands touch code, plans, or project
knowledge and assume loaded context — they carry the gate.

### The ensure-primed gate (sub-procedure)

Every context-dependent command runs this as the first step of its pre-flight:

1. **Check** — does `.claude/plans/.primed` exist?
2. **Absent** → emit the notice *"Session not primed — running /craft:prime first"*,
   run `/craft:prime` (which loads context, verifies the four tools — aborting with the
   loud ⚠ + repair hint if any is missing — and writes the marker), then continue with
   the original command.
3. **Present** → silent no-op; continue immediately.

The gate never duplicates the tool-availability check — it inherits it by routing
through `/craft:prime`. If prime aborts (a required tool is missing, or the project is
not onboarded), the gated command does not run either.

### Under `/craft:execute` (worktree execution)

`/craft:execute` runs Phases 4–8 inside `slice-builder` subagents in parallel git
worktrees. Two facts would break the normal marker lifecycle there: the `.primed` marker
is gitignored (absent from a fresh worktree checkout) and **SessionStart hooks do not
fire for `Task` subagents** — so the gate would always read the marker as absent and every
slice-builder would wrongly auto-run `/craft:prime` inside its worktree (redundant at
best; an abort of the autonomous run at worst, if prime's strict tool check cannot reach a
tool from the subagent).

The orchestrator therefore **seeds the marker per worktree**: immediately after
`git worktree add`, `/craft:execute` writes `.claude/plans/.primed` into the new worktree
(see `commands/execute.md` → *Spawn slice-builders*). The context those subagents need is
already guaranteed — the orchestrator primed on `main` and briefs each slice-builder with
`intent.md` / `rules.md` — so the seeded marker is a truthful "this execution context is
primed" signal and the gate is a silent no-op for every slice-builder. In-place execution
mode needs no seed: it builds inline in the already-primed main session.

---

## Cross-Slice Memory

After Phase 9 deletes the plan file, the slice's surviving signal lives in three places:

- **Code** — the implementation itself.
- **Commits** — the chronology, with `Slice:` footers for reverse-tracing.
- **Slice archive** — pruned summary at `.claude/project/slices/slice-NNN-<slug>.md`: What / Why / Decisions / Commits, optionally a Mermaid diagram.

The slice archive is the Decision Log, emergent from Phase 6 + 9 — there is no separate decision-log file. Archive contents are by construction non-stale: past-tense facts, original-time justifications, and immutable commit references.

---

## Mid-Phase Abort

If a slice is paused or abandoned mid-phase:

- `/craft:pause` saves state; the plan file remains with its current `Status:` field.
- `/craft:abort <slice>` asks confirmation (Level 0), then deletes the plan file. Aborted slices have no archive value.
- `/craft:prime` detects stale slices (untouched for >N days) and asks: resume or discard.

---

## Worktree Execution Mode

When `/craft:execute <epic-or-slice>` is used, the 9-phase loop runs across parallel git worktrees. The phase boundaries shift slightly:

| Phase | Runs on | Notes |
|---|---|---|
| 1–2 (Brainstorm, Alignment) | main | Pre-slice; unchanged. |
| 3 (Planning) | main | `/craft:plan` writes the plan file on main. Worktrees are NOT created here. |
| 4 (Implementation) | slice-worktree | `/craft:execute` creates `../<repo>-worktrees/<slice-id>-<slug>/` on branch `<slice-id>-<slug>` from the epic-branch (or `main` for a lone slice). The `slice-builder` subagent runs `/craft:build` here. |
| 5 (Testing) | slice-worktree | Subagent-callable mode of `/craft:test` writes `.craft/handoff.md` and pauses — Phase 5 requires a human and cannot be automated. |
| 6 (Recap) | slice-worktree | Subagent-callable mode of `/craft:recap` auto-drafts the What/Why/Walk-through. Flagged for human review at checkout. |
| 7 (Refactor) | slice-worktree | Subagent-callable mode of `/craft:refactor` skips if `rules.md` declares Phase 7 dropped; otherwise writes handoff candidates without applying. |
| 8 (Review) | slice-worktree | Subagent-callable mode of `/craft:review` applies in-phase fixes automatically; Heavy + needs-rethinking findings and soft-cap breaches write a handoff and pause. |
| 8 → epic-merge | epic-worktree | When a slice clears review, the orchestrator merges its branch into `epic-<NNN>-<slug>` with `--no-ff`. For a lone slice, this step is skipped — the slice-branch stays parked until Phase 9. |
| 9 (Commit) | main | `/craft:commit` runs from main, detects the mode (Standard / Slice-finalize / Epic-finalize), merges with `--no-ff`, walks decisions across every included slice, writes archive entries, deletes plan files, and removes worktrees + branches. |

### Subagent-callable contract

Phase commands `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review` each carry a `## Subagent Mode` section that defines what they do when invoked by the `slice-builder` subagent rather than directly by a human. The orchestrator delegates rather than duplicating phase logic — one canonical implementation per phase, reused.

The contract has two rules:

1. **Never fabricate human judgment.** UX feedback (W/B/U), refactor candidate selection, escalation routing, decision promotions, commit-message edits — all stay human-only. Subagent mode either auto-drafts (Recap) and flags it for review, or writes a handoff marker and pauses (Test/Refactor/Review/Heavy findings).
2. **Always surface state via `.craft/handoff.md`.** The marker file is the universal "human needed" signal. Hooks watch for it; `/craft:execute` collects it; `/craft:checkout` shows it.

### Handoff marker format

`<worktree-root>/.craft/handoff.md`:

```markdown
---
Slice-ID: slice-NNN
Status: awaiting-test | awaiting-refactor-decision | awaiting-rethink-decision | awaiting-protocol | awaiting-block-decision | failure
Phase: 4 | 5 | 6 | 7 | 8
Written: <ISO datetime>
---

# Handoff: <one-line title>

<short paragraph describing what the subagent needs from the human>

## Suggested next action

<one-line — typically a /craft:command the human should run, with the slice or epic ID>
```

The orchestrator's "epic partially complete" output lists every active handoff with the slice-ID, the status, and the one-line title. Most statuses pair with a slice plan at `Status: paused`; the exception is `awaiting-block-decision`, which the subagent pairs with the first-class `Status: blocked` state (frontmatter + `## Blocker`) and which resolves via `/craft:unblock` rather than a plain `/craft:continue`.

---

## When Phases 1 and 2 Run

Phases 1 and 2 are **not run every slice**. They are appropriate when:

- A project is brand new (Phase 1 = product brainstorm; Phase 2 = alignment with the human).
- A major new domain opens inside an existing project (e.g., adding a recommendation engine to an e-commerce site).
- A slice plan in Phase 3 reveals fundamental disagreement that planning cannot resolve — kick back to Alignment.

For routine feature slices, the loop starts at Phase 3 and runs through Phase 9.

---

## How Phase Commands Use This Skill

Every `/`-command that drives a phase reads this SKILL.md to know:

- Its phase-default autonomy level.
- The structured outputs it owes (e.g., `/craft:plan` must answer the three universal questions).
- The transition criterion to the next phase.
- The token-brake / bundle rules for its session window.

Commands that span phases (`/craft:debug`, `/craft:handoff`, `/craft:pause`, `/craft:abort`, `/craft:intent-update`, `/craft:status`) use this skill for the knowledge model and autonomy taxonomy, not the phase semantics.

`/craft:onboard` references this skill when generating the initial `rules.md` to inform the user about workflow conventions that apply to their project.
