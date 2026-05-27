# Plugin Brainstorm — Decisions & Open Questions

> Working artifact for the design of a Claude-Code-Plugin package that wraps the user's universal coding workflow (based on Benjamin Thorstensen's 8-Phase Loop + brainstorm/grill-me skills + existing real_live_projekt setup).
>
> Status: brainstorm in progress (Progressive Flow + Question Storming → First Principles). Reset-safe: a fresh agent can resume from here.

---

## 1. Session Setup (frozen)

| | |
|---|---|
| **Topic** | Architecture of a Claude-Code plugin package for the user's universal coding workflow |
| **Outcome** | Ready-to-use plugin/skill set as basis for new & existing projects, actively guiding through the 8 phases, enforcing universal working rules — language- and stack-independent |
| **Core principle** | **Universality with constant control** — same workflow, same control surface, whether Shell script or Laravel monolith |
| **Distribution** | Claude-Code plugin (user-wide, updatable) + project-local `.claude/` overrides (two-tier model) |
| **Language** | Commands / Skills / Agents written in English; user interaction in German |
| **Tool assumptions** | context-mode, agent-browser, git/gh expected; plugin checks at start and warns gracefully if missing |
| **Audience** | Primary: the user. Architecture stays team-capable. |
| **Model strategy** | Optimize for Claude Code first; keep workflow content as portable Markdown, invocation mechanics CC-specific → later port = swap shell, keep content |
| **Session energy** | Mixed: divergent exploration first, then convergent decisions |

---

## 2. Question Inventory (frozen, 16 questions)

### Cluster A — Persistence & Knowledge
- **A1** How do we store project data / project summary for the agent?
- **A2** How do we handle plans?
- **A3** What happens when a plan is done?
- **A4** What can serve as an information source — plans, code, git commits?

### Cluster B — Control & Autonomy
- **B1** How do we honor user preferences (e.g., review approval)?
- **B2** How much autonomy does the agent get during the loop?

### Cluster C — Scale & Cognitive Load
- **C1** How do we parallelize the loop across project parts?
- **C2** How do we prevent mental overload for the user?

### Cluster D — Code Hygiene
- **D1** How do we handle refactoring?
- **D2** How do we handle tests / test adjustments?

### Cluster E — Migration / Legacy
- **E1** What if agent-based development has already happened in the project?
- **E2** Who wins — existing process or our workflow? How do we override?

### Seeds 4–10 (cross-cutting)
- **S4** What happens if the user stops the agent mid-phase? How is state recovered?
- **S5** When human & agent disagree on facts — who wins by default? How is dissent communicated?
- **S6** Plugin lifecycle — how do plugin updates avoid breaking in-flight slices?
- **S7** How does the agent autonomously verify a bug fix and avoid endless loops?
- **S8** What *is* a "vertical slice" for a shell script vs. a library vs. a full-stack web app — universal definition or profile-specific?
- **S9** Cross-slice memory — what knowledge must survive after slice MDs are deleted?
- **S10** Pacing & interrupt etiquette — when may/must the agent interrupt the user?

---

## 3. Decisions (so far)

### D1 — Three-Layer Knowledge Model

| Layer | Content | Ground truth | Persisted in |
|---|---|---|---|
| **State** | What exists | Code / git / configs | Not duplicated — read on demand |
| **Intent** | What we want & why | Human-authored (or dialogically built) | `.claude/project/intent.md` |
| **Rules** | Operational distillation: short, human-readable rules | **Derived** from State + Intent, but **materialized** as a first-class doc | `.claude/project/rules.md` |

**Rules discipline:** `prime` (or equivalent session-start command) validates Rules against State on every run and reports drift. This prevents Rules from going stale, which is the only justification for keeping a derived layer.

### D2 — File Layout

- `.claude/project/intent.md` — Intent (separate file)
- `.claude/project/rules.md` — Rules (separate file)
- `CLAUDE.md` — index/reference only; **does not duplicate content** of intent.md / rules.md

### D3 — Conflict Resolution Policy (A4a)

Assumption: `prime` has just validated Rules ≡ State.

| Conflict | Default winner | Agent autonomy |
|---|---|---|
| **State vs. Intent** | **Intent** | Agent builds toward Intent autonomously — that is the purpose of the loop |
| **Rules vs. State** | **Rules** | Agent corrects State autonomously (e.g., convert PHPUnit → Pest); Rules are canonical after `prime` validation |
| **Rules vs. Intent** | **Rules** by default — **but**: if the human sets a session/slice Intent that breaks a Rule, the agent must **detect, flag, ask** |

### D4 — Three-Stage Rule Override

| Stage | Scope | Persistence | Example |
|---|---|---|---|
| **1. Bend** | Single exchange / single action | None — forgotten after | "Push without Pint this once, it's a README typo" |
| **2. Override** | **Slice-scoped** (Phase 3 → 8 of one slice) | Recorded in the slice plan under "Active Rule Overrides"; **Phase 8 cleanup deletes it** | "During migration-slice 5, direct main pushes allowed" |
| **3. Repeal** | Permanent | Edit `rules.md`, optionally justify in `intent.md` | "We drop Pint in favor of Rector-format" |

**Agent UI on detected conflict:** explicit prompt with the three options + cancel; agent never silently bends a rule.

### D5 — Update Responsibility for intent.md / rules.md (A1b)

**Principle:** Human keeps control. Agent proposes, human confirms, never silent mutation.

| File | Trigger | Mechanism |
|---|---|---|
| **`rules.md`** | `prime` drift detection OR Stage-3 Repeal | Agent shows proposed diff → human confirms |
| **`intent.md`** | Explicit `/intent-update` command OR Phase 6 Recap surfaces architectural insight | Dialogic ("Phase X learned Y — promote to intent?") |
| **Both** | Never silently mutated in Phase 8 — cleanup stays mechanical, semantic updates stay explicit |

### D6 — File Schemas (A1c)

Both files **stay under ~80 lines**. They are loaded on every `prime`; token cost is the filter.

#### `.claude/project/intent.md`
- **Product Vision** (1–3 sentences)
- **Active Goals** (one-liners)
- **Architectural Decisions** (with `Why not <alternative>` line)
- **Non-Goals** (explicit out-of-scope)
- **Open Questions** (cross-slice product questions)

**Rule:** No verifiable/operational instructions in `intent.md` — those belong in `rules.md`.

#### `.claude/project/rules.md`
- **Stack & Tools** (language, test framework, linter, static analysis, package manager)
- **Workflow Rules** (verifiable conditions, e.g. "tests green before commit")
- **Code Conventions**
- **Tabus** (anti-patterns, hard noes)
- **Deployment** (branch model, release tagging, deploy commands) ← lives here as a section, not separate file

**Rule:** Every rule must be **verifiable against State** — otherwise it's an Intent (convention-in-the-making), not a Rule.

#### `.claude/project/roadmap.md` (separate file)
Long-term phases / releases / milestones. Lives outside `intent.md` so the Intent stays compact.

### D7 — Plan Lifecycle (A2)

#### Directory structure
```
.claude/plans/
  slice-NNN-<slug>.md        # one file per active slice
```

- **No `active/` or `done/` subdirs.** What's in the directory IS active. What's gone is done.
- **Slice ID schema**: `slice-NNN-<slug>` (continuous numbering, slug for human readability).
- Parallel slices supported by design (multiple files coexist).

#### Plan file schema
```markdown
# Slice NNN — <Title>

> Status: planning | implementing | testing | review | committed
> Slice-ID: slice-NNN
> Started: <ISO-date> | Phase: <3-8>

## Goal
<one sentence: definition of "done" for this slice>

## Vertical Slice Definition
<which layers this slice spans — stack-specific or universal>

## Test Strategy
<how we know it works — defined BEFORE Phase 4>

## Sub-Tasks
- [ ] <task>

## Active Rule Overrides (Stage 2)
<empty by default; filled when a Stage-2 override is active for this slice>

## Decisions Made During This Slice
<architectural / product decisions to harvest into intent.md or slice archive>
```

#### Lifecycle by phase
| Phase | Plan state |
|---|---|
| 3 | Plan created dialogically (Grill-Me style), status `planning` |
| 4–5 | Status `implementing`/`testing`, sub-tasks checked off |
| 6 Recap | Recap captured **directly as slice archive entry** (see D8) — no separate Recap section |
| 7 Refactor | Sub-tasks extended with refactor items if needed |
| 8 Cleanup | Agent prompts: "Promote these Decisions to `intent.md`?" → human confirms → plan file deleted, archive entry remains |

#### Edge case (S4: mid-slice abort)
Aborted slice's plan stays in the directory; `prime` detects stale slices and asks: "Slice NNN open since X days — resume or discard?"

### D8 — Slice Archive on Cleanup (A3) — *Path A: consolidated*

**No separate `recaps.md`.** Phase 6 Recap produces directly the slice archive entry; that file IS the Recap and the Decision Log.

#### Archive location
```
.claude/project/slices/
  slice-NNN-<slug>.md
```

Agent **may read** this directory — by construction, its contents do not go stale:
- *What* is historically true (past tense).
- *Why* remains valid as the original justification, even if later revised by a newer slice.
- *Commits* are canonical immutable references.

The implementation details (sub-tasks, failed attempts, test specifics) are pruned during Phase 6 → they live in code/commit.

#### Slice archive schema
```markdown
# Slice NNN — <Title>

> Completed: <ISO-date>
> Commits: <first-hash>..<last-hash> (PR #<n>)

## What
<1–2 sentences: what happened>

## Why
- <product / architectural reason>

## Decisions
- **<Decision>** — <reasoning>. *Why not* <alternative>: <one line>

## Commits
- `<hash>` — <commit subject>
- `<hash>` — <commit subject>

## How (Diagram)  ← optional, only for complex slices
<text or mermaid diagram of how the slice's pieces interact>
```

**Consequence:** A4c (separate Decision Log) is **resolved by D8** — the Decision Log is the slice archive, emergent from Phase 6/8.

### D9 — Commit Message Convention (A4b)

**Conventional Commits + `Slice:` footer.**

#### Format
```
<type>(<scope>): <imperative description>

<optional body — what and why, not how>

Slice: slice-NNN
```

- `type` ∈ `feat | fix | refactor | test | docs | chore | perf | build | ci`
- `scope` optional (e.g. `pwa`, `api`, `admin`)
- Footer **always** when working in a slice
- No separate `Phase:` footer — `type` already signals phase (`refactor` ≈ Phase 7, `test` ≈ Phase 5, `feat`/`fix` ≈ Phase 4)

#### Enforcement
**Recommendation only, not blocking.** Real software development is non-linear; the agent suggests a corrected message when format diverges but never blocks a commit on style alone.

#### `/commit` command behavior
1. Read active slice plan from `.claude/plans/` → know `slice-NNN`
2. Analyze uncommitted changes → suggest `type(scope)`
3. Map to sub-tasks → propose atomic commit split
4. Inject `Slice:` footer automatically

#### Why this is strong
| Property | Benefit |
|---|---|
| Standard format | Works with `semantic-release`, changelog tools, GitHub UI, no custom tooling |
| `type` carries phase signal | Agent reconstructs phase distribution per slice via `git log --grep "Slice: slice-NNN"` |
| Footer reverse-traces | One grep recovers full slice history |
| Body stays free | Reasoning fits in, no structural straitjacket |

---

### D10 — Universal Vertical Slice Definition (S8)

> A **Vertical Slice** is the smallest code change that realizes a complete **use-case path** from an **external trigger** (user click, CLI invocation, API call, event, file drop) to an **observable effect** (UI update, stdout, response, state change, output file) and is **end-to-end testable**.

**Four defining properties:**
1. End-to-end testable (test runs from outermost entry gate to outermost exit gate)
2. Standalone-experienceable (delivers clear new caller-value)
3. Minimal (no speculative scaffolding for "the day after tomorrow")
4. Self-contained (could be merged without anything else waiting)

### D11 — No Profile System

The plugin does **not** ship hard project-type profiles (`web | cli | library | …`). The universal definition + a reference table of trigger/effect examples is enough. Phase 3 (Planning) commands are dialogic: they force three universal questions in every slice planning session:

1. **What is the trigger?**
2. **What is the observable effect?**
3. **How do we test it end-to-end?**

**Why not profiles:** Monorepos and mixed projects don't fit hard categories; less plugin maintenance; dialogic discovery is more robust than mechanical profile-matching.

### D13 — Four-Level Autonomy Taxonomy (Cluster B)

| Level | Name | Behavior | Typical actions |
|---|---|---|---|
| **0** | Ask-Always | Ask explicitly, wait for "yes" | Brainstorm answers, alignment questions, rules mutation, push/PR/deploy |
| **1** | Propose-Confirm | Propose, wait for confirmation | Plan creation, in-code architectural decisions, refactoring steps, commit messages |
| **2** | Auto-Notify | Act, then notify compactly at block boundary — pause/rollback possible | Code implementation inside the plan, test runs (if effectful), lint fixes |
| **3** | Auto-Silent | Act without interrupting | File reads, grep, single-file doc lookups, status checks |

### D14 — Phase × Action-Type Autonomy Matrix

#### Phase defaults
| Phase | Default | Reasoning |
|---|---|---|
| 1 Brainstorm | **0** | Consensus is the deliverable |
| 2 Alignment | **0** | Dialogic interview |
| 3 Planning | **1** | Agent drafts, human shapes |
| 4 Implementation | **2** | Code-writing in flow > friction |
| 5 Testing/UX | **1** | UX feel is human-centric |
| 6 Recap | **1** | Recap exists *for* human understanding |
| 7 Refactoring | **1** | Refactor can break — explicit |
| 8 Commit & Cleanup | **1** | Atomic split needs confirmation |

#### Action-type force-overrides (override the phase default in either direction)
| Action | Forced level | Reason |
|---|---|---|
| File read, grep, lint check, status poll | **3** | Pure information gathering |
| Code edit **inside** plan scope | Phase default (~2) | Standard flow |
| Code edit **outside** plan scope | **1** | Plan boundary is a contract |
| Test run / lint run | **3** | Read-only effect |
| `rules.md` / `intent.md` mutation | **0** | Sacred (see D5) |
| Git commit | **1** | Meaningful |
| Git push, PR, deploy | **0** | External, irreversible |
| Branch ops (local, non-destructive) | **2** | Recoverable |
| Branch delete, force-push | **0** | Destructive |
| Stage-3 Repeal | **0** | By definition |
| Stage-2 Override declaration | **1** | Negotiation |

#### Solves
- **S5** (human/agent disagreement on facts): forced Level 0 — agent shows evidence (file/line/commit), asks, never pushes.
- **S10** (interrupt etiquette): the level mix handles it.

### D15 — Bundling, Auto-Continue, Token Brake (Cluster B / C2)

#### Bundle boundary
- **Default:** end of a sub-task in the active plan.
- **Token brake:** if agent output exceeds **30k tokens** since the last bundle, force a bundle mid-sub-task (Dumb-Zone protection).
- **Mandatory bundle at phase end:** every phase transition produces an explicit status check.

#### Bundle format
```
✓ Sub-Task 3/7: <name>
   Changed: <file list>
   Test: <status>
   Level-3 silent ops: <one-line summary, e.g. "read 12 files, ran 3 lint checks">
   Next: Sub-Task 4/7 — <name>
   [continuing in 3s — type 'pause' to stop]
```

#### Continue behavior
- **Auto-continue with abort option** at Level 2 — otherwise Level 2 collapses into Level 1.
- User can interrupt mid-bundle (any input pauses).
- User can pre-empt: "pause after current sub-task" → agent stops at next bundle boundary.

#### Level-3 visibility
- **Not invisible.** Every bundle includes a one-line summary of Level-3 actions performed during the bundle (read files, lint checks, etc.) so the user retains traceability of "what the agent quietly did."

### D12 — Slice Granularity in Agent-Coded Development

**Boundary rule:** end-to-end testability defines the slice boundary. If the end-to-end test simulates the outermost user/caller action, it is **one** slice — independent of how many architectural layers it touches.

**Important insight:** Slice granularity is **mode-dependent**:
- **PM thinking** ≈ feature = one slice
- **Team development** ≈ usually split into 2 slices (frontend + backend) for parallel work
- **Solo agent-coding** = one slice (feature-shaped, not component-shaped)

The plugin's default is **agent-coding mode**: feature-shaped slices. A team-mode override (split frontend/backend per slice) could later become an explicit option, but is **not** the default.

---

## 4. Open Questions in Cluster A

**All resolved.** Cluster A is closed. S8 also resolved.

## 5. Open Questions Parked for Later Clusters

- **B1/B2** Autonomy levels per phase (override mechanics already touched this — continue from there)
- **C1/C2** Parallelization & cognitive-load policy
- **D1/D2** Refactoring & test-adjustment discipline
- **E1/E2** Migration from existing agent setups (relevant for `real_live_projekt`)
- **S4** Mid-phase abort recovery
- **S5** Fact-disagreement protocol (related to D3 but for non-rule disagreements)
- **S6** Plugin update safety while slice is in flight
- **S7** Bug-fix self-verification (from original transcript)
- **S8** Universal "vertical slice" definition
- **S9** Cross-slice knowledge persistence
- **S10** Interrupt etiquette

## 6. Project File Inventory (after Cluster A)

#### Persistent project knowledge (`.claude/project/`)
- `intent.md` — Vision, Goals, Architectural Decisions, Non-Goals (≤80 lines)
- `rules.md` — Stack, Workflow Rules, Conventions, Tabus, Deployment (≤80 lines)
- `roadmap.md` — long-term phases / releases
- `slices/slice-NNN-<slug>.md` — archived completed slices (Decision Log emergent)

#### Ephemeral working memory (`.claude/plans/`)
- `slice-NNN-<slug>.md` — active slice plan, deleted on Phase 8 cleanup

#### Project entry point (repo root)
- `CLAUDE.md` — index/reference to the files above; no duplicated content

### D16 — Three Entry Points (separated)

| Entry-Point | When | Frequency | Lives where |
|---|---|---|---|
| **Project tooling init** (env setup, deps, DB) | Once per machine/clone | Rare | **Project-local** `.claude/commands/` |
| **Workflow onboarding** (`/onboard`) | Once per project — when `.claude/project/` does not exist | One-time | **Plugin** |
| **Session prime** (`/prime`) | Every new chat / context reset | Frequent | **Plugin** |

**Why separate:** they solve different problems; merging would inflate `/prime` with conditional logic and feature-creep.

### D17 — `/prime` Mechanics

> Revised 2026-05-19: trigger semantics tightened; `/craft` entry-point added as Skill (see D23).

#### Trigger
**Auto via SessionStart-Hook — only in Craft-initialized projects.**
- If `.claude/project/intent.md` exists → hook fires `/prime` automatically.
- If not → hook stays **silent**. No nudge, no suggestion. The user opts in by invoking `/craft` themselves.
- User can always re-invoke manually (e.g. after editing `rules.md`).
- Rationale: projects without Craft involvement must remain unbothered; adopting Craft is a deliberate user action (consistent with the Human-Control principle).

#### What `/prime` does
1. **Tool health (strict)** — checks context-mode, agent-browser, git, gh. **Missing tools = abort with installation instructions.** Justification: token efficiency and reliability over graceful degradation.
2. **Auto-activate context-mode** for the session and ensure it is **current** (suggests/applies upgrade if outdated).
3. **Tool currency check** — verifies that integrated tools are usable at current versions; if outdated and breaking, abort.
4. **Load project knowledge** — reads `rules.md` + `intent.md` into context.
5. **Drift check** — Rules vs State; reports drift if any.
6. **Workflow status** — scans `.claude/plans/` for active slices + their phase/sub-task position.
7. **Stale-slice detection** — flags slices untouched for >N days, asks resume/discard.
8. **Recommended next action** — explicit "where do we continue" navigation:
   - active slice present → continue at its phase
   - aborted slice → ask resume/discard
   - none → ready for `/plan`

#### Example output
```
✓ Project: <name> (<stack summary>)
✓ Rules ↔ State drift check: clean | ⚠ <n> drifts (listed)
✓ Tools: context-mode ✓ (activated, v1.0.140), agent-browser ✓, git ✓, gh ✓

Active slices:
  → slice-NNN "<title>" — Phase X, Y/Z sub-tasks done
⚠ slice-MMM untouched for K days — resume or discard?

Recommended next: continue slice-NNN (Phase X)
  → /continue to resume, /plan to start something new
```

### D18 — `/onboard` Mechanics

#### Bail-out
If `.claude/project/` exists → abort, message "already onboarded, run `/prime`".

#### Mode choice (user picks at start)
Agent presents two paths explicitly; user decides:

- **Heuristic-first (fast)** — scan existing docs (`README.md`, `CLAUDE.md`, `PRD.md`) + manifests (`package.json`/`composer.json`/`Cargo.toml`/`*.sh`/…), draft `intent.md`/`rules.md` from heuristics, then ~3–5 dialogic clarifying questions for what heuristics can't infer (product vision, tabus).
- **Grill-Me-intensive** — full interview-style alignment (10+ questions) before any draft. **Recommended for new/greenfield projects** where the structure isn't yet in the head clearly.

Default suggestion: heuristic-first. User can always switch.

#### Outputs
- `.claude/project/intent.md`
- `.claude/project/rules.md`
- `.claude/project/roadmap.md` (if applicable)
- `CLAUDE.md` index entry added (or created) in repo root
- Drift check Rules ↔ State runs immediately, confirms green

### D19 — Self-Verification Protocol for Bugs (S7)

Asset shape: **Skill `self-verify`** (universal, language-independent) + **Command `/debug <bug-description>`** that uses it + separate **Command `/handoff`** for fresh-context restart.

#### `/debug` workflow

| Step | Autonomy | Action |
|---|---|---|
| 1 ALIGN | Level 0 | Dialogically capture bug: expected vs. actual. Append to slice plan under `## Bugs`. |
| 2 PROTOCOL | Level 0 | Agent proposes a **verification command + expected result + negative check**. User confirms before any fix attempt. Protocol nailed into slice plan. |
| 3 AUTONOMOUS LOOP | Level 2 + tightened token brake (15k instead of 30k) | Iterate up to **5 attempts**: hypothesize → edit → run protocol → log attempt → next. On success, exit and report fix + diff. |
| 4 ESCALATION | Level 0 | After 5 failed attempts: full attempt log, three suggested options (handoff, recap, re-negotiate protocol). |

#### Auto-trigger threshold
Agent self-offers `/debug` when it detects **≥2 fix attempts** for the same symptom in the active slice. Agent asks — never forces.

#### Configurability
Both numbers (`max-attempts: 5`, `auto-trigger threshold: 2`) are **overridable per project in `rules.md`** under "Self-Verification Settings".

#### Natural follow-ups (not separate decisions, just consequences)
- Verification protocol written into slice plan under `## Verification Protocols` — survives context resets, visible to next session.
- On successful fix, agent **proposes** promoting the ad-hoc verification command to a permanent regression test (user confirms).
- Bug fix commits follow D9 — `fix(scope): …` + `Slice:` footer.

#### `/handoff` — separate command
For cases of context-poisoning or stalled progress (not necessarily bug-related). Agent summarizes the current problem state (what tried, what didn't) into a designated handoff section of the slice plan; user starts a fresh chat, `/prime` reloads it, fresh agent picks up.

### D20 — Migration Strategy (Cluster E)

#### Core insight: Plugin = Shell, Project-local = Body
- **Plugin** provides the universal workflow shell (commands, navigation, autonomy, phase logic).
- **Project-local** keeps language/stack-specific specialist content (skills, agents, code-quality references).
- Plugin commands lazy-load project-local skills/agents at runtime.
- **Migration is replacement of the shell, not removal of the body.**

#### Trigger: `/onboard` with auto-detect
No separate `/migrate` command. `/onboard` detects whether `.claude/` already exists with content and switches to migration sub-path automatically.

#### Migration sub-path inside `/onboard`
1. **Detect** — scan existing `.claude/` structure.
2. **Classify** every asset into one of four classes:
   - **Universal conflict** (commands that overlap with plugin commands) → move to `.claude/commands/_legacy/`
   - **Specialist keep** (language/stack-specific skills and agents) → leave in place
   - **Knowledge-split source** (existing `CLAUDE.md`, `README.md`, `PRD.md`) → split into `intent.md` / `rules.md` / `roadmap.md`
   - **Project-local keep** (project tooling commands, allowlists) → leave in place
3. **Inventory report** to user — what was found and the proposed action per class.
4. **Confirm-by-class with override option** (Level 0) — user accepts a class wholesale or overrides specific items ("yes legacy all commands EXCEPT `init-project.md`").
5. **Execute** — moves, splits, generates `.claude/project/*.md`.
6. **Validate** — drift check Rules ↔ State, green confirmation.

#### Command naming: same names, no namespace
- Plugin commands use natural names (`/plan`, `/execute`, `/commit`, …).
- Claude Code's precedence (project-local wins) is **respected** — but after migration, the legacy commands are moved out of `commands/`, so plugin commands become active.
- A user who wants to keep a project-local variant can simply leave it in place; it will override the plugin automatically.

#### Concrete migration mapping for `real_live_projekt` (example, captured for later)

| Asset | Action |
|---|---|
| `commands/plan-feature.md`, `plan-backlog.md`, `plan-parallel.md`, `review-plan.md`, `execute.md`, `co-review.md`, `commit.md`, `prime.md`, `create-prd.md`, `create-rules.md` | → `_legacy/` |
| `commands/init-project.md` | keep (project-tooling init) |
| `agents/developer.md`, `agents/code-reviewer.md` | keep |
| `skills/developer/`, `skills/code-review/` | keep |
| `skills/agent-browser/` | open — keep project-local, OR promote to plugin universal skill |
| `CLAUDE.md` | split into `intent.md` + `rules.md` + `roadmap.md`; keep slim index in repo root |
| `CLAUDE-template.md` | → `_legacy/` (plugin ships its own template) |
| `settings.local.json`, `allowed-commands.md` | keep |

### D21 — Phase 5 Mechanics (User Testing)

Phase 5 is the only place the human exercises the artifact before Phase 6/7/8 progress. It cannot be skipped even if Phase-4 automated tests are green.

#### Sub-steps
| Step | Autonomy | Description |
|---|---|---|
| **5a Demo-Setup** | Level 1 | Agent prepares the artifact for hands-on: starts the server, prints the URL/command, lists concrete "try this" steps derived from the slice's trigger (D10). |
| **5b User-Exercise** | (Human) | User exercises the artifact. No agent intervention. |
| **5c Feedback-Capture** | Level 0 | Agent asks structured: **[W]orks → Phase 6 / [B]ug → trigger `/debug` / [U]X issue → iterate** |

#### UX-Issue handling
When user reports `[U]`: agent asks **directly** ("Was genau soll anders sein?") — never interprets autonomously. UX interpretation without explicit input is the largest pitfall.

#### Bug-found-during-Phase-5
Triggers D19 `/debug` flow automatically. Agent: "User reported bug — entering `/debug` mode for verification protocol."

#### Demo-Setup adaptation per project type
Phase 5a derives the demo invocation from the slice's recorded trigger (D10):
- Web app → URL to open
- CLI tool → command to run
- Library → minimal snippet using the new API
- Worker → how to trigger the job
- Pipeline → how to feed input

### D22 — Light-Sweep Decisions (Cluster D + C + S6 + S4 + Misc)

#### Phase 7 Refactoring
- Mandatory in every slice (Thorstensen "not later" discipline).
- Agent dialogically asks the three transcript prompts (Level 1).
- **Max 2–3 refactor items per slice.** Larger refactor = its own slice.

#### Tests
- Strategy defined in Phase 3 (D7).
- Phase 4 runs tests automatically (Level 3 silent unless red).
- Phase 5 = UX/human feedback, NOT functional tests.
- Phase 7 refactor breaks tests → fix tests in the same slice.

#### Parallel slices (Cluster C / C1)
- File structure supports it (multiple files in `plans/`).
- **Plugin does NOT orchestrate** parallel slices — one CLI session, one focus slice.
- `/prime` lists all active slices; user picks the focus explicitly.
- Parallelism = multiple worktrees or multiple sessions (user responsibility).

#### Plugin update mid-slice (S6)
- Slice plan frontmatter carries `plugin-version: <semver>`, set at Phase-3 start.
- `/prime` compares installed vs. slice-locked version; on mismatch, **warn but allow continuation**.
- No hard version lock — pragmatic over rigid.

#### Mid-phase abort (S4)
- `/pause` saves state, slice remains open.
- `/abort <slice>` asks confirmation (Level 0), **deletes** plan file by default (aborted slices have no archive value).

#### Phase 6 Recap format
- Plain-text What/Why/Decisions by default.
- Mermaid diagram only on complex slices (>3 modules/files); agent offers it, user decides.

#### Phase 8 Decisions Promotion Dialog
- Walks through each "Decisions Made During This Slice" entry.
- Per item: single-letter choice **[K]eep in archive / [I]ntent / [R]ules / [D]iscard**.
- Default for skipped entries: **K** (archive only) — no cognitive burden for trivial items.

#### agent-browser skill
- **Promoted to plugin** as universal skill (browser is stack-agnostic).
- Project can override locally if needed.

#### Multi-repo / Monorepo scope
- In-scope but not first-class.
- Monorepo: each sub-project runs its own `/onboard` → its own `.claude/project/`.
- Plugin assumes 1 repo = 1 project setup; not orchestrated across sub-projects.

#### Brainstorm / Grill-Me skills
- **Adopted 1:1** into the plugin (`skills/brainstorm/`, `skills/grill-me/`).
- Plugin provides commands `/brainstorm` and `/grill-me`.
- Phase 1 wraps `/brainstorm`; Phase 2 wraps `/grill-me`.

### D23 — `/craft` Single Entry-Point (Skill)

> Decided 2026-05-19, replaces the prior "short shim names" approach.

#### Asset shape
- **Skill** at `skills/craft/SKILL.md` with frontmatter `name: craft`, `user-invocable: true`.
- Because plugin name (`craft`) equals skill name (`craft`), Claude Code's namespace collapse exposes the skill as `/craft` — same pattern as `/context-mode`.
- **One asset only**: either Skill or Command, never both. The decision is Skill.

#### Why Skill, not Command
- Namespace collapse delivers the `/craft` short form natively.
- Body can carry both behavior (state-detection logic) and reference material (what each state means) without per-invocation token cost — loaded once, persists.
- Description field allows optional auto-activation triggers later without changing asset shape.

#### Behavior — state-aware dispatch
On invocation, `/craft` reads project state and offers exactly the actions valid for that state:

| Detected state | Marker | Offered actions |
|---|---|---|
| **Not onboarded** | `.claude/project/intent.md` missing | `/craft:onboard` only |
| **Onboarded, no active slice** | `intent.md` present, `.claude/plans/` empty | `/craft:plan`, `/craft:status`, `/craft:intent-update` |
| **Active slice in progress** | one or more `.claude/plans/slice-*.md` | `/craft:continue`, `/craft:status`, `/craft:pause`, `/craft:abort` |
| **Aborted/stale slice** | plan untouched >N days (per D17 stale-detection) | `/craft:continue` (resume), `/craft:abort` (discard) |

The user picks; `/craft` does not auto-execute. This preserves Human-Control.

#### Naming convention for sub-commands
- All sub-commands are addressed as `/craft:<name>` — `plan`, `execute`, `commit`, `debug`, `continue`, `pause`, `abort`, `handoff`, `onboard`, `test`, `refactor`, `recap`, `intent-update`, `status`.
- **No shim files** in `~/.claude/commands/`. Existing shims from the earlier short-name policy will be removed.
- Internal cross-references inside command/skill bodies and hooks must use the full `/craft:<name>` form to avoid collisions with Claude Code reserved names (e.g. `/plan` vs. Plan-Mode) and with project-local `commands/<name>.md` overrides (D20 migration scenario).

#### Spike closed (2026-05-20)
The `/craft` skill stub shipped in v0.1.0/v0.2.0 and is in active use. The three probes are no longer load-bearing — see D26 for the dropped follow-ups.

### D24 — Pre/Post-Assertions for Durable-State Commands

> Decided 2026-05-20, prompted by the `/craft:upgrade` design (v0.2.0).

#### What

CRAFT adopts a named **Pre/Post-Assertion pattern** for commands that mutate durable state outside the running session. The pattern is documented in `skills/workflow/SKILL.md` and applied selectively — never as ceremony.

#### Scope — required

- `/craft:onboard` — Pre: target directory is unowned by an existing CRAFT setup; Post: `intent.md` + `rules.md` both exist with valid frontmatter.
- `/craft:plan` — Pre: no in-flight slice already covers the requested feature; Post: slice plan file exists, frontmatter parses, sub-tasks section present.
- `/craft:commit` — Pre: working tree state matches expected, plan file present; Post: commit landed, plan file deleted, archive entry written.
- `/craft:abort` — Pre: plan file exists; Post: plan file gone.
- `/craft:upgrade` — already implemented in v0.2.0 as the reference implementation.

#### Scope — exempt

- Read-only commands (`/craft:status`, `/craft:prime`, `/craft`) — no mutation, no assertions.
- Phase-execution commands (`/craft:execute`, `/craft:test`, `/craft:refactor`) — open-ended code changes; assertions would be ceremonial.
- Pure-conversation commands (`/craft:brainstorm`, `/craft:grill-me`, `/craft:debug`) — no FS mutation.

#### Pattern shape

Each assertion is a discrete, named check. Failure stops the command with a loud message — never silent override, never auto-correction. This mirrors the `/craft:upgrade` template:

```
## Pre-Assertions
### A1 — <name>
<check>
On failure: <abort message, no mutation>

## Procedure
...

## Post-Assertions
### P1 — <name>
<check>
On failure: <warn loudly, surface to user, do not pretend success>
```

#### Why

- Aligns with `feedback-human-control`: durable mutations require explicit guardrails.
- Aligns with `feedback-recommendation-over-blocking`: strict only at the boundary of durable state changes, not for style.
- Mirrors context-mode's defensive pattern without adopting its build complexity.

#### Open

Retrofit existing durable-state commands in a separate slice — not blocking this decision.

### D25 — No MCP Server for CRAFT (for now)

> Decided 2026-05-20.

#### Decision

CRAFT stays **pure Markdown** — no MCP server, no build pipeline, no native addons, no runtime dependencies. Slice state remains derivable from `.claude/plans/*.md` files via `Glob` + `Read`.

#### Why

- CRAFT's USP is the "Plugin = nur Markdown" charm: zero install friction, forkable, contributor-friendly, debuggable by reading the files.
- Slice-state queries (active slices, phase, stale detection) are already fast enough at the scale we have observed.
- An MCP server would tilt CRAFT into context-mode's category — different tool, different value proposition.

#### When to revisit

Concrete performance pain (e.g., `/craft:prime` consistently >5s on a project with many slices, or cross-session state needs that can't be expressed in file frontmatter). Until then, do not speculatively design it.

#### What we do **not** do

- No build step, no `package.json` for the plugin root.
- No background process, no daemon.
- No SQLite or any other persistent index.

### D26 — Dropped Follow-Ups (Spring 2026 Cleanup)

> Decided 2026-05-20.

The following items were considered and explicitly dropped. Recorded here so future iterations of the project don't speculatively resurrect them without a fresh decision.

#### Dropped

- **D23 Probe 3 — Skill vs. project-local command shim precedence.** The `/craft` skill is in active use; the precedence corner case is not load-bearing. If a real-world collision ever occurs, deal with it then.
- **`/craft:upgrade` dogfood test.** v0.2.0 ships; we will validate the pull path naturally when v0.3.0 is cut. No dedicated dogfood slice required.
- **`/craft:prime` hybrid refactor (skill + hook + manual command).** Item 5 of `brainstorm-skill-shortname-pattern.md`'s "Folge-Schritte". The current `/craft:prime` command + SessionStart hook is sufficient; no observed need to convert it to a skill.
- **`prime` trigger mode (auto vs. manual) banking as a formal decision.** Already settled in practice — auto-prime fires only when `.claude/project/intent.md` exists; manual `/craft:prime` is always available. No formal decision artifact needed.

#### Why dropped, not parked

These items had been carry-overs from earlier brainstorms but stopped producing new design tension. Parking them perpetually inflates the open-questions surface; explicitly dropping them keeps the decision space focused.

### D27 — Personality Autoload (3-Tier System)

> Decided 2026-05-20. Closes the parked "Capability / personality autoload" item from `plugin-architecture.md` §13 item 10. Grounded in the developer skill extracted from `research/real_live_projekt/.claude/skills/developer/` — which mixed universal, stack-specific, and project-specific content monolithically.

#### Three tiers

The personality system is split into three portable layers, mapped to natural clusters observed in the existing developer skill:

```
┌──────────────────────────────────────────────────────┐
│  Tier 3 — Project-Overlay                            │
│  Where:  .claude/project/rules.md  (already exists)  │
│  Loaded: by /craft:prime                             │
│  Owns:   project-specific commands, conventions,     │
│          domain rules, tool bindings                 │
├──────────────────────────────────────────────────────┤
│  Tier 2 — Stack-Pack  (monolithic)                   │
│  Where:  plugin:  skills/stack-<lang>-<fw>/SKILL.md  │
│          user:    ~/.claude/craft-personalities/...  │
│  Declared in: rules.md `## Personality` block        │
│  Loaded: by /craft:execute, /craft:test,             │
│          /craft:refactor (explicit Read)             │
│  Frontmatter: `disable-model-invocation: true`       │
│  Owns:   language idioms, framework patterns,        │
│          test-framework idioms, anti-patterns        │
├──────────────────────────────────────────────────────┤
│  Tier 1 — Senior-Dev Baseline                        │
│  Where:  skills/senior-developer/SKILL.md            │
│  Loaded: by /craft:prime, always active              │
│  Frontmatter: `disable-model-invocation: true`       │
│  Owns:   stance, quality hierarchy, workflow gates,  │
│          test-discipline matrix, problem-playbook    │
└──────────────────────────────────────────────────────┘
```

Override precedence (when contents conflict): **Tier 3 > Tier 2 > Tier 1**. The project's `rules.md` always wins. This is consistent with the existing CRAFT rule-conflict resolution (D17): Rules > State, Rules > Intent (override offered).

#### Why monolithic stack-packs (no PHP/Laravel/Filament split)

A stack-pack bundles `<language> + <framework> + <test-framework>` into one named unit (e.g., `stack-php-laravel`). The earlier brainstorm proposal of "PHP general" → "PHP Laravel" → "PHP Laravel Filament" composition was rejected — the population of users per stack is small, and duplication between `stack-php-laravel` and `stack-php-symfony` is fine. Simplicity beats reuse here.

#### Why hybrid distribution

CRAFT ships a curated starter library of stack-packs (beginning with `stack-php-laravel`, extracted from the validated `real_live_projekt/developer.md`). Users can add their own at `~/.claude/craft-personalities/`. Plugin updates refresh shipped packs; user-added packs are untouched. This mirrors the marketplace model: official content + user content, both discoverable, no overwrite.

#### Why declared + explicit-load for Stack-Pack

`rules.md` is the single source of truth for what stack-pack is active in a given project. Implementation-time commands (`/craft:execute`, `/craft:test`, `/craft:refactor`) read this declaration and load the skill explicitly via `Read`. CC's native description-triggered auto-activation is **off** for stack-packs (`disable-model-invocation: true`) to prevent cross-stack contamination (e.g., a Python pack activating in a Laravel project when "Python" is mentioned in passing).

This is consistent with `feedback-human-control`: durable loading is human-controlled, not LLM-opportunistic.

#### Why Senior-Dev is loaded by /craft:prime, not lazy

The Senior-Dev baseline is small (~2-3KB), universal (no stack-specific risk), and relevant in every phase (planning, debugging, executing, recapping). Loading it once at session start, like `skills/workflow/`, matches its semantic role: the embodiment of the CRAFT mindset itself. Stack-packs are large (~8-10KB+), framework-specific, and only relevant during code-near work — those stay lazy.

#### Open implementation details (out of scope for D27)

These belong to the implementation slice when it opens:

- How `/craft:onboard` heuristically detects the stack and proposes a stack-pack name (composer.json → `stack-php-laravel`, package.json with Next.js → `stack-ts-nextjs`, etc.).
- Exact schema of the `## Personality` block in `rules.md` (single field vs. structured section, optional vs. required).
- Behavior of `/craft:prime` when `rules.md` declares a stack-pack that is not installed (warn + fall back to Senior-Dev only).
- Whether `/craft:plan` and `/craft:debug` also load the stack-pack (current assumption: no — Senior-Dev is enough for planning and debug-protocol negotiation).
- Content extraction work: split `research/real_live_projekt/.claude/skills/developer/` into `skills/senior-developer/` (Cluster A) + `skills/stack-php-laravel/` (Cluster B), with Cluster C (project-specific) staying in the existing `rules.md` template.

#### File structure (canonical)

```
skills/
├── senior-developer/
│   └── SKILL.md
└── stack-php-laravel/
    ├── SKILL.md
    └── references/
        ├── code-quality-standards.md
        ├── framework-patterns.md
        └── test-patterns.md
```

User-added packs mirror the same shape at `~/.claude/craft-personalities/stack-<name>/`.

#### Extension (2026-05-20) — Tier-1 singularity & Tier-2 naming convention

> Brainstorm-refined from `brainstorm-personas-wishlist.md`. Two threads resolved;
> one wished item explicitly relocated out of D27 scope. Additive — D27's tier
> model is unchanged; only the Tier-2 name pattern is generalized (see below).

##### Tier 1 stays a single baseline

The wishlist proposed a second Tier-1 personality ("Senior Reviewer") and inferred
"Tier 1 may hold multiple parallel roles." That inference is **rejected**. A reviewer
is the *same* Senior-Developer baseline — same quality hierarchy, same stance, same
architecture understanding — invoked differently. It carries no personality content
the baseline lacks.

The one genuinely review-specific element — severity grading of findings — splits
cleanly and needs no new personality:

- **Judgment** (is a finding architecture-/security-critical or cosmetic?) is senior
  judgment and already lives in the baseline's quality hierarchy.
- **Mechanics** (the explicit severity ladder, the findings format, what the agent
  does per tier) is process — comparable to the autonomy matrix or commit convention.

→ **Tier 1 owns exactly one baseline skill (`skills/senior-developer/`), unchanged.**
The wishlist's "Senior Reviewer" Tier-1 entry is dropped.

##### The reviewer is a workflow construct, not a personality (carry-over)

"Senior Reviewer" stays a wanted capability — the four-eyes principle: a fresh agent
reviews finished, refactored code against existing architecture/project decisions,
flags silent revocation of prior decisions (unless the slice deliberately replaced
them), grades findings by severity, and leaves already-good code better.

Because it is the baseline skill + a fresh agent + a review brief, it belongs to the
*workflow*, not to D27's personality tiers. Provisional placement: a `/craft:review`
step after Phase 7 (Refactor), before Phase 8 (Commit) — Execute → Refactor → Review
→ Fix → (optional Refactor) → Commit. Whether Review becomes a formal new phase or a
step inside the existing model is a separate decision.

→ **Carry-over:** open a dedicated decision for the review step — phase-model
placement, the severity rubric, the fresh-agent invocation. Out of scope for D27.

##### Tier-2 naming convention

D27's file structure shows `skills/stack-<lang>-<fw>/`. This extension generalizes it:

- **Pattern:** `stack-<language>[-<context>]` — the second segment is **optional**.
- The second segment is not strictly "framework" but the **idiom-defining world**:
  usually a framework (`laravel`, `symfony`, `django`), occasionally a domain (e.g.
  data-science). It always denotes the thing that makes this idiom set genuinely
  different from the bare language.
- **Frameworkless packs are first-class, not degenerate.** `stack-bash` (no framework
  concept) and `stack-python` (vanilla) are complete monolithic packs carrying the
  language's native best practices. "Vanilla Python" and "Python + framework" are two
  distinct packs — related, but separate — consistent with D27's no-composition /
  duplication-is-fine rule.
- **The test framework is NOT a name segment.** A pack does not silently bake one
  test tool. Per language (and differently with/without framework) it carries a
  *menu* of standard tooling — test framework, linter, static analysis — each
  annotated with the community-recommended default and its trade-offs.
- The *active* tooling choice is a **Tier-3 decision**: `/craft:onboard` surfaces the
  pack's recommendation, the user chooses, the choice is recorded in `rules.md`.
  Recommendation, not mandate (cf. `feedback-recommendation-over-blocking`).

This sharpens the tier split: **Tier 2 = what the stack knows and recommends;
Tier 3 = what this project chose.**

##### Wishlist disposition

- `stack-php-laravel` — canonical, unchanged.
- `stack-php-symfony` — valid; fits `stack-<language>-<context>`.
- `stack-python` — valid frameworkless pack (vanilla); `stack-python-django` etc. are separate packs.
- `stack-bash` — valid frameworkless pack; bash has no framework concept — fine.
- "Senior Reviewer" — removed from Tier-1 wishlist; relocated to the review-workflow carry-over above.

### D28 — Code Review Phase (Phase 8)

> Decided 2026-05-20. Resolves the review-workflow carry-over parked by D27's
> extension block. The "Senior Reviewer" is a workflow construct, not a personality
> (see D27 §6 extension) — this decision gives it phase rank, an autonomy profile,
> and a findings rubric.

#### Phase placement

Review becomes a standalone **Phase 8**; the former Phase 8 (Commit) shifts to
**Phase 9**. The model is now nine phases:

1 Brainstorm · 2 Align · 3 Plan · 4 Execute · 5 Test · 6 Recap · 7 Refactor ·
**8 Review** · 9 Commit

Review sits *after* Refactor deliberately: it reviews the artifact that will actually
be committed. A CRAFT slice is small by design (D10/D12) and Phase 7 refactoring is
bounded (D22: max 2–3 items), so the post-refactor delta is small — one late review
is enough. No second, earlier review is baked into the model. For an unusually large
slice the agent **may recommend** an extra ad-hoc `/craft:review` earlier (Level-1
autonomy: recommend, human decides) — an opt-in escape hatch, not a phase.

Slash command: `/craft:review`.

Knock-on: `/craft:recap` currently states its draft becomes the slice-archive entry
"in Phase 8" — that archive write moves to Phase 9 (Commit).

#### What Review does

Phase 8 both **finds and fixes** — but fixing is bounded, so the committed artifact
stays trustworthy without a re-review. The review agent produces severity-graded
findings and resolves them per the rubric below.

#### Findings rubric — two axes

Findings are classified on **two orthogonal axes**:

- **Severity** — does this *have* to be resolved before Commit?
  - *Heavy*: architecture violation, security issue, a test that technically passes
    but is task-wise wrong (signals a misunderstanding), silent revocation of a prior
    decision not deliberately replaced by this slice.
  - *Light*: code style, a small missing test case, cosmetics.
- **Fix-nature** — *where* is it resolved?
  - *Local edit*: a paged-in developer could finish it in ~half an hour — one-liner,
    add a missing test case, style. → fixed **in Phase 8**.
  - *Needs rethinking*: something is genuinely wrong and the original developer must
    reconsider it with the reviewer's notes. → **escalated**, never fixed in Phase 8.
    Fix-nature is "edit vs. rethink", not "small vs. large" — a task-wrong test is a
    tiny edit but still escalates, because it is a misunderstanding.

The 2×2:

| | Fix = local edit (in-phase) | Fix = needs rethinking (escalated) |
|---|---|---|
| **Heavy** | Review agent fixes in Phase 8 | Escalated — **blocks Commit**: loop back to Phase 4 / spin off a new slice before this slice may close |
| **Light** | Review agent fixes in Phase 8 | Recorded as a **follow-up**; **Commit proceeds** |

Severity decides whether a finding blocks Commit; fix-nature decides whether it is
resolved here or by escalation.

#### Soft volume cap

On top of the edit-vs-rethink line, a **soft count cap** guards against many tiny
fixes summing to a large unreviewed delta: once in-phase fixes exceed **N** (default
5, configurable in `rules.md` under `## Self-Verification Settings`), the agent stops
and **recommends** escalating the whole batch rather than fixing it. Soft = a
recommendation, not a hard block (cf. `feedback-recommendation-over-blocking`).

#### Fresh-agent invocation

Review runs as a **subagent with a fresh context window** — the four-eyes principle.
Independence comes from the clean window, not from blinding the reviewer.

The review agent is loaded with:

- the Senior-Developer baseline (D27 Tier 1) and the project's Stack-Pack (D27 Tier 2
  — review is code-near work, like Execute/Refactor);
- the slice's task/intent and plan;
- all prior project decisions (to catch silent revocation);
- the final code / diff under review;
- the **Phase 6 Recap** as the developer's "thinking trace" — a *summary* of
  what/why, mirroring a human PR description, not the raw Execute logs;
- this findings rubric.

The Recap is the existing artifact that plays the PR-description role — no new
artifact is introduced.

#### Why

- One late review (post-Refactor) reviews the real shipped artifact; an earlier
  review would be partly invalidated by the refactoring that follows it. Small slices
  + bounded refactoring make a single review sufficient — cost stays proportionate.
- Capped, edit-only in-phase fixes keep the committed delta small enough that
  re-review is genuinely unnecessary; anything bigger escalates.
- Working *with* the Recap (not in full isolation) mirrors real human review: the
  reviewer sees a summary of intent, which makes "what/how/why" fast to reconstruct,
  while the fresh context window still prevents implementer bias.

#### Open implementation details (out of scope for D28)

- Exact escalation mechanics: loop-back to Phase 4 vs. spinning off a new slice — and
  how a Commit-blocking finding is surfaced and tracked.
- The `## Self-Verification Settings` key name and default for the soft cap N.
- Findings/follow-up format and where light "needs-rethinking" follow-ups are
  recorded (slice archive vs. a dedicated follow-up list).
- Whether `/craft:review` is also independently slash-invocable mid-flow (the
  large-slice escape hatch) and how that interacts with phase state.
- The review agent's autonomy profile in the D13/D14 matrix (Phase-8 defaults).

---

### D29 — Concentrated-Control Execution

> Decided 2026-05-26. Inverts the original "constant control" framing of the plugin
> for execution-heavy phases without weakening the human's grip on the hard ones.

The original framing — *universality with constant control* — describes the discipline
correctly but mis-positions where the control actually has to land. In practice the
human's judgment is load-bearing in a small set of phases (Planning, Recap, Review of
escalations, escalated Bugs); the others (Build, automated Test, in-phase Review
fixes, mechanical Recap drafting) are mechanical enough to delegate.

Decision: control is **concentrated at the hard phases**, delegated at the
mechanical ones. The 9-phase loop is unchanged; the autonomy taxonomy (D13/D14) is
unchanged. What changes is the implicit cadence — the agent is allowed to run
several mechanical phases back-to-back without per-phase confirmation, and the
human steps in at the planned checkpoints.

This decision is the prerequisite for parallel-worktree execution (D30): without
concentrated control the orchestrator would be impossible — every slice would need
per-phase human input.

---

### D30 — Parallel Worktree Execution Architecture

> Decided 2026-05-26 during the slice-009 planning session. Operationalizes D29 by
> defining how the 9-phase loop runs across multiple git worktrees simultaneously.

A new orchestrator command (`/craft:execute`, see D31) takes an epic or a single
slice, creates one git worktree per runnable slice, runs Phases 4–7 inside each via
the `slice-builder` subagent, merges slice-branches into an epic-branch as each
slice clears review, and stops at epic-end for human review. The architecture has
the following load-bearing choices:

- **Worktree location** — `../<repo>-worktrees/<slice-id>-<slug>/`, neben dem Repo
  (not inside `.craft/` in the repo). Reason: tools (npm/Docker/IDEs) scan the repo
  and would otherwise mistake sub-checkouts for the main checkout. Path is
  configurable via `## Worktree Settings` in `rules.md`.
- **Lifecycle** — one worktree per slice, alive from start of Phase 4 until Phase 9
  archive cleanup. Created by `/craft:execute`, not by `/craft:plan` (planning
  stays on main; only execution moves into worktrees).
- **Concurrency** — multiple slices run in parallel via subagents. Sub-tasks within
  one slice remain sequential — cross-sub-task merge coordination has the same cost
  as cross-slice merge coordination without comparable parallelism gain.
- **Phase distribution** — Phase 1/2/3 on main; Phase 4–7 in slice-worktree;
  Phase 8 = merge into epic-branch (orchestrator) or into main (`/craft:commit`);
  Phase 9 = worktree + branch cleanup.
- **Merge topology** — slices merge to an `epic-<NNN>-<slug>` branch inside a
  dedicated epic-worktree; the epic-branch merges to main at `/craft:commit` time.
  Reason: enables a "checkout the full epic for review" mode alongside per-slice
  inspection.
- **Merge strategy** — always `--no-ff` merge commits. Reason: preserves slice
  topology in history, makes parallel build structure visible. Squash or rebase
  would erase it.
- **Slice dependencies** — explicit `Depends-On: [slice-NNN, ...]` frontmatter on
  each slice plan. Reason: file-overlap heuristics are unsafe; cycles are detected
  upfront from the explicit graph.
- **Default review-stop** — at epic-end. Per-slice or per-checkpoint stops opt-in
  via `## Review Checkpoints` in the epic plan. Reason: per-slice stops produce
  review fatigue ("klickt ihn nur sinnlos weiter").
- **Handoff signaling** — `.craft/handoff.md` marker file in the slice-worktree.
  Phase commands write it in subagent mode whenever human judgment is required
  (Phase 5 UX feedback, refactor decisions, Heavy + needs-rethinking findings,
  test failures past the autonomy threshold). A SessionStart hook surfaces
  pending markers when a new chat opens.
- **Provisioning** — `/craft:checkout` does only `git worktree`-related navigation
  and prints a stack-pack-specific hint (e.g., `composer install`). Reason: the
  universal layer stays out of stack-specific dependency installation; the
  stack-pack carries that knowledge.
- **Cleanup** — automatic at Phase 9 archive (worktree-remove + branch-delete).
  `/craft:worktree-clean` exists as a safety net for orphans from interrupted
  runs. `/craft:abort` asks before removing an active worktree.

#### Three companion commands

- `/craft:checkout <slice|epic>` — switch into a worktree for human inspection.
- `/craft:worktree-status` — list every active CRAFT worktree.
- `/craft:worktree-clean` — reconcile orphans.

These are described concretely in `commands/{execute,checkout,worktree-status,worktree-clean}.md`.

---

### D31 — `/craft:execute` Rename + Orchestrator-Delegation Pattern

> Decided 2026-05-26 alongside D30. Resolves a naming collision and fixes the
> "two code paths per phase" risk that D30 would otherwise introduce.

The Phase-4 build command was originally named `/craft:execute`. The autonomous
orchestrator introduced by D30 wants the same name — `/craft:execute <epic>` is the
most discoverable framing of "run my plan." Rather than name the orchestrator
something weaker, the Phase-4 command is renamed:

- `/craft:execute` (Phase 4 build) → `/craft:build`. The Phase-4 work is
  semantically "build the slice", and the new name reflects that.
- `/craft:execute` is freed up for the orchestrator from D30.

A one-time migration cost; the wrong name lingers forever.

**Delegation pattern.** The orchestrator does **not** duplicate Phase 4–7 logic.
Inside each slice-worktree, the `slice-builder` subagent invokes the existing
per-phase commands (`/craft:build`, `/craft:test`, `/craft:recap`,
`/craft:refactor`, `/craft:review`) in sequence. Each of those commands now carries
a `## Subagent Mode` section defining what it does when invoked by the slice-builder
rather than directly by a human: write `.craft/handoff.md` and pause (Phase 5,
refactor decisions, Heavy + needs-rethinking findings) or auto-draft
(Phase 6 recap). Reason: one canonical phase implementation, reused across manual
and automated runs — no drift between two code paths.

The workflow skill (`skills/workflow/SKILL.md`) carries the formal subagent-callable
contract and the `.craft/handoff.md` schema.

---

## 7. Carry-Over to Next Clusters

- **Plans are ephemeral**: fully decided (D7 + D8).
- **Universal slice definition (S8)**: resolved (D10/D11/D12).
- **Cross-slice memory (S9)**: resolved by D8.
- **S5, S10**: resolved by D13/D14.
- **C2 (mental overload)**: largely resolved by D15 (bundling + level mix).

### Still open

All clusters from the original inventory are resolved.

#### Parked for a future brainstorm thread
- **Capability / Personality Autoload** — where does the library of language/framework personalities live, how is it lazy-loaded, and does it introduce a third architectural tier between the plugin and project-local layers? Examples: "PHP general" vs. "PHP Symfony" vs. "PHP Laravel"; "Python general" vs. "Python Django" vs. "Python FastAPI". Likely needs composition/inheritance between personalities. Triggers: stack detection at `/prime`, explicit `/persona <name>`, or `intent.md`-declared default. Captured in [`plugin-architecture.md`](./plugin-architecture.md) Section 13 item 8.
