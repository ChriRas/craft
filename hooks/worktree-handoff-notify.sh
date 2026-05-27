#!/usr/bin/env bash
#
# craft — Worktree handoff notifier (SessionStart hook)
#
# Behavior:
#   - For each git worktree attached to the current project, check for
#     `<worktree>/.craft/handoff.md` — the universal "human needed" signal
#     written by phase commands when called by the slice-builder subagent.
#   - If any are present, emit a single block listing them so the user sees
#     pending work the moment a new session opens.
#   - Stays silent otherwise.
#
# Output goes to stdout and is appended to Claude's session context.
# Never fails the session; on any unexpected error it exits 0 silently.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || exit 0

# Require git and require we are inside a working tree.
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Iterate non-main worktrees, check for handoff markers.
handoffs=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      wt="${line#worktree }"
      if [[ "$wt" != "$PROJECT_DIR" ]]; then
        marker="$wt/.craft/handoff.md"
        if [[ -f "$marker" ]]; then
          slice_id=$(grep -m1 '^Slice-ID:' "$marker" 2>/dev/null | sed 's/^Slice-ID:[[:space:]]*//')
          status=$(grep -m1 '^Status:' "$marker" 2>/dev/null | sed 's/^Status:[[:space:]]*//')
          title=$(grep -m1 '^#[[:space:]]' "$marker" 2>/dev/null | sed 's/^#[[:space:]]*//')
          slice_id="${slice_id:-unknown}"
          status="${status:-unknown}"
          title="${title:-<no title>}"
          handoffs+="  - ${slice_id} (${status}): ${title}"$'\n'"      at ${wt}"$'\n'
        fi
      fi
      ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)

if [[ -n "$handoffs" ]]; then
  cat <<EOF
[craft] Pending worktree handoffs — slices awaiting human action:
${handoffs}Run /craft:worktree-status for the full overview, or /craft:checkout <slice-id> to inspect.
EOF
fi

exit 0
