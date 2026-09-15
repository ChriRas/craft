---
description: Resume work on an active slice. Routes automatically to the right phase command based on the slice's recorded Status. Use after /craft:prime when picking up where you left off.
argument-hint: "[slice-NNN]"
allowed-tools: ["Read", "Glob", "Edit"]
---

# /craft:continue — Resume an Active Slice

## Purpose

Pick up work on an open slice without re-thinking the entry point. Reads the slice plan, identifies the current phase, and recommends or routes to the corresponding command.

Its one write is the **resume of a `paused` slice** (step 4a): the confirmed resume moves the plan off `paused`, which is what tells a waiting handoff marker that the human has answered.

`/craft:continue` is the navigation glue between `/craft:prime` (orient) and the phase commands (act).

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

- `Read` the project knowledge files quickly to confirm onboarding (`.claude/project/intent.md`, `.claude/project/rules.md`). If missing, tell user to run `/craft:onboard` and stop.

---

## Procedure

### 1. Identify the target slice

- If `<slice-NNN>` argument is given, find `.claude/plans/slice-<NNN>-*.md`.
- Otherwise, `Glob` `.claude/plans/*.md`:
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
| `review` (Phase 5 passed, Phase 6 not yet run) | `/craft:recap` — Phase 5 approved the artifact, so the slice moves **forward** into Phase 6. Offer `/craft:test` only to re-demo on request; never route backwards by default. Route to `/craft:recap` **in both Phase-7 configurations**, even when the plan already carries a filled `## Recap Draft`: `review` is an *advisory* status for `/craft:review` (see `commands/review.md`), so routing there directly would leave Commit ungated — the exact failure this slice fixes. `/craft:recap` accepts a `review` slice, revises an existing draft, and writes the status the project's Phase-7 setting calls for. |
| `refactoring` | `/craft:refactor` |
| `reviewing` | `/craft:review` |
| `committing` | `/craft:commit` |
| `blocked` | `/craft:unblock` — the slice is blocked on a prerequisite or decision; `/craft:unblock` presents the resume / re-plan / abort fork and restores the recorded `Blocked-status`. (A `prerequisite-work` block also auto-resurfaces when its prerequisite closes via `/craft:commit`.) |
| `awaiting-release` | `/craft:release` — the in-place review halt (built in place, paused before Phase 5); review the raw diff in your IDE, then release to resume into Phase 5 |
| `awaiting-approval` | `/craft:commit` — a protected-main PR is open and waiting; approve it on GitHub, then re-run `/craft:commit` to merge via `gh`. **Sequential-epic slice** (an active `epic-<NNN>` plan lists it in `## Slice Decomposition` under an `Epic Mode: sequential` + protected-main profile): re-run `/craft:execute <epic-NNN>` instead — its `s0` merges this slice and continues the epic. |
| `committed` | this slice is done — recommend `/craft:plan` for the next one |
| `paused` | ask whether to resume; if yes, **resume** it (step 4a) and route by the restored status <!-- craft:reads status=paused --> |
| any unrecognized value | log warning, ask the user what to do |

### 4. Handle pause and handoff

- If the slice plan has a `## Handoff` section that was filled (i.e., this is a fresh-context restart) → show its summary to the user and route based on `Phase`.
- If the slice is at `Status: paused`, surface its `## Pause Note` and ask whether the user wants to continue from that point. A Pause Note on a slice at any other status is history (marked `> Resumed:` or `> Superseded by block:`) — never a reason to resume.
- If the slice is `blocked`, surface its `## Blocker` section (what's missing / resume acceptance) and route to `/craft:unblock` — do not mutate here; unblocking is that command's job.

### 4a. Resume a paused slice

The **one** definition of moving a plan off `paused` (`skills/workflow/SKILL.md` → **Pause record**). `/craft:build`
runs it on a `paused` plan; the phase commands that refuse one point here. It runs **only when `Status:` is `paused`**,
and only on the user's yes in step 3/4; a no leaves the plan untouched.

1. **Where** — edit the plan in the checkout this command runs in. For a slice built in a worktree that is the slice
   worktree (reach it with `/craft:checkout`): its plan copy is the one the handoff marker is judged against.
2. **What to restore** — the pause record's `Paused-status:`, when it holds a status other than `paused` or `blocked`.
   A plan without a record (paused before B11), or with such a value, has no structured answer: **ask** the user which
   status to resume into — offer `implementing`, `testing`, `review`, `refactoring`, `reviewing`, `committing` and
   propose a default read from the `## Pause Note`. Never guess from `Phase:` (a plan-time stamp that reads stale).
   Note the record's `Paused-since` too — step 5 needs it after step 3 removes the record.
3. **Write** — set `Status:` to that value and remove the two pause-record fields (`Paused-status`, `Paused-since`).
   Keep `## Pause Note` as history, with `> Resumed: <ISO datetime> → <status>` prepended. A handoff marker written with the pause is now stale by derivation — rename
   nothing (`skills/workflow/SKILL.md` → **Handoff marker lifecycle**).
4. **Check** — `Read` the plan back: `Status:` must equal the restored value and neither field may remain. On a
   mismatch warn loudly (*"⚠ Resume not written as intended in `<path>` — inspect before continuing"*) and stop.
5. **Say what the resume does not do** — only when a handoff marker belongs to **this** pause: `Read`
   `.craft/handoff.md` in this checkout; it belongs when its frontmatter `Episode:` equals the `Paused-since` noted in
   step 2, or — a marker written before B11 — it has no `Episode:` and its `Status:` is one the lifecycle table
   (`skills/workflow/SKILL.md` → **Handoff marker lifecycle**) pairs with `paused`. Then the resume records **no
   answer** to the question the handoff asked (a scope decision, a protocol, a refactor pick): carry the warning in the
   output block (Output Format). No marker, or one from another episode (an old, never-renamed marker) → no warning.
6. **Route** — continue with step 5 using the restored status's row in step 3.

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
[After a resume (step 4a): Resumed: paused → <status>]
[Only after a handoff's pause (4a step 5): ⚠ Resume records no answer — give it by running the recommended command interactively; a subagent re-run would meet the same question again.]

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
- It does **not** modify the slice plan — except the confirmed resume of a `paused` slice (step 4a).
- It does **not** otherwise change `Status` (the phase command itself does that when it actually starts work). A
  `blocked` slice is resumed by `/craft:unblock`, never here.
