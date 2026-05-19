---
description: Propose an explicit edit to .claude/project/intent.md. Agent drafts the diff, human confirms before write. Used outside Phase 8 when an intent shift surfaces.
allowed-tools: ["Read", "Edit", "Glob"]
---

# /intent-update — Update Project Intent

## Purpose

Edit `intent.md` deliberately and visibly. The agent proposes the diff; the human confirms. This is the *only* path for `intent.md` changes outside Phase 8's promotion dialog.

Used when, mid-work, the user realizes the project's intent has shifted (e.g., a non-goal has become a goal, or an architectural decision was just made).

`intent.md` is sacred (see `skills/workflow/SKILL.md` knowledge model). Never silently mutated.

---

## Pre-flight

- `Read` `.claude/project/intent.md`. If missing → tell user to run `/onboard` and stop.

---

## Procedure (Autonomy Level 0)

### 1. Capture the user's intent shift

Ask:

> What is the change? Describe it as either:
>   - A new entry (e.g., "add a goal: …")
>   - A revision (e.g., "the architectural decision about X should now say Y")
>   - A removal (e.g., "drop the non-goal about Z, we are now going to build it")

If the user is vague, push for specifics. Updates should be concrete sentences, not abstractions.

### 2. Propose a diff

Show the change as a unified diff (context lines + the actual change). Example:

```
--- intent.md (current)
+++ intent.md (proposed)
@@ Architectural Decisions @@
 - **Livewire v3 statt Filament** — Custom-Theming skaliert besser. *Why not Filament:* zu rigides Component-Layout
+- **Optimistic UI Updates** — PWA must remain responsive on flaky mobile networks. *Why not:* server-confirm latency hurts UX
```

If the change is large (>10 lines), surface a high-level summary first, then offer the full diff on demand.

### 3. Confirm

Ask:

```
Apply this diff to intent.md? (Y / revise / cancel)
```

Only proceed on `Y`.

If `revise`, iterate on the proposed diff with the user.

If `cancel`, do nothing.

### 4. Apply

`Edit` the file with the confirmed change.

### 5. Validate

After writing, re-run a quick sanity check:

- `intent.md` is still under ~80 lines (if approaching the limit, warn).
- No verifiable / operational instructions slipped in (those belong in `rules.md`, not `intent.md`).

If the user accidentally added something that should be a rule:

> This looks operational ("must run lint before commit") — operational instructions belong in `rules.md`. Move it there instead?

### 6. Confirm completion

```
✓ intent.md updated.
   Lines: <N> (was <M>)
   Diff size: <N> lines changed
```

---

## Output Format

The confirmation line above. The diff itself is shown in step 2.

---

## Error Handling

| Situation | Behavior |
|---|---|
| `intent.md` missing | Stop, recommend `/onboard`. |
| User wants to write to `rules.md` instead | Suggest creating a similar `/rules-update` command (not built yet) or hand-editing `rules.md` carefully. For now, refuse to edit `rules.md` from this command. |
| Proposed change includes operational/verifiable language | Surface mismatch, suggest moving to `rules.md` (manual). |
| User cancels mid-confirmation | Make no changes; exit cleanly. |

---

## What This Command Does NOT Do

- It does **not** edit `rules.md`. Different concern, different command.
- It does **not** edit silently. Confirmation is mandatory.
- It does **not** revert prior changes. Use git for that.
- It does **not** validate semantics — only structural sanity (line count, intent vs operational).
