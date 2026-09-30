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
grep -q "commands/plan.md" "$AGENT" && ok "slice-planner follows commands/plan.md" || bad "slice-planner no longer points at commands/plan.md"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
