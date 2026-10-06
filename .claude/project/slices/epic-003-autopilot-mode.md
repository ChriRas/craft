# Epic 003 — Autopilot Mode

> Completed: 2026-10-06 (started 2026-09-15)
> Slices: 10/10 landed · trunk-based; slice-060 via the first autopilot run (`ae0875c Merge epic-003: Autopilot Mode`)
> Closed by hand: an autopilot epic has no close path in CRAFT yet (roadmap B24)

## Vision

CRAFT concentrates human control at planning, recap, review and escalated bugs, so an epic of finely planned slices
still needed a human at every Phase-5 demo, review rethink and commit dialog — the per-step control D29 already found too
slow once work can be parceled out. Autopilot mode (D32) is the explicit, opt-in inversion: the human defines an epic,
approves one plan package after an agent architect review, and signs off at the epic end; in between a lean master
session plans, builds in place on the epic branch, verifies each slice against its committed Test Strategy, reviews it
with a fresh-context reviewer, breaks review ping-pong deterministically and commits atomically — escalating only
direction calls, a tripped breaker or a budget stop. At the end the human holds an epic branch plus a digest and
decides the merge to `main`.

Scope edges held: no autopilot in parallel worktrees (B15), no push or merge to `main` without the human, no autonomous
edits to `intent.md` / `rules.md`, the idle cache guard outside autopilot stays F7, the Workflow tool is not the engine,
and non-Claude-Code agents stay F8.

## Slices (10/10)

- [slice-045 — builder-return-probe](./slice-045-builder-return-probe.md) — spike: how a builder's result reaches the master; decided Q8, foreground builders via `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`.
- [slice-046 — Model Tiers](./slice-046-model-tiers.md) — the allowed model values declared once and bound everywhere; per-agent model / effort / cache TTL; `fable` human-chosen only.
- [slice-049 — Autopilot Loop](./slice-049-autopilot-loop.md) — `/craft:execute epic-NNN --autopilot`: the in-place slice loop on the epic branch, Level-2 commits, the Autopilot Log, digest and merge-on-yes sign-off.
- [slice-051 — Autonomous Verification](./slice-051-autonomous-verification.md) — Phase 5 by command (`verify-run.sh`, D35) instead of the human stop; the UX demo script for the epic end.
- [slice-052 — Ping-Pong Breaker](./slice-052-ping-pong-breaker.md) — one autonomous loop-back per Heavy + Rethink finding, the round cap, the ≤ 15-line escalation package.
- [slice-053 — Autonomous Debug Loop](./slice-053-autonomous-debug-loop.md) — `/craft:debug` inside autopilot against a protocol two agents froze; every verdict by `verify-run.sh`.
- [slice-054 — Planning Pipeline](./slice-054-planning-pipeline.md) — slice-planner fan-out and the one plan gate with the run briefing.
- [slice-055 — Plan Architect Review](./slice-055-plan-architect-review.md) — the plan-architect reviews the package before the gate, ≤ 2 autonomous revision rounds.
- [slice-058 — Autopilot Budget Guard](./slice-058-budget-guard.md) — the statusline tap and `usage-state.sh`: stops before a slice, inside one and after one by the plan's usage windows.
- [slice-060 — cache-guard](./slice-060-cache-guard.md) — a `UserPromptSubmit` hook blocks a cold-cache human answer at an autopilot stop; built and landed by the first autopilot run.

Outside the decomposition but on the epic's path: [slice-047](./slice-047-harness-fence-parser.md) (finished without
widening), [slice-050](./slice-050-b19-delete-safe-cleanup.md) (B19 delete-safe, needed before an autopilot run on a
machine with a deny rule on `rm`), [slice-056](./slice-056-b21-autopilot-skip-phase7.md),
[slice-057](./slice-057-b22-autopilot-digest-drift.md) and [slice-059](./slice-059-statusline-tap-wiring.md);
slice-048 was aborted and not carried to the roadmap.

## Epic Decisions

- **Design record is the source** (2026-09-15) — verified facts, touchpoint matrix, architecture, ping-pong breaker,
  budget / cache guard and the user decisions Q1–Q4, Q7 live in `.claude/project/design/autopilot-mode.md`; child slices
  planned against it, not against the epic summary.
- **Design §8 item 1 dropped** (2026-09-15) — "D32 + intent update" was already done: D32 is banked in
  `brainstorm-decisions.md` and `intent.md` carries autopilot as the opt-in inversion.
- **Vertical order: loop first, then remove stops** (2026-09-15, user-approved) — `autopilot-loop` ran an already-planned
  epic end to end while every remaining human touchpoint still escalated; each later slice replaced one stop. The probe
  and model tiers preceded the loop because they decided its shape and its per-spawn models.
- **Finding IDs reuse the shipped record** (2026-09-15, user-approved) — the breaker builds on `R<round>-<n>` and
  `scripts/review-findings-state.sh` (slice-037), not the design record's proposed `F<round>-<n>`.
- **Deferred decisions, each settled by its slice** — Q8 foreground builders (slice-045); direct commits on the epic
  branch, autopilot as the sequential path's `--autopilot` variant, R1-15 deferred to roadmap B18 (slice-049); the
  budget thresholds and the `## Autopilot` profile block (slice-058); the cache guard bound to the armed session, the
  restart `/clear` → `/craft:execute epic-NNN --autopilot`, the `Cache-guard-recache-tokens` threshold (slice-060).
  Details in each slice's archive.
- **Unowned: duplicate delivery in today's CRAFT** (slice-045 R1-7) — in an interactive session with fork mode on, a
  direct delegation to `craft:code-reviewer` received its result twice; shipped surface outside every entry's scope.
- **Step back: review findings stop setting the agenda** (2026-09-29, user) — after two weeks no autopilot functionality
  existed: slice-046 ran nine review rounds hardening a harness, whose findings spawned slice-047 and slice-048. Decided:
  slice-047 finished without widening, slice-048 aborted, **Phase 8 calibrated to real risk** — in `rules.md`, and
  plugin-wide through `ping-pong-breaker`.
- **`planning-pipeline` split** (2026-09-30, user) — the plan-architect review became its own entry
  `plan-architect-review`; `planning-pipeline` kept the planner fan-out, the plan gate, the briefing and the judgment line.
- **`budget-and-cache-guard` split** (2026-10-06) — into `budget-guard` (slice-058) and `cache-guard` (slice-060).
- **Epic decisions kept here (`[K]`)** — closed by hand without the `[K]/[I]/[R]/[D]` walk of an Epic-finalize; nothing
  promoted to `intent.md` / `rules.md`. A promotion stays open to the human.

## First autopilot run (slice-060, 2026-10-06)

The epic's own last slice was the first real run: the builder built and verified it unattended, review round 1 hit the
fix cap and stopped the run (`awaiting-rethink-decision`), an interactive round 2 found a harness the slice had turned
red (`test-delete-safe.sh`, R2-1), the re-run landed the slice at a3, and the human walked the cache-guard hands-on test
before answering the sign-off `[Y]`. Gaps it showed: the demo block's "Try this" was too vague for a human to follow
(rewritten into exact steps at a5), the plan gate does not check the verify-block grammar, and an autopilot epic has no
close path (this archive was written by hand).

## Open follow-ups

- **B24 — closing an autopilot epic** — no CRAFT command writes this archive or closes the epic plan after a5 (roadmap).
- **Release 2.0.0 held** (user, 2026-10-06) — the user has a few more things to do first (roadmap → Notes).
- **slice-060** — human test (c) part B (real idle ≥ 1 h) owed; R1-1 / R1-2 in its archive.
- **slice-051 R1-18, slice-049 R1-11 / R1-13, slice-058 R2-11, slice-046 R1-21 / R1-22** — in their archives.
- **B23 / B18** — autopilot master drift and the handoff-answer record (roadmap).
