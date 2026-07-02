# CRAFT Profile Defaults

The CRAFT profile (`.claude/project/craft-profile.md`) is the single per-project home
for autonomy, commit, merge, language, and model settings. It is **portable** — copy it
into a sibling project to reuse a setup — and **auto-read on every `/craft:prime`**.

When a project has **no** profile file, the implicit profile documented here applies.
These defaults equal the **`balanced`** preset: they reproduce CRAFT's historical
out-of-the-box behaviour, so adopting the profile system changes nothing until a project
actively edits its profile.

This file documents the default values, the resolution rules, and the validation
`/craft:prime` performs.

---

## Default Mapping

| Block | Field | Default | Meaning |
|---|---|---|---|
| Execution | Mode | `worktree` | `/craft:execute` builds slices in throwaway git worktrees outside the repo (parallel-safe). |
| Commit Policy | Auto-commit | `on` | Per-sub-task commits are authored inside the worktree (required by the worktree merge model). |
| Merge Workflow | Type | `direct` | A finished slice/epic merges straight to the trunk via `/craft:commit`. |
| Merge Workflow | Protected-main | `no` | The trunk accepts direct merges; no PR gate. |
| Merge Workflow | Approval | `chat` | Human go-ahead is a chat confirmation, not a GitHub PR review. |
| Merge Workflow | Approval-granularity | `auto` | Sequential epic → per slice; parallel epic → once at epic end. |
| Epic Mode | Default | `parallel` | `/craft:execute <epic>` runs independent slices concurrently in worktrees. |
| Permissions | Scope | `standard` | A moderate permission allowlist (the actual entries live in `settings.local.json`). |
| Operational Language | Chat | system language | The language `/craft:prime` adopts for the session. |
| Operational Language | Commits | `English` | Commit-message language (`/craft:commit`). |
| Operational Language | Comments | `English` | Code-comment language (`/craft:build`, `/craft:review`). |
| Agent Model Overrides | — | none (use defaults) | Subagent models resolve from `model-defaults.md`. See that file. |

> Language and model defaults are unchanged from what CRAFT applied before the profile
> became their home (model defaults: `model-defaults.md`). The profile is now their only
> home — `rules.md` no longer carries these settings (migrated in slice-016).

---

## Named Presets

Three starting profiles ship under `templates/profiles/`. `/craft:onboard` copies one
into `.claude/project/craft-profile.md`; the project may then edit it freely.

| Preset | Execution | Auto-commit | Merge | Epic | Permissions |
|---|---|---|---|---|---|
| `careful` | in-place | off | protected-`main` PR you approve | sequential | minimal |
| `balanced` *(= defaults)* | worktree | on | direct | parallel | standard |
| `autonomous` | worktree | on | direct | parallel | broad |

"Give me the defaults" during onboarding resolves to `balanced`.

---

## Permission Allowlist

The `Permissions → Scope` field records *which* read-only allowlist onboarding wrote; the
concrete entries live in `.claude/settings.local.json` (gitignored). All three scopes are
**read-only** — they auto-allow only non-mutating commands, so trust is never widened
silently and mutating commands always keep prompting. The exact entries per scope are
defined in the Permission Allowlist sub-procedure of `/craft:onboard`:

| Scope (preset) | Read-only allowlist |
|---|---|
| `minimal` (`careful`) | `git status`/`diff`/`log`, `ls` |
| `standard` (`balanced`) | `minimal` + `cat`, `grep`, `git show`, read-only `gh` (`pr view`/`pr list`) |
| `broad` (`autonomous`) | `standard` + `wc`, `head`, `tail`, `git blame`, `gh issue view`/`run view` |

Onboarding merges the tier idempotently — re-running never duplicates entries and never
removes anything already present.

---

## Resolution Order

1. **Profile file** — `.claude/project/craft-profile.md`, if present. Its values win
   wholesale; there is no field-level merge with a preset.
2. **Plugin defaults** — the Default Mapping above, when no profile file exists.

A profile file is self-contained: a missing block or field within it falls back to the
corresponding plugin default, but the file as a whole is the source of truth when present.

---

## Validation

`/craft:prime` reads the profile during context loading and reports it (read-only —
never corrected, per the rules.md Tabu on silent drift correction):

- ✓ The active preset and effective settings when the profile is present and valid.
- ✓ A "no profile — plugin defaults" line, with the default values, when absent.
- ⚠ A drift-style warning when the profile is malformed:
  - an unknown block or field key;
  - a value outside its enum (e.g. `Mode: parallel`);
  - the invalid combination `Auto-commit: off` with `Mode: worktree` (auto-commit can
    only be disabled on the in-place path — the worktree merge model requires commits).

Warnings are non-fatal — `/craft:prime` continues so the user can inspect and fix.
