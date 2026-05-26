# Slice 009 — Parallel Worktree Execution (C+D+E)

> Status: planning
> Slice-ID: slice-009
> Slice-Slug: parallel-worktree-execution
> Started: 2026-05-26
> Phase: 3
> plugin-version: 0.3.0
> Handoff active: no
> Depends-On: []

## Goal

Ship the autonomous-build orchestration layer: `/craft:execute` runs an epic (or single slice) in parallel git worktrees, builds Phases 4–7 via subagents, merges slice-branches into an epic-branch, stops at epic-end for human review, and provides `/craft:checkout` to inspect either a single slice or the merged epic before final main-merge.

## Vertical Slice Definition

The slice cuts vertically through every layer of the plugin:

- **Commands** — four new (`execute`, `checkout`, `worktree-status`, `worktree-clean`) plus surgical edits to five existing (`plan`, `commit`, `abort`, `archive`, `epic`).
- **Templates** — `slice-plan` (new `Depends-On:` field), `epic-plan` (new optional `## Review Checkpoints`), `rules.md` (new `## Worktree Settings` block).
- **Skills** — `workflow` updated for worktree-aware phase boundaries.
- **Subagents** — new `slice-builder` agent that executes Phase 4–7 autonomously and writes the handoff marker.
- **Hooks** — new marker-file watcher that surfaces ready-for-checkout signals to the user.
- **Docs** — `README`, `intent.md`, `brainstorm-decisions.md` updates.

## Trigger

User runs `/craft:execute <epic-NNN | slice-NNN>` after planning (and optionally epic-shaping) is complete.

## Effect

Per execute-run:

1. **DAG resolution** — execute reads all referenced slice plans, builds a dependency graph from each `Depends-On:` frontmatter, rejects cycles.
2. **Worktree creation** — for each runnable slice (no unmet deps), execute creates `../<repo>-worktrees/slice-NNN-<slug>/` on a fresh branch `slice-NNN-<slug>` checked out from the current epic-branch (or main, for lone-slice execute).
3. **Parallel subagent build** — independent slices launch in parallel via the `slice-builder` subagent. Within a slice, sub-tasks run sequentially.
4. **Phase 4–7 execution** — Build, Recap (auto-draft), self-Review (auto-draft) happen autonomously in the slice-worktree. A subagent that needs human input writes `.craft/handoff.md` and stops.
5. **Per-slice merge** — once a slice's Phase 7 self-review completes without escalation, the slice-branch is merged into the epic-branch (`epic-NNN-<slug>`) inside a dedicated epic-worktree, using `--no-ff`. Dependent slices unblock and start.
6. **Epic-ready signal** — when all slices in the epic are merged (or any slice raises a hard stop), execute stops and surfaces a single "epic ready for review" prompt. For a lone slice, the stop happens after its Phase 7.
7. **User review** — `/craft:checkout slice-NNN` switches to a single slice-worktree; `/craft:checkout epic-NNN` switches to the merged-epic worktree. Both print the stack-pack-specific provisioning hint (no auto-install).
8. **Final commit** — `/craft:commit` (Phase 8) merges `epic-NNN-<slug>` → main with `--no-ff`. For a lone slice, slice-branch → main directly.
9. **Archive cleanup** — `/craft:archive` (Phase 9) removes the slice-worktrees, the epic-worktree, and deletes the slice and epic branches.

For an in-flight epic the user can pause at any time via `/craft:pause`; resume via `/craft:continue`. `/craft:abort` on an in-flight slice prompts before removing its worktree (default no).

## Test Strategy

> **Bootstrap note** — this slice builds the worktree infrastructure that future slices will run inside. It therefore cannot be executed by `/craft:execute` itself (the command does not exist yet). Build it directly on `main`, or on a manually created feature branch, with the classic per-phase `/craft:*` workflow.

- **Static**: `claude plugin validate` passes; no Markdown-frontmatter regressions in templates.
- **Manual smoke (this repo)** — plan a 2-slice epic with `Depends-On: []` and `Depends-On: [slice-X]`, run `/craft:execute epic-NNN`:
  - Two slice-worktrees appear under `../AI-Coding-Tools-worktrees/`
  - First slice merges into the epic-branch before the second starts
  - Both slices complete → "epic ready for review" prompt
  - `/craft:checkout slice-X` switches CWD; `/craft:checkout epic-NNN` shows the merged tree
  - `/craft:commit` produces a single `--no-ff` merge commit to main
  - `/craft:archive` removes all three worktrees and both branches
- **Edge cases**:
  - DAG cycle → execute aborts before any worktree is created.
  - Slice subagent escalates → handoff marker visible, other independent slices still complete.
  - `/craft:abort slice-X` mid-build → asks before worktree-remove, default no.
  - `git worktree add` fails (e.g., path collision) → execute aborts cleanly, no partial state.

## Sub-Tasks

### Templates & Data

- [ ] Add optional `Depends-On: [slice-NNN, ...]` to `templates/slice-plan.md.template` frontmatter (default `[]`).
- [ ] Add optional `## Review Checkpoints` section to `templates/epic-plan.md.template` (default: end-of-epic only).
- [ ] Add `## Worktree Settings` block to `templates/rules.md.template` documenting the two configurable knobs (`worktree_path_pattern`, `branch_name_pattern`) with defaults; both optional.

### Rename — Free Up `/craft:execute` for the Orchestrator

- [ ] Rename `commands/execute.md` → `commands/build.md`. The file ships the Phase-4 build behavior; the rename frees the `execute` name for the new autonomous orchestrator.
- [ ] Sweep all cross-references to `/craft:execute` that refer to the Phase-4 build command and replace with `/craft:build`. Known touch-points:
  - `commands/continue.md` (routing table)
  - `commands/plan.md` (output "Next:" hints)
  - `commands/test.md` and any other phase command that references the previous step
  - `skills/workflow/SKILL.md`
  - `README.md`
  - Any archived slice mentioning the historical name stays as-is (history, not behavior).

### New Commands

- [ ] Create `commands/execute.md` (now empty after rename) — `/craft:execute <epic-or-slice>`: Pre-Assertions (onboarded, target plan exists, no in-flight execute, git tree clean on main), DAG resolution, subagent spawn loop, per-slice delegation to `/craft:build` → `/craft:test` → `/craft:recap` → `/craft:refactor` → `/craft:review` (Phase 4–7) inside each slice-worktree, merge into epic-branch on success, "epic ready" signal, Post-Assertions, output block.
- [ ] Create `commands/checkout.md` — `/craft:checkout <slice|epic>`: resolves worktree path, prints `cd` instruction + stack-pack provisioning hint (no auto-install).
- [ ] Create `commands/worktree-status.md` — `/craft:worktree-status`: lists active worktrees with slice/epic-ID, branch, path, last activity timestamp, handoff-marker presence.
- [ ] Create `commands/worktree-clean.md` — `/craft:worktree-clean`: detects orphans (worktrees whose plan has been archived or no longer exists), lists them, asks before removing.

### Existing Command Edits

- [ ] Modify `commands/plan.md` — add the optional `Depends-On:` question to the Phase-3 dialog; write the frontmatter field. Plan is still written on main (no worktree creation here).
- [ ] Modify `commands/commit.md` — Phase 8 inside a worktree: merges slice-branch → epic-branch with `--no-ff`; Phase 8 on epic-branch: merges epic-branch → main with `--no-ff`. Lone-slice execute path: slice-branch → main directly.
- [ ] Modify `commands/abort.md` — detect active worktree; if present, list uncommitted files, ask "Worktree und Branch entfernen [j/n]?" with default `n`.
- [ ] Modify the Phase-9 archive command (`commands/archive.md` if it exists, otherwise the section of `commands/commit.md` that handles archival) — run `git worktree remove` and `git branch -d` for the slice (and for the epic on epic-archive).
- [ ] Modify `commands/epic.md` — output block now mentions `/craft:execute <epic>` as the next step after slice-decomposition is filled in via `/craft:plan`.
- [ ] Verify `commands/test.md`, `commands/recap.md`, `commands/refactor.md`, `commands/review.md` are safely callable from a subagent context (no interactive prompts that block; if any do, route them through a `.craft/handoff.md` write instead). Adjust as needed.

### Skills & Subagents

- [ ] Update `skills/workflow/SKILL.md` — document worktree-aware phase boundaries: Phase 3 on main, Phase 4–7 in slice-worktree, Phase 8 = merge, Phase 9 = cleanup.
- [ ] Create `agents/slice-builder.md` — autonomous Phase 4–7 executor. Reads slice plan, executes sub-tasks sequentially, writes `.craft/handoff.md` on hard stops (escalation, missing protocol, test failure beyond autonomy threshold).

### Hooks

- [ ] Create `hooks/worktree-handoff-notify.sh` — Stop-hook (or SubagentStop) that scans active worktrees for fresh `.craft/handoff.md` writes and surfaces them to the user with the slice-ID and a one-line summary.
- [ ] Register the hook in `.claude-plugin/plugin.json` under `hooks`.

### Integration & Docs

- [ ] Update `README.md` Quickstart and command reference to document `/craft:execute`, `/craft:checkout`, `/craft:worktree-status`, `/craft:worktree-clean`.
- [ ] Update `.claude/project/intent.md` — move C+D+E out of Active Goals (will happen at Phase 9 archive, but flagged here as a sub-task to ensure it's not missed).
- [ ] Update `brainstorm-decisions.md` — record the cluster of worktree decisions captured during this planning session (numbered continuing from D29).

## Active Rule Overrides

> Stage-2 overrides for this slice. Cleared automatically on Phase 9 cleanup.

(none)

## Bugs

> Filled by `/test` (Phase 5 [B] feedback) or `/debug`.

(none)

## Verification Protocols

> Filled by `/debug` Step 2 (PROTOCOL). Frozen — no mid-loop mutation.

(none)

## Bug Fix Attempts

> Filled by `/debug` Step 3 (AUTONOMOUS LOOP). Audit trail of each attempt.

(none)

## Decisions Made During This Slice

> Captured as architectural / product decisions surface. Phase 9 walks each entry with `[K]/[I]/[R]/[D]` promotion dialog.

The following decisions were captured during Phase 3 planning (2026-05-26) and ship as the architectural baseline of this slice:

- **Worktree location** — `../<repo>-worktrees/<slice-id>/`. *Why not* inside the repo: tools (npm/Docker/IDEs) scan the repo and would confuse worktrees with the main checkout.
- **Worktree lifecycle** — one worktree per slice, alive from start of Phase 4 until Phase 9 cleanup. Created by `/craft:execute`, not by `/craft:plan`. *Why not* per sub-task: cross-sub-task merge coordination would be required and the parallelism gain is marginal.
- **Concurrency model** — multiple slices in parallel, sub-tasks sequential inside a slice. *Why not* sub-task-level parallelism: same coordination cost without proportional gain.
- **Phase distribution** — Plan (Phase 3) on main; Build/Recap/Review (Phase 4–7) in slice-worktree; Commit (Phase 8) = merge slice-branch → epic-branch → main; Archive (Phase 9) = cleanup.
- **Ready-for-checkout signal** — marker file `.craft/handoff.md` in the slice-worktree; a Stop-hook surfaces it. *Why not* PushNotification: we don't want a Claude-Code-API dependency for a debuggable file-based protocol.
- **Recap/Review provisioning** — `/craft:checkout` does only `git worktree`-related work and prints a stack-pack-specific hint (e.g., `composer install`). *Why not* automated provisioning hooks: stack-specific commands are out-of-scope for the universal layer.
- **Merge strategy** — always `--no-ff` merge commits (slice → epic, epic → main). *Why not* squash or rebase: preserves slice-branch topology, makes the parallel-build structure visible in history.
- **Branch naming** — `slice-NNN-<slug>` and `epic-NNN-<slug>`. Configurable via `## Worktree Settings` in `rules.md`.
- **Default review-stop** — end of epic. Per-slice or per-checkpoint stops opt-in via `## Review Checkpoints` in the epic plan. *Why*: per-slice stops produce review fatigue ("klickt ihn nur sinnlos weiter").
- **Merge topology** — slices merge to an epic-branch (in a dedicated epic-worktree), not directly to main. *Why*: enables the "checkout the full epic for review" use case in addition to per-slice inspection.
- **Slice dependencies** — explicit `Depends-On: [slice-NNN, …]` frontmatter. *Why not* heuristic file-overlap detection: too magical, unsafe.
- **Cleanup policy** — automatic worktree-remove and branch-delete at Phase 9 (Archive). *Why*: dovetails with the existing archive cleanup, keeps the filesystem clean.
- **`/craft:abort` behavior** — asks before removing an active worktree, default `n`. *Why*: matches the "Human keeps control" rule for destructive operations.
- **New commands** — `/craft:execute` (orchestrator, fresh after rename), `/craft:checkout`, `/craft:worktree-status`, `/craft:worktree-clean`.
- **Rename Phase-4 build command** — `/craft:execute` → `/craft:build`. *Why*: the autonomous orchestrator needs the semantically strongest name (`execute` = "run a planned thing"); the per-slice Phase-4 step is best described as `build` (= "write the code for one slice"). *Why not* a different name for the orchestrator: the user-facing `/craft:execute <epic>` is the most discoverable framing of "run my plan." A rename is a one-time migration cost; the wrong name lingers forever.
- **Orchestrator delegation model** — the orchestrator does not duplicate Phase 4–7 logic. It invokes `/craft:build`, `/craft:test`, `/craft:recap`, `/craft:refactor`, `/craft:review` per slice inside the slice-worktree, each as a subagent task. *Why not* duplicated phase logic: two code paths drift; one canonical phase implementation is reused across manual and automated runs. The per-phase commands gain a "may be called from a subagent" contract.

These will be walked individually in the Phase 9 `[K]/[I]/[R]/[D]` dialog to decide which get promoted to `brainstorm-decisions.md` as numbered architectural decisions versus living only in this slice's archive entry.

## Recap Draft

> Filled by `/recap` (Phase 6). Becomes the basis for the slice archive in Phase 9.

(not yet recorded)

## Review Findings

> Filled by `/craft:review` (Phase 8). Audit trail — one line per finding: `Severity · Fix-nature · description · resolution`.

(none yet)

## Handoff

> Filled by `/handoff` when context-poisoned. Read by the next session's `/prime`.

(none)

## Pause Note

> Filled by `/pause` when work pauses mid-phase.

(none)
