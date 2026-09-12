#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-plugin-cache-drift.sh — self-contained tests for check-plugin-cache-drift.sh (B2).
#
# Builds a throwaway "dev repo" (a git work tree carrying the plugin manifest) and a
# "cache" copy of its runtime surface under a temp dir, mutates one side per case, and
# asserts the helper's key=value output and exit code. Run it directly:
#
#   bash scripts/test-plugin-cache-drift.sh
#
# It writes nothing outside its own mktemp fixture (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/check-plugin-cache-drift.sh"
[[ -f "$HELPER" ]] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# A fresh repo + identical cache for every case, so no case leaks into the next.
setup() {
  rm -rf "$FIX/repo" "$FIX/cache"
  mkdir -p "$FIX/repo/.claude-plugin" "$FIX/repo/commands" "$FIX/repo/skills/workflow" "$FIX/repo/docs"
  printf '{ "name": "craft", "version": "9.9.9" }\n' > "$FIX/repo/.claude-plugin/plugin.json"
  printf 'build command\n'  > "$FIX/repo/commands/build.md"
  printf 'review command\n' > "$FIX/repo/commands/review.md"
  printf 'workflow skill\n' > "$FIX/repo/skills/workflow/SKILL.md"
  printf 'defaults\n'       > "$FIX/repo/model-defaults.md"
  printf 'readme\n'         > "$FIX/repo/README.md"
  printf 'site\n'           > "$FIX/repo/docs/index.html"
  printf '*.log\n'          > "$FIX/repo/.gitignore"
  git -C "$FIX/repo" init -q
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.name=t -c user.email=t@t commit -q -m fixture
  cp -R "$FIX/repo" "$FIX/cache"
  rm -rf "$FIX/cache/.git"
}

# run <project> <plugin-root> → sets OUT and RC
run() {
  OUT="$(bash "$HELPER" --project "$1" --plugin-root "$2" 2>&1)"
  RC=$?
}
has() { printf '%s\n' "$OUT" | grep -qxF "$1"; }

echo "IN-SYNC:"
setup
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 0 ]] && has "STATUS=in-sync" && has "RUNTIME=cache" && has "DIFF_COUNT=0"; } \
  && ok "identical runtime surface → in-sync, exit 0" || bad "identical trees (rc=$RC, out=$OUT)"

echo "DIVERGED:"
setup
printf 'build command, changed\n' > "$FIX/repo/commands/build.md"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 10 ]] && has "STATUS=diverged" && has "DIFF_COUNT=1" && has "DIFF=modified:commands/build.md"; } \
  && ok "uncommitted edit under commands/ → diverged, file named, exit 10" || bad "modified file (rc=$RC, out=$OUT)"

setup
printf 'new command\n' > "$FIX/repo/commands/autopilot.md"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 10 ]] && has "STATUS=diverged" && has "DIFF=added:commands/autopilot.md"; } \
  && ok "runtime file only in the repo → diverged, listed as added" || bad "repo-only file (rc=$RC, out=$OUT)"

setup
rm "$FIX/repo/commands/review.md"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 10 ]] && has "DIFF=removed:commands/review.md"; } \
  && ok "runtime file deleted in the repo → diverged, listed as removed" || bad "deleted file (rc=$RC, out=$OUT)"

setup
printf 'defaults, changed\n' > "$FIX/repo/model-defaults.md"
mkdir -p "$FIX/repo/workflows"; printf 'wf\n' > "$FIX/repo/workflows/run.js"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 10 ]] && has "DIFF_COUNT=2" && has "DIFF=modified:model-defaults.md" && has "DIFF=added:workflows/run.js"; } \
  && ok "root runtime file + a not-yet-existing component dir are both covered" || bad "root file / new component (rc=$RC, out=$OUT)"

echo "NO FALSE POSITIVES:"
setup
printf 'readme, changed\n' > "$FIX/repo/README.md"
printf 'site, changed\n'   > "$FIX/repo/docs/index.html"
printf 'noise\n'           > "$FIX/repo/commands/debug.log"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 0 ]] && has "STATUS=in-sync"; } \
  && ok "docs-only edits and a gitignored file under commands/ stay in-sync" || bad "doc/ignored noise (rc=$RC, out=$OUT)"

echo "NOT A DEV REPO:"
setup
printf '{ "name": "other-plugin" }\n' > "$FIX/repo/.claude-plugin/plugin.json"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 0 ]] && has "STATUS=not-dev-repo"; } \
  && ok "foreign plugin name → not-dev-repo, exit 0" || bad "foreign name (rc=$RC, out=$OUT)"

setup
rm -rf "$FIX/repo/.claude-plugin"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 0 ]] && has "STATUS=not-dev-repo"; } \
  && ok "project without .claude-plugin/plugin.json → not-dev-repo, exit 0" || bad "no manifest (rc=$RC, out=$OUT)"

echo "WORKING TREE RUNTIME:"
setup
printf 'build command, changed\n' > "$FIX/repo/commands/build.md"
run "$FIX/repo" "$FIX/repo"
{ [[ $RC -eq 0 ]] && has "STATUS=in-sync" && has "RUNTIME=working-tree"; } \
  && ok "plugin root is the project itself (--plugin-dir) → in-sync, runtime=working-tree" || bad "plugin root = project (rc=$RC, out=$OUT)"

echo "UNKNOWN:"
setup
run "$FIX/repo" "$FIX/does-not-exist"
{ [[ $RC -eq 3 ]] && has "STATUS=unknown" && printf '%s\n' "$OUT" | grep -q '^REASON=plugin root not found'; } \
  && ok "missing cache path → unknown with reason, exit 3" || bad "missing plugin root (rc=$RC, out=$OUT)"

setup
printf 'not an index\n' > "$FIX/repo/.git/index"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 3 ]] && has "STATUS=unknown" && ! printf '%s\n' "$OUT" | grep -q '^DIFF=removed:'; } \
  && ok "failing git ls-files (corrupt index) → unknown, never a false all-removed diverged" || bad "git failure (rc=$RC, out=$OUT)"

setup
mkdir -p "$FIX/cache/commands/locked"; printf 'x\n' > "$FIX/cache/commands/locked/a.md"
chmod 000 "$FIX/cache/commands/locked"
run "$FIX/repo" "$FIX/cache"
chmod 755 "$FIX/cache/commands/locked"
{ [[ $RC -eq 3 ]] && has "STATUS=unknown" && ! printf '%s\n' "$OUT" | grep -q '^DIFF='; } \
  && ok "unreadable directory in the cache → unknown, never a partial diff" || bad "unreadable cache dir (rc=$RC, out=$OUT)"

setup
chmod 000 "$FIX/cache/commands/build.md"
run "$FIX/repo" "$FIX/cache"
chmod 644 "$FIX/cache/commands/build.md"
{ [[ $RC -eq 3 ]] && has "STATUS=unknown" && ! has "DIFF=modified:commands/build.md"; } \
  && ok "unreadable file (cmp exit 2) → unknown, not reported as modified" || bad "unreadable cache file (rc=$RC, out=$OUT)"

setup
nl_name="$FIX/repo/commands/new"$'\n'"line.md"
printf 'x\n' > "$nl_name"; printf 'x\n' > "$FIX/cache/commands/new"$'\n'"line.md"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 3 ]] && has "STATUS=unknown"; } \
  && ok "file name containing a newline → unknown, not a false two-file diff" || bad "newline file name (rc=$RC, out=$OUT)"

echo "SYMMETRY:"
setup
ln -s build.md "$FIX/repo/commands/alias.md"
git -C "$FIX/repo" add commands/alias.md
git -C "$FIX/repo" -c user.name=t -c user.email=t@t commit -q -m symlink
ln -s build.md "$FIX/cache/commands/alias.md"
printf 'finder\n' > "$FIX/repo/commands/.DS_Store"
printf 'finder\n' > "$FIX/cache/skills/.DS_Store"
run "$FIX/repo" "$FIX/cache"
{ [[ $RC -eq 0 ]] && has "STATUS=in-sync"; } \
  && ok "tracked symlink on both sides + unignored .DS_Store on either side → in-sync" || bad "symlink/.DS_Store symmetry (rc=$RC, out=$OUT)"

echo "NO TOOLS NEEDED TO STAY SILENT:"
setup
rm -rf "$FIX/repo/.claude-plugin"
BASH_BIN="$(command -v bash)"
OUT="$(PATH="$FIX/empty-path" "$BASH_BIN" "$HELPER" --project "$FIX/repo" --plugin-root "$FIX/cache" 2>&1)"; RC=$?
{ [[ $RC -eq 0 ]] && has "STATUS=not-dev-repo"; } \
  && ok "non-plugin project with no python3/git on PATH → still silent not-dev-repo" || bad "tool-less consumer (rc=$RC, out=$OUT)"

echo "USAGE:"
OUT="$(bash "$HELPER" --project "$FIX/repo" 2>&1)"; RC=$?
{ [[ $RC -eq 2 ]] && [[ "$OUT" == *"ERROR=missing_argument:--plugin-root"* ]]; } \
  && ok "missing --plugin-root → usage error, exit 2" || bad "missing argument (rc=$RC, out=$OUT)"

# A trailing flag without a value used to loop forever (`shift 2` fails on one argument);
# `timeout` turns a regression into a failure instead of a hung harness. It is GNU coreutils
# (not on a stock Mac) — without it the cases still run, a regression then hangs visibly.
guard() { if command -v timeout >/dev/null 2>&1; then timeout 10 "$@"; else "$@"; fi; }
for flag in --plugin-root --project; do
  OUT="$(guard bash "$HELPER" --project "$FIX/repo" $flag 2>&1)"; RC=$?
  { [[ $RC -eq 2 ]] && [[ "$OUT" == *"ERROR=missing_value:$flag"* ]]; } \
    && ok "trailing $flag with no value → usage error, exit 2 (no hang)" || bad "trailing $flag (rc=$RC, out=$OUT)"
done
OUT="$(guard bash "$HELPER" --project "$FIX/repo" --plugin-root "" 2>&1)"; RC=$?
{ [[ $RC -eq 2 ]] && [[ "$OUT" == *"ERROR=missing_value:--plugin-root"* ]]; } \
  && ok "empty --plugin-root value (unset variable, quoted) → usage error, exit 2" || bad "empty value (rc=$RC, out=$OUT)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
