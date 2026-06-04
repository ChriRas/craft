# Slice 014 — Worktree Trust via additionalDirectories

> Completed: 2026-06-04
> Commits: 4a2578d..29e342b (branch main, trunk-based)

## What

`/craft:execute` now trusts the worktree tree automatically. Before creating any
worktree it resolves the **base directory** of the configured `Worktree path pattern`
and records it once in `permissions.additionalDirectories` of the project-local
`.claude/settings.local.json`. A new shipped helper — `scripts/ensure-worktree-trust.sh`
— does the derivation and the idempotent JSON merge; a new Procedure step 2 ("Trust the
worktree base directory") wires it into the orchestrator between lock-acquire and the
first `git worktree add`.

## Why

- Worktrees live **outside** the project root (`../<repo>-worktrees/…`), which Claude
  Code does not trust by default. Every file operation a `slice-builder` performed inside
  a worktree (mkdir, edits, `git -C`, test runs) raised a per-path permission prompt —
  stalling the autonomous run that `/craft:execute` exists to enable.
- Users "fixed" this by hand-collecting hundreds of path-specific allow rules in
  `settings.local.json` (one per worktree subpath). That wuchert, must be redone per
  worktree, and never closes the gap. The root fix is a single entry: trust the base
  directory, and the whole worktree tree inherits the project root's trust level.
- The behavior had to respect CRAFT's durable-state contract — a write to user settings is
  **never silent**. It reuses the existing announce-then-apply + Pre/Post-Assertion idiom
  rather than a bespoke mechanism (D24, Durable Capture lineage).

## Walk-through

On `/craft:execute <target>`, after acquiring the lock and before creating worktrees, the
orchestrator resolves the path pattern (project override from `rules.md` `## Worktree
Settings`, else the default `../<repo>-worktrees/<slice-id>-<slug>/`) and runs the helper
in `--check` mode. The script substitutes the `<repo>` token, strips the per-worktree leaf
segment, and normalises the remainder against the repo root into an absolute, existence-
independent base path (python3 `os.path` — no string hacks). It reports `BASE_DIR` and
`STATUS=present|absent`. If present, the step is a silent no-op (idempotent on every later
run). If absent, the orchestrator announces the exact path to be added and confirms once
(Level 0, default `[Y]`); on yes it runs `--apply`, which merges the entry without touching
existing `allow`/`deny`/`additionalDirectories`/`env`, creates and gitignores the settings
file when missing, writes atomically (temp + rename), and re-reads the file to verify it is
valid JSON containing `BASE_DIR`. Corrupt settings → refuse, exit non-zero, no write.

## Decisions

- **Sub-decision of D30 (parallel worktree architecture)** — kept in this archive (Decision
  Log) without a new `D<N>`, matching how the 15 D30 composing sub-bullets were handled in
  slice-009. This one: *"CRAFT maintains the worktree base directory in
  `permissions.additionalDirectories`; the user never hand-maintains per-path allow rules."*
- **Execute-pre-phase step, not a WorktreeCreate hook** — CRAFT creates worktrees with
  `git worktree add` directly, not via the `EnterWorktree` tool, so a `WorktreeCreate` hook
  would not reliably fire. An explicit Procedure step before the first worktree is created
  is the architecture-fitting place. *Cost:* one confirmation on the first run per target.
- **Shipped Bash+python3 helper, not inline Markdown logic** — DRY, testable, reusable by
  both `/craft:execute` and (potentially) onboarding; keeps fragile path/JSON handling out
  of the command spec. Consistent with the repo already shipping Bash under `hooks/`.
- **`additionalDirectories` alone suffices** — no broad path-based Bash allow defaults for
  the worktree tree; one base-dir entry gives the whole tree the project root's trust level.
- **No onboarding pre-seed** — the base directory does not exist before the first
  `/craft:execute`, and the execute step is idempotent; pre-seeding at onboarding would
  duplicate logic for the marginal gain of one saved confirmation. The helper stays reusable
  if that changes.
- **Bootstrap-style slice** — like slice-009, this changes the worktree infrastructure
  itself, so it was built directly on `main` with the classic per-phase flow rather than
  inside `/craft:execute`.

## Commits

- `4a2578d` — feat(execute): auto-trust worktree base dir in additionalDirectories
- `561cda5` — docs(rules): document worktree additionalDirectories maintenance
- `29e342b` — chore(plans): bump slice counter to 15

## Follow-ups

- None. Manually verified the helper across: fresh repo, merge preserving existing
  allow/deny/env, custom + absolute patterns, `permissions` without `additionalDirectories`,
  empty `{}`, idempotent re-apply (no duplicates), and corrupt JSON (refused, file
  untouched). `claude plugin validate` green throughout.
