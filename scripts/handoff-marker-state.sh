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
# A status can be re-entered for an unrelated reason — a pause after a resume, a block after an
# unblock, a new review round — so the status alone would revive an old marker (B11). A marker
# therefore also carries its episode, `Episode:`, the value the plan held when the marker was
# written, and counts only while the plan is still in that episode. What the episode is per plan
# state is defined once, in EPISODES below: the plan header's `Paused-since:` / `Blocked-since:`
# stamp, which every entry into that status from another status stamps anew, or the review round
# count, read by scripts/review-findings-state.sh. A review episode also ends once no finding line
# is open — a guard for a round routed by hand with no new round; a real review appends its round
# before it routes.
#
# Doubt means LIVE: no Slice-ID, no plan (a project may gitignore .claude/plans/), more
# than one plan, no or a malformed plan status, an unknown marker status, an episode the plan
# cannot confirm (no stamp, the findings parser failed, a value that is not a UTC stamp or a round
# number, a marker episode later than the plan's). A marker without `Episode:` in its frontmatter
# (written before B11) is judged by its status alone. A false STALE would hide a slice waiting on the
# human; a false LIVE only keeps the old behaviour.
#
#   <worktree>                    Report the marker's state. Never writes.
#   <worktree> --resolve          Rename a STALE marker to .craft/handoff-resolved-<Written>.md.
#   <worktree> --resolve --retry  Also rename a `failure` marker (a new run is the retry).
#   --print-pairing               Print the pairing table as `<marker-status>=<plan-state>`.
#   --print-episodes              Print the episode table as `<plan-state>=<source>`.
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
#   REASON=<why>               paired | unpaired | episode_mismatch | findings_closed | failure |
#                              episode_unknown | no_slice_id | plan_not_found | plan_ambiguous |
#                              plan_status_missing | unknown_marker_status
#   RESOLVED=<path>|no         (--resolve only) the renamed file, or `no`
#   ERROR=<reason>             on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success (any STATE) · 2 bad arguments · 4 worktree unreachable ·
# 5 rename failed (marker left in place).
# Bash-3.2-compatible on purpose — the SessionStart hook runs it, and it runs
# review-findings-state.sh with the same bash, so that parser is bash-3.2-bound too.

set -uo pipefail

PAIRING="awaiting-test=paused
awaiting-protocol=paused
awaiting-scope-decision=paused
awaiting-refactor-decision=paused
awaiting-block-decision=blocked
awaiting-rethink-decision=reviewing
failure="

# plan state → its episode: `> <Key>:` in the plan header, or `round` (the review round count)
EPISODES="paused=Paused-since
blocked=Blocked-since
reviewing=round"

lookup() { # table key → value; returns 1 for an unknown key
  local line
  while IFS= read -r line; do
    if [[ "${line%%=*}" == "$2" ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done <<EOF
$1
EOF
  return 1
}
paired_state() { lookup "${PAIRING}" "$1"; } # marker-status → plan state

WORKTREE=""
RESOLVE=0
RETRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-pairing) printf '%s\n' "${PAIRING}"; exit 0 ;;
    --print-episodes) printf '%s\n' "${EPISODES}"; exit 0 ;;
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

# `<key>:` inside the marker's leading `---` frontmatter only, value trimmed — an optional field
# must not be picked up from the body. A frontmatter that never closes has no fields: without the
# closing `---` nothing tells frontmatter from body. One awk pass, no pipe (a reader that stops early
# would make the answer depend on the file's size under pipefail).
frontmatter_field() { # file key
  local v
  v="$(awk -v key="$2:" '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { if (found != "") print found; closed = 1; exit }
    found == "" && index($0, key) == 1 { found = $0 }
  ' "$1" 2>/dev/null)"
  [[ -n "$v" ]] || return 1
  v="${v#*:}"
  printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

STAMP_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'
ROUND_RE='^[0-9]+$'

# Is the plan still in the marker's episode? → match | mismatch | closed | unknown
# Only a well-formed pair can be told apart: a value in another shape (quotes, a local time, `R1`)
# is `unknown`, never a mismatch. So is a marker episode later than the plan's — no writer produces
# one (a re-entry always leaves the later value on the plan side), so it is a miscopy, not an answer.
episode_verdict() { # plan plan-state marker-episode
  local source v out rounds open
  source="$(lookup "${EPISODES}" "$2")" || { printf 'unknown'; return; }
  if [[ "${source}" == "round" ]]; then
    # a round count starts at 1: `0` is no round a writer copies
    { [[ "$3" =~ ${ROUND_RE} ]] && (( 10#$3 > 0 )); } || { printf 'unknown'; return; }
    out="$("${BASH}" "$(dirname "${BASH_SOURCE[0]}")/review-findings-state.sh" "$1" 2>/dev/null)" \
      || { printf 'unknown'; return; }
    rounds="$(printf '%s\n' "$out" | sed -n 's/^ROUNDS=//p')"
    open="$(printf '%s\n' "$out" | sed -n 's/^OPEN_COUNT=//p')"
    [[ "${rounds}" =~ ${ROUND_RE} && "${open}" =~ ${ROUND_RE} ]] || { printf 'unknown'; return; }
    if (( 10#$3 > 10#${rounds} )); then printf 'unknown'
    elif (( 10#$3 != 10#${rounds} )); then printf 'mismatch'
    elif (( open == 0 )); then printf 'closed'
    else printf 'match'
    fi
    return
  fi
  [[ "$3" =~ ${STAMP_RE} ]] || { printf 'unknown'; return; }
  # `> <Key>:` in the plan header — above the first `## ` heading, so body prose never counts
  v="$(sed -n '/^## /q; p' "$1" | grep -m1 "^> ${source}:")" || { printf 'unknown'; return; }
  v="$(printf '%s' "${v#*:}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if ! [[ "$v" =~ ${STAMP_RE} ]]; then printf 'unknown'
  elif [[ "$v" == "$3" ]]; then printf 'match'
  elif [[ "$3" > "$v" ]]; then printf 'unknown'
  else printf 'mismatch'
  fi
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
MARKER_EPISODE="$(frontmatter_field "${MARKER}" Episode)"
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
      if [[ "${PLAN_STATUS}" == "${PAIRED}" && -z "${MARKER_EPISODE}" ]]; then
        REASON="paired"
      elif [[ "${PLAN_STATUS}" == "${PAIRED}" ]]; then
        case "$(episode_verdict "${PLANS[0]}" "${PAIRED}" "${MARKER_EPISODE}")" in
          match)    REASON="paired" ;;
          mismatch) STATE="STALE"; REASON="episode_mismatch" ;;
          closed)   STATE="STALE"; REASON="findings_closed" ;;
          *)        REASON="episode_unknown" ;;
        esac
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
