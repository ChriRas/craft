---
description: Switch into a slice- or epic-worktree for human inspection during Recap / Review. Read-only — resolves the worktree path, prints the cd instruction and the stack-pack provisioning hint. Does not install anything.
argument-hint: "<slice-NNN | epic-NNN>"
allowed-tools: ["Bash", "Read", "Glob"]
---

# /craft:checkout — Inspect a Worktree

## Purpose

When `/craft:execute` signals that a slice or epic is ready for review, `/craft:checkout` is the navigation command that surfaces the worktree path so the human can `cd` into it and exercise the artifact.

This is a **read-only** command — per the workflow skill's autonomy taxonomy, it carries no Pre/Post-Assertions. It resolves a path, prints it, and stops.

---

## Pre-flight

### Step 1 — Resolve target

The argument is `slice-NNN` or `epic-NNN`. If absent, ask: *"Which slice or epic? Pass `slice-NNN` or `epic-NNN`."*

### Step 2 — Find the worktree

`Bash` `git worktree list --porcelain` and match the target's branch name (`<slice-id>-<slug>` or `epic-<NNN>-<slug>`; honor `## Worktree Settings` overrides in `rules.md`).

If no match → stop with `No worktree for <target>. Either /craft:execute has not run yet, or the worktree was already cleaned up by /craft:archive.`

### Step 3 — Resolve the stack-pack provisioning hint

`Read` the `## Personality` section of `.claude/project/rules.md`. If a `Stack-Pack:` other than `none` is declared, `Read` the pack's `SKILL.md` and look for a `## Provisioning` section (optional). If present, surface its content verbatim. If the pack has no `## Provisioning` section, fall back to a generic hint.

If no pack is declared, emit only the generic hint.

---

## Procedure

### 1. Print the worktree path

Emit a single, clear block:

```
Worktree for <target>:
  <absolute path>

Switch in:
  cd "<absolute path>"
```

### 2. Print the stack-pack provisioning hint

If the loaded stack-pack has a `## Provisioning` section, print it. Otherwise, print:

```
Provisioning hint:
  The worktree is a fresh git checkout — language-specific dependencies
  (composer, npm, pip, etc.) are not installed. Run the project's normal
  bootstrap inside the worktree if you intend to run a dev server or tests.
```

### 3. Print the post-review nudge

Tail line:

```
After review:
  /craft:commit   to merge <target>'s branch into main (--no-ff)
  /craft:abort    to discard the worktree and branch (asks for confirmation)
```

---

## Output Format

```
Worktree for <target>:
  <absolute path>

Switch in:
  cd "<absolute path>"

<stack-pack hint OR generic hint>

After review:
  /craft:commit   to merge <target>'s branch into main (--no-ff)
  /craft:abort    to discard the worktree and branch (asks for confirmation)
```

If the target has no worktree, emit only the single line: `No worktree for <target>. Either /craft:execute has not run yet, or the worktree was already cleaned up by /craft:archive.`

---

## Error Handling

| Situation | Behavior |
|---|---|
| Argument missing | Ask once, then stop if still missing. |
| Target name unrecognized (neither slice-NNN nor epic-NNN) | Reject with format hint. |
| `git worktree list` fails | Surface the git error and stop. |
| Worktree path no longer exists on disk (stale git metadata) | Tell the user: *"Worktree path `<X>` is in git metadata but missing on disk. Run `/craft:worktree-clean` to reconcile."* |

---

## What This Command Does NOT Do

- It does **not** change Claude Code's working directory itself — it prints `cd "<path>"` for the user to run.
- It does **not** install dependencies, start a dev server, or run tests. The provisioning hint is informational.
- It does **not** modify the slice plan or any git state.
- It does **not** initiate the commit or the archive — those are separate explicit user steps.
