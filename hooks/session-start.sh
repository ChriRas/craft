#!/usr/bin/env bash
#
# ai-coding-tools — SessionStart hook
#
# Behaviour:
#   - If the current project has been onboarded (`.claude/project/intent.md` exists)
#     → emit a directive telling Claude to auto-run /prime.
#   - Otherwise → emit a gentle nudge to /onboard.
#
# Output goes to stdout and is appended to Claude's session context.
# The script never fails the session; on any unexpected error it exits 0 silently
# so the user is not blocked by a broken hook.

set -uo pipefail

# Run in the project root if Claude Code provides it; otherwise stay in cwd.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || exit 0

INTENT_FILE=".claude/project/intent.md"

if [[ -f "${INTENT_FILE}" ]]; then
  cat <<'EOF'
[ai-coding-tools] Project is onboarded. Auto-priming: please run `/prime` now to load project context for this session.
EOF
else
  cat <<'EOF'
[ai-coding-tools] Project is not onboarded. If you intend to use the 8-phase workflow here, run `/onboard` to set up project knowledge (intent.md / rules.md). Otherwise this notice can be ignored.
EOF
fi

exit 0
