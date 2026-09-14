#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-plan-landing.sh — self-contained tests for the tracked-plan landing helper
# (plan-landing.sh, slice-040).
#
# No test runner exists in this repo (plugin assets, not runtime software), so this
# harness stands alone: each case builds a throwaway project with a local bare repository
# as `origin`, lands a slice the way /craft:commit does under `pull-request` +
# `Protected-main: yes` (the approved `gh pr merge` simulated by a merge pushed from a second
# clone), drives the helper and asserts on git's own state. It also pins the two git
# behaviors the helper exists for, checks that a fresh clone reads the landed slice as landed
# (scripts/execute-resume-state.sh), and binds the helper to commands/commit.md. Run it directly:
#
#   bash scripts/test-plan-landing.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/plan-landing.sh"
RESUME="$SCRIPT_DIR/execute-resume-state.sh"
COMMIT="$REPO_ROOT/commands/commit.md"
for f in "$RESUME" "$COMMIT"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { # name command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}
refute() { # name command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$name"; else ok "$name"; fi
}

TMP="$(mktemp -d)"
TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR

PLAN=".claude/plans/slice-001-a.md"
ARCHIVE=".claude/project/slices/slice-001-a.md"
N=0
C=""   # the case directory
P=""   # the project's main checkout
fixture() { # fresh project tracking its plans, pushed to a bare origin; the slice plan is committed on main
  N=$((N + 1)); C="$TMP/c$N"; P="$C/proj"
  mkdir -p "$C"
  git init -q --bare -b main "$C/origin.git"
  git clone -q "$C/origin.git" "$P" 2>/dev/null
  git -C "$P" checkout -q -b main 2>/dev/null
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
  printf '# Slice — fixture\n\n> Status: planning\n> Slice-ID: slice-001\n> Slice-Slug: a\n' > "$P/$PLAN"
  printf 'base\n' > "$P/app.txt"; printf 'mine\n' > "$P/human.txt"
  git -C "$P" add . && git -C "$P" commit -q -m init && git -C "$P" push -q -u origin main 2>/dev/null
}
status_to() { sed -i.bak "s/^> Status: .*/> Status: $1/" "$P/$PLAN" && rm -f "$P/$PLAN.bak"; }
build_in_place() { # the slice built on its branch in the main checkout, work + archive committed (Steps 3, 5b)
  git -C "$P" checkout -q -b slice-001-a
  status_to committing
  printf 'work\n' >> "$P/app.txt"
  git -C "$P" commit -q -m "feat: work" -- app.txt
  printf '# Slice 001 — archive\n' > "$P/$ARCHIVE"
  git -C "$P" add -- "$ARCHIVE" && git -C "$P" commit -q -m "docs(slices): archive slice-001" -- "$ARCHIVE"
}
gh_clone() { [[ -d "$C/gh" ]] || git clone -q "$C/origin.git" "$C/gh" 2>/dev/null; git -C "$C/gh" pull -q --ff-only 2>/dev/null; }
merge_on_remote() { # branch — the approved PR merged on GitHub: a --no-ff merge pushed from another clone
  gh_clone
  git -C "$C/gh" fetch -q origin 2>/dev/null
  git -C "$C/gh" merge -q --no-ff "origin/$1" -m "Merge pull request #1" && git -C "$C/gh" push -q origin main 2>/dev/null
}
other_pr_on_remote() { # another PR landed on the trunk afterwards, changing human.txt
  gh_clone
  printf 'changed by another PR\n' >> "$C/gh/human.txt"
  git -C "$C/gh" commit -q -am "Merge pull request #2" && git -C "$C/gh" push -q origin main 2>/dev/null
}
run() { (cd "$P" && bash "$HELPER" "$@" 2>&1); }
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }   # a KEY= anywhere on a line
expect() { # name output key want
  local got; got="$(field "$2" "$3")"
  if [[ "$got" == "$4" ]]; then ok "$1"; else bad "$1 — $3=$got, want $4"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}
tracked_in() { git -C "$P" cat-file -e "$1:$PLAN" 2>/dev/null; }
nothing_staged_but_human() { [[ "$(git -C "$P" diff --cached --name-only)" == "human.txt" ]]; }
nothing_staged() { [[ -z "$(git -C "$P" diff --cached --name-only)" ]]; }

echo "── why the helper exists: git facts ─────────────────────────────────"

fixture; build_in_place
git -C "$P" rm -q --cached -- "$PLAN"
git -C "$P" commit -q -m close -- "$PLAN" 2>/dev/null
check "git rm --cached + pathspec commit re-tracks the plan from disk (no deletion committed)" tracked_in HEAD

fixture; build_in_place
mv "$P/$PLAN" "$C/aside" && git -C "$P" commit -q -m close -- "$PLAN" && mv "$C/aside" "$P/$PLAN"
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
refute "an untracked plan copy makes the checkout to a trunk that tracks it abort" git -C "$P" checkout -q main
check  "  … and leaves the checkout on the slice branch" test "$(git -C "$P" branch --show-current)" = slice-001-a

echo "── close: the deletion rides in the PR (first pass) ─────────────────"

[[ -f "$HELPER" ]] || bad "helper exists: $HELPER"

fixture; build_in_place
printf 'staged by the human\n' >> "$P/human.txt"; git -C "$P" add human.txt
out="$(run close --message "chore(plans): close slice-001" --keep-copy "$PLAN")"
expect "close --keep-copy → RESULT ok"                      "$out" RESULT ok
refute "  … the branch no longer tracks the plan"           tracked_in HEAD
check  "  … the commit holds the plan's deletion alone"     test "$(git -C "$P" show --name-status --format= HEAD)" = "D	$PLAN"
check  "  … the copy stays on disk"                         test -f "$P/$PLAN"
check  "  … untracked"                                      test "$(git -C "$P" status --porcelain -- "$PLAN")" = "?? $PLAN"
check  "  … the human's staged change stays staged, uncommitted" nothing_staged_but_human
expect "  … COMMIT names HEAD"                              "$out" COMMIT "$(git -C "$P" rev-parse HEAD)"

fixture; build_in_place
out="$(run close --message "chore(plans): close slice-001" "$PLAN")"
expect "close without --keep-copy → RESULT ok"              "$out" RESULT ok
check  "  … the plan is gone from disk"                     test ! -e "$P/$PLAN"
check  "  … nothing left staged"                            nothing_staged

fixture; build_in_place
git -C "$P" commit -q -m "chore: plan committed by an old Step 1" -- "$PLAN"
status_to awaiting-approval
out="$(run close --message "chore(plans): close slice-001" --keep-copy "$PLAN")"
expect "plan committed on the branch and edited again (R2-6) → close still RESULT ok" "$out" RESULT ok
refute "  … deletion committed"                             tracked_in HEAD
check  "  … the copy keeps its latest edit"                 grep -q 'awaiting-approval' "$P/$PLAN"

fixture
git -C "$P" checkout -q -b slice-001-a
printf '# other\n' > "$P/.claude/plans/slice-002-b.md"; git -C "$P" add .claude/plans/slice-002-b.md
out="$(run close --message x .claude/plans/slice-002-b.md)"
expect "close on a plan HEAD does not track (staged only) → RESULT ok" "$out" RESULT ok
expect "  … CLOSED=no"                                      "$out" CLOSED no
expect "  … COMMIT=-"                                       "$out" COMMIT -
check  "  … nothing committed"                              test "$(git -C "$P" rev-list --count HEAD)" = 1
check  "  … the file is untouched and still staged"         test -f "$P/.claude/plans/slice-002-b.md" -a "$(git -C "$P" diff --cached --name-only)" = .claude/plans/slice-002-b.md

fixture; build_in_place
printf '# sibling\n' > "$P/.claude/plans/slice-002-b.md"
out="$(run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" .claude/plans/slice-002-b.md)"
check  "tracked and untracked plans together → only the tracked one is closed" \
  test "$(git -C "$P" show --name-status --format= HEAD)" = "D	$PLAN"
check  "  … per-plan CLOSED lines"                          bash -c "grep -q '^PLAN=$PLAN CLOSED=yes' <<<\"\$1\" && grep -q '^PLAN=.claude/plans/slice-002-b.md CLOSED=no' <<<\"\$1\"" _ "$out"

fixture; build_in_place
printf 'staged by the human\n' >> "$P/human.txt"; git -C "$P" add human.txt
printf '#!/bin/sh\necho "lint says no" >&2\nexit 1\n' > "$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
head_before="$(git -C "$P" rev-parse HEAD)"
out="$(run close --message "chore(plans): close slice-001" --keep-copy "$PLAN")"
expect "a failing pre-commit hook → ERROR commit_failed"   "$out" ERROR commit_failed
check  "  … git's own reason is surfaced"                   bash -c 'grep -q "lint says no" <<<"$1"' _ "$out"
check  "  … HEAD unchanged"                                 test "$(git -C "$P" rev-parse HEAD)" = "$head_before"
check  "  … the plan copy is back, still tracked"           test -f "$P/$PLAN" -a -z "$(git -C "$P" ls-files --deleted -- "$PLAN")"
check  "  … the human's staged change stays staged, no deletion staged" nothing_staged_but_human

fixture; build_in_place
out="$(run close --keep-copy "$PLAN")"
expect "close without --message → ERROR"                    "$out" ERROR "missing_value:--message"

echo "── sync: the trunk after the approved merge (second pass) ───────────"

fixture; build_in_place
printf 'staged by the human\n' >> "$P/human.txt"; git -C "$P" add human.txt
run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" >/dev/null
status_to awaiting-approval
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
out="$(run sync --trunk main "$PLAN")"
expect "in-place: sync → RESULT ok (R1-2)"                  "$out" RESULT ok
check  "  … on the trunk"                                   test "$(git -C "$P" branch --show-current)" = main
check  "  … local trunk equals origin/main"                 test "$(git -C "$P" rev-parse main)" = "$(git -C "$P" rev-parse origin/main)"
check  "  … the plan is gone from disk"                     test ! -e "$P/$PLAN"
check  "  … no staged deletion — only the human's change"   nothing_staged_but_human
refute "  … origin/main does not track the plan"            tracked_in origin/main
check  "  … origin/main holds the archive"                  git -C "$P" cat-file -e "origin/main:$ARCHIVE"
expect "  … ON_TRUNK=no"                                    "$out" ON_TRUNK no
git clone -q "$C/origin.git" "$C/fresh" 2>/dev/null
out="$(cd "$C/fresh" && bash "$RESUME" slice-001 2>&1)"
check  "fresh clone of origin: execute-resume-state reads slice-001 as archived" \
  bash -c "printf '%s\n' \"\$1\" | grep -q '^SLICE=slice-001 .*ACTION=skip REASON=archived'" _ "$out"

fixture; build_in_place
git -C "$P" commit -q -m "chore: plan committed by an old Step 1" -- "$PLAN"
run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" >/dev/null
status_to awaiting-approval
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
out="$(run sync --trunk main "$PLAN")"
expect "close, then sync, after an old Step 1 committed the plan on the branch → RESULT ok" "$out" RESULT ok
check  "  … on the trunk, plan gone"                        test "$(git -C "$P" branch --show-current)" = main -a ! -e "$P/$PLAN"
# the restore of a tracked, edited plan (R2-6's abort) is guarded by the finalize case below: without it the ff aborts

fixture
git -C "$P" checkout -q -b slice-001-a
printf 'work\n' >> "$P/app.txt"; git -C "$P" commit -q -m feat -- app.txt
( cd "$P" && git rm -q -- "$PLAN" && git commit -q -m "chore(plans): close slice-001" -- "$PLAN" )
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
git -C "$P" checkout -q main
status_to awaiting-approval
check  "(fixture: finalize — the main checkout's tracked plan carries a status edit)" test -n "$(git -C "$P" status --porcelain -- "$PLAN")"
out="$(run sync --trunk main "$PLAN")"
expect "finalize: tracked, modified plan on the trunk → sync RESULT ok" "$out" RESULT ok
check  "  … plan gone, nothing staged, trunk = origin"      test ! -e "$P/$PLAN" -a -z "$(git -C "$P" diff --cached --name-only)" -a "$(git -C "$P" rev-parse main)" = "$(git -C "$P" rev-parse origin/main)"

fixture
printf '.claude/plans/\n' > "$P/.gitignore"; git -C "$P" rm -q --cached -- "$PLAN"; git -C "$P" add .gitignore
git -C "$P" commit -q -m "untrack plans" && git -C "$P" push -q 2>/dev/null
git -C "$P" checkout -q -b slice-001-a; printf 'work\n' >> "$P/app.txt"; git -C "$P" commit -q -m feat -- app.txt
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
out="$(run sync --trunk main "$PLAN")"
expect "plans not tracked (ignored): sync → RESULT ok"      "$out" RESULT ok
check  "  … the plan is removed, like the plain rm it replaces" test ! -e "$P/$PLAN"

fixture; build_in_place
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
status_to awaiting-approval
out="$(run sync --trunk main "$PLAN")"
expect "a PR that did not carry the deletion → RESULT ok"   "$out" RESULT ok
expect "  … ON_TRUNK=yes (the trunk still tracks the plan)" "$out" ON_TRUNK yes
check  "  … nothing staged"                                 nothing_staged
check  "  … the stale plan is removed from disk, an unstaged deletion" test "$(git -C "$P" status --porcelain -- "$PLAN")" = " D $PLAN"
out="$(cd "$P" && bash "$RESUME" slice-001 2>&1)"
check  "  … so the checkout reads slice-001 as archived, not as a slice to build" \
  bash -c "printf '%s\n' \"\$1\" | grep -q '^SLICE=slice-001 .*ACTION=skip REASON=archived'" _ "$out"

echo "── sync never loses the live plan ───────────────────────────────────"

fixture; build_in_place
run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" >/dev/null
status_to awaiting-approval
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
git -C "$P" update-ref refs/heads/main "$(git -C "$P" commit-tree -p main -m local-only 'main^{tree}')"
out="$(run sync --trunk main "$PLAN")"
expect "local trunk diverged from origin → ERROR trunk_diverged" "$out" ERROR "trunk_diverged:main"
check  "  … still on the slice branch"                      test "$(git -C "$P" branch --show-current)" = slice-001-a
check  "  … the plan copy keeps awaiting-approval"          grep -q 'awaiting-approval' "$P/$PLAN"

fixture; build_in_place
run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" >/dev/null
status_to awaiting-approval
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
other_pr_on_remote                         # another PR changed human.txt on the trunk …
printf 'my edit\n' >> "$P/human.txt"       # … which the human is editing, uncommitted
out="$(run sync --trunk main "$PLAN")"
expect "in-place: moving to the trunk fails on a human change → ERROR checkout_failed" "$out" ERROR "checkout_failed:main"
check  "  … git's reason names the blocking file"           bash -c 'grep -q "human.txt" <<<"$1"' _ "$out"
check  "  … still on the slice branch (R1-1: no half-done move)" test "$(git -C "$P" branch --show-current)" = slice-001-a
check  "  … the plan copy is back, untracked, with awaiting-approval" \
  test "$(git -C "$P" status --porcelain -- "$PLAN")" = "?? $PLAN" -a -n "$(grep -l awaiting-approval "$P/$PLAN")"
git -C "$P" checkout -q -- human.txt
out="$(run sync --trunk main "$PLAN")"
expect "  … once the human's change is out of the way, a re-run lands" "$out" RESULT ok
check  "  … on the trunk = origin, plan gone"               test "$(git -C "$P" branch --show-current)" = main -a ! -e "$P/$PLAN" -a "$(git -C "$P" rev-parse main)" = "$(git -C "$P" rev-parse origin/main)"

fixture
git -C "$P" checkout -q -b slice-001-a
printf 'work\n' >> "$P/app.txt"; git -C "$P" commit -q -m feat -- app.txt
( cd "$P" && git rm -q -- "$PLAN" && git commit -q -m "chore(plans): close slice-001" -- "$PLAN" )
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
git -C "$P" checkout -q main
other_pr_on_remote
status_to awaiting-approval; printf 'my edit\n' >> "$P/human.txt"
out="$(run sync --trunk main "$PLAN")"
expect "finalize: the fast-forward fails on a human change → ERROR ff_failed" "$out" ERROR "ff_failed:main"
check  "  … still on the trunk, not advanced"               test "$(git -C "$P" branch --show-current)" = main -a "$(git -C "$P" rev-parse main)" != "$(git -C "$P" rev-parse origin/main)"
check  "  … the tracked plan keeps its awaiting-approval edit" grep -q 'awaiting-approval' "$P/$PLAN"

fixture; build_in_place
run close --message "chore(plans): close slice-001" --keep-copy "$PLAN" >/dev/null
status_to awaiting-approval
git -C "$P" push -q -u origin slice-001-a 2>/dev/null; merge_on_remote slice-001-a
mkdir -p "$C/shim"
REAL_GIT="$(command -v git)"
printf '#!/usr/bin/env bash\nif [[ "$1" == checkout && "$2" == -q && "$3" == -B ]]; then kill -TERM "$PPID"; sleep 1; exit 1; fi\nexec "%s" "$@"\n' "$REAL_GIT" > "$C/shim/git"
chmod +x "$C/shim/git"
out="$(cd "$P" && PATH="$C/shim:$PATH" bash "$HELPER" sync --trunk main "$PLAN" 2>&1)"
expect "interrupted while moving to the trunk → ERROR interrupted" "$out" ERROR interrupted
check  "  … the held plan copy is back with awaiting-approval" grep -q 'awaiting-approval' "$P/$PLAN"
check  "  … still on the slice branch"                      test "$(git -C "$P" branch --show-current)" = slice-001-a

fixture
out="$(run sync --trunk main --remote nowhere "$PLAN")"
expect "fetch fails → ERROR fetch_failed"                   "$out" ERROR "fetch_failed:nowhere/main"
check  "  … the plan is untouched"                          test -f "$P/$PLAN"

echo "── bound to commands/commit.md ──────────────────────────────────────"

check "commit.md calls plan-landing.sh close"               grep -q 'plan-landing.sh" close' "$COMMIT"
check "commit.md calls plan-landing.sh sync"                grep -q 'plan-landing.sh" sync' "$COMMIT"
refute "commit.md no longer leaves a staged deletion for the human" grep -q 'leave the staged deletion' "$COMMIT"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
