#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-execute-resume-state.sh — self-contained tests for the B8 re-run helper
# (execute-resume-state.sh).
#
# No test runner exists in this repo (plugin assets, not runtime software), so this
# harness stands alone: each case builds a throwaway repo with real git worktrees, branches
# and merges under a temp dir, writes slice / epic plans, drives the helper and asserts on
# its KEY=VALUE output. It also binds the helper's action table to its own header comment
# and to commands/execute.md. Run it directly:
#
#   bash scripts/test-execute-resume-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/execute-resume-state.sh"
EXECUTE="$REPO_ROOT/commands/execute.md"
for f in "$HELPER" "$EXECUTE"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR   # the helper prefers it over the cwd; each case sets it where it tests it

N=0
P=""   # the current fixture project (main checkout)
W=""   # its worktree base: <parent>/proj-worktrees
fixture() { # fresh project with one commit on main; plans are gitignored
  N=$((N + 1))
  mkdir -p "$TMP/c$N"
  P="$TMP/c$N/proj"; W="$TMP/c$N/proj-worktrees"
  git init -q -b main "$P"
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
  printf '.claude/plans/\n' > "$P/.gitignore"
  git -C "$P" add . && git -C "$P" commit -q -m init
}
splan() { # id slug status
  printf '# Slice — fixture\n\n> Status: %s\n> Slice-ID: %s\n> Slice-Slug: %s\n' "$3" "$1" "$2" > "$P/.claude/plans/$1-$2.md"
}
eplan() { printf '# Epic — fixture\n\n> Status: active\n> Epic-ID: epic-001\n> Epic-Slug: ep\n' > "$P/.claude/plans/epic-001-ep.md"; }
commit_plans() { # a new worktree reads the plan from its base, so worktree cases commit theirs (ignored or not)
  (cd "$P" && git add -f .claude/plans/*.md && git commit -q -m plans)
}
run() { (cd "$P" && bash "$HELPER" "$@" 2>&1); }
EPIC=".claude/plans/epic-001-ep.md"
S1=".claude/plans/slice-001-a.md"
S2=".claude/plans/slice-002-b.md"

# the value of KEY on the line starting with <head> (e.g. SLICE=slice-001), or a global KEY=
field() { # output head key
  local line
  if [[ -n "$2" ]]; then
    line="$(printf '%s\n' "$1" | grep -m1 "^$2 ")" || return 0
    if [[ "$3" == "WORKTREE" ]]; then printf '%s' "${line#* WORKTREE=}"; return 0; fi
    printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^$3=//p" | head -1
  else
    printf '%s\n' "$1" | sed -n "s/^$3=//p" | head -1
  fi
}
expect() { # name output head key want
  local got
  got="$(field "$2" "$3" "$4")"
  if [[ "$got" == "$5" ]]; then ok "$1"; else bad "$1 — $4=$got, want $5"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}
epic_worktree() { git -C "$P" worktree add -q "$W/epic-001-ep" -b epic-001-ep; }
slice_worktree() { # id-slug from-ref
  git -C "$P" worktree add -q "$W/$1" -b "$1" "$2"
}
merge_into_epic() { # id-slug slice-id
  git -C "$W/$1" commit -q --allow-empty -m "work $2"
  git -C "$W/epic-001-ep" merge -q --no-ff "$1" -m "Merge $2 into epic-001"
}

echo "── parallel: what a re-run finds ────────────────────────────────────"

fixture; eplan; splan slice-001 a implementing; splan slice-002 b planning; commit_plans
out="$(run --epic "$EPIC" "$S1" "$S2")"
expect "fresh epic → epic line create"            "$out" "EPIC=epic-001"  ACTION create
expect "fresh epic → slice create"                "$out" "SLICE=slice-001" ACTION create
expect "fresh epic → pattern path"                "$out" "SLICE=slice-001" WORKTREE "$W/slice-001-a"
expect "fresh epic → RESULT ok"                   "$out" "" RESULT ok

epic_worktree
slice_worktree slice-001-a epic-001-ep
out="$(run --epic "$EPIC" "$S1" "$S2")"
expect "epic worktree exists → epic line reuse"   "$out" "EPIC=epic-001"  ACTION reuse
expect "fresh slice branch, no commits → reuse, not merged (ancestor trap)" "$out" "SLICE=slice-001" ACTION reuse
expect "  … MERGED=no"                            "$out" "SLICE=slice-001" MERGED no
expect "  … reused worktree path"                 "$out" "SLICE=slice-001" WORKTREE "$W/slice-001-a"
expect "untouched slice beside it → create"       "$out" "SLICE=slice-002" ACTION create

merge_into_epic slice-001-a slice-001
out="$(run --epic "$EPIC" "$S1" "$S2")"
expect "merged by --no-ff into the epic branch → skip" "$out" "SLICE=slice-001" ACTION skip
expect "  … REASON merged"                        "$out" "SLICE=slice-001" REASON merged
expect "  … RESULT ok"                            "$out" "" RESULT ok

git -C "$P" worktree remove "$W/slice-001-a" && git -C "$P" branch -q -D slice-001-a && ! git -C "$P" show-ref --quiet refs/heads/slice-001-a && ok "  (fixture: slice branch deleted)"
out="$(run --epic "$EPIC" "$S1" "$S2")"
expect "merged, branch since deleted → skip by merge subject" "$out" "SLICE=slice-001" REASON merged

fixture; eplan; splan slice-001 a implementing
epic_worktree
git -C "$P" branch -q slice-001-a epic-001-ep
out="$(run --epic "$EPIC" "$S1")"
expect "branch without worktree → conflict"       "$out" "SLICE=slice-001" REASON branch_without_worktree
expect "  … RESULT conflict"                      "$out" "" RESULT conflict
expect "  … CONFLICT_COUNT 1"                     "$out" "" CONFLICT_COUNT 1

fixture; eplan; splan slice-001 a implementing
epic_worktree; slice_worktree slice-001-a epic-001-ep
mv "$W/slice-001-a" "$TMP/c$N/moved-away"
out="$(run --epic "$EPIC" "$S1")"
expect "registered worktree, directory gone → conflict" "$out" "SLICE=slice-001" REASON worktree_missing

fixture; eplan; splan slice-001 a implementing
epic_worktree
git -C "$P" worktree add -q "$W/slice-001-a" -b something-else
out="$(run --epic "$EPIC" "$S1")"
expect "pattern path is a worktree on another branch → conflict" "$out" "SLICE=slice-001" REASON worktree_foreign_branch

fixture; eplan; splan slice-001 a implementing
git -C "$P" worktree add -q --detach "$W/slice-001-a"
out="$(run --epic "$EPIC" "$S1")"
expect "pattern path is a detached worktree → conflict" "$out" "SLICE=slice-001" REASON worktree_foreign_branch

fixture; eplan; splan slice-001 a implementing
mkdir -p "$W/slice-001-a"
out="$(run --epic "$EPIC" "$S1")"
expect "pattern path is a plain directory → conflict" "$out" "SLICE=slice-001" REASON path_taken

# a new worktree is a checkout of its base. Since slice-067 a SLICE's plan is handed in by execute step 5
# (plan-roundtrip.sh in), so the base need not hold it; the EPIC line keeps the guard (R1-1)
fixture; eplan; splan slice-001 a implementing
out="$(run --epic "$EPIC" "$S1")"
expect "plans never committed (ignored) → epic line plan_not_committed" "$out" "EPIC=epic-001" REASON plan_not_committed
expect "  … the slice creates (its plan is handed in)"  "$out" "SLICE=slice-001" ACTION create
expect "  … REASON fresh"                         "$out" "SLICE=slice-001" REASON fresh
out="$(run "$S1")"
expect "  … lone slice as well"                   "$out" "SLICE=slice-001" ACTION create
expect "  … REASON fresh (lone slice)"            "$out" "SLICE=slice-001" REASON fresh
commit_plans
printf 'edit\n' >> "$P/$S1"
out="$(run --epic "$EPIC" "$S1")"
expect "committed plan edited since → the slice still creates" "$out" "SLICE=slice-001" ACTION create
expect "  … the unchanged epic plan creates"      "$out" "EPIC=epic-001" ACTION create
printf 'edit\n' >> "$P/$EPIC"
out="$(run --epic "$EPIC" "$S1")"
expect "  … an epic plan edited since its commit → plan_not_committed" "$out" "EPIC=epic-001" REASON plan_not_committed
git -C "$P" add -f "$S1" "$EPIC"; git -C "$P" commit -q -m "plan edit"
out="$(run --epic "$EPIC" "$S1")"
expect "  … committed → create"                   "$out" "SLICE=slice-001" ACTION create
epic_worktree
splan slice-002 b planning; git -C "$P" add -f "$S2"; git -C "$P" commit -q -m "late plan on main"
out="$(run --epic "$EPIC" "$S1" "$S2")"
expect "plan committed on main after the epic branch was cut → the slice creates" "$out" "SLICE=slice-002" ACTION create
expect "  … a plan the epic branch holds creates"  "$out" "SLICE=slice-001" ACTION create
slice_worktree slice-001-a epic-001-ep
printf 'status edit\n' >> "$P/$S1"
out="$(run --epic "$EPIC" "$S1")"
expect "an existing worktree is reused whatever the main-checkout plan says" "$out" "SLICE=slice-001" ACTION reuse

fixture; eplan; splan slice-001 a implementing; commit_plans
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
out="$(run --epic "$EPIC" "$S1")"
expect "plan still present beside its archive → not landed" "$out" "SLICE=slice-001" ACTION create
mv "$P/$S1" "$TMP/c$N/closed-plan.md"
out="$(run --epic "$EPIC" "$S1")"
expect "plan gone, archive present → skip archived" "$out" "SLICE=slice-001" REASON archived
out="$(run --epic "$EPIC" slice-001)"
expect "slice-ID with only an archive → skip archived" "$out" "SLICE=slice-001" REASON archived

fixture; splan slice-001 a awaiting-approval
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
slice_worktree slice-001-a main
out="$(run "$S1")"
expect "lone slice at awaiting-approval (archive written by commit's first pass) → skip" "$out" "SLICE=slice-001" REASON awaiting_approval

fixture; eplan; splan slice-001 a implementing
epic_worktree; slice_worktree slice-001-a epic-001-ep
merge_into_epic slice-001-a slice-001
git -C "$W/slice-001-a" commit -q --allow-empty -m "after the merge"
out="$(run --epic "$EPIC" "$S1")"
expect "branch advanced after its merge → reuse, not skipped by the merge subject" "$out" "SLICE=slice-001" ACTION reuse

fixture; eplan; splan slice-001 a planning
epic_worktree
printf 'x\n' > "$W/epic-001-ep/f.txt"; git -C "$W/epic-001-ep" add f.txt; git -C "$W/epic-001-ep" commit -q -m epic-side
git -C "$P" checkout -q -b side; printf 'y\n' > "$P/f.txt"; git -C "$P" add f.txt; git -C "$P" commit -q -m side-side; git -C "$P" checkout -q main
git -C "$W/epic-001-ep" merge -q side >/dev/null 2>&1
out="$(run --epic "$EPIC" "$S1")"
expect "epic worktree with an unfinished merge → conflict" "$out" "EPIC=epic-001" REASON epic_merge_in_progress
git -C "$W/epic-001-ep" merge --abort
printf 'stray\n' > "$W/epic-001-ep/stray.txt"
out="$(run --epic "$EPIC" "$S1")"
expect "epic worktree with uncommitted changes → conflict" "$out" "EPIC=epic-001" REASON epic_worktree_dirty

fixture; eplan; printf '# Slice\n\n> Status: implementing\n> Slice-ID: slice-001\n' > "$P/$S1"
out="$(run --epic "$EPIC" "$S1")"
expect "plan without Slice-Slug → conflict"       "$out" "SLICE=slice-001" REASON plan_unreadable
printf '# Epic\n\n> Epic-ID: epic-001\n' > "$P/$EPIC"; splan slice-001 a implementing
out="$(run --epic "$EPIC" "$S1")"
expect "epic plan without Epic-Slug → epic conflict" "$out" "EPIC=epic-001" REASON plan_unreadable

fixture; splan slice-001 a committing
slice_worktree slice-001-a main
out="$(run "$S1")"
expect "lone slice, worktree exists → reuse"      "$out" "SLICE=slice-001" ACTION reuse
expect "  … no epic line"                         "$out" "EPIC=epic-001" ACTION ""
git -C "$W/slice-001-a" commit -q --allow-empty -m work
git -C "$P" merge -q --no-ff slice-001-a -m "Merge slice-001: fixture"
out="$(run "$S1")"
expect "lone slice merged into the trunk → skip"  "$out" "SLICE=slice-001" REASON merged

fixture; eplan; splan slice-001 a planning
out="$(run --epic "$EPIC" --branch-pattern 'feature/<slice-id>' --path-pattern '../wt/<slug>-<slice-id>' "$S1")"
expect "custom branch pattern"                    "$out" "SLICE=slice-001" BRANCH feature/slice-001
expect "custom path pattern"                      "$out" "SLICE=slice-001" WORKTREE "$TMP/c$N/wt/a-slice-001"
expect "custom patterns apply to the epic"        "$out" "EPIC=epic-001"  BRANCH feature/epic-001

echo "── sequential: resume a stopped slice ───────────────────────────────"

fixture
for s in implementing testing review refactoring reviewing committing; do
  splan slice-001 a "$s"; splan slice-002 b planning
  out="$(run --mode sequential "$S1" "$S2")"
  expect "status $s → resume"                     "$out" "SLICE=slice-001" ACTION resume
done
expect "  … OPEN_SLICE"                           "$out" "" OPEN_SLICE slice-001
expect "  … next planned slice → create"          "$out" "SLICE=slice-002" ACTION create

splan slice-001 a awaiting-approval
out="$(run --mode sequential "$S1" "$S2")"
expect "awaiting-approval → resume"               "$out" "SLICE=slice-001" REASON awaiting_approval
for s in paused blocked; do
  splan slice-001 a "$s"
  out="$(run --mode sequential "$S1" "$S2")"
  expect "status $s → held"                       "$out" "SLICE=slice-001" ACTION held
done
splan slice-001 a awaiting-release
out="$(run --mode sequential "$S1" "$S2")"
expect "unknown status → conflict"                "$out" "SLICE=slice-001" REASON unknown_status

splan slice-001 a implementing; splan slice-002 b reviewing
out="$(run --mode sequential "$S1" "$S2")"
expect "two open slices → both conflict"          "$out" "SLICE=slice-002" REASON multiple_open
expect "  … the first too"                        "$out" "SLICE=slice-001" REASON multiple_open
expect "  … OPEN_SLICE none"                      "$out" "" OPEN_SLICE none

splan slice-001 a implementing; splan slice-002 b planning
printf 'wip\n' > "$P/work.txt"
out="$(run --mode sequential "$S1" "$S2")"
expect "direct: dirty trunk with one open slice → ok" "$out" "" RESULT ok
expect "  … DIRTY yes"                            "$out" "" DIRTY yes
splan slice-001 a planning
out="$(run --mode sequential "$S1" "$S2")"
expect "dirty tree, no open slice → conflict"     "$out" "" RESULT_REASON dirty_without_open_slice
expect "  … RESULT conflict"                      "$out" "" RESULT conflict

fixture; splan slice-001 a implementing
git -C "$P" checkout -q -b elsewhere
out="$(run --mode sequential "$S1")"
expect "direct: open slice, not on the trunk → wrong_branch" "$out" "" RESULT_REASON wrong_branch

fixture; splan slice-001 a implementing; splan slice-002 b planning
git -C "$P" checkout -q -b slice-001-a
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: open slice on its branch → ok" "$out" "" RESULT ok
git -C "$P" checkout -q main
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: open slice, on the trunk → wrong_branch" "$out" "" RESULT_REASON wrong_branch
git -C "$P" branch -q -D slice-001-a
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: open slice without its branch → conflict" "$out" "SLICE=slice-001" REASON branch_missing
splan slice-001 a planning
git -C "$P" branch -q slice-001-a
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: fresh slice whose branch exists → conflict" "$out" "SLICE=slice-001" REASON branch_exists
git -C "$P" branch -q -D slice-001-a
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: fresh start on a clean trunk → ok" "$out" "" RESULT ok

fixture; splan slice-001 a awaiting-approval; splan slice-002 b planning
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
git -C "$P" checkout -q -b slice-001-a
printf 'plan edit\n' >> "$P/$S1"
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: awaiting-approval with its archive, on its branch → resume" "$out" "SLICE=slice-001" REASON awaiting_approval
expect "  … RESULT ok"                            "$out" "" RESULT ok

fixture; splan slice-001 a committing; splan slice-002 b planning
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
out="$(run --mode sequential "$S1" "$S2")"
expect "plan still present beside its archive (push failed) → resume" "$out" "SLICE=slice-001" ACTION resume

for s in paused blocked; do
  fixture; splan slice-001 a "$s"; splan slice-002 b planning
  printf 'half done\n' > "$P/work.txt"
  out="$(run --mode sequential "$S1" "$S2")"
  expect "direct: $s slice with its own uncommitted work → held, RESULT ok" "$out" "" RESULT ok
  expect "  … OPEN_SLICE is the held slice"       "$out" "" OPEN_SLICE slice-001
done
fixture; splan slice-001 a paused; splan slice-002 b planning
git -C "$P" checkout -q -b slice-001-a; printf 'half done\n' > "$P/work.txt"
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: paused slice on its branch with work → RESULT ok" "$out" "" RESULT ok
git -C "$P" checkout -q main
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: paused slice, checkout on the trunk → wrong_branch" "$out" "" RESULT_REASON wrong_branch
fixture; splan slice-001 a paused; splan slice-002 b implementing
out="$(run --mode sequential "$S1" "$S2")"
expect "held and resume slice together → multiple_open" "$out" "SLICE=slice-001" REASON multiple_open

fixture; splan slice-001 a implementing; splan slice-002 b planning
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
git -C "$P" add .claude/project/slices && git -C "$P" commit -q -m "archive slice-001"   # commit's P2 leaves a clean tree
mv "$P/$S1" "$TMP/c$N/closed-plan.md"
out="$(run --mode sequential "$S1" "$S2")"
expect "after s0: the landed slice's deleted plan path → skip archived" "$out" "SLICE=slice-001" REASON archived
expect "  … the next slice → create"              "$out" "SLICE=slice-002" ACTION create
expect "  … RESULT ok"                            "$out" "" RESULT ok
printf '# archive\n' > "$P/.claude/project/slices/slice-002-b.md"; mv "$P/$S2" "$TMP/c$N/closed-plan-2.md"
git -C "$P" add .claude/project/slices && git -C "$P" commit -q -m "archive slice-002"
out="$(run --mode sequential slice-001 slice-002)"
expect "every slice landed, passed as slice-IDs → all skip, RESULT ok" "$out" "" RESULT ok

fixture
git -C "$P" rm -q --cached .gitignore; rm "$P/.gitignore"; git -C "$P" commit -q -m "track everything"
splan slice-001 a planning; git -C "$P" add -A; git -C "$P" commit -q -m plans
printf '12345 epic-001\n' > "$P/.claude/plans/.execute.lock"; touch "$P/.claude/plans/.primed" "$P/.claude/plans/.hook-env" "$P/.claude/plans/.cache-guard"
out="$(run --mode sequential "$S1")"
expect "CRAFT's own session files (lock, .primed, .hook-env, .cache-guard) are not dirt" "$out" "" DIRTY no
mkdir -p "$P/.claude/plans/.closed"; printf '# closed\n' > "$P/.claude/plans/.closed/slice-009-z.md"
out="$(run --mode sequential "$S1")"
expect "  … nor are closed plans in .claude/plans/.closed/ (B19), unignored and untracked" "$out" "" DIRTY no
expect "  … and a closed plan is no slice in flight: slice-001 alone is read"  "$out" "SLICE=slice-001" ACTION create
printf 'real\n' > "$P/real.txt"
out="$(run --mode sequential "$S1")"
expect "  … a real untracked file still is"       "$out" "" DIRTY yes

fixture
git -C "$P" rm -q --cached .gitignore; rm "$P/.gitignore"; git -C "$P" commit -q -m "track everything"
eplan; splan slice-001 a planning; git -C "$P" add -A; git -C "$P" commit -q -m plans
epic_worktree
mkdir -p "$W/epic-001-ep/.claude/plans"; touch "$W/epic-001-ep/.claude/plans/.primed" "$W/epic-001-ep/.claude/plans/.hook-env"
out="$(run --epic "$EPIC" "$S1")"
expect "epic worktree with only CRAFT's session files → reuse" "$out" "EPIC=epic-001" ACTION reuse
mkdir -p "$W/epic-001-ep/.craft"; printf 'slice-001 shown 2026-09-14\n' > "$W/epic-001-ep/.craft/checkpoints.md"
out="$(run --epic "$EPIC" "$S1")"
expect "  … plus a step-9 checkpoint record in a project that does not ignore .craft/ → reuse" "$out" "EPIC=epic-001" ACTION reuse
printf 'x\n' > "$W/epic-001-ep/.craft/other.md"
out="$(run --epic "$EPIC" "$S1")"
expect "  … any other file under .craft/ still is dirt" "$out" "EPIC=epic-001" REASON epic_worktree_dirty

# slice-066 (B20): step 9 keeps the record as state and hides it through a nested .craft/.gitignore, so nothing
# of CRAFT's issues a removal and `git worktree remove` of the epic worktree still succeeds.
# The two lines below are the ones commands/execute.md step 9 names (pinned further down).
record_gitignore() { printf '/.gitignore\n/checkpoints.md\n' > "$W/epic-001-ep/.craft/.gitignore"; }
record_fixture() { # a project that does not ignore .craft/ (or, given a rule, negates it), plus an epic worktree holding the record
  fixture
  git -C "$P" rm -q .gitignore
  [[ -n "${1:-}" ]] && { printf '%s\n' "$1" > "$P/.gitignore"; git -C "$P" add .gitignore; }
  git -C "$P" commit -q -m "track everything"
  eplan; splan slice-001 a planning; git -C "$P" add -A; git -C "$P" commit -q -m plans
  epic_worktree
  mkdir -p "$W/epic-001-ep/.craft"; printf 'slice-001 shown 2026-09-14 abc123\n' > "$W/epic-001-ep/.craft/checkpoints.md"
}
record_fixture; record_gitignore
out="$(run --epic "$EPIC" "$S1")"
expect "step-9 record kept as state: epic worktree reads reuse" "$out" "EPIC=epic-001" ACTION reuse
st="$(git -C "$W/epic-001-ep" status --porcelain --untracked-files=all)"
[[ -z "$st" ]] && ok "  … and git status in the epic worktree lists neither file" || bad "  … git status lists: $st"
git -C "$P" worktree remove "$W/epic-001-ep" >/dev/null 2>&1; rc=$?
if [[ "$rc" == 0 && ! -d "$W/epic-001-ep" ]]; then ok "step-9 record kept as state: git worktree remove succeeds"
else bad "step-9 record kept as state: git worktree remove succeeds — exit $rc"; fi

record_fixture $'.craft/\n!.craft/'; record_gitignore   # a real negation: the project's rule un-ignores .craft/ again
st="$(git -C "$W/epic-001-ep" status --porcelain --untracked-files=all)"
git -C "$P" worktree remove "$W/epic-001-ep" >/dev/null 2>&1; rc=$?
if [[ -z "$st" && "$rc" == 0 && ! -d "$W/epic-001-ep" ]]; then ok "step-9 record kept as state: a project negation of .craft/ does not expose it"
else bad "step-9 record kept as state: a project negation of .craft/ does not expose it — status '$st', remove exit $rc"; fi

record_fixture
git -C "$P" worktree remove "$W/epic-001-ep" >/dev/null 2>&1; rc=$?
[[ "$rc" != 0 && -d "$W/epic-001-ep" ]] && ok "step-9 record without its .gitignore still blocks git worktree remove" \
  || bad "step-9 record without its .gitignore still blocks git worktree remove — exit $rc"
out="$(run --epic "$EPIC" "$S1")"
expect "  … yet a record written before this slice still reads reuse (tree-dirt-state's exclusion)" "$out" "EPIC=epic-001" ACTION reuse

# another writer created .craft/.gitignore first (slice-067): step 9 appends the missing line, never rewrites one
record_fixture; printf '/.gitignore\n' > "$W/epic-001-ep/.craft/.gitignore"
st="$(git -C "$W/epic-001-ep" status --porcelain --untracked-files=all)"
[[ -n "$st" ]] && ok "a .gitignore lacking the record's line leaves the record exposed (the premise for the append)" \
  || bad "a .gitignore lacking the record's line leaves the record exposed — status is empty"
printf '/checkpoints.md\n' >> "$W/epic-001-ep/.craft/.gitignore"
st="$(git -C "$W/epic-001-ep" status --porcelain --untracked-files=all)"
git -C "$P" worktree remove "$W/epic-001-ep" >/dev/null 2>&1; rc=$?
[[ -z "$st" && "$rc" == 0 && ! -d "$W/epic-001-ep" ]] && ok "step-9 record kept as state: an existing .gitignore gets the missing line appended and the removal succeeds" \
  || bad "step-9 append case — status '$st', remove exit $rc"

record_fixture; record_gitignore
printf 'x\n' > "$W/epic-001-ep/.craft/other.md"
out="$(run --epic "$EPIC" "$S1")"
expect "self-ignored record: any other file under .craft/ still is dirt" "$out" "EPIC=epic-001" REASON epic_worktree_dirty

# the prose names the same two lines the fixture writes
step9="$(awk '/^### 9\./{f=1} /^### 10\./{f=0} f' "$EXECUTE")"
if grep -qF '.craft/.gitignore' <<<"$step9" && grep -qF 'appends the missing line' <<<"$step9" && grep -qF '`/.gitignore`' <<<"$step9" && grep -qF '`/checkpoints.md`' <<<"$step9"; then
  ok "execute.md step 9 names the record's .gitignore lines"
else bad "execute.md step 9 names the record's .gitignore lines — not found in step 9"; fi

fixture; splan slice-001 a paused; splan slice-002 b implementing
printf 'half done\n' > "$P/work.txt"
out="$(run --mode sequential "$S1" "$S2")"
expect "held + open + dirty → the slices conflict, no run-wide reason" "$out" "" RESULT_REASON -
expect "  … multiple_open on the slices"          "$out" "SLICE=slice-002" REASON multiple_open
fixture; splan slice-001 a paused; splan slice-002 b planning
printf 'half done\n' > "$P/work.txt"
out="$(run --mode sequential --landing pull-request "$S1" "$S2")"
expect "pull-request: paused slice without its branch, dirty → branch_missing only" "$out" "" RESULT_REASON -

# a project below the repository root (slice-035): .claude/ is read in the project dir
N=$((N + 1)); mkdir -p "$TMP/c$N"
R="$TMP/c$N/repo"; git init -q -b main "$R"
P="$R/app"; mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
splan slice-002 b planning
git -C "$R" add -A && git -C "$R" commit -q -m init
printf '12345\n' > "$P/.claude/plans/.execute.lock"
out="$(run --mode sequential slice-001 "$S2")"
expect "subdirectory project: a landed slice-ID resolves from the project dir" "$out" "SLICE=slice-001" REASON archived
expect "  … its lock is not dirt"                 "$out" "" DIRTY no
expect "  … RESULT ok"                            "$out" "" RESULT ok
out="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" --mode sequential slice-001 .claude/plans/slice-002-b.md 2>&1)"
expect "  … CLAUDE_PROJECT_DIR wins over the cwd, relative plans resolve in it" "$out" "SLICE=slice-002" ACTION create
git -C "$R" add -f app/.claude/plans/slice-002-b.md >/dev/null 2>&1; git -C "$R" commit -q -m "plan" >/dev/null 2>&1 || true
out="$(run "$S2")"
expect "  … a committed plan passed by relative path reads from the project dir, not the repo root" "$out" "SLICE=slice-002" ACTION create
printf 'x\n' > "$R/outside.txt"
out="$(run --mode sequential slice-001 "$S2")"
expect "  … a change elsewhere in the repository still is dirt" "$out" "" DIRTY yes

echo "── autopilot: the epic branch is the trunk (slice-049) ──────────────"
# /craft:execute --autopilot runs the sequential rows with --landing direct --trunk <epic-branch>: every slice
# lands on the epic branch, so to this helper that branch plays the trunk. No helper change — these cases
# pin that the existing sequential rows give the autopilot run the answers it needs.

AP=(--mode sequential --landing direct --trunk epic-001-ep)
fixture; git -C "$P" checkout -q -b epic-001-ep
splan slice-001 a planning; splan slice-002 b planning
out="$(run "${AP[@]}" "$S1" "$S2")"
expect "autopilot: fresh run on the epic branch → ok"      "$out" "" RESULT ok
expect "  … TRUNK is the epic branch"                     "$out" "" TRUNK epic-001-ep
expect "  … first slice → create"                         "$out" "SLICE=slice-001" ACTION create

splan slice-001 a reviewing
printf 'wip\n' > "$P/work.txt"
out="$(run "${AP[@]}" "$S1" "$S2")"
expect "autopilot: stopped slice, its work on the epic branch → resume" "$out" "SLICE=slice-001" ACTION resume
expect "  … the dirt is that slice's, not a conflict"     "$out" "" RESULT ok

# the slice landed: /craft:commit (Autopilot Mode) committed its work and archive on the epic branch, removed the plan
(cd "$P" && printf 'archive\n' > .claude/project/slices/slice-001-a.md && git add -A && git commit -q -m "slice-001")
rm "$P/.claude/plans/slice-001-a.md"
out="$(run "${AP[@]}" slice-001 "$S2")"
expect "autopilot: a slice landed on the epic branch → skip" "$out" "SLICE=slice-001" ACTION skip
expect "  … the next slice → create"                      "$out" "SLICE=slice-002" ACTION create
expect "  … clean after the landing"                      "$out" "" RESULT ok

splan slice-002 b implementing
git -C "$P" checkout -q main
# only the slice in flight: slice-001's archive lives on the epic branch, so on main it is not found — which is
# why /craft:execute's a0 settles the epic branch BEFORE step 1c runs
out="$(run "${AP[@]}" "$S2")"
expect "autopilot: a slice in flight, checkout back on main → wrong_branch" "$out" "" RESULT_REASON wrong_branch
git -C "$P" checkout -q epic-001-ep
out="$(run --mode sequential "$S2")"
expect "control: the same run without --trunk <epic-branch> → wrong_branch" "$out" "" RESULT_REASON wrong_branch

echo "── autopilot: --slices-from the epic plan (slice-063) ───────────────"
# a4's step-1c re-run used to rebuild the slice list by hand — a probe's master passed the epic plan itself as a
# slice, read RESULT=conflict (plan_unreadable) and went on to a5 (slice-057 probe 1, B23). --slices-from reads the
# list off the epic plan's entries (epic-entry-link.sh resolve), so the caller passes none.

ep_entries() { # the epic plan with its decomposition entries (one argument per line)
  { printf '# Epic — fixture\n\n> Status: active\n> Epic-ID: epic-001\n> Epic-Slug: ep\n\n## Slice Decomposition\n\n'
    printf '%s\n' "$@"; printf '\n## Recap Draft\n'; } > "$P/$EPIC"
}
fixture; git -C "$P" checkout -q -b epic-001-ep
splan slice-001 a planning; splan slice-002 b planning
ep_entries '- [ ] slice-001 — a — first' '- [ ] slice-002 — b — second'
[[ "$(run "${AP[@]}" --slices-from "$EPIC")" == "$(run "${AP[@]}" "$S1" "$S2")" ]] \
  && ok "--slices-from: a fresh run reads exactly as the explicit list" \
  || bad "--slices-from: a fresh run differs from the explicit list"
out="$(run "${AP[@]}" "$EPIC" "$S2")"
expect "control: the epic plan passed as a slice → plan_unreadable (B23's mistake)" "$out" "" RESULT conflict
(cd "$P" && printf 'archive\n' > .claude/project/slices/slice-001-a.md && git add -A && git commit -q -m "slice-001")
rm "$P/.claude/plans/slice-001-a.md"
out="$(run "${AP[@]}" --slices-from "$EPIC")"
expect "--slices-from: the landed slice → skip"            "$out" "SLICE=slice-001" ACTION skip
expect "  … the next slice → create"                      "$out" "SLICE=slice-002" ACTION create
expect "  … RESULT ok"                                    "$out" "" RESULT ok
[[ "$out" == "$(run "${AP[@]}" slice-001 "$S2")" ]] \
  && ok "  … and reads exactly as the explicit list after the landing" \
  || bad "  … differs from the explicit list after the landing"

errof() { (cd "$P" && bash "$HELPER" "$@" 2>&1 >/dev/null; printf ' rc=%s' "$?"); }
ep_entries '- [ ] slice-002 — b — second' '- [ ] c — not planned yet'
expect_err() { if [[ "$2" == *"ERROR=$3"*" rc=$4" ]]; then ok "$1"; else bad "$1 — got '$2'"; fi; }
expect_err "--slices-from: an unlinked entry → exit 4, named" "$(errof "${AP[@]}" --slices-from "$EPIC")" "slices_from:unresolved:c:unlinked" 4
ep_entries '- [ ] slice-002 — b — second' '- [ ] slice-007 — d — aborted'
expect_err "--slices-from: a dead link (aborted slice) → exit 4" "$(errof "${AP[@]}" --slices-from "$EPIC")" "slices_from:unresolved:d:missing" 4
ep_entries '- [ ] slice-002 — b — second' '  - [ ] slice-003 — e — indented'
expect_err "--slices-from: an ignored line → exit 4" "$(errof "${AP[@]}" --slices-from "$EPIC")" "slices_from:ignored_line:" 4
ep_entries
expect_err "--slices-from: no entries → exit 4" "$(errof "${AP[@]}" --slices-from "$EPIC")" "slices_from:no_entries" 4
expect_err "--slices-from: an unreadable epic plan → exit 4" "$(errof "${AP[@]}" --slices-from .claude/plans/nope.md)" "slices_from:unreadable" 4
expect_err "--slices-from with a slice as well → exit 2" "$(errof "${AP[@]}" --slices-from "$EPIC" "$S2")" "slices_from_with_slices" 2

# the autopilot reads its slice list through --slices-from at step 1c and at a4's re-run, and stops on a conflict there
EXEC="$(cd "$(dirname "$HELPER")/.." && pwd)/commands/execute.md"
c1="$(awk '/^### 1c\./{f=1; next} f && /^### /{exit} f' "$EXEC")"
a4="$(awk '/^### a4 /{f=1; next} f && /^### /{exit} f' "$EXEC")"
[[ "$c1" == *'- autopilot run — `--mode sequential --landing direct --trunk <epic-branch> --slices-from <epic-plan>` and **no**'* ]] \
  && ok "step 1c: the autopilot run passes --slices-from and no slice list" \
  || bad "step 1c: the autopilot run still builds its slice list by hand (B23)"
[[ "$a4" == *'the same command, `--slices-from <epic-plan>` and no slice'* ]] \
  && ok "a4: the re-run uses --slices-from" || bad "a4: the re-run does not use --slices-from (B23)"
[[ "$a4" == *'**A `RESULT=conflict`'* && "$a4" == *'stops the run here**'* && "$a4" == *'never'*'goes on to a5'* ]] \
  && ok "a4: a conflict on the re-run stops the run ⛔ and never reaches a5" \
  || bad "a4: a conflict on the re-run does not stop before a5 (slice-057 probe 1)"

echo "── tree dirt: CRAFT's own files are not the human's work (B14) ──────"

DIRT="$SCRIPT_DIR/tree-dirt-state.sh"
dirt() { (cd "$P" && bash "$DIRT" "$@" 2>&1); }

# a project that neither tracks nor ignores its plans, but tracks the counter (this repo's shape)
fixture
git -C "$P" rm -q --cached .gitignore; rm "$P/.gitignore"
printf '1\n' > "$P/.claude/plans/.next-id"; git -C "$P" add -A; git -C "$P" commit -q -m "track the counter"
splan slice-001 a planning; printf '2\n' > "$P/.claude/plans/.next-id"
expect "untracked plan + modified tracked counter → not dirt" "$(dirt)" "" DIRTY no
out="$(run --mode sequential "$S1")"
expect "  … sequential re-run: no dirty_without_open_slice" "$out" "" RESULT_REASON -
expect "  … RESULT ok"                            "$out" "" RESULT ok
while IFS= read -r p; do
  case "$p" in */) mkdir -p "$P/$p"; printf 'x\n' > "$P/${p}handoff.md" ;; *) mkdir -p "$(dirname "$P/$p")"; printf 'x\n' > "$P/$p" ;; esac
done < <(bash "$SCRIPT_DIR/ensure-gitignore.sh" --print-paths)
expect "every local-state path from ensure-gitignore.sh --print-paths, unignored → not dirt" "$(dirt)" "" DIRTY no
git -C "$P" add -A; git -C "$P" commit -q -m "track plans too"
printf 'edit\n' >> "$P/$S1"; git -C "$P" rm -q "$P/.claude/plans/.next-id"
expect "tracked plan edited, tracked counter deleted → not dirt" "$(dirt)" "" DIRTY no
printf 'wip\n' > "$P/work.txt"; printf 'y\n' > "$P/.claude/other.md"
out="$(dirt)"
expect "unrelated file → dirt"                    "$out" "" DIRTY yes
printf '%s\n' "$out" | grep -qxF 'DIRT=?? work.txt' && ok "  … named on a DIRT line" || bad "  … named on a DIRT line"
printf '%s\n' "$out" | grep -qxF 'DIRT=?? .claude/other.md' && ok "  … a non-CRAFT file under .claude/ still is dirt" || bad "  … a non-CRAFT file under .claude/ still is dirt"
out="$(run --mode sequential "$S1")"
expect "  … sequential re-run still stops"        "$out" "" RESULT_REASON dirty_without_open_slice
mkdir -p "$P/docs"; printf 'mine\n' > "$P/docs/notes.md"; printf 'slice\n' > "$P/docs/guide.md"
out="$(dirt)"
{ printf '%s\n' "$out" | grep -qxF 'DIRT=?? docs/notes.md' && printf '%s\n' "$out" | grep -qxF 'DIRT=?? docs/guide.md' && ! printf '%s\n' "$out" | grep -qxF 'DIRT=?? docs/'; } \
  && ok "an untracked directory is listed file by file, never collapsed (P2 compares paths)" || bad "collapsed untracked directory: $(printf '%s' "$out" | tr '\n' '|')"

# the epic worktree keeps plans as dirt: slice branches are merged into it
fixture
git -C "$P" rm -q --cached .gitignore; rm "$P/.gitignore"
eplan; splan slice-001 a planning; git -C "$P" add -A; git -C "$P" commit -q -m plans
epic_worktree
printf 'edit\n' >> "$W/epic-001-ep/$S1"
expect "epic-worktree scope: an edited tracked plan is dirt" "$(dirt --checkout "$W/epic-001-ep" --scope epic-worktree)" "" DIRTY yes
expect "  … the main scope would not count it"    "$(dirt --checkout "$W/epic-001-ep")" "" DIRTY no
out="$(run --epic "$EPIC" "$S1")"
expect "  … execute-resume-state.sh judges the epic worktree in that scope" "$out" "EPIC=epic-001" REASON epic_worktree_dirty

# a slice worktree (slice-067): execute step 6 commits the slice's work and nothing of CRAFT's — in a project
# below the repository root, where some of CRAFT's files sit at the worktree root and some under the prefix
N=$((N + 1)); SD="$TMP/c$N"; mkdir -p "$SD"
git init -q -b main "$SD/proj"; mkdir -p "$SD/proj/sub/src"
printf 'v1\n' > "$SD/proj/sub/src/code.txt"; printf 'old\n' > "$SD/proj/sub/src/old.txt"
git -C "$SD/proj" add -A; git -C "$SD/proj" commit -q -m init
git -C "$SD/proj" worktree add -q "$SD/wt" -b slice-001-a main
SW="$SD/wt"
sdirt() { (cd "$SD/proj/sub" && CLAUDE_PROJECT_DIR="$SD/proj/sub" bash "$DIRT" --checkout "$SW" --scope slice-worktree "$@" 2>&1); }
mdirt() { (cd "$SD/proj/sub" && CLAUDE_PROJECT_DIR="$SD/proj/sub" bash "$DIRT" --checkout "$SW" "$@" 2>&1); }
mkdir -p "$SW/sub/.claude/plans/.closed" "$SW/.craft" "$SW/.claude/plans"
printf 'p\n' > "$SW/sub/.claude/plans/slice-001-a.md"; printf 'c\n' > "$SW/sub/.claude/plans/.closed/slice-000-z.md"
printf 'r\n' > "$SW/.craft/plan-roundtrip"; printf 'g\n' > "$SW/.craft/.gitignore"
printf 'h\n' > "$SW/.craft/handoff.md"; printf 'h\n' > "$SW/.craft/handoff-resolved-2026-10-07T10-00-00Z.md"
: > "$SW/.claude/plans/.primed"; : > "$SW/.claude/plans/.hook-env"; : > "$SW/.claude/plans/.cache-guard"
while IFS= read -r p; do
  case "$p" in */) mkdir -p "$SW/sub/$p"; printf 'x\n' > "$SW/sub/${p}f" ;; *) mkdir -p "$(dirname "$SW/sub/$p")"; printf 'x\n' > "$SW/sub/$p" ;; esac
done < <(bash "$SCRIPT_DIR/ensure-gitignore.sh" --print-paths)
expect "slice-worktree scope: CRAFT files are no dirt, slice work is" "$(sdirt)" "" DIRTY no
expect "  … the main scope counts the worktree-root files (.craft/, .primed) — that is why the scope exists" "$(mdirt)" "" DIRTY yes
printf 'v2\n' > "$SW/sub/src/code.txt"; printf 'new\n' > "$SW/sub/src/new.txt"; git -C "$SW" rm -q "sub/src/old.txt"
out="$(sdirt)"
expect "  … a changed, a new and a deleted code file are dirt" "$out" "" DIRTY yes
{ printf '%s\n' "$out" | grep -qxF 'DIRT= M sub/src/code.txt' && printf '%s\n' "$out" | grep -qxF 'DIRT=?? sub/src/new.txt' && printf '%s\n' "$out" | grep -qxF 'DIRT=D  sub/src/old.txt'; } \
  && ok "  … each named on a DIRT line, by repository-relative path" || bad "  … DIRT lines: $(printf '%s' "$out" | tr '\n' '|')"
[[ "$(printf '%s\n' "$out" | grep -c '^DIRT=')" == 3 ]] && ok "  … and nothing else (3 DIRT lines, CRAFT's files stay out)" || bad "  … more than the three code changes counted: $(printf '%s' "$out" | tr '\n' '|')"
out="$(cd "$SD/proj/sub" && CLAUDE_PROJECT_DIR="$SD/proj/sub" /bin/bash "$DIRT" --checkout "$SW" --scope slice-worktree 2>&1)"
{ [[ "$out" == *DIRTY=yes* ]] && ! grep -qE 'syntax error|command not found|unbound variable|bad substitution|line [0-9]+:' <<<"$out"; } \
  && ok "  … a /bin/bash run of the new scope prints no shell error (the helper stays bash-3.2-compatible)" || bad "  … /bin/bash run: $(printf '%s' "$out" | tr '\n' '|')"

# doubt means dirt: without the list the helper errors, and execute-resume-state.sh counts that as dirt
fixture; splan slice-001 a planning
mkdir -p "$TMP/lonely"; cp "$DIRT" "$HELPER" "$TMP/lonely/"
(cd "$P" && bash "$TMP/lonely/tree-dirt-state.sh" >/dev/null 2>&1); rc=$?
[[ "$rc" == 5 ]] && ok "tree-dirt-state.sh without ensure-gitignore.sh → exit 5" || bad "tree-dirt-state.sh without ensure-gitignore.sh → exit 5 (got $rc)"
out="$(cd "$P" && bash "$TMP/lonely/execute-resume-state.sh" --mode sequential "$S1" 2>&1)"
expect "  … execute-resume-state.sh then reports the tree dirty" "$out" "" DIRTY yes
(cd "$P" && bash "$DIRT" --scope everything >/dev/null 2>&1); rc=$?
[[ "$rc" == 2 ]] && ok "tree-dirt-state.sh: invalid scope → exit 2" || bad "tree-dirt-state.sh: invalid scope → exit 2 (got $rc)"
mkdir -p "$TMP/nogit"
(cd "$TMP/nogit" && GIT_CEILING_DIRECTORIES="$TMP" bash "$DIRT" >/dev/null 2>&1); rc=$?
[[ "$rc" == 3 ]] && ok "tree-dirt-state.sh outside a git repository → exit 3" || bad "tree-dirt-state.sh outside a git repository → exit 3 (got $rc)"

# after s0 has landed a slice (B13): what /craft:commit leaves behind decides the next re-run
fixture                                    # plans gitignored
splan slice-002 b planning
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"
out="$(run --mode sequential slice-001 "$S2")"
expect "post-s0, archive left uncommitted (the old commit) → still dirt" "$out" "" RESULT_REASON dirty_without_open_slice
git -C "$P" add .claude/project/slices/slice-001-a.md; git -C "$P" commit -q -m "docs(slices): archive slice-001 (a)"
out="$(run --mode sequential slice-001 "$S2")"
expect "post-s0, archive committed by Step 5b → no run-wide conflict" "$out" "" RESULT_REASON -
expect "  … slice-001 skipped as archived"        "$out" "SLICE=slice-001" REASON archived
expect "  … slice-002 created"                    "$out" "SLICE=slice-002" ACTION create

fixture                                    # plans tracked, protected main: Step 7 only stages the deletion
git -C "$P" rm -q --cached .gitignore; rm "$P/.gitignore"
splan slice-001 a awaiting-approval; splan slice-002 b planning; git -C "$P" add -A; git -C "$P" commit -q -m plans
printf '# archive\n' > "$P/.claude/project/slices/slice-001-a.md"; git -C "$P" add -A; git -C "$P" commit -q -m "merge PR"
printf '> PR: #7\n' >> "$P/$S1"                # the plan carries its uncommitted status edits by Step 7
if git -C "$P" rm -q "$P/$S1" 2>/dev/null; then bad "  (fixture: plain git rm should refuse a modified plan)"; else ok "plain git rm refuses a tracked plan with local edits — Step 7 needs -f"; fi
git -C "$P" rm -q -f "$P/$S1"
out="$(run --mode sequential --landing pull-request slice-001 "$S2")"
expect "post-s0 under protected main, tracked plan deletion staged → no run-wide conflict" "$out" "" RESULT_REASON -
expect "  … DIRTY no"                             "$out" "" DIRTY no

grep -qF '### Step 5b — Commit the record' "$REPO_ROOT/commands/commit.md" \
  && awk '/^### Step 5b/{f=1} /^### Step 6/{f=0} f' "$REPO_ROOT/commands/commit.md" | grep -qF 'docs(slices): archive slice-<NNN>' \
  && ok "commands/commit.md commits the archive in Step 5b, before Step 6 lands" \
  || bad "commands/commit.md has no Step 5b committing the archive before Step 6"
step5b="$(awk '/^### Step 5b/{f=1} /^### Step 6/{f=0} f' "$REPO_ROOT/commands/commit.md")"
grep -qF 'git commit -m "…" -- <files>' <<<"$step5b" && ok "  … with a pathspec, so nothing the human staged goes along" || bad "  … Step 5b commits without a pathspec"
step7="$(awk '/^### Step 7 /{f=1} /^### Step 7b/{f=0} f' "$REPO_ROOT/commands/commit.md")"
{ grep -qF 'git rm -f' <<<"$step7" && grep -qF '"chore(plans): close slice-<NNN>" -- <plan paths>' <<<"$step7"; } \
  && ok "commands/commit.md Step 7 removes a tracked plan with git rm -f and commits it with a pathspec" || bad "commands/commit.md Step 7: tracked plan removal lacks -f or the pathspec commit"

# slice-067: the plan guard is epic-only, and step 1c says so
step1c_pin="$(awk '/^### 1c\./{f=1} /^### 2\./{f=0} f' "$EXECUTE")"
{ [[ "$step1c_pin" == *plan_not_committed* ]] && [[ "$step1c_pin" == *'epic line'* ]] && [[ "$step1c_pin" != *'a new worktree is a checkout of its base, so an uncommitted, ignored or edited plan would reach'* ]]; } \
  && ok "commands/execute.md step 1c names plan_not_committed for the epic line only" || bad "commands/execute.md step 1c still gives plan_not_committed to a slice (or never says it is an epic-line reason)"

# the commands judge "clean" through the helper, never by a porcelain call of their own
for cmd in execute commit release; do
  f="$REPO_ROOT/commands/$cmd.md"
  grep -qF 'scripts/tree-dirt-state.sh' "$f" && ok "commands/$cmd.md judges the tree through tree-dirt-state.sh" || bad "commands/$cmd.md never calls tree-dirt-state.sh"
  if grep -qF 'git status --porcelain' "$f"; then bad "commands/$cmd.md still prescribes git status --porcelain"; else ok "  … and no porcelain call of its own"; fi
done

echo "── arguments and exit codes ─────────────────────────────────────────"

fixture; eplan; splan slice-001 a planning
exit_of() { (cd "$P" && bash "$HELPER" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
[[ "$(exit_of --bogus "$S1")" == 2 ]] && ok "unknown argument → exit 2" || bad "unknown argument → exit 2"
[[ "$(exit_of)" == 2 ]] && ok "no plan → exit 2" || bad "no plan → exit 2"
[[ "$(exit_of --mode serial "$S1")" == 2 ]] && ok "invalid mode → exit 2" || bad "invalid mode → exit 2"
[[ "$(exit_of --mode sequential --epic "$EPIC" "$S1")" == 2 ]] && ok "--epic in sequential mode → exit 2" || bad "--epic in sequential mode → exit 2"
[[ "$(exit_of --trunk)" == 2 ]] && ok "option without value → exit 2" || bad "option without value → exit 2"
[[ "$(exit_of .claude/plans/nope.md)" == 4 ]] && ok "missing plan file without an archive → exit 4" || bad "missing plan file without an archive → exit 4"
[[ "$(exit_of slice-099)" == 4 ]] && ok "unknown slice-ID → exit 4" || bad "unknown slice-ID → exit 4"
mkdir -p "$TMP/nogit"
(cd "$TMP/nogit" && GIT_CEILING_DIRECTORIES="$TMP" bash "$HELPER" x.md >/dev/null 2>&1); rc=$?
[[ "$rc" == 3 ]] && ok "outside a git repository → exit 3" || bad "outside a git repository → exit 3 (got $rc)"

echo "── the action table is described once ───────────────────────────────"

# every action=reason row appears in the helper's header comment table
missing=""
while IFS= read -r row; do
  mode="${row%%:*}"; rest="${row#*:}"; reason="${rest%%=*}"; action="${rest#*=}"
  grep -qE "^#.*[[:space:]]${action}[[:space:]]+${reason}\$" "$HELPER" || missing+=" ${mode}:${reason}"
done < <(bash "$HELPER" --print-actions)
[[ -z "$missing" ]] && ok "header comment lists every action=reason row" || bad "header comment lacks:${missing}"

# commands/execute.md handles every action value the helper can emit
missing=""
for action in $(bash "$HELPER" --print-actions | sed 's/.*=//' | sort -u); do
  grep -qF "ACTION=${action}" "$EXECUTE" || missing+=" ${action}"
done
[[ -z "$missing" ]] && ok "commands/execute.md handles every ACTION value" || bad "commands/execute.md never handles ACTION=:${missing}"

# every conflict REASON has its fix in commands/execute.md step 1c (the section up to step 2)
step1c="$(awk '/^### 1c\./{f=1} /^### 2\./{f=0} f' "$EXECUTE")"
missing=""
for reason in $(bash "$HELPER" --print-actions | sed -n 's/^[a-z]*:\([a-z_]*\)=conflict$/\1/p' | sort -u); do
  grep -qF "\`${reason}\`" <<<"$step1c" || missing+=" ${reason}"
done
[[ -n "$step1c" && -z "$missing" ]] && ok "step 1c names a fix for every conflict REASON" || bad "step 1c has no fix for:${missing}"

echo
echo "RESULT: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
