#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-plan-gate-state.sh — self-contained tests for plan-gate-state.sh (slice-054): which slice
# plans of an epic still await the autopilot's plan gate, derived from the plans and the epic
# plan's `## Autopilot Log` — never stored.
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-plan-gate-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/plan-gate-state.sh"
EXECUTE="$REPO_ROOT/commands/execute.md"
PLAN_CMD="$REPO_ROOT/commands/plan.md"
AGENT="$REPO_ROOT/agents/slice-planner.md"
TEMPLATE="$REPO_ROOT/templates/epic-plan.md.template"
for f in "$HELPER" "$EXECUTE" "$PLAN_CMD" "$AGENT" "$SCRIPT_DIR/epic-entry-link.sh" "$SCRIPT_DIR/example-regions.sh"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
EPIC=".claude/plans/epic-009-fixture.md"

reset() {
  rm -rf "$P"
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
}
# epic <log-body> [entries] — an epic plan with the given ## Autopilot Log body
epic() {
  local entries="${2:-- [ ] slice-101 — alpha — first entry
- [ ] slice-102 — beta — second entry}"
  printf '# Epic 009 — Fixture\n\n> Status: planning\n> Epic-ID: epic-009\n> Epic-Slug: fixture\n\n## Vision\n\nv\n\n## Slice Decomposition\n\n%s\n\n## Autopilot Log\n\n%s\n\n## Recap Draft\n\n(not yet recorded)\n' \
    "$entries" "$1" > "$P/$EPIC"
}
# plan <id> <slug> <planned-by: yes|no|<value>> [extra body]
plan() {
  local pb=""
  case "$3" in
    yes) pb='> Planned-by: autopilot
' ;;
    no)  pb="" ;;
    *)   pb="> Planned-by: $3
" ;;
  esac
  printf '# Slice %s — %s\n\n> Status: planning\n> Slice-ID: %s\n> Depends-On: []\n%s\n## Goal\n\ng\n\n## Trigger\n\nt\n\n%s\n' \
    "${1#slice-}" "$2" "$1" "$pb" "${4:-}" > "$P/.claude/plans/$1-$2.md"
}
run() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" "$@" 2>&1); }
val() { printf '%s\n' "$1" | sed -n "s/^.*$2=\([^ ]*\).*$/\1/p" | head -1; }
gate_of() { printf '%s\n' "$1" | grep "^PLAN SLICE=$2 " | sed -n 's/.* GATE=\([^ ]*\).*/\1/p'; }
nh_of() { printf '%s\n' "$1" | grep "^PLAN SLICE=$2 " | sed -n 's/.* NEEDS_HUMAN=\([^ ]*\).*/\1/p'; }
expect() { # <label> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — got '$2', want '$3'"; fi
}

APPROVE_BOTH='- 2026-09-30T10:00:00Z · ▶ · epic-009 · run started
- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101, slice-102'

echo "CASES:"

# 1. hand-planned epic — no Planned-by, no gate
reset; epic '(no autopilot run yet)'; plan slice-101 alpha no; plan slice-102 beta no
out="$(run "$EPIC")"
expect "hand-planned plans read GATE=hand" "$(gate_of "$out" slice-101)/$(gate_of "$out" slice-102)" "hand/hand"
expect "hand-planned epic: RESULT=clear" "$(val "$out" RESULT)" "clear"

# 2. two pipeline plans, empty log
reset; epic '(no autopilot run yet)'; plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "pipeline plans without an approval line await" "$(gate_of "$out" slice-101)/$(gate_of "$out" slice-102)" "awaiting/awaiting"
expect "AWAITING_COUNT counts them" "$(val "$out" AWAITING_COUNT)" "2"
expect "RESULT=gate" "$(val "$out" RESULT)" "gate"

# 3. both approved
reset; epic "$APPROVE_BOTH"; plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "an approval line naming both approves both" "$(gate_of "$out" slice-101)/$(gate_of "$out" slice-102)" "approved/approved"
expect "all approved: RESULT=clear" "$(val "$out" RESULT)" "clear"

# 4. one approved — a plan re-planned later (new ID) is not covered by an older approval
reset
epic '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101'
plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "only the named plan is approved" "$(gate_of "$out" slice-101)/$(gate_of "$out" slice-102)" "approved/awaiting"
expect "one awaiting: RESULT=gate" "$(val "$out" RESULT)/$(val "$out" AWAITING_COUNT)" "gate/1"

# 5. approval for another epic does not count
reset; epic '- 2026-09-30T10:05:00Z · ✓ · epic-008 · plan gate approved: slice-101, slice-102'
plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "another epic's approval line counts for nothing" "$(val "$out" AWAITING_COUNT)" "2"

# 6. malformed approval lines — doubt means awaiting
for bad_line in \
  '- 2026-09-30T10:05:00Z · ⛔ · epic-009 · plan gate approved: slice-101, slice-102' \
  '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved:' \
  '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101 slice-102' \
  '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate shown: slice-101, slice-102' \
  '  - 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101, slice-102' \
  '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101, slice-102 (and more)'; do
  reset; epic "$bad_line"; plan slice-101 alpha yes; plan slice-102 beta yes
  out="$(run "$EPIC")"
  expect "malformed approval line approves nothing: ${bad_line:25:60}" "$(val "$out" AWAITING_COUNT)" "2"
done

# 7. an approval line outside ## Autopilot Log does not count
reset; epic '(no autopilot run yet)'; plan slice-101 alpha yes; plan slice-102 beta yes
printf '%s\n' '- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101, slice-102' >> "$P/$EPIC"
out="$(run "$EPIC")"
expect "an approval line below ## Recap Draft counts for nothing" "$(val "$out" AWAITING_COUNT)" "2"

# 8. an approval line inside a fenced example in the log does not count
reset
epic '```
- 2026-09-30T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101, slice-102
```'
plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "a fenced approval line counts for nothing" "$(val "$out" AWAITING_COUNT)" "2"

# 9. CRLF epic plan still approves
reset; epic "$APPROVE_BOTH"; plan slice-101 alpha yes; plan slice-102 beta yes
sed -i.bak 's/$/\r/' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run "$EPIC")"
expect "a CRLF epic plan's approval line counts" "$(val "$out" RESULT)" "clear"

# 10. NEEDS-HUMAN lines
reset; epic '(no autopilot run yet)'
plan slice-101 alpha yes 'NEEDS-HUMAN: which trigger?

## Effect

- NEEDS-HUMAN: which effect?

## Test Strategy

> NEEDS-HUMAN: which test?

```
NEEDS-HUMAN: fenced, not counted
```

The word NEEDS-HUMAN: inside a sentence is not counted.'
plan slice-102 beta yes
out="$(run "$EPIC")"
expect "NEEDS-HUMAN at line start, bullet or quote counts; fenced and mid-sentence do not" "$(nh_of "$out" slice-101)/$(nh_of "$out" slice-102)" "3/0"
expect "NEEDS_HUMAN_COUNT sums the awaiting plans" "$(val "$out" NEEDS_HUMAN_COUNT)" "3"

# 10b. formatted NEEDS-HUMAN lines still count (review R1-5): bold, checkbox, numbered
reset; epic '(no autopilot run yet)'
plan slice-101 alpha yes '- **NEEDS-HUMAN:** bold marker
- **NEEDS-HUMAN**: bold word
- [ ] NEEDS-HUMAN: checkbox
1. NEEDS-HUMAN: numbered
2) NEEDS-HUMAN: numbered paren
- NEEDS-HUMAN without its colon is not the marker'
plan slice-102 beta yes
out="$(run "$EPIC")"
expect "bold, checkbox and numbered NEEDS-HUMAN lines count; one without a colon does not" "$(nh_of "$out" slice-101)" "5"

# 11. NEEDS-HUMAN on an approved plan is reported but not summed
reset; epic "$APPROVE_BOTH"; plan slice-101 alpha yes 'NEEDS-HUMAN: left over'; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "an approved plan's NEEDS-HUMAN is not summed" "$(nh_of "$out" slice-101)/$(val "$out" NEEDS_HUMAN_COUNT)" "1/0"

# 12. Planned-by only counts in the frontmatter; another value is doubt → pipeline
reset; epic '(no autopilot run yet)'
plan slice-101 alpha no '> Planned-by: autopilot'
plan slice-102 beta manual
out="$(run "$EPIC")"
expect "Planned-by in the body is not the marker; another value still awaits" "$(gate_of "$out" slice-101)/$(gate_of "$out" slice-102)" "hand/awaiting"

# 13. landed and unlinked entries have no plan and are not reported
reset
epic '(no autopilot run yet)' '- [x] slice-100 — done — landed entry
- [ ] slice-101 — alpha — first entry
- [ ] gamma — unplanned entry'
printf '# Slice 100\n' > "$P/.claude/project/slices/slice-100-done.md"
plan slice-101 alpha yes
out="$(run "$EPIC")"
expect "only entries with a plan are reported" "$(printf '%s\n' "$out" | grep -c '^PLAN ')" "1"
expect "PLAN_COUNT counts them" "$(val "$out" PLAN_COUNT)" "1"

# 13b. orphans — active plans no entry of any epic links (review R1-1)
reset
epic '(no autopilot run yet)' '- [ ] slice-101 — alpha — first entry
- [ ] beta — second entry, unplanned'
plan slice-101 alpha yes
plan slice-102 beta-by-hand no
plan slice-103 beta-esc yes
plan slice-104 other no
printf '# Epic 010\n\n> Epic-ID: epic-010\n\n## Slice Decomposition\n\n- [ ] slice-104 — other — another epic\n' > "$P/.claude/plans/epic-010-other.md"
out="$(run "$EPIC")"
expect "an unlinked hand plan and an unlinked pipeline plan are orphans; linked ones (this epic or another) are not" \
  "$(printf '%s\n' "$out" | grep '^ORPHAN ' | sed -n 's/^ORPHAN SLICE=\([^ ]*\) PIPELINE=\([^ ]*\).*/\1:\2/p' | tr '\n' ' ')" "slice-102:no slice-103:yes "
expect "ORPHAN_COUNT counts them" "$(val "$out" ORPHAN_COUNT)" "2"
reset; epic "$APPROVE_BOTH"; plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "no orphan: ORPHAN_COUNT=0" "$(val "$out" ORPHAN_COUNT)" "0"

# --- ## Plan Review — the plan-architect's rounds (slice-055) -------------------------------
# epic_r <review-body> — a two-entry epic with both plans, whose ## Plan Review holds the body
epic_r() {
  reset; epic '(no autopilot run yet)'; plan slice-101 alpha yes; plan slice-102 beta yes
  local body="$1"
  python3 - "$P/$EPIC" "$body" <<'PY'
import sys
p, body = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("## Autopilot Log", "## Plan Review\n\n" + body + "\n\n## Autopilot Log", 1)
open(p, "w").write(s)
PY
}
arch() { printf '%s\n' "$1" | grep "^ARCH FINDING=$2 " | sed -n "s/.* $3=\([^ ]*\).*/\1/p"; }
R1='### Round 1 — 2026-10-01T10:00:00Z (first)'
F_REV='- P1-1 · slice-101, slice-102 · overlap · revise · both change the greeting line · open'
F_NOTE='- P1-2 · slice-102 · sizing · note · large but buildable · resolved in round 2'

# A1. no section
reset; epic '(no autopilot run yet)'; plan slice-101 alpha yes; plan slice-102 beta yes
out="$(run "$EPIC")"
expect "no ## Plan Review: no rounds, 2 autonomous rounds left, nothing open" \
  "$(val "$out" ARCH_ROUNDS)/$(val "$out" ARCH_NEXT_ROUND)/$(val "$out" ARCH_LAST_KIND)/$(val "$out" ARCH_AUTO_LEFT)/$(val "$out" ARCH_OPEN_COUNT)" "0/1/-/2/0"

# A2. one first round, one open revise finding and one resolved note
epic_r "$R1
$F_REV
$F_NOTE
- note · P0-9 was never raised — a note line is no finding"
out="$(run "$EPIC")"
expect "a first round: rounds, kind, findings and their state" \
  "$(val "$out" ARCH_ROUNDS)/$(val "$out" ARCH_LAST_KIND)/$(val "$out" ARCH_OPEN_COUNT)/$(arch "$out" P1-1 OPEN)/$(arch "$out" P1-2 OPEN)" "1/first/1/yes/no"
expect "a finding carries its route, kind and slices" \
  "$(arch "$out" P1-1 ROUTE)/$(arch "$out" P1-1 KIND)/$(arch "$out" P1-1 SLICES)" "revise/overlap/slice-101,slice-102"
expect "a note line is no finding" "$(printf '%s\n' "$out" | grep -c '^ARCH FINDING=')" "2"
expect "after the first round 2 autonomous rounds are left" "$(val "$out" ARCH_AUTO_LEFT)" "2"

# A3. the autonomous-round budget per planning pass
a3() { # <kinds...> -> AUTO_LEFT/LAST_KIND
  local body="" n=0 k
  for k in "$@"; do n=$((n + 1)); body="$body### Round $n — 2026-10-01T10:0$n:00Z ($k)
"; done
  epic_r "$body"; out="$(run "$EPIC")"; echo "$(val "$out" ARCH_AUTO_LEFT)/$(val "$out" ARCH_LAST_KIND)"
}
expect "first + auto: 1 left" "$(a3 first auto)" "1/auto"
expect "first + auto + auto: exhausted" "$(a3 first auto auto)" "0/auto"
expect "a review-only round spends nothing, and the budget stays spent" "$(a3 first auto auto review-only)" "0/review-only"
expect "a new first round opens a new planning pass" "$(a3 first auto auto review-only first)" "2/first"
expect "review-only rounds alone spend nothing" "$(a3 first review-only review-only)" "2/review-only"

# A4. malformed finding lines count open and stop autonomy (doubt)
for bad_line in \
  '- P1-1 · slice-101 · overlap · revise · no resolution field' \
  '- P1-1 · slice-101 · naming · revise · unknown kind · open' \
  '- P1-1 · slice-101 · overlap · fix · unknown route · open' \
  '- P1-1 · slice-101 · overlap · revise · resolution garbage · done' \
  '- P2-1 · slice-101 · overlap · revise · ID of another round · open' \
  '- P1-1 · sl101 · overlap · revise · not a slice-ID · open' \
  '- **P1-1** · slice-101 · overlap · revise · a bold ID · open' \
  '* P1-1 · slice-101 · overlap · revise · another bullet · open' \
  '-  P1-1 · slice-101 · overlap · revise · two spaces after the bullet · open' \
  '1. P1-1 · slice-101 · overlap · revise · a numbered item · open' \
  '- `P1-1` · slice-101 · overlap · revise · a backticked ID · open' \
  '- [ ] P1-1 · slice-101 · overlap · revise · a checkbox · open' \
  '> - P1-1 · slice-101 · overlap · revise · a blockquote · open' \
  'P1-1 · slice-101 · overlap · revise · no bullet at all · open'; do
  epic_r "$R1
$bad_line"
  out="$(run "$EPIC")"
  expect "malformed finding line counts open, autonomy 0: ${bad_line:0:50}" \
    "$(val "$out" ARCH_OPEN_COUNT)/$(val "$out" ARCH_AUTO_LEFT)/$(printf '%s\n' "$out" | grep -c '^ARCH_MALFORMED ')" "1/0/1"
done

# A5. a round heading out of position is malformed
epic_r '### Round 2 — 2026-10-01T10:00:00Z (first)'
out="$(run "$EPIC")"
expect "a heading numbered off its position: malformed, autonomy 0" \
  "$(val "$out" ARCH_AUTO_LEFT)/$(printf '%s\n' "$out" | grep -c '^ARCH_MALFORMED ')" "0/1"
epic_r '### Round 1 — 2026-10-01T10:00:00Z (sideways)'
out="$(run "$EPIC")"
expect "an unknown round kind: malformed, autonomy 0" \
  "$(val "$out" ARCH_AUTO_LEFT)/$(printf '%s\n' "$out" | grep -c '^ARCH_MALFORMED ')" "0/1"
epic_r "$R1
#### a sub-heading is no round
$F_REV"
out="$(run "$EPIC")"
expect "a #### sub-heading is no round heading" \
  "$(val "$out" ARCH_ROUNDS)/$(arch "$out" P1-1 OPEN)/$(printf '%s\n' "$out" | grep -c '^ARCH_MALFORMED ')" "1/yes/0"

# A5b. a finding the human approved open at the gate is accepted, not open
epic_r "$R1
- P1-1 · slice-101, slice-102 · overlap · note · both change the greeting line · accepted at gate
$F_NOTE"
out="$(run "$EPIC")"
expect "'accepted at gate' is no open finding and reads well-formed" \
  "$(arch "$out" P1-1 OPEN)/$(val "$out" ARCH_OPEN_COUNT)/$(val "$out" ARCH_AUTO_LEFT)/$(printf '%s\n' "$out" | grep -c '^ARCH_MALFORMED ')" "no/0/2/0"

# A6. fenced lines and lines outside the section do not count
epic_r "$R1
\`\`\`
$F_REV
\`\`\`"
printf '%s\n' "$F_REV" >> "$P/$EPIC"
out="$(run "$EPIC")"
expect "a fenced finding and one below another heading count for nothing" "$(val "$out" ARCH_OPEN_COUNT)/$(printf '%s\n' "$out" | grep -c '^ARCH FINDING=')" "0/0"

# A7. CRLF
epic_r "$R1
$F_REV"
sed -i.bak 's/$/\r/' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run "$EPIC")"
expect "a CRLF plan review still reads" "$(val "$out" ARCH_ROUNDS)/$(arch "$out" P1-1 OPEN)" "1/yes"

# 14. errors
reset
out="$(run)"; rc=$?
expect "no argument: exit 2" "$rc" "2"
out="$(run .claude/plans/epic-404-nope.md)"; rc=$?
expect "unreadable epic plan: exit 4 + ERROR" "$rc/$(val "$out" ERROR | cut -d: -f1)" "4/epic_plan_unreadable"
reset; epic '(no autopilot run yet)'; sed -i.bak '/Epic-ID/d' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run "$EPIC")"; rc=$?
expect "no Epic-ID: exit 4 + ERROR" "$rc/$(val "$out" ERROR | cut -d: -f1)" "4/no_epic_id"

echo "PINS:"
# The helper's approval-line format is what execute.md writes, and the markers are what plan.md defines.
grep -q 'plan-gate-state.sh' "$EXECUTE" && ok "execute.md calls plan-gate-state.sh" || bad "execute.md does not call plan-gate-state.sh"
grep -q 'plan gate approved: ' "$EXECUTE" && ok "execute.md writes the 'plan gate approved: ' log line" || bad "execute.md never writes 'plan gate approved: ' — the helper would never see an approval"
# A string only ap's link step carries — A6's rejection messages name `link` too (review R1-7).
grep -qF 'link "<epic-plan>" "<entry>" slice-<NNN>' "$EXECUTE" && ok "execute.md's ap links each planned entry through epic-entry-link.sh" || bad "execute.md's ap no longer links planned entries through epic-entry-link.sh"
grep -q 'slice-planner' "$EXECUTE" && ok "execute.md spawns slice-planner" || bad "execute.md never spawns slice-planner"
for needle in 'NEEDS-HUMAN: ' '> Planned-by: autopilot'; do
  grep -qF -- "$needle" "$PLAN_CMD" && ok "plan.md's Subagent Mode defines '$needle'" || bad "plan.md no longer defines '$needle' — the helper reads it"
done
for needle in 'plan-architect' '## Plan Review' 'review-only'; do
  grep -qF -- "$needle" "$EXECUTE" && ok "execute.md's ap names '$needle'" || bad "execute.md's ap no longer names '$needle'"
done
grep -q '^## Plan Review' "$TEMPLATE" && ok "the epic template carries ## Plan Review" || bad "the epic template has no ## Plan Review section"
# The record's format is the helper header's alone (slice-055 review R1-3): the template and 4b point at it.
grep -q 'plan-gate-state.sh' "$TEMPLATE" && ok "the epic template points at plan-gate-state.sh for ## Plan Review" || bad "the epic template no longer points at plan-gate-state.sh"
for f in "$TEMPLATE" "$EXECUTE"; do
  grep -qF -- '<overlap|contract|order|sizing> · <revise|note>' "$f" && bad "$(basename "$f") repeats the finding-line format" || ok "$(basename "$f") does not repeat the finding-line format"
  grep -qF -- '### Round <n> — <' "$f" && bad "$(basename "$f") repeats the round-heading format" || ok "$(basename "$f") does not repeat the round-heading format"
done
# Only plans that still await the gate are revised autonomously (R1-1); an architect note never answers for the human (R1-2).
grep -qF -- 'only a `GATE=awaiting` plan is revised autonomously' "$EXECUTE" && ok "execute.md's 4b revises awaiting plans only" || bad "execute.md's 4b no longer limits autonomous revision to GATE=awaiting plans"
grep -qF -- 'never two planners on one plan' "$EXECUTE" && ok "execute.md's 4b sends one planner per plan, all its notes" || bad "execute.md's 4b may send two planners to one plan (R2-3)"
grep -qF -- 'is not awaiting this gate' "$EXECUTE" && ok "execute.md's [R] refuses a plan that does not await the gate" || bad "execute.md's [R] could revise an approved plan unseen (R2-4)"
grep -qF -- 'accepted at gate' "$EXECUTE" && ok "execute.md's [Y] writes 'accepted at gate'" || bad "execute.md never writes 'accepted at gate' — an approved-open finding would stay open forever"
grep -qF -- 'never replaces or removes a `NEEDS-HUMAN:` line' "$PLAN_CMD" && ok "plan.md: an architect note never answers a NEEDS-HUMAN question" || bad "plan.md lets an architect note answer a NEEDS-HUMAN question"
grep -q "commands/plan.md" "$AGENT" && ok "slice-planner follows commands/plan.md" || bad "slice-planner no longer points at commands/plan.md"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
