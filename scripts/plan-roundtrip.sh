#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# plan-roundtrip.sh — a slice plan's round trip through a worktree: hand-in, read-back, release (B15, slice-067)
#
# WHY ------------------------------------------------------------------------
# In parallel worktree mode a slice is built in a worktree, but its plan lives in the main checkout, where plans
# are excluded from git on purpose (slice-039: CRAFT's own files are not the human's work). A worktree is a
# checkout of its base, so the plan reached it only when it was committed — /craft:execute stopped on
# `plan_not_committed` otherwise — and the finished plan (Status: committing, recap, review findings) never
# came back, so /craft:commit, which reads the main checkout, could not detect a Slice-finalize. The copy
# itself would then block `git worktree remove` (an untracked file). Nothing here is a git operation on the
# slice's work: the three subcommands move one plan file, guarded by a record, and make the copy harmless.
#
# WHAT -----------------------------------------------------------------------
# Run from the main checkout. The project dir is CLAUDE_PROJECT_DIR (else the cwd) and may sit below the
# repository root; <plan> is a path below it (relative to it, or absolute) and is mirrored at the same
# project-relative path inside the worktree.
#
#   plan-roundtrip.sh in      --worktree <dir> <plan>   hand-in, /craft:execute step 5, right after
#                                                       `git worktree add` — and for a reused worktree that has
#                                                       no record (an interrupted earlier run): the main checkout's
#                                                       plan is copied into the worktree (unchanged when the
#                                                       worktree already holds it byte-identical, as it does for a
#                                                       plan the base commits). Without a record a worktree copy
#                                                       that is not the worktree HEAD's version is a plan somebody
#                                                       worked on: conflict worktree_changed, never overwritten
#   plan-roundtrip.sh back    --worktree <dir> <plan>   read-back, /craft:execute step 6, after the slice work is
#                                                       committed: the worktree's plan is copied to the main
#                                                       checkout — only when it reads Status: committing; a main
#                                                       copy already identical to it is `unchanged`, record or not
#   plan-roundtrip.sh release --worktree <dir> <plan>   /craft:commit Step 7, before `git worktree remove`: the
#                                                       worktree's copy is made no obstacle to the removal
#
# The record <worktree>/.craft/plan-roundtrip holds SLICE_ID=, PLAN= (relative to the repository root),
# MAIN=<hash> and WORKTREE=<hash> of the last hand-in or read-back. `in` writes it, `back` updates it,
# `release` checks the worktree copy against it. Nothing is overwritten unseen: a main copy or a worktree
# copy that changed since is a conflict, and so is a missing record or one that names another slice (doubt
# means conflict — a worktree made by a run before this slice has no record). The record hides itself:
# `in` makes sure <worktree>/.craft/.gitignore lists `/.gitignore` and `/plan-roundtrip` — written with exactly
# those two lines when missing, the one line appended when only that is missing, an existing line never
# rewritten or removed (slice-066's step 9 writes the same file with `/checkpoints.md`). It lists nothing else, so
# any other file under .craft/ (the handoff marker) stays visible to git.
#
# `release`: a plan copy the worktree's HEAD tracks is restored to HEAD; an untracked copy prints ACTION=close
# and PROJECT=<the worktree's project dir> — the agent closes it through /craft:commit's *Closing an untracked
# plan* (close-file.sh, D34), and nothing here removes anything. Before that, when git does not already ignore
# the worktree's <prefix>.claude/plans/.closed/ (a project without the CRAFT local-state block), `release`
# writes `.closed/.gitignore` with the one line `*`, so a move-mode close leaves nothing git sees. Likewise, at the
# worktree root and below a subdirectory project's prefix, each local-state file of ensure-gitignore.sh's list that
# sits in .claude/plans/ — the .primed seed execute step 5 writes, a session hook's .hook-env — is hidden when git does
# not ignore it (a `.claude/plans/.gitignore` listing itself and the file; a one tracked by the project is left alone),
# and what is left under <worktree>/.craft/ — a resolved handoff marker, `.craft/handoff-resolved-<Written>.md` — is
# hidden as a whole (a `*` line appended to `.craft/.gitignore`). At release the slice has landed and no handoff is live,
# so nothing is hidden that a human still needs; before it, `in` hides the record alone. This is what lets `git worktree
# remove` succeed whatever the project's .gitignore covers.
#
# Copies go through a temp file next to the target and a rename, with a byte check on both sides.
# This helper holds no removal command (D34).
#
# Output is line-oriented key=value:
#   in:       RESULT=copied|unchanged|conflict  [REASON=]  SLICE_ID=  PLAN=<the worktree's copy>
#   back:     RESULT=copied|unchanged|conflict|refused  [REASON=]  SLICE_ID=  PLAN=<the main checkout's copy>
#   release:  RESULT=released|conflict  ACTION=none|close  [REASON=]  SLICE_ID=  PLAN=<the worktree's copy>
#             PROJECT=<the worktree's project dir>  TRACKED=yes|no
#   REASON (conflict): main_changed (the main plan differs from the record's) · worktree_changed (the worktree
#     copy differs from the record's) · no_record · record_other_slice;  (refused): not_committing
#   ERROR=<reason>  on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success (any RESULT, a conflict or refusal included) · 2 bad arguments (also a worktree that
# is the main checkout) · 3 not in a git repository · 4 plan, worktree or worktree plan not found, or no
# Slice-ID in the plan · 5 a copy or a write failed (ERROR=copy_failed / write_failed).

set -uo pipefail

fail() { echo "ERROR=$1" >&2; exit "$2"; }

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
WORKTREE=""; PLAN_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--worktree" 2; WORKTREE="$2"; shift 2 ;;
    --*)        fail "unknown_argument:$1" 2 ;;
    *)          [[ -z "${PLAN_ARG}" ]] || fail "one_plan_only" 2; PLAN_ARG="$1"; shift ;;
  esac
done
case "${CMD}" in in|back|release) ;; *) fail "unknown_command:${CMD:-none}" 2 ;; esac
[[ -n "${WORKTREE}" ]] || fail "missing_value:--worktree" 2
[[ -n "${PLAN_ARG}" ]] || fail "missing_argument:<plan>" 2

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT}" 2>/dev/null || fail "project_dir_unreachable:${PROJECT}" 3
PROJECT="$(pwd -P)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not_a_git_repository:${PROJECT}" 3
REL="$(git rev-parse --show-prefix 2>/dev/null)"   # the project dir below the repository root, `/`-terminated or empty

# the plan, project-relative
case "${PLAN_ARG}" in
  /*) case "${PLAN_ARG}" in "${PROJECT}"/*) PLAN_REL="${PLAN_ARG#"${PROJECT}"/}" ;; *) fail "plan_outside_project:${PLAN_ARG}" 2 ;; esac ;;
  *)  PLAN_REL="${PLAN_ARG#./}" ;;
esac
MAIN_PLAN="${PROJECT}/${PLAN_REL}"

[[ -d "${WORKTREE}" ]] || fail "worktree_not_found:${WORKTREE}" 4
WT="$(cd -P "${WORKTREE}" && pwd -P)"
git -C "${WT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "worktree_not_found:${WORKTREE}" 4
[[ "${WT}" != "${ROOT}" ]] || fail "worktree_is_the_main_checkout:${WORKTREE}" 2
WT_TOP="$(git -C "${WT}" rev-parse --show-toplevel 2>/dev/null)"
[[ "${WT_TOP}" == "${WT}" ]] || fail "worktree_not_found:${WORKTREE}" 4
WT_PLAN="${WT}/${REL}${PLAN_REL}"
WT_PROJECT="${WT}"; [[ -n "${REL}" ]] && WT_PROJECT="${WT}/${REL%/}"
CRAFT_DIR="${WT}/.craft"
RECORD="${CRAFT_DIR}/plan-roundtrip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_STATE="$(bash "${SCRIPT_DIR}/ensure-gitignore.sh" --print-paths 2>/dev/null)"   # CRAFT's local-state list, defined there once
[[ -n "${LOCAL_STATE}" ]] || LOCAL_STATE=".claude/plans/.primed"

hash_of() { git hash-object -- "$1" 2>/dev/null; }

# `> Key: value` from a plan, trimmed (CR included)
plan_field() { # file key
  local v
  v="$(grep -m1 "^> $2:" "$1" 2>/dev/null)" || return 0
  printf '%s' "${v#*:}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

rec() { sed -n "s/^$1=//p" "${RECORD}" 2>/dev/null | head -1; }

# copy through a temp file next to the target, a rename, and a byte check on both sides
copy_plan() { # src dst
  local tmp="$2.roundtrip-tmp"
  mkdir -p "$(dirname "$2")" 2>/dev/null || fail "copy_failed:mkdir:$2" 5
  cp -- "$1" "${tmp}" 2>/dev/null || fail "copy_failed:$2" 5
  cmp -s "$1" "${tmp}" || fail "copy_failed:verify:${tmp}" 5
  mv -f -- "${tmp}" "$2" 2>/dev/null || fail "copy_failed:rename:$2" 5
  cmp -s "$1" "$2" || fail "copy_failed:verify:$2" 5
}

# an atomic small-file write
write_file() { # path content
  local tmp="$1.roundtrip-tmp"
  printf '%s\n' "$2" > "${tmp}" 2>/dev/null || fail "write_failed:$1" 5
  mv -f -- "${tmp}" "$1" 2>/dev/null || fail "write_failed:$1" 5
}

# <worktree>/.craft/.gitignore hides the record and itself, and nothing else; an existing line stays
ensure_craft_ignore() {
  mkdir -p "${CRAFT_DIR}" 2>/dev/null || fail "write_failed:${CRAFT_DIR}" 5
  local f="${CRAFT_DIR}/.gitignore"
  if [[ ! -f "$f" ]]; then
    write_file "$f" "$(printf '/.gitignore\n/plan-roundtrip')"
  elif ! grep -qxF '/plan-roundtrip' "$f"; then
    if [[ -s "$f" && -n "$(tail -c1 "$f")" ]]; then printf '\n' >> "$f" || fail "write_failed:$f" 5; fi
    printf '/plan-roundtrip\n' >> "$f" || fail "write_failed:$f" 5
  fi
}

# The local-state files of ensure-gitignore.sh's list that live in .claude/plans/ of <dir> (the worktree root, or the
# project dir below it) are hidden by <dir>/.claude/plans/.gitignore — it lists itself and each such file that exists
# and that git does not ignore; an existing line stays, and a .gitignore the project tracks is left alone.
hide_local_state() { # dir relative to the worktree root: "" or the `/`-terminated prefix
  local d="$1.claude/plans" name lines="" f line
  [[ -d "${WT}/${d}" ]] || return 0
  while IFS= read -r name; do
    case "${name}" in .claude/plans/*) ;; *) continue ;; esac
    case "${name}" in */) continue ;; esac
    name="${name#.claude/plans/}"
    [[ -e "${WT}/${d}/${name}" ]] || continue
    if git -C "${WT}" check-ignore -q -- "${d}/${name}" 2>/dev/null; then continue; fi
    lines="${lines}/${name}"$'\n'
  done < <(printf '%s\n' "${LOCAL_STATE}")
  [[ -n "${lines}" ]] || return 0
  f="${WT}/${d}/.gitignore"
  if git -C "${WT}" ls-files --error-unmatch -- "${d}/.gitignore" >/dev/null 2>&1; then return 0; fi
  if [[ ! -f "$f" ]]; then
    write_file "$f" "$(printf '/.gitignore\n%s' "${lines%$'\n'}")"
    return 0
  fi
  if [[ -s "$f" && -n "$(tail -c1 "$f")" ]]; then printf '\n' >> "$f" || fail "write_failed:$f" 5; fi
  for line in /.gitignore ${lines}; do
    grep -qxF -- "${line}" "$f" || printf '%s\n' "${line}" >> "$f" || fail "write_failed:$f" 5
  done
}

# At release the slice has landed and no handoff is live, so everything left under <worktree>/.craft/ is CRAFT's
# own — a resolved marker (.craft/handoff-resolved-<Written>.md), a checkpoint line — and is hidden as a whole,
# unless git already ignores it (a project's CRAFT block at the worktree root).
hide_craft_dir() {
  [[ -d "${CRAFT_DIR}" ]] || return 0
  if git -C "${WT}" check-ignore -q -- ".craft/handoff-resolved-probe.md" 2>/dev/null; then return 0; fi
  local f="${CRAFT_DIR}/.gitignore"
  if git -C "${WT}" ls-files --error-unmatch -- ".craft/.gitignore" >/dev/null 2>&1; then return 0; fi
  if [[ ! -f "$f" ]]; then write_file "$f" '*'
  elif ! grep -qxF '*' "$f"; then
    if [[ -s "$f" && -n "$(tail -c1 "$f")" ]]; then printf '\n' >> "$f" || fail "write_failed:$f" 5; fi
    printf '*\n' >> "$f" || fail "write_failed:$f" 5
  fi
}

write_record() { # slice-id main-hash worktree-hash
  ensure_craft_ignore
  write_file "${RECORD}" "$(printf 'SLICE_ID=%s\nPLAN=%s\nMAIN=%s\nWORKTREE=%s' "$1" "${REL}${PLAN_REL}" "$2" "$3")"
}

# the record must exist and name this slice; prints the conflict and exits 0 otherwise
check_record() { # slice-id
  if [[ ! -f "${RECORD}" ]]; then conflict no_record "$1"; fi
  if [[ "$(rec SLICE_ID)" != "$1" ]]; then conflict record_other_slice "$1"; fi
}
conflict() { # reason slice-id
  echo "RESULT=conflict"
  echo "REASON=$1"
  echo "SLICE_ID=$2"
  [[ "${CMD}" == release ]] && echo "ACTION=none"
  [[ "${CMD}" == back ]] && echo "PLAN=${MAIN_PLAN}" || echo "PLAN=${WT_PLAN}"
  exit 0
}

case "${CMD}" in

in)
  [[ -f "${MAIN_PLAN}" ]] || fail "plan_not_found:${PLAN_REL}" 4
  SLICE_ID="$(plan_field "${MAIN_PLAN}" Slice-ID)"
  [[ -n "${SLICE_ID}" ]] || fail "slice_id_missing:${PLAN_REL}" 4
  if [[ -f "${RECORD}" ]]; then
    [[ "$(rec SLICE_ID)" == "${SLICE_ID}" ]] || conflict record_other_slice "${SLICE_ID}"
    if [[ -f "${WT_PLAN}" && "$(hash_of "${WT_PLAN}")" != "$(rec WORKTREE)" ]]; then conflict worktree_changed "${SLICE_ID}"; fi
  elif [[ -f "${WT_PLAN}" ]] && ! cmp -s "${MAIN_PLAN}" "${WT_PLAN}"; then
    # no record: the copy may only be what the worktree's HEAD holds (a plan the base committed). Anything else is
    # a plan somebody worked on — an older run's worktree — and is never overwritten.
    head_blob="$(git -C "${WT}" rev-parse -q --verify "HEAD:${REL}${PLAN_REL}" 2>/dev/null)" || head_blob=""
    [[ -n "${head_blob}" && "${head_blob}" == "$(hash_of "${WT_PLAN}")" ]] || conflict worktree_changed "${SLICE_ID}"
  fi
  H="$(hash_of "${MAIN_PLAN}")"
  if [[ -f "${WT_PLAN}" ]] && cmp -s "${MAIN_PLAN}" "${WT_PLAN}"; then RESULT=unchanged
  else copy_plan "${MAIN_PLAN}" "${WT_PLAN}"; RESULT=copied
  fi
  write_record "${SLICE_ID}" "${H}" "${H}"
  echo "RESULT=${RESULT}"
  echo "SLICE_ID=${SLICE_ID}"
  echo "PLAN=${WT_PLAN}"
  ;;

back)
  [[ -f "${WT_PLAN}" ]] || fail "worktree_plan_missing:${WT_PLAN}" 4
  SLICE_ID="$(plan_field "${WT_PLAN}" Slice-ID)"
  [[ -n "${SLICE_ID}" ]] || fail "slice_id_missing:${WT_PLAN}" 4
  if [[ "$(plan_field "${WT_PLAN}" Status)" != committing ]]; then
    echo "RESULT=refused"; echo "REASON=not_committing"; echo "SLICE_ID=${SLICE_ID}"; echo "PLAN=${MAIN_PLAN}"
    exit 0
  fi
  H="$(hash_of "${WT_PLAN}")"
  MAIN_HASH="-"; [[ -f "${MAIN_PLAN}" ]] && MAIN_HASH="$(hash_of "${MAIN_PLAN}")"
  if [[ "${MAIN_HASH}" == "${H}" ]]; then RESULT=unchanged   # identical: nothing to overwrite, whatever the record says (a hand-made copy included)
  else
    check_record "${SLICE_ID}"
    [[ "${MAIN_HASH}" == "$(rec MAIN)" ]] || conflict main_changed "${SLICE_ID}"
    copy_plan "${WT_PLAN}" "${MAIN_PLAN}"; RESULT=copied
  fi
  write_record "${SLICE_ID}" "${H}" "${H}"
  echo "RESULT=${RESULT}"
  echo "SLICE_ID=${SLICE_ID}"
  echo "PLAN=${MAIN_PLAN}"
  ;;

release)
  # CRAFT's own files in the worktree — the seed execute step 5 puts at the worktree root, a session hook's state, a
  # handoff marker a re-run renamed — are untracked, and git refuses to remove a worktree that holds one it does not
  # ignore. A project's .gitignore covers them only where its CRAFT block sits (below a subdirectory project's prefix,
  # or nowhere), so each is hidden here by a nested, self-ignoring .gitignore wherever git does not ignore it already.
  # Only once the release goes through: on a conflict the worktree stays in use, and a live handoff must stay visible.
  hide_all() { hide_local_state ""; [[ -z "${REL}" ]] || hide_local_state "${REL}"; hide_craft_dir; }
  if [[ ! -f "${WT_PLAN}" ]]; then   # nothing to release: closed already, or never handed in
    hide_all
    echo "RESULT=released"; echo "ACTION=none"; echo "REASON=no_copy"; echo "PLAN=${WT_PLAN}"; echo "PROJECT=${WT_PROJECT}"; echo "TRACKED=no"
    exit 0
  fi
  SLICE_ID="$(plan_field "${WT_PLAN}" Slice-ID)"
  check_record "${SLICE_ID}"
  [[ "$(hash_of "${WT_PLAN}")" == "$(rec WORKTREE)" ]] || conflict worktree_changed "${SLICE_ID}"
  hide_all
  if git -C "${WT}" ls-files --error-unmatch -- "${REL}${PLAN_REL}" >/dev/null 2>&1; then
    git -C "${WT}" restore --source=HEAD --staged --worktree -- "${REL}${PLAN_REL}" >/dev/null 2>&1 || fail "copy_failed:restore:${WT_PLAN}" 5
    echo "RESULT=released"; echo "ACTION=none"; echo "SLICE_ID=${SLICE_ID}"; echo "PLAN=${WT_PLAN}"; echo "PROJECT=${WT_PROJECT}"; echo "TRACKED=yes"
    exit 0
  fi
  CLOSED="${REL}.claude/plans/.closed"
  if ! git -C "${WT}" check-ignore -q -- "${CLOSED}/x.md" 2>/dev/null; then
    mkdir -p "${WT}/${CLOSED}" 2>/dev/null || fail "write_failed:${WT}/${CLOSED}" 5
    f="${WT}/${CLOSED}/.gitignore"
    if [[ ! -f "$f" ]]; then write_file "$f" '*'
    elif ! grep -qxF '*' "$f"; then printf '*\n' >> "$f" || fail "write_failed:$f" 5
    fi
  fi
  echo "RESULT=released"; echo "ACTION=close"; echo "SLICE_ID=${SLICE_ID}"; echo "PLAN=${WT_PLAN}"; echo "PROJECT=${WT_PROJECT}"; echo "TRACKED=no"
  ;;

esac
exit 0
