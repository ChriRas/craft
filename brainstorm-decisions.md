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

#### Trigger
**Auto via SessionStart-Hook with opt-in marker.**
- If `.claude/project/intent.md` exists → hook fires `/prime` automatically.
- If not → hook shows a one-line nudge: "Project not onboarded — run `/onboard`."
- User can always re-invoke manually (e.g. after editing `rules.md`).

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

---

## 7. Carry-Over to Next Clusters

- **`prime` trigger mode** (auto vs. manual): still open — natural opener for the phase-navigation design.
- **Plans are ephemeral**: fully decided (D7 + D8).
- **Universal slice definition (S8)**: resolved (D10/D11/D12).
- **Cross-slice memory (S9)**: resolved by D8.
- **S5, S10**: resolved by D13/D14.
- **C2 (mental overload)**: largely resolved by D15 (bundling + level mix).

### Still open

All clusters from the original inventory are resolved.

#### Parked for a future brainstorm thread
- **Capability / Personality Autoload** — where does the library of language/framework personalities live, how is it lazy-loaded, and does it introduce a third architectural tier between the plugin and project-local layers? Examples: "PHP general" vs. "PHP Symfony" vs. "PHP Laravel"; "Python general" vs. "Python Django" vs. "Python FastAPI". Likely needs composition/inheritance between personalities. Triggers: stack detection at `/prime`, explicit `/persona <name>`, or `intent.md`-declared default. Captured in [`plugin-architecture.md`](./plugin-architecture.md) Section 13 item 8.
