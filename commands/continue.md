---
description: Resume work on an active slice. Routes automatically to the right phase command based on the slice's recorded Status. Use after /craft:prime when picking up where you left off.
argument-hint: "[slice-NNN]"
allowed-tools: ["Read", "Glob"]
---

# /craft:continue — Resume an Active Slice

## Purpose

Pick up work on an open slice without re-thinking the entry point. Reads the slice plan, identifies the current phase, and recommends or routes to the corresponding command.

`/craft:continue` is the navigation glue between `/craft:prime` (orient) and the phase commands (act).

---

## Pre-flight

- `Read` the project knowledge files quickly to confirm onboarding (`.claude/project/intent.md`, `.claude/project/rules.md`). If missing, tell user to run `/craft:onboard` and stop.

---

## Procedure

### 1. Identify the target slice

- If `<slice-NNN>` argument is given, find `.claude/craft:plans/slice-<NNN>-*.md`.
- Otherwise, `Glob` `.claude/craft:plans/*.md`:
  - If exactly one file → use it.
  - If multiple → list them and ask the user to pick:

    ```
    Multiple active slices. Pick one:
      → slice-007 "PWA reservation button" — Phase 4, 3/7 sub-tasks done
      → slice-009 "Email confirmation" — Phase 3, planning
    Type slice number to continue.
    ```

  - If none → tell user `No active slices. Run /craft:plan <feature> to start one.` and stop.

### 2. Read slice frontmatter

Pull `Status`, `Phase`, `Slice-ID`, and any pause/handoff notes.

### 3. Route by Status

| Status | Recommended next |
|---|---|
| `planning` | `/craft:plan` (to finish planning) — or `/craft:build` if planning is actually done |
| `implementing` | `/craft:build` |
| `testing` | `/craft:test` |
| `review` (Phase 5 between iterations) | `/craft:test` to re-demo or `/craft:recap` if approved |
| `refactoring` | `/craft:refactor` |
| `reviewing` | `/craft:review` |
| `committing` | `/craft:commit` |
| `committed` | this slice is done — recommend `/craft:plan` for the next one |
| `paused` | ask whether to resume; if yes, route based on the `Phase:` field |
| any unrecognized value | log warning, ask the user what to do |

### 4. Handle pause and handoff

- If the slice plan has a `## Handoff` section that was filled (i.e., this is a fresh-context restart) → show its summary to the user and route based on `Phase`.
- If the slice was paused with a `## Pause Note`, surface that note and ask whether the user wants to continue from that point.

### 5. Emit recommendation, do not auto-invoke

`/craft:continue` recommends but does not run the phase command automatically. The user types the actual command (`/craft:build`, `/craft:test`, etc.). This preserves the user's choice to take a different path (e.g., re-plan, abort).

---

## Output Format

```
Continuing slice-<NNN> "<title>"
  Phase: <X>
  Status: <status>
  Progress: <Y>/<Z> sub-tasks done
  Started: <K> days ago

[If Handoff or Pause Note present, show 2–3 line excerpt]

Recommended next: /<phase-command>
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Slice file specified by argument not found | List the actually-active slices, ask user to choose. |
| Slice file unreadable / malformed frontmatter | Tell user, ask whether to repair manually or `/craft:abort`. |
| Slice status is `committed` | Tell user that slice is closed and recommend `/craft:plan`. |

---

## What This Command Does NOT Do

- It does **not** execute any phase work directly.
- It does **not** modify the slice plan.
- It does **not** change `Status` (the phase command itself does that when it actually starts work).
