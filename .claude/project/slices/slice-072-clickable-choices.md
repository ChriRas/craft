# Slice 072 — clickable-choices

> Completed: 2026-10-08
> Commits: ab2aa1a..40c033f (branch only — epic-005-comfort-and-flow, no PR)

## What

In an interactive session every human choice CRAFT asks for — lettered menus, yes/no confirmations and open questions
with typical answers — is now specified as an `AskUserQuestion` click (D40). Subagent Mode and headless `claude -p` keep
the rendered full legend / handoff. `/craft:abort` confirms with two clicks instead of a typed slice ID. The stops that
arm the autopilot's cache guard stay typed text.

## Why

- Every switch between clicking and typing is friction at points where the answer is a choice (D40, banked at planning).
- A click returns as a tool result, so the `UserPromptSubmit` cache-guard hook never sees it: the autopilot's stops that
  arm the guard (orphan question, plan gate, a5 sign-off, any question a run stops to ask) keep the typed legend
  (review R1-1, amended into D40).

## Decisions

- **D40 banked** (2026-10-08) — every human choice is a click in an interactive session; see `brainstorm-decisions.md`.
- **One rule, not per-site edits** (2026-10-08) — nearly every menu site already points at the lettered-choice-prompt
  convention in `skills/workflow/SKILL.md` (abort, onboard ×4, worktree-clean, commit, test, unblock); rewriting that one
  rule changes them all. Only sites that contradict it (`test.md`'s single-letter wording, `abort.md`'s typed ID) are
  edited — no second copy of the rule (rules.md tabu).
- **`/craft:abort`: two clicks** (2026-10-08, human choice over "keep typed" and "one click") — the second question
  names the slice-ID and that it cannot be undone.
- **Open questions offer suggestions** (2026-10-08, human choice) — context-derived options + "Other"; questions with no
  meaningful presets (Vision, bug description) stay typed.
- **Interactive test left for the epic-end sign-off** (2026-10-08, autopilot) — the Test Strategy's five-step human script is
  ready in this plan; the autopilot's Phase 5 is verified by the `craft:verify` block (D35), and the product feel of the
  click goes to the human at the epic end. `AskUserQuestion` is not in the commands' `allowed-tools`; the human test must
  confirm it is not needed there (a built-in tool, expected to need no pre-approval).
- Phase 7 skipped (project rule)
- **Review round 1 → loop-back to Phase 4** (2026-10-08) — 1 Heavy + needs-rethinking finding (R1-1, cache guard bypassed by clicks at the autopilot's human stops) routed to Phase 4; route chosen by the autopilot rule (one autonomous loop-back per finding, slice-052). The three Light findings were fixed in-phase.
- **Limits** (2026-10-08, from the tool schema in this session) — 2–4 options per question plus automatic "Other", up to
  four questions per call; unavailable in subagents and headless `-p` (Claude Code docs).

## Commits

- `ab2aa1a` — docs(decisions): amend D40 with the cache-guard exception
- `9662b2a` — feat(workflow): ask every human choice as an AskUserQuestion click
- `1ef2ba1` — feat(abort): confirm with two clicks, the second naming the slice
- `40c033f` — docs(clickable-choices): document click prompts in the docs page and changelog
