# Slice 082 — B38: hooks run from a plugin path with spaces (quoted shell form)

> Completed: 2026-10-12
> Commits: e454950..98e102f (direct on main, no PR)

## What

CRAFT's five hooks now start when the plugin lives at a path with a space. Before, the unquoted path split at the space
and no hook ran — for the read-only guard that meant write protection for `research/` silently off (the control probe
created the file).

## Why

- The path is quoted: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`. The slice first chose the exec form the hooks
  reference prefers, but review round 1 (R1-1) showed that a Claude Code older than 2.1.139 most likely drops `args` and
  runs a bare `bash` that executes code from the hook payload — outside the permission system. The quoted shell form
  fixes the space on every version, needs no minimum version and has no such fallback. `onFailure: "block"` for the
  guard stays roadmap B39.
- Walk-through: the harness check in `scripts/test-toolchain-check.sh` requires the quoted form, forbids `args` and
  compares the registered scripts with `hooks/*.sh` as a set; it was RED against the exec form first, and eight mutated
  copies go red. The pins in `test-cache-guard.sh` / `test-pause-watch.sh` followed. `hooks.json` switched, and
  `claude plugin validate .` lost its quoting warnings. Probes at a path with a space: the old form's SessionStart hooks
  exit 127 and the `research/` file is created; the new form's exit 0 and the write is denied. The docs followed (the
  ≥ 2.1.139 requirement removed again), and the human's second interactive test confirmed it. Review round 2 also
  quoted the plugin root in `/craft:execute`'s worktree-trust check.

## Decisions

- **Quoted shell form instead of exec form** (user, review round 1) — promoted to rules.md → Code Conventions:
  `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`. *Why not* the exec form (`"command": "bash"`, `"args": [...]`), which
  the hooks reference prefers: on a Claude Code older than 2.1.139 it most likely loses `args` (2.1.138's hook schema,
  read from the binary's strings, is a non-strict object without it) and runs a bare `bash` that reads the hook payload
  from stdin as a script — backticks in a prompt or `$(…)` in a Write content then run outside the permission system
  (reproduced with `sh -c bash`). *Why not* exec form with the script as `command` and `"args": []`: a safe fallback,
  but a version-dependent form that needs the exec bit on every hook script.
- **`onFailure: "block"` for the guard stays out of this slice** (user, Phase 3): fail-closed is its own decision — the
  guard also matches Read / Grep / Glob, so a guard that cannot start would block every read; `onFailure` needs Claude
  Code ≥ 2.1.295. Roadmap B39.
- **The check lives in `test-toolchain-check.sh`** (Phase 3): that harness already scans `hooks/*.sh` and runs the hooks
  under `/bin/bash` 3.2; a 29th harness would add a docs-site table row, a CLAUDE.md block and a rules.md line for one
  check.
- **Probe evidence, old vs new form** (Phase 4, Claude Code 2.1.296, sonnet, `acceptEdits`): the same fixture with the
  plugin copied to `…/craft plugin/`. *Old (unquoted):* both CRAFT SessionStart hooks exit 127 (`bash: …/craft: No such
  file or directory`), `.primed` stays, no `.hook-env`, and `research/probe.txt` **is created** — the guard never
  started. *New:* every SessionStart hook exits 0, `.primed` removed, `.hook-env` written, the Write denied, the file
  absent. A first run under `~/.claude/jobs/…` was discarded: Claude Code refuses writes below `~/.claude` as a
  "sensitive file" on its own, which hid the guard — a probe fixture for a write guard must live outside `~/.claude`.
- **Review round 1 → loop-back to Phase 4** — 1 Heavy + needs-rethinking finding (R1-1) routed to Phase 4, with the two
  Light findings R1-2 (the harness compared counts only) and R1-3 (the roadmap F5 note) that described the same hook
  form; route chosen by the user.
- **Scope widened in review round 2** (user): `commands/execute.md`'s `ensure-worktree-trust.sh --check` call quotes the
  plugin root too — the only unquoted Bash-invoked `${CLAUDE_PLUGIN_ROOT}` left in commands/, skills/ and agents/
  (R2-2). Shown by grep only; no probe ran for it.
- **Loop-back evidence** (Phase 4): the harness check (RED against the exec form first) requires the quoted form,
  forbids `args` and compares the registered scripts with `hooks/*.sh` as a set — 8 mutations (unquoted, exec form,
  quoted + `args`, an extra word, a missing script, not bash, a duplicate registration, no hooks) each go RED for their
  own reason, the duplicate only through the set comparison. The quoted-form probe: every SessionStart hook exit 0,
  `.hook-env` written, the Write denied. With the quoted form bash runs the script file and the payload stays data.
- **Human re-test passed after the loop-back** (Phase 5, `[W]`): `--plugin-dir "/tmp/craft-human-082b/craft plugin"` —
  the transcript names that path, never `plugins/cache/craft`; CRAFT's SessionStart hook is recorded as
  `bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"` with `hook_success`, the guard denied the Write into
  `research/`, three prompts raised no hook error, and `.hook-env` names `/opt/homebrew/bin/bash` 5.3.15. CRAFT's two
  UserPromptSubmit hooks print nothing, so the transcript records them only on failure — their run is shown by the
  absence of an error record, not by a success one.

## Commits

- `e454950` — fix(hooks): quote the plugin root in every hook command
- `4032c64` — fix(execute): quote the plugin root in the worktree-trust check
- `1a79499` — docs: record the quoted hook form
- `277ea93` — docs(rules): name the hooks.json form check in the toolchain harness
- `613631e` — docs(roadmap): record B38 as shipped, add B39 and update the F5 note
- `98e102f` — chore(plans): bump slice counter to 83
