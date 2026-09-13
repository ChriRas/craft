#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# handoff-marker-state.sh — is a worktree's handoff marker still live? (B7)
#
# WHY ------------------------------------------------------------------------
# A slice-builder that needs a human writes `<worktree>/.craft/handoff.md` and stops.
# The human then resolves it (a Phase-5 answer, an unblock, a review route …) — and
# nothing removes the marker. The SessionStart hook, /craft:worktree-status,
# /craft:execute and slice-builder kept treating a resolved slice as stopped.
#
# WHAT -----------------------------------------------------------------------
# The slice plan in the worktree is the truth; the marker is a projection of it. Each
# marker status pairs with one plan state, and a marker is LIVE only while the plan is
# still in that state. The pairing is defined once, in PAIRING below (`failure` pairs with
# nothing: live until a retry); skills/workflow/SKILL.md → Handoff marker lifecycle carries
# its readable copy, and scripts/test-handoff-marker-state.sh fails when the two disagree.
#
# Doubt means LIVE: no Slice-ID, no plan (a project may gitignore .claude/plans/), more
# than one plan, no or a malformed plan status, an unknown marker status. A false STALE
# would hide a slice waiting on the human; a false LIVE only keeps the old behaviour.
#
#   <worktree>                    Report the marker's state. Never writes.
#   <worktree> --resolve          Rename a STALE marker to .craft/handoff-resolved-<Written>.md.
#   <worktree> --resolve --retry  Also rename a `failure` marker (a new run is the retry).
#   --print-pairing               Print the pairing table as `<marker-status>=<plan-state>`.
#
# A LIVE marker other than a retried `failure` is never renamed. An existing resolved
# file is never overwritten (a -2, -3 … suffix is added).
#
# Output is line-oriented key=value:
#   STATE=NONE|LIVE|STALE      the marker's state before any rename
#   MARKER_STATUS=<status>     the marker's Status: value (empty when NONE)
#   MARKER_PHASE=<n>           the marker's Phase: value (empty when NONE or absent)
#   PLAN_STATUS=<status>       the plan's Status value, or `unknown`
#   SLICE_ID=<id>              the marker's Slice-ID: value
#   REASON=<why>               paired | unpaired | failure | no_slice_id | plan_not_found |
#                              plan_ambiguous | plan_status_missing | unknown_marker_status
#   RESOLVED=<path>|no         (--resolve only) the renamed file, or `no`
#   ERROR=<reason>             on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success (any STATE) · 2 bad arguments · 4 worktree unreachable ·
# 5 rename failed (marker left in place).
# Bash-3.2-compatible on purpose — the SessionStart hook runs it.

set -uo pipefail

PAIRING="awaiting-test=paused
awaiting-protocol=paused
awaiting-scope-decision=paused
awaiting-refactor-decision=paused
awaiting-block-decision=blocked
awaiting-rethink-decision=reviewing
failure="

paired_state() { # marker-status → plan state; returns 1 for an unknown status
  local line
  while IFS= read -r line; do
    if [[ "${line%%=*}" == "$1" ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done <<EOF
${PAIRING}
EOF
  return 1
}

WORKTREE=""
RESOLVE=0
RETRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-pairing) printf '%s\n' "${PAIRING}"; exit 0 ;;
    --resolve) RESOLVE=1; shift ;;
    --retry) RETRY=1; shift ;;
    --*) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
    *)
      [[ -z "${WORKTREE}" ]] || { echo "ERROR=unexpected_argument:$1" >&2; exit 2; }
      WORKTREE="$1"; shift ;;
  esac
done
[[ -n "${WORKTREE}" ]] || { echo "ERROR=missing_argument:<worktree>" >&2; exit 2; }
(( RETRY == 0 || RESOLVE == 1 )) || { echo "ERROR=retry_requires_resolve" >&2; exit 2; }
[[ -d "${WORKTREE}" ]] || { echo "ERROR=worktree_unreachable:${WORKTREE}" >&2; exit 4; }

MARKER="${WORKTREE}/.craft/handoff.md"

# first `<key>:` line of a file, value trimmed (CR included)
field() { # file key
  local v
  v="$(grep -m1 "^$2:" "$1" 2>/dev/null)" || return 1
  v="${v#*:}"
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "$v"
}

if [[ ! -f "${MARKER}" ]]; then
  echo "STATE=NONE"
  echo "MARKER_STATUS="
  echo "MARKER_PHASE="
  echo "PLAN_STATUS=unknown"
  echo "SLICE_ID="
  echo "REASON=no_marker"
  (( RESOLVE == 1 )) && echo "RESOLVED=no"
  exit 0
fi

MARKER_STATUS="$(field "${MARKER}" Status)"
SLICE_ID="$(field "${MARKER}" Slice-ID)"
WRITTEN="$(field "${MARKER}" Written)"
MARKER_PHASE="$(field "${MARKER}" Phase)"
PLAN_STATUS="unknown"
STATE="LIVE"
REASON=""

if ! PAIRED="$(paired_state "${MARKER_STATUS}")"; then
  REASON="unknown_marker_status"
elif [[ -z "${PAIRED}" ]]; then
  REASON="failure"
elif ! [[ "${SLICE_ID}" =~ ^slice-[0-9]+$ ]]; then
  REASON="no_slice_id"
else
  PLANS=()
  for f in "${WORKTREE}/.claude/plans/${SLICE_ID}-"*.md; do
    [[ -f "$f" ]] && PLANS+=("$f")
  done
  if (( ${#PLANS[@]} == 0 )); then
    REASON="plan_not_found"
  elif (( ${#PLANS[@]} > 1 )); then
    REASON="plan_ambiguous"
  else
    # A plan carries exactly one value; the unfilled template lists them all with `|`.
    v="$(grep -m1 '^> Status:' "${PLANS[0]}" 2>/dev/null)"
    v="$(printf '%s' "${v#*:}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$v" || "$v" == *"|"* || "$v" == *" "* ]]; then
      REASON="plan_status_missing"
    else
      PLAN_STATUS="$v"
      if [[ "${PLAN_STATUS}" == "${PAIRED}" ]]; then
        REASON="paired"
      else
        STATE="STALE"; REASON="unpaired"
      fi
    fi
  fi
fi

echo "STATE=${STATE}"
echo "MARKER_STATUS=${MARKER_STATUS}"
echo "MARKER_PHASE=${MARKER_PHASE}"
echo "PLAN_STATUS=${PLAN_STATUS}"
echo "SLICE_ID=${SLICE_ID}"
echo "REASON=${REASON}"

(( RESOLVE == 1 )) || exit 0

if [[ "${STATE}" == "STALE" ]] || { (( RETRY == 1 )) && [[ "${REASON}" == "failure" ]]; }; then
  stamp="$(printf '%s' "${WRITTEN:-unknown}" | tr -c 'A-Za-z0-9._-' '-')"
  target="${WORKTREE}/.craft/handoff-resolved-${stamp}.md"
  n=2
  while [[ -e "${target}" ]]; do
    target="${WORKTREE}/.craft/handoff-resolved-${stamp}-${n}.md"
    n=$((n + 1))
  done
  mv "${MARKER}" "${target}" || { echo "ERROR=rename_failed:${MARKER}" >&2; exit 5; }
  echo "RESOLVED=${target}"
else
  echo "RESOLVED=no"
fi
exit 0
