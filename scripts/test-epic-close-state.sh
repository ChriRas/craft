#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-epic-close-state.sh — self-contained tests for epic-close-state.sh (slice-061, roadmap B24, D37):
# whether an autopilot epic can be closed by /craft:commit now — merged into the trunk on the human's
# a5 [Y], every decomposition entry landed — derived from git and the epic plan, never stored.
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-epic-close-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/epic-close-state.sh"
for f in "$HELPER" "$SCRIPT_DIR/epic-entry-link.sh" "$SCRIPT_DIR/example-regions.sh"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
EPIC=".claude/plans/epic-900-demo.md"
BR="epic-900-demo"

g() { git -C "$P" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# reset — a fresh repo on main with one commit; the plans are untracked, as in a project that ignores them
reset() {
  rm -rf "$P"
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
  git init -q -b main "$P"
  echo base > "$P/base.txt"; g add base.txt; g commit -m base
}

# epic_branch — the epic branch with one own commit, back on main
epic_branch() { g checkout -b "$BR"; echo work > "$P/work.txt"; g add work.txt; g commit -m work; g checkout main; }
# merge — what a5 [Y] direct does
merge() { g merge --no-ff "$BR" -m "Merge epic-900: Demo"; }

# archives — both slices landed (no plan, one archive each)
archives() {
  printf '# Slice 901\n\n## What\n\na.\n' > "$P/.claude/project/slices/slice-901-alpha.md"
  printf '# Slice 902\n\n## What\n\nb.\n' > "$P/.claude/project/slices/slice-902-beta.md"
}

# epic <log-lines> [<frontmatter>] [<path>] — the epic plan; <log-lines> is the Autopilot Log body
epic() {
  local log="$1" fm="${2-> Epic-ID: epic-900
> Epic-Slug: demo}" path="${3-$EPIC}"
  printf '# Epic 900 — Demo\n\n> Status: planning\n%s\n\n## Vision\n\nv\n\n## Slice Decomposition\n\n- [x] slice-901 — alpha — first\n- [x] slice-902 — beta — second\n\n## Decisions Made During This Epic\n\n- **A** — kept\n\n## Autopilot Log\n\n%s\n\n## Recap Draft\n\n(not yet recorded)\n' \
    "$fm" "$log" > "$P/$path"
}

L_RUN='- 2026-10-06T10:00:00Z · ▶ · epic-900 · run started'
L_ASK='- 2026-10-06T11:00:00Z · ▶ · epic-900 · sign-off asked'
L_MERGED='- 2026-10-06T11:05:00Z · ■ · epic-900 · merged into main'
L_NO='- 2026-10-06T11:05:00Z · ■ · epic-900 · complete, not merged'
L_PR='- 2026-10-06T11:05:00Z · ■ · epic-900 · PR #12 opened'
L_OTHER='- 2026-10-06T11:05:00Z · ■ · epic-900 · merged into develop'
SIGNED="$L_RUN
$L_ASK
$L_MERGED"

OUT=""; RC=0
run() { OUT="$(cd "$P" && bash "$HELPER" "$@" 2>&1)"; RC=$?; }
line_for() { grep -E "^EPIC=[^ ]+ PLAN=$1 " <<<"$OUT"; }

# expect <name> <plan> <state> <branch-state> <reason>
expect() {
  local l
  l="$(line_for "$2")"
  if [[ $RC -eq 0 && "$l" == *" STATE=$3 "* && "$l" == *" BRANCH_STATE=$4 "* && "$l" == *" REASON=$5" ]]; then ok "$1"
  else bad "$1 — rc=$RC, want STATE=$3 BRANCH_STATE=$4 REASON=$5, got: ${l:-<no line>} | $(tr '\n' '|' <<<"$OUT")"; fi
}
expect_error() { # name rc reason
  if [[ $RC -eq $2 && "$OUT" == *"ERROR=$3"* && "$OUT" != *"STATE="* ]]; then ok "$1"
  else bad "$1 — want rc=$2 ERROR=$3, got rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
}
expect_counts() { # name epics closable
  if [[ "$OUT" == *$'\n'"EPIC_COUNT=$2"$'\n'"CLOSABLE_COUNT=$3"* || "$OUT" == "EPIC_COUNT=$2"$'\n'"CLOSABLE_COUNT=$3"* ]]; then ok "$1"
  else bad "$1 — want EPIC_COUNT=$2 CLOSABLE_COUNT=$3, got: $(tr '\n' '|' <<<"$OUT")"; fi
}

echo "epic-close-state.sh — closable"
reset; epic_branch; merge; archives; epic "$SIGNED"
run --trunk main "$EPIC"
expect "merged on a5 [Y], every entry landed" "$EPIC" closable merged -
expect_counts "counts for one closable epic" 1 1
if grep -qE "^EPIC=epic-900 PLAN=$EPIC STATE=closable BRANCH=$BR BRANCH_STATE=merged REASON=-$" <<<"$OUT"; then
  ok "the line names the epic branch, fields in order"; else bad "line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
g branch -d "$BR"
run --trunk main "$EPIC"
expect "branch already deleted, its merge on the trunk" "$EPIC" closable deleted -
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
$L_NO
$L_ASK
$L_MERGED"
run --trunk main "$EPIC"
expect "a later [Y] after an earlier [N] — the last answer counts" "$EPIC" closable merged -
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -pi -e 's/\n/\r\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a CRLF epic plan" "$EPIC" closable merged -

echo "epic-close-state.sh — not an autopilot epic, not signed off, not merged"
reset; epic_branch; merge; archives; epic "(no autopilot run yet)"
run --trunk main "$EPIC"
expect "no log line: not an autopilot epic" "$EPIC" not-autopilot - no_autopilot_log
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -0pi -e 's/## Autopilot Log\n\n.*?\n\n## Recap/## Recap/s' "$P/$EPIC"
run --trunk main "$EPIC"
expect "no ## Autopilot Log section" "$EPIC" not-autopilot - no_autopilot_log
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK"
run --trunk main "$EPIC"
expect "sign-off asked, never answered" "$EPIC" not-signed-off - no_answer
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_NO"
run --trunk main "$EPIC"
expect "a5 answered [N]" "$EPIC" not-merged - not_merged
reset; epic_branch; archives; epic "$L_RUN
- 2026-10-06T10:10:00Z · ■ · epic-900 · plan gate: stopped, plans kept"
run --trunk main "$EPIC"
expect "a run stopped at the plan gate's [N] is no a5 answer" "$EPIC" not-signed-off - run_stopped
reset; epic_branch; archives; epic "$L_RUN
- 2026-10-06T10:10:00Z · ■ · epic-900 · orphan plans: stopped — slice-903"
run --trunk main "$EPIC"
expect "a run stopped at the orphan question's [N] is no a5 answer" "$EPIC" not-signed-off - run_stopped
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_PR"
run --trunk main "$EPIC"
expect "a5 opened a PR: the PR path is not this mode's" "$EPIC" pr-path - pr_opened
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_OTHER"
run --trunk main "$EPIC"
expect "merged into another trunk" "$EPIC" not-merged - merged_into:develop
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
- 2026-10-06T11:05:00Z · ■ · epic-901 · merged into main"
run --trunk main "$EPIC"
expect "a ■ line of another epic does not count" "$EPIC" not-signed-off - no_answer
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
\`\`\`
$L_MERGED
\`\`\`"
run --trunk main "$EPIC"
expect "a ■ line inside a fence does not count" "$EPIC" not-signed-off - no_answer
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK"
perl -0pi -e 's/\n\nv\n/\n\nv\n\n- 2026-10-06T11:05:00Z · ■ · epic-900 · merged into main\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a ■ line outside ## Autopilot Log does not count" "$EPIC" not-signed-off - no_answer

echo "epic-close-state.sh — entries"
reset; epic_branch; merge; archives; epic "$SIGNED"
rm -f "$P/.claude/project/slices/slice-902-beta.md"
printf '# Slice 902\n\n> Status: reviewing\n> Slice-ID: slice-902\n' > "$P/.claude/plans/slice-902-beta.md"
run --trunk main "$EPIC"
expect "a slice still open" "$EPIC" entries-open - not_landed:slice-902:plan
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -pi -e 's/^- \[x\] slice-902 — beta/- [ ] beta/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "an entry never planned" "$EPIC" entries-open - not_landed:-:unlinked

echo "epic-close-state.sh — the epic branch"
reset; g checkout -b "$BR"; g checkout main; archives; epic "$SIGNED"
run --trunk main "$EPIC"
expect "the ancestor trap: a branch without own commits is not merged" "$EPIC" branch-unmerged unmerged branch_unmerged
reset; epic_branch; merge; archives; epic "$SIGNED"
g checkout "$BR"; echo more > "$P/more.txt"; g add more.txt; g commit -m more; g checkout main
run --trunk main "$EPIC"
expect "commits on the epic branch after the merge" "$EPIC" branch-unmerged unmerged branch_unmerged
reset; epic_branch; archives; epic "$SIGNED"
g branch -D "$BR"
run --trunk main "$EPIC"
expect "branch gone and no merge commit on the trunk" "$EPIC" branch-unmerged missing branch_missing

echo "epic-close-state.sh — scanning every epic plan"
reset; epic_branch; merge; archives; epic "$SIGNED"
epic "$L_RUN" "> Epic-ID: epic-901
> Epic-Slug: other" ".claude/plans/epic-901-other.md"
run --trunk main
expect "scan: the closable epic" "$EPIC" closable merged -
expect "scan: the open epic" ".claude/plans/epic-901-other.md" not-signed-off - no_answer
expect_counts "scan: counts" 2 1
reset
run --trunk main
if [[ $RC -eq 0 && "$OUT" == $'EPIC_COUNT=0\nCLOSABLE_COUNT=0' ]]; then ok "scan: no epic plan"
else bad "scan: no epic plan — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi

echo "epic-close-state.sh — malformed plans and errors"
reset; epic_branch; merge; archives; epic "$SIGNED" "> Epic-Slug: demo"
run --trunk main "$EPIC"
if [[ $RC -eq 0 && "$OUT" == *"EPIC=- PLAN=$EPIC STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_frontmatter:Epic-ID"* ]]; then
  ok "no Epic-ID: malformed, never closable"; else bad "no Epic-ID — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset; epic_branch; merge; archives; epic "$SIGNED" "> Epic-ID: epic-900"
run --trunk main "$EPIC"
if [[ $RC -eq 0 && "$OUT" == *"EPIC=epic-900 PLAN=$EPIC STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_frontmatter:Epic-Slug"* ]]; then
  ok "no Epic-Slug: malformed"; else bad "no Epic-Slug — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset
run --trunk main ".claude/plans/epic-999-none.md"
if [[ $RC -eq 0 && "$OUT" == *"PLAN=.claude/plans/epic-999-none.md STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_plan_unreadable"* ]]; then
  ok "a named plan that does not exist: malformed"; else bad "missing plan — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset
run "$EPIC"
expect_error "no --trunk" 2 usage
run --trunk
expect_error "--trunk without a value" 2 usage
reset; epic_branch; merge; archives; epic "$SIGNED"
run --trunk trunk "$EPIC"
expect_error "a trunk that does not exist" 5 trunk_missing:trunk
rm -rf "$P/.git"
run --trunk main "$EPIC"
expect_error "not a git repository" 5 not_a_git_repo

echo "epic-close-state.sh — read-only"
reset; epic_branch; merge; archives; epic "$SIGNED"
before="$(cd "$P" && git status --porcelain --untracked-files=all; git for-each-ref; find . -path ./.git -prune -o -type f -print | sort | xargs cksum)"
run --trunk main "$EPIC"
after="$(cd "$P" && git status --porcelain --untracked-files=all; git for-each-ref; find . -path ./.git -prune -o -type f -print | sort | xargs cksum)"
[[ "$before" == "$after" ]] && ok "writes nothing" || bad "the helper changed the fixture"

echo "pinned sites"
COMMIT_MD="$REPO/commands/commit.md"
EXECUTE_MD="$REPO/commands/execute.md"
grep -qF 'scripts/epic-close-state.sh' "$COMMIT_MD" && ok "commit.md calls epic-close-state.sh" || bad "commit.md does not call epic-close-state.sh"
for s in closable not-autopilot not-signed-off not-merged pr-path entries-open branch-unmerged malformed; do
  grep -qF "STATE=$s" "$COMMIT_MD" && ok "commit.md handles STATE=$s" || bad "commit.md does not handle STATE=$s"
done
grep -qF 'Autopilot-epic-close' "$COMMIT_MD" && ok "commit.md names the Autopilot-epic-close mode" || bad "commit.md lacks the Autopilot-epic-close mode"
a5="$(awk '/^### a5 /{f=1} f&&/^## /{exit} f' "$EXECUTE_MD")"
grep -qF 'Recommended next: /craft:commit' <<<"$a5" && ok "execute.md a5 hands over to /craft:commit" || bad "execute.md a5 lacks 'Recommended next: /craft:commit'"
if grep -qF 'closing an epic is not part of an autopilot run' "$EXECUTE_MD"; then bad "execute.md still says closing is not part of the run"
else ok "execute.md no longer says closing is not part of the run"; fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
