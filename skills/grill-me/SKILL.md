---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree one question at a time. Slash-invocable as `/craft:grill-me [plan-or-subject]`. Phase 2 entry point of the CRAFT workflow; also usable anytime outside Phase 2 to stress-test an architectural decision.
argument-hint: "[plan-or-subject]"
allowed-tools: ["Read", "Write", "Glob", "Grep"]
disable-model-invocation: true
---

# Grill-Me — Alignment Interview

## Core Prompt

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. **For each question, provide your recommended answer** — never Socratic-only asks; the user can accept, override, or refine.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

---

## Slash Invocation (CRAFT)

When invoked as `/craft:grill-me [plan-or-subject]`:

### Pre-flight

If the subject is the active slice plan:

- `Glob` `.claude/plans/slice-*.md`. If exactly one is active and `$ARGUMENTS` matches its scope (or is empty), `Read` it before starting the interview.
- Otherwise, the subject is whatever the user provides in `$ARGUMENTS` or describes in the first exchange.

### Codebase exploration over user-asking

Where the answer can be derived from the code (e.g. *"what testing framework do you use?"* — look in `composer.json` / `package.json` / `pyproject.toml`), explore via `Read` / `Glob` / `Grep` instead of asking. Respect the user's time.

### Capture decisions

Maintain an internal log of decisions reached. When the interview converges (user signals "enough" or the decision tree is fully resolved):

- **Aligning on a slice plan** → append resolutions to the slice plan under `## Alignment` (or merge into existing sections like `## Goal`, `## Vertical Slice Definition` if vague).
- **Aligning on a project decision** → append to `.claude/grill-me-<subject-slug>-<date>.md` at repo root, or recommend promotion to `.claude/project/intent.md` via `/craft:intent-update`.

### Output format

The interview itself is back-and-forth — one question per agent turn, one answer per user turn. Final block:

```
✓ Grill complete.

Decisions reached:
  - <one-line>
  - <one-line>
  - <one-line>

Captured to: <file or slice section>
Recommended next: <command>
```

### Recommended next steps

- Phase 2 of a new feature → `/craft:plan`
- Mid-slice grill → `/craft:execute` or `/craft:continue`
- Project-level decision worth promoting → `/craft:intent-update`

### Error handling

| Situation | Behavior |
|---|---|
| User says *"you decide"* repeatedly | Surface the pattern: *"I'm providing recommendations for every question, but I need your input on at least the strategic ones (X, Y, Z). Without that, alignment is hollow."* |
| Codebase exploration returns ambiguous results | Surface the ambiguity to the user and ask. Don't pick silently. |
| Interview drags into ground already covered | Recognize convergence; offer to close the session. |

### What this skill does NOT do when slash-invoked

- It does **not** ask multiple questions per response. One at a time, always.
- It does **not** decide on the user's behalf. It recommends; the user picks.
- It does **not** modify `intent.md` or `rules.md` directly. Promotions happen via `/craft:intent-update` or Phase 9's promotion dialog.
