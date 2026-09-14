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
EOF
)"
out="$(run "$P")"
want_open="R1-5 R1-7 R1-8"; want_closed="R1-1 R1-2 R1-3 R1-4 R1-6 R1-9 R2-1 R2-2"; wrong=""
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
EOF
)"
out="$(run "$P" --followups)"
[[ "$out" == $'FOLLOWUP=R1-1 Light · Rethink · first follow-up\nFOLLOWUP=R1-3 Light · Rethink · second · with a dot — roadmap B8\nFOLLOWUP_MALFORMED=R1-5 LINE=9' ]] \
  && ok "--followups keeps severity, fix-nature and the resolution note, and reports a malformed follow-up line" || bad "followups (out=$out)"

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

P="$(printf '## Review Findings:\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n- R1-1 · Heavy · Rethink · a\n  ```foo``` wrapped · fixed in-phase\n- R1-2 · Heavy · Rethink · b · escalated → route pending\n' | plan)"
out="$(run "$P")"
{ [[ "$(line_for "$out" R1-2)" == *"OPEN=yes"* ]] && has "$out" "OPEN_COUNT=1" && ! printf '%s' "$out" | grep -q '^MALFORMED='; } \
  && ok "an inline \`\`\`code\`\`\` span is not a fence; a '## Review Findings:' heading is read" || bad "inline span / colon heading (out=$out)"

P="$(printf '## Review Findings\n\n### Round 1 — 2026-09-14 (Phase-8)\n\n* R1-1 · Light · Rethink · starred · Follow-up → slice archive\n- R1-2 · Lite · Rethink · bad severity · Follow-up → slice archive\n' | plan)"
out="$(run "$P" --followups)"
[[ "$out" == $'FOLLOWUP_MALFORMED=R1-2 LINE=6\nFOLLOWUP_MALFORMED=R1-1 LINE=5' || "$out" == $'FOLLOWUP_MALFORMED=R1-1 LINE=5\nFOLLOWUP_MALFORMED=R1-2 LINE=6' ]] \
  && ok "a near-format or capitalised follow-up line that cannot be read is still reported" || bad "followup malformed variants (out=$out)"

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

# --- old bash -------------------------------------------------------------------------------------------------------
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]]; then
  P="$(printf '## Review Findings\n\n- Heavy · Rethink · x · escalated → route pending\n- Light · Local · y · fixed in-phase\n\n### Round 2 — 2026-09-14 (Phase-8)\n\n- R2-1 · Heavy · Rethink · z · escalated → new slice (pending)\n' | plan)"
  out="$(/bin/bash "$HELPER" "$P" 2>&1)"
  { has "$out" "OPEN_COUNT=2" && [[ "$out" != *"line "*": "* ]]; } && ok "under /bin/bash 3.2: same answer, no shell errors" || bad "bash 3.2 (out=$out)"
else
  echo "  SKIP  no bash < 4 at /bin/bash — old-bash run not exercised"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
