# Slice 019 — Protected-main PR ("Freigabe ≠ Merge")

> Completed: 2026-07-05
> Commits: c53ebb4..6bf6305 (branch main, no PR — this repo is trunk-based)

## What

`/craft:commit` now acts on the profile's Merge Workflow: when `Merge → Type: pull-request`
with `Protected-main: yes`, the finalize **opens a PR and waits for a real GitHub approval,
then merges via `gh`** — the "Freigabe ≠ Merge" gate — instead of a direct merge. A new
`Status: awaiting-approval` turns it into a two-invocation open-then-resume flow: the first
`/craft:commit` commits + archives, pushes, opens the PR, and halts; a re-run detects the
approval and merges. Direct-merge / trunk projects are unchanged.

## Why

- Second behaviour slice acting on the profile — slice-015/017 built + populated the schema;
  this reads the Merge Workflow block.
- The gate is *real* because `gh pr merge` **without `--admin`** fails until the required
  approval exists (verified against live `gh` 2.95.0) — we wait on branch protection, never
  bypass it. The human **approves**; the system merges.
- Open-then-resume (re-run `/craft:commit`) over a dedicated command: the second step is
  still "finalize the commit", so it stays in `/craft:commit`; the `awaiting-approval` status
  keeps the two phases unambiguous.

## Decisions

- **Approval granularity = `auto`** — lone slice / parallel epic → one PR + approval at the finalize; sequential-epic per-slice is forward-looking (`epic-sequential`). Confirmed the epic's flagged-open default.
- **Open-then-resume, no new command** — the in-place `awaiting-approval` halt is resumed by a re-run of `/craft:commit` (not a dedicated command); the second step is still "finalize the commit". *Why not* a `/craft:merge` gesture: one command, one mental model; the new status disambiguates the two passes. *Why not* inline-poll: it would block the session on a human GitHub action.
- **Profile-driven protected-main** — the gate fires on `Merge → Type: pull-request` + `Protected-main: yes`; `gh api …/branches/<trunk>/protection` detection needs admin, so the profile field is the robust primary (optional detect-and-warn).
- **Verification-debt-first** — `gh pr merge` / branch-protection / required-review mechanics were verified against live `gh` 2.95.0 + GitHub docs before any step was written (training knowledge ~5+ months stale): detect approval via `gh pr view --json reviewDecision`; merge via `gh pr merge --merge` (no `--admin`); re-check at merge time (stale-review dismissal). Works under classic branch protection or rulesets.
- **Approve ≠ merge reinterprets the baseline (human-blessed → promoted to intent.md)** — `/craft:commit` runs `gh pr merge` itself, but only after a real human GitHub PR approval; a deliberate reinterpretation of the Senior-Developer baseline's *"do not self-merge"*. Blessed by the human and promoted to `intent.md`'s Architectural Decisions (epic Decision D).

## Commits

- `c53ebb4` — feat(commit): profile-driven protected-main PR merge gate ("Freigabe ≠ Merge")
- `d5ecabd` — docs: document the protected-main PR flow
- `6bf6305` — chore(plans): bump slice counter to 20

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review. Each is a candidate for a future slice.

- **slice-018 in-place-finalize local cleanup** (carried) — after a protected-main merge of an in-place branch, deleting the merged local branch + switching back to the trunk is still the slice-018 in-place-finalize follow-up; the PR merge itself succeeds.
- **A1 "exactly one plan" vs Epic-finalize multi-plan** (new, pre-existing) — `/craft:commit` A1 requires exactly one plan file, yet Epic-finalize `rm`s every included slice's plan + the epic plan (implying several coexist). slice-019 makes the epic `awaiting-approval` second pass reachable, so this is worth resolving before the protected-main *epic* path ships. Predates slice-019 (A1 unchanged) — candidate for a future slice.

## Review notes

Phase 8 took **3 rounds** (all fixes converged): R1 found a broken two-invocation seam (2nd pass didn't skip Steps 1–5) + 8 light → loop-back; R2 found the fix-#6 A6 regression (over-fired on every finalize run) + 4 light → loop-back; R3 verified the A6 worktree-guard mode-matrix from first principles (fires only for a genuine Standard-on-trunk commit) + 2 residual light fixed in-phase. No Commit-blocking finding remained.

## How (Diagram)

```mermaid
sequenceDiagram
    participant U as You
    participant C1 as /craft:commit (1st)
    participant GH as GitHub
    participant C2 as /craft:commit (2nd)
    U->>C1: /craft:commit (Merge pull-request + Protected-main)
    C1->>C1: commits + decisions + archive (Step 1a/1b skip direct merge)
    C1->>GH: git push + gh pr create #N
    C1-->>U: Status awaiting-approval — approve PR #N, then re-run
    U->>GH: approve PR #N (a real review)
    U->>C2: /craft:commit
    C2->>GH: gh pr view reviewDecision → APPROVED
    C2->>GH: gh pr merge #N --merge (no --admin)
    C2-->>U: PR merged → main; plan deleted; slice closed
```
