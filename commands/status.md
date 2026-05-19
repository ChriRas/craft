---
description: Lightweight slice overview. Reports active slices, phases, and sub-task progress without re-loading project context. Read-only, never modifies anything.
allowed-tools: ["Read", "Glob", "Bash"]
---

# /status — Active Slice Overview

## Purpose

Quick mid-session check of "what's open right now?" without running the full `/prime` sequence. Useful when the prime status block was emitted long ago and the user wants a refreshed slice view.

This is the read-only counterpart to `/prime`'s slice section. No tool health checks, no drift validation, no context loading.

---

## Procedure

1. `Glob` `.claude/plans/*.md`.
2. For each slice plan file:
   - Read its frontmatter: `Status`, `Slice-ID`, `Started`, `Phase`.
   - Read its `## Sub-Tasks` section, count completed (`- [x]`) vs. total.
   - Compute days-since-`Started`.
3. Identify stale slices (older than 7 days, not in Phase 8). The threshold may be overridden in `.claude/project/rules.md` under `## Self-Verification Settings` → `Stale slice threshold`.

---

## Output Format

```
Active slices:
  → slice-NNN "<title>" — Phase X, Y/Z sub-tasks done, started <K> days ago
  → slice-MMM "<title>" — Phase X, Y/Z sub-tasks done, started <K> days ago
⚠ slice-PPP untouched for K days — resume or discard?

Recommended: <action>
  → <follow-up command>
```

If no active slices: `No active slices. Run /plan <feature-name> to start a new slice.`

---

## Error Handling

| Situation | Behavior |
|---|---|
| `.claude/plans/` does not exist | Report `No active slices` (the project may simply have no slices in flight). |
| A slice plan file is unreadable | Log `⚠ slice plan <file> unreadable — skipping`, continue with the rest. |

---

## What This Command Does NOT Do

- It does **not** check tool health (use `/prime`).
- It does **not** load `intent.md` or `rules.md` (use `/prime`).
- It does **not** validate Rules ↔ State drift (use `/prime`).
- It does **not** modify any file.
