#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# tree-dirt-state.sh — does a checkout hold uncommitted work, CRAFT's own files aside? (B14)
#
# WHY ------------------------------------------------------------------------
# /craft:execute A3 and /craft:commit asked `git status --porcelain` for "clean", so CRAFT's
# own files counted as the human's work: a slice plan that is neither tracked nor ignored
# (this repo) failed A3 whenever a plan existed, and the session files were excluded in one
# helper by a list of its own. Which paths count as dirt is decided here, once; the commands
# and scripts/execute-resume-state.sh read only DIRTY=.
#
# WHAT -----------------------------------------------------------------------
# The project dir is CLAUDE_PROJECT_DIR (else the cwd) and may sit below the repository root;
# the excluded paths are anchored there. Never counted as dirt:
#
#   --scope main (default)   the checkout CRAFT orchestrates from — every CRAFT local-state path
#                            (the list scripts/ensure-gitignore.sh --print-paths defines) and
#                            .claude/plans/ (slice and epic plans, the ID counters), whether
#                            tracked, ignored or neither
#   --scope epic-worktree    an epic worktree — the local-state files of that list (a directory
#                            entry such as .craft/ is not excluded wholesale) and execute's
#                            checkpoint record .craft/checkpoints.md at the worktree root. Plans
#                            stay dirt here: slice branches are merged into this checkout.
#
#   --checkout <dir>         The checkout to judge. Default: the repository root of the project dir.
#
# Output is line-oriented key=value:
#   DIRTY=yes|no
#   DIRT=<porcelain line>    one per counted change (porcelain v1), per file — untracked directories are
#                            listed file by file, so a caller can compare paths across two runs
#   ERROR=<reason>           on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success (either answer) · 2 bad arguments · 3 project dir or checkout unreachable,
# or not in a git repository · 5 the local-state list could not be read.
# Bash-3.2-compatible on purpose, like the helper it reads its list from.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOPE="main"
CHECKOUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:--scope" >&2; exit 2; }
      SCOPE="$2"; shift 2 ;;
    --checkout)
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:--checkout" >&2; exit 2; }
      CHECKOUT="$2"; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done
[[ "${SCOPE}" == "main" || "${SCOPE}" == "epic-worktree" ]] || { echo "ERROR=invalid_scope:${SCOPE}" >&2; exit 2; }

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT}" >&2; exit 3; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR=not_a_git_repository:${PROJECT}" >&2; exit 3; }
REL="$(git rev-parse --show-prefix 2>/dev/null)"   # the project dir below the repository root, `/`-terminated or empty
[[ -n "${CHECKOUT}" ]] || CHECKOUT="${ROOT}"
[[ -d "${CHECKOUT}" ]] || { echo "ERROR=checkout_unreachable:${CHECKOUT}" >&2; exit 3; }

PATHS="$(bash "${SCRIPT_DIR}/ensure-gitignore.sh" --print-paths 2>/dev/null)"
[[ -n "${PATHS}" ]] || { echo "ERROR=local_state_list_unreadable:${SCRIPT_DIR}/ensure-gitignore.sh" >&2; exit 5; }

set -- ':(top)'
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if [[ "${SCOPE}" == "epic-worktree" && "$p" == */ ]]; then continue; fi
  set -- "$@" ":(top,exclude)${REL}${p%/}"
done <<EOF
${PATHS}
EOF
if [[ "${SCOPE}" == "main" ]]; then
  set -- "$@" ":(top,exclude)${REL}.claude/plans"
else
  set -- "$@" ':(top,exclude).craft/checkpoints.md'
fi

STATUS="$(git -C "${CHECKOUT}" status --porcelain --untracked-files=all -- "$@" 2>/dev/null)" || {   # one DIRT= line per file, never a collapsed directory
  echo "ERROR=not_a_git_repository:${CHECKOUT}" >&2; exit 3
}

if [[ -z "${STATUS}" ]]; then
  echo "DIRTY=no"
else
  echo "DIRTY=yes"
  while IFS= read -r line; do echo "DIRT=${line}"; done <<EOF
${STATUS}
EOF
fi
exit 0
