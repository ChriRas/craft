#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# execute-resume-state.sh — what does a /craft:execute re-run find, per slice? (B8)
#
# WHY ------------------------------------------------------------------------
# /craft:execute used to re-create what an earlier run left behind: `git worktree add -b`
# aborts on an existing branch (exit 255), so a parallel re-run stopped before any
# slice-builder ran, merged slices would have been spawned again, and a sequential re-run
# after a mid-slice stop tripped over its own dirty tree or branch and restarted Phase 4.
# Whether a slice is to be created, reused, skipped or resumed is decided here, once;
# commands/execute.md reads only ACTION= and REASON=.
#
# WHAT -----------------------------------------------------------------------
# Run from the main checkout. The project dir is CLAUDE_PROJECT_DIR (else the cwd) and may sit below
# the repository root (slice-035); `.claude/` is read there, branches and worktrees are the
# repository's. Each slice is passed as its plan path or its slice-ID. A slice
# whose plan is gone but whose archive `.claude/project/slices/<slice-id>-*.md` exists has
# landed (/craft:commit deletes the plan when it closes a slice); while the plan exists the
# slice has not, even if an archive already does (commit writes it before opening a PR).
# Branch and worktree path come from the plan's Slice-ID + Slice-Slug and the patterns.
# Doubt means CONFLICT — the caller stops and overwrites nothing.
#
#   parallel (default), per slice, first match wins:
#     plan unreadable (no Slice-ID / Slice-Slug)                   conflict  plan_unreadable
#     plan gone, archive present                                   skip      archived
#     Status awaiting-approval (a PR is open; /craft:commit completes it)
#                                                                  skip      awaiting_approval
#     merged into the target (epic branch, or trunk for a lone slice): a merge commit whose
#       non-first parent is the branch tip, or — branch since deleted, epic only — a merge
#       commit whose subject is `Merge <slice-id> into <epic-id>`  skip      merged
#     a worktree of the branch is registered, directory gone      conflict  worktree_missing
#     a worktree of the branch exists                              reuse     worktree_exists
#     the branch exists without a worktree                         conflict  branch_without_worktree
#     the pattern path is a registered worktree whose directory is gone
#                                                                  conflict  worktree_missing
#     the pattern path is a worktree on another branch / detached  conflict  worktree_foreign_branch
#     the pattern path exists                                      conflict  path_taken
#     otherwise                                                    create    fresh
#   The epic line (--epic) runs the worktree rows above for the epic branch; an existing epic
#   worktree is not reused while
#     a merge is unfinished in it (MERGE_HEAD)                     conflict  epic_merge_in_progress
#     it has uncommitted changes (its step-9 record .craft/checkpoints.md at the worktree root aside)
#                                                                  conflict  epic_worktree_dirty
#
#   sequential, per slice, first match wins:
#     plan unreadable                                              conflict  plan_unreadable
#     plan gone, archive present                                   skip      archived
#     Status implementing | testing | review | refactoring | reviewing | committing
#                                                                  resume    open
#     Status awaiting-approval                                     resume    awaiting_approval
#     Status paused | blocked                                      held      plan_held
#     Status planning                                              create    fresh
#     any other Status                                             conflict  unknown_status
#   then, for the whole run — a resume or held slice is IN FLIGHT: its work may sit in the tree
#   (on the trunk under direct, on its branch under pull-request):
#     more than one slice in flight → each of them                 conflict  multiple_open
#     --landing pull-request: a slice in flight without its branch conflict  branch_missing
#                             a create slice whose branch exists   conflict  branch_exists
#     the tree is dirty and no slice is in flight                  run-wide  conflict  dirty_without_open_slice
#     pull-request, a slice in flight, current branch ≠ its branch; or direct / nothing in
#       flight, current branch ≠ trunk                             run-wide  conflict  wrong_branch
#   CRAFT's own session files (.claude/plans/.primed, .hook-env, .execute.lock) never count as dirt.
#   Once every slice in flight is itself a conflict (multiple_open, branch_missing), no run-wide
#   reason is added — the tree's changes may be that slice's, and its line names the fix.
#
#   <slice-plan | slice-ID>...     One or more slices.
#   --mode parallel|sequential     Default parallel.
#   --epic <epic-plan>             Parallel epic target: adds the epic line and merges are
#                                  looked up in the epic branch.
#   --trunk <branch>               Default main.
#   --landing direct|pull-request  Sequential only. Default direct.
#   --branch-pattern <p>           Default `<slice-id>-<slug>`.
#   --path-pattern <p>             Default `../<repo>-worktrees/<slice-id>-<slug>/`, relative to
#                                  the repository root. The epic uses both with its Epic-ID/-Slug.
#   --print-actions                Print the <mode>:<reason>=<action> rows above and exit.
#
# Output is line-oriented; a slice or epic line is space-separated KEY=VALUE with WORKTREE
# last (a path may contain spaces):
#   MODE=parallel|sequential  TRUNK=<branch>  CURRENT_BRANCH=<branch>|detached  DIRTY=yes|no
#   EPIC=<id> ACTION= REASON= BRANCH= BRANCH_EXISTS=yes|no WORKTREE=<path>|-
#   SLICE=<id> ACTION=create|reuse|skip|resume|held|conflict REASON= BRANCH= BRANCH_EXISTS=
#     MERGED=yes|no|- ARCHIVED=yes|no PLAN_STATUS=<status>|unknown WORKTREE=<path>|-
#   OPEN_SLICE=<id>|none           (sequential) the one slice in flight
#   CONFLICT_COUNT=<n>
#   RESULT=ok|conflict             conflict whenever any line is a conflict
#   RESULT_REASON=<why>|-          a run-wide conflict reason (sequential), else -
#   ERROR=<reason>                 on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success (any RESULT) · 2 bad arguments · 3 project dir unreachable or not in a git repository ·
# 4 a slice has neither a plan nor an archive, or its slice-ID matches several plans.

set -uo pipefail

ACTIONS="parallel:plan_unreadable=conflict
parallel:archived=skip
parallel:awaiting_approval=skip
parallel:merged=skip
parallel:worktree_missing=conflict
parallel:worktree_exists=reuse
parallel:branch_without_worktree=conflict
parallel:worktree_foreign_branch=conflict
parallel:path_taken=conflict
parallel:fresh=create
parallel:epic_merge_in_progress=conflict
parallel:epic_worktree_dirty=conflict
sequential:plan_unreadable=conflict
sequential:archived=skip
sequential:open=resume
sequential:awaiting_approval=resume
sequential:plan_held=held
sequential:fresh=create
sequential:unknown_status=conflict
sequential:multiple_open=conflict
sequential:branch_missing=conflict
sequential:branch_exists=conflict
sequential:dirty_without_open_slice=conflict
sequential:wrong_branch=conflict"

OPEN_STATUSES=" implementing testing review refactoring reviewing committing "

MODE="parallel"
EPIC_PLAN=""
TRUNK="main"
LANDING="direct"
BRANCH_PATTERN='<slice-id>-<slug>'
PATH_PATTERN='../<repo>-worktrees/<slice-id>-<slug>/'
REFS=()

need_value() { [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:$1" >&2; exit 2; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-actions) printf '%s\n' "${ACTIONS}"; exit 0 ;;
    --mode) need_value "$@"; MODE="$2"; shift 2 ;;
    --epic) need_value "$@"; EPIC_PLAN="$2"; shift 2 ;;
    --trunk) need_value "$@"; TRUNK="$2"; shift 2 ;;
    --landing) need_value "$@"; LANDING="$2"; shift 2 ;;
    --branch-pattern) need_value "$@"; BRANCH_PATTERN="$2"; shift 2 ;;
    --path-pattern) need_value "$@"; PATH_PATTERN="$2"; shift 2 ;;
    --*) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
    *) REFS+=("$1"); shift ;;
  esac
done

[[ "${MODE}" == "parallel" || "${MODE}" == "sequential" ]] || { echo "ERROR=invalid_mode:${MODE}" >&2; exit 2; }
[[ "${LANDING}" == "direct" || "${LANDING}" == "pull-request" ]] || { echo "ERROR=invalid_landing:${LANDING}" >&2; exit 2; }
(( ${#REFS[@]} > 0 )) || { echo "ERROR=missing_argument:<slice-plan|slice-ID>" >&2; exit 2; }
[[ -z "${EPIC_PLAN}" || "${MODE}" == "parallel" ]] || { echo "ERROR=epic_requires_parallel" >&2; exit 2; }

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT}" >&2; exit 3; }
PROJECT="$(pwd -P)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR=not_a_git_repository" >&2; exit 3; }
REL="$(git rev-parse --show-prefix 2>/dev/null)"   # the project dir below the repository root, `/`-terminated or empty
[[ -z "${EPIC_PLAN}" || -f "${EPIC_PLAN}" ]] || { echo "ERROR=plan_not_found:${EPIC_PLAN}" >&2; exit 4; }

archive_of() { compgen -G "${PROJECT}/.claude/project/slices/$1-*.md" >/dev/null; }

# resolve each argument to "plan<TAB><path>" or "landed<TAB><slice-id>"; exit 4 when neither holds
RESOLVED=()
for ref in "${REFS[@]}"; do
  if [[ "${ref}" =~ ^slice-[0-9]+$ ]]; then
    matches=()
    for f in "${PROJECT}/.claude/plans/${ref}-"*.md; do [[ -f "$f" ]] && matches+=("$f"); done
    if (( ${#matches[@]} == 1 )); then RESOLVED+=("plan	${matches[0]}")
    elif (( ${#matches[@]} > 1 )); then echo "ERROR=plan_ambiguous:${ref}" >&2; exit 4
    elif archive_of "${ref}"; then RESOLVED+=("landed	${ref}")
    else echo "ERROR=plan_not_found:${ref}" >&2; exit 4
    fi
  elif [[ -f "${ref}" ]]; then
    RESOLVED+=("plan	${ref}")
  else
    base="$(basename "${ref}")"
    if [[ "${base}" =~ ^(slice-[0-9]+)- ]] && archive_of "${BASH_REMATCH[1]}"; then RESOLVED+=("landed	${BASH_REMATCH[1]}")
    else echo "ERROR=plan_not_found:${ref}" >&2; exit 4
    fi
  fi
done

# `> Key: value` from a plan, trimmed (CR included); a template value listing options with `|` is empty
plan_field() { # file key
  local v
  v="$(grep -m1 "^> $2:" "$1" 2>/dev/null)" || return 0
  v="$(printf '%s' "${v#*:}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ "$v" == *"|"* || "$v" == *" "* ]] && v=""
  printf '%s' "$v"
}

# lexical normalisation of an absolute path: no symlink resolution, `.` and `..` folded
normalize() {
  local IFS='/' part out=()
  for part in $1; do
    case "${part}" in
      ''|.) ;;
      ..) (( ${#out[@]} > 0 )) && unset 'out[${#out[@]}-1]' ;;
      *) out+=("${part}") ;;
    esac
  done
  local joined
  joined="$(printf '/%s' "${out[@]+"${out[@]}"}")"
  printf '%s' "${joined:-/}"
}

# the physical path when the directory exists, else the lexical one
canonical() {
  if [[ -d "$1" ]]; then (cd -P "$1" 2>/dev/null && pwd -P) || normalize "$1"; else normalize "$1"; fi
}

substitute() { # pattern id slug
  local s="$1"
  s="${s//<repo>/$(basename "${ROOT}")}"
  s="${s//<slice-id>/$2}"
  s="${s//<slug>/$3}"
  printf '%s' "$s"
}

expected_path() { # id slug
  local p
  p="$(substitute "${PATH_PATTERN}" "$1" "$2")"
  [[ "$p" == /* ]] || p="${ROOT}/$p"
  canonical "$p"
}

# registered worktrees: WT_PATH[i], WT_BRANCH[i] (branch name, or empty when detached)
WT_PATH=(); WT_BRANCH=()
cur_path=""; cur_branch=""
flush() { [[ -n "${cur_path}" ]] && { WT_PATH+=("$(canonical "${cur_path}")"); WT_BRANCH+=("${cur_branch}"); }; cur_path=""; cur_branch=""; }
while IFS= read -r line; do
  case "${line}" in
    "worktree "*) flush; cur_path="${line#worktree }" ;;
    "branch refs/heads/"*) cur_branch="${line#branch refs/heads/}" ;;
    "") flush ;;
  esac
done < <(git -C "${ROOT}" worktree list --porcelain 2>/dev/null)
flush

branch_exists() { git -C "${ROOT}" show-ref --verify --quiet "refs/heads/$1"; }

worktree_of_branch() { # branch → index, or return 1
  local i
  for i in "${!WT_BRANCH[@]}"; do [[ "${WT_BRANCH[$i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }; done
  return 1
}

worktree_at_path() { # canonical path → index, or return 1
  local i
  for i in "${!WT_PATH[@]}"; do [[ "${WT_PATH[$i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }; done
  return 1
}

# uncommitted changes anywhere in a checkout, CRAFT's own session files (in the project dir) and any
# extra pathspec excluded
is_dirty() { # checkout [extra-exclude-pathspec...]
  local dir="$1"; shift
  [[ -n "$(git -C "${dir}" status --porcelain -- ':(top)' \
    ":(top,exclude)${REL}.claude/plans/.primed" ":(top,exclude)${REL}.claude/plans/.hook-env" \
    ":(top,exclude)${REL}.claude/plans/.execute.lock" "$@" 2>/dev/null)" ]]
}

# is <branch> merged into <target>? Only a merge commit whose non-first parent is the branch tip
# counts: a fresh branch without commits is an ancestor of its target, yet nothing was merged.
is_merged() { # branch target
  branch_exists "$1" && branch_exists "$2" || return 1
  local tip fields i
  tip="$(git -C "${ROOT}" rev-parse "refs/heads/$1")"
  while read -r -a fields; do
    for (( i = 2; i < ${#fields[@]}; i++ )); do [[ "${fields[$i]}" == "${tip}" ]] && return 0; done
  done < <(git -C "${ROOT}" rev-list --merges --parents "refs/heads/$2" 2>/dev/null)
  return 1
}

# a deleted slice branch leaves only execute's merge subject behind; an existing branch is judged
# by its tip alone, so commits added after the merge are never skipped
merged_by_subject() { # branch target slice-id epic-id
  [[ -n "$4" ]] && ! branch_exists "$1" && branch_exists "$2" || return 1
  git -C "${ROOT}" log --merges --format='%s' "refs/heads/$2" 2>/dev/null | grep -qxF "Merge $3 into $4"
}

# the worktree rows shared by the slice and the epic line → "ACTION REASON WORKTREE"
worktree_decision() { # branch id slug
  local i path
  if i="$(worktree_of_branch "$1")"; then
    if [[ -d "${WT_PATH[$i]}" ]]; then printf 'reuse worktree_exists %s' "${WT_PATH[$i]}"
    else printf 'conflict worktree_missing %s' "${WT_PATH[$i]}"; fi
    return
  fi
  if branch_exists "$1"; then printf 'conflict branch_without_worktree -'; return; fi
  path="$(expected_path "$2" "$3")"
  if i="$(worktree_at_path "${path}")"; then
    if [[ ! -d "${path}" ]]; then printf 'conflict worktree_missing %s' "${path}"
    else printf 'conflict worktree_foreign_branch %s' "${path}"; fi
    return
  fi
  if [[ -e "${path}" ]]; then printf 'conflict path_taken %s' "${path}"; return; fi
  printf 'create fresh %s' "${path}"
}

yn() { "$@" && printf yes || printf no; }

CURRENT_BRANCH="$(git -C "${ROOT}" symbolic-ref --quiet --short HEAD 2>/dev/null || printf detached)"
DIRTY="$(yn is_dirty "${ROOT}")"

echo "MODE=${MODE}"
echo "TRUNK=${TRUNK}"
echo "CURRENT_BRANCH=${CURRENT_BRANCH}"
echo "DIRTY=${DIRTY}"

CONFLICTS=0
EPIC_ID=""; EPIC_BRANCH=""
if [[ -n "${EPIC_PLAN}" ]]; then
  EPIC_ID="$(plan_field "${EPIC_PLAN}" Epic-ID)"
  EPIC_SLUG="$(plan_field "${EPIC_PLAN}" Epic-Slug)"
  if [[ ! "${EPIC_ID}" =~ ^epic-[0-9]+$ || -z "${EPIC_SLUG}" ]]; then
    echo "EPIC=${EPIC_ID:-unknown} ACTION=conflict REASON=plan_unreadable BRANCH=- BRANCH_EXISTS=no WORKTREE=-"
    CONFLICTS=$((CONFLICTS + 1))
  else
    EPIC_BRANCH="$(substitute "${BRANCH_PATTERN}" "${EPIC_ID}" "${EPIC_SLUG}")"
    read -r a r w <<<"$(worktree_decision "${EPIC_BRANCH}" "${EPIC_ID}" "${EPIC_SLUG}")"
    if [[ "$a" == "reuse" ]]; then
      if git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then a="conflict"; r="epic_merge_in_progress"
      elif is_dirty "$w" ':(top,exclude).craft/checkpoints.md'; then a="conflict"; r="epic_worktree_dirty"
      fi
    fi
    [[ "$a" == "conflict" ]] && CONFLICTS=$((CONFLICTS + 1))
    echo "EPIC=${EPIC_ID} ACTION=$a REASON=$r BRANCH=${EPIC_BRANCH} BRANCH_EXISTS=$(yn branch_exists "${EPIC_BRANCH}") WORKTREE=$w"
  fi
fi
MERGE_TARGET="${EPIC_BRANCH:-${TRUNK}}"

# collect per-slice facts first; the sequential run-wide rows can rewrite actions
S_ID=(); S_ACTION=(); S_REASON=(); S_BRANCH=(); S_BEXISTS=(); S_MERGED=(); S_ARCHIVED=(); S_STATUS=(); S_WT=()
for entry in "${RESOLVED[@]}"; do
  kind="${entry%%	*}"; val="${entry#*	}"
  branch="-"; bexists="no"; merged="-"; archived="no"; wt="-"; status="unknown"
  if [[ "${kind}" == "landed" ]]; then
    id="${val}"; archived="yes"; action="skip"; reason="archived"
  else
    id="$(plan_field "${val}" Slice-ID)"
    slug="$(plan_field "${val}" Slice-Slug)"
    status="$(plan_field "${val}" Status)"; status="${status:-unknown}"
    if [[ ! "${id}" =~ ^slice-[0-9]+$ || -z "${slug}" ]]; then
      action="conflict"; reason="plan_unreadable"
    else
      branch="$(substitute "${BRANCH_PATTERN}" "${id}" "${slug}")"
      bexists="$(yn branch_exists "${branch}")"
      archive_of "${id}" && archived="yes"
      if [[ "${MODE}" == "parallel" ]]; then
        merged="no"
        if is_merged "${branch}" "${MERGE_TARGET}" || merged_by_subject "${branch}" "${MERGE_TARGET}" "${id}" "${EPIC_ID}"; then merged="yes"; fi
        if [[ "${status}" == "awaiting-approval" ]]; then action="skip"; reason="awaiting_approval"
        elif [[ "${merged}" == "yes" ]]; then action="skip"; reason="merged"
        else read -r action reason wt <<<"$(worktree_decision "${branch}" "${id}" "${slug}")"
        fi
      else
        if [[ "${OPEN_STATUSES}" == *" ${status} "* ]]; then action="resume"; reason="open"
        elif [[ "${status}" == "awaiting-approval" ]]; then action="resume"; reason="awaiting_approval"
        elif [[ "${status}" == "paused" || "${status}" == "blocked" ]]; then action="held"; reason="plan_held"
        elif [[ "${status}" == "planning" ]]; then action="create"; reason="fresh"
        else action="conflict"; reason="unknown_status"
        fi
      fi
    fi
  fi
  S_ID+=("${id:-unknown}"); S_ACTION+=("${action}"); S_REASON+=("${reason}"); S_BRANCH+=("${branch}")
  S_BEXISTS+=("${bexists}"); S_MERGED+=("${merged}"); S_ARCHIVED+=("${archived}"); S_STATUS+=("${status}"); S_WT+=("${wt}")
done

in_flight() { [[ "${S_ACTION[$1]}" == "resume" || "${S_ACTION[$1]}" == "held" ]]; }

RESULT_REASON="-"
OPEN_SLICE="none"
if [[ "${MODE}" == "sequential" ]]; then
  flying=()
  for i in "${!S_ID[@]}"; do in_flight "$i" && flying+=("$i"); done
  had_flight=${#flying[@]}
  if (( ${#flying[@]} > 1 )); then
    for i in "${flying[@]}"; do S_ACTION[$i]="conflict"; S_REASON[$i]="multiple_open"; done
  fi
  if [[ "${LANDING}" == "pull-request" ]]; then
    for i in "${!S_ID[@]}"; do
      if in_flight "$i" && [[ "${S_BEXISTS[$i]}" == "no" ]]; then S_ACTION[$i]="conflict"; S_REASON[$i]="branch_missing"
      elif [[ "${S_ACTION[$i]}" == "create" && "${S_BEXISTS[$i]}" == "yes" ]]; then S_ACTION[$i]="conflict"; S_REASON[$i]="branch_exists"
      fi
    done
  fi
  open_idx=""
  for i in "${!S_ID[@]}"; do in_flight "$i" && { OPEN_SLICE="${S_ID[$i]}"; open_idx="$i"; }; done
  if (( had_flight > 0 )) && [[ -z "${open_idx}" ]]; then
    :   # every slice in flight is a conflict of its own; a run-wide reason would misattribute the tree
  elif [[ "${DIRTY}" == "yes" && -z "${open_idx}" ]]; then
    RESULT_REASON="dirty_without_open_slice"
  elif [[ -n "${open_idx}" && "${LANDING}" == "pull-request" ]]; then
    [[ "${CURRENT_BRANCH}" == "${S_BRANCH[$open_idx]}" ]] || RESULT_REASON="wrong_branch"
  elif [[ "${CURRENT_BRANCH}" != "${TRUNK}" ]]; then
    RESULT_REASON="wrong_branch"
  fi
fi

for i in "${!S_ID[@]}"; do
  [[ "${S_ACTION[$i]}" == "conflict" ]] && CONFLICTS=$((CONFLICTS + 1))
  echo "SLICE=${S_ID[$i]} ACTION=${S_ACTION[$i]} REASON=${S_REASON[$i]} BRANCH=${S_BRANCH[$i]} BRANCH_EXISTS=${S_BEXISTS[$i]} MERGED=${S_MERGED[$i]} ARCHIVED=${S_ARCHIVED[$i]} PLAN_STATUS=${S_STATUS[$i]} WORKTREE=${S_WT[$i]}"
done

[[ "${MODE}" == "sequential" ]] && echo "OPEN_SLICE=${OPEN_SLICE}"
echo "CONFLICT_COUNT=${CONFLICTS}"
if (( CONFLICTS > 0 )) || [[ "${RESULT_REASON}" != "-" ]]; then echo "RESULT=conflict"; else echo "RESULT=ok"; fi
echo "RESULT_REASON=${RESULT_REASON}"
exit 0
