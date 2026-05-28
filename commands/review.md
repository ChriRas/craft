---
description: Phase 8 — independent fresh-eyes code review of the slice. A subagent with a clean context window classifies findings on the severity × fix-nature rubric; bounded local edits are fixed in-phase, the rest escalate, and Commit is gated until heavy needs-rethinking findings are resolved.
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Task"]
---

# /craft:review — Phase 8 Code Review

## Purpose

An independent, fresh-eyes review of the artifact that will actually be committed. Review runs *after* Refactor so it sees the real shipped delta. A subagent with a clean context window does the reviewing — four-eyes independence comes from the fresh window, not from blinding the reviewer.

Phase 8 both **finds and fixes**: bounded local edits are resolved here, anything that needs rethinking escalates, and Commit (Phase 9) is gated until every heavy needs-rethinking finding is resolved.

Follow `skills/workflow/SKILL.md` Phase 8 mechanics — in particular the findings rubric, the soft fix cap, and the autonomy profile.

---

## Pre-flight

### 1. Locate the active slice

- `Glob` `.claude/plans/*.md`.
- If multiple slices → ask the user which one to review.
- If none → stop with `No active slice to review. Run /craft:refactor first, or /craft:plan to start one.`

### 2. Determine the mode

`/craft:review` runs in one of two modes, decided by the slice's `Status:`:

- **Phase-8 mode** — `Status:` is `refactoring`, `reviewing`, or `committing` (the slice has reached the review phase). Full review: classify, fix bounded local edits in-phase, escalate the rest, gate Commit. Update `Status: reviewing` if not already.
- **Advisory mode** — `Status:` is any earlier value (`planning`, `implementing`, `testing`, `review`). This is an ad-hoc mid-flow review — the large-slice escape hatch. It **produces findings only**: it fixes nothing, writes no in-phase edits, and changes no `Status:`. Tell the user: `Ad-hoc advisory review — findings only, no fixes, no phase change.`

### 3. Load the declared stack-pack

Review is code-near work, so it loads the project's stack-pack the same way `/craft:build` and `/craft:refactor` do. `Read` the `## Personality` section of `.claude/project/rules.md`:

- If it declares a `Stack-Pack:` other than `none`, resolve the pack — `skills/<name>/SKILL.md` (plugin-shipped) or `~/.claude/craft-personalities/<name>/SKILL.md` (user-added). If found, `Read` it (and its `references/` files as the work needs) and emit `✓ Stack-pack loaded: <name>`.
- If a pack is declared but the file cannot be found, emit `⚠ Stack-pack <name> declared but not found — reviewing on the Senior-Developer baseline only` and continue.
- If no pack is declared (`none`, or no `## Personality` section), proceed on the Senior-Developer baseline alone — no stack-pack line.

---

## Procedure (Autonomy Level 1)

### Step 1 — Assemble the review brief

Gather everything the fresh review agent needs to judge the slice. Do not summarize away detail — the subagent has its own clean window:

- the **Senior-Developer baseline** — `skills/senior-developer/SKILL.md`;
- the **stack-pack** loaded in Pre-flight step 3 (if any);
- the **slice plan** (Goal, Trigger, Effect, Test Strategy, Sub-Tasks, Decisions) and `.claude/project/intent.md`;
- **all prior slice archives** under `.claude/project/slices/` — the decision history, so the reviewer can catch a *silent revocation* of an earlier decision;
- the **diff under review** — `git diff HEAD` for the slice's uncommitted Phase-4 / Phase-7 changes (Commit is Phase 9, so the slice delta is still in the working tree);
- the **Phase-6 Recap** — the slice plan's `## Recap Draft`, the developer's what/why "thinking trace", playing the role of a human PR description;
- the project's **comment language** — the `Comments` key of the `## Operational Language` block in `rules.md` (default English when absent). The reviewer flags code comments not written in this language as a Light finding;
- the **findings rubric** (Step 2).

### Step 2 — Run the review subagent (fresh context window)

Launch the **`code-reviewer`** subagent via the `Task` tool with `subagent_type: "code-reviewer"`. The named agent is pinned at `model: opus` for review-grade judgment (see `model-defaults.md`); a clean context window is the source of independence. Hand it the review brief from Step 1 and the rubric below. The agent classifies — it does not edit — and returns a structured findings list; the parent command applies fixes.

If a project has overridden `code-reviewer` in `.claude/project/rules.md` → `## Agent Model Overrides`, the override's model is used instead. `/craft:prime` reports the effective value.

#### Findings rubric — two orthogonal axes

- **Severity** — must this be resolved before Commit?
  - *Heavy*: architecture violation, security issue, a test that passes but is task-wise wrong (a misunderstanding), silent revocation of a prior decision not deliberately replaced by this slice.
  - *Light*: code style, a small missing test case, cosmetics.
- **Fix-nature** — where is it resolved?
  - *Local edit*: a paged-in developer could finish it in ~half an hour — a one-liner, a missing test case, style.
  - *Needs rethinking*: genuinely wrong; the original developer must reconsider it with the reviewer's notes. Fix-nature is "edit vs. rethink", not "small vs. large" — a task-wrong test is a tiny edit but still needs rethinking, because it is a misunderstanding.

| | Local edit | Needs rethinking |
|---|---|---|
| **Heavy** | fixed in Phase 8 | **escalated — blocks Commit** |
| **Light** | fixed in Phase 8 | recorded as a **follow-up** — Commit proceeds |

Each returned finding carries: `Severity` (Heavy/Light), `Fix-nature` (Local/Rethink), a `description`, and — for local edits — a concrete fix suggestion.

### Step 3 — Present the findings

Show the user the findings list grouped by the four rubric cells, with a one-line count summary. No fixes yet.

### Step 4 — Apply in-phase fixes (Level 2)

For every **local-edit** finding (Heavy or Light), apply the fix, then run the project's tests (Level 3, silent unless red). Bundle the fixes:

```
✓ In-phase fix <N>/<M>: <description>
   Changed: <files>
   Tests: <status>
```

**Soft volume cap.** The cap is `Review in-phase fix cap` in `rules.md` `## Self-Verification Settings` (default **5**). Once the number of in-phase fixes reaches the cap, **stop** and recommend (Level 1):

> Review in-phase fix cap (<N>) reached — <K> local-edit findings still open. Many small fixes sum to a large unreviewed delta. Recommend escalating the remaining batch (loop back to Phase 4) rather than fixing it here.

The cap is a recommendation, not a hard block — the user may waive it.

In **advisory mode**, skip this step: report local-edit findings as suggestions, apply nothing.

### Step 5 — Handle escalations (Level 1)

- **Heavy + needs-rethinking** — never fixed here. For each, recommend one of two routes and let the user choose:
  - *loop back to Phase 4* (`/craft:build`) — the fix belongs in this slice's scope;
  - *spin off a new slice* (`/craft:plan`) — it is genuinely separate work.
  These findings **block Commit** (Step 7).
- **Light + needs-rethinking** — recorded as a **follow-up**. Commit proceeds; the follow-up lands in the slice archive's `## Follow-ups` section at Phase 9.

In advisory mode, present both as recommendations only — no phase routing, no `Status:` change.

### Step 6 — Write the findings record

Write every finding to the slice plan's `## Review Findings` section — the audit trail. One line per finding:

```
- Heavy · Local   · <description> · fixed in-phase
- Light · Rethink · <description> · follow-up → slice archive
- Heavy · Rethink · <description> · escalated → Phase 4 loop-back
```

If the slice plan has no `## Review Findings` section yet, append one.

### Step 7 — Gate or clear

- **Advisory mode** — stop. Emit the findings report; do not touch `Status:`.
- **Phase-8 mode** —
  - If any **Heavy + needs-rethinking** finding is open → Commit is **blocked**. Leave `Status: reviewing`. Emit the blocking finding(s) and the chosen route(s). The slice may not close until they are resolved and re-reviewed.
  - If none → the review is **clear**. Update `Status: committing` and emit `Recommended next: /craft:commit`.

---

## Output Format

Phase-8 mode, clear:

```
Phase 8 — Review (clear)

Findings: <H> heavy, <L> light
  In-phase fixes applied: <N>
  Follow-ups recorded: <N>
Tests: <status>

✓ No Commit-blocking findings. Status: committing.
Recommended next: /craft:commit
```

Phase-8 mode, blocked:

```
⚠ Phase 8 — Review (Commit blocked)

Findings: <H> heavy, <L> light
  In-phase fixes applied: <N>
  Heavy + needs-rethinking (blocking): <N>
    - <description> → <loop-back to Phase 4 | new slice>

Status stays `reviewing` — resolve the blocking finding(s) before Commit.
Recommended next: /craft:build  (or /craft:plan for a spun-off slice)
```

Advisory mode:

```
Ad-hoc advisory review — findings only

Findings: <H> heavy, <L> light  (<N> local-edit, <N> needs-rethinking)
[grouped findings list]

No fixes applied, no phase change. Fold these into your ongoing work.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| No active slice plan | Stop; recommend `/craft:refactor` or `/craft:plan`. |
| Multiple active slices | Ask the user which slice to review. |
| `git diff HEAD` is empty (no slice delta) | Tell the user there is nothing to review; recommend confirming Phase 4 actually ran. |
| The review subagent returns no structured findings | Re-run once with the rubric restated; if still unstructured, present the raw output and ask the user to classify. |
| A test turns red after an in-phase fix | Treat it like any Phase-4 fix: one fix attempt; if still red, offer `/craft:debug`. Do not leave the tree red. |
| In-phase fixes reach the soft cap | Stop fixing; recommend escalating the remaining batch (Step 4). Not a hard block. |
| User waives the soft cap | Continue fixing, but note in `## Review Findings` that the cap was waived. |
| `## Review Findings` section missing from the slice plan | Append the section, then write the findings into it. |

---

## Subagent Mode (when called by `/craft:execute`)

`/craft:review` already runs its core work in a fresh-context subagent (the reviewer). When `/craft:review` itself is invoked by the `slice-builder` subagent during an autonomous run, that becomes a sub-subagent — supported.

Behavior in this mode:

- Steps 1–6 run normally; findings are classified and written to the slice plan's `## Review Findings`.
- Step 4 (in-phase fix application) runs — fixing local-edit findings is mechanical and safe to automate.
- Step 5 — **Heavy + needs-rethinking** findings do **not** prompt the user. They are written to `.craft/handoff.md` with `Status: awaiting-rethink-decision` plus the recommended route (loop-back or new slice) for each. The slice is paused for human resolution at `/craft:checkout` time.
- Soft-cap breach (Step 4) → same handoff path: marker written, slice paused.

The reviewer subagent itself never makes routing decisions; routing is always human-confirmed.

---

## What This Command Does NOT Do

- It does **not** commit. Phase 9 / `/craft:commit` does that.
- It does **not** fix needs-rethinking findings — those escalate by design, even when the edit looks tiny.
- It does **not** close a slice while a Heavy + needs-rethinking finding is open.
- It does **not** promote decisions to `intent.md` / `rules.md`. That dialog is Phase 9.
- In advisory mode it does **not** change `Status:` or apply any edit.
