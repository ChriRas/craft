#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-worktree-kinds.sh — self-contained tests for worktree-kinds.sh (slice-078, roadmap B33).
#
# Builds throwaway git repositories with real linked worktrees (slice, epic, detached, foreign branch, a
# custom branch pattern, a prunable one, a path with a space), runs the helper and asserts its key=value
# output and exit code. Then pins the sites that read it — commands/commit.md's Mode Detection step 0 and
# step 1, Step 7's In-place-finalize and the line naming a foreign worktree, commands/execute.md's
# post-assertions P5–P7, with the old predicate held out even when wrapped across lines — and proves
# the pins bite on mutated copies. It also pins what slice-079 made of A6: it reads the mode Mode Detection found
# (steps 1–2 run before it), and step 2 names each CRAFT worktree that is no finalize target. Run it directly:
#
#   bash scripts/test-worktree-kinds.sh
#
# It writes nothing outside its own mktemp fixture (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/worktree-kinds.sh"
COMMIT_MD="$REPO_ROOT/commands/commit.md"
EXECUTE_MD="$REPO_ROOT/commands/execute.md"
[[ -f "$HELPER" ]] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }
[[ -f "$COMMIT_MD" ]] || { echo "FATAL: commands/commit.md not found at $COMMIT_MD" >&2; exit 2; }
[[ -f "$EXECUTE_MD" ]] || { echo "FATAL: commands/execute.md not found at $EXECUTE_MD" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: git prints worktree paths resolved (/var → /private/var on macOS)
trap 'rm -rf "$FIX"' EXIT

g() { git -c user.name=t -c user.email=t@t "$@"; }

# A fresh main repository with one commit, no linked worktree.
setup() {
  rm -rf "$FIX/main" "$FIX/wt"
  mkdir -p "$FIX/main" "$FIX/wt"
  g -C "$FIX/main" init -q -b main
  printf 'x\n' > "$FIX/main/file"
  g -C "$FIX/main" add -A
  g -C "$FIX/main" commit -q -m fixture
}
add_branch()   { g -C "$FIX/main" worktree add -q -b "$1" "$2" >/dev/null 2>&1; }   # <new-branch> <path>
add_detached() { g -C "$FIX/main" worktree add -q --detach "$1" >/dev/null 2>&1; }   # <path>

# run [<dir>] → OUT (stdout), ERR (stderr), RC; the helper runs from <dir> (default: the main checkout)
run() {
  local dir="${1:-$FIX/main}"
  OUT="$(cd "$dir" && CLAUDE_PROJECT_DIR= bash "$HELPER" 2>"$FIX/err")"
  RC=$?
  ERR="$(cat "$FIX/err")"
}
has()   { printf '%s\n' "$OUT" | grep -qxF "$1"; }
lines() { printf '%s\n' "$OUT" | grep -c '^KIND=' ; }

echo "CLASSIFICATION:"
setup
run
{ [[ $RC -eq 0 ]] && has "CRAFT_COUNT=0" && has "FOREIGN_COUNT=0" && [[ "$(lines)" -eq 0 ]]; } \
  && ok "main worktree only → no lines, both counts 0, exit 0" || bad "main only (rc=$RC, out=$OUT)"

setup
add_branch slice-012-x "$FIX/wt/slice-012-x"
add_branch epic-003-y  "$FIX/wt/epic-003-y"
run
{ [[ $RC -eq 0 ]] && has "KIND=craft BRANCH=slice-012-x WORKTREE=$FIX/wt/slice-012-x" \
  && has "KIND=craft BRANCH=epic-003-y WORKTREE=$FIX/wt/epic-003-y" \
  && has "CRAFT_COUNT=2" && has "FOREIGN_COUNT=0" && [[ "$(lines)" -eq 2 ]]; } \
  && ok "slice and epic worktrees → craft, main itself not listed" || bad "slice + epic (rc=$RC, out=$OUT)"

setup
add_branch slice-012-x "$FIX/wt/slice-012-x"
add_detached "$FIX/wt/CRAFT-runtime-epic-004"
run
{ [[ $RC -eq 0 ]] && has "KIND=foreign BRANCH=(detached) WORKTREE=$FIX/wt/CRAFT-runtime-epic-004" \
  && has "CRAFT_COUNT=1" && has "FOREIGN_COUNT=1"; } \
  && ok "detached worktree (the B33 case: a path that names an epic) → foreign" || bad "detached (rc=$RC, out=$OUT)"

setup
add_branch experiment "$FIX/wt/exp"
run
{ [[ $RC -eq 0 ]] && has "KIND=foreign BRANCH=experiment WORKTREE=$FIX/wt/exp" && has "FOREIGN_COUNT=1"; } \
  && ok "worktree on a branch without a slice/epic token → foreign" || bad "foreign branch (rc=$RC, out=$OUT)"

setup
add_branch feature/slice-012-x "$FIX/wt/custom"
add_branch release/epic-007    "$FIX/wt/custom-epic"
run
{ [[ $RC -eq 0 ]] && has "KIND=craft BRANCH=feature/slice-012-x WORKTREE=$FIX/wt/custom" \
  && has "KIND=craft BRANCH=release/epic-007 WORKTREE=$FIX/wt/custom-epic" && has "CRAFT_COUNT=2"; } \
  && ok "custom branch pattern carrying the ID token → craft" || bad "custom pattern (rc=$RC, out=$OUT)"

setup
add_branch myepic-123   "$FIX/wt/a"
add_branch slice-abc    "$FIX/wt/b"
add_branch slice-0123x  "$FIX/wt/c"
run
{ [[ $RC -eq 0 ]] && has "KIND=foreign BRANCH=myepic-123 WORKTREE=$FIX/wt/a" \
  && has "KIND=foreign BRANCH=slice-abc WORKTREE=$FIX/wt/b" \
  && has "KIND=foreign BRANCH=slice-0123x WORKTREE=$FIX/wt/c" && has "CRAFT_COUNT=0" && has "FOREIGN_COUNT=3"; } \
  && ok "token boundaries: inside a word, without digits, digits run into letters → foreign" || bad "token boundaries (rc=$RC, out=$OUT)"

setup
add_branch slice-020-gone "$FIX/wt/gone"
rm -rf "$FIX/wt/gone"
run
{ [[ $RC -eq 0 ]] && has "KIND=craft BRANCH=slice-020-gone WORKTREE=$FIX/wt/gone" && has "CRAFT_COUNT=1"; } \
  && ok "prunable worktree (directory gone) → classified by its branch" || bad "prunable (rc=$RC, out=$OUT)"

setup
add_detached "$FIX/wt/with space"
run
{ [[ $RC -eq 0 ]] && has "KIND=foreign BRANCH=(detached) WORKTREE=$FIX/wt/with space" && has "FOREIGN_COUNT=1"; } \
  && ok "worktree path with a space → named whole, as the last field" || bad "space in path (rc=$RC, out=$OUT)"

setup
add_branch slice-012-x "$FIX/wt/slice-012-x"
add_detached "$FIX/wt/foreign"
run "$FIX/wt/slice-012-x"
{ [[ $RC -eq 0 ]] && has "KIND=craft BRANCH=slice-012-x WORKTREE=$FIX/wt/slice-012-x" \
  && has "KIND=foreign BRANCH=(detached) WORKTREE=$FIX/wt/foreign" \
  && ! printf '%s\n' "$OUT" | grep -q "WORKTREE=$FIX/main\$" && has "CRAFT_COUNT=1" && has "FOREIGN_COUNT=1"; } \
  && ok "run from inside a linked worktree → the main worktree is still the one left out" || bad "from linked worktree (rc=$RC, out=$OUT)"

setup
add_branch slice-012-x "$FIX/wt/slice-012-x"
mkdir -p "$FIX/main/sub/dir"
OUT="$(cd "$FIX/wt" && CLAUDE_PROJECT_DIR="$FIX/main/sub/dir" bash "$HELPER" 2>/dev/null)"; RC=$?
{ [[ $RC -eq 0 ]] && has "CRAFT_COUNT=1"; } \
  && ok "CLAUDE_PROJECT_DIR in a subdirectory of the repository → read there, not from the cwd" || bad "project dir (rc=$RC, out=$OUT)"

echo "ERRORS:"
mkdir -p "$FIX/nogit"
run "$FIX/nogit"
{ [[ $RC -eq 3 && -z "$OUT" ]] && printf '%s\n' "$ERR" | grep -q '^ERROR=not_a_git_repository:'; } \
  && ok "not a git repository → exit 3, ERROR= on stderr, empty stdout" || bad "no git (rc=$RC, out=$OUT, err=$ERR)"

OUT="$(cd "$FIX/main" && bash "$HELPER" --bogus 2>"$FIX/err")"; RC=$?; ERR="$(cat "$FIX/err")"
{ [[ $RC -eq 2 && -z "$OUT" ]] && printf '%s\n' "$ERR" | grep -q '^ERROR=unknown_argument:--bogus'; } \
  && ok "unknown argument → exit 2, empty stdout" || bad "bad arg (rc=$RC, out=$OUT, err=$ERR)"

OUT="$(CLAUDE_PROJECT_DIR="$FIX/does-not-exist" bash "$HELPER" 2>"$FIX/err")"; RC=$?; ERR="$(cat "$FIX/err")"
{ [[ $RC -eq 3 && -z "$OUT" ]] && printf '%s\n' "$ERR" | grep -q '^ERROR=project_dir_unreachable:'; } \
  && ok "unreachable project dir → exit 3, empty stdout" || bad "unreachable (rc=$RC, out=$OUT, err=$ERR)"

# ---------------------------------------------------------------------------------------------------------
# Pins on commands/commit.md. Each pin reads one region of the file; check_pins <file> prints one FAIL token
# per broken pin, so the same function judges the real file and the mutated copies below.
section() { # <file> <start-regex> <end-regex> — the lines from the first start match up to (not incl.) the next end match
  S="$2" E="$3" awk 'f && $0 ~ ENVIRON["E"] {exit} $0 ~ ENVIRON["S"] {f=1} f' "$1"   # ENVIRON: -v would eat the backslashes
}
# The old predicate may be wrapped across lines (and inside a blockquote) — judge the joined text, never one line.
old_predicate() { sed -E 's/^> ?//' "$1" | tr '\n' ' ' | tr -s ' ' | grep -qiE 'only the (main|primary) worktree'; }
check_pins() {
  local f="$1" a6 step0 step1 step2 inplace intro
  intro="$(section "$f" '^## Pre-Assertions' '^### A0 ')"
  a6="$(section "$f" '^### A6 ' '^(### |---)')"
  step0="$(section "$f" '^0\. \*\*A finished epic\.\*\*' '^1\. ')"
  step1="$(section "$f" '^1\. ' '^2\. ')"
  step2="$(section "$f" '^2\. ' '^When the protected-main')"
  inplace="$(section "$f" '^> \*\*In-place-finalize' '^> - `direct`')"
  # A6 reads the mode Mode Detection found, never a worktree count of its own (slice-079)
  printf '%s\n' "$a6" | grep -q 'Mode Detection found \*\*Standard mode\*\*' \
    && ! printf '%s\n' "$a6" | grep -qE 'CRAFT_COUNT|worktree-kinds' || echo "a6"
  printf '%s\n' "$a6" | grep -q 'When Mode Detection step 2 named CRAFT worktrees' || echo "a6-names"
  printf '%s\n' "$intro" | grep -q 'Mode Detection steps 1–2' && printf '%s\n' "$intro" | grep -q 'A3 and A6 read the mode' || echo "order"
  printf '%s\n' "$step2" | grep -qE '^ *· Worktree <WORKTREE> \(<BRANCH>, plan <STATUS>\) is no finalize target — not finalized by this run$' \
    && printf '%s\n' "$step2" | grep -q 'mode = Standard' || echo "step2"
  printf '%s\n' "$step0" | grep -q 'worktree-kinds\.sh' && printf '%s\n' "$step0" | grep -q 'CRAFT_COUNT=0' || echo "step0"
  printf '%s\n' "$step1" | grep -q 'worktree-kinds\.sh' && printf '%s\n' "$step1" | grep -q 'CRAFT_COUNT=0' || echo "step1"
  printf '%s\n' "$inplace" | grep -q 'worktree-kinds\.sh' && printf '%s\n' "$inplace" | grep -q 'CRAFT_COUNT=0' || echo "inplace"
  grep -q '^· Worktree <WORKTREE> (<BRANCH>) is on no slice or epic branch — ignored' "$f" || echo "foreign-line"
  ! old_predicate "$f" || echo "old-predicate"
}

echo "PINS (commands/commit.md):"
PINS="$(check_pins "$COMMIT_MD")"
for p in order a6 a6-names step0 step1 step2 inplace foreign-line old-predicate; do
  case "$p" in
    order)         label="the Pre-Assertions intro runs Mode Detection steps 1–2 before A3 and A6" ;;
    a6)            label="A6 reads the detected mode (Standard), no worktree count of its own" ;;
    a6-names)      label="A6 repeats the step-2 lines naming the worktrees that are no finalize target" ;;
    step0)         label="Mode Detection step 0 reads the helper (CRAFT_COUNT=0)" ;;
    step1)         label="Mode Detection step 1 reads the helper (CRAFT_COUNT=0)" ;;
    step2)         label="Mode Detection step 2 falls through to Standard and names a non-target worktree" ;;
    inplace)       label="Step 7's In-place-finalize reads the helper (CRAFT_COUNT=0)" ;;
    foreign-line)  label="the · line naming a foreign worktree is there" ;;
    old-predicate) label="no 'only the main/primary worktree' predicate is left (lines joined)" ;;
  esac
  printf '%s\n' "$PINS" | grep -qx "$p" && bad "$label" || ok "$label"
done

check_exec_pins() {
  local f="$1" p
  for p in P5 P6 P7; do
    section "$f" "^### $p " '^(### |---)' | grep -q 'worktree-kinds\.sh.*CRAFT_COUNT=0' || echo "$p"
  done
  ! old_predicate "$f" || echo "old-predicate"
}

echo "PINS (commands/execute.md):"
PINS="$(check_exec_pins "$EXECUTE_MD")"
for p in P5 P6 P7 old-predicate; do
  case "$p" in
    old-predicate) label="no 'only the main/primary worktree' predicate is left (lines joined)" ;;
    *)             label="$p reads the helper (CRAFT_COUNT=0)" ;;
  esac
  printf '%s\n' "$PINS" | grep -qx "$p" && bad "$label" || ok "$label"
done

echo "PIN SELF-TEST (mutated copies must go red):"
mutate() { # <name> <expected-token> <sed-expression> — the copy must fail exactly its pin
  local copy="$FIX/commit-$1.md" got
  sed -E "$3" "$COMMIT_MD" > "$copy"
  got="$(check_pins "$copy")"
  printf '%s\n' "$got" | grep -qx "$2" && ok "correctly RED: $1" || bad "mutation not caught: $1 (pins: ${got:-none})"
}
mutate a6-reads-count         a6            '/^### A6 /,/^---/ s/Mode Detection found \*\*Standard mode\*\*/`worktree-kinds.sh` reports `CRAFT_COUNT=0`/'
mutate a6-count-added         a6            '/^### A6 /,/^---/ s/^(This catches only)/CRAFT_COUNT=0 \1/'
mutate order-removed          order         '/^## Pre-Assertions/,/^### A0 / s/Mode Detection steps 1–2/Mode Detection/'
mutate step2-line-removed     step2         '/is no finalize target — not finalized by this run$/d'
mutate a6-names-removed       a6-names      '/^### A6 /,/^---/ s/When Mode Detection step 2 named CRAFT worktrees/When step 2 listed worktrees/'
mutate step2-standard-removed step2         '/^2\. /,/^When the protected-main/ s/mode = Standard/mode = undecided/'
mutate step0-helper-removed   step0         '/^0\. \*\*A finished epic/,/^1\. / s/worktree-kinds\.sh/worktree-x.sh/g'
mutate step1-count-removed    step1         '/^1\. /,/^2\. / s/CRAFT_COUNT=0/CRAFT_COUNT=1/g'
mutate foreign-line-removed   foreign-line  '/^· Worktree <WORKTREE>/d'
mutate old-predicate-restored old-predicate '1 s/^/shows only the main worktree\n/'
mutate inplace-helper-removed inplace       '/^> \*\*In-place-finalize/,/^> - `direct`/ s/worktree-kinds\.sh/worktree-x.sh/g'
mutate old-predicate-wrapped  old-predicate '1 s/^/> i.e. only the primary\
> worktree exists\
/'
mutate_exec() { # <name> <expected-token> <sed-expression>
  local copy="$FIX/execute-$1.md" got
  sed -E "$3" "$EXECUTE_MD" > "$copy"
  got="$(check_exec_pins "$copy")"
  printf '%s\n' "$got" | grep -qx "$2" && ok "correctly RED: $1" || bad "mutation not caught: $1 (pins: ${got:-none})"
}
mutate_exec p5-helper-removed  P5 '/^### P5 /,/^### P6 / s/worktree-kinds\.sh/worktree-x.sh/g'
mutate_exec p6-helper-removed  P6 '/^### P6 /,/^### P7 / s/worktree-kinds\.sh/worktree-x.sh/g'
mutate_exec p7-count-changed   P7 '/^### P7 /,/^### P8 / s/CRAFT_COUNT=0/CRAFT_COUNT=1/g'
mutate_exec exec-old-predicate old-predicate '1 s/^/shows only the primary worktree /'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
