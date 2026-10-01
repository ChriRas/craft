#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# plan-gate-state.sh — which slice plans of an epic still await the autopilot's plan gate (slice-054)
#
# WHY ------------------------------------------------------------------------
# An autopilot run plans an epic's unplanned entries itself (slice-planner, /craft:execute → Autopilot
# run → ap) and then stops ONCE for the human: the plan gate. The gate must come back after an [N], an
# Esc or a crashed session, and must not come back once the human said yes — so "is it still owed?"
# has to be answerable from disk. A stored flag is one more thing a writer can forget to clear
# (intent: derived state over cleanup). The answer is derived from two things that exist anyway:
# the marker a pipeline-written plan carries, and the approval line the run logs.
#
# WHAT -----------------------------------------------------------------------
#   plan-gate-state.sh <epic-plan>
#
# Run from the project root (CLAUDE_PROJECT_DIR, else the cwd); the epic plan path is relative to it.
# The epic's plans are the entries `epic-entry-link.sh resolve` reports STATE=plan — the one parser of
# the entry format. Landed, unlinked, missing and ambiguous entries have no plan here and are not
# reported (A6 judges those).
#
# Per plan:
#   pipeline   its frontmatter (the `> ` lines above the first `## ` heading) carries `> Planned-by:`,
#              whatever the value — a value other than `autopilot` is doubt, and doubt means the gate.
#   approved   a pipeline plan whose slice-ID an approval line in the epic plan's `## Autopilot Log`
#              names, for this epic:
#                - <datetime> · ✓ · <epic-id> · plan gate approved: slice-<a>, slice-<b>, …
#              at column 0, nothing after the ID list. Any other shape approves nothing.
#   GATE       hand (no marker) · approved · awaiting (a pipeline plan no approval line names)
#   NEEDS_HUMAN  lines whose text begins with `NEEDS-HUMAN:` — after indent, `>`, a list bullet (`-`, `*`,
#              `+`, `1.`), a checkbox and bold (`**NEEDS-HUMAN:**`, `**NEEDS-HUMAN**:`) — the question a planner
#              could not answer (commands/plan.md → Subagent Mode). Mid-sentence mentions do not count.
#
# Orphans — the plans no entry links (slice-054 review R1-1):
#   ORPHAN     an active plan `.claude/plans/slice-<NNN>-*.md` whose slice-ID no entry of ANY epic plan under
#              .claude/plans/ carries. A hand re-plan of an entry that was never linked, a plan whose link
#              failed, or one a planner wrote when Esc came before the link. The master does not decide
#              whether it refines an entry — /craft:execute → ap asks the human before planning.
#              PIPELINE=yes when it carries `> Planned-by:` in its frontmatter.
# Fenced blocks and multi-line HTML comments are examples, not content: both files are read through
# example-regions.sh. A trailing CR is ignored.
#
# The plan review — the plan-architect's rounds (slice-055), in the epic plan's `## Plan Review`:
#   ### Round <n> — <ISO datetime> (<first | auto | review-only>)
#   - P<n>-<k> · <slice-id>[, <slice-id>…] · <overlap|contract|order|sizing> · <revise|note> · <text> · <resolution>
#   - note · <free text>                                      (never a finding)
#   <n> is the heading's position; a finding's <n> is its round's. The resolution is the last ` · `
#   field: `open`, `resolved in round <m>` (the architect's `holds`), or `accepted at gate` (the human's
#   [Y] with the finding open) — only `open` is open. Anything else — a field missing, an unknown kind,
#   route or round kind, a heading off its position, a line naming P<n> in any other shape (bold, a
#   backtick, another bullet, a number, a checkbox, a quote, no bullet) — is ARCH_MALFORMED: an
#   unreadable finding counts open, and any malformed
#   line sets ARCH_AUTO_LEFT=0 (doubt means the gate, never another autonomous round). A `#### ` or
#   deeper heading is no round heading.
#   `first` opens a planning pass; each `auto` round after the last `first` spends one of its two
#   autonomous revision rounds; `review-only` spends nothing. Open findings never withhold [Y].
#
# Output (free text last on its line):
#   PLAN SLICE=<id> GATE=hand|approved|awaiting NEEDS_HUMAN=<n> PATH=<path>     one per plan
#   ORPHAN SLICE=<id> PIPELINE=yes|no PATH=<path>                                 one per orphan
#   ARCH FINDING=<id> OPEN=yes|no ROUTE=<route> KIND=<kind> SLICES=<id,id>         one per plan-review finding
#   ARCH_MALFORMED LINE=<n> TEXT=<line>                                           one per unreadable line
#   ARCH_ROUNDS=<n>  ARCH_NEXT_ROUND=<n+1>  ARCH_LAST_KIND=<kind|->  ARCH_AUTO_LEFT=<0..2>  ARCH_OPEN_COUNT=<n>
#   PLAN_COUNT=<n>  AWAITING_COUNT=<n>  NEEDS_HUMAN_COUNT=<n, over awaiting plans only>  ORPHAN_COUNT=<n>
#   RESULT=gate|clear   (gate: at least one plan awaits)
#   ERROR=<reason>      on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success · 2 bad arguments · 3 project dir unreachable · 4 epic plan unreadable, no
# Epic-ID, or the entry helper failed (on this or any other epic plan).
#
# Runtime: bash >= 5 is fine (scripts/, no hook reaches this); no python3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$SCRIPT_DIR/epic-entry-link.sh"
REGIONS="$SCRIPT_DIR/example-regions.sh"

die() { echo "ERROR=$2" >&2; exit "$1"; }

[[ $# -eq 1 && -n "$1" ]] || die 2 "usage: plan-gate-state.sh <epic-plan>"
EPIC_PLAN="$1"
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || die 3 "project_dir_unreachable:${CLAUDE_PROJECT_DIR:-.}"
[[ -f "$EPIC_PLAN" && -r "$EPIC_PLAN" ]] || die 4 "epic_plan_unreadable:$EPIC_PLAN"
[[ -f "$LINK" && -f "$REGIONS" ]] || die 4 "helper_missing:epic-entry-link.sh or example-regions.sh"

# blank <file> -> the file with example lines emptied and CRs dropped, line count kept
blank() {
  local out
  out="$(bash "$REGIONS" blank markdown "$1")" || return 1
  printf '%s\n' "$out" | tr -d '\r'
}

EPIC_TEXT="$(blank "$EPIC_PLAN")" || die 4 "epic_plan_unreadable:$EPIC_PLAN"

EPIC_ID=""
while IFS= read -r line; do
  [[ "$line" =~ ^\>\ Epic-ID:\ (epic-[0-9]+)[[:space:]]*$ ]] && { EPIC_ID="${BASH_REMATCH[1]}"; break; }
done <<< "$EPIC_TEXT"
[[ -n "$EPIC_ID" ]] || die 4 "no_epic_id:$EPIC_PLAN"

# The approved IDs: approval lines inside ## Autopilot Log only.
declare -A APPROVED=()
APPROVE_RE="^- [^ ]+ · ✓ · ${EPIC_ID} · plan gate approved: (slice-[0-9]+(, slice-[0-9]+)*)[[:space:]]*\$"
in_log=0
while IFS= read -r line; do
  if [[ "$line" =~ ^##\  ]]; then
    [[ "$line" =~ ^##\ Autopilot\ Log[[:space:]]*$ ]] && in_log=1 || in_log=0
    continue
  fi
  (( in_log )) || continue
  if [[ "$line" =~ $APPROVE_RE ]]; then
    IFS=',' read -ra ids <<< "${BASH_REMATCH[1]}"
    for id in "${ids[@]}"; do APPROVED["${id// /}"]=1; done
  fi
done <<< "$EPIC_TEXT"

RESOLVED="$(bash "$LINK" resolve "$EPIC_PLAN" 2>&1)" || die 4 "entry_helper_failed:$(printf '%s' "$RESOLVED" | tail -1)"

# indent / quote, then an optional bullet or number, checkbox and bold opener, then the marker and its colon
NEEDS_RE='^[[:space:]>]*(([-*+]|[0-9]+[.)])[[:space:]]+)?(\[[ xX]\][[:space:]]+)?(\*\*|__)?NEEDS-HUMAN(\*\*|__)?:'

plan_count=0 awaiting=0 nh_total=0
while IFS= read -r rline; do
  [[ "$rline" =~ ^SLICE=(slice-[0-9]+)\ STATE=plan\ PLAN=([^ ]+)\  ]] || continue
  sid="${BASH_REMATCH[1]}" path="${BASH_REMATCH[2]}"
  text="$(blank "$path")" || { echo "ERROR=plan_unreadable:$path" >&2; exit 4; }

  pipeline=0 nh=0 in_front=1
  while IFS= read -r line; do
    [[ "$line" =~ ^##\  ]] && in_front=0
    (( in_front )) && [[ "$line" =~ ^\>\ Planned-by: ]] && pipeline=1
    [[ "$line" =~ $NEEDS_RE ]] && nh=$((nh + 1))
  done <<< "$text"

  if (( ! pipeline )); then gate=hand
  elif [[ -n "${APPROVED[$sid]:-}" ]]; then gate=approved
  else gate=awaiting; awaiting=$((awaiting + 1)); nh_total=$((nh_total + nh))
  fi
  plan_count=$((plan_count + 1))
  echo "PLAN SLICE=$sid GATE=$gate NEEDS_HUMAN=$nh PATH=$path"
done <<< "$RESOLVED"

# Orphans: every slice-ID any epic plan's entries carry, then the active plans outside that set.
declare -A LINKED=()
for ep in .claude/plans/epic-*.md; do
  [[ -f "$ep" ]] || continue
  out="$(bash "$LINK" resolve "$ep" 2>&1)" || die 4 "entry_helper_failed:$ep:$(printf '%s' "$out" | tail -1)"
  while IFS= read -r rline; do
    [[ "$rline" =~ ^SLICE=(slice-[0-9]+)\  ]] && LINKED["${BASH_REMATCH[1]}"]=1
  done <<< "$out"
done
orphans=0
for pf in .claude/plans/slice-*.md; do
  [[ -f "$pf" ]] || continue
  [[ "$(basename "$pf")" =~ ^(slice-[0-9]+)- ]] || continue
  sid="${BASH_REMATCH[1]}"
  [[ -n "${LINKED[$sid]:-}" ]] && continue
  pipe=no
  text="$(blank "$pf")" || { echo "ERROR=plan_unreadable:$pf" >&2; exit 4; }
  while IFS= read -r line; do
    [[ "$line" =~ ^##\  ]] && break
    [[ "$line" =~ ^\>\ Planned-by: ]] && { pipe=yes; break; }
  done <<< "$text"
  orphans=$((orphans + 1))
  echo "ORPHAN SLICE=$sid PIPELINE=$pipe PATH=$pf"
done

# The plan review.
arch_rounds=0 arch_open=0 arch_malformed=0 arch_last=- arch_auto=0 in_rev=0 lineno=0
HEAD_RE='^### Round ([0-9]+) — [^ ]+ \((first|auto|review-only)\)[[:space:]]*$'
FIND_RE='^- (P([0-9]+)-[0-9]+) · (slice-[0-9]+(, slice-[0-9]+)*) · (overlap|contract|order|sizing) · (revise|note) · (.+) · (open|resolved in round [0-9]+|accepted at gate)[[:space:]]*$'
# any line whose text starts with P<digit> — after indent, `>`, a bullet or number, a checkbox, bold or a
# backtick — is a finding attempt: the well-formed shape, or malformed
ATTEMPT_RE='^[[:space:]>]*(([-*+]|[0-9]+[.)])[[:space:]]+)?(\[[ xX]\][[:space:]]+)?(\*\*|__|`)?P[0-9]'
while IFS= read -r line; do
  lineno=$((lineno + 1))
  if [[ "$line" =~ ^##\  ]]; then
    [[ "$line" =~ ^##\ Plan\ Review[[:space:]]*$ ]] && in_rev=1 || in_rev=0
    continue
  fi
  (( in_rev )) || continue
  if [[ "$line" =~ ^###[[:space:]] ]]; then
    arch_rounds=$((arch_rounds + 1))
    if [[ "$line" =~ $HEAD_RE ]] && (( BASH_REMATCH[1] == arch_rounds )); then
      arch_last="${BASH_REMATCH[2]}"
      case "$arch_last" in first) arch_auto=0 ;; auto) arch_auto=$((arch_auto + 1)) ;; esac
    else
      arch_malformed=$((arch_malformed + 1)); echo "ARCH_MALFORMED LINE=$lineno TEXT=$line"
    fi
    continue
  fi
  [[ "$line" =~ $ATTEMPT_RE ]] || continue
  if [[ "$line" =~ $FIND_RE ]] && (( BASH_REMATCH[2] == arch_rounds )); then
    id="${BASH_REMATCH[1]}" slices="${BASH_REMATCH[3]// /}" kind="${BASH_REMATCH[5]}" route="${BASH_REMATCH[6]}"
    res="${BASH_REMATCH[8]}" open=no
    [[ "$res" == open ]] && { open=yes; arch_open=$((arch_open + 1)); }
    echo "ARCH FINDING=$id OPEN=$open ROUTE=$route KIND=$kind SLICES=$slices"
  else
    arch_malformed=$((arch_malformed + 1)) arch_open=$((arch_open + 1))
    echo "ARCH_MALFORMED LINE=$lineno TEXT=$line"
  fi
done <<< "$EPIC_TEXT"
arch_left=$((2 - arch_auto)); (( arch_left < 0 )) && arch_left=0
(( arch_malformed > 0 )) && arch_left=0

echo "PLAN_COUNT=$plan_count"
echo "AWAITING_COUNT=$awaiting"
echo "NEEDS_HUMAN_COUNT=$nh_total"
echo "ORPHAN_COUNT=$orphans"
echo "ARCH_ROUNDS=$arch_rounds"
echo "ARCH_NEXT_ROUND=$((arch_rounds + 1))"
echo "ARCH_LAST_KIND=$arch_last"
echo "ARCH_AUTO_LEFT=$arch_left"
echo "ARCH_OPEN_COUNT=$arch_open"
(( awaiting > 0 )) && echo "RESULT=gate" || echo "RESULT=clear"
