#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-epic-close-state.sh — self-contained tests for epic-close-state.sh (slice-061 / slice-062, B24 / B26, D37 / D38):
# whether an epic can be closed by /craft:commit now — an autopilot epic merged into the trunk on the human's
# a5 [Y], or a sequential one with no unmerged epic branch; every decomposition entry landed — derived from
# git and the epic plan, never stored.
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-epic-close-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail
# the helper prefers CLAUDE_PROJECT_DIR over the cwd; an inherited one (a context-mode sandbox, a hook) points every
# fixture call at the wrong project — slice-063's verify-run went 34 red that way. Each case runs from its fixture.
unset CLAUDE_PROJECT_DIR

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

# expect <name> <plan> <kind> <state> <branch-state> <reason>
expect() {
  local l
  l="$(line_for "$2")"
  if [[ $RC -eq 0 && "$l" == *" KIND=$3 "* && "$l" == *" STATE=$4 "* && "$l" == *" BRANCH_STATE=$5 "* && "$l" == *" REASON=$6" ]]; then ok "$1"
  else bad "$1 — rc=$RC, want KIND=$3 STATE=$4 BRANCH_STATE=$5 REASON=$6, got: ${l:-<no line>} | $(tr '\n' '|' <<<"$OUT")"; fi
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
expect "merged on a5 [Y], every entry landed" "$EPIC" autopilot closable merged -
expect_counts "counts for one closable epic" 1 1
if grep -qE "^EPIC=epic-900 PLAN=$EPIC KIND=autopilot STATE=closable BRANCH=$BR BRANCH_STATE=merged REASON=-$" <<<"$OUT"; then
  ok "the line names the epic branch, fields in order"; else bad "line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
g branch -d "$BR"
run --trunk main "$EPIC"
expect "branch already deleted, its merge on the trunk" "$EPIC" autopilot closable deleted -
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
$L_NO
$L_ASK
$L_MERGED"
run --trunk main "$EPIC"
expect "a later [Y] after an earlier [N] — the last answer counts" "$EPIC" autopilot closable merged -
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -pi -e 's/\n/\r\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a CRLF epic plan" "$EPIC" autopilot closable merged -

echo "epic-close-state.sh — an epic without an autopilot log (sequential, or worked by hand)"
reset; archives; epic "(no autopilot run yet)"
run --trunk main "$EPIC"
expect "every entry landed, no epic branch: closable" "$EPIC" sequential closable none -
if grep -qE "^EPIC=epic-900 PLAN=$EPIC KIND=sequential STATE=closable BRANCH=$BR BRANCH_STATE=none REASON=-$" <<<"$OUT"; then
  ok "a sequential line names the branch it looked for"; else bad "sequential line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
reset; archives; epic "$SIGNED"
perl -0pi -e 's/## Autopilot Log\n\n.*?\n\n## Recap/## Recap/s' "$P/$EPIC"
run --trunk main "$EPIC"
expect "no ## Autopilot Log section at all" "$EPIC" sequential closable none -
reset; epic_branch; merge; archives; epic "(no autopilot run yet)"
run --trunk main "$EPIC"
expect "its epic branch exists and is merged" "$EPIC" sequential closable merged -
reset; epic_branch; archives; epic "(no autopilot run yet)"
run --trunk main "$EPIC"
expect "its epic branch exists unmerged" "$EPIC" sequential branch-unmerged unmerged branch_unmerged
reset; g checkout -b "$BR"; g checkout main; archives; epic "(no autopilot run yet)"
run --trunk main "$EPIC"
expect "the ancestor trap holds without a log too" "$EPIC" sequential branch-unmerged unmerged branch_unmerged
reset; archives; epic "(no autopilot run yet)"
rm -f "$P/.claude/project/slices/slice-902-beta.md"
printf '# Slice 902\n\n> Status: implementing\n> Slice-ID: slice-902\n' > "$P/.claude/plans/slice-902-beta.md"
run --trunk main "$EPIC"
expect "a slice still open" "$EPIC" sequential entries-open - not_landed:slice-902:plan
reset; archives; epic "(no autopilot run yet)"
perl -0pi -e 's/- \[x\] slice-901 — alpha — first\n- \[x\] slice-902 — beta — second\n//' "$P/$EPIC"
run --trunk main "$EPIC"
expect "an epic with no entries yet" "$EPIC" sequential entries-open - no_entries

echo "epic-close-state.sh — an autopilot epic not signed off, not merged"
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK"
run --trunk main "$EPIC"
expect "sign-off asked, never answered" "$EPIC" autopilot not-signed-off - no_answer
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_NO"
run --trunk main "$EPIC"
expect "a5 answered [N]" "$EPIC" autopilot not-merged - not_merged
reset; epic_branch; archives; epic "$L_RUN
- 2026-10-06T10:10:00Z · ■ · epic-900 · plan gate: stopped, plans kept"
run --trunk main "$EPIC"
expect "a run stopped at the plan gate's [N] is no a5 answer" "$EPIC" autopilot not-signed-off - run_stopped
reset; epic_branch; archives; epic "$L_RUN
- 2026-10-06T10:10:00Z · ■ · epic-900 · orphan plans: stopped — slice-903"
run --trunk main "$EPIC"
expect "a run stopped at the orphan question's [N] is no a5 answer" "$EPIC" autopilot not-signed-off - run_stopped
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_PR"
run --trunk main "$EPIC"
expect "a5 opened a PR: the PR path is not this mode's" "$EPIC" autopilot pr-path - pr_opened
reset; epic_branch; archives; epic "$L_RUN
$L_ASK
$L_OTHER"
run --trunk main "$EPIC"
expect "merged into another trunk" "$EPIC" autopilot not-merged - merged_into:develop
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
- 2026-10-06T11:05:00Z · ■ · epic-901 · merged into main"
run --trunk main "$EPIC"
expect "a ■ line of another epic does not count" "$EPIC" autopilot not-signed-off - no_answer
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK
\`\`\`
$L_MERGED
\`\`\`"
run --trunk main "$EPIC"
expect "a ■ line inside a fence does not count" "$EPIC" autopilot not-signed-off - no_answer
reset; epic_branch; merge; archives; epic "$L_RUN
$L_ASK"
perl -0pi -e 's/\n\nv\n/\n\nv\n\n- 2026-10-06T11:05:00Z · ■ · epic-900 · merged into main\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a ■ line outside ## Autopilot Log does not count" "$EPIC" autopilot not-signed-off - no_answer

echo "epic-close-state.sh — the PR path (slice-068, B25)"
# merge_pr <N> — what GitHub's merge button writes on the trunk (the branch tip becomes a non-first parent)
merge_pr() { g merge --no-ff "$BR" -m "Merge pull request #$1 from owner/$BR"; }
PRLOG="$L_RUN
$L_ASK
$L_PR"
reset; epic_branch; merge_pr 12; archives; epic "$PRLOG"
run --trunk main "$EPIC"
expect "PR #12 merged, the trunk synced: closable" "$EPIC" autopilot closable merged -
expect_counts "counts: a merged PR-path epic is closable" 1 1
if grep -qE "^EPIC=epic-900 PLAN=$EPIC KIND=autopilot STATE=closable BRANCH=$BR BRANCH_STATE=merged REASON=-$" <<<"$OUT"; then
  ok "the PR-path line names the epic branch, fields in order"; else bad "PR-path line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
reset; epic_branch; archives; epic "$PRLOG"
run --trunk main "$EPIC"
expect "PR #12 still open (the branch unmerged): pr-path" "$EPIC" autopilot pr-path - pr_opened
expect_counts "counts: an open PR-path epic is not closable" 1 0
if grep -qE "^EPIC=epic-900 PLAN=$EPIC KIND=autopilot STATE=pr-path BRANCH=$BR BRANCH_STATE=- REASON=pr_opened$" <<<"$OUT"; then
  ok "the pr-path line names the branch the PR carries"; else bad "pr-path line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
reset; epic_branch; merge_pr 12; archives; epic "$PRLOG"
g checkout "$BR"; echo more > "$P/more.txt"; g add more.txt; g commit -m more; g checkout main
run --trunk main "$EPIC"
expect "commits on the epic branch after the PR merged: branch-unmerged, as on the direct path" "$EPIC" autopilot branch-unmerged unmerged branch_unmerged
reset; epic_branch; merge_pr 12; archives; epic "$PRLOG"
g branch -d "$BR"
run --trunk main "$EPIC"
expect "PR merged and the branch gone: its merge commit names PR #12" "$EPIC" autopilot closable deleted -
reset; epic_branch; g checkout "$BR"; echo more > "$P/more.txt"; g add more.txt; g commit -m more; g checkout main
merge_pr 12; g branch -f "$BR" "$BR~1"; archives; epic "$PRLOG"
run --trunk main "$EPIC"
expect "PR merged, the local branch lags the PR's head: branch-unmerged, not a pr-path loop" "$EPIC" autopilot branch-unmerged unmerged branch_unmerged
reset; epic_branch; g merge --squash "$BR"; g commit -m "Demo (#12)"; archives; epic "$PRLOG"
run --trunk main "$EPIC"
expect "PR squash-merged: no merge commit proves it, pr-path (the known limit)" "$EPIC" autopilot pr-path - pr_opened
# older merges with ~20 KB subjects (well past a pipe buffer), the PR's merge the newest line of `git log --merges`
reset; longsubj="$(head -c 20000 /dev/zero | tr '\0' x)"
for i in 1 2 3 4 5 6 7 8; do g checkout -b "side$i"; echo "$i" > "$P/s$i.txt"; g add "s$i.txt"; g commit -m "s$i"; g checkout main; g merge --no-ff "side$i" -m "Merge side$i $longsubj"; done
epic_branch; archives; epic "$PRLOG"; merge_pr 12; g branch -d "$BR"
run --trunk main "$EPIC"
expect "branch gone, a long merge history: grep -q's early exit must not read as no match" "$EPIC" autopilot closable deleted -
reset; epic_branch; merge_pr 99; archives; epic "$PRLOG"
g branch -d "$BR"
run --trunk main "$EPIC"
expect "branch gone, only another PR's merge on the trunk: pr-path" "$EPIC" autopilot pr-path - pr_opened
reset; archives; epic "$PRLOG"
run --trunk main "$EPIC"
expect "branch gone, nothing merged: pr-path" "$EPIC" autopilot pr-path - pr_opened
reset; epic_branch; merge_pr 12; archives; epic "$PRLOG"
rm -f "$P/.claude/project/slices/slice-902-beta.md"
printf '# Slice 902\n\n> Status: reviewing\n> Slice-ID: slice-902\n' > "$P/.claude/plans/slice-902-beta.md"
run --trunk main "$EPIC"
expect "PR merged, but a slice still open: entries-open" "$EPIC" autopilot entries-open - not_landed:slice-902:plan

echo "epic-close-state.sh — closing: the close PR is open"
await() { perl -pi -e 's/^> Status: planning$/> Status: awaiting-approval/' "$P/$EPIC"; }
reset; epic_branch; merge; archives; epic "$SIGNED"; await
run --trunk main "$EPIC"
expect "an autopilot epic plan at awaiting-approval" "$EPIC" autopilot closing - awaiting_approval
expect_counts "counts: a closing epic is not closable" 1 0
if grep -qE "^EPIC=epic-900 PLAN=$EPIC KIND=autopilot STATE=closing BRANCH=- BRANCH_STATE=- REASON=awaiting_approval$" <<<"$OUT"; then
  ok "the closing line, fields in order"; else bad "closing line format — got: $(tr '\n' '|' <<<"$OUT")"; fi
reset; archives; epic "(no autopilot run yet)"; await
run --trunk main "$EPIC"
expect "a sequential epic plan at awaiting-approval" "$EPIC" sequential closing - awaiting_approval
reset; epic_branch; archives; epic "$PRLOG"; await
run --trunk main "$EPIC"
expect "a PR-path epic at awaiting-approval (its branch unmerged)" "$EPIC" autopilot closing - awaiting_approval
reset; epic_branch; archives; epic "$L_RUN"; await
run --trunk main "$EPIC"
expect "closing is judged before a5's answer" "$EPIC" autopilot closing - awaiting_approval
reset; archives; epic "(no autopilot run yet)" "> Epic-ID: epic-900"; await
run --trunk main "$EPIC"
if [[ $RC -eq 0 && "$OUT" == *"STATE=malformed"*"REASON=epic_frontmatter:Epic-Slug"* ]]; then ok "malformed outranks closing"; else bad "malformed vs closing — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset; epic_branch; merge; archives; epic "$SIGNED"; await
perl -pi -e 's/\n/\r\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a CRLF epic plan at awaiting-approval" "$EPIC" autopilot closing - awaiting_approval
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -pi -e 's/^> Status: planning$/```\n> Status: awaiting-approval\n```/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a Status line inside a fence is no status" "$EPIC" autopilot closable merged -
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -0pi -e 's/\n\nv\n/\n\nv\n\n> Status: awaiting-approval\n/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "a Status line below the frontmatter is no status" "$EPIC" autopilot closable merged -
reset; epic_branch; merge; archives; epic "$SIGNED"; await
epic "$L_RUN" "> Epic-ID: epic-901
> Epic-Slug: other" ".claude/plans/epic-901-other.md"
run --trunk main
expect "scan: the closing epic" "$EPIC" autopilot closing - awaiting_approval
expect "scan: the open epic beside it" ".claude/plans/epic-901-other.md" autopilot not-signed-off - no_answer
expect_counts "scan: counts with a closing epic" 2 0

echo "epic-close-state.sh — entries"
reset; epic_branch; merge; archives; epic "$SIGNED"
rm -f "$P/.claude/project/slices/slice-902-beta.md"
printf '# Slice 902\n\n> Status: reviewing\n> Slice-ID: slice-902\n' > "$P/.claude/plans/slice-902-beta.md"
run --trunk main "$EPIC"
expect "a slice still open" "$EPIC" autopilot entries-open - not_landed:slice-902:plan
reset; epic_branch; merge; archives; epic "$SIGNED"
perl -pi -e 's/^- \[x\] slice-902 — beta/- [ ] beta/' "$P/$EPIC"
run --trunk main "$EPIC"
expect "an entry never planned" "$EPIC" autopilot entries-open - not_landed:-:unlinked

echo "epic-close-state.sh — the epic branch"
reset; g checkout -b "$BR"; g checkout main; archives; epic "$SIGNED"
run --trunk main "$EPIC"
expect "the ancestor trap: a branch without own commits is not merged" "$EPIC" autopilot branch-unmerged unmerged branch_unmerged
reset; epic_branch; merge; archives; epic "$SIGNED"
g checkout "$BR"; echo more > "$P/more.txt"; g add more.txt; g commit -m more; g checkout main
run --trunk main "$EPIC"
expect "commits on the epic branch after the merge" "$EPIC" autopilot branch-unmerged unmerged branch_unmerged
reset; epic_branch; archives; epic "$SIGNED"
g branch -D "$BR"
run --trunk main "$EPIC"
expect "branch gone and no merge commit on the trunk" "$EPIC" autopilot branch-unmerged missing branch_missing

echo "epic-close-state.sh — scanning every epic plan"
reset; epic_branch; merge; archives; epic "$SIGNED"
epic "$L_RUN" "> Epic-ID: epic-901
> Epic-Slug: other" ".claude/plans/epic-901-other.md"
run --trunk main
expect "scan: the closable epic" "$EPIC" autopilot closable merged -
expect "scan: the open epic" ".claude/plans/epic-901-other.md" autopilot not-signed-off - no_answer
expect_counts "scan: counts" 2 1
reset
run --trunk main
if [[ $RC -eq 0 && "$OUT" == $'EPIC_COUNT=0\nCLOSABLE_COUNT=0' ]]; then ok "scan: no epic plan"
else bad "scan: no epic plan — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi

echo "epic-close-state.sh — malformed plans and errors"
reset; epic_branch; merge; archives; epic "$SIGNED" "> Epic-Slug: demo"
run --trunk main "$EPIC"
if [[ $RC -eq 0 && "$OUT" == *"EPIC=- PLAN=$EPIC KIND=- STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_frontmatter:Epic-ID"* ]]; then
  ok "no Epic-ID: malformed, never closable"; else bad "no Epic-ID — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset; epic_branch; merge; archives; epic "$SIGNED" "> Epic-ID: epic-900"
run --trunk main "$EPIC"
if [[ $RC -eq 0 && "$OUT" == *"EPIC=epic-900 PLAN=$EPIC KIND=- STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_frontmatter:Epic-Slug"* ]]; then
  ok "no Epic-Slug: malformed"; else bad "no Epic-Slug — rc=$RC: $(tr '\n' '|' <<<"$OUT")"; fi
reset
run --trunk main ".claude/plans/epic-999-none.md"
if [[ $RC -eq 0 && "$OUT" == *"PLAN=.claude/plans/epic-999-none.md KIND=- STATE=malformed BRANCH=- BRANCH_STATE=- REASON=epic_plan_unreadable"* ]]; then
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
for s in closable not-signed-off not-merged pr-path entries-open branch-unmerged malformed; do
  grep -qF "STATE=$s" "$COMMIT_MD" && ok "commit.md handles STATE=$s" || bad "commit.md does not handle STATE=$s"
done
for k in autopilot sequential; do
  grep -qF "KIND=$k" "$COMMIT_MD" && ok "commit.md handles KIND=$k" || bad "commit.md does not handle KIND=$k"
done
grep -qF 'STATE=closing' "$COMMIT_MD" && ok "commit.md handles STATE=closing" || bad "commit.md does not handle STATE=closing"
close_sec="$(awk '/^## Epic-close Mode/{f=1;next} f&&/^## /{exit} f' "$COMMIT_MD")"
grep -qE 'plan-landing\.sh.* close ' <<<"$close_sec" && ok "Epic-close calls plan-landing.sh close" || bad "Epic-close does not call plan-landing.sh close"
grep -qE 'plan-landing\.sh.* sync ' <<<"$close_sec" && ok "Epic-close calls plan-landing.sh sync" || bad "Epic-close does not call plan-landing.sh sync"
# the status graph allows exactly ONE craft:writes marker per command and status (test-workflow-status-graph.sh) — Step 6
# item 3 holds it; Epic-close sets the status by delegating to that item, so its text must say so
grep -qF 'status=awaiting-approval' <<<"$close_sec" && grep -qF 'Step 6' <<<"$close_sec" && grep -qF 'Status: awaiting-approval' <<<"$close_sec" && ok "Epic-close sets awaiting-approval through Step 6's first-invocation item 3" || bad "Epic-close does not name the awaiting-approval write it delegates to Step 6"
[[ "$(grep -cF '<!-- craft:writes status=awaiting-approval -->' "$COMMIT_MD")" -eq 1 ]] && ok "commit.md carries the one awaiting-approval writer marker" || bad "commit.md does not carry exactly one awaiting-approval writer marker"
grep -qF -- '<epic-id>-<slug>-close' <<<"$close_sec" && ok "Epic-close names the close branch (<epic-id>-<slug>-close)" || bad "Epic-close does not name the close branch"
grep -qF 'gh pr create' <<<"$close_sec" && ok "Epic-close opens the close PR with gh pr create" || bad "Epic-close does not name gh pr create"
for stale in 'close it by hand, through a PR (B25)' 'that close is not built yet (B25)'; do
  grep -qF "$stale" "$COMMIT_MD" "$EXECUTE_MD" && bad "a shipped command still says: $stale" || ok "no command still says: $stale"
done
a5pr="$(awk '/^### a5 /{f=1} f&&/^- \*\*\[Y\], `pull-request`/{g=1;next} g&&/^- \*\*\[N\]\*\*/{exit} g' "$EXECUTE_MD")"
grep -qF 'Recommended next: /craft:commit' <<<"$a5pr" && ok "execute.md a5's PR bullet hands over to /craft:commit" || bad "execute.md a5's PR bullet lacks 'Recommended next: /craft:commit'"
grep -qF 'STATE=not-autopilot' "$COMMIT_MD" && bad "commit.md still handles the removed STATE=not-autopilot" || ok "commit.md no longer names STATE=not-autopilot"
grep -qF '## Epic-close Mode' "$COMMIT_MD" && ok "commit.md has the Epic-close mode" || bad "commit.md lacks '## Epic-close Mode'"
a5="$(awk '/^### a5 /{f=1} f&&/^## /{exit} f' "$EXECUTE_MD")"
grep -qF 'Recommended next: /craft:commit' <<<"$a5" && ok "execute.md a5 hands over to /craft:commit" || bad "execute.md a5 lacks 'Recommended next: /craft:commit'"
s5="$(awk '/^### s5 /{f=1;next} f&&/^#{2,3} /{exit} f' "$EXECUTE_MD")"
grep -qF 'Recommended next: /craft:commit' <<<"$s5" && ok "execute.md s5 hands over to /craft:commit" || bad "execute.md s5 lacks 'Recommended next: /craft:commit'"
if grep -qF 'closing an epic is not part of an autopilot run' "$EXECUTE_MD"; then bad "execute.md still says closing is not part of the run"
else ok "execute.md no longer says closing is not part of the run"; fi
# the mode was renamed (slice-062, D38): no shipped file may still name the old one
old="$(grep -rlF 'Autopilot-epic-close' "$REPO/commands" "$REPO/skills" "$REPO/agents" "$REPO/templates" "$REPO/docs" "$REPO/README.md" "$REPO/CLAUDE.md" "$REPO/scripts/epic-close-state.sh" 2>/dev/null)"
[[ -z "$old" ]] && ok "no shipped file names the old Autopilot-epic-close mode" || bad "the old mode name remains in: $(tr '\n' ' ' <<<"$old")"

echo "the epic archive template"
TPL="$REPO/templates/epic-archive.md.template"
if [[ -f "$TPL" ]]; then
  ok "templates/epic-archive.md.template exists"
  for h in '## Vision' '## Epic Decisions' '## Open follow-ups'; do
    grep -qxF "$h" "$TPL" && ok "the template carries $h" || bad "the template lacks $h"
  done
  grep -qE '^## Slices \(' "$TPL" && ok "the template carries ## Slices (N/N)" || bad "the template lacks ## Slices (N/N)"
  for k in Completed Slices Merge; do
    grep -qE "^> $k: " "$TPL" && ok "the template's frontmatter carries > $k:" || bad "the template's frontmatter lacks > $k:"
  done
  grep -qxF '## Commits' "$TPL" && bad "the template has a ## Commits section — commits belong in the frontmatter only" || ok "the template has no ## Commits section"
else
  bad "templates/epic-archive.md.template is missing"
fi
[[ "$(grep -cF 'templates/epic-archive.md.template' "$COMMIT_MD")" -ge 3 ]] \
  && ok "commit.md names the template in Step 5, in Epic-close and in its P3" \
  || bad "commit.md names templates/epic-archive.md.template fewer than 3 times"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
