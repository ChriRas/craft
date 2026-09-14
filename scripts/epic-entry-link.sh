#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# epic-entry-link.sh — an epic's decomposition entry ↔ its slice-ID (B12, slice-041)
#
# WHY ------------------------------------------------------------------------
# /craft:epic writes decomposition entries without a slice-ID, and /craft:execute A6 matched an
# entry to "a plan that matches it" by judgment. Once the slice landed and its plan was gone, the
# entry matched nothing and every re-run of the epic aborted at A6 until a human wrote the ID into
# the entry — which an unattended epic run (autopilot, F6) cannot do. The ID is allocated by
# /craft:plan, so that is where the entry is linked, and A6 resolves entries through here.
#
# WHAT -----------------------------------------------------------------------
# The entry format is defined here, once. An entry is a line of an epic plan's
# `## Slice Decomposition` section (up to the next `## ` heading), starting at column 0:
#
#   - [ ] <short-name> — <intent>                  unlinked, as /craft:epic writes it
#   - [ ] slice-<NNN> — <short-name> — <intent>    linked by /craft:plan
#
# The checkbox may be `[ ]` or `[x]`. The short-name is the text up to the first ` — ` (em dash);
# an entry is matched by its exact short-name, never as a pattern. A trailing CR or whitespace on a
# line is ignored. A fenced block (``` or ~~~, at any indent; a ``` fence's info string holds no
# backtick) hides its lines — entries and headings alike — until a line holding only a fence of the
# same character, at least as long. Inside the section, a checkbox list item that is not an entry
# (`* [ ]`, an indented `- [x]`, …) and a fence still open at the end of the file are IGNORED —
# reported by `resolve` and `candidates`, never silently dropped. A plain list item (a link) is not.
# Known limit: an unlinked entry whose short-name is itself shaped like a slice-ID reads as linked.
# The project dir is CLAUDE_PROJECT_DIR (else the cwd); plan paths are relative to it.
#
# The state of a linked ID:
#   plan       exactly one plan .claude/plans/<id>-*.md
#   landed     no plan, an archive .claude/project/slices/<id>-*.md
#   missing    neither plan nor archive — the slice was aborted: a DEAD link, which counts as no link
#   ambiguous  several plans for the ID
#   unlinked   (the entry carries no slice-ID)
# A dead link is only safe while slice-IDs are never handed out twice.
#
#   candidates                          The entries /craft:plan may link: every unlinked or dead-linked
#                                       entry of every epic plan under .claude/plans/. DUP=yes marks an entry
#                                       whose short-name another entry of the same epic shares — `link`
#                                       refuses it until one is renamed.
#   link <epic-plan> <short-name> <slice-id>
#                                       Write the slice-ID into that entry. An unlinked entry is linked; a
#                                       dead link is replaced; the same ID again changes nothing. Refused: no
#                                       or several entries of that short-name; a live link (plan, landed,
#                                       ambiguous) to another ID; an ID already on another entry of this or
#                                       any other epic plan; an ID that has no single plan and no archive
#                                       (a typo — also when the entry already carries it); a read-only
#                                       epic plan. Exactly that one line changes — written through the
#                                       existing file, so the mode, a symlink, the line ending and a missing
#                                       final newline stay; the new content is checked before it replaces
#                                       the old, and a failed copy leaves the full new content behind.
#   resolve <epic-plan>                 Every entry with its state, and every IGNORED line — what
#                                       /craft:execute A6 reads.
#
# Output is line-oriented; free text comes last on its line:
#   candidates:  IGNORED EPIC_PLAN=<path> LINE=<n> TEXT=<line>                     one per ignored line
#                CANDIDATE EPIC=<epic-id> EPIC_PLAN=<path> LINK=-|<dead-id> DUP=yes|no ENTRY=<short-name> INTENT=<text>
#                CANDIDATE_COUNT=<n>  IGNORED_COUNT=<n>
#   link:        RESULT=linked|relinked|unchanged  [REPLACED=<dead-id>]  LINE=<the entry line after linking>
#   resolve:     SLICE=<id>|- STATE=<state> PLAN=<path>|- ENTRY=<short-name>      one per entry
#                IGNORED LINE=<n> TEXT=<line>                                      one per ignored line
#                ENTRY_COUNT=<n>  IGNORED_COUNT=<n>
#                RESULT=ok|unresolved   (unresolved: no entry, an ignored line, or an entry unlinked,
#                                        missing or ambiguous)
#   ERROR=<reason>   on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success · 2 bad arguments · 3 project dir unreachable · 4 epic plan unreadable, no / several
# entries of that short-name, or the ID has no single plan and no archive · 5 the entry is linked live to
# another ID, or the ID sits on another entry · 6 the epic plan could not be written.

set -uo pipefail

fail() { echo "ERROR=$1" >&2; exit "$2"; }

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT}" 2>/dev/null || fail "project_dir_unreachable:${PROJECT}" 3

SEP=" — "
ID_RE='^slice-[0-9]{3,}$'
FENCE_OPEN_BT_RE='^[[:space:]]*(`{3,})[^`]*$'
FENCE_OPEN_TL_RE='^[[:space:]]*(~{3,})'
FENCE_CLOSE_RE='^[[:space:]]*(`{3,}|~{3,})$'
ENTRY_RE='^-\ \[[\ xX]\]\ (.+)$'
ITEM_RE='^[[:space:]]*[-*+][[:space:]]+\[[^]]?\]'

# parse <epic-plan> → E_LINE (line number), E_ID (slice-ID or empty), E_NAME, E_INTENT; I_LINE, I_TEXT (ignored)
parse() {
  local f="$1" n=0 in=0 fence="" fence_line=0 fence_in=0 line t rest id
  E_LINE=(); E_ID=(); E_NAME=(); E_INTENT=(); I_LINE=(); I_TEXT=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$((n + 1))
    t="${line%$'\r'}"; t="${t%"${t##*[![:space:]]}"}"   # drop a trailing CR and whitespace
    if [[ -n "${fence}" ]]; then
      if [[ "${t}" =~ ${FENCE_CLOSE_RE} && "${BASH_REMATCH[1]:0:1}" == "${fence:0:1}" && ${#BASH_REMATCH[1]} -ge ${#fence} ]]; then
        fence=""
      fi
      continue
    fi
    if [[ "${t}" =~ ${FENCE_OPEN_BT_RE} || "${t}" =~ ${FENCE_OPEN_TL_RE} ]]; then
      fence="${BASH_REMATCH[1]}"; fence_line=${n}; fence_in=${in}; continue
    fi
    if [[ "${t}" == "## "* ]]; then
      if [[ "${t}" == "## Slice Decomposition" ]]; then in=1; else in=0; fi
      continue
    fi
    [[ ${in} -eq 1 ]] || continue
    if [[ ! "${t}" =~ ${ENTRY_RE} ]]; then
      [[ "${t}" =~ ${ITEM_RE} ]] && { I_LINE+=("${n}"); I_TEXT+=("${t}"); }
      continue
    fi
    rest="${BASH_REMATCH[1]}"; id=""
    if [[ "${rest}" == *"${SEP}"* && "${rest%%"${SEP}"*}" =~ ${ID_RE} ]]; then
      id="${rest%%"${SEP}"*}"; rest="${rest#*"${SEP}"}"
    fi
    E_LINE+=("${n}"); E_ID+=("${id}"); E_NAME+=("${rest%%"${SEP}"*}")
    if [[ "${rest}" == *"${SEP}"* ]]; then E_INTENT+=("${rest#*"${SEP}"}"); else E_INTENT+=(""); fi
  done < "${f}"
  # a fence still open at the end hides the rest of the file: never let that pass silently
  if [[ -n "${fence}" && ( ${fence_in} -eq 1 || ${#E_LINE[@]} -eq 0 ) ]]; then
    I_LINE+=("${fence_line}"); I_TEXT+=("unclosed fence ${fence}")
  fi
}

# state_of <slice-id> → sets STATE (plan | landed | missing | ambiguous) and STATE_PLAN (the plan, or -)
state_of() {
  local p plans=()
  STATE_PLAN="-"
  for p in .claude/plans/"$1"-*.md; do [[ -f "${p}" ]] && plans+=("${p}"); done
  if [[ ${#plans[@]} -eq 1 ]]; then STATE="plan"; STATE_PLAN="${plans[0]}"
  elif [[ ${#plans[@]} -gt 1 ]]; then STATE="ambiguous"
  elif compgen -G ".claude/project/slices/$1-*.md" >/dev/null; then STATE="landed"
  else STATE="missing"; fi
}

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
case "${CMD}" in
  candidates)
    [[ $# -eq 0 ]] || fail "unexpected_argument:$1" 2
    count=0; ignored=0
    for f in .claude/plans/epic-*.md; do
      [[ -f "${f}" ]] || continue
      epic="$(sed -n 's/^> Epic-ID: *//p' "${f}" | head -1 | tr -d '\r')"
      [[ -n "${epic}" ]] || epic="$(basename "${f}" .md | sed -E 's/^(epic-[0-9]+).*/\1/')"
      parse "${f}"
      for i in "${!I_LINE[@]}"; do echo "IGNORED EPIC_PLAN=${f} LINE=${I_LINE[$i]} TEXT=${I_TEXT[$i]}"; ignored=$((ignored + 1)); done
      for i in "${!E_LINE[@]}"; do
        link="-"
        if [[ -n "${E_ID[$i]}" ]]; then
          state_of "${E_ID[$i]}"; [[ "${STATE}" == "missing" ]] || continue
          link="${E_ID[$i]}"
        fi
        dup="no"
        for j in "${!E_LINE[@]}"; do [[ $j -ne $i && "${E_NAME[$j]}" == "${E_NAME[$i]}" ]] && dup="yes"; done
        echo "CANDIDATE EPIC=${epic} EPIC_PLAN=${f} LINK=${link} DUP=${dup} ENTRY=${E_NAME[$i]} INTENT=${E_INTENT[$i]}"
        count=$((count + 1))
      done
    done
    echo "CANDIDATE_COUNT=${count}"
    echo "IGNORED_COUNT=${ignored}"
    ;;

  link)
    [[ $# -eq 3 ]] || fail "usage:link <epic-plan> <short-name> <slice-id>" 2
    EPIC_PLAN="$1"; NAME="$2"; ID="$3"
    [[ "${ID}" =~ ${ID_RE} ]] || fail "invalid_slice_id:${ID}" 2
    [[ -r "${EPIC_PLAN}" ]] || fail "epic_plan_unreadable:${EPIC_PLAN}" 4
    parse "${EPIC_PLAN}"
    hit=()
    for i in "${!E_LINE[@]}"; do
      [[ "${E_NAME[$i]}" == "${NAME}" ]] && hit+=("$i")
      if [[ "${E_ID[$i]}" == "${ID}" && "${E_NAME[$i]}" != "${NAME}" ]]; then fail "slice_already_linked:${E_NAME[$i]}" 5; fi
    done
    [[ ${#hit[@]} -gt 0 ]] || fail "entry_not_found:${NAME}" 4
    [[ ${#hit[@]} -eq 1 ]] || fail "entry_ambiguous:${NAME}" 4
    i="${hit[0]}"; old_id="${E_ID[$i]}"; line_no="${E_LINE[$i]}"
    if [[ -n "${old_id}" && "${old_id}" != "${ID}" ]]; then
      state_of "${old_id}"; [[ "${STATE}" == "missing" ]] || fail "entry_linked_elsewhere:${old_id}" 5
    fi
    # the target must exist — also for `unchanged`, so a dead ID is never confirmed as a link
    state_of "${ID}"
    [[ "${STATE}" == "plan" || "${STATE}" == "landed" ]] || fail "slice_not_found:${ID}:${STATE}" 4
    if [[ "${old_id}" == "${ID}" ]]; then
      echo "RESULT=unchanged"; echo "LINE=$(sed -n "${line_no}p" "${EPIC_PLAN}" | tr -d '\r')"; exit 0
    fi
    for f in .claude/plans/epic-*.md; do
      [[ -f "${f}" && ! "${f}" -ef "${EPIC_PLAN}" ]] || continue
      parse "${f}"
      for j in "${!E_LINE[@]}"; do
        [[ "${E_ID[$j]}" == "${ID}" ]] && fail "slice_linked_in_other_epic:${f}:${E_NAME[$j]}" 5
      done
    done

    [[ -w "${EPIC_PLAN}" ]] || fail "epic_plan_unwritable:${EPIC_PLAN}:read_only" 6
    mapfile -t LINES < "${EPIC_PLAN}"
    old="${LINES[$((line_no - 1))]}"
    if [[ -n "${old_id}" ]]; then
      result="relinked"; new="${old:0:6}${ID}${old:$((6 + ${#old_id}))}"   # `- [ ] ` / `- [x] ` is six characters
    else
      result="linked"; new="${old:0:6}${ID}${SEP}${old:6}"
    fi
    LINES[$((line_no - 1))]="${new}"
    final_nl="yes"; [[ -n "$(tail -c1 "${EPIC_PLAN}")" ]] && final_nl="no"
    old_size="$(wc -c < "${EPIC_PLAN}" | tr -d ' ')"
    new_bytes="$(printf '%s' "${new}" | wc -c | tr -d ' ')"; old_bytes="$(printf '%s' "${old}" | wc -c | tr -d ' ')"
    expected=$(( old_size + new_bytes - old_bytes ))
    tmp="$(mktemp)" || fail "epic_plan_unwritable:${EPIC_PLAN}" 6
    last=$(( ${#LINES[@]} - 1 ))
    if ! (
      for (( k = 0; k < last; k++ )); do printf '%s\n' "${LINES[$k]}" || exit 1; done
      printf '%s' "${LINES[$last]}" || exit 1
      if [[ "${final_nl}" == "yes" ]]; then printf '\n' || exit 1; fi
    ) > "${tmp}" 2>/dev/null || [[ "$(wc -c < "${tmp}" | tr -d ' ')" != "${expected}" ]]; then
      rm -f "${tmp}"; fail "epic_plan_unwritable:${EPIC_PLAN}" 6   # the epic plan is untouched
    fi
    # write through the existing file: mode, owner and a symlink stay as they are
    if ! { cat "${tmp}" > "${EPIC_PLAN}"; } 2>/dev/null || ! cmp -s "${tmp}" "${EPIC_PLAN}"; then
      fail "epic_plan_unwritable:${EPIC_PLAN}:copy_failed:${tmp}" 6   # the full new content stays in tmp
    fi
    rm -f "${tmp}"
    echo "RESULT=${result}"
    [[ "${result}" == "relinked" ]] && echo "REPLACED=${old_id}"
    echo "LINE=${new%$'\r'}"
    ;;

  resolve)
    [[ $# -eq 1 ]] || fail "usage:resolve <epic-plan>" 2
    EPIC_PLAN="$1"
    [[ -r "${EPIC_PLAN}" ]] || fail "epic_plan_unreadable:${EPIC_PLAN}" 4
    parse "${EPIC_PLAN}"
    result="ok"
    [[ ${#E_LINE[@]} -gt 0 && ${#I_LINE[@]} -eq 0 ]] || result="unresolved"
    for i in "${!E_LINE[@]}"; do
      id="${E_ID[$i]}"; state="unlinked"; plan="-"
      if [[ -z "${id}" ]]; then id="-"; else state_of "${id}"; state="${STATE}"; plan="${STATE_PLAN}"; fi
      [[ "${state}" == "plan" || "${state}" == "landed" ]] || result="unresolved"
      echo "SLICE=${id} STATE=${state} PLAN=${plan} ENTRY=${E_NAME[$i]}"
    done
    for i in "${!I_LINE[@]}"; do echo "IGNORED LINE=${I_LINE[$i]} TEXT=${I_TEXT[$i]}"; done
    echo "ENTRY_COUNT=${#E_LINE[@]}"
    echo "IGNORED_COUNT=${#I_LINE[@]}"
    echo "RESULT=${result}"
    ;;

  *) fail "unknown_command:${CMD:-none}" 2 ;;
esac
