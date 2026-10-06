---
name: debug
description: Bug verification protocol — four-step ALIGN → PROTOCOL → AUTONOMOUS LOOP → ESCALATION flow. Use this skill when the user types `/craft:debug`, when the user explicitly says "I have a bug", "let me debug X", "this is broken", or when the agent detects it has made 2 or more fix attempts on the same symptom within the active slice. Do NOT trigger on generic mentions of bugs in unrelated discussion (reading bug-related docs, theoretical talk).
argument-hint: "<bug-description>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:debug — Bug Self-Verification

## Pre-flight

> **Ensure-primed gate** — before the steps below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

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

## Autonomous Mode (autopilot run)

Inside an autopilot run (`/craft:execute <epic-NNN> --autopilot`; the spawn says so) there is no human for ALIGN,
PROTOCOL or ESCALATION. This section is the **one** definition of how the four steps run there (slice-053);
`commands/build.md` and `commands/test.md` (Subagent Mode) enter it, and nothing else changes it. Outside an autopilot
run it never applies. The rule that replaces the human is D35's: **the verdict is `scripts/verify-run.sh`'s, never
the agent's** — an attempt has passed only when a helper round reads `pass`.

**Entry.** Two triggers, one loop:

- **Phase 4** — the builder is about to make a 2nd fix attempt on the same symptom (`commands/build.md` → Subagent
  Mode). The protocol does not exist yet; it is drafted and frozen by two agents (below).
- **Phase 5** — `verify-run.sh` reported `RESULT=fail` (a check failed or timed out; `commands/test.md` → Subagent Mode
  step 0a). The failed check (`FAILED=`) **is** the frozen protocol — committed with the Test Strategy before any code;
  the other checks are its negative check.

**No verify block, no autonomous mode.** A plan without a `<!-- craft:verify -->` block stops at once, at the entry's
end stop (below): its Phase 5 stops anyway, and a block holding only bug checks would turn that stop into a pass.

1. **ALIGN** — the agent writes the `## Bugs` entry itself (Expected / Actual / Reproduction / Scope, as Step 1), from
   the recurring symptom (Phase 4) or the failed check's evidence round (Phase 5), and adds
   `- **Aligned by:** slice-builder (autopilot — no human ALIGN)`.
2. **PROTOCOL** — Phase 5 skips this step. Phase 4: draft the protocol as verify-block lines in the grammar of
   `scripts/verify-run.sh` (its header): one or more checks that fail today and pass only when the bug
   is fixed (`- check bug-<id>-<n> :: …`) and at least one negative check that passes today and must still pass after
   the fix (`- check bug-<id>-neg-<n> :: …`). `<id>` is lower-case `[a-z0-9-]`, `<n>` counts from 1, and no name may
   already be in the block — an unparseable or duplicate line makes the whole block malformed, and it can never be
   removed again (below). Before asking anyone, judge each draft command with
   `bash "<plugin-root>/scripts/permission-rule-match.sh" --project "<project-root>" --command "$CMD"`, where `CMD` holds
   the command byte-exact (read it from a quoted heredoc, `CMD=$(cat <<'EOF' … EOF)`, so its own quotes survive):
   anything but `MATCH=no` would be refused later — redraft it. Then **freeze by two agents**: spawn `code-reviewer` with its
   **Protocol Freeze** brief (`agents/code-reviewer.md`) — the `## Bugs` entry, the draft lines, the plan's Test
   Strategy and the diff so far. Before spawning, settle the reviewer's model: follow `model-defaults.md` →
   **Spawn-Reachable Values** → *What a spawn site must do*, for the agent `code-reviewer`; it is defined once, there.
   **If that file cannot be resolved** — neither `<plugin-root>/model-defaults.md` nor `<project-root>/model-defaults.md`
   exists — spawn `code-reviewer` with **no** `model` parameter, and emit `⚠ Could not read model-defaults.md —
   spawning code-reviewer without a model; a project override, if any, was dropped.` (This sentence is not a copy of
   that procedure: it is the one case its pointer cannot deliver — B-R7-1.) Only on `freeze`: append the lines to the
   plan's verify block (after its last check, no line between) and record the protocol under
   `## Verification Protocols` as Step 2 does, naming the check lines, with
   `- **Frozen by:** slice-builder + code-reviewer (autopilot), <ISO date>` in place of Step 2's `Frozen at:`. On
   `reject: <why>`, redraft once against the reason and ask again; a second `reject` is the end stop — a rejected draft
   is written nowhere but the Pause Note. **Then the red baseline, by the helper:** run the Phase-4 command of step 3
   once with every protocol name, before any attempt. Its `FAILED=` must name exactly the `bug-…` checks and no
   `-neg-` check — a bug check that already passes would let any attempt "pass", and a failing negative check guards
   nothing. Anything else is the end stop, and the package names that round.
3. **LOOP** — as Step 3, up to *Max attempts* (`rules.md` → Self-Verification Settings), token brake 15k. Before each
   attempt the builder runs its budget guard (`agents/slice-builder.md` → *The budget guard*); a budget stop leaves
   the frozen protocol and the attempts so far in the plan. A re-spawned builder does **not** resume this loop: when
   the symptom returns it enters this mode afresh, and *Max attempts* counts again from 1 — a known limit
   (slice-058, follow-up). Between
   attempts the builder may run the protocol's commands itself to explore; only the helper ends an attempt:
   - Phase 4: `bash "<plugin-root>/scripts/verify-run.sh" --project "<project-root>" --only <protocol check names> <plan>`;
   - Phase 5: the same without `--only` — the whole block.

   Each attempt's `## Bug Fix Attempts` entry (Step 3's format) carries, instead of the agent's own ✓ / ❌, the line
   `- **Verdict:** verify-run.sh round <ROUND> — <RESULT>`. `RESULT=pass` ends the loop: Phase 4 returns to the
   sub-task being built, Phase 5 returns to step 0a's pass branch. `RESULT=fail` → the next attempt. `RESULT=refused`
   or a malformed block is no bug to fix → the end stop at once.
4. **End stop** (replaces ESCALATION) — the attempts are exhausted, the protocol was rejected twice, the red baseline
   was not the expected one, the helper refused or found the block malformed, or (Phase 4) there is no verify block. Stop at the entry's pause — Phase 4: `commands/build.md`'s `awaiting-protocol`; Phase 5:
   `commands/test.md`'s `awaiting-test` — with an **escalation package of at most 15 lines** in the Pause Note: the
   bug; the protocol's check names and where they live (`frozen checks in the verify block: <names> — yours to keep,
   replace or remove`, or the committed check that failed); one line per attempt (hypothesis → round, result); the last
   evidence round; and the options on the resume path — resume with `/craft:continue` and fix it in `/craft:build` /
   `/craft:test`, re-negotiate the protocol in an interactive `/craft:debug` (its verify lines included), or
   `/craft:handoff` for a fresh context. The human picks; the agent does not pre-pick.

**Forbidden in this mode**, in addition to Step 3's list: editing, removing or reordering any check line of the verify
block — a committed Test Strategy check or a frozen protocol line —; editing, for the loop's duration, any file that verifies
rather than is verified — a check's test, harness, fixture or verification script (in this repo `scripts/test-*.sh`);
the code under test is not frozen, even when a check's command runs it directly (`bash greet.sh`), because that is where
the fix goes; and
writing a `## Verification Evidence` round by hand. All three are evidence-tampering. A check the agent believes wrong
is the end stop — the human re-negotiates it — never an edit; this overrides the Senior-Developer Problem-Playbook's
"adapt the test and record why" inside this mode. **Promotion to a regression test** needs no question here: a frozen protocol's
lines stay in the verify block, so every later Phase-5 run checks the bug again.

**Meeting it interactively.** An interactive `/craft:debug` on a plan this mode stopped finds the `## Bugs` entry
(`Aligned by: slice-builder`), the attempts, and — from Phase 4 — a frozen protocol whose `bug-…` lines sit in the
verify block. ALIGN starts from that entry instead of from scratch, and a re-negotiated protocol is the human's to
write, **verify lines included**: replace or remove the old ones, or the next autopilot Phase 5 fails on them again.

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
| AUTOPILOT | Two agents freeze, the helper judges, the human gets the end stop. (Autonomous Mode) |
