#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-gitignore-sync.sh — self-contained tests for the B4 gitignore helper
# (ensure-gitignore.sh), which keeps CRAFT's local state out of version control.
#
# No test runner exists in this repo (plugin assets, not runtime software), so
# this harness stands alone: it builds throwaway git repos under a temp dir, drives
# the helper against them, asserts on its key=value output and on what git itself
# reports, and exits non-zero if any case fails. Run it directly:
#
#   bash scripts/test-gitignore-sync.sh
#
# It writes nothing outside its own mktemp directory (removed on exit). The fixture
# repos ignore the caller's global and system git config, so a personal excludes
# file cannot make a case pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/ensure-gitignore.sh"
[[ -f "$HELPER" ]] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# git reads $XDG_CONFIG_HOME/git/ignore as a default excludes file even with no
# global config, so that has to be pointed away too.
mkdir -p "$ROOT/xdg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$ROOT/xdg"

# The paths the helper must cover — kept in step with CRAFT_PATHS in the helper;
# the first case fails loudly if the two ever drift apart.
PATHS=".claude/plans/.primed .claude/plans/.hook-env .claude/plans/.execute.lock .claude/settings.local.json .craft/"
MARKERS=".claude/plans/.primed .claude/plans/.hook-env .claude/plans/.execute.lock .claude/settings.local.json .craft/handoff.md"

new_repo() { # → prints the path of a fresh git repo (called in $(…), so no shared counter)
  local d
  d="$(mktemp -d "$ROOT/repo.XXXXXX")" && git -C "$d" init -q && printf '%s' "$d"
}
helper() { # repo mode
  CLAUDE_PROJECT_DIR="$1" bash "$HELPER" "$2" 2>&1
}
all_ignored() { # repo — every marker ignored by git
  local p
  for p in $MARKERS; do git -C "$1" check-ignore -q --no-index -- "$p" || return 1; done
}
count() { # pattern file
  grep -c -- "$1" "$2" 2>/dev/null || true
}
no_leftovers() { # dir — no temp or backup file from the helper survives the run
  [[ -z "$(find "$1" -maxdepth 1 -name '.gitignore.craft-*')" ]]
}

# --- fresh repo, no .gitignore ------------------------------------------------
R="$(new_repo)"
out="$(helper "$R" --check)"; rc=$?
entries="$(printf '%s\n' "$out" | sed -n 's/^ENTRY=\([^ ]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
[[ "$entries" == "$PATHS" ]] && ok "helper reports exactly the expected CRAFT paths, in order" || bad "path list drift (helper: '$entries')"
{ [[ $rc -eq 10 ]] && [[ "$out" == *"MISSING=5"* ]] && [[ "$out" == *"STATUS=absent"* ]] && [[ "$out" == *"GITIGNORE=missing"* ]] && [[ ! -e "$R/.gitignore" ]]; } \
  && ok "fresh repo: --check reports all 5 absent (exit 10) and writes nothing" || bad "fresh --check (rc=$rc, out=$out)"

out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=yes"* ]] && all_ignored "$R" && [[ "$(count '^# CRAFT local state' "$R/.gitignore")" == 1 ]]; } \
  && ok "fresh repo: --apply creates .gitignore with one marked block; git ignores every marker" || bad "fresh --apply (rc=$rc, out=$out)"

cp "$R/.gitignore" "$ROOT/snapshot"
out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=no"* ]] && cmp -s "$ROOT/snapshot" "$R/.gitignore"; } \
  && ok "re-running --apply is a byte-identical no-op (CHANGED=no)" || bad "idempotency (rc=$rc, out=$out)"

out="$(helper "$R" --check)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"STATUS=present"* ]]; } && ok "after apply: --check exits 0 (STATUS=present)" || bad "post-apply --check (rc=$rc)"

# end-to-end: the markers exist, the tree shows only the .gitignore
mkdir -p "$R/.claude/plans" "$R/.craft"
for p in $MARKERS; do : > "$R/$p"; done
status="$(git -C "$R" status --porcelain --untracked-files=all)"
[[ "$status" == "?? .gitignore" ]] && ok "end-to-end: with every marker on disk, git status lists only .gitignore" || bad "end-to-end status: '$status'"

# --- broader existing rules count as coverage ---------------------------------
for rule in '.claude/plans/' '.claude/plans/*'; do
  R="$(new_repo)"
  printf '%s\n' "$rule" > "$R/.gitignore"
  helper "$R" --apply >/dev/null
  { [[ "$(count '^\.claude/plans/\.' "$R/.gitignore")" == 0 ]] && all_ignored "$R"; } \
    && ok "broader rule '$rule' covers the plans markers — none appended" || bad "broader rule '$rule': $(tr '\n' '|' < "$R/.gitignore")"
done

# --- partial coverage (the Proxmox shape) ---------------------------------------
R="$(new_repo)"
printf 'vendor/\n.claude/plans/.primed\n' > "$R/.gitignore"
out="$(helper "$R" --apply)"
{ [[ "$out" == *"MISSING=4"* ]] && [[ "$(count '^\.claude/plans/\.primed$' "$R/.gitignore")" == 1 ]] && all_ignored "$R" && no_leftovers "$R"; } \
  && ok "partial coverage: only the 4 missing paths appended, .primed not duplicated, no backup left" || bad "partial coverage (out=$out)"

# --- no trailing newline ---------------------------------------------------------
R="$(new_repo)"
printf 'node_modules' > "$R/.gitignore"
helper "$R" --apply >/dev/null
{ [[ "$(sed -n 1p "$R/.gitignore")" == "node_modules" ]] && [[ -z "$(sed -n 2p "$R/.gitignore")" ]] \
  && [[ "$(sed -n 3p "$R/.gitignore")" == "# CRAFT local state"* ]] && all_ignored "$R"; } \
  && ok "missing trailing newline: last line intact, one blank line, then the block" || bad "trailing newline: $(tr '\n' '|' < "$R/.gitignore")"

# --- an existing block is extended, not duplicated --------------------------------
R="$(new_repo)"
printf '# CRAFT local state\n.claude/plans/.primed\n\n*.log\n' > "$R/.gitignore"
helper "$R" --apply >/dev/null
block="$(sed -n '/^# CRAFT local state/,/^$/p' "$R/.gitignore" | grep -c '^\.')"
{ [[ "$(count '^# CRAFT local state' "$R/.gitignore")" == 1 ]] && [[ "$block" == 5 ]] && [[ "$(tail -n 1 "$R/.gitignore")" == "*.log" ]] && no_leftovers "$R"; } \
  && ok "existing CRAFT block is extended in place (one header, 5 entries, later lines kept, no backup left)" || bad "block extension: $(tr '\n' '|' < "$R/.gitignore")"

# A block that ends the file (no blank line after it) — the shape every project has
# once a future release adds a path.
R="$(new_repo)"
printf 'dist/\n\n# CRAFT local state\n.claude/plans/.primed\n' > "$R/.gitignore"
helper "$R" --apply >/dev/null
block="$(sed -n '/^# CRAFT local state/,$p' "$R/.gitignore" | grep -c '^\.')"
{ [[ "$(count '^# CRAFT local state' "$R/.gitignore")" == 1 ]] && [[ "$block" == 5 ]] && all_ignored "$R"; } \
  && ok "CRAFT block at end of file is extended (5 entries, one header)" || bad "block at EOF: $(tr '\n' '|' < "$R/.gitignore")"

# --- a project below the git top level (monorepo) ----------------------------------------
# The hook writes the markers relative to CLAUDE_PROJECT_DIR, so coverage and the block
# belong to the project directory, not the repository root.
R="$(new_repo)"
P="$R/app"; mkdir -p "$P/.claude/plans" "$P/.craft"
out="$(helper "$P" --apply)"; rc=$?
for p in $MARKERS; do : > "$P/$p"; done
status="$(git -C "$R" status --porcelain --untracked-files=all)"
{ [[ $rc -eq 0 ]] && [[ -f "$P/.gitignore" ]] && [[ ! -e "$R/.gitignore" ]] && [[ "$status" == "?? app/.gitignore" ]]; } \
  && ok "project in a subdirectory: block written to <project>/.gitignore; git status lists only that file" || bad "subdirectory project (rc=$rc, status='$status')"
out="$(helper "$P" --check)"; rc=$?
[[ $rc -eq 0 ]] && ok "project in a subdirectory: --check then reports all covered" || bad "subdirectory --check (rc=$rc, out=$out)"

# A root-level rule that names the project's paths counts as coverage too.
R="$(new_repo)"
mkdir -p "$R/app"
printf 'app/.claude/\napp/.craft/\n' > "$R/.gitignore"
out="$(helper "$R/app" --check)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ ! -e "$R/app/.gitignore" ]]; } && ok "project in a subdirectory: a root .gitignore rule naming app/… counts as coverage" || bad "root rule for subdirectory (rc=$rc, out=$out)"

# --- symlinked .gitignore and CRLF -------------------------------------------------------
R="$(new_repo)"
printf 'dist/\n' > "$R/shared-ignore"
ln -s shared-ignore "$R/.gitignore"
out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 5 ]] && [[ "$out" == *"ERROR=gitignore_is_symlink"* ]] && [[ -L "$R/.gitignore" ]] && [[ "$(cat "$R/shared-ignore")" == "dist/" ]] && no_leftovers "$R"; } \
  && ok "symlinked .gitignore: --apply refuses (exit 5), link and target untouched" || bad "symlink (rc=$rc, out=$out)"

R="$(new_repo)"
printf 'dist/\r\n' > "$R/.gitignore"
helper "$R" --apply >/dev/null
lines="$(grep -c '' "$R/.gitignore")"; crlf="$(grep -c $'\r$' "$R/.gitignore")"
{ [[ "$lines" == "$crlf" ]] && all_ignored "$R"; } \
  && ok "CRLF .gitignore: every line, old and appended, keeps CRLF; markers ignored" || bad "CRLF ($crlf of $lines lines CRLF)"

# --- negation: the project's own `!path` is its decision, wherever it stands (B9) ---
ignored() { git -C "$1" check-ignore -q --no-index -- "$2"; }
others_ignored() { # repo skip-marker — every marker but one ignored
  local p
  for p in $MARKERS; do [[ "$p" == "$2" ]] && continue; ignored "$1" "$p" || return 1; done
}

R="$(new_repo)"
printf '.claude/plans/*\n!.claude/plans/.primed\n' > "$R/.gitignore"
out="$(helper "$R" --check)"; rc=$?
{ [[ "$out" == *"ENTRY=.claude/plans/.primed STATUS=negated"* ]] && [[ "$out" == *"MISSING=2"* ]] && [[ $rc -eq 10 ]]; } \
  && ok "negation above the append point: --check reports negated, not missing" || bad "negation above --check (rc=$rc, out=$out)"
out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=yes"* ]] && ! ignored "$R" .claude/plans/.primed && others_ignored "$R" .claude/plans/.primed \
  && [[ "$(count '^\.claude/plans/\.primed$' "$R/.gitignore")" == 0 ]] && [[ "$out" == *"ENTRY=.claude/plans/.primed STATUS=negated"* ]]; } \
  && ok "  … --apply appends the others, never the negated path; git still un-ignores it" || bad "negation above --apply (rc=$rc): $(tr '\n' '|' < "$R/.gitignore")"

R="$(new_repo)"
printf '# CRAFT local state\n.claude/plans/.primed\n\n!.claude/plans/.hook-env\n' > "$R/.gitignore"
out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"ENTRY=.claude/plans/.hook-env STATUS=negated"* ]] && [[ "$out" == *"CHANGED=yes"* ]] \
  && ! ignored "$R" .claude/plans/.hook-env && others_ignored "$R" .claude/plans/.hook-env \
  && [[ "$(count '^\.claude/plans/\.hook-env$' "$R/.gitignore")" == 0 ]] && no_leftovers "$R"; } \
  && ok "negation below the block: same answer — negated, not appended, exit 0 (no exit 6)" || bad "negation below (rc=$rc, out=$out)"

R="$(new_repo)"
printf '# CRAFT local state\n.claude/plans/.primed\n!.claude/plans/.primed\n' > "$R/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"ENTRY=.claude/plans/.primed STATUS=negated"* ]] && ok "negation inside the block → negated" || bad "negation inside the block (out=$out)"

R="$(new_repo)"
mkdir -p "$R/.claude"; printf '!settings.local.json\n' > "$R/.claude/.gitignore"; printf '.claude/settings.local.json\n' > "$R/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"ENTRY=.claude/settings.local.json STATUS=negated"* ]] && ok "negation in a nested .claude/.gitignore → negated" || bad "nested negation (out=$out)"

R="$(new_repo)"
printf '.claude/*\n!.claude/plans/\n' > "$R/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"ENTRY=.claude/plans/.primed STATUS=absent"* ]] && ok "broader un-ignore (!.claude/plans/ after .claude/*) decides nothing for the file → absent" || bad "broader negation --check (out=$out)"
helper "$R" --apply >/dev/null
all_ignored "$R" && ok "  … --apply covers it; git ignores every marker" || bad "broader negation --apply: $(tr '\n' '|' < "$R/.gitignore")"

R="$(new_repo)"
printf '# CRAFT local state\n.claude/plans/.hook-env\n.claude/plans/.execute.lock\n.claude/settings.local.json\n.craft/\n.claude/plans/.primed\n!.claude/plans/.primed\n' > "$R/.gitignore"
cp "$R/.gitignore" "$ROOT/snapshot"
out="$(helper "$R" --check)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"STATUS=present"* ]] && [[ "$out" == *"MISSING=0"* ]]; } \
  && ok "only covered and negated paths → --check exit 0, STATUS=present" || bad "all decided --check (rc=$rc, out=$out)"
out="$(helper "$R" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=no"* ]] && cmp -s "$ROOT/snapshot" "$R/.gitignore"; } \
  && ok "  … --apply changes nothing, .gitignore byte-identical" || bad "all decided --apply (rc=$rc, out=$out)"

# A negated path the project also tracks is kept visible on purpose: no TRACKED advice (R1-9)
R="$(new_repo)"
mkdir -p "$R/.claude"; printf '{}\n' > "$R/.claude/settings.local.json"
printf '.claude/settings.local.json\n!.claude/settings.local.json\n' > "$R/.gitignore"
git -C "$R" add .claude/settings.local.json
out="$(helper "$R" --check)"
{ [[ "$out" == *"ENTRY=.claude/settings.local.json STATUS=negated"* ]] && [[ "$out" != *"TRACKED=.claude/settings.local.json"* ]]; } \
  && ok "negated and tracked → negated, no TRACKED line (no git rm --cached advice)" || bad "negated+tracked (out=$out)"
printf '.claude/\n' > "$R/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"TRACKED=.claude/settings.local.json"* ]] && ok "  … the same tracked file under a covering rule still gets TRACKED" || bad "covered+tracked lost TRACKED (out=$out)"

# --verdict: the one mapping the settings helpers report (R1-11)
verdict() { CLAUDE_PROJECT_DIR="$1" bash "$HELPER" --verdict "$2" 2>/dev/null; }
R="$(new_repo)"; printf '.claude/\n' > "$R/.gitignore"
[[ "$(verdict "$R" .claude/settings.local.json)" == yes ]] && ok "--verdict: covered → yes" || bad "--verdict covered ($(verdict "$R" .claude/settings.local.json))"
printf '.claude/settings.local.json\n!.claude/settings.local.json\n' > "$R/.gitignore"
[[ "$(verdict "$R" .claude/settings.local.json)" == negated ]] && ok "--verdict: negated → negated" || bad "--verdict negated"
printf 'dist/\n' > "$R/.gitignore"
[[ "$(verdict "$R" .claude/settings.local.json)" == no ]] && ok "--verdict: absent → no" || bad "--verdict absent"
cp "$R/.gitignore" "$ROOT/snapshot"; verdict "$R" .claude/settings.local.json >/dev/null
cmp -s "$ROOT/snapshot" "$R/.gitignore" && ok "--verdict never writes" || bad "--verdict wrote .gitignore"
mkdir -p "$ROOT/notgit"
(cd "$ROOT/notgit" && GIT_CEILING_DIRECTORIES="$ROOT" CLAUDE_PROJECT_DIR="$ROOT/notgit" bash "$HELPER" --verdict x >/dev/null 2>&1); rc=$?
[[ $rc -eq 4 ]] && ok "--verdict outside a git work tree → exit 4, no verdict" || bad "--verdict non-git (rc=$rc)"
(CLAUDE_PROJECT_DIR="$R" bash "$HELPER" --verdict >/dev/null 2>&1); rc=$?
[[ $rc -eq 2 ]] && ok "--verdict without a path → exit 2" || bad "--verdict no path (rc=$rc)"

# Known limit, pinned so a git change shows: git names no deciding rule for a negated directory
# (`.craft/` then `!.craft/`), so the helper cannot tell it from no rule and appends `.craft/`.
R="$(new_repo)"
printf '.craft/\n!.craft/\n' > "$R/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"ENTRY=.craft/ STATUS=absent"* ]] && ok "known limit: a negated directory entry (!.craft/) reads absent — git reports no rule" || bad "directory negation changed (out=$out) — revisit the known limit in ensure-gitignore.sh"

R="$(new_repo)"
mkdir -p "$ROOT/home"; printf '.craft/\n' > "$ROOT/home/.gitignore"
git -C "$R" config core.excludesFile "$ROOT/home/.gitignore"
out="$(helper "$R" --check)"
[[ "$out" == *"ENTRY=.craft/ STATUS=absent"* ]] && ok "a global excludes file named ~/.gitignore is not project coverage" || bad "global ~/.gitignore (out=$out)"

# --- rules outside the project's .gitignore files do not count --------------------
R="$(new_repo)"
printf '.craft/\n' > "$ROOT/global-excludes"
git -C "$R" config core.excludesFile "$ROOT/global-excludes"
printf '.claude/plans/.hook-env\n' >> "$R/.git/info/exclude"
out="$(helper "$R" --check)"
{ [[ "$out" == *"ENTRY=.craft/ STATUS=absent"* ]] && [[ "$out" == *"ENTRY=.claude/plans/.hook-env STATUS=absent"* ]]; } \
  && ok "a rule in the global excludes file or .git/info/exclude is not project coverage" || bad "non-project rules (out=$out)"

# --- a nested .gitignore counts ------------------------------------------------------
R="$(new_repo)"
mkdir -p "$R/.claude"
printf 'settings.local.json\nplans/.primed\n' > "$R/.claude/.gitignore"
out="$(helper "$R" --check)"
{ [[ "$out" == *"ENTRY=.claude/settings.local.json STATUS=covered"* ]] && [[ "$out" == *"ENTRY=.claude/plans/.primed STATUS=covered"* ]]; } \
  && ok "a rule in a nested in-repo .gitignore counts as coverage" || bad "nested .gitignore (out=$out)"

# --- tracked file is flagged -----------------------------------------------------------
R="$(new_repo)"
mkdir -p "$R/.claude" && printf '{}\n' > "$R/.claude/settings.local.json"
git -C "$R" add -f .claude/settings.local.json
out="$(helper "$R" --apply)"
{ [[ "$out" == *"TRACKED=.claude/settings.local.json"* ]] && [[ "$out" == *"ENTRY=.claude/settings.local.json STATUS=covered"* ]]; } \
  && ok "a tracked CRAFT file is covered after apply but flagged TRACKED" || bad "tracked flag (out=$out)"

# --- errors ---------------------------------------------------------------------------
NOGIT="$ROOT/not-a-repo"; mkdir -p "$NOGIT"
out="$(CLAUDE_PROJECT_DIR="$NOGIT" GIT_CEILING_DIRECTORIES="$ROOT" bash "$HELPER" --apply 2>&1)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=not_a_git_work_tree"* ]] && [[ ! -e "$NOGIT/.gitignore" ]]; } \
  && ok "outside a git work tree: exits 4 with ERROR, writes nothing" || bad "not-a-repo (rc=$rc, out=$out)"

out="$(CLAUDE_PROJECT_DIR="$ROOT" bash "$HELPER" --bogus 2>&1)"; rc=$?
{ [[ $rc -eq 2 ]] && [[ "$out" == *"ERROR=unknown_argument"* ]]; } && ok "unknown argument: exits 2" || bad "unknown argument (rc=$rc)"

# --- runs under an old bash (macOS /bin/bash 3.2) ------------------------------------
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]]; then
  R="$(new_repo)"
  out="$(CLAUDE_PROJECT_DIR="$R" /bin/bash "$HELPER" --apply 2>&1)"; rc=$?
  { [[ $rc -eq 0 ]] && all_ignored "$R" && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash $(/bin/bash -c 'echo $BASH_VERSION'): --apply succeeds with no shell errors" || bad "bash 3.2 run (rc=$rc, out=$out)"
else
  echo "  SKIP  no bash < 4 at /bin/bash — old-bash run not exercised"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
