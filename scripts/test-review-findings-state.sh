#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-review-findings-state.sh — self-contained tests for the B6 findings-record helper
# (review-findings-state.sh), which decides which review findings are open, which round
# comes next, and which lines are follow-ups.
#
# No test runner exists in this repo (plugin assets, not runtime software), so this
# harness stands alone: it writes throwaway slice plans under a temp dir, drives the helper,
# asserts on its key=value output, and exits non-zero if any case fails. Run it directly:
#
#   bash scripts/test-review-findings-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/review-findings-state.sh"
REVIEW="$REPO_ROOT/commands/review.md"
for f in "$HELPER" "$REVIEW"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

plan() { # stdin → a plan file; prints its path (called in $(…), so no shared counter)
  local p
  p="$(mktemp "$ROOT/plan.XXXXXX")" && cat > "$p" && printf '%s' "$p"
}
run() { bash "$HELPER" "$@" 2>&1; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
line_for() { printf '%s\n' "$1" | grep "^FINDING=$2 "; }

# --- no record ---------------------------------------------------------------------------
P="$(printf '# Slice\n\n## Sub-Tasks\n\n- [x] done\n' | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=0" && has "$out" "NEXT_ROUND=1" && has "$out" "OPEN_COUNT=0" && ! printf '%s' "$out" | grep -q '^FINDING='; } \
  && ok "no ## Review Findings section → ROUNDS=0, NEXT_ROUND=1, OPEN_COUNT=0" || bad "no record (out=$out)"

P="$(printf '# Slice\n\n## Review Findings\n\n> Filled by /craft:review.\n\n(none yet)\n\n## Blocker\n' | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=0" && has "$out" "OPEN_COUNT=0"; } && ok "empty section with placeholder → no rounds, nothing open" || bad "empty section (out=$out)"

# --- legacy record -------------------------------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

- Heavy · Rethink · spun off before IDs · escalated → new slice
- Light · Local · a style nit · fixed in-phase
- Heavy · Rethink · unrouted · escalated → route pending
EOF
)"
out="$(run "$P")"
{ has "$out" "ROUNDS=1" && has "$out" "LEGACY=yes" && has "$out" "NEXT_ROUND=2" \
  && [[ "$(line_for "$out" R1-1)" == *"OPEN=yes"* ]] && [[ "$(line_for "$out" R1-2)" == *"OPEN=no"* ]] \
  && [[ "$(line_for "$out" R1-3)" == *"OPEN=yes"* ]] && has "$out" "OPEN_COUNT=2"; } \
  && ok "legacy record: one Phase-8 round, IDs by position, new slice without an ID stays open" || bad "legacy (out=$out)"

# --- every resolution, multi-round -----------------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (Phase-8)

- R1-1 · Heavy · Local · a · fixed in-phase
- R1-2 · Light · Rethink · b · follow-up → slice archive
- R1-3 · Heavy · Rethink · c · escalated → Phase 4 loop-back
- R1-4 · Light · Local · d · escalated → Phase 4 loop-back (fix cap)
- R1-5 · Heavy · Rethink · e · escalated → new slice (pending)
- R1-6 · Heavy · Rethink · f · escalated → new slice slice-042
- R1-7 · Heavy · Rethink · g · escalated → route pending
- R1-8 · Heavy · Local · h · open — fix cap, awaiting decision
- R1-9 · Heavy · Rethink · i · resolved in round 2
- note · fix cap (5) waived by the user

### Round 2 — 2026-09-15 (Phase-8)

- R2-1 · Light · Local · j · fixed in-phase: renamed the variable
- R2-2 · Heavy · Rethink · k · escalated → Phase 4 loop-back (user: build pauses too)
- R2-3 · Heavy · Local · l · accepted → known limit: needs adversarial input
EOF
)"
out="$(run "$P")"
want_open="R1-5 R1-7 R1-8"; want_closed="R1-1 R1-2 R1-3 R1-4 R1-6 R1-9 R2-1 R2-2 R2-3"; wrong=""
for id in $want_open;   do [[ "$(line_for "$out" "$id")" == *"OPEN=yes"* ]] || wrong="$wrong $id"; done
for id in $want_closed; do [[ "$(line_for "$out" "$id")" == *"OPEN=no"* ]]  || wrong="$wrong $id"; done
{ [[ -z "$wrong" ]] && has "$out" "OPEN_COUNT=3" && has "$out" "ROUNDS=2" && has "$out" "NEXT_ROUND=3" && has "$out" "LEGACY=no" \
  && ! printf '%s' "$out" | grep -q '^MALFORMED='; } \
  && ok "every resolution value: open = new slice (pending), route pending, fix-cap awaiting; notes after ':' / ' (' allowed" \
  || bad "resolution table (wrong:$wrong; out=$out)"
[[ "$(line_for "$out" R1-9)" == *"RESOLUTION=resolved in round <R>"* ]] && ok "resolved in round <R> closes a line" || bad "resolved route (out=$(line_for "$out" R1-9))"
[[ "$(line_for "$out" R1-4)" == *"RESOLUTION=escalated → Phase 4 loop-back (fix cap)"* ]] && ok "longest prefix wins: (fix cap) is its own resolution" || bad "longest prefix (out=$(line_for "$out" R1-4))"
printf '%s' "$out" | grep -q '^FINDING=note' && bad "a note line was read as a finding" || ok "note · lines are not findings"

# --- the slice-034 false positive and field positions --------------------------------------------
P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (Phase-8)

- R1-1 · Heavy · Rethink · the gate once read `escalated → route pending` as open · fixed in-phase
- R1-2 · Light · Local · a description · with a middle dot · fixed in-phase
- R1-3 · Light · Local · wrapped over
  two lines · escalated → route pending
EOF
)"
out="$(run "$P")"
{ [[ "$(line_for "$out" R1-1)" == *"OPEN=no"* ]] && [[ "$(line_for "$out" R1-2)" == *"OPEN=no"* ]] && ! printf '%s' "$out" | grep -q '^MALFORMED='; } \
  && ok "a resolution quoted inside a description, or a ' · ' in it, does not decide the line — the last field does" || bad "quoted value (out=$out)"
[[ "$(line_for "$out" R1-3)" == *"OPEN=yes"* ]] && ok "an indented continuation line belongs to the finding above" || bad "continuation (out=$out)"

# --- doubt blocks ------------------------------------------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (Phase-8)

- R1-1 · Medium · Local · bad severity · fixed in-phase
- R1-2 · Light · Quick · bad fix-nature · fixed in-phase
- R1-3 · Light · Local · unknown resolution · done
- R1-4 · Light · Local · too few fields
- R1-5 · Light · Local · glued suffix · fixed in-phasey
EOF
)"
out="$(run "$P")"
wrong=""
for id in R1-1 R1-2 R1-3 R1-4 R1-5; do
  [[ "$(line_for "$out" "$id")" == *"OPEN=yes"* ]] || wrong="$wrong $id"
  printf '%s\n' "$out" | grep -q "^MALFORMED=$id " || wrong="$wrong $id(no-MALFORMED)"
done
{ [[ -z "$wrong" ]] && has "$out" "OPEN_COUNT=5"; } && ok "bad severity / fix-nature / resolution / field count / glued suffix → MALFORMED and open (doubt blocks)" || bad "malformed (wrong:$wrong; out=$out)"

# --- advisory rounds, section bounds, CRLF ----------------------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (advisory)

- R1-1 · Heavy · Rethink · looked at mid-flow · advisory — no route
- R1-2 · Heavy · Rethink · even an open-looking value · escalated → route pending

## Blocker

- Heavy · Rethink · outside the section · escalated → route pending
EOF
)"
out="$(run "$P")"
{ [[ "$(line_for "$out" R1-1)" == *"MODE=advisory OPEN=no"* ]] && [[ "$(line_for "$out" R1-2)" == *"OPEN=no"* ]] && has "$out" "OPEN_COUNT=0" \
  && [[ "$(printf '%s\n' "$out" | grep -c '^FINDING=')" == 2 ]]; } \
  && ok "advisory rounds are never open; lines outside ## Review Findings are ignored" || bad "advisory/bounds (out=$out)"

P="$(printf '## Review Findings\r\n\r\n### Round 1 — 2026-09-14 (Phase-8)\r\n\r\n- R1-1 · Heavy · Rethink · crlf · escalated → route pending\r\n' | plan)"
out="$(run "$P")"
{ [[ "$(line_for "$out" R1-1)" == *"OPEN=yes RESOLUTION=escalated → route pending"* ]] && ! printf '%s' "$out" | grep -q '^MALFORMED='; } \
  && ok "CRLF record reads the same" || bad "CRLF (out=$out)"

# --- round numbering with a legacy block before headings ----------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

- Light · Local · legacy line · fixed in-phase

### Round 2 — 2026-09-14 (Phase-8)

- Heavy · Rethink · headed but no ID · escalated → route pending
EOF
)"
out="$(run "$P")"
{ has "$out" "ROUNDS=2" && has "$out" "NEXT_ROUND=3" && [[ "$(line_for "$out" R2-1)" == *"OPEN=yes"* ]]; } \
  && ok "legacy lines count as round 1; a heading after them is round 2; ID-less lines numbered in their round" || bad "numbering (out=$out)"

# --- follow-ups --------------------------------------------------------------------------------------------------
P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (Phase-8)

- R1-1 · Light · Rethink · first follow-up · follow-up → slice archive
- R1-2 · Heavy · Local · not one · fixed in-phase
- R1-3 · Light · Rethink · second · with a dot · follow-up → slice archive: roadmap B8
- R1-4 · Light · Rethink · a mention of follow-up → slice archive · fixed in-phase
- R1-5 · Lite · Rethink · a broken follow-up line · follow-up → slice archive
- R1-6 · Heavy · Rethink · accepted at the round cap · accepted → known limit: needs a hostile author
- R1-7 · Heavy · Local · accepted without a reason · accepted → known limit
- R1-8 · Heavy · Nope · a broken known-limit line · accepted → known limit
EOF
)"
out="$(run "$P" --followups)"
[[ "$out" == $'FOLLOWUP=R1-1 Light · Rethink · first follow-up\nFOLLOWUP=R1-3 Light · Rethink · second · with a dot — roadmap B8\nFOLLOWUP_MALFORMED=R1-5 LINE=9\nFOLLOWUP=R1-6 Heavy · Rethink · accepted at the round cap — known limit: needs a hostile author\nFOLLOWUP=R1-7 Heavy · Local · accepted without a reason — known limit\nFOLLOWUP_MALFORMED=R1-8 LINE=12' ]] \
  && ok "--followups keeps severity, fix-nature and the resolution note, carries accepted known limits (slice-052), and reports malformed lines" || bad "followups (out=$out)"

# --- near-format lines, fences, headings, IDs (review round 1: R1-3, R1-5) ---------------------------------------
P="$(plan <<'EOF'
## Review Findings (Phase 8)

### Round 1 — 2026-09-14 (Phase-8, re-checks an earlier advisory pass)

* R1-1 · Heavy · Rethink · star bullet · escalated → route pending
1. Heavy · Rethink · numbered · escalated → route pending
- R1-3 · Light · Local · a real line · fixed in-phase

  - R1-4 · Heavy · Rethink · indented after a blank · escalated → route pending
- R1-5 · Light · Local · padded columns   · fixed in-phase
- R1-6 · Heavy   · Local   · padded severity and fix-nature · fixed in-phase
- R1-5 · Light · Local · duplicate ID · fixed in-phase
- R7-1 · Light · Local · ID from another round · fixed in-phase

```
## an example heading inside a fence
- R1-9 · Heavy · Rethink · example only · escalated → route pending
```

- R1-8 · Heavy · Rethink · after the fence · escalated → route pending

### Round 3 — 2026-09-15 (Phase-8)

- R2-1 · Light · Local · heading number skips 2 · fixed in-phase
EOF
)"
out="$(run "$P")"
mal="$(printf '%s\n' "$out" | grep '^MALFORMED=' | sed -E 's/^MALFORMED=([^ ]+) .*/\1/' | tr '\n' ' ')"
{ has "$out" "ROUNDS=2" && [[ "$(line_for "$out" R1-8)" == *"MODE=phase8 OPEN=yes"* ]] && [[ "$(line_for "$out" R1-3)" == *"OPEN=no"* ]] \
  && ! printf '%s' "$out" | grep -q '^FINDING=R1-9 ' ; } \
  && ok "suffixed section heading read; '(…, … advisory …)' mid-heading stays Phase-8; fenced lines skipped" || bad "section/fence/advisory (out=$out)"
for want in R1-1 R1-2 R1-4 heading-2; do
  [[ " $mal " == *" $want "* ]] || bad "expected MALFORMED $want (got: $mal)"
done
[[ " $mal " == *" R1-1 "* && " $mal " == *" R1-2 "* && " $mal " == *" R1-4 "* ]] \
  && ok "star, numbered and indented bullets carrying the severity · fix-nature pattern → MALFORMED" || true
[[ " $mal " == *" heading-2 "* ]] && ok "a round heading whose number is not its position → MALFORMED" || true
dups="$(printf '%s\n' "$out" | grep -c '^MALFORMED=R1-5 ')"
{ [[ "$dups" == 1 ]] && [[ " $mal " == *" R7-1 "* ]]; } && ok "a repeated ID and an ID from another round → MALFORMED" || bad "ids (dups=$dups mal=$mal)"
{ [[ "$(printf '%s\n' "$out" | grep -c '^FINDING=R1-5 .*RESOLUTION=fixed in-phase')" == 1 ]] && [[ "$(line_for "$out" R1-6)" == *"RESOLUTION=fixed in-phase"* ]]; } \
  && ok "padded columns ('Heavy   ·', 'Local   ·', '…   ·') still read" || bad "padding (out=$out)"
printf '%s\n' "$out" | grep -q '^MALFORMED=.* MODE=phase8$' && ok "MALFORMED lines carry MODE" || bad "MALFORMED without MODE (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-14 (advisory)

- R1-1 · Heavy · Wrong · malformed but advisory · advisory — no route
EOF
)"
out="$(run "$P")"
{ has "$out" "OPEN_COUNT=0" && printf '%s\n' "$out" | grep -q '^MALFORMED=R1-1 LINE=[0-9]* MODE=advisory$'; } \
  && ok "an advisory MALFORMED line is reported with MODE=advisory and not counted open" || bad "advisory malformed (out=$out)"

# --- fences that must not hide findings (review round 2: R2-1) and heading/follow-up gaps (R2-5) ---------------------
P="$(printf '# P\n\n~~~\n```\n~~~\n\n## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a · escalated → route pending\n' | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=1" && has "$out" "OPEN_COUNT=1"; } && ok "a ~~~ fence containing a \`\`\` line closes only on ~~~ — the section after it is read" || bad "tilde fence (out=$out)"

P="$(printf '## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n```\nnever closed\n- R1-1 · Heavy · Rethink · a · escalated → route pending\n' | plan)"
out="$(run "$P")"
{ printf '%s\n' "$out" | grep -q '^MALFORMED=fence-unclosed LINE=5 MODE=phase8$' && has "$out" "OPEN_COUNT=1"; } \
  && ok "a fence left open at the end is MALFORMED and counted open (it may hide findings)" || bad "unclosed fence (out=$out)"

# R2-1 loop-back (slice-047): a prose line that merely NAMES an HTML comment opener used to open a
# phantom example region that the exact-`-->` closer never closed, so the whole rest of the plan --
# the findings record with it -- was blanked and this parser answered OPEN_COUNT=0 on a plan with an
# open finding. This is the case that would have caught it: the gate reads THIS number. The token is
# assembled at run time so that this harness does not carry a line naming it, which is the trigger.
OPENER="$(printf '<!%s' '--')"
P="$(printf '# P\n\nthe token `%s` named in prose must not open a region\n\n## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a · escalated → route pending\n' "$OPENER" | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=1" && has "$out" "OPEN_COUNT=1"; } \
  && ok "a prose mention of a comment opener does not hide the findings record (R2-1)" || bad "prose opener mention (out=$out)"

P="$(printf '# P\n\n%s\nhidden\n%s\n\n## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a · escalated → route pending\n' "$OPENER" '-->' | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=1" && has "$out" "OPEN_COUNT=1"; } \
  && ok "a real comment block that opens and closes still hides only its own lines (R2-1 guard)" || bad "real comment block (out=$out)"

# R3-1 (slice-047 review round 3): a block closed at the END of its last text line -- the shape an
# editor's block-comment toggle writes -- was never closed by the exact-`-->` rule, and this parser
# answered OPEN_COUNT=0 on a plan with an open finding.
P="$(printf '# P\n\n%s Dropped from scope for now:\nthe old goal paragraph, kept for reference %s\n\n## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a · escalated → route pending\n' "$OPENER" '-->' | plan)"
out="$(run "$P")"
{ has "$out" "ROUNDS=1" && has "$out" "OPEN_COUNT=1"; } \
  && ok "a comment block closed at the end of its last text line does not hide the findings record (R3-1)" || bad "trailing closer (out=$out)"

P="$(printf '## Review Findings:\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a\n  ```foo``` wrapped · fixed in-phase\n- R1-2 · Heavy · Rethink · b · escalated → route pending\n' | plan)"
out="$(run "$P")"
{ [[ "$(line_for "$out" R1-2)" == *"OPEN=yes"* ]] && has "$out" "OPEN_COUNT=1" && ! printf '%s' "$out" | grep -q '^MALFORMED='; } \
  && ok "an inline \`\`\`code\`\`\` span is not a fence; a '## Review Findings:' heading is read" || bad "inline span / colon heading (out=$out)"

P="$(printf '## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n* R1-1 · Light · Rethink · starred · Follow-up → slice archive\n- R1-2 · Lite · Rethink · bad severity · Follow-up → slice archive\n' | plan)"
out="$(run "$P" --followups)"
[[ "$out" == $'FOLLOWUP_MALFORMED=R1-2 LINE=6\nFOLLOWUP_MALFORMED=R1-1 LINE=5' || "$out" == $'FOLLOWUP_MALFORMED=R1-1 LINE=5\nFOLLOWUP_MALFORMED=R1-2 LINE=6' ]] \
  && ok "a near-format or capitalised follow-up line that cannot be read is still reported" || bad "followup malformed variants (out=$out)"

# --- ping-pong breaker (slice-052) -----------------------------------------------------------------------------------
# The breaker's counters are DERIVED from the record, never stored: rounds from the round headings, reopens from a
# finding whose description starts `reopens <ID>:` (agents/code-reviewer.md → 2). A reopen trips only in the LATEST
# Phase-8 round — the record is append-only, so an old reopen the human has already answered must not trip again.

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · wrong gate · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Light · Local · a new nit · fixed in-phase
EOF
)"
out="$(run "$P")"
{ has "$out" "TRIP=none" && has "$out" "PHASE8_ROUNDS=2" && has "$out" "ROUND_CAP=3" && has "$out" "OPEN_HEAVY=0" \
  && ! printf '%s' "$out" | grep -q '^REOPEN='; } \
  && ok "breaker: a loop-back that held (no reopen) → TRIP=none, PHASE8_ROUNDS=2, ROUND_CAP=3" || bad "breaker no trip (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · wrong gate · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · reopens R1-1: the gate still reads the wrong field · escalated → route pending
EOF
)"
out="$(run "$P")"
{ has "$out" "REOPEN=R2-1 OF=R1-1 SEV=Heavy KNOWN=yes" && has "$out" "TRIP=reopen:R1-1" && has "$out" "OPEN_HEAVY=1"; } \
  && ok "breaker: a Heavy reopen in the latest round trips on the first reopen → TRIP=reopen:R1-1" || bad "breaker reopen trip (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Local · off-by-one · fixed in-phase

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Light · Local · Reopens R1-1 : the comment still names the old bound · fixed in-phase
EOF
)"
out="$(run "$P")"
{ has "$out" "REOPEN=R2-1 OF=R1-1 SEV=Light KNOWN=yes" && has "$out" "TRIP=none"; } \
  && ok "breaker: a Light reopen is reported but does not trip (case and a space before ':' tolerated)" || bad "breaker light reopen (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Local · off-by-one · fixed in-phase

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Local · reopens R1-1: still off by one · fixed in-phase
EOF
)"
out="$(run "$P")"
{ has "$out" "REOPEN=R2-1 OF=R1-1 SEV=Heavy KNOWN=yes" && has "$out" "TRIP=none" && has "$out" "OPEN_COUNT=0"; } \
  && ok "breaker: a Heavy reopen of a line fixed in-phase (never looped back) does not trip (slice-052 R1-3)" || bad "breaker in-phase reopen (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · wrong gate · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · reopens R1-1: still wrong · escalated → Phase 4 loop-back (user: one more try)

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Light · Local · a nit · fixed in-phase
EOF
)"
out="$(run "$P")"
{ has "$out" "REOPEN=R2-1 OF=R1-1 SEV=Heavy KNOWN=yes" && has "$out" "TRIP=none"; } \
  && ok "breaker: an answered reopen in an earlier round does not trip again (only the latest round counts)" || bad "breaker old reopen (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Light · Local · reopens R9-9: points nowhere · fixed in-phase
- R2-2 · Light · Local · reopens R2-1: points into its own round · fixed in-phase
EOF
)"
out="$(run "$P")"
{ has "$out" "REOPEN=R2-1 OF=R9-9 SEV=Light KNOWN=no" && has "$out" "REOPEN=R2-2 OF=R2-1 SEV=Light KNOWN=no" \
  && has "$out" "TRIP=reopen:R9-9"; } \
  && ok "breaker: a reopen of an unknown or not-earlier ID is doubt → it trips even when Light" || bad "breaker unknown reopen (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · b · escalated → Phase 4 loop-back

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Heavy · Rethink · c, a new one again · escalated → route pending
- R3-2 · Light · Rethink · d · follow-up → slice archive
EOF
)"
out="$(run "$P")"
{ has "$out" "PHASE8_ROUNDS=3" && has "$out" "OPEN_HEAVY=1" && has "$out" "TRIP=round-cap"; } \
  && ok "breaker: round 3 closes with a Heavy open → TRIP=round-cap" || bad "breaker round cap (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (advisory)

- R2-1 · Heavy · Rethink · reopens R1-1: advisory only · advisory — no route

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Light · Local · e · open — fix cap, awaiting decision
EOF
)"
out="$(run "$P")"
{ has "$out" "PHASE8_ROUNDS=2" && has "$out" "TRIP=none" && ! printf '%s' "$out" | grep -q '^REOPEN='; } \
  && ok "breaker: advisory rounds count neither as Phase-8 rounds nor as reopens; an open Light never trips" || bad "breaker advisory (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · b · escalated → Phase 4 loop-back

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Heavy · Rethink · c · escalated → Phase 4 loop-back
- note · extra round granted: the user wants one more try at c
EOF
)"
out="$(run "$P")"
{ has "$out" "ROUND_CAP=4" && has "$out" "TRIP=none"; } \
  && ok "breaker: a '- note · extra round granted' line raises the cap by one" || bad "breaker grant (out=$out)"

# Each note counts, so /craft:review writes it ONCE per run (review.md cap route, slice-052 R2-2); two notes = two rounds.
P="$(printf '## Review Findings\n\n### Round 1 — 2026-09-30 (Phase-8)\n\n- R1-1 · Light · Local · a · fixed in-phase\n- note · extra round granted: one\n- note · extra round granted: two\n' | plan)"
out="$(run "$P")"
has "$out" "ROUND_CAP=5" && ok "breaker: every grant note counts (two notes → ROUND_CAP=5) — hence one note per run" || bad "breaker two grants (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · b · escalated → Phase 4 loop-back

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Heavy · Rethink · reopens R2-1: b again · escalated → route pending
EOF
)"
out="$(run "$P")"
has "$out" "TRIP=reopen:R2-1" && ok "breaker: reopen and round cap together → the reopen names the trip" || bad "breaker both (out=$out)"

P="$(plan <<'EOF'
## Review Findings

### Round 1 — 2026-09-30 (Phase-8)

- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back

### Round 2 — 2026-09-30 (Phase-8)

- R2-1 · Heavy · Rethink · b · escalated → Phase 4 loop-back

### Round 3 — 2026-09-30 (Phase-8)

- R3-1 · Heavy · Wrong · unreadable · escalated → route pending
EOF
)"
out="$(run "$P")"
has "$out" "TRIP=round-cap" && ok "breaker: a MALFORMED line open at the cap is doubt → TRIP=round-cap" || bad "breaker malformed at cap (out=$out)"

P="$(printf '# Slice\n\n## Sub-Tasks\n\n- [x] done\n' | plan)"
out="$(run "$P")"
{ has "$out" "TRIP=none" && has "$out" "PHASE8_ROUNDS=0" && has "$out" "ROUND_CAP=3"; } \
  && ok "breaker: no record → TRIP=none" || bad "breaker no record (out=$out)"

# --- arguments ------------------------------------------------------------------------------------------------------
run >/dev/null; rc=$?; [[ $rc -eq 2 ]] && ok "missing plan argument → exit 2" || bad "missing arg (rc=$rc)"
run "$ROOT/nope.md" >/dev/null; rc=$?; [[ $rc -eq 4 ]] && ok "unreadable plan → exit 4" || bad "unreadable (rc=$rc)"
run --bogus >/dev/null; rc=$?; [[ $rc -eq 2 ]] && ok "unknown argument → exit 2" || bad "unknown argument (rc=$rc)"

# --- commands/review.md Step 6 shows the helper's resolutions -------------------------------------------------------
# The format block in Step 6 is the readable copy of RESOLUTIONS; legacy-only values are
# described in prose there, not listed. This binds the two.
step6="$(awk '/^### Step 6/{s=1} s&&/^```/{c++; next} s&&c==1&&/^- /{print} c>=2{exit}' "$REVIEW" \
  | grep -v '^- note' | sed -E 's/.* · //' | sed -E 's/[[:space:]]+$//' | sort -u)"
helper_res="$(bash "$HELPER" --print-resolutions | awk -F'|' '$2=="no"{print substr($0, index($0,$3))}' | sort -u)"
{ [[ -n "$step6" ]] && [[ "$step6" == "$helper_res" ]]; } \
  && ok "commands/review.md Step 6 format block lists exactly the helper's resolutions" \
  || bad "Step 6 ↔ helper drift: step6=[$(printf '%s' "$step6" | tr '\n' ';')] helper=[$(printf '%s' "$helper_res" | tr '\n' ';')]"

# --- the example-regions helper is unavailable (slice-047) -----------------------------------------------------------
# This parser no longer decides what a fenced example is; scripts/example-regions.sh does. Without
# it the script cannot tell a finding line from one parked in an example, so it FAILS rather than
# answering. That is what its two callers are built for: commands/review.md Step 6 reads a
# non-zero exit as "nothing about the record is known" and keeps Commit blocked, and
# handoff-marker-state.sh turns it into `unknown`, which doubt-means-live keeps live. An earlier
# draft fell back to the raw file and said nothing, which is the one outcome neither caller can
# detect.
# Created under $ROOT so the EXIT trap at the top of this file covers it, including on a signal.
# A second, independent temp lifecycle is a second copy of the cleanup rule (slice-047, N6 round 2).
NOHELP="$(mktemp -d "$ROOT/nohelp.XXXXXX")"
mkdir -p "$NOHELP/scripts"
cp "$HELPER" "$NOHELP/scripts/"
printf '## Review Findings\n\n- Heavy · Rethink · x · escalated → route pending\n' > "$NOHELP/plan.md"
out="$(bash "$NOHELP/scripts/$(basename "$HELPER")" "$NOHELP/plan.md" 2>&1)"; rc=$?
{ [[ $rc -ne 0 ]] && [[ "$out" == *"example_regions_helper_missing"* ]] && ! printf '%s' "$out" | grep -q '^OPEN_COUNT='; } \
  && ok "without example-regions.sh the parser fails closed — non-zero, named error, no OPEN_COUNT to misread" \
  || bad "fail-closed (rc=$rc out=$out)"

# --- old bash -------------------------------------------------------------------------------------------------------
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]]; then
  P="$(printf '## Review Findings\n\n- Heavy · Rethink · x · escalated → route pending\n- Light · Local · y · fixed in-phase\n\n### Round 2 — 2026-09-14 (Phase-8)\n\n- R2-1 · Heavy · Rethink · z · escalated → new slice (pending)\n' | plan)"
  out="$(/bin/bash "$HELPER" "$P" 2>&1)"
  { has "$out" "OPEN_COUNT=2" && [[ "$out" != *"line "*": "* ]]; } && ok "under /bin/bash 3.2: same answer, no shell errors" || bad "bash 3.2 (out=$out)"
  P="$(printf '## Review Findings\n\n### Round 1 — 2026-09-30 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a · escalated → Phase 4 loop-back\n\n### Round 2 — 2026-09-30 (Phase-8)\n\n- R2-1 · Heavy · Rethink · reopens R1-1: again · escalated → route pending\n' | plan)"
  out="$(/bin/bash "$HELPER" "$P" 2>&1)"
  { has "$out" "TRIP=reopen:R1-1" && has "$out" "REOPEN=R2-1 OF=R1-1 SEV=Heavy KNOWN=yes" && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash 3.2: the breaker trips the same, no shell errors" || bad "bash 3.2 breaker (out=$out)"
else
  echo "  SKIP  no bash < 4 at /bin/bash — old-bash run not exercised"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
