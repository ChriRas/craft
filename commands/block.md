---
description: Record a first-class `blocked` state on the active slice when work cannot proceed until a prerequisite — itself a unit of work or a decision — is resolved. Classifies the blocker, writes on-demand frontmatter + a ## Blocker section, and routes prerequisite work to its own slice/epic without spawning it.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /craft:block — Block the Active Slice on a Prerequisite

## Purpose

A slice in flight can hit an obstacle whose resolution lies outside its scope — classically,
it cannot be tested because a prerequisite (e.g. deployment infrastructure) does not exist
yet. `/craft:block` records this as a **first-class `blocked` state** on the active slice so
the running slice never silently absorbs the new direction (scope creep) and the blocker
stays visible under human control.

`/craft:block` is distinct from its neighbours:

- `/craft:pause` — "I stepped away." No external dependency.
- `/craft:handoff` — the *conversation* is context-poisoned; reset the session, keep the slice.
- `/craft:debug` — a bug in *your own* code; stays in-slice.
- `/craft:abort` — abandon the slice entirely.
- `/craft:block` — work cannot proceed until a **prerequisite or decision outside this slice**
  is resolved.

This is the **interactive** front-end of the `blocked` state. The autonomous front-end (a
`slice-builder` writing `.craft/handoff.md` during `/craft:execute`) is a separate capability.

This command is a **durable-state mutation** (it rewrites the active slice plan's frontmatter
and adds a `## Blocker` section) and follows the Pre/Post-Assertion pattern documented in
`skills/workflow/SKILL.md`. It does **not** create the prerequisite slice/epic — it records
and routes.

---

## Pre-flight

- `Glob` `.claude/plans/*.md`. Identify the active **slice** to block (ignore `epic-*` plan
  files — an epic is not blocked, its child slice is):
  - Exactly one active slice → use it.
  - Multiple → ask which slice to block.
  - None → tell the user *"No active slice to block."* and stop.
- `Read` the chosen slice plan. Hold `Slice-ID`, `Status`, `Phase` in context.

---

## Pre-Assertions

Run both. Any failure stops the command before the plan is touched.

### A1 — Slice is in a blockable state

The slice `Status` must be an in-flight execution state — one of `implementing`, `testing`,
`review`, `refactoring`, `reviewing`, `committing`. Special cases:

- `Status: planning` → *"This slice hasn't started — a blocker discovered during planning is
  just a scoping decision. Refine the plan or split the prerequisite out with `/craft:plan`."*
  Abort.
- `Status: committed` → *"Slice already closed. Nothing to block."* Abort.
- `Status: blocked` → not a failure: offer to **update** the existing blocker (re-classify or
  re-word) rather than stacking a second one.
- `Status: paused` → allowed; blocking supersedes the pause (note it in the confirmation).

### A2 — Slice plan readable with valid frontmatter

`Read` the slice plan; it must be non-empty and carry a parseable frontmatter block with
`Slice-ID`, `Status`, and `Phase`.

Failure → *"⚠ Active slice plan unreadable or malformed at `<path>`. Inspect manually before
blocking."* Abort.

---

## Procedure (Autonomy Level 1)

Blocking is a human-facing direction decision — it runs dialogically at Level 1.

### 1. Classify the blocker

Ask, dialogically:

> What kind of blocker is this?
> - **prerequisite-work** — a missing unit of work (infra, an API, a service) that must be
>   built first. Spawns its own slice/epic.
> - **external** — waiting on the world (third-party outage, an expiring certificate, a
>   pending upstream release).
> - **decision** — an open direction question only you can answer.
> - **access** — missing credentials / permission that only you can grant.

Reinforce the **spawn-boundary heuristic** so a blocker is not confused with in-slice work:
it is a blocker only when the missing thing (a) would have its own test / observable effect,
(b) exceeds this slice's declared scope, **or** (c) is an unsanctioned direction. Otherwise it
is a minimal in-slice dependency — build it, don't block. *In doubt, escalate (block).*

### 2. Capture the blocker prose

Collect three things (this becomes the `## Blocker` section):

1. **What's missing** — the precise prerequisite / decision / access that is absent.
2. **What was tried** — attempts made before concluding the slice is blocked (one line each).
3. **What "unblocked" looks like** — the resume-acceptance: the observable condition under
   which this slice can continue.

### 3. Type-specific handling

- **prerequisite-work** — present the 3-option fork:
  1. **Spawn** — the prerequisite becomes its own slice/epic. `/craft:block` does **not**
     create it; it routes: recommend `/craft:plan <name>` (or `/craft:epic <name>` if the
     prerequisite is itself multi-slice). If the user creates it now, capture the resulting
     ID into `Blocked-on`; otherwise write `Blocked-on: (pending — create via /craft:plan)`.
  2. **Park** — record the blocker and stop; the prerequisite is deferred.
  3. **Descope** — the slice was mis-scoped (its testable boundary secretly required the
     prerequisite). Recommend re-planning; do not block, redirect to `/craft:plan` to
     reshape the slice.
- **external / decision / access** — no spawn. `Blocked-on` holds a free-text description of
  what is being waited on / decided / granted.

### 4. Determine the resume phase

`Blocked-phase` = the phase number the slice is currently in (from `Phase:` / the execution
`Status`). This is where `/craft:continue` will drop the slice back once unblocked.

### 5. Write the blocked state

Edit the active slice plan:

- Set `Status: blocked` in the frontmatter.
- Add the **on-demand** blocker frontmatter fields directly below the `Status:` line (they are
  absent on a normal slice; write them only now):

  ```
  > Blocker-type: <prerequisite-work | external | decision | access>
  > Blocked-on: <slice-NNN | epic-NNN | (pending — create via /craft:plan) | free text>
  > Blocked-since: <ISO date>
  > Blocked-phase: <phase number to resume into>
  ```

- Add (or, when re-blocking, overwrite) the `## Blocker` section:

  ```markdown
  ## Blocker

  > Blocked: <ISO date> | Type: <type> | On: <blocked-on>

  ### What's missing
  <…>

  ### What was tried
  - <…>

  ### What "unblocked" looks like (resume acceptance)
  <…>
  ```

### 6. Confirm

```
✓ slice-<NNN> blocked.

  Type:      <blocker-type>
  Blocked-on: <blocked-on>
  Resume at: Phase <blocked-phase>

<for prerequisite-work + Spawn: "Next: /craft:plan <name> to build the prerequisite — its
ID will be back-filled into Blocked-on.">

The block is recorded. /craft:prime and /craft:status will surface it; /craft:continue
resumes once unblocked.
```

---

## Post-Assertions

Run all three after the write. Any failure → warn loudly, surface to the user, do **not**
pretend success. No auto-rollback.

### P1 — Blocked frontmatter written

`Read` the slice plan. Frontmatter must now show `Status: blocked` plus all four fields
`Blocker-type`, `Blocked-on`, `Blocked-since`, `Blocked-phase` with non-placeholder values.

Failure → *"⚠ Blocked frontmatter incomplete in `<path>`. Inspect before relying on the
blocked state."*

### P2 — `## Blocker` section present and non-empty

The plan must contain a `## Blocker` section with all three sub-parts filled (not the
template's `(none)` placeholder).

Failure → *"⚠ `## Blocker` section missing or empty in `<path>`. The block prose was not
captured."*

### P3 — Prerequisite reference resolvable or explicitly pending

For `Blocker-type: prerequisite-work`, `Blocked-on` must either reference a plan that exists
in `.claude/plans/` or `.claude/project/slices/`, **or** be the explicit `(pending — create
via /craft:plan)` marker. For the other three types, `Blocked-on` is free text (any non-empty
value passes).

Failure → *"⚠ `Blocked-on` names `<ref>`, which does not resolve to a known slice/epic and is
not marked pending. Fix the reference or mark it pending."*

---

## Output Format

Success: the confirmation block from Procedure step 6.

Aborted:

```
Block aborted — <reason>. No changes made.
```

Partial (post-assertion failure):

```
⚠ Block partially written — <which assertion(s) failed>.
   File: <path>
   Inspect and reconcile manually.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| A1 fails (`planning`) | Redirect to `/craft:plan` — a planning-phase blocker is a scoping decision. |
| A1 fails (`committed`) | Stop: *"Slice already closed. Nothing to block."* |
| Slice already `blocked` | Offer to update the existing blocker rather than stacking a second. |
| Multiple active slices | Ask which slice to block before proceeding. |
| User cannot articulate "what unblocked looks like" | Push back: a blocker with no resume-acceptance cannot be cleared cleanly — help the user state the observable condition, or reconsider whether this is really a blocker. |
| prerequisite-work, user picks Descope | Do not write `blocked`; route to `/craft:plan` to reshape the slice. |
| P1/P2/P3 fail after write | Warn loudly; emit the partial block; do not auto-rollback. |

---

## What This Command Does NOT Do

- It does **not** create the prerequisite slice/epic. It records and routes; the user runs
  `/craft:plan` / `/craft:epic` to build it.
- It does **not** unblock. Automatic un-blocking on prerequisite completion (via
  `/craft:commit`) and the `resume | re-plan | abort` fork in `/craft:continue` are separate
  capabilities.
- It does **not** abort the slice. Use `/craft:abort` for that.
- It does **not** modify code, commits, or any project state outside the active slice plan.
- It does **not** edit `intent.md` or `rules.md`. Decisions surfaced while blocking go into
  the slice plan's `## Decisions Made During This Slice` section for Phase 9 promotion.
