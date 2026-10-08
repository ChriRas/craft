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
| 9 | **Commit & Cleanup** | Level 1 | Atomic commits + slice archive promotion + plan closing | Commits, slice archive entry, closed plan file (deleted, or moved into `.claude/plans/.closed/`) |

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

**Context discipline:** Keep the implementation session under ~150k tokens. If the slice is too big for one session, that is a signal that the slice was too big for Phase 3 — re-slice next time.

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
The one opt-in exception is an autopilot run (D32, D35): a helper's pass of the slice's committed checks replaces the
stop, and the human's product-feel check moves to the epic end (`## UX Demo Script`).

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

#### The Phase-7-dropped rule

Phase 7 is the one phase a project may drop wholesale — some codebases (a plugin shipping
Markdown assets, say) rarely accumulate structure worth improving mid-slice. **A project drops
Phase 7 when a bullet in its `rules.md` `## Workflow Rules` section declares Phase 7 (Refactor)
dropped or skipped.** This is the single definition; `/craft:recap`, `/craft:refactor` and
`/craft:execute` resolve the drop against it rather than each carrying their own test.
`/craft:continue` deliberately does **not** consult it — it routes a `review` slice to
`/craft:recap` in *both* configurations, because `review` is an advisory status for
`/craft:review` and routing there directly would leave Commit ungated. Being
config-independent is a property worth stating, not an omission.

The drop **re-routes the phase graph** — it does not merely skip a step:

| | Phase 7 kept (default) | Phase 7 dropped |
|---|---|---|
| Phase 6 (`/craft:recap`) hands to | Phase 7, writing `Status: refactoring` | **Phase 8, writing `Status: reviewing`** |
| `Status: refactoring` is consumed by | `/craft:refactor` | *nothing* — it is an **orphan status** |
| `Status: reviewing` is produced by | `/craft:refactor` | **`/craft:recap`** |
| `/craft:refactor` invoked anyway | runs the Thorstensen prompts | skips cleanly **if the slice is at `review` / `reviewing` / `refactoring`**: records `Phase 7 skipped (project rule)`, sets `Status: reviewing`, routes to `/craft:review`. At any earlier status it must **not** touch the status — a slice at `implementing` / `testing` has not passed the Phase-5 human demo, and Phase 5 cannot be skipped. |

**Why this matters — the actual failure mode.** In a Phase-7-dropped project, the *only* route out
of Phase 6 leads to `/craft:refactor`, a command the project never runs. There is then no good
move: follow the recommendation and the slice sits in a phase that does not exist; decline it and
the slice stays at `Status: review`, which `/craft:review` reads as a pre-Phase-8 status and
answers with **advisory mode** — findings only, no in-phase fixes, Commit never gated. That is
precisely what happened in slice-030, where the status had to be repaired by hand before Phase 8
would engage.

Note what is *not* the mechanism: `refactoring` is **not** an advisory status.
`commands/review.md` lists it among the Phase-8-mode statuses, and rightly so — a slice mid-Phase-7
is review-ready. The damage is done by the dangling hand-off, not by that status value.

**The invariant:** every **marked** status write must have a consumer under the project's active
configuration. `scripts/test-workflow-status-graph.sh` asserts it — see the marker contract below,
which is what makes the assertion real rather than a claim about prose. The qualifier is load-
bearing and stated deliberately: the harness sees markers, not prose, so an *unmarked* write is
invisible to it. Mark every new status write, or the graph goes blind on that one.

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

**Soft volume cap (D41):** **N** (default 5; `Review in-phase fix cap` in `rules.md` `## Self-Verification Settings`) is a **guide value**. Once in-phase fixes reach it while local-edit findings are still open, the agent keeps fixing the small findings (criteria in `/craft:review` → Step 4) up to a hard ceiling of **twice** N fixes per round, in every mode, recording why each extra fix is small; a finding that is not small, or one past the ceiling, is **recommended** for escalation. The rule is defined once, in `/craft:review` → Step 4.

**Escalation:** a Heavy + needs-rethinking finding is never auto-fixed. The agent **recommends** (Level 1), per finding, one of two routes — loop back to Phase 4 (`/craft:build`) if the fix is in slice scope, or spin off a new slice (`/craft:plan`) if it is separate work. Phase 9 (Commit) is blocked until every Heavy + needs-rethinking finding is resolved. The routes are carried out by `/craft:review` itself — **Step 7** (gate, and when a spun-off finding counts as resolved) and **Step 8 (Loop back to Phase 4)**; this skill does not restate them.

**Findings record:** all findings are written to the slice plan's `## Review Findings` section — an audit trail of rounds, one line per finding with an ID and a resolution. The format, the round count and which lines are open are defined once, by `scripts/review-findings-state.sh`, and shown in `/craft:review` → Step 6; a re-review's reviewer receives the earlier rounds and verifies them first (Step 2).

**Round cap and breaker:** a finding is Heavy only with a realistic failure, a slice gets a capped number of Phase-8 rounds, and inside an autopilot run a Heavy + needs-rethinking finding gets one loop-back before the ping-pong breaker blocks the slice — `/craft:review` → Pre-flight step 4, Step 7's cap route and Step 9 (slice-052).

**Autonomy profile:** classifying findings — Level 3 (silent analysis, surfaced in the findings bundle); in-phase fixes — Level 2 (act, then bundle); escalation decisions and escalating a finding that is not small, or past the ceiling — Level 1 (recommend, human decides).

**Ad-hoc mode:** `/craft:review` is slash-invocable at any time. Invoked *before* Phase 8 it is **advisory only** — it produces findings, fixes nothing, and changes no phase state; the developer folds the findings into ongoing work.

**Output:** severity-graded findings in `## Review Findings`, bounded in-phase fixes applied, and Phase 9 either gated (a Heavy + needs-rethinking finding is open), cleared, or the slice looped back to Phase 4 (`/craft:review` Step 8).

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
5. **Plan closing** — `.claude/plans/slice-NNN-<slug>.md` is closed: deleted, or moved into `.claude/plans/.closed/` when the user's settings deny or ask on removing it (D34; `/craft:commit` Step 7). The slice archive plus commit history is the durable record.

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

## Phase Transition Rules

The slice plan's `Status:` is the execution token that moves a slice between phases: one command
**produces** it, another **consumes** it. The table below is the **canonical graph** — the single
source of truth that the phase commands implement.

Keep the table and the commands in lockstep. If you change a `Status:` write in a command, change
the row too; the harness fails when they diverge. The `Config` column is `any` (the row is live in
every project) or `phase7-kept` / `phase7-dropped` (the row is live only under that setting — see
**The Phase-7-dropped rule** above).

### The marker contract

A command is prose, and prose is not checkable: a grep for `` `Status: refactoring` `` cannot tell
the sentence that *prescribes* the write from the one that *forbids* it. The first version of this
harness learned that the hard way — deleting a whole routing branch left it green, because the
status literal survived in a "never write this" sentence. So the affirmative writes and reads are
marked, and **only the markers count**:

- `<!-- craft:writes status=<x> [when=<config>] -->` — placed immediately above the instruction
  that actually writes `Status: <x>`. Optional `when=` scopes it to `phase7-kept` /
  `phase7-dropped`.
- `<!-- craft:reads status=<x> -->` — placed on the pre-flight or routing step that *accepts* a
  slice at `Status: <x>`.

A prohibition carries no marker and therefore proves nothing — which is the point. Three further
rules exist because each was, at some point, the hole a reviewer walked through:

- a `craft:writes` marker must sit **on or within 6 lines above** the `Status: <x>` instruction it
  describes, and markers inside **fenced code blocks are ignored** — a marker parked in an example
  under "What This Command Does NOT Do" once kept a deleted gate green;
- **exactly one** `craft:writes` marker per table row — not "at least one". With two markers on one
  row, either can be deleted and the other covers for it, so the row binds neither;
- a command must not restate another's rule. `/craft:refactor`'s Subagent-Mode section **delegates**
  to the single Phase-7 gate instead of carrying its own copy, and marks that with a
  `<!-- craft:delegates rule=<r> to=<target> -->` token; its autopilot path delegates the Phase-7 end to Step 5
  the same way (`rule=phase7-end to=step-5`). `/craft:review`'s Subagent-Mode section
  does the same for the review loop-back (`rule=loop-back to=step-8`), and `/craft:plan`'s for the plan file
  the autopilot's `slice-planner` writes (`rule=plan-file to=step-7`). The harness asserts the token is present,
  that the delegating section declares no status write of its own — neither a `craft:writes`
  marker nor a `Status: <x>` literal in its prose — **and** that the token's target resolves: the named
  heading exists and carries the rule's write marker. Every token in `commands/` must also have an entry
  in the harness's delegation table, and every entry a token. (The target check binds the marker's
  *location*, not that the section's prose still implements the rule.) Duplication is how B1 survived, and a duplicated
  rule writes nothing the status checks would otherwise see. **What the token does not do:** it
  binds its own presence, not the meaning of the prose beneath it. A section that keeps the token
  and negates the rule in words still passes — the same residual as marker drift, and it is stated
  here because an earlier version of this document claimed the token had closed it. It had not: the
  negation never lived in a phrase's absence, it lives in the prose.

The contract runs **both ways**, and that is what makes the invariant real:

1. every marker in `commands/` must have a matching row in the table, and
2. every table row must have its producer's `craft:writes` and its consumer's `craft:reads` marker.

So a status a command writes but the table forgets is a failure, not a blind spot; and a row whose
command silently lost its write is a failure too. `scripts/test-workflow-status-graph.sh` then
reasons about closure on the table — `/craft:commit` reachable from `/craft:plan`, no live row
handing to a command the configuration disables — and checks the two directions above.

The marker's weakness is honest and worth naming: it can drift from the prose beneath it. Keep it
adjacent to the instruction it describes, so the drift is visible to a reader in one glance.

<!-- craft:transitions -->

| Producer | Status | Consumer | Config |
|---|---|---|---|
| `/craft:plan` | `planning` | `/craft:build` | any |
| `/craft:build` | `implementing` | `/craft:build` | any |
| `/craft:build` | `testing` | `/craft:test` | any |
| `/craft:build` | `paused` | `/craft:continue` | any |
| `/craft:test` | `review` | `/craft:recap` | any |
| `/craft:test` | `paused` | `/craft:continue` | any |
| `/craft:recap` | `refactoring` | `/craft:refactor` | phase7-kept |
| `/craft:recap` | `reviewing` | `/craft:review` | phase7-dropped |
| `/craft:refactor` | `refactoring` | `/craft:refactor` | phase7-kept |
| `/craft:refactor` | `reviewing` | `/craft:review` | phase7-kept |
| `/craft:refactor` | `reviewing` | `/craft:review` | phase7-dropped |
| `/craft:review` | `reviewing` | `/craft:review` | any |
| `/craft:review` | `implementing` | `/craft:build` | any |
| `/craft:review` | `committing` | `/craft:commit` | any |
| `/craft:review` | `blocked` | `/craft:unblock` | any |
| `/craft:execute` | `awaiting-release` | `/craft:release` | any |
| `/craft:release` | `testing` | `/craft:test` | any |
| `/craft:commit` | `awaiting-approval` | `/craft:commit` | any |
| `/craft:block` | `blocked` | `/craft:unblock` | any |
| `/craft:pause` | `paused` | `/craft:continue` | any |
| `/craft:execute` | `paused` | `/craft:continue` | any |

<!-- /craft:transitions -->

Four notes the table cannot carry itself:

- `/craft:refactor` produces `reviewing` under **both** configs, but by **two different routes**,
  so it gets **two rows**: in a Phase-7-keeping project at the end of its refactor items
  (`when=phase7-kept`), and in a Phase-7-dropped project via the skip gate (`when=phase7-dropped`).
  They must stay separate: with a single `any` row, either marker alone satisfied it, and the skip
  gate could be deleted *together with its marker* while the harness stayed green — the guard would
  bind the file, not the fix.
- Some commands **produce the status they also consume** (`/craft:build` → `implementing`,
  `/craft:refactor` → `refactoring`, `/craft:review` → `reviewing`): they normalize a slice that
  arrives one step early. Those are real rows, not artifacts.
- `/craft:review` → `implementing` is the **review loop-back** (roadmap B3), the one edge that runs
  *backwards*. It is written only by `/craft:review` **Step 8 (Loop back to Phase 4)**, which defines
  when it fires and what it records; `/craft:build` consumes it through the `implementing` read it
  already has.
- `committed` has **no row**, and that is correct: no command ever writes it. `/craft:commit`
  closes the plan file instead (deleted, or moved into `.claude/plans/.closed/`, D34) — the archive and the git history
  are the record. It survives in
  the plan template and in a few abort checks as a legacy value.

**Not in this graph** — five legitimate exclusions, all unmarked and unrowed on purpose. (There
was briefly a sixth, and it was *not* on purpose: `/craft:refactor`'s Subagent-Mode section
restated the Phase-7-dropped rule and wrote `reviewing` a second time, unmarked and unrowed. It is
gone — the subagent section now delegates to the one gate via a `craft:delegates` token, and the
harness asserts the token's presence and that the section carries no status write of its own.)

- the `.craft/handoff.md` statuses (`awaiting-test`, `awaiting-protocol`, `awaiting-scope-decision`,
  `awaiting-block-decision`, `awaiting-rethink-decision`, `awaiting-refactor-decision`, `failure`)
  — they live in the worktree handoff file, not in a slice plan, and are a separate namespace;
- `/craft:unblock`'s restore-write — it writes back the *recorded* `Blocked-status`, a variable, not
  a fixed value, so it has no single edge to declare;
- `/craft:continue`'s resume (step 4a, also run by `/craft:build` on a `paused` plan) — it writes back the
  *recorded* `Paused-status`, a variable, so it has no single edge to declare;
- `slice-builder`'s failure-retry restore (step 0) — it writes 4a's restore of the recorded `Paused-status`, or, for a
  plan without a usable record, the entry status of the phase in the `failure` marker's `Phase:` (a variable over five
  values), and only over `paused` (the status its own Failure handling set) — never over a status set since the failure;
- `/craft:epic`'s `Status: planning` — that is written into an **epic** plan, a different artifact
  with its own lifecycle.

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

#### Choice prompts (the lettered-choice-prompt convention)

Several commands ask the human to choose — a lettered menu such as `[W]/[B]/[U]` (Phase 5 feedback), `[K]/[I]/[R]/[D]`
(Phase 9 decision promotion) or `[P]/[U]/[D]` (onboard migration), a yes/no confirmation, or an open question with
typical answers (D40). This is the one rule for all of them. A command names its options once, in its own legend, and at
each human-choice site carries **one marked sentence**: on a line marked `<!-- craft:choice -->` it names `AskUserQuestion`
together with the no-click fallback ("where the tool is not available, the full legend as text"). Human test T2 showed why
the sentence cannot be a pointer: no session ever read this section, so the sites that only pointed here never clicked.
That sentence is the one deliberate copy — an agent that needs it is by definition one that did not read this file — and
`scripts/test-choice-prompts.sh` binds it (the marker, the tool name on the same line, the declared site count per file,
the sequence sites as `<!-- craft:choice sequence -->`, and the cache-guard stops below as `<!-- craft:choice typed -->`). The full rule stays here: the limits,
splitting, follow-ups, the fallback and the cache-guard exception. A site sentence may add its own option list; it restates no
rule.

**Where the legend lives.** A command writes its menu as a legend: each letter, **its meaning and its consequence /
next step**. That legend is the single source of the options for both renderings below.

**Interactive session — a click.** If the `AskUserQuestion` tool is available, ask the question with it instead of
printing a menu to type into:

- **Lettered menu** → one question; one option per letter (label: the letter and its meaning; description: the
  consequence / next step). The answer is the chosen option — never ask the user to type a letter.
- **Yes/no confirmation** ("Proceed?", "Is that right?") → a two-option question, the default option first. A
  destructive step names what it removes and that it cannot be undone in the question text.
- **Open question with typical answers** (a trigger category, a language, a slice name derived from the context) →
  offer context-derived suggestions as the options; the automatic "Other" takes the user's own text. A question with no
  meaningful presets (a Vision, a bug description) stays typed.
- **The tool's limits** — 2–4 options per question plus the automatic "Other", up to four questions per call. A menu of
  more than four options is split into steps (or grouped, the group picked first) and nothing is dropped; an option
  that needs a parameter (`[R] <ids> — <note>`, "Other language") asks for it in a follow-up question after the click.
- **Dependent questions are asked one call at a time** (D40, slice-077). A question that depends on an earlier answer, or
  whose point is lost when the earlier one is No (a confirmation chain such as `/craft:abort`'s), is asked in an
  `AskUserQuestion` call of its own, the next one only after the answer; a No ends the chain before any further question.
  Only independent questions share a call. A site that is such a chain carries `<!-- craft:choice sequence -->` and the
  phrase ``in an `AskUserQuestion` call of its own`` on that line, bound by `scripts/test-choice-prompts.sh`.
- **A vague answer to a menu** (text under "Other" that picks no option — "kind of works, but…") is not interpreted: ask
  the question again.

**A stop that arms the autopilot cache guard stays text.** Every question asked at a stop that arms the guard — the
orphan question, the plan gate, the a5 sign-off, and any question a run stops to ask (`commands/execute.md` → *The cache
guard*) — ends the turn so that the human's answer arrives as the next **prompt**: the `UserPromptSubmit` hook
`hooks/cache-guard.sh` blocks a prompt that comes after the prompt cache expired, and a click is a tool result the hook
never sees (and `AskUserQuestion` after the arm would be the tool call after the arm that lets the answer pass
unguarded). Those questions are rendered as text with their full legend, as below, and answered by typing; every question
at a stop that does not arm the guard, in an autopilot run too, is a click.

**No human can click — the legend is rendered.** In Subagent Mode (`AskUserQuestion` is not available to a subagent; the
command's own Subagent Mode writes a handoff instead of asking), in a headless `claude -p` session, or whenever the tool
is not available, render the legend **in full** as text: every option as its letter plus its meaning plus its
consequence / next step, on **every** occurrence — not just the first. The user may answer with the bare letter, but the
agent always shows the full legend. Never present bare letters and rely on the user recalling what they mean.


#### Auto flow (the Slice Flow rule, D42)

<!-- craft:flow-rule -->
With the profile's `## Slice Flow` → `Mode: auto` (the plugin default; the `careful` preset ships `manual`) an
interactive slice moves from phase to phase **by itself**, up to and including the commit, instead of waiting for the
human to type each phase command — the human decisions inside the phases are what need the human, and they stay human.
This is the one definition; the phase commands point here from the closing section marked `<!-- craft:flow -->` and
carry no second copy.

**Where it applies.** At the end of an interactive `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`,
`/craft:review` and `/craft:commit`, and after `/craft:plan` (below). Never in **Subagent Mode**, never inside
`/craft:execute` or an autopilot run (they orchestrate the phases themselves), and never where no human can click (a
headless `claude -p` session): there each command ends as it always did.

**The verdict comes from one helper, never from judgment.** At the end of the command, after its normal closing output:

1. Take the `--from` value: the plan's `Status:` at the moment the command's **own work** began — *after* its Pre-flight
   status write, not the status it found (a build that found `planning` has already written `implementing`; passing
   `planning` would let a build that stopped early start itself again). One value per command:

   | Command | `--from` |
   |---|---|
   | `/craft:build` | `implementing` |
   | `/craft:test` | `testing` |
   | `/craft:recap` | the status it found (`review`, or `testing` right after Phase 5) |
   | `/craft:refactor` | `refactoring`; with Phase 7 dropped none (its skip gate always advances to `reviewing` and must chain) |
   | `/craft:review` | `reviewing`, in Phase-8 mode only — an **advisory** review changes no status and never chains |
   | `/craft:plan`, `/craft:commit` | none (the plan click; the flow ends) |

   A command that **refused in its Pre-flight** (no slice, a wrong status, a paused or blocked slice) did no work and wrote
   no status: it runs **no** Auto flow step at all — its refusal message stands. Passing the table's value then would
   start another phase on a slice the user only mistyped a command for.
2. Run `bash "<plugin-root>/scripts/flow-state.sh" --project "<project-root>" --from <that status> "<slice plan>"` —
   `<plugin-root>` is the resolved `${CLAUDE_PLUGIN_ROOT}` the phase command hands over (a skill read as a file is not
   substituted); in CRAFT's own source repo `scripts/flow-state.sh` of the working tree. It reads the profile's mode and the plan's
   `Status:` and prints `MODE=`, `STATUS=`, any `WARN=` lines and **exactly one** of `NEXT=` or `STOP=`.
3. **`NEXT=/craft:<phase>`** → say `Auto flow → /craft:<phase>` and start that phase yourself, the way the user's typed
   command would run it — its Pre-flight, its procedure, its human decisions as clicks (use the `Skill` tool where the
   session offers it; else read the command's file and follow it). That phase ends with this same step.
4. **`STOP=<reason>`** → do not start anything. `STOP=manual` is silent (the pause word is the exception to "`manual` = before D42": a live request prints `STOP=pause-requested` in manual mode too): the command ends with its own `Recommended
   next:` as before. Any other reason is named in one line, `Auto flow stops: <reason> — <what that means>`, above the
   command's own `Recommended next:`: `committed` — the slice is done, the flow ends here; `blocked`, `paused`,
   `awaiting-release`, `awaiting-approval` — a human holds the slice (`/craft:unblock`, `/craft:continue`,
   `/craft:release`, `/craft:commit`); `pause-requested` — you sent the pause word (in either mode), run the pause action (*The pause
   request* below) instead of the generic line; `no-progress` — the phase ended in the status it began in, so it is waiting for
   you (a gated review, a `[U]` iteration, a pause) — say what it waits for; `invalid-mode` — the profile's value is
   neither `auto` nor `manual` (`/craft:prime` warns); `no-plan`, `unknown-status` — the plan cannot be read; any reason
   this rule does not list — name it and stop.
5. **Any `STOP=` settles a pending pause request** (*The pause request*, rule 4) — run `pause-request.sh consume` after
   naming it, so a request the flow never read cannot pause the next slice of this session.
6. Relay every `WARN=` line as `⚠ <text>`. **Doubt means stop**: the helper missing, failing, or printing no `NEXT=` /
   `STOP=` line is a stop — say `Auto flow stops: flow check incomplete — <one-line cause>`. (Unlike the handoff marker,
   where doubt means live: a wrong automatic phase start costs more than a halt.)

**Human decisions stay human.** The flow answers nothing for the human: Phase 5's `[W]/[B]/[U]` (and the exercise before
it), a review escalation or cap route, the decision walk of Phase 9 and the commit-message confirmation are asked as
clicks (*Choice prompts* above) and the flow goes on right after the answer. A phase's own stops are unchanged — a
Pre-flight refusal runs no Auto flow step (step 1), and a gated review, a pause or a `/craft:debug` detour leaves the
status where the work began, which the helper sees as no progress.

**The flow ends after `/craft:commit`.** Its closing section calls no helper: the slice is closed, nothing follows but the
command's own `Recommended next:`.

**After `/craft:plan`.** With `Mode: auto`, plan ends by asking one click, **Build now** / **Later** (several slices can
still be planned ahead); *Build now* runs steps 2–3 with the new plan (no `--from`) and so starts `/craft:build`, *Later*
ends with the output's own `Next: /craft:build` line as before. The click follows only a successful closing output (not
a partial write). With `manual` it asks nothing.

**Manual.** `Mode: manual` is exactly the behavior before D42: one command per phase, each ending with `Recommended
next:` — except the pause word, which works in manual flow as in auto flow (*The pause request*).

**The pause request (slice-075; both modes since slice-077).** The human pauses a slice in flight — in auto flow and in
`Mode: manual` alike (D42 amendment, decision `[G]`) — by sending a message that is **only** `pause`, `pausieren` or
`/craft:pause` (trimmed, any case — `stop` and `halt` are deliberately no pause words, and a message that merely contains
the word is no request). Claude Code delivers a message sent while a turn runs at the turn's next tool boundary, so the
request must outlive the step in flight: it is a marker, `.claude/plans/.pause-request` (kept as state, never removed),
recorded by you and, for a word sent as a prompt of its own, by the `UserPromptSubmit` hook `hooks/pause-watch.sh`.
**The finding (re-test T3, 2026-10-08):** the hook did not fire for a message delivered mid-turn. It covers only a pause
word sent as a prompt of its own (the agent idle, or a held command delivered at turn end); for a word delivered
mid-turn your own `request` (rule 1) is the only path. `/craft:pause` is a pause word too, but it is a **command**: Claude
Code holds a queued command until the turn ends, so it takes effect only then and cannot stop a running flow mid-turn
the way `pause` / `pausieren` can — whatever the flow did in that turn stands. Four rules, all through
`scripts/pause-request.sh` / `flow-state.sh` (the same plugin-root and project-root as above); you never parse the marker:

1. **Record it.** When a user message that is only a pause word reaches you — in the prompt, or delivered mid-turn
   between tool results — run `bash "<plugin-root>/scripts/pause-request.sh" request --project "<project-root>"` before
   anything else (the hook may or may not have fired; `request` is idempotent). Only for an interactive slice in flight
   (at `implementing`, `testing`, `review`, `refactoring`, `reviewing` or `committing` — a slice still at `planning` is
   not in flight: a "pause" typed in the planning dialogue is too easily meant otherwise), in either flow mode; in
   Subagent Mode and an autopilot run there is no flow to pause. At a countdown (build's sub-task bundle, refactor's item
   bundle, debug's attempt bundle) a message that is only a pause word is the slice's pause request, and any other input
   halts only the countdown or the debug loop. Each phase command states this at its site in one line marked
   `<!-- craft:pause-word -->` (bound by `scripts/test-pause-watch.sh`).
2. **Check it at every boundary.** At each phase end the helper call above already includes it: a live request of this
   session prints `STOP=pause-requested` (it wins over `NEXT=` and over `no-progress`; under `Mode: manual` too, for a
   slice in flight). `/craft:build` also asks at each **sub-task boundary** — after the bundle, while a sub-task is still
   unchecked — with `--from implementing`, in both modes; there only `STOP=pause-requested` matters, any other output
   means the build goes on with the next sub-task.
3. **The pause action.** On `STOP=pause-requested`: finish the running step (never stop in the middle of an edit — the
   sub-task or phase step in flight is completed, or left unchecked with its state in the note), say `Auto flow stops:
   pause-requested — you asked to pause`, then write the handoff (`/craft:handoff`) and pause the slice
   (`/craft:pause`) — the pause note composed by you and shown, not asked for. Both consume the request
   (`pause-request.sh consume`), so `/craft:continue` later resumes the slice the usual way and the old request cannot
   fire again; a request made before a resume is no request (`state --plan` reads the plan's `> Resumed:` line). Start
   nothing after it. A pause word that reaches you while **no step is running** (a new prompt at a boundary) needs no
   boundary: record it (rule 1) and run the pause action at once; for `/craft:pause` that run is the command itself, nothing runs before it (`commands/pause.md` → Pre-flight).
4. **Settle what is not read.** A request the flow never reads — the slice ends in another `STOP=` (Auto flow step 5),
   `/craft:commit` closes it, `/craft:abort` drops it — is consumed there (`pause-request.sh consume`), so it cannot pause
   the next slice of this session.

Doubt for this helper is the reverse of the flow's own: a marker nobody can read, or one of another session, is **no**
request — a phantom pause would halt a flow the human did not stop; a missed one costs one more step, and the human can
type the word again.

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
- `/craft:commit` — git commit + plan closing + slice archive write.
- `/craft:abort` — plan file closing.
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
| **bash ≥ 5.0** | CRAFT's `scripts/` may use current bash features; macOS still ships a frozen `/bin/bash` 3.2. `hooks/` deliberately stay bash-3.2-compatible — they run with whatever bash Claude Code hands them, and the SessionStart hook records that bash so `/craft:prime` can warn when it is older than the Bash tool's. |
| **python3** | JSON handling in the helper scripts (settings merges, manifest parsing). |

The plugin cannot declare these as installable dependencies in the Claude Code plugin manifest. Detection and abort happen at `/craft:prime` runtime; bash and python3 are checked by `scripts/check-toolchain.sh`, which prints an install command that fits the OS.

---

## Session Priming Gate

A CRAFT command is only safe to run once the session is **primed** — project context
(intent / rules / Senior-Developer baseline) is loaded **and** the required tools
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
   run `/craft:prime` (which loads context, verifies the required tools — aborting with the
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

After Phase 9 closes the plan file, the slice's surviving signal lives in three places:

- **Code** — the implementation itself.
- **Commits** — the chronology, with `Slice:` footers for reverse-tracing.
- **Slice archive** — pruned summary at `.claude/project/slices/slice-NNN-<slug>.md`: What / Why / Decisions / Commits, optionally a Mermaid diagram.

The slice archive is the Decision Log, emergent from Phase 6 + 9 — there is no separate decision-log file. Archive contents are by construction non-stale: past-tense facts, original-time justifications, and immutable commit references.

---

## Mid-Phase Abort

If a slice is paused or abandoned mid-phase:

- `/craft:pause` saves state: the plan file stays, at `Status: paused`, with the **pause record** below.
- `/craft:abort <slice>` asks confirmation (Level 0), then closes the plan file — deleted, or moved into `.claude/plans/.closed/` (gitignored once `/craft:prime` step 4f's block is applied) when the user's settings deny or ask on removing it (D34). Aborted slices have no archive value.
- `/craft:prime` detects stale slices (untouched for >N days) and asks: resume or discard.

### Pause record — `Paused-status` and `Paused-since`

Every write of `Status: paused` — `/craft:pause`, the Subagent-Mode pauses of `/craft:build`, `/craft:test` and
`/craft:refactor`, `slice-builder`'s Failure handling, and `/craft:execute`'s interrupt pause — also writes the pause record, two on-demand header fields directly below `Status:` (absent on a
slice that is not paused), the counterpart of `/craft:block`'s `Blocked-status`:

```
> Paused-status: <the Status value the pause replaces, e.g. testing>
> Paused-since: <ISO datetime, UTC — YYYY-MM-DDTHH:MM:SSZ>
```

- **Never over `blocked`:** a pause would drop the block (its fields, `/craft:unblock`'s resume). `/craft:pause` refuses a
  blocked slice and `slice-builder`'s Failure handling leaves one as it is.
- **A pause from any other status starts an episode:** record the replaced status and a fresh `Paused-since`.
- **A pause of a slice that is already `paused` stays in its episode:** keep both fields unchanged (only the Pause
  Note changes). A new stamp would turn a handoff the human has not answered yet stale.
- **A handoff marker written with the pause** carries that `Paused-since` value, character for character, as its
  `Episode:` (see **Handoff marker lifecycle** below).
- **Resume** — moving the plan off `paused` — is defined once, in `/craft:continue` (**Resume a paused slice**): it
  restores `Paused-status` and removes both fields. No other command resumes on its own terms: `/craft:build` runs 4a
  itself, `slice-builder`'s failure retry (step 0) applies the same restore, and the
  phase commands that refuse a `paused` slice (`/craft:test`, `/craft:refactor`) name `/craft:continue` instead.

---

## Worktree Execution Mode

When `/craft:execute <epic-or-slice>` is used, the 9-phase loop runs across parallel git worktrees. The phase boundaries shift slightly:

| Phase | Runs on | Notes |
|---|---|---|
| 1–2 (Brainstorm, Alignment) | main | Pre-slice; unchanged. |
| 3 (Planning) | main | `/craft:plan` writes the plan file on main. Worktrees are NOT created here. |
| 4 (Implementation) | slice-worktree | `/craft:execute` creates `../<repo>-worktrees/<slice-id>-<slug>/` on branch `<slice-id>-<slug>` from the epic-branch (or `main` for a lone slice). `/craft:execute` hands the main checkout's plan into it (`scripts/plan-roundtrip.sh in`), committed or not, so the plan the `slice-builder` works on is the worktree's copy. The `slice-builder` subagent runs `/craft:build` here. |
| 5 (Testing) | slice-worktree | Subagent-callable mode of `/craft:test` writes `.craft/handoff.md` and pauses — Phase 5 requires a human. The one exception: in an autopilot run a helper's pass of the committed checks (`/craft:test` → Subagent Mode step 0a, D35); the product feel then goes to the human at the epic end. |
| 6 (Recap) | slice-worktree | Subagent-callable mode of `/craft:recap` auto-drafts the What/Why/Walk-through. Flagged for human review at checkout. |
| 7 (Refactor) | slice-worktree | Subagent-callable mode of `/craft:refactor` skips if `rules.md` declares Phase 7 dropped; otherwise writes handoff candidates without applying. In an autopilot run it records its candidates as decision lines, applies none and goes on to Phase 8 — the epic-end digest shows them (`/craft:refactor` → Subagent Mode defines it). |
| 8 (Review) | slice-worktree | Subagent-callable mode of `/craft:review` applies in-phase fixes automatically; open findings write a handoff and stop — the plan is not paused (`/craft:review` → Subagent Mode defines the outcome). |
| 8 → epic-merge | slice-worktree, then epic-worktree | When a slice clears review, the orchestrator first commits the slice's work on its branch inside the worktree (the `--scope slice-worktree` paths of `tree-dirt-state.sh`, split as `/craft:commit` Steps 1–3 do) and reads the finished plan back into the main checkout (`plan-roundtrip.sh back`) — for a lone slice too. Then it merges the branch into `epic-<NNN>-<slug>` with `--no-ff`; for a lone slice that merge is skipped — the slice-branch stays parked until Phase 9. |
| 9 (Commit) | main | `/craft:commit` runs from main, detects the mode (Standard / Slice-finalize / Epic-finalize / Epic-close — a finished epic with no epic worktree; under protected main in two passes, D39), merges with `--no-ff`, walks decisions across every included slice, writes archive entries, closes plan files (deleted, or moved into `.claude/plans/.closed/`), and removes worktrees + branches — after releasing each slice worktree's copy of the plan (`plan-roundtrip.sh release`), which would otherwise block the removal. |

### Subagent-callable contract

Phase commands `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review` each carry a `## Subagent Mode` section that defines what they do when invoked by the `slice-builder` subagent rather than directly by a human. The orchestrator delegates rather than duplicating phase logic — one canonical implementation per phase, reused.

The contract has two rules:

1. **Never fabricate human judgment.** UX feedback (W/B/U), refactor candidate selection, escalation routing, decision promotions, commit-message edits — all stay human-only. Subagent mode either auto-drafts (Recap) and flags it for review, or writes a handoff marker and stops (Test/Refactor pause the plan; Review leaves it as its Subagent Mode defines). In an autopilot run Refactor neither selects nor stops: it records its candidates, applies none, and the human selects at the epic end (`/craft:refactor` → Subagent Mode).
2. **Always surface state via `.craft/handoff.md`.** The marker file is the universal "human needed" signal. Hooks watch for it; `/craft:execute` collects it; `/craft:checkout` shows it.

### Handoff marker format

`<worktree-root>/.craft/handoff.md`:

```markdown
---
Slice-ID: slice-NNN
Status: awaiting-test | awaiting-refactor-decision | awaiting-rethink-decision | awaiting-protocol | awaiting-scope-decision | awaiting-block-decision | failure
Phase: 4 | 5 | 6 | 7 | 8
Written: <ISO datetime>
Episode: <the plan's episode when written — see Handoff marker lifecycle; omitted for failure>
---

# Handoff: <one-line title>

<short paragraph describing what the subagent needs from the human>

## Suggested next action

<one-line — typically a /craft:command the human should run, with the slice or epic ID>
```

The orchestrator's "epic partially complete" output lists every active handoff with the slice-ID, the status, and the one-line title. Most statuses pair with a slice plan at `Status: paused` — every writer of such a status pauses the plan, and each writer carries a `<!-- craft:handoff status=… plan=… -->` marker the harness binds to the lifecycle table below; three are exceptions. `failure` pairs with no plan status (live until a retry). `awaiting-block-decision` pairs with the first-class `Status: blocked` state (frontmatter + `## Blocker`) and resolves via `/craft:unblock` rather than a plain `/craft:continue`. `awaiting-rethink-decision` does not pause the plan; its plan status and resolution are defined once, in `/craft:review` → Subagent Mode.

### Handoff marker lifecycle — live, stale, resolved

No command deletes the marker when the human resolves it. Instead **the slice plan in the worktree is the truth and
the marker is a projection of it**: a marker is **live** only while that plan is still at the status its own status
pairs with. Once the human has resolved the handoff — the confirmed resume (`/craft:continue` 4a), `/craft:unblock`, a review route — the plan
has moved on and the marker is **stale**: it no longer means "human needed".

| Marker status | Live while the plan is at |
|---|---|
| `awaiting-test` | `paused` |
| `awaiting-protocol` | `paused` |
| `awaiting-scope-decision` | `paused` |
| `awaiting-refactor-decision` | `paused` |
| `awaiting-block-decision` | `blocked` |
| `awaiting-rethink-decision` | `reviewing` |
| `failure` | — (no paired plan status; live until a retry) |

**A status can be re-entered for an unrelated reason** — a pause after a resume, a block after an unblock, a new
review round in `reviewing` — and an old marker would count again. So a marker also carries its **episode** (`Episode:`), and is live
only while the plan is at the paired status **and** still in that episode:

| Plan at | The episode is | Written into the marker by |
|---|---|---|
| `paused` | the plan header's `Paused-since:` (**Pause record** above) | the pause writers, copying the stamp |
| `blocked` | the plan header's `Blocked-since:` (`/craft:block` → frontmatter) | the `awaiting-block-decision` writer, copying the stamp |
| `reviewing` | the review round count (`scripts/review-findings-state.sh` → `ROUNDS=`); it also ends once no finding line is open | the `awaiting-rethink-decision` writer, from the helper |

A new episode needs no clean-up: every entry into a status *from another status* goes through a writer that stamps
anew (a pause of a paused slice and a re-block of a blocked one keep their stamp — same episode), and an interactive
`/craft:review` appends its round before it routes. A round routed by hand with no new round (`OPEN_COUNT=0`) ends the
episode too — a guard, not a path any writer takes. A marker **without** `Episode:`
(written before B11) is judged by its status alone.

The decision is made in one place, `scripts/handoff-marker-state.sh <worktree>` (`STATE=NONE|LIVE|STALE`); these
tables are its readable copy, and `scripts/test-handoff-marker-state.sh` fails when they disagree. **Doubt means
live** — no plan in the worktree (a project may gitignore `.claude/plans/`), several plans for one slice-ID, a
missing status, an unknown marker status, an episode the plan cannot confirm (no stamp, the findings parser failed,
a value that is not a UTC stamp `YYYY-MM-DDTHH:MM:SSZ` or a round number, a marker episode later than the plan's —
`REASON=episode_unknown`): the marker counts, as it did before the check existed. The same holds
when **the helper cannot run** (not found, non-zero exit, no `STATE=` line): a present `.craft/handoff.md` counts as
live. Every reader and `slice-builder` apply this one fallback; none restates it.

- **Readers** — the SessionStart hook, `/craft:worktree-status` and `/craft:execute` (outcome collection) count a
  marker only when the helper reports `LIVE` (or cannot run, see above); `/craft:abort` and `/craft:worktree-clean`
  show a live marker before they offer to remove its worktree. They only read — never rename.
- **Resolving** — only `slice-builder` renames, and only in its step 0 (`agents/slice-builder.md` → **0.
  Start-of-run marker check**), which is the one definition of when a run stops and when a marker is renamed —
  a stale one with `--resolve`, a `failure` one with `--resolve --retry` — to `.craft/handoff-resolved-<Written>.md`,
  an audit trail that no longer counts. Any marker present after that start check was written in this run.

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
