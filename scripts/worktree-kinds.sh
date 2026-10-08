#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# worktree-kinds.sh — which linked worktrees are CRAFT's? (slice-078, roadmap B33)
#
# WHY ------------------------------------------------------------------------
# /craft:commit asked `git worktree list --porcelain` for "only the main worktree" at three sites: Mode
# Detection step 0 (a finished epic), step 1 (Standard mode) and A6 (the protected-main guard). Any worktree
# counted, so one CRAFT does not own decided the mode: at the epic-005 close (2026-10-08) a detached worktree
# kept a closable epic from Epic-close, and /craft:commit answered with A1/A2's slice messages. Under
# protected main the same worktree switches A6 off, and a Standard commit lands on a trunk that cannot be
# pushed. Which worktrees count is decided here, once; commit.md reads only the counts and the lines.
#
# WHAT -----------------------------------------------------------------------
#   worktree-kinds.sh
#
# Run from the project root (or set CLAUDE_PROJECT_DIR); any checkout of the repository answers the same,
# a linked worktree included. One line per worktree except the main one (the porcelain's first entry), in
# the porcelain's order, then the counts:
#
#   KIND=craft|foreign BRANCH=<branch>|(detached) WORKTREE=<path>
#   CRAFT_COUNT=<n>
#   FOREIGN_COUNT=<n>
#
# WORKTREE is the last field and may hold spaces. A worktree is `craft` when its branch carries a
# `slice-<NNN>` or `epic-<NNN>` token — the ID `<slice-id>` / `<epic-id>` puts into every branch CRAFT
# creates, so a custom `Branch name pattern` (`feature/slice-012-x`) counts too, and a close branch
# `epic-<NNN>-<slug>-close` with it. The token starts the branch or follows a character that is no letter or
# digit, and its digits end the branch or are followed by `-` or `/`. Everything else is `foreign`: a
# detached worktree, a branch without the token. A worktree whose directory is gone (prunable) is classified
# by its branch like any other.
#
# Reading a CRAFT worktree as foreign errs safe at every reader: commit.md step 0's epic-close-state.sh still
# requires every entry landed and the epic branch merged; step 1 reads Standard mode instead of Slice-finalize,
# where A3 ("nothing to commit") or the human-reviewed commit split stops it, and A6 — which reads that mode
# (slice-079) — fires rather than stepping aside;
# Step 7's In-place-finalize lands an in-place branch on the trunk; execute.md P5–P7 warn rather than pass. So a
# slice worktree caught detached (mid-rebase) is foreign here — the `·` line says it is on no slice or epic
# branch, which is true of its checkout at that moment.
# KNOWN LIMIT: a `Branch name pattern` without `<slice-id>` makes its slice worktrees read foreign.
#
# Errors print ERROR=<reason> on stderr and nothing on stdout. Exit codes: 0 success · 2 bad arguments ·
# 3 project dir unreachable, or not in a git repository.

set -uo pipefail

[[ $# -eq 0 ]] || { echo "ERROR=unknown_argument:$1" >&2; exit 2; }

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT}" >&2; exit 3; }
LIST="$(git worktree list --porcelain 2>/dev/null)" || { echo "ERROR=not_a_git_repository:${PROJECT}" >&2; exit 3; }

TOKEN='(^|[^A-Za-z0-9])(slice|epic)-[0-9]+([-/]|$)'
CRAFT=0
FOREIGN=0
OUT=""
N=0          # worktree entries seen; the first is the main worktree
WT=""
BR=""

flush() {
  [[ -n "${WT}" ]] || return 0
  N=$((N + 1))
  if [[ ${N} -gt 1 ]]; then
    if [[ -n "${BR}" && "${BR}" =~ ${TOKEN} ]]; then
      KIND=craft; CRAFT=$((CRAFT + 1))
    else
      KIND=foreign; FOREIGN=$((FOREIGN + 1))
    fi
    OUT="${OUT}KIND=${KIND} BRANCH=${BR:-(detached)} WORKTREE=${WT}"$'\n'
  fi
  WT=""; BR=""
}

while IFS= read -r line; do
  case "${line}" in
    "worktree "*)          flush; WT="${line#worktree }" ;;
    "branch refs/heads/"*) BR="${line#branch refs/heads/}" ;;
    "")                    flush ;;
  esac
done <<EOF
${LIST}
EOF
flush

printf '%s' "${OUT}"
echo "CRAFT_COUNT=${CRAFT}"
echo "FOREIGN_COUNT=${FOREIGN}"
exit 0
