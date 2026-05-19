---
name: craft
description: State-aware entry point for the CRAFT workflow. When invoked as /craft, detect whether the current project is onboarded, whether any slices are in progress, and offer the user the actions valid for that state. Does not execute sub-actions itself — only orients and recommends.
user-invocable: true
allowed-tools: ["Read", "Glob", "Bash"]
---

# /craft — State-Aware Entry Point

This skill is the single user-facing entry to the CRAFT plugin. The plugin name (`craft`) equals the skill name (`craft`), so Claude Code's namespace collapse exposes this skill as `/craft` (mirrors the `/context-mode` pattern).

**Spike status (2026-05-19):** This is the first iteration. Three open validations from `brainstorm-decisions.md` D23 are tested by this skill's behavior at runtime — see the "Validation probes" section at the bottom. After validation, expand or simplify the skill accordingly.

---

## What This Skill Does on Invocation

Detect project state, then present a single state-dependent menu of valid actions. **Do not execute the chosen action** — recommend it; the user types the corresponding `/craft:<name>` command. This preserves Human-Control: every state transition is an explicit user step.

---

## Procedure

### Step 1 — Detect state

Run these checks, in order:

1. **Onboarded?** `Read` `.claude/project/intent.md`. If the file does not exist or is empty → state is `not-onboarded`. Skip to Step 2.
2. **Active slices?** `Glob` `.claude/plans/slice-*.md`.
   - Zero matches → state is `onboarded-idle`.
   - One or more matches → state is `active-slice`. Also collect per-slice metadata:
     - `Slice-ID`, `Status`, `Phase`, `Started` (from frontmatter)
     - Stale flag — slice `Started` older than **7 days** (override in `.claude/project/rules.md` under `## Self-Verification Settings → Stale slice threshold`).
3. **Pending handoff?** For each active slice, check if its frontmatter contains `Handoff active: yes`. If so, the state qualifier is `active-slice-with-handoff`.

### Step 2 — Emit the state report + action menu

Format the output as a compact block. Pick the menu shape based on the detected state:

#### State: `not-onboarded`

```
CRAFT — project state: not onboarded

No .claude/project/intent.md found. Craft is not initialized in this project.

Available action:
  → /craft:onboard — set up project knowledge (intent.md, rules.md)

Run /craft:onboard if you want to adopt the 8-phase workflow here.
```

No other commands are offered. The user opts in by running `/craft:onboard` themselves — consistent with the no-nudge policy.

#### State: `onboarded-idle`

```
CRAFT — project state: onboarded, no active slices

Project: <name from intent.md if discoverable, else current dir>
Stack:   <one-line summary from rules.md if discoverable>

Available actions:
  → /craft:plan <feature>   — start a new vertical slice (Phase 3)
  → /craft:status            — show project status without re-priming
  → /craft:intent-update     — revise intent.md
  → /craft:prime             — reload full project context (rules ↔ state drift check)
```

The recommendation order is intentional: planning is the most common next step after `onboard` or after a finished slice.

#### State: `active-slice`

```
CRAFT — project state: <N> active slice(s)

  → slice-NNN "<title>" — Phase <X>, <Y>/<Z> sub-tasks done, started <K> days ago
  → slice-MMM "<title>" — Phase <X>, <Y>/<Z> sub-tasks done, started <K> days ago
  [⚠ slice-PPP untouched for <K> days — stale]

Available actions:
  → /craft:continue [slice-NNN]  — resume work (defaults to single active slice)
  → /craft:status                 — refresh the slice list
  → /craft:pause                  — pause the active slice cleanly
  → /craft:abort <slice-NNN>      — abandon a slice (destructive)
  → /craft:plan <feature>         — start an additional parallel slice
  [If stale slice present:]
  → resolve the stale slice first — /craft:continue or /craft:abort
```

#### State: `active-slice-with-handoff`

```
⚠ Handoff waiting for slice-NNN — a previous session ended with /craft:handoff.

Recommended next:
  → /craft:continue slice-NNN  — the handoff summary will be loaded

Other available actions:
  → /craft:status               — see all active slices
  → /craft:abort slice-NNN      — discard if the handoff is no longer relevant
```

The handoff state takes precedence over the generic active-slice menu — it's a signal the user should address before anything else.

### Step 3 — Stop

Do not invoke any sub-command. The user reads the menu and types one of the offered commands. `/craft` is dispatch, not execution.

---

## Output Discipline

- Keep the block under **20 lines** for any state. If many active slices would exceed this, collapse older ones: `+ 4 more slices (run /craft:status for full list)`.
- Do not include the tool-health check or full drift check that `/craft:prime` performs — `/craft` is lightweight orientation, not a full priming. Recommend `/craft:prime` if drift validation is needed.
- Never mutate any file in this skill. Read-only.

---

## Error Handling

| Situation | Behavior |
|---|---|
| `.claude/project/` exists but `intent.md` is missing while `rules.md` exists | Treat as `not-onboarded` but warn: *"⚠ Inconsistent onboarding — rules.md exists without intent.md. Run /craft:onboard to repair."* |
| `.claude/plans/` exists but contains no `slice-*.md` files (only `.next-id` or stale subdirs) | Treat as `onboarded-idle`. |
| A slice plan file is unreadable or has malformed frontmatter | Log `⚠ slice plan <file> unreadable — skipping` and continue with the others. |
| Filesystem read fails (e.g., outside any directory) | Output `⚠ Could not detect project state from <cwd>. Are you inside a project directory?` and stop. |

---

## What This Skill Does NOT Do

- It does **not** run `/craft:prime`. Priming is a separate, heavier check the user invokes explicitly when needed.
- It does **not** start any phase, modify files, or commit anything.
- It does **not** auto-trigger from keywords. For the Spike, activation is only via the explicit `/craft` invocation. Description-based auto-trigger may be added later if it proves useful.
- It does **not** accept arguments. `/craft` is a no-arg dispatcher. If the user passes arguments by accident, ignore them silently and emit the menu anyway. (Validation probe — see below.)

---

## Validation probes (Spike-only — D23 open questions)

The following observations should be captured during the first real-world invocations and reported back to the brainstorm thread before the skill is treated as stable.

### Probe 1 — `$ARGUMENTS` substitution in skills

If the user invokes `/craft something extra`, observe whether the literal text `something extra` is accessible inside this skill's execution context as `$ARGUMENTS` (analogous to commands).

**To probe:** When invoked, also emit a single hidden diagnostic line **only if the user passed unexpected text after `/craft`**:

```
[spike] received trailing input: "<the trailing text>" — ignored by /craft, but logged here so we can verify how skills receive arguments
```

If the trailing text appears verbatim, `$ARGUMENTS` (or its equivalent) works in skills. If only a generic placeholder appears, skills receive arguments differently than commands.

### Probe 2 — Bash / Read at skill invocation

This skill uses `Read`, `Glob`, and (implicitly) Bash via the `allowed-tools` frontmatter. Successful execution of Step 1 (state detection) is itself the validation: if the skill can read `intent.md` and glob `.claude/plans/`, then skills can perform filesystem operations equivalent to commands.

**To probe:** Simply run `/craft` in a Craft-onboarded project and observe whether the state menu is correctly emitted (not a placeholder). Success = probe passed.

### Probe 3 — Skill vs. project-local shim conflict

The user-global shims have already been removed (Part B). To probe behavior on conflict, deliberately create a temporary `~/.claude/commands/craft.md` with body `/craft:status` (a different action), then invoke `/craft`.

**Expected outcomes:**
- If the project-local command wins (Claude Code precedence), `/craft` will run `/craft:status` instead of this skill — the skill is shadowed.
- If the skill wins, this skill runs as designed and the shim is inert.

After observation, delete the temporary shim. **Do not leave it in place** — it would defeat the single-entry-point design.

---

## Forward path after the Spike

Once the three probes are answered:

- If all green → expand this skill: add tool-health quick-check, support a tighter menu rendering, consider Description-trigger keywords for auto-activation in conversational contexts ("where am I?", "what's next?").
- If Probe 2 fails (Bash/Read not allowed in skills at invocation time) → fall back: keep `/craft` as a thin command (`commands/craft.md`) and accept the lost namespace collapse.
- If Probe 3 reveals unexpected precedence → document the behavior in the README install section.

This skill is intentionally minimal — no decoration, no logic that cannot be removed if a probe fails.
