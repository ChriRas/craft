---
description: Lightweight slice overview. Reports active slices, phases, and sub-task progress without re-loading project context. Read-only, never modifies anything.
allowed-tools: ["Read", "Glob", "Bash"]
---

# /craft:status — Active Slice Overview

## Purpose

Quick mid-session check of "what's open right now?" without running the full `/craft:prime` sequence. Useful when the prime status block was emitted long ago and the user wants a refreshed slice view.

This is the read-only counterpart to `/craft:prime`'s slice section. No tool health checks, no drift validation, no context loading.

---

## Procedure

1. `Glob` `.claude/craft:plans/*.md`.
2. For each slice plan file:
   - Read its frontmatter: `Status`, `Slice-ID`, `Started`, `Phase`.
   - Read its `## Sub-Tasks` section, count completed (`- [x]`) vs. total.
   - Compute days-since-`Started`.
3. Identify stale slices (older than 7 days, not in Phase 9). The threshold may be overridden in `.claude/project/rules.md` under `## Self-Verification Settings` → `Stale slice threshold`.

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

If no active slices: `No active slices. Run /craft:plan <feature-name> to start a new slice.`

---

## Error Handling

| Situation | Behavior |
|---|---|
| `.claude/craft:plans/` does not exist | Report `No active slices` (the project may simply have no slices in flight). |
| A slice plan file is unreadable | Log `⚠ slice plan <file> unreadable — skipping`, continue with the rest. |

---

## What This Command Does NOT Do

- It does **not** check tool health (use `/craft:prime`).
- It does **not** load `intent.md` or `rules.md` (use `/craft:prime`).
- It does **not** validate Rules ↔ State drift (use `/craft:prime`).
- It does **not** modify any file.
