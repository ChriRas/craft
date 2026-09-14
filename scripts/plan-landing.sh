#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# plan-landing.sh — a slice plan's way off the trunk when the trunk takes no direct commit (slice-040)
#
# WHY ------------------------------------------------------------------------
# Under `pull-request` + `Protected-main: yes` /craft:commit cannot commit on the trunk, so a
# tracked plan had no clean exit: Step 7's `git rm` left a staged deletion that a later commit
# carried, the remote trunk kept the plan (a fresh clone read the slice as not landed), and a
# plan committed early and edited again made the second pass's trunk checkout abort. The plan's
# deletion therefore rides in the PR, and the second pass drops the local copy before it syncs.
# Neither is a git one-liner — `git rm --cached` + a pathspec commit re-tracks the file from disk,
# and an untracked copy blocks the checkout to a trunk that tracks it — so both live here, and
# /craft:commit names only the calls and their outputs.
#
# WHAT -----------------------------------------------------------------------
# Run from the checkout to act on; plan paths are relative to it. Whether a plan is tracked means
# one thing here: HEAD holds it.
#
#   close --message <msg> [--keep-copy] <plan>...
#       First pass, on the PR branch. Commits the deletion of every given plan HEAD tracks, and
#       nothing else — a pathspec commit, so anything the human staged stays staged. A plan HEAD
#       does not track is skipped (CLOSED=no); when none is tracked, nothing is committed
#       (COMMIT=-). --keep-copy leaves the closed plans on disk, untracked: the live copy the
#       second pass reads (`awaiting-approval`, `> PR:`) in the main checkout. Without it they are
#       gone (a worktree that is removed later must hold no untracked file).
#
#   sync --trunk <branch> [--remote <name>] <plan>...
#       Second pass, after the approved merge, in the main checkout. Fetches <remote>/<trunk> and
#       refuses a local trunk that cannot fast-forward to it. Then drops each local plan copy (an
#       untracked one is removed, a tracked one restored to HEAD) and moves the checkout to the
#       fetched trunk in ONE git step: `checkout -B <trunk> <upstream>` from another branch (the
#       ancestor check makes that a fast-forward), `merge --ff-only` on the trunk itself. That
#       step either completes or leaves HEAD where it was, so a failure puts every plan copy back
#       on the branch it came from — the live plan is never lost to a sync that did not happen.
#       A plan the synced trunk still tracks (the merged PR did not carry its removal) is removed
#       from disk too, leaving an unstaged deletion: locally the slice then reads as landed, and
#       that deletion is what the removal PR needs. --remote defaults to origin.
#
#   An interrupted run (INT, TERM, HUP) puts every held plan copy back before it exits.
#
# Output is line-oriented key=value:
#   close:  PLAN=<path> CLOSED=yes|no KEPT=yes|no (one per plan)  COMMIT=<hash>|-  RESULT=ok
#   sync:   BRANCH_BEFORE=<branch>|detached  PLAN=<path> ON_TRUNK=yes|no (one per plan: does the
#           synced trunk still track it)  RESULT=ok
#   ERROR=<reason>   on failure (stderr, after git's own message), with a non-zero exit code
#
# Exit codes: 0 success · 2 bad arguments · 3 not in a git repository · 5 the commit failed
# (close; every plan copy is back) · 6 fetch, diverged trunk, restore, checkout or fast-forward
# failed (sync; nothing changed, or every plan copy is back on the branch sync started from) ·
# 130 interrupted (every held plan copy is back).

set -uo pipefail

fail() { echo "ERROR=$1" >&2; exit "$2"; }

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
MESSAGE=""; KEEP="no"; TRUNK=""; REMOTE="origin"; PLANS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)   [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--message" 2; MESSAGE="$2"; shift 2 ;;
    --keep-copy) KEEP="yes"; shift ;;
    --trunk)     [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--trunk" 2; TRUNK="$2"; shift 2 ;;
    --remote)    [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--remote" 2; REMOTE="$2"; shift 2 ;;
    --*)         fail "unknown_argument:$1" 2 ;;
    *)           PLANS+=("$1"); shift ;;
  esac
done
case "${CMD}" in
  close) [[ -n "${MESSAGE}" ]] || fail "missing_value:--message" 2 ;;
  sync)  [[ -n "${TRUNK}" ]] || fail "missing_value:--trunk" 2 ;;
  *)     fail "unknown_command:${CMD:-none}" 2 ;;
esac
[[ ${#PLANS[@]} -gt 0 ]] || fail "missing_argument:<plan>" 2
git rev-parse --show-toplevel >/dev/null 2>&1 || fail "not_a_git_repository:$(pwd)" 3
PREFIX="$(git rev-parse --show-prefix)"
in_head() { git cat-file -e "HEAD:${PREFIX}$1" 2>/dev/null; }

HOLD="$(mktemp -d)" || fail "hold_dir_unavailable" 6
GITERR="${HOLD}/git.err"
HELD=()          # the plans whose copies are held, by index into HOLD
ROLLBACK="no"    # yes while a held copy may be missing from disk
trap 'rm -rf "${HOLD}"' EXIT
trap 'interrupted' INT TERM HUP
hold() { # plan...
  local i=0 p; HELD=("$@")
  for p in "$@"; do
    if [[ -e "$p" ]]; then cp -p "$p" "${HOLD}/$i" || return 1; else : > "${HOLD}/$i.none"; fi
    i=$((i + 1))
  done
}
put_back() {
  local i=0 p
  for p in ${HELD[@]+"${HELD[@]}"}; do
    if [[ ! -e "${HOLD}/$i.none" ]]; then mkdir -p "$(dirname "$p")" && cp -p "${HOLD}/$i" "$p"; fi
    i=$((i + 1))
  done
}
interrupted() { [[ "${ROLLBACK}" == "yes" ]] && put_back; echo "ERROR=interrupted" >&2; exit 130; }
git_fail() { [[ -s "${GITERR}" ]] && cat "${GITERR}" >&2; }   # surface git's own reason

if [[ "${CMD}" == "close" ]]; then
  CLOSE=()
  for p in "${PLANS[@]}"; do in_head "$p" && CLOSE+=("$p"); done
  if [[ ${#CLOSE[@]} -eq 0 ]]; then
    for p in "${PLANS[@]}"; do echo "PLAN=$p CLOSED=no KEPT=no"; done
    echo "COMMIT=-"; echo "RESULT=ok"; exit 0
  fi
  hold "${CLOSE[@]}" || fail "hold_failed" 5
  ROLLBACK="yes"
  rm -f -- "${CLOSE[@]}"
  if ! git commit -q -m "${MESSAGE}" -- "${CLOSE[@]}" >/dev/null 2>"${GITERR}"; then
    git_fail; put_back; fail "commit_failed" 5
  fi
  [[ "${KEEP}" == "yes" ]] && put_back
  ROLLBACK="no"
  for p in "${PLANS[@]}"; do
    if in_head "$p"; then echo "PLAN=$p CLOSED=no KEPT=no"
    elif [[ " ${CLOSE[*]} " == *" $p "* ]]; then echo "PLAN=$p CLOSED=yes KEPT=${KEEP}"
    else echo "PLAN=$p CLOSED=no KEPT=no"; fi
  done
  echo "COMMIT=$(git rev-parse HEAD)"
  echo "RESULT=ok"
  exit 0
fi

# sync
BEFORE="$(git branch --show-current)"
echo "BRANCH_BEFORE=${BEFORE:-detached}"
git fetch -q "${REMOTE}" "${TRUNK}" >/dev/null 2>"${GITERR}" || { git_fail; fail "fetch_failed:${REMOTE}/${TRUNK}" 6; }
UPSTREAM="refs/remotes/${REMOTE}/${TRUNK}"
git rev-parse -q --verify "${UPSTREAM}" >/dev/null || UPSTREAM="$(git rev-parse FETCH_HEAD)"
if git rev-parse -q --verify "refs/heads/${TRUNK}" >/dev/null; then
  git merge-base --is-ancestor "refs/heads/${TRUNK}" "${UPSTREAM}" || fail "trunk_diverged:${TRUNK}" 6
fi

hold "${PLANS[@]}" || fail "hold_failed" 6
ROLLBACK="yes"
for p in "${PLANS[@]}"; do
  [[ -e "$p" ]] || continue
  if in_head "$p"; then
    git checkout -q HEAD -- "$p" 2>"${GITERR}" || { git_fail; put_back; fail "restore_failed:$p" 6; }
  else
    rm -f -- "$p"
  fi
done
if [[ "${BEFORE}" == "${TRUNK}" ]]; then
  git merge -q --ff-only "${UPSTREAM}" >/dev/null 2>"${GITERR}" || { git_fail; put_back; fail "ff_failed:${TRUNK}" 6; }
else
  git checkout -q -B "${TRUNK}" "${UPSTREAM}" >/dev/null 2>"${GITERR}" || { git_fail; put_back; fail "checkout_failed:${TRUNK}" 6; }
fi
ROLLBACK="no"
for p in "${PLANS[@]}"; do
  if in_head "$p"; then
    rm -f -- "$p"
    echo "PLAN=$p ON_TRUNK=yes"
  else
    echo "PLAN=$p ON_TRUNK=no"
  fi
done
echo "RESULT=ok"
