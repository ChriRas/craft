---
name: debug
description: Bug verification protocol — four-step ALIGN → PROTOCOL → AUTONOMOUS LOOP → ESCALATION flow. Use this skill when the user types `/craft:debug`, when the user explicitly says "I have a bug", "let me debug X", "this is broken", or when the agent detects it has made 2 or more fix attempts on the same symptom within the active slice. Do NOT trigger on generic mentions of bugs in unrelated discussion (reading bug-related docs, theoretical talk).
argument-hint: "<bug-description>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:debug — Bug Self-Verification

## Pre-flight

When invoked as a slash command:

1. **Locate the active slice.** `Glob` `.claude/plans/slice-*.md`. Pick the active slice. If multiple, ask which.
   If none → ask: *"No active slice. Is this a bug in a closed slice, or do we need to plan a new slice first?"* Bug fixes for closed slices may warrant their own slice.

2. **Read project tooling.** `Read` `.claude/project/rules.md` for the test framework, lint commands, etc. — needed to compose verification commands.

3. **Read self-verification settings.** Look for `## Self-Verification Settings` in `rules.md`. Override defaults if present (see [Configurability](#configurability) below).

4. **Seed the bug description.** Use `$ARGUMENTS` as the initial bug description. If empty, ask: *"What is the bug? One sentence."*

When auto-triggered (≥2 fix attempts on the same symptom), skip step 4 — the symptom is already known from the active slice context.

---

## Purpose

This skill defines how the agent verifies that a bug fix actually works **without asking the user to test each attempt**. It prevents the most common failure mode of agent-driven debugging: the agent claims "fixed" based on incomplete signals, the user re-tests, the bug returns or surfaces as a different symptom, and the loop drags on.

The protocol shifts verification responsibility from the human to the agent — but **only after a verification criterion has been agreed jointly**, before any fix attempt is made. The agreement comes first; the autonomous loop comes second.

---

## When This Skill Runs

- **Manually**, when the user invokes `/craft:debug <description>`. The user knows it's a bug, not a feature.
- **Automatically**, when the agent detects it has made **≥2 fix attempts on the same symptom** within the active slice. The agent does not enter the protocol unilaterally — it asks: *"I notice I'm cycling on this. Should we enter `/craft:debug` mode?"*
- **Phase 5 cascade**: when the user reports `[B]` in Phase 5's structured feedback, `/craft:test` invokes `/craft:debug` and this skill runs.

The auto-trigger threshold (default `2`) and the maximum-attempts cap (default `5`) are **overridable per project** in `.claude/project/rules.md` under a *"Self-Verification Settings"* section.

---

## The Four-Step Protocol

### Step 1 — ALIGN (Autonomy Level 0)

The agent and user agree on what the bug actually is. The agent must elicit, not assume.

Required output of this step (recorded in the slice plan under `## Bugs`):

```markdown
### Bug: <short identifier>
- **Expected:** <what should happen>
- **Actual:** <what currently happens>
- **Reproduction:** <minimal steps>
- **Scope:** <which slice, which file/component if known>
```

The agent asks one clarifying question at a time, never bundles. If the user is vague ("the button doesn't work"), the agent probes ("Doesn't click at all? Clicks but no toast? Toast wrong text?"). No fix attempt is made in this step.

### Step 2 — PROTOCOL (Autonomy Level 0)

The agent proposes a **verification command + expected result + negative check**, and the user confirms before any code is touched. This is the most important step — without a frozen verification criterion, the autonomous loop in Step 3 is meaningless.

#### What makes a good verification protocol

1. **Concrete** — Yields a clear yes/no, not "looks better."
2. **Reproducible** — Same command, same expected output, every run.
3. **Pre-committed** — Frozen before fix attempts. Adjusting the protocol mid-loop to fit the failure is evidence-tampering and is explicitly forbidden.
4. **Bounded** — Tied to the specific bug; not "all tests pass" but "this specific test passes for this specific case."
5. **Has a negative check** — Confirms the fix didn't break something else nearby.

#### Required output of this step (appended to the slice plan under `## Verification Protocols`):

```markdown
### Verification: <bug identifier>
- **Command:** `<exact command to run, including arguments>`
- **Expected on fix:** <exact output line, exit code, or condition>
- **Negative check:** `<exact command + expected output that must still hold>`
- **Frozen at:** <ISO date>
```

The agent presents this draft, the user confirms or adjusts. Once confirmed, the protocol is frozen.

### Step 3 — AUTONOMOUS LOOP (Autonomy Level 2, token brake tightened to 15k)

The agent now runs autonomously, up to **5 attempts** by default.

For each attempt:

1. **Hypothesize** — Agent states the cause hypothesis in one line.
2. **Edit** — Apply the minimal code change implied by the hypothesis. Code edits inside the slice scope follow Level 2; edits outside (e.g., touching a shared util) drop to Level 1 and require explicit confirmation.
3. **Verify** — Run the frozen verification command. Capture command output exactly.
4. **Run the negative check** — Confirm nothing nearby broke.
5. **Log the attempt** — In the slice plan under `## Bug Fix Attempts`, format:

   ```markdown
   #### Attempt N (<ISO date>)
   - **Hypothesis:** ...
   - **Change:** <one-line summary of the edit>
   - **Verification:** ✓ or ❌ — <output line>
   - **Negative check:** ✓ or ❌ — <output line>
   ```

6. **Bundle output to user** at the end of each attempt:

   ```
   Attempt N/5: changed <file>
     Verification: ❌ — <output snippet>
     Negative check: ✓
     Next hypothesis: <one-liner>
     [continuing in 3s — type 'pause' to stop]
   ```

#### Loop exit conditions

- **Success** — Verification passes AND negative check passes. Agent exits the loop, reports the working fix with diff, and offers to promote the verification command to a permanent regression test (see below).
- **5 attempts exhausted** — Agent stops, transitions to Step 4.
- **User interrupts** — Any input during the auto-continue countdown pauses the loop. The user can ask for the attempt log, request a strategy change, or escalate.

#### Forbidden during the loop

- Modifying the verification command or expected output (evidence-tampering).
- Touching files outside the slice scope without explicit Level 1 confirmation.
- Skipping the negative check.

### Step 4 — ESCALATION (Autonomy Level 0)

If the loop exhausts its 5 attempts, the agent stops autonomous work and presents the full attempt log to the user. The escalation message is structured:

```
5 attempts exhausted. Full log:

Attempt 1: <hypothesis> → ❌ (<reason>)
Attempt 2: <hypothesis> → ❌ (<reason>)
Attempt 3: <hypothesis> → ❌ (<reason>)
Attempt 4: <hypothesis> → ❌ (<reason>)
Attempt 5: <hypothesis> → ❌ (<reason>)

Suggested options:
 a) /craft:handoff — fresh-context restart with attempt summary preserved
 b) /craft:recap — step back, the bug may be a symptom of a deeper design issue
 c) Re-negotiate the verification protocol — it may be too strict or missing a case
 d) Take it manually — disable /craft:debug mode and continue in regular Phase 4
```

The user picks. The agent does not pre-pick.

---

## Promotion to Regression Test

When the loop exits successfully, the agent proposes:

> "The verification command worked. Should I promote it to a permanent test in the regression suite? This converts the ad-hoc check into a test that runs every CI build."

User confirms `yes` or `no`. On `yes`, the agent:

1. Writes a new test in the project's test suite using the verification command and expected output.
2. Adds the test path to the slice plan under `## Sub-Tasks` as a check-marked item (so Phase 9 commit includes it).
3. Verifies the new test passes.

This converts each successfully debugged bug into a regression preventer — the codebase gets slightly more robust with every successful `/craft:debug` session.

---

## Commit Convention for Bug Fixes

Bug fix commits follow the standard plugin convention:

```
fix(<scope>): <one-line description>

<optional body — what was wrong, why this fix>

Slice: slice-NNN
```

If the regression test was added, it should be in the same commit or a separate `test(<scope>): add regression test for <bug>` commit, both with the same `Slice:` footer.

---

## Sister Command: /craft:handoff

When the loop fails and the user picks option `(a)`, `/craft:handoff` is invoked. That command is **not part of this skill** — it lives separately because it is also useful outside `/craft:debug` (any time context-poisoning suspected). What `/craft:handoff` does:

1. Reads the bug, the verification protocol, and the attempt log from the slice plan.
2. Writes a condensed handoff summary under `## Handoff` in the slice plan, including: "what tried, what didn't try, what was ruled out, what the verification protocol was."
3. Tells the user to start a fresh chat session.
4. On the next session start, `/craft:prime` reloads the slice plan; the fresh agent picks up the handoff section and continues with no context-poisoning.

---

## Configurability

The two key thresholds are project-overridable in `.claude/project/rules.md`:

```markdown
## Self-Verification Settings
- **Max attempts:** 5         # default; lower for token-conservative projects, higher for genuinely hard bugs
- **Auto-trigger threshold:** 2  # offer /craft:debug after this many fix attempts on same symptom
- **Token brake during loop:** 15000  # tighter than the 30k default for normal Phase 4
```

If absent, defaults apply.

---

## What This Skill Does NOT Cover

- **Bug discovery** (Phase 5 testing). That is handled by `/craft:test` and the workflow skill's Phase 5 mechanics.
- **Refactoring during a bug fix.** If a refactor would help, that is a separate slice unless the fix legitimately requires structural change. Don't smuggle refactors into bug fixes.
- **Bug *triage*** — deciding whether a reported bug is worth fixing right now vs. queuing. That is a planning decision, not a verification one.

---

## Discipline Summary

| Phase of the protocol | Discipline |
|---|---|
| ALIGN | Elicit, never assume. One question at a time. |
| PROTOCOL | Freeze before fixing. Negative check is mandatory. |
| LOOP | Autonomous but logged. Max 5 attempts. No protocol mutation. |
| ESCALATION | Present options, never pre-pick. |
| PROMOTION | Always offer regression-test promotion on success. |
