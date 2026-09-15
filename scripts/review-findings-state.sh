#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# review-findings-state.sh — read a slice plan's `## Review Findings` record (B6)
#
# WHY ------------------------------------------------------------------------
# `/craft:review` gates Commit on the findings record: which lines are still open, which
# round comes next, which lines are follow-ups for the archive. Five consumers read that
# record (review Step 6, Step 7, the Subagent-Mode gate, `/craft:commit` Step 5, and
# handoff-marker-state.sh for a review episode), and a
# grep cannot tell a resolution from a description that merely quotes one (slice-034). So
# the record is parsed here, once.
#
# WHAT -----------------------------------------------------------------------
# The record is a sequence of rounds. A round is a heading
#   ### Round <R> — <ISO date> (<Phase-8 | advisory>)
# followed by finding lines; the mode is `advisory` only when the heading ends in `(advisory)` —
# anything else is Phase-8. Lines above the first heading form a legacy Phase-8 round. The section is
# `## Review Findings` (any non-word suffix, any case) up to the next `## ` heading; fenced code
# is skipped, and a fence left open at the end is itself MALFORMED.
# A finding line is
#   - R<r>-<n> · <Heavy|Light> · <Local|Rethink> · <description> · <resolution>
# or, in a legacy record, the same without the ID (numbered by position in its round).
# The resolution is the LAST ` · ` field; a ` · ` inside the description is harmless.
# A resolution may carry a note after `: ` or ` (`. Indented lines continue the finding
# above; `- note · …` lines and prose paragraphs are not findings.
#
# The resolutions and whether each keeps a line open are defined once, in RESOLUTIONS
# below; `commands/review.md` Step 6 shows them, and scripts/test-review-findings-state.sh
# fails when the two disagree. Lines in an advisory round are never open. Doubt blocks:
# reported MALFORMED and counted open (in a Phase-8 round) are a finding line with a bad
# severity or fix-nature, fewer than four fields or an unknown resolution; an ID that repeats
# or belongs to another round; a line that carries the `Heavy|Light · Local|Rethink ·` pattern
# but is not a `- ` bullet at column 0 (`*`, `1.`, indented); and a round heading whose
# number is not its position.
#
#   <plan>               Report rounds and every finding.
#   <plan> --followups   Report only the `follow-up → slice archive` lines (for the archive).
#   --print-resolutions  Print the resolution table as `<open>|<legacy>|<resolution>`.
#
# Output is line-oriented key=value; free text comes last on its line:
#   ROUNDS=<n>                   rounds in the record (legacy round included)
#   LEGACY=yes|no                finding lines above the first round heading
#   NEXT_ROUND=<n>               the number the next review round writes
#   FINDING=<id> ROUND=<r> MODE=phase8|advisory OPEN=yes|no RESOLUTION=<canonical>
#   MALFORMED=<id> LINE=<n> MODE=<m>  an unreadable finding line or round heading (open in phase8)
#   OPEN_COUNT=<n>               open lines across all Phase-8 rounds
#   FOLLOWUP=<id> <sev> · <fix> · <description>[ — <note>]   (--followups only)
#   FOLLOWUP_MALFORMED=<id> LINE=<n>   (--followups) a line naming a follow-up that could not be read
#   ERROR=<reason>               on failure (stderr), with a non-zero exit code
#
# Exit codes: 0 success · 2 bad arguments · 4 plan unreadable.
# Bash-3.2-compatible on purpose — handoff-marker-state.sh, which a SessionStart hook runs, calls it
# for a review episode (B11); scripts/test-toolchain-check.sh parses and scans it as 3.2-bound.

set -uo pipefail

# <open yes|no>|<legacy yes|no>|<canonical resolution>; placeholders <slice-ID> and <R>
RESOLUTIONS="no|no|fixed in-phase
no|no|follow-up → slice archive
no|no|escalated → Phase 4 loop-back
no|no|escalated → Phase 4 loop-back (fix cap)
yes|no|escalated → new slice (pending)
no|no|escalated → new slice <slice-ID>
yes|no|escalated → route pending
yes|no|open — fix cap, awaiting decision
no|no|resolved in round <R>
no|no|advisory — no route
yes|yes|escalated → new slice"

MODE="report"
PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-resolutions) printf '%s\n' "${RESOLUTIONS}"; exit 0 ;;
    --followups) MODE="followups"; shift ;;
    --*) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
    *)
      [[ -z "${PLAN}" ]] || { echo "ERROR=unexpected_argument:$1" >&2; exit 2; }
      PLAN="$1"; shift ;;
  esac
done
[[ -n "${PLAN}" ]] || { echo "ERROR=missing_argument:<plan>" >&2; exit 2; }
[[ -f "${PLAN}" && -r "${PLAN}" ]] || { echo "ERROR=plan_unreadable:${PLAN}" >&2; exit 4; }

CRAFT_RESOLUTIONS="${RESOLUTIONS}" CRAFT_MODE="${MODE}" awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# Length of the canonical resolution c matched at the start of v, or 0.
function match_len(v, c,    pre, post, ph, i, rest, n) {
  ph = ""
  if (index(c, "<slice-ID>")) ph = "<slice-ID>"
  else if (index(c, "<R>")) ph = "<R>"
  if (ph == "") {
    if (substr(v, 1, length(c)) != c) return 0
    return length(c)
  }
  i = index(c, ph); pre = substr(c, 1, i - 1); post = substr(c, i + length(ph))
  if (substr(v, 1, length(pre)) != pre) return 0
  rest = substr(v, length(pre) + 1); n = 0
  if (ph == "<slice-ID>") {
    if (substr(rest, 1, 6) != "slice-") return 0
    rest = substr(rest, 7); n = 6
  }
  if (!match(rest, /^[0-9]+/)) return 0
  n += RLENGTH; rest = substr(rest, RLENGTH + 1)
  if (substr(rest, 1, length(post)) != post) return 0
  return length(pre) + n + length(post)
}

# Resolve v against the table (longest canonical prefix wins): sets R_CANON / R_OPEN / R_NOTE.
function resolve(v,    k, best, l, tail) {
  best = 0; R_CANON = ""; R_OPEN = ""; R_NOTE = ""
  for (k = 1; k <= NRES; k++) {
    l = match_len(v, RES_C[k])
    if (l > best) {
      tail = substr(v, l + 1)
      if (tail == "" || substr(tail, 1, 1) == ":" || substr(tail, 1, 2) == " (") {
        best = l; R_CANON = RES_C[k]; R_OPEN = RES_O[k]; R_NOTE = tail
      }
    }
  }
  if (substr(R_NOTE, 1, 1) == ":") R_NOTE = substr(R_NOTE, 2)
  R_NOTE = trim(R_NOTE)
  return best > 0
}

function malformed(id, lineno) {
  MAL[++NMAL] = "MALFORMED=" id " LINE=" lineno " MODE=" MODEOF[ROUND]
  if (MODEOF[ROUND] != "advisory") OPENC++
}

function flush(    n, f, i, id, sev, fix, desc, res, ok, open, rid) {
  if (PENDING == "") return
  line = PENDING; lineno = PENDING_NO; PENDING = ""
  n = split(line, f, / · /)
  POS[ROUND]++
  id = ""; i = 1
  if (f[1] ~ /^R[0-9]+-[0-9]+$/) { id = f[1]; i = 2 }
  if (id == "") id = "R" ROUND "-" POS[ROUND]
  ok = (n - i + 1 >= 4)
  sev = trim(f[i]); fix = trim(f[i + 1]); res = trim(f[n])
  desc = ""
  for (k2 = i + 2; k2 < n; k2++) desc = desc (desc == "" ? "" : " · ") trim(f[k2])
  if (sev != "Heavy" && sev != "Light") ok = 0
  if (fix != "Local" && fix != "Rethink") ok = 0
  if (i == 2) { rid = substr(id, 2); sub(/-.*/, "", rid); if (rid + 0 != ROUND) ok = 0 }
  if (id in SEEN) ok = 0
  SEEN[id] = 1
  if (ok && !resolve(res)) ok = 0
  if (!ok) {
    malformed(id, lineno)
    OUT[++NOUT] = "FINDING=" id " ROUND=" ROUND " MODE=" MODEOF[ROUND] " OPEN=" (MODEOF[ROUND] == "advisory" ? "no" : "yes") " RESOLUTION=unknown"
    if (tolower(line) ~ /follow-up/) FU[++NFU] = "FOLLOWUP_MALFORMED=" id " LINE=" lineno
    return
  }
  open = (MODEOF[ROUND] == "advisory") ? "no" : R_OPEN
  if (open == "yes") OPENC++
  OUT[++NOUT] = "FINDING=" id " ROUND=" ROUND " MODE=" MODEOF[ROUND] " OPEN=" open " RESOLUTION=" R_CANON
  if (R_CANON == "follow-up → slice archive")
    FU[++NFU] = "FOLLOWUP=" id " " sev " · " fix " · " desc (R_NOTE == "" ? "" : " — " R_NOTE)
}

BEGIN {
  NRES = split(ENVIRON["CRAFT_RESOLUTIONS"], rows, "\n")
  for (k = 1; k <= NRES; k++) {
    split(rows[k], p, "|"); RES_O[k] = p[1]; RES_C[k] = substr(rows[k], length(p[1]) + length(p[2]) + 3)
  }
  insec = 0; fence = ""; ROUND = 0; LEGACY = "no"; OPENC = 0; PENDING = ""
}
{
  sub(/\r$/, "")
  # CommonMark-style fences: up to 3 spaces of indent, a run of 3+ backticks or tildes; a
  # backtick opener carries no backtick in its info string; a closer uses the same character,
  # is at least as long, and has nothing after it. An unclosed fence is reported at END.
  if (fence == "") {
    if (match($0, /^ ? ? ?(```+|~~~+)/)) {
      run = substr($0, RSTART, RLENGTH); sub(/^ +/, "", run)
      info = substr($0, RSTART + RLENGTH)
      if (!(substr(run, 1, 1) == "`" && index(info, "`"))) {
        fence = run; fence_line = NR; if (insec) flush(); next
      }
    }
  } else {
    line2 = $0; sub(/^ ? ? ?/, "", line2)
    c = substr(fence, 1, 1)
    isclose = 0
    if (c == "`" && line2 ~ /^`+[ \t]*$/) isclose = 1
    if (c == "~" && line2 ~ /^~+[ \t]*$/) isclose = 1
    if (isclose) {
      closer = line2; sub(/[ \t]+$/, "", closer)
      if (length(closer) >= length(fence)) { fence = ""; next }
    }
    next
  }
  if ($0 ~ /^## /) {
    if (insec) { flush(); insec = 0 }
    if (tolower($0) ~ /^## review findings([^a-z0-9_]|$)/) insec = 1
    next
  }
  if (!insec) next
  if ($0 ~ /^### Round[ \t]+[0-9]+/) {
    flush()
    ROUND++
    MODEOF[ROUND] = (tolower($0) ~ /\([ \t]*advisory[ \t]*\)[ \t]*$/) ? "advisory" : "phase8"
    num = $0; sub(/^### Round[ \t]+/, "", num); sub(/[^0-9].*$/, "", num)
    if (num + 0 != ROUND) malformed("heading-" ROUND, NR)
    next
  }
  near = ($0 ~ /(^|[ \t*.])(Heavy|Light)[ \t]*·[ \t]*(Local|Rethink)[ \t]*·/)
  bullet = ($0 ~ /^[ \t]*([-*]|[0-9]+[.)])[ \t]/)
  if ($0 ~ /^[ \t]+[^ \t]/ && PENDING != "" && !bullet) { PENDING = PENDING " " trim($0); next }
  flush()
  if ($0 ~ /^- note([ \t]*·|:)/) next
  if ($0 ~ /^- /) {
    if (ROUND == 0) { ROUND = 1; MODEOF[1] = "phase8"; LEGACY = "yes" }
    PENDING = substr($0, 3); PENDING_NO = NR
    next
  }
  if (near) {
    if (ROUND == 0) { ROUND = 1; MODEOF[1] = "phase8"; LEGACY = "yes" }
    POS[ROUND]++
    malformed("R" ROUND "-" POS[ROUND], NR)
    OUT[++NOUT] = "FINDING=R" ROUND "-" POS[ROUND] " ROUND=" ROUND " MODE=" MODEOF[ROUND] " OPEN=" (MODEOF[ROUND] == "advisory" ? "no" : "yes") " RESOLUTION=unknown"
    if (tolower($0) ~ /follow-up/) FU[++NFU] = "FOLLOWUP_MALFORMED=R" ROUND "-" POS[ROUND] " LINE=" NR
  }
}
END {
  flush()
  if (fence != "") {
    if (ROUND == 0) MODEOF[0] = "phase8"
    MAL[++NMAL] = "MALFORMED=fence-unclosed LINE=" fence_line " MODE=phase8"; OPENC++
    FU[++NFU] = "FOLLOWUP_MALFORMED=fence-unclosed LINE=" fence_line
  }
  if (ENVIRON["CRAFT_MODE"] == "followups") {
    for (k = 1; k <= NFU; k++) print FU[k]
    exit 0
  }
  print "ROUNDS=" ROUND
  print "LEGACY=" LEGACY
  print "NEXT_ROUND=" (ROUND + 1)
  for (k = 1; k <= NOUT; k++) print OUT[k]
  for (k = 1; k <= NMAL; k++) print MAL[k]
  print "OPEN_COUNT=" OPENC
}
' "${PLAN}"
