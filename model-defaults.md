# Per-Phase Model Defaults

CRAFT routes Code Review to an Opus-pinned `code-reviewer` subagent, and Slice
Execution (when run through the `/craft:execute` orchestrator) to a Sonnet-pinned
`slice-builder` subagent. The other heavy-thinking phases — Plan, Debug autonomous
loop — stay on the active session model because they are dialogic, and a subagent
boundary would break their incremental streaming/pause UX. The orchestrating slash
command stays on the session model and delegates to the subagent at the
appropriate step. See the Default Mapping table for the full picture and the
rationale for each row.

This file documents the default mapping, the per-project override mechanism, and
the resolution rules.

> **Why this design**: Claude Code does not support a `model:` frontmatter field on
> slash commands (`commands/*.md`) — only on subagents (`agents/*.md`). Therefore the
> only way to make a workflow phase run on a specific model is to route the work
> through a subagent. See slice-010 archive for the verification trail.

---

## Default Mapping

| Phase | Phase Command | Delegating Subagent | Model |
|---|---|---|---|
| 3 — Plan | `/craft:plan` | — (dialogic, runs in main session) | session |
| 4 — Execute | `/craft:execute` | `slice-builder` | `sonnet` |
| 5 — Test | `/craft:test` | — (user-driven, no delegation) | session |
| 6 — Recap | `/craft:recap` | — (user-driven dialog) | session |
| 7 — Refactor | `/craft:refactor` | — (small, in-session edits) | session |
| 8 — Review | `/craft:review` | `code-reviewer` | `opus` |
| 9 — Commit | `/craft:commit` | — (mechanical, no delegation) | session |
| Debug (escalated) | `/craft:debug` step 3 | — (interactive loop, session) | session |

Phase 3 and Debug stay on the session model because their value is interactive: the
three universal planning questions and the AUTONOMOUS LOOP's per-attempt
streaming + user-pause UX, respectively. Subagents block their parent on a single
return — they cannot stream incremental bundles or honour a mid-loop user pause.
Delegating either phase would either break the interaction or require routing every
turn through a subagent boundary, which is fragile. Users who want Opus for these
phases switch the session model before invoking the command.

Phases marked **session** run on whatever model the user selected for the active
Claude Code session — CRAFT does not switch the model for them.

### Source of truth

Each agent's `model:` value is declared in its own frontmatter under
`agents/<name>.md`. This table is a human-readable index; the runtime resolution
reads the agent files directly.

---

## Per-Project Overrides

A project may override any agent's model by adding an `## Agent Model Overrides`
section to its `.claude/project/rules.md`:

```markdown
## Agent Model Overrides

- slice-builder: opus
- code-reviewer: haiku
```

### Format

- Section heading must be exactly `## Agent Model Overrides`.
- One entry per line, format `<agent-name>: <model-value>`.
- Allowed model values: `opus`, `sonnet`, `haiku`, `inherit`.
  (Exact model IDs like `claude-opus-4-7` are accepted by some Claude Code
  versions but not officially documented — prefer the short aliases.)
- An empty section, or a missing section, means "use defaults".

### Why a project would override

- **Cost control**: pin everything to `haiku` for low-stakes spike work.
- **Speed**: drop `code-reviewer` to `sonnet` for trivial single-file slices.
- **Capability**: upgrade `slice-builder` to `opus` for a risky migration slice.

---

## Resolution Order

1. **Default** — `model:` from the agent's own frontmatter (`agents/<name>.md`).
2. **Project override** — matching entry in `rules.md` → `## Agent Model Overrides`,
   if present.

Project override wins. No further sources.

---

## Validation

`/craft:prime` reads the overrides during its pre-flight check and reports:

- ✓ Each agent's effective model (default vs. overridden).
- ⚠ Soft warning for unknown agent names in the override block (e.g., typo for a
  removed agent).
- ⚠ Soft warning for invalid model values (anything outside `opus`, `sonnet`,
  `haiku`, `inherit`).

Warnings are non-fatal — `/craft:prime` continues so the user is not blocked from
inspecting and fixing the override.

---

## Verification — does `model:` actually take effect?

[GitHub issue #173](https://github.com/affaan-m/everything-claude-code/issues/173)
reported that the `model:` field in agent frontmatter was non-functional in
earlier Claude Code versions: all agents defaulted to Opus regardless of their
declared model. Before relying on this feature in production, verify the runtime
respects the pin in your installed Claude Code version.

### Procedure

1. Install the latest CRAFT release (`/craft:upgrade`).
2. From any Claude Code session, ask Claude to invoke the `code-reviewer` agent
   via the `Task` tool with `subagent_type: "code-reviewer"` and a trivial
   prompt. You can ask Claude directly:

   > Spawn the `code-reviewer` subagent with the prompt:
   > "Report your model identity in one line — for example,
   > 'I am running on Claude Opus 4.7'. Do not do any other work."
   > Show me its reply.

3. Inspect the agent's reply. If it names the model declared in
   `agents/code-reviewer.md` frontmatter (`opus` / Claude Opus), the pin is
   honoured.
4. If it names a different model (e.g. defaulted to the session model), the
   issue is still present in your version — file an upstream bug and fall back
   to switching the session model manually for review work.

This is a one-shot check per Claude Code version upgrade.
