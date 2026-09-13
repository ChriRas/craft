#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests) — SessionStart hook
#
# Behaviour:
#   - Always clear the per-session prime marker (`.claude/plans/.primed`) so the
#     ensure-primed gate re-triggers this session (and correctly after `/clear`).
#   - If the current project has been onboarded (`.claude/project/intent.md` exists)
#     → emit a directive telling Claude to auto-run /craft:prime.
#   - Otherwise → stay silent. Projects without Craft involvement are not nudged;
#     the user opts in by invoking /craft themselves.
#
# Output goes to stdout and is appended to Claude's session context.
# The script never fails the session; on any unexpected error it exits 0 silently
# so the user is not blocked by a broken hook.

set -uo pipefail

# Run in the project root if Claude Code provides it; otherwise stay in cwd.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || exit 0

# Clear the per-session prime marker so context-dependent commands re-trigger the
# ensure-primed gate this session (and correctly after /clear). Harmless if absent.
rm -f ".claude/plans/.primed" 2>/dev/null || true

INTENT_FILE=".claude/project/intent.md"

if [[ -f "${INTENT_FILE}" ]]; then
  # Record the bash this hook actually runs with. Hooks get Claude Code's own environment,
  # not the user's shell profile, so this can differ from the bash the Bash tool sees;
  # scripts/check-toolchain.sh compares the two during /craft:prime. One record per project
  # folder, rewritten at every session start (the last session started here wins); gitignored.
  # (Hooks must stay bash-3.2-compatible — this record is how an old hook bash gets reported.)
  # The braces silence a failed redirect too: `2>/dev/null` after `>` would apply too late.
  { mkdir -p ".claude/plans" \
      && printf 'HOOK_BASH_VERSION=%s\nHOOK_BASH_PATH=%s\n' "${BASH_VERSION:-unknown}" "${BASH:-unknown}" \
         > ".claude/plans/.hook-env"; } 2>/dev/null || true

  cat <<'EOF'
[craft] Project is onboarded. Auto-priming: please run `/craft:prime` now to load project context for this session.
EOF
fi

exit 0
