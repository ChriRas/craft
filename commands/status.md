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

1. `Glob` `.claude/plans/*.md`. This may include epic plans (`# Epic NNN — <title>`) alongside slice plans (`# Slice NNN — <title>`).
2. For each plan file:
   - Read its metadata block (`Status`, `Slice-ID` or `Epic-ID`, `Started`, `Phase`, `Handoff active`) **plus** its title from the `# (Slice|Epic) NNN — <title>` heading.
   - Read its `## Sub-Tasks` section, count completed (`- [x]`) as `done` and completed + unchecked (`- [ ]`) as `total`. An epic plan has no `## Sub-Tasks` (it carries `## Slice Decomposition`); treat its counts as `0/0` → empty bar.
   - Compute days-since-`Started`.
3. Resolve the phase **label** from the slice's `Status` (primary), falling back to the `Phase:` number when `Status` does not encode a phase (see **Phase label** below).
4. Render a **progress bar** from `done` / `total` (see below).
5. **Partition** the slices into two groups: `Active` and `Stale`. A slice is stale when its `Started` is older than the threshold (default **7 days**, overridable in `.claude/project/rules.md` under `## Self-Verification Settings` → `Stale slice threshold`) **and** it is not in Phase 9. All other slices are Active.
6. Mark any slice whose frontmatter has `Handoff active: yes` with a **handoff flag** (`⊹ handoff`).
7. Mark any `Status: blocked` slice with a **blocked flag** — `⛔ blocked → <Blocked-on> (<Blocker-type>)` (see **Blocked flag** below), including orphan detection.

### Blocked flag

A `Status: blocked` slice appends `⛔ blocked → <Blocked-on> (<Blocker-type>)` to its line (mirrors
`⊹ handoff`). **Orphan detection:** when `Blocker-type` is `prerequisite-work` and `Blocked-on`
resolves to neither an active plan (`.claude/plans/`) nor an archive (`.claude/project/slices/`),
append `· ⚠ orphan` — the prerequisite was aborted or never created. A `Blocked-on: (pending — …)`
marker and free-text `Blocked-on` (the `external` / `decision` / `access` types) are **never**
orphans — they carry no resolvable ID.

### Phase label

The label answers "where in the 9-phase loop is this slice?". Derive it from `Status` **first** — `Status` tracks the live phase, whereas the `Phase:` frontmatter number is set at plan time and is not advanced by every phase command, so it can read stale.

**Primary — `Status` → phase** (source of truth: the `Status:` writes in the phase commands and the routing table in `commands/continue.md`):

| Status | Label | Status | Label |
|---|---|---|---|
| `planning` | Phase 3 (Plan) | `refactoring` | Phase 7 (Refactor) |
| `implementing` | Phase 4 (Build) | `reviewing` | Phase 8 (Review) |
| `testing` | Phase 5 (Test) | `committing` | Phase 9 (Commit) |
| `review` | Phase 6 (Recap) | `committed` | Phase 9 (Commit ✓) |

**Blocked — `Status: blocked`.** Never render `blocked` as a phase. The live phase is carried by
the `Blocked-status` frontmatter (always an execution token): resolve the label from
`Blocked-status` through the primary table above, and append the blocked flag (see **Blocked
flag** below) so the reader sees both where it will resume *and* that it is waiting.

**Fallback — `Phase:` number → name.** When `Status` is `paused` (it does not encode a phase), an `awaiting-*` orchestration state, or any value absent from the table above, fall back to the `Phase:` frontmatter number through this map (command-aligned short names; source of truth: the `### Phase N —` headers in `skills/workflow/SKILL.md`):

| Phase | Name | Phase | Name |
|---|---|---|---|
| 1 | Brainstorm | 6 | Recap |
| 2 | Alignment | 7 | Refactor |
| 3 | Plan | 8 | Review |
| 4 | Build | 9 | Commit |
| 5 | Test | | |

Render as `Phase <N> (<Name>)`. Because a fallback-derived label comes from the possibly-stale `Phase:` number rather than live `Status`, **append the raw status** as a `· <status>` suffix so it is not mistaken for a live phase — e.g. `Phase 6 (Recap) · paused`, `Phase 3 (Plan) · awaiting-approval`. If the fallback number is itself out of range or missing, render `Phase <N> (?)` and continue — never abort the overview for one malformed plan.

### Progress bar

A fixed **5-cell** bar, filled `▓` / empty `░`:

```
filled = (total == 0)    ? 0                     // no sub-tasks yet → empty bar
       : (done == total)  ? 5                     // complete → full bar
       : min(4, round(done ÷ total × 5))          // in progress → round half up, never full
bar    = "▓" × filled + "░" × (5 − filled)
```

Render as `<bar> <done>/<total>`. Rounding is **half-up**, and the full 5-cell bar `▓▓▓▓▓` is **reserved for `done == total`** (the `min(4, …)` cap) — so a full bar always means complete, and `19/20` shows `▓▓▓▓░`, not a misleading full bar. A slice with **zero** sub-tasks (e.g. a fresh Phase-3 plan) renders an empty bar `░░░░░ 0/0` — the `total == 0` guard means the division is never evaluated.

---

## Output Format

Slices are rendered in two groups, each with a count header, separated by a blank line. The `Stale` group is omitted entirely when empty; the `Active` group is always shown (even at count 0) so the reader can distinguish "no active work" from "only stale work left".

```
Active (3):
  → slice-NNN "<title>" — Phase 4 (Build)     ▓▓░░░ 2/5 · 1d ago
  → slice-MMM "<title>" — Phase 8 (Review)    ▓▓▓▓▓ 5/5 · 3d ago  ⊹ handoff
  → slice-QQQ "<title>" — Phase 5 (Test)      ▓▓▓░░ 3/5 · 2d ago  ⛔ blocked → slice-030 (prerequisite-work)

Stale (1):
  ⚠ slice-PPP "<title>" — Phase 3 (Plan)      ░░░░░ 0/0 · untouched 9d — resume or discard?

Recommended: <action>
  → <follow-up command>
```

A handoff-flagged slice appends `⊹ handoff` to its line (mirrors how `/craft:prime` surfaces pending handoffs). Bars and the `·`-separated fields are aligned by eye — exact column alignment is not required, readability is.

If there are no plans at all: `No slices in flight. Run /craft:plan <feature-name> to start a new slice.` (Distinct from the empty-Active-but-has-Stale case, which still renders `Active (0):` followed by the `Stale` group.)

---

## Error Handling

| Situation | Behavior |
|---|---|
| `.claude/plans/` does not exist | Report `No active slices` (the project may simply have no slices in flight). |
| A slice plan file is unreadable | Log `⚠ slice plan <file> unreadable — skipping`, continue with the rest. |

---

## What This Command Does NOT Do

- It does **not** check tool health (use `/craft:prime`).
- It does **not** load `intent.md` or `rules.md` (use `/craft:prime`).
- It does **not** validate Rules ↔ State drift (use `/craft:prime`).
- It does **not** modify any file.
