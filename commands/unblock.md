---
description: Clear a `blocked` slice. Presents the resume | re-plan | abort fork and restores the slice to the exact execution status it was blocked at; also back-fills a `(pending)` prerequisite marker with the real slice/epic-ID once it exists. The mutating counterpart to /craft:block; /craft:continue routes here.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /craft:unblock — Clear a Blocked Slice

## Purpose

The mutating counterpart to `/craft:block`. Where `/craft:block` records a `blocked` state,
`/craft:unblock` clears it — or links a still-pending prerequisite so it *can* be cleared later.
`/craft:continue` is a read-only router and delegates a `blocked` slice here.

Two functions, in one flow:

- **Back-fill** — when the blocker's `Blocked-on` is the `(pending — create via /craft:plan)`
  marker and the prerequisite has since been created, write its real ID so
  `/craft:commit`'s auto-resurface can match it when it closes.
- **Resume fork** — present `resume | re-plan | abort` and, on resume, restore the slice's
  `Status` to its recorded `Blocked-status`.

Automatic clearing when a `prerequisite-work` slice closes is owned by `/craft:commit`
(Step 7b, auto-resurface). `/craft:unblock` is the **manual** surface: for `external` /
`decision` / `access` blockers (which have no auto-trigger), for a force-resume, and for the
back-fill link.

This command is a **durable-state mutation** (it rewrites the slice plan's frontmatter and
`## Blocker` section) and follows the Pre/Post-Assertion pattern in `skills/workflow/SKILL.md`.

---

## Pre-flight

> **Ensure-primed gate** — before the checks below, if the session marker `.claude/plans/.primed` is absent, emit *"Session not primed — running /craft:prime first"*, run `/craft:prime` (it loads project context, verifies the four required tools, and writes the marker), then resume this command. Silent no-op when the marker is already present. Defined in `skills/workflow/SKILL.md` → **Session Priming Gate**.

- `Glob` `.claude/plans/*.md`. Identify the target **slice**:
  - `<slice-NNN>` argument given → that slice.
  - Else exactly one `Status: blocked` slice → use it. <!-- craft:reads status=blocked -->
  - Else multiple blocked → ask which.
  - None blocked → *"No blocked slice to unblock."* and stop.
- `Read` the chosen slice plan. Hold `Slice-ID`, `Status`, and the blocker frontmatter
  (`Blocker-type`, `Blocked-on`, `Blocked-since`, `Blocked-status`).

---

## Pre-Assertions

Run both. Any failure stops the command before the plan is touched.

### A1 — Target is a blocked slice

`Status` must be `blocked`.

- Any other status → *"Slice `<id>` is `<status>`, not blocked. `/craft:unblock` only clears a
  blocked slice."* Abort.

### A2 — Blocker frontmatter is intact

A blocked slice must carry all four on-demand fields (`Blocker-type`, `Blocked-on`,
`Blocked-since`, `Blocked-status`), and `Blocked-status` must be an execution token
(`implementing`, `testing`, `review`, `refactoring`, `reviewing`, `committing`).

Failure → *"⚠ Slice `<id>` is `blocked` but its blocker frontmatter is incomplete or
`Blocked-status` is not an execution token. Inspect the plan before unblocking."* Abort.

---

## Procedure (Autonomy Level 1)

### 1. Back-fill a pending prerequisite (only when `Blocked-on` is `(pending — …)`)

If `Blocked-on` is the pending marker, the prerequisite may since have been created:

> The prerequisite for this block is still marked pending. Has it been created? Enter its
> slice/epic-ID to link it (so this slice auto-resurfaces when it closes), or skip to keep it
> pending.

- If an ID is given, verify it resolves to a plan under `.claude/plans/` or an archive under
  `.claude/project/slices/`; on success write it into `Blocked-on` (replacing the marker).
  Unresolvable → reject and re-ask.
- Linking does **not** unblock: the prerequisite is not necessarily done. State that, then —
  if the user only wanted to link — stop here with the back-fill confirmation. Otherwise
  continue to the resume fork.

### 2. Resume fork

Present the fork with its full legend, per the lettered-choice-prompt convention in
`skills/workflow/SKILL.md`:

```
Unblock slice-<NNN> "<title>" — blocked on <blocked-on> (<blocker-type>)?
  [R] Resume    → clear the block, restore Status: <blocked-status>, continue where you left off
  [P] Re-plan   → the prerequisite showed this slice was mis-scoped → /craft:plan to reshape it
  [A] Abort     → abandon the slice → /craft:abort
```

For a `prerequisite-work` blocker whose `Blocked-on` names a real ID that has **not** closed
yet, add a caution: *"`<id>` hasn't landed — `/craft:commit` will auto-resurface this slice when
it does. Resume now only to override."*

### 3. Apply the chosen route

- **[R] Resume** — edit the slice plan:
  - set `Status:` to the recorded `Blocked-status`;
  - remove the four on-demand blocker frontmatter fields;
  - mark the `## Blocker` section resolved — prepend `> Resolved: <ISO date> — <reason>` (reason
    = `<blocked-on> landed` or `manual unblock`) and keep the prose as an audit note.
  Then recommend the phase command for the restored status (mirror `/craft:continue`'s routing).
- **[P] Re-plan** — do not mutate the blocked state; recommend `/craft:plan` to reshape the
  slice. The user re-plans deliberately.
- **[A] Abort** — do not mutate; recommend `/craft:abort`.

Before any write (Resume path), echo the change and get a one-word go-ahead — propose, never
silently mutate (rules.md).

### 4. Confirm

```
✓ slice-<NNN> unblocked → resumed at <blocked-status>.
  (or: ✓ Blocked-on back-filled: (pending) → <id> — still blocked until it lands.)

Recommended next: /<phase-command for restored status>
```

---

## Post-Assertions

Run the assertions matching the route taken. Any failure → warn loudly, do **not** pretend
success. No auto-rollback.

### P1 — Resume left a consistent slice ([R] only)

`Read` the slice plan. `Status:` equals the former `Blocked-status`; the four on-demand blocker
fields are gone; the `## Blocker` section carries a `> Resolved:` marker.

Failure → *"⚠ Unblock left `<id>` inconsistent (Status / blocker-fields / Blocker-marker).
Inspect the plan."*

### P2 — Back-fill wrote a resolvable ID ([back-fill] only)

If a back-fill ran, `Blocked-on` now holds an ID that resolves to a known plan/archive and is
no longer the `(pending — …)` marker.

Failure → *"⚠ Back-fill did not land a resolvable `Blocked-on` for `<id>`. Inspect the plan."*

### P3 — Re-plan / Abort left state untouched ([P]/[A] only)

For `[P]` or `[A]`, the slice plan's frontmatter is unchanged (still `Status: blocked` with its
blocker fields) — the routing is a recommendation, the mutation belongs to the routed command.

Failure → *"⚠ `<id>` was mutated on a re-plan/abort route that should only recommend. Inspect."*

---

## Output Format

Success: the confirmation block from Procedure step 4.

Aborted:

```
Unblock aborted — <reason>. No changes made.
```

Partial (post-assertion failure):

```
⚠ Unblock partially applied — <which assertion(s) failed>.
   File: <path>
   Inspect and reconcile manually.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (not blocked) | Abort: only a blocked slice can be unblocked. |
| A2 fails (malformed blocker frontmatter) | Abort; inspect the plan. |
| Multiple blocked slices, no argument | Ask which to unblock. |
| Back-fill ID does not resolve | Reject and re-ask, or let the user keep it pending. |
| User picks [R] on a `prerequisite-work` blocker whose prerequisite has not landed | Allowed (override), but surface the caution first; the auto-resurface would otherwise handle it. |
| P1–P3 fail after the write | Warn loudly; emit the partial block; do not auto-rollback. |

---

## What This Command Does NOT Do

- It does **not** auto-resurface on prerequisite completion — that is `/craft:commit`'s Step 7b.
- It does **not** build, test, or commit — it only clears the blocked state and recommends the
  next phase command.
- It does **not** abort or re-plan itself — `[P]`/`[A]` route to `/craft:plan` / `/craft:abort`.
- It does **not** create the prerequisite — that is `/craft:plan` / `/craft:epic`; this command
  only links an already-created one.
