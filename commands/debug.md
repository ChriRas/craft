---
description: Bug verification protocol — 4 steps (ALIGN → PROTOCOL → AUTONOMOUS LOOP → ESCALATION). Auto-offered at ≥2 fix attempts on the same symptom. Uses skills/self-verify.
argument-hint: "<bug-description>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# /craft:debug — Bug Self-Verification

## Purpose

When the agent is cycling on a bug — or when the user reports one in Phase 5 — `/craft:debug` shifts verification responsibility from the human to the agent. It refuses to start the autonomous fix loop until a verification protocol has been agreed jointly.

Read `skills/self-verify/SKILL.md` for the full protocol. This command is the user-facing wrapper.

---

## Pre-flight

### 1. Locate active slice

- `Glob` `.claude/plans/*.md`. Pick the active slice. If multiple, ask which.
- If none → ask: *"No active slice. Is this a bug in a closed slice, or do we need to plan a new slice first?"* Bug fixes for closed slices may warrant their own slice.

### 2. Read project tooling

- `Read` `.claude/project/rules.md` for the test framework, lint, etc. — needed to compose verification commands.

### 3. Read self-verification settings

- Look for `## Self-Verification Settings` in `rules.md`. Override defaults if present:
  - `Max attempts:` (default 5)
  - `Auto-trigger threshold:` (default 2)
  - `Token brake during loop:` (default 15000)

---

## Procedure

The argument `<bug-description>` is the initial seed. If absent, ask: *"What is the bug? One sentence."*

Now run the four steps from `skills/self-verify/SKILL.md`.

### Step 1 — ALIGN (Autonomy Level 0)

Elicit, do not assume. Ask clarifying questions one at a time until you have:

- Expected behavior
- Actual behavior
- Reproduction steps (minimal)
- Scope (which slice, file, component)

Append to the slice plan under `## Bugs`:

```markdown
### Bug: <short identifier>
- **Expected:** <…>
- **Actual:** <…>
- **Reproduction:** <…>
- **Scope:** <…>
```

### Step 2 — PROTOCOL (Autonomy Level 0)

Propose a verification:

```
Verification proposal:
  Command: <exact command, e.g. `vendor/bin/pest tests/Feature/ReservationTest.php --filter=it_creates_reservation`>
  Expected on fix: <exact output line, exit code, or condition>
  Negative check: <exact command + expected output that must still hold, e.g. all other tests still green>
```

Wait for user confirmation. Adjust if user pushes back. Once confirmed, **freeze** it. Append to the slice plan under `## Verification Protocols`:

```markdown
### Verification: <bug identifier>
- **Command:** `<…>`
- **Expected on fix:** <…>
- **Negative check:** `<…>`
- **Frozen at:** <ISO date>
```

### Step 3 — AUTONOMOUS LOOP (Autonomy Level 2 + 15k-token brake)

Up to **max-attempts** (default 5):

For each attempt:

1. Hypothesize the cause in one line.
2. Apply the minimal code change.
3. Run the frozen verification command.
4. Run the frozen negative check.
5. Append the attempt log to the slice plan under `## Bug Fix Attempts`:

   ```markdown
   #### Attempt N (<ISO date>)
   - **Hypothesis:** <…>
   - **Change:** <one-line summary>
   - **Verification:** ✓ or ❌ — <output line>
   - **Negative check:** ✓ or ❌ — <output line>
   ```

6. Bundle to the user:

   ```
   Attempt N/<max>: changed <file>
     Verification: ❌ — <output snippet>
     Negative check: ✓
     Next hypothesis: <one-liner>
     [continuing in 3s — type 'pause' to stop]
   ```

**Exit conditions:**

- **Verification ✓ AND negative check ✓** → loop exits successfully, proceed to "On success" below.
- **Max attempts reached** → exit to Step 4 ESCALATION.
- **User interrupts** → pause cleanly; preserve the attempt log.

**Forbidden during the loop:**

- Modifying the frozen verification command or expected output.
- Editing files outside the slice scope without dropping to Level 1.
- Skipping the negative check.

### On success

Emit the fix summary:

```
✓ Bug fixed in <N> attempt(s).
   Verification: ✓
   Negative check: ✓
   Diff: <files changed>
```

Then offer regression test promotion:

> The verification command worked. Promote it to a permanent test in the regression suite?

If yes: write a new test using the verification command and expected output. Add a sub-task to the slice plan: `- [x] Regression test for <bug>` so Phase 8 commits it.

### Step 4 — ESCALATION (Autonomy Level 0)

If max attempts exhausted, emit the full log + options:

```
<max> attempts exhausted. Full log:

Attempt 1: <hypothesis> → ❌ (<reason>)
Attempt 2: <hypothesis> → ❌ (<reason>)
...

Suggested options:
 a) /craft:handoff — fresh-context restart with attempt summary preserved
 b) /craft:recap — step back; the bug may be a symptom of a deeper design issue
 c) Re-negotiate the verification protocol — it may be too strict or missing a case
 d) Take it manually — disable /craft:debug and continue in regular Phase 4
```

User picks. Do not pre-pick.

---

## Output Format

Bundles per attempt as shown in Step 3. Final block as shown in "On success" or "Step 4 ESCALATION".

---

## Error Handling

| Situation | Behavior |
|---|---|
| User refuses to agree on a verification protocol | Tell user: *"Without an agreed verification, this is regular Phase 4 work. Returning to /craft:execute."* and stop. |
| The verification command itself errors out (broken syntax, missing binary) | Surface the error, ask the user to repair the command before continuing. |
| User wants to "just try one more" after max attempts | Allow exactly one more attempt at Level 0 — explicit ask, explicit consent. Do not re-enter the autonomous loop. |
| The bug is actually in the test, not the code | Flag this explicitly; ask the user whether to fix the test or to re-negotiate the verification command. |

---

## What This Command Does NOT Do

- It does **not** decide whether a reported bug is worth fixing now vs. queueing. That's planning.
- It does **not** modify the frozen verification protocol mid-loop.
- It does **not** smuggle refactors into the bug fix. If a refactor would help, capture it for Phase 7 (or a future slice).
- It does **not** commit. Phase 8 / `/craft:commit` does, and the bug fix participates in the slice's commit set.
