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

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

### 1. Locate the active slice

- `Glob` `.claude/plans/*.md`.
- If multiple slices → ask the user which one to review.
- If none → stop with `No active slice to review. Run /craft:recap first (Phase 6 is what hands a slice to Review — via /craft:refactor only in a project that keeps Phase 7), or /craft:plan to start one.`

### 2. Determine the mode

`/craft:review` runs in one of two modes, decided by the slice's `Status:`:

- **Phase-8 mode** — <!-- craft:reads status=reviewing --> `Status:` is `refactoring`, `reviewing`, or `committing` (the slice has reached the review phase). Full review: classify, fix bounded local edits in-phase, escalate the rest, gate Commit. <!-- craft:writes status=reviewing --> Update `Status: reviewing` if not already.
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
- on a **re-review** (the plan's `## Review Findings` already holds a round), the **earlier rounds** — the section as written, plus the finding list read by `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-findings-state.sh" <slice plan>`: every `FINDING=<id>` with its resolution and whether it is open. The reviewer verifies them before looking for new issues (Step 2). Independence comes from the fresh window, not from hiding the record;
- the project's **comment language** — the `Comments` key of the `## Operational Language` block in `.claude/project/craft-profile.md` (default English when the profile, the block, or the key is absent). The reviewer flags code comments not written in this language as a Light finding;
- the **findings rubric** (Step 2).

### Step 2 — Run the review subagent (fresh context window)

Launch the **`code-reviewer`** subagent via the `Task` tool with `subagent_type: "code-reviewer"`. The named agent is pinned at `model: opus` for review-grade judgment (see `model-defaults.md`); a clean context window is the source of independence. Hand it the review brief from Step 1 and the rubric below. The agent classifies — it does not edit — and returns a structured findings list; the parent command applies fixes.

If a project has overridden `code-reviewer` in `.claude/project/craft-profile.md` → `## Agent Model Overrides`, the override's model is used instead. `/craft:prime` reports the effective value.

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

On a re-review the reviewer returns a **prior-round verification** first — one verdict per earlier finding ID — then its new findings. The verdicts, and when a bad verdict also owes a new `reopens <ID>` finding, are defined once, in `agents/code-reviewer.md` → **2. Verify earlier rounds first**; how a verdict feeds the route is Step 7's.

### Step 3 — Present the findings

Show the user the findings list grouped by the four rubric cells, with a one-line count summary. On a re-review, show the prior-round verification first (`<ID>: <verdict>`, the verdicts of `agents/code-reviewer.md` → 2), plus any `reopens <ID>` finding next to its ID, so the human sees which earlier findings the reviewer judges resolved before any new one. No fixes yet.

### Step 4 — Apply in-phase fixes (Level 2)

For every **local-edit** finding (Heavy or Light), apply the fix, then run the project's tests (Level 3, silent unless red). Bundle the fixes:

```
✓ In-phase fix <N>/<M>: <description>
   Changed: <files>
   Tests: <status>
```

**Soft volume cap.** The cap is `Review in-phase fix cap` in `rules.md` `## Self-Verification Settings` (default **5**). Once the number of in-phase fixes reaches the cap **while local-edit findings are still open** (`<K>` > 0), **stop** and recommend (Level 1) — with nothing left open there is no batch to escalate, and the cap does not fire:

> Review in-phase fix cap (<N>) reached — <K> local-edit findings still open. Many small fixes sum to a large unreviewed delta. Recommend escalating the remaining batch (loop back to Phase 4) rather than fixing it here.

The cap is a recommendation, not a hard block — the user may waive it. If the user **accepts** the escalation, the remaining local-edit findings are not fixed here: they loop back to Phase 4 through **Step 8**, reached via Step 7.

In **advisory mode**, skip this step: report local-edit findings as suggestions, apply nothing.

### Step 5 — Handle escalations (Level 1)

- **Heavy + needs-rethinking** — never fixed here. For each, recommend one of two routes and let the user choose:
  - *loop back to Phase 4* (`/craft:build`) — the fix belongs in this slice's scope; runs **Step 8**, reached via Step 7;
  - *spin off a new slice* (`/craft:plan`) — it is genuinely separate work. The finding is **resolved only once that slice exists** and its ID is recorded (Step 6: `escalated → new slice <slice-ID>`); until then it stays open as `escalated → new slice (pending)`.
  A finding the user has not routed yet is recorded `escalated → route pending`. Open findings **block Commit** (Step 7).
- **Light + needs-rethinking** — recorded as a **follow-up**. Commit proceeds; the follow-up lands in the slice archive's `## Follow-ups` section at Phase 9.

In advisory mode, present both as recommendations only — no phase routing, no `Status:` change.

### Step 6 — Write the findings record

Write every finding to the slice plan's `## Review Findings` section — the audit trail, **one round per run, appended**. The record is read by one parser, `scripts/review-findings-state.sh` (below, "the helper"): it is the one definition of the round count, the line format, the resolution field and which lines are open; this step and Step 7 only call it. **If the helper cannot run** — not found, a non-zero exit, or no `OPEN_COUNT=` line — nothing about the record is known: never read that as clear. Interactively, stop and say so (Commit stays blocked); in Subagent Mode, go straight to **Subagent Mode → Gate**, which treats a helper that cannot run as open and makes the one marked handoff write. Every use of the helper in this command applies this rule.

1. **Fix the round number first** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-findings-state.sh" <slice plan>` *before* writing and take `NEXT_ROUND=` as `<R>` (it counts every `### Round` heading, advisory ones included, and a **legacy record** — finding lines above the first heading, written before round headings existed — as one Phase-8 round).
2. **Append** a heading `### Round <R> — <ISO date> (<Phase-8 | advisory>)` and one line per finding below it, numbered `R<R>-1`, `R<R>-2`, … in the order written. Never replace or reword an earlier round — the only in-place changes to an earlier round are Step 7's: replacing the **resolution** (the last ` · ` field) of one of its **open** lines, and correcting what the helper reports `MALFORMED` (a finding line, a round heading with its IDs, an unclosed fence). When Step 7 edits a legacy line (one without an ID), it also writes the ID the helper reported (`R<r>-<n> · `) in front of it, so that ID stays stable. Anything else about an earlier line (an ID that did not resolve, a remark, a verification verdict) goes under **this** round's heading as a `note ·` line.

```
- R<R>-<n> · Heavy · Local   · <description> · fixed in-phase
- R<R>-<n> · Light · Rethink · <description> · follow-up → slice archive
- R<R>-<n> · Heavy · Rethink · <description> · escalated → Phase 4 loop-back
- R<R>-<n> · Heavy · Rethink · <description> · escalated → new slice (pending)
- R<R>-<n> · Heavy · Rethink · <description> · escalated → new slice <slice-ID>
- R<R>-<n> · Heavy · Rethink · <description> · escalated → route pending
- R<R>-<n> · Light · Local   · <description> · escalated → Phase 4 loop-back (fix cap)
- R<R>-<n> · Heavy · Local   · <description> · open — fix cap, awaiting decision
- R<R>-<n> · Heavy · Rethink · <description> · resolved in round <R>
- R<R>-<n> · Heavy · Rethink · <description> · advisory — no route
- note · fix cap (<N>) waived by the user
```

The **resolution** is the last ` · ` field — a ` · ` or a quoted resolution value inside the description does not change it. It may carry a short note after `: ` or ` (` (`fixed in-phase: renamed the guard`); the note must not contain ` · `, or its tail becomes the last field and the line reads `MALFORMED`. `resolved in round <R>` is written only by Step 7, in place; `advisory — no route` is every line's resolution in advisory mode. Which resolutions keep a line **open** is the helper's table alone — `review-findings-state.sh --print-resolutions`, first column `yes`; advisory rounds are never open. A line the helper cannot read is reported `MALFORMED` and counted open — doubt blocks.

If the slice plan has no `## Review Findings` section yet, append one.

### Step 7 — Gate, loop back, or clear

- **Advisory mode** — stop. Emit the findings report; do not touch `Status:`.
- **Phase-8 mode** — first **resolve open lines**: run the helper and take every `FINDING=… OPEN=yes` of *every* Phase-8 round, this round's and earlier ones, legacy record included, and every `MALFORMED=` line:
  - `new slice (pending)` — or a legacy `escalated → new slice` without an ID — → ask whether that slice now exists. Record the ID in place (`escalated → new slice <slice-ID>`) **only if** it resolves to `.claude/plans/<slice-ID>-*.md` or `.claude/project/slices/<slice-ID>-*.md`; otherwise say so and keep it pending.
  - `route pending` or `open — fix cap, awaiting decision` on an **earlier** round's line (this round's were routed in Steps 4–5) → show the reviewer's verification verdict for that ID (Step 2) and ask for the route, recording it in place: *resolved* (`resolved in round <R>`, with `<R>` this round), *loop back to Phase 4* (`escalated → Phase 4 loop-back`), *spin off a new slice* (`escalated → new slice (pending)`, resolved as above), or *leave it pending*. **Pre-select *resolved* only when the verdict is `holds`**; on any other verdict offer it without pre-selection and name what the reviewer reported. The human confirms — a verdict never closes a line by itself.
  - a `MALFORMED=… MODE=phase8` finding line (advisory ones never block) → show it; the human either corrects it in place so the helper can read it (Step 6 lists this as an allowed in-place change), or routes it as above. It never counts as closed on its own.
  - `MALFORMED=heading-<n>` — a round heading whose number is not its position `<n>` → not routable; show the heading text. The human renumbers that heading to `<n>` **and** that round's IDs to `R<n>-…`, and writes the old → new IDs as a `note ·` line under this round, so earlier `Loop-back <ID>` sub-tasks and `reopens <ID>` references stay traceable.
  - `MALFORMED=fence-unclosed` — a code fence opened at that line never closes, so the helper cannot tell what it hides → show the line; the human closes the fence (an allowed in-place correction).

  Then run the helper again and decide in this order; the first match wins:
  1. **A loop-back was chosen** — in this run the user routed at least one finding to Phase 4: a Heavy + needs-rethinking finding (Step 5), an earlier round's open line (above), or the accepted fix-cap batch (Step 4) → run **Step 8** and stop there. Do not write `reviewing` or `committing` over it.
  2. **`OPEN_COUNT` is not 0** — a line in some Phase-8 round is still open. The gate reads the record through the helper rather than relying on the reviewer to re-find an earlier finding. → Commit is **blocked**. Leave `Status: reviewing`. Emit the open line(s) with their ID and resolution.
  3. **`OPEN_COUNT=0`** → the review is **clear**. <!-- craft:writes status=committing --> Update `Status: committing` and emit `Recommended next: /craft:commit`.

### Step 8 — Loop back to Phase 4

This is the **only** place the review loop-back is defined. Step 4 (accepted fix-cap escalation) and Step 5 (loop-back route) reach it through Step 7, and the Subagent Mode handoff is resolved by running this command interactively, which ends here too. It runs only on the user's choice — never on the reviewer's — and only when at least one finding loops back.

1. **Round** — use the `<R>` Step 6 fixed for this round.
2. **Sub-tasks** — append to the plan's `## Sub-Tasks`, below the existing (checked) items, one unchecked item per finding looped back in this run (earlier-round lines routed in Step 7 included): `- [ ] Loop-back <ID> — <finding description>` (the finding's ID from Step 6). A fix-cap batch may be grouped into one item per file or concern; keep every finding traceable to an item. If the plan has no `## Sub-Tasks` section, append one first (as Step 6 does for findings) and say so in the decision entry.
3. **Findings record** — already written by Step 6 (and Step 7 for earlier-round lines); Step 8 changes no finding line. Lines still open stay open for Step 7 of every later round.
4. **Decision** — append to `## Decisions Made During This Slice`: `**Review round <R> → loop-back to Phase 4** (<ISO date>) — <reasons, joined with "and": <N> Heavy + needs-rethinking finding(s) routed to Phase 4; fix cap (<cap>) reached with <K> local-edit findings open>; route chosen by the user.`
5. **Status** — <!-- craft:writes status=implementing --> write `Status: implementing` to the slice plan. In-phase fixes already applied in Step 4 stay in the working tree; Phase 4 builds on top of them.
6. **Hand off** — emit the looped-back output block and `Recommended next: /craft:build`. From Phase 4 the slice walks the ordinary transition graph forward again — through whichever of Phases 5–7 this project runs, as `/craft:recap`'s Phase-7 routing decides — back to this command for a re-review, because the loop-back changes the artifact those phases signed off.

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
  Open lines (blocking): <N>
    - <ID> · <description, or the heading / fence line for a heading-<n> / fence-unclosed entry> → <new slice (pending) | route pending | open — fix cap, awaiting decision | MALFORMED>

Status stays `reviewing` — resolve the open line(s) before Commit.
Recommended next: /craft:plan  (spin off the pending work), then /craft:review
                  — its Step 7 records the slice-ID, or asks for a route on a pending line
```

Phase-8 mode, looped back (Step 8):

```
↩ Phase 8 — Review round <R> → loop-back to Phase 4

Findings: <H> heavy, <L> light
  In-phase fixes applied: <N>
  Looped back: <N> finding(s) → <N> new sub-task(s)
    - Loop-back <ID> — <description>
  Still open lines: <N>   (omit when 0 — each blocks the re-review until Step 7 resolves it)

Status: implementing — Phase 4 resumes on the new sub-tasks; the slice then walks the graph forward to a re-review.
Recommended next: /craft:build
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
| No active slice plan | Stop; recommend `/craft:recap` (or `/craft:refactor` in a Phase-7-keeping project), else `/craft:plan`. |
| Multiple active slices | Ask the user which slice to review. |
| `git diff HEAD` is empty (no slice delta) | Tell the user there is nothing to review; recommend confirming Phase 4 actually ran. |
| The review subagent returns no structured findings | Re-run once with the rubric restated; if still unstructured, present the raw output and ask the user to classify. |
| A test turns red after an in-phase fix | Treat it like any Phase-4 fix: one fix attempt; if still red, offer `/craft:debug`. Do not leave the tree red. |
| In-phase fixes reach the soft cap with local-edit findings still open | Stop fixing; recommend escalating the remaining batch (Step 4). Not a hard block. Accepted → Step 7 case 1. |
| User routes findings both ways (some loop-back, some new slice) | → Step 7 case 1 (Step 8); the spin-offs stay open per Step 7 case 2. |
| Slice plan has no `## Sub-Tasks` section when Step 8 runs | → Step 8.2 (append the section). |
| User waives the soft cap | Continue fixing; record a `note ·` line under this round's heading (Step 6). |
| A recorded slice-ID does not resolve to a plan or archive | → Step 7 (keep the line pending). |
| `## Review Findings` section missing from the slice plan | Append the section, then write the findings into it. |

---

## Subagent Mode (when called by `/craft:execute`)

`/craft:review` already runs its core work in a fresh-context subagent (the reviewer). When `/craft:review` itself is invoked by the `slice-builder` subagent during an autonomous run, that becomes a sub-subagent — supported.

Behavior in this mode:

This section is the **one** definition of the autonomous review outcome; `agents/slice-builder.md` and `skills/workflow/SKILL.md` point here.

- Steps 1–6 run normally; findings are classified and written to the slice plan's `## Review Findings`.
- Step 4 (in-phase fix application) runs — fixing local-edit findings is mechanical and safe to automate. On a soft-cap breach the remaining local-edit findings are recorded `open — fix cap, awaiting decision` (no one accepted a loop-back).
- Step 5 — **Heavy + needs-rethinking** findings do **not** prompt the user; they are recorded `escalated → route pending`, with the recommended route (loop-back or new slice) for each written to `.craft/handoff.md`.
- **Gate** — <!-- craft:handoff status=awaiting-rethink-decision plan=reviewing --> Step 7 runs **without its questions**: if the helper reports `OPEN_COUNT` above 0 (any Phase-8 round, this round's or an earlier one's; `MALFORMED` lines count), **or cannot run** (Step 6) — no line is ever recorded `resolved` here, because that route is human-confirmed — write `.craft/handoff.md` with `Status: awaiting-rethink-decision` and as its `Episode:` the `ROUNDS=` of the helper run **after** Step 6 wrote this round — it equals `<R>`, never the pre-write run's value (omit `Episode:` when the helper cannot run — the marker then counts by status alone), name `/craft:review` as the resolution, and stop. The slice plan is **not** paused: it stays at the Phase-8 status Pre-flight step 2 set, which is exactly what the interactive resolution reads. With no open line, Step 7 case 3 applies (the review is clear).
- **Loop-back** — <!-- craft:delegates rule=loop-back to=step-8 --> this mode never loops a slice back itself and writes no plan status for it. The human resolves the handoff with an interactive `/craft:review` in the slice worktree (reach it with `/craft:checkout`, or `/craft:continue`, which routes the unchanged plan status there); its Step 7 asks for the routes of the open lines, and a chosen loop-back runs **Step 8**, the one definition.

The reviewer subagent itself never makes routing decisions; routing is always human-confirmed.

---

## What This Command Does NOT Do

- It does **not** commit. Phase 9 / `/craft:commit` does that.
- It does **not** fix needs-rethinking findings — those escalate by design, even when the edit looks tiny.
- It does **not** close a slice while a Heavy + needs-rethinking finding is open.
- It does **not** loop a slice back to Phase 4 on its own judgment — Step 8 runs only on the user's route choice.
- It does **not** promote decisions to `intent.md` / `rules.md`. That dialog is Phase 9.
- In advisory mode it does **not** change `Status:` or apply any edit.
