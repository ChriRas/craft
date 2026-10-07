#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-delete-safe.sh — self-contained tests for delete-safe plan cleanup (B19, D34):
# the rule detection (delete-mode.sh), the close helper (close-file.sh), the execute
# lock's states (execute-lock.sh), the read block on .claude/plans/.closed/ in the
# PreToolUse guard, the scanners that must not see .closed/, the binding of every close
# site in the command prose, and the prime hint.
#
# No test runner exists in this repo, so this harness stands alone: it builds settings
# and project fixtures under a temp dir, points $HOME and the managed-settings
# directory at them, drives the helpers and asserts on their key=value output and on
# the file system. Run it directly:
#
#   bash scripts/test-delete-safe.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE_HELPER="$SCRIPT_DIR/delete-mode.sh"
[[ -f "$MODE_HELPER" ]] || { echo "FATAL: helper not found at $MODE_HELPER" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$ROOT"
unset CLAUDE_CONFIG_DIR

# A fixture: its own $HOME, managed dir and project, none holding a rule yet.
new_fixture() { # → prints the fixture dir (holds home/, managed/, proj/)
  local d
  d="$(mktemp -d "$ROOT/fx.XXXXXX")"
  mkdir -p "$d/home/.claude" "$d/managed" "$d/proj/.claude/plans"
  printf '%s' "$d"
}
settings() { # file rule-kind rule — write a settings file holding one rule
  mkdir -p "$(dirname "$1")"
  printf '{ "permissions": { "%s": ["%s"] } }\n' "$2" "$3" > "$1"
}
mode() { # fixture [path] — run delete-mode.sh inside the fixture
  HOME="$1/home" CRAFT_TEST_MANAGED_DIR="$1/managed" \
    bash "$MODE_HELPER" --project "$1/proj" --path "${2:-.claude/plans/slice-001-x.md}" 2>&1
}
field() { # key output — the first value of key=
  printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1
}

echo "== 1. rule detection (delete-mode.sh)"

F="$(new_fixture)"
out="$(mode "$F")"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field MODE "$out")" == delete ]] && [[ "$(field COMMAND "$out")" == "rm -- '.claude/plans/slice-001-x.md'" ]]; } \
  && ok "no settings anywhere: delete mode, matched on the concrete, quoted 'rm -- <path>'" || bad "no rules (rc=$rc, out=$out)"

for rule in 'Bash(rm:*)' 'Bash(rm *)' 'Bash(rm*)' 'Bash(rm -- *)' 'Bash' 'B*' 'Bash(*)'; do
  F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny "$rule"
  out="$(mode "$F")"
  { [[ "$(field MODE "$out")" == move ]] && [[ "$(field RULE "$out")" == "$rule" ]] && [[ "$(field RULE_KIND "$out")" == deny ]]; } \
    && ok "deny '$rule' matches: move mode" || bad "deny '$rule' (out=$out)"
done

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" ask 'Bash(rm:*)'
out="$(mode "$F")"
{ [[ "$(field MODE "$out")" == move ]] && [[ "$(field RULE_KIND "$out")" == ask ]]; } \
  && ok "an ask rule also means move mode (it prompts at every close)" || bad "ask rule (out=$out)"

F="$(new_fixture)"
settings "$F/home/.claude/settings.json" ask 'Bash(rm:*)'
settings "$F/proj/.claude/settings.json" deny 'Bash(rm *)'
out="$(mode "$F")"
{ [[ "$(field RULE_KIND "$out")" == deny ]] && [[ "$(field RULE_LEVEL "$out")" == project ]]; } \
  && ok "deny is reported before ask" || bad "deny before ask (out=$out)"

for level in user project local managed managed-dropin; do
  F="$(new_fixture)"
  case "$level" in
    user) file="$F/home/.claude/settings.json" ;;
    project) file="$F/proj/.claude/settings.json" ;;
    local) file="$F/proj/.claude/settings.local.json" ;;
    managed) file="$F/managed/managed-settings.json" ;;
    managed-dropin) file="$F/managed/managed-settings.d/10-team.json" ;;
  esac
  settings "$file" deny 'Bash(rm:*)'
  out="$(mode "$F")"
  { [[ "$(field MODE "$out")" == move ]] && [[ "$(field RULE_LEVEL "$out")" == "${level%-dropin}" ]] && [[ "$(field RULE_SOURCE "$out")" == "$file" ]]; } \
    && ok "a rule on the $level level alone switches move mode on and names its source" || bad "$level level (out=$out)"
done

F="$(new_fixture)"; mkdir -p "$F/cfg"; settings "$F/cfg/settings.json" deny 'Bash(rm:*)'
out="$(CLAUDE_CONFIG_DIR="$F/cfg" mode "$F")"
{ [[ "$(field MODE "$out")" == move ]] && [[ "$(field RULE_SOURCE "$out")" == "$F/cfg/settings.json" ]]; } \
  && ok "a rule in \$CLAUDE_CONFIG_DIR/settings.json is read" || bad "CLAUDE_CONFIG_DIR (out=$out)"

F="$(new_fixture)"; git -C "$F/proj" init -q; mkdir -p "$F/proj/sub/.claude"
settings "$F/proj/.claude/settings.local.json" deny 'Bash(rm:*)'
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" GIT_CEILING_DIRECTORIES= bash "$MODE_HELPER" --project "$F/proj/sub" 2>&1)"
[[ "$(field MODE "$out")" == move ]] \
  && ok "a subdirectory project also reads the git top level's settings" || bad "git top level (out=$out)"

for rule in 'Bash(rm -r *)' 'Bash(rm -rf *)' 'Bash(rm -fr:*)' 'Read(./.claude/plans/**)' 'Bash(rmdir *)' 'Bash(git rm *)' 'Edit' 'Bash(rm)'; do
  F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny "$rule"
  out="$(mode "$F")"
  [[ "$(field MODE "$out")" == delete ]] \
    && ok "'$rule' does not match 'rm -- <path>': delete mode" || bad "non-matching '$rule' (out=$out)"
done

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" allow 'Bash(rm:*)'
out="$(mode "$F")"
[[ "$(field MODE "$out")" == delete ]] && ok "an allow rule alone keeps delete mode" || bad "allow only (out=$out)"

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny 'Bash(rm .claude/plans/*)'
out="$(mode "$F" .claude/plans/slice-001-x.md)"
[[ "$(field MODE "$out")" == delete ]] \
  && ok "the match is on the concrete command: 'rm .claude/plans/*' does not match 'rm -- .claude/plans/…'" \
  || bad "concrete command (out=$out)"
# The rule is written against the command as issued — the path single-quoted (R1-2 of slice-050).
F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny "Bash(rm -- '.claude/plans/*')"
out="$(mode "$F" .claude/plans/slice-001-x.md)"; out2="$(mode "$F" other/file.md)"
{ [[ "$(field MODE "$out")" == move ]] && [[ "$(field MODE "$out2")" == delete ]]; } \
  && ok "a path-scoped rule matches its own path only" || bad "path-scoped (out=$out / $out2)"
# …and on the command close-file.sh really prints: the absolute, quoted path (R2-7 of slice-050).
F="$(new_fixture)"; PA="$(cd "$F/proj" && pwd -P)"
settings "$F/home/.claude/settings.json" deny "Bash(rm -- '$PA/.claude/plans/*')"
printf 'x\n' > "$F/proj/.claude/plans/slice-007-p.md"
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" bash "$SCRIPT_DIR/close-file.sh" --project "$F/proj" .claude/plans/slice-007-p.md 2>&1)"
{ [[ "$(field RESULT "$out")" == moved ]] && [[ "$(field RULE_KIND "$out")" == deny ]]; } \
  && ok "a rule written on the absolute, quoted path matches what close-file.sh issues: moved" || bad "absolute path-scoped rule (out=$out)"

F="$(new_fixture)"; printf '{ "permissions": { "deny": [ "Bash(rm:*)" ' > "$F/home/.claude/settings.json"
out="$(mode "$F")"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field MODE "$out")" == move ]] && [[ "$(field REASON "$out")" == "unparseable:$F/home/.claude/settings.json" ]]; } \
  && ok "malformed JSON: move mode (doubt means move) with a reason line" || bad "malformed (rc=$rc, out=$out)"

F="$(new_fixture)"; printf '[1, 2]\n' > "$F/proj/.claude/settings.json"; printf '{ "permissions": "none" }\n' > "$F/proj/.claude/settings.local.json"
out="$(mode "$F")"
[[ "$(field MODE "$out")" == delete ]] && ok "valid JSON without a permissions object: no rule, delete mode" || bad "odd shapes (out=$out)"

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny 'Bash(rm:*)'; chmod 000 "$F/home/.claude/settings.json"
if [[ ! -r "$F/home/.claude/settings.json" ]]; then
  out="$(mode "$F")"
  { [[ "$(field MODE "$out")" == move ]] && [[ "$(field REASON "$out")" == unreadable:* ]]; } \
    && ok "an unreadable settings file: move mode with a reason line" || bad "unreadable (out=$out)"
else
  echo "  SKIP  running as a user who can read a mode-000 file — unreadable case not exercised"
fi
chmod 600 "$F/home/.claude/settings.json"

F="$(new_fixture)"
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" PATH="/nonexistent" /bin/bash "$MODE_HELPER" --project "$F/proj" 2>&1)"
{ [[ "$(field MODE "$out")" == move ]] && [[ "$(field REASON "$out")" == python3_not_found ]]; } \
  && ok "no python3: move mode with a reason line" || bad "no python3 (out=$out)"

out="$(bash "$MODE_HELPER" --path x 2>&1)"; rc=$?
{ [[ $rc -eq 2 ]] && [[ "$out" == *"ERROR=missing_project"* ]] && [[ "$out" != *MODE=* ]]; } \
  && ok "usage error: exit 2, no MODE line" || bad "usage (rc=$rc, out=$out)"

echo "== 2. close helper (close-file.sh)"

CLOSE_HELPER="$SCRIPT_DIR/close-file.sh"
close() { # fixture args… — run close-file.sh inside the fixture
  local f="$1"; shift
  HOME="$f/home" CRAFT_TEST_MANAGED_DIR="$f/managed" bash "$CLOSE_HELPER" --project "$f/proj" "$@" 2>&1
}
plan() { # fixture name [content] — an untracked plan file in the fixture
  printf '%s\n' "${3:-# plan $2}" > "$1/proj/.claude/plans/$2"
}

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny 'Bash(rm:*)'
plan "$F" slice-001-a.md "# a — $(date +%s%N)"; cp "$F/proj/.claude/plans/slice-001-a.md" "$ROOT/a.orig"
out="$(close "$F" .claude/plans/slice-001-a.md)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field MODE "$out")" == move ]] && [[ "$(field RESULT "$out")" == moved ]] \
  && [[ "$(field TARGET "$out")" == .claude/plans/.closed/slice-001-a.md ]] \
  && [[ ! -e "$F/proj/.claude/plans/slice-001-a.md" ]] && cmp -s "$ROOT/a.orig" "$F/proj/.claude/plans/.closed/slice-001-a.md" \
  && [[ "$(field RULE_SOURCE "$out")" == "$F/home/.claude/settings.json" ]] && [[ "$out" != *COMMAND=* ]]; } \
  && ok "move mode: the plan moves into .closed/, source gone, target byte-identical, rule source reported" \
  || bad "move (rc=$rc, out=$out)"

plan "$F" slice-001-a.md "# a, second copy"; plan "$F" slice-001-a.md.keep "x"
out="$(close "$F" .claude/plans/slice-001-a.md)"; t1="$(field TARGET "$out")"
plan "$F" slice-001-a.md "# a, third copy"
out="$(close "$F" .claude/plans/slice-001-a.md)"; t2="$(field TARGET "$out")"
{ [[ "$t1" =~ ^\.claude/plans/\.closed/slice-001-a\.[0-9]{8}T[0-9]{6}Z\.md$ ]] && [[ -n "$t2" ]] && [[ "$t2" != "$t1" ]] \
  && [[ "$(cat "$F/proj/$t1")" == "# a, second copy" ]] && [[ "$(cat "$F/proj/$t2")" == "# a, third copy" ]] \
  && [[ "$(cat "$F/proj/.claude/plans/.closed/slice-001-a.md")" == "$(cat "$ROOT/a.orig")" ]]; } \
  && ok "a name collision gets a unique suffix and never overwrites an earlier closed copy ($t1, $t2)" \
  || bad "collision (t1=$t1, t2=$t2)"

F="$(new_fixture)"; plan "$F" slice-002-b.md
out="$(close "$F" .claude/plans/slice-002-b.md)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field MODE "$out")" == delete ]] && [[ "$(field RESULT "$out")" == delete ]] \
  && [[ "$(field DELETE_CMD "$out")" == "rm -- '$(cd "$F/proj" && pwd -P)/.claude/plans/slice-002-b.md'" ]] \
  && [[ -f "$F/proj/.claude/plans/slice-002-b.md" ]] && [[ ! -e "$F/proj/.claude/plans/.closed" ]]; } \
  && ok "delete mode: the helper removes nothing and prints DELETE_CMD (absolute, quoted) for the agent" \
  || bad "delete mode (rc=$rc, out=$out)"

out="$(close "$F" --move .claude/plans/slice-002-b.md)"
{ [[ "$(field MODE "$out")" == move ]] && [[ "$(field RESULT "$out")" == moved ]] && [[ -f "$F/proj/.claude/plans/.closed/slice-002-b.md" ]]; } \
  && ok "--move moves even without a rule (for a helper that cannot hand a command back)" || bad "--move (out=$out)"

# A project path with a space (common on macOS): DELETE_CMD must stay one argument. The command
# is parsed by bash with `rm` swapped for a counter, so nothing is removed here.
F="$(new_fixture)"; mkdir -p "$F/My Project"; mv "$F/proj" "$F/My Project/proj"
mkdir -p "$F/My Project/proj/.claude/plans"; printf 'x\n' > "$F/My Project/proj/.claude/plans/slice-005-s.md"
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" bash "$CLOSE_HELPER" --project "$F/My Project/proj" \
  "$F/My Project/proj/.claude/plans/slice-005-s.md" 2>&1)"
dc="$(field DELETE_CMD "$out")"
args="$(bash -c "count() { shift; printf '%s|%s' \"\$#\" \"\$1\"; }; count ${dc#rm }" 2>&1)"
[[ "$args" == "1|$(cd "$F/My Project/proj" && pwd -P)/.claude/plans/slice-005-s.md" ]] \
  && ok "a project path with a space: DELETE_CMD parses as one argument, the plan's absolute path" \
  || bad "space in path (DELETE_CMD=$dc, parsed=$args)"

F="$(new_fixture)"; printf '{ "permissions": { "deny": [ ' > "$F/proj/.claude/settings.json"; plan "$F" slice-003-c.md
out="$(close "$F" .claude/plans/slice-003-c.md)"
{ [[ "$(field RESULT "$out")" == moved ]] && [[ "$(field REASON "$out")" == unparseable:* ]]; } \
  && ok "doubt (unparseable settings) moves, with the reason passed through" || bad "doubt (out=$out)"

F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny 'Bash(rm:*)'
out="$(close "$F" .claude/plans/missing.md)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=not_found"* ]]; } && ok "a missing file: exit 4, not_found" || bad "missing (rc=$rc, out=$out)"
mkdir -p "$F/outside"; printf 'x\n' > "$F/outside/f.md"
out="$(close "$F" "$F/outside/f.md")"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=outside_project"* ]] && [[ -f "$F/outside/f.md" ]]; } \
  && ok "a file outside the project: exit 4, untouched" || bad "outside (rc=$rc, out=$out)"
out="$(close "$F" ../outside/f.md)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=outside_project"* ]]; } && ok "a ../ path out of the project: exit 4" || bad "dotdot (rc=$rc, out=$out)"
mkdir -p "$F/proj/.claude/plans/.closed"; printf 'x\n' > "$F/proj/.claude/plans/.closed/old.md"
out="$(close "$F" .claude/plans/.closed/old.md)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=already_closed"* ]]; } && ok "a file already in .closed/: exit 4" || bad "already closed (rc=$rc, out=$out)"
ln -s "$F/outside/f.md" "$F/proj/.claude/plans/link.md"
out="$(close "$F" .claude/plans/link.md)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ -f "$F/outside/f.md" ]]; } && ok "a symlink is refused, its target untouched" || bad "symlink (rc=$rc, out=$out)"
git -C "$F/proj" init -q; plan "$F" slice-004-t.md; git -C "$F/proj" add .claude/plans/slice-004-t.md
out="$(close "$F" .claude/plans/slice-004-t.md)"; rc=$?
{ [[ $rc -eq 4 ]] && [[ "$out" == *"ERROR=tracked"* ]] && [[ -f "$F/proj/.claude/plans/slice-004-t.md" ]]; } \
  && ok "a tracked file is refused (git rm closes it; git can undo that)" || bad "tracked (rc=$rc, out=$out)"

no_removal() { # file — true when no non-comment line runs rm / unlink (the printed DELETE_CMD aside)
  ! grep -v '^[[:space:]]*#' "$1" | grep -v 'DELETE_CMD=rm -- ' \
    | grep -Eq '(^|[;&|(`[:space:]])(rm|unlink)([[:space:]]|$)'
}
# The rule semantics are defined once, in permission-rule-match.sh (shared with verify-run.sh, D35):
# delete-mode.sh calls it and carries no matcher of its own.
{ grep -q 'permission-rule-match.sh' "$MODE_HELPER" && ! grep -q 'spec_regex\|fnmatch' "$MODE_HELPER" \
  && grep -q 'def spec_regex' "$SCRIPT_DIR/permission-rule-match.sh"; } \
  && ok "delete-mode.sh asks the one shared matcher (permission-rule-match.sh) and holds no copy of it" \
  || bad "the rule matcher is not defined once"
no_removal "$CLOSE_HELPER" && no_removal "$MODE_HELPER" && no_removal "$SCRIPT_DIR/permission-rule-match.sh" \
  && ok "close-file.sh, delete-mode.sh and permission-rule-match.sh hold no removal command (only the printed DELETE_CMD)" \
  || bad "a helper issues a removal of its own"

echo "== 3. execute lock as state (execute-lock.sh)"

LOCK_HELPER="$SCRIPT_DIR/execute-lock.sh"
PIDS=()
trap 'for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$ROOT"' EXIT
spawn() { # [name] — start a long-lived process (named via a symlink when given) → sets SPAWNED
  local exe; exe="$(command -v sleep)"
  if [[ -n "${1:-}" ]]; then mkdir -p "$ROOT/bin"; ln -sf "$exe" "$ROOT/bin/$1"; exe="$ROOT/bin/$1"; fi
  "$exe" 300 & SPAWNED=$!; PIDS+=("$SPAWNED")
  sleep 0.2
}
gone_pid() { # → a PID that just exited
  sleep 0 & local p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"
}
lock() { # project caller-pid cmd args… — run execute-lock.sh as caller-pid ('-' = no CLAUDE_PID)
  local proj="$1" caller="$2"; shift 2
  if [[ "$caller" == - ]]; then
    env -u CLAUDE_PID bash "$LOCK_HELPER" "$1" --project "$proj" "${@:2}" 2>&1
  else
    CLAUDE_PID="$caller" CLAUDE_CODE_SESSION_ID="sess-$caller" bash "$LOCK_HELPER" "$1" --project "$proj" "${@:2}" 2>&1
  fi
}
held_by() { # project pid [start] — write a held lock owned by pid
  printf 'STATE=held\nTARGET=epic-009\nOWNER_PID=%s\nOWNER_START=%s\nSESSION=s\nSINCE=2026-09-30T00:00:00Z\n' \
    "$2" "${3-$(ps -o lstart= -p "$2" 2>/dev/null | sed 's/[[:space:]]*$//')}" > "$1/.claude/plans/.execute.lock"
}
LOCKF() { printf '%s' "$1/.claude/plans/.execute.lock"; }

spawn; ME=$SPAWNED; spawn; OTHER=$SPAWNED

P="$(new_fixture)/proj"
out="$(lock "$P" "$ME" check)"
{ [[ "$(field LOCK "$out")" == absent ]] && [[ "$(field DECISION "$out")" == proceed ]] && [[ ! -e "$(LOCKF "$P")" ]]; } \
  && ok "absent: check says proceed and writes nothing" || bad "absent check (out=$out)"
out="$(lock "$P" "$ME" acquire --target epic-003)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field RESULT "$out")" == acquired ]] && grep -qx 'STATE=held' "$(LOCKF "$P")" \
  && grep -qx "OWNER_PID=$ME" "$(LOCKF "$P")" && grep -qx 'TARGET=epic-003' "$(LOCKF "$P")" \
  && grep -qx "SESSION=sess-$ME" "$(LOCKF "$P")" && [[ -n "$(sed -n 's/^OWNER_START=//p' "$(LOCKF "$P")")" ]]; } \
  && ok "absent → acquire: held by the caller's CLAUDE_PID, with start time, target and session" || bad "acquire (rc=$rc, out=$out)"

out="$(lock "$P" "$OTHER" acquire --target epic-004)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$(field RESULT "$out")" == refused ]] && [[ "$(field REASON "$out")" == held_by_live_owner ]] \
  && [[ "$(field OWNER_PID "$out")" == "$ME" ]] && grep -qx 'TARGET=epic-003' "$(LOCKF "$P")"; } \
  && ok "held by another live process: stop (exit 10), lock untouched" || bad "live owner (rc=$rc, out=$out)"
out="$(lock "$P" "$OTHER" release)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$(field REASON "$out")" == not_owner ]] && grep -qx 'STATE=held' "$(LOCKF "$P")"; } \
  && ok "release by a process that does not own it: refused, still held" || bad "foreign release (rc=$rc, out=$out)"

# Held by the caller's own process: an Esc-interrupted run, or one still working through background
# spawns (which share CLAUDE_PID) — the lock cannot tell, so it is never taken over silently (R1-1 of slice-050).
out="$(lock "$P" "$ME" check)"
{ [[ "$(field DECISION "$out")" == confirm ]] && [[ "$(field REASON "$out")" == own_process ]]; } \
  && ok "held by the caller's own process: check says confirm (the human decides), never takeover" || bad "own process check (out=$out)"
before="$(cat "$(LOCKF "$P")")"
out="$(lock "$P" "$ME" acquire --target epic-005)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$(field RESULT "$out")" == refused ]] && [[ "$(field REASON "$out")" == own_process ]] \
  && [[ "$(cat "$(LOCKF "$P")")" == "$before" ]]; } \
  && ok "…and acquire refuses it (exit 10), the lock byte-identical" || bad "own process acquire (rc=$rc, out=$out)"

out="$(lock "$P" "$ME" release)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field RESULT "$out")" == released ]] && [[ -f "$(LOCKF "$P")" ]] \
  && grep -qx 'STATE=released' "$(LOCKF "$P")" && grep -q '^RELEASED=' "$(LOCKF "$P")" && grep -qx 'TARGET=epic-003' "$(LOCKF "$P")"; } \
  && ok "release by its owner: the file stays, STATE=released with a timestamp" || bad "release (rc=$rc, out=$out)"
out="$(lock "$P" "$ME" release)"
[[ "$(field RESULT "$out")" == unchanged ]] && ok "releasing a released lock: unchanged" || bad "re-release (out=$out)"
out="$(lock "$P" "$OTHER" acquire --target epic-004)"
{ [[ "$(field RESULT "$out")" == acquired ]] && [[ "$(field REASON "$out")" == released ]] && grep -qx "OWNER_PID=$OTHER" "$(LOCKF "$P")"; } \
  && ok "released → any process acquires it" || bad "after release (out=$out)"

P="$(new_fixture)/proj"; held_by "$P" "$(gone_pid)" "Mon Sep 28 10:00:00 2026"
out="$(lock "$P" "$ME" check)"
{ [[ "$(field DECISION "$out")" == takeover ]] && [[ "$(field REASON "$out")" == owner_gone ]] && [[ "$(field OWNER_ALIVE "$out")" == no ]]; } \
  && ok "held by a process that is gone: takeover" || bad "gone owner (out=$out)"
out="$(lock "$P" "$ME" acquire --target epic-003)"
{ [[ "$(field RESULT "$out")" == taken_over ]] && grep -qx "OWNER_PID=$ME" "$(LOCKF "$P")"; } \
  && ok "…and acquire takes it over, now owned by the caller" || bad "gone owner acquire (out=$out)"

P="$(new_fixture)/proj"; held_by "$P" "$OTHER" "Thu Jan  1 00:00:00 2015"
out="$(lock "$P" "$ME" check)"
{ [[ "$(field DECISION "$out")" == takeover ]] && [[ "$(field REASON "$out")" == owner_reused ]]; } \
  && ok "held by a live PID with another start time (PID reused): takeover" || bad "reused PID (out=$out)"
P="$(new_fixture)/proj"; held_by "$P" "$OTHER" ""
out="$(lock "$P" "$ME" check)"
[[ "$(field REASON "$out")" == held_by_live_owner ]] \
  && ok "no recorded start time (ps could not tell): the PID alone decides — live, stop" || bad "no start (out=$out)"

spawn claude; LIVE_CLAUDE=$SPAWNED
P="$(new_fixture)/proj"; printf '%s\nepic-003\n' "$LIVE_CLAUDE" > "$(LOCKF "$P")"
out="$(lock "$P" "$ME" check)"
{ [[ "$(field LOCK "$out")" == legacy ]] && [[ "$(field DECISION "$out")" == stop ]] && [[ "$(field REASON "$out")" == legacy_owner_live ]]; } \
  && ok "legacy lock whose PID is a running 'claude' process: stop" || bad "legacy live (out=$out)"
P="$(new_fixture)/proj"; printf 'PID %s target epic-003\n' "$OTHER" > "$(LOCKF "$P")"
out="$(lock "$P" "$ME" acquire --target epic-003)"
{ [[ "$(field REASON "$out")" == legacy_owner_gone ]] && [[ "$(field RESULT "$out")" == taken_over ]] && grep -qx 'STATE=held' "$(LOCKF "$P")"; } \
  && ok "legacy lock whose PID is not a claude process: taken over, rewritten in the new format" || bad "legacy gone (out=$out)"
P="$(new_fixture)/proj"; printf 'epic-003\n' > "$(LOCKF "$P")"
out="$(lock "$P" "$ME" check)"
[[ "$(field DECISION "$out")" == takeover ]] && ok "legacy lock without any PID: takeover" || bad "legacy no pid (out=$out)"

P="$(new_fixture)/proj"; printf 'STATE=held\nTARGET=epic-003\n' > "$(LOCKF "$P")"
out="$(lock "$P" "$ME" acquire --target epic-003)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$(field REASON "$out")" == unreadable ]]; } \
  && ok "held without an owner: stop (doubt stops)" || bad "no owner (rc=$rc, out=$out)"
printf 'STATE=paused\n' > "$(LOCKF "$P")"
out="$(lock "$P" "$ME" check)"
[[ "$(field DECISION "$out")" == stop ]] && ok "an unknown STATE: stop" || bad "unknown state (out=$out)"
held_by "$P" "$OTHER"
out="$(lock "$P" - release --force)"
{ [[ "$(field RESULT "$out")" == released ]] && grep -qx 'STATE=released' "$(LOCKF "$P")"; } \
  && ok "release --force (the human's) releases a lock it does not own" || bad "force (out=$out)"

P="$(new_fixture)/proj"
out="$(lock "$P" - acquire --target epic-003)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$(field REASON "$out")" == no_identity ]] && [[ "$(printf '%s\n' "$out" | grep -c '^REASON=')" == 1 ]] \
  && [[ "$out" != *LOCK=* ]] && [[ ! -e "$(LOCKF "$P")" ]]; } \
  && ok "no CLAUDE_PID: acquire refused with one REASON= line (no check lines), nothing written" || bad "no identity (rc=$rc, out=$out)"
held_by "$P" "$OTHER"
out="$(lock "$P" - check)"
[[ "$(field DECISION "$out")" == stop ]] && ok "no CLAUDE_PID: check still judges a live foreign owner as stop" || bad "check without identity (out=$out)"
out="$(lock "$P" "$ME" release)"
[[ "$(field RESULT "$out")" == refused ]] && ok "release without --force by a non-owner: refused" || bad "non-owner (out=$out)"
out="$(lock "$P" "$ME" acquire)"; rc=$?
[[ $rc -eq 2 ]] && ok "acquire without --target: usage error" || bad "usage (rc=$rc)"

no_removal "$LOCK_HELPER" && ok "execute-lock.sh holds no removal command" || bad "execute-lock.sh removes something"

echo "== 4. read block on .claude/plans/.closed/ (readonly-context-guard.sh)"

GUARD="$REPO/hooks/readonly-context-guard.sh"
GP="$(new_fixture)/proj"; mkdir -p "$GP/.claude/project" "$GP/research"
printf '# Rules\n## Read-Only Context Sources (optional)\n(no connected projects declared)\n' > "$GP/.claude/project/rules.md"
if command -v jq >/dev/null 2>&1; then
  for SH in bash /bin/bash; do
    [[ "$SH" == /bin/bash ]] && { [[ -x /bin/bash ]] || continue; }
    V="$("$SH" -c 'echo $BASH_VERSION')"
    gcase() { # expect tool input-json label
      local o e
      o="$(printf '{"tool_name":"%s","tool_input":%s,"cwd":"%s"}' "$2" "$3" "$GP" \
        | CLAUDE_PROJECT_DIR="$GP" "$SH" "$GUARD" 2>"$ROOT/guard.err")"
      e="$(cat "$ROOT/guard.err")"
      if [[ -n "$e" ]]; then bad "[$V] $4 — shell error: $e"; return; fi
      if [[ "$1" == deny ]]; then
        [[ "$o" == *'"permissionDecision":"deny"'* && "$o" == *'.claude/plans/.closed/'* ]] && ok "[$V] $4" || bad "[$V] $4 (got: ${o:-<empty>})"
      else
        [[ -z "$o" ]] && ok "[$V] $4" || bad "[$V] $4 (got: $o)"
      fi
    }
    C="$GP/.claude/plans/.closed"
    gcase deny  Read "{\"file_path\":\"$C/slice-001-a.md\"}"                        "Read of a closed plan (absolute) is denied"
    gcase deny  Read '{"file_path":".claude/plans/.closed/slice-001-a.md"}'           "Read of a closed plan (relative) is denied"
    gcase deny  Read "{\"file_path\":\"$GP/commands/../.claude/plans/.closed/x.md\"}" "Read through a ../ segment is denied"
    gcase deny  Read '{"file_path":".claude/plans/./.closed//x.md"}'                  "Read through ./ and // is denied"
    gcase deny  Read "{\"file_path\":\"$C\"}"                                         "Read of the directory itself is denied"
    gcase allow Read "{\"file_path\":\"$GP/.claude/plans/slice-001-a.md\"}"           "Read of a live plan is allowed"
    gcase allow Read "{\"file_path\":\"$GP/.claude/plans/.closed-notes/x.md\"}"       "a sibling .closed-notes/ is no false positive"
    gcase deny  Read '{"file_path":"/elsewhere/main-checkout/.claude/plans/.closed/x.md"}' "Read of another checkout's .closed/ is denied (a session in a slice worktree)"
    gcase allow Read '{"file_path":"/elsewhere/notes/.closed/x.md"}'                  "a .closed/ outside .claude/plans/ is no false positive"
    gcase allow Read "{\"file_path\":\"$GP/research/x.md\"}"                          "Read of research/ stays allowed (read-only, not read-blocked)"
    gcase deny  Grep '{"pattern":"TODO","path":".claude/plans/.closed"}'              "Grep with its path in .closed/ is denied"
    gcase deny  Grep '{"pattern":"TODO","path":".claude/plans","glob":".closed/**"}'  "Grep whose glob reaches into .closed/ is denied"
    gcase deny  Grep "{\"pattern\":\"TODO\",\"path\":\"$C/sub\"}"                     "Grep below .closed/ (absolute) is denied"
    gcase allow Grep '{"pattern":"TODO"}'                                             "Grep from the project root is allowed (gitignore scopes it)"
    gcase allow Grep '{"pattern":"TODO","path":".claude/plans","glob":"*.md"}'        "Grep over live plans is allowed"
    gcase deny  Glob '{"pattern":".claude/plans/.closed/*.md"}'                       "Glob of a .closed/ pattern is denied"
    gcase deny  Glob '{"pattern":".closed/**","path":".claude/plans"}'                "Glob into .closed/ relative to its path is denied"
    gcase deny  Glob "{\"pattern\":\"*.md\",\"path\":\"$C\"}"                         "Glob with its path in .closed/ is denied"
    gcase allow Glob '{"pattern":"**/*.md"}'                                          "Glob from the project root is allowed (names only)"
    gcase deny  Write "{\"file_path\":\"$C/new.md\",\"content\":\"x\"}"               "Write into .closed/ is denied"
    gcase deny  Edit  "{\"file_path\":\"$C/slice-001-a.md\"}"                         "Edit in .closed/ is denied"
    gcase allow Write "{\"file_path\":\"$GP/.claude/plans/slice-002-b.md\"}"          "Write of a live plan is allowed"
    gcase allow Bash  '{"command":"cat .claude/plans/.closed/x.md"}'                  "Bash is not judged (known limit: no hook reads a command reliably)"
  done
else
  echo "  SKIP  jq not installed — the guard fails open without it; guard cases not exercised"
fi
if command -v jq >/dev/null 2>&1; then
  reason="$(printf '{"tool_name":"Read","tool_input":{"file_path":".claude/plans/.closed/x.md"},"cwd":"%s"}' "$GP" \
    | CLAUDE_PROJECT_DIR="$GP" bash "$GUARD" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  { [[ "$reason" == *"blocked on purpose"* ]] && [[ "$reason" == *"Do not read it another way"* ]] \
    && [[ "$reason" == *"do not suggest changing or disabling this block"* ]] \
    && [[ "$reason" == *"If the human needs the plan, they can open it themselves."* ]] && [[ "$reason" != *"Ask the human"* ]]; } \
    && ok "the deny reason sets the boundary: on purpose, no other way, no loosening, the human opens it (slice-050 Phase 5)" \
    || bad "deny reason wording (got: $reason)"
fi
grep -q '"matcher": "Write|Edit|NotebookEdit|Read|Grep|Glob"' "$REPO/hooks/hooks.json" \
  && ok "hooks.json routes Read / Grep / Glob to the guard" || bad "hooks.json matcher does not cover Read / Grep / Glob"

echo "== 5. scanners do not see .claude/plans/.closed/"

# One project, read by every CRAFT scanner before and after closed copies are planted in
# .closed/ — copies that, if read, would revive an aborted slice's epic link, make a live
# slice ambiguous, add candidates, or change the handoff marker's plan.
SP="$(new_fixture)/proj"; mkdir -p "$SP/.claude/project/slices" "$SP/.craft"
git -C "$SP" init -q -b main; git -C "$SP" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cat > "$SP/.claude/plans/epic-009-x.md" <<'EOF'
# Epic 009 — x

> Status: planning
> Epic-ID: epic-009
> Epic-Slug: x

## Slice Decomposition

- [ ] slice-001 — alpha — intent a
- [ ] slice-002 — beta — intent b (aborted: no plan, no archive)
- [ ] gamma — intent c
EOF
printf '# Slice 001 — alpha\n\n> Status: paused\n> Slice-ID: slice-001\n> Slice-Slug: alpha\n' > "$SP/.claude/plans/slice-001-alpha.md"
printf -- '---\nSlice-ID: slice-001\nStatus: awaiting-protocol\nPhase: 4\nWritten: 2026-09-30T10:00:00Z\n---\n\n# Handoff\n' > "$SP/.craft/handoff.md"
scan() { # → every scanner's output, one block
  (
    cd "$SP" || exit 1
    export CLAUDE_PROJECT_DIR="$SP"
    echo "-- execute-resume-state slice-001"; bash "$SCRIPT_DIR/execute-resume-state.sh" --mode sequential slice-001 2>&1
    echo "-- execute-resume-state slice-002"; bash "$SCRIPT_DIR/execute-resume-state.sh" --mode sequential slice-002 2>&1
    echo "-- epic-entry-link candidates"; bash "$SCRIPT_DIR/epic-entry-link.sh" candidates 2>&1
    echo "-- epic-entry-link resolve"; bash "$SCRIPT_DIR/epic-entry-link.sh" resolve .claude/plans/epic-009-x.md 2>&1
    echo "-- handoff-marker-state"; bash "$SCRIPT_DIR/handoff-marker-state.sh" "$SP" 2>&1
    echo "-- tree-dirt-state"; bash "$SCRIPT_DIR/tree-dirt-state.sh" 2>&1
  )
}
before="$(scan)"
mkdir -p "$SP/.claude/plans/.closed"
printf '# Slice 002 — beta\n\n> Status: implementing\n> Slice-ID: slice-002\n> Slice-Slug: beta\n' > "$SP/.claude/plans/.closed/slice-002-beta.md"
printf '# Slice 001 — alpha\n\n> Status: committing\n> Slice-ID: slice-001\n> Slice-Slug: alpha\n' > "$SP/.claude/plans/.closed/slice-001-alpha.md"
printf '# Epic 010\n\n> Epic-ID: epic-010\n\n## Slice Decomposition\n\n- [ ] delta — intent d\n' > "$SP/.claude/plans/.closed/epic-010-y.md"
cp "$SP/.claude/plans/epic-009-x.md" "$SP/.claude/plans/.closed/epic-009-x.md"
after="$(scan)"; [[ -n "${SHOW_SCAN:-}" ]] && printf "%s\n" "$before"
{ [[ "$before" == "$after" ]] && [[ "$before" == *"STATE=LIVE"* ]] && [[ "$before" == *"ENTRY=beta"* ]] && [[ "$before" == *"DIRTY=no"* ]] \
  && [[ "$before" == *"SLICE=slice-001 "*"ACTION="* ]] && [[ "$before" == *"ERROR=plan_not_found:slice-002"* ]]; } \
  && ok "execute-resume-state, epic-entry-link (candidates, resolve), handoff-marker-state and tree-dirt-state read the same with closed copies planted" \
  || bad "a scanner changed its answer: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | tr '\n' '|')"
recursive="$(cd "$REPO" && grep -rn -E 'plans/\*\*|find [^|`]*\.claude/plans|ls -R[^|`]*plans' commands agents skills || true)"
[[ -z "$recursive" ]] && ok "no command, agent or skill enumerates .claude/plans/ recursively (prime, status, continue use .claude/plans/*.md)" \
  || bad "a recursive plan scan: $recursive"

echo "== 7. the cleanup hint (delete-mode.sh --report)"

report() { # fixture — delete-mode.sh --report inside the fixture
  HOME="$1/home" CRAFT_TEST_MANAGED_DIR="$1/managed" bash "$MODE_HELPER" --project "$1/proj" --report 2>&1
}
closed_files() { # fixture n — n fresh files in .closed/
  local i; mkdir -p "$1/proj/.claude/plans/.closed"
  for (( i = 1; i <= $2; i++ )); do printf 'x\n' > "$1/proj/.claude/plans/.closed/slice-$i.md"; done
}
F="$(new_fixture)"
out="$(report "$F")"
{ [[ "$(field CLOSED_COUNT "$out")" == 0 ]] && [[ "$(field CLOSED_OLDEST_DAYS "$out")" == - ]] && [[ "$(field HINT "$out")" == no ]] && [[ "$out" != *HINT_CMD=* ]]; } \
  && ok "no .closed/ at all: count 0, no hint" || bad "no dir (out=$out)"
closed_files "$F" 19
out="$(report "$F")"
{ [[ "$(field CLOSED_COUNT "$out")" == 19 ]] && [[ "$(field HINT "$out")" == no ]]; } \
  && ok "19 fresh files: below the threshold, no hint" || bad "19 files (out=$out)"
closed_files "$F" 20
out="$(report "$F")"; cmd="$(field HINT_CMD "$out")"
{ [[ "$(field CLOSED_COUNT "$out")" == 20 ]] && [[ "$(field HINT "$out")" == yes ]] && [[ -n "$cmd" ]] \
  && [[ "$(printf '%s\n' "$out" | grep -c '^HINT_CMD=')" == 1 ]] && [[ "$cmd" != *$'\n'* ]]; } \
  && ok "20 files: the hint, with its command on one line" || bad "20 files (out=$out)"
mkdir -p "$F/proj/.claude/plans/.closed/sub"; printf 'x\n' > "$F/proj/.claude/plans/.closed/sub/keep.md"
printf 'live\n' > "$F/proj/.claude/plans/slice-099-live.md"
listed="$(bash -c "${cmd% -delete} -print" 2>&1)"
{ [[ "$(printf '%s\n' "$listed" | grep -c .)" == 20 ]] && [[ "$listed" != *slice-099-live* ]] && [[ "$listed" != *keep.md* ]] \
  && [[ -d "$F/proj/.claude/plans/.closed" ]]; } \
  && ok "the hint's command, dry-run: exactly the 20 files in .closed/ — no live plan, nothing below it" || bad "hint scope (listed=$listed)"
bash -c "$cmd" 2>&1
{ [[ -z "$(find "$F/proj/.claude/plans/.closed" -maxdepth 1 -type f)" ]] && [[ -f "$F/proj/.claude/plans/slice-099-live.md" ]] \
  && [[ -f "$F/proj/.claude/plans/.closed/sub/keep.md" ]]; } \
  && ok "…run for real (as the human would): .closed/ emptied, the live plan untouched" || bad "hint run"
out="$(report "$F")"
[[ "$(field HINT "$out")" == no ]] && ok "after the cleanup: no hint" || bad "after cleanup (out=$out)"

F="$(new_fixture)"; closed_files "$F" 2; touch -t 202601010000 "$F/proj/.claude/plans/.closed/slice-1.md"
out="$(report "$F")"
{ [[ "$(field HINT "$out")" == yes ]] && [[ "$(field CLOSED_OLDEST_DAYS "$out")" -gt 30 ]]; } \
  && ok "one file older than 30 days: the hint, even with 2 files" || bad "old file (out=$out)"
F="$(new_fixture)"; closed_files "$F" 1; touch -t "$(date -v-29d +%Y%m%d0000 2>/dev/null || date -d '29 days ago' +%Y%m%d0000)" "$F/proj/.claude/plans/.closed/slice-1.md"
out="$(report "$F")"
[[ "$(field HINT "$out")" == no ]] && ok "a file 29 days old: no hint yet" || bad "29 days (out=$out)"

# The age counts from the close, not from the plan's last edit: aborting a stale plan (prime's
# "untouched for K days") must not raise the hint at the next session (R1-3 of slice-050).
F="$(new_fixture)"; settings "$F/home/.claude/settings.json" deny 'Bash(rm:*)'
plan "$F" slice-006-old.md; touch -t 202601010000 "$F/proj/.claude/plans/slice-006-old.md"
close "$F" .claude/plans/slice-006-old.md >/dev/null
out="$(report "$F")"
{ [[ "$(field CLOSED_COUNT "$out")" == 1 ]] && [[ "$(field CLOSED_OLDEST_DAYS "$out")" == 0 ]] && [[ "$(field HINT "$out")" == no ]]; } \
  && ok "a plan last edited months ago and closed today: 0 days old, no hint" || bad "age from close (out=$out)"

F="$(new_fixture)"; mkdir -p "$F/pr'oj x"; mv "$F/proj" "$F/pr'oj x/proj"; mkdir -p "$F/proj"
closed_files "$F" 0; mkdir -p "$F/pr'oj x/proj/.claude/plans/.closed"
for i in $(seq 1 20); do printf 'x\n' > "$F/pr'oj x/proj/.claude/plans/.closed/c$i.md"; done
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" bash "$MODE_HELPER" --project "$F/pr'oj x/proj" --report 2>&1)"
cmd="$(field HINT_CMD "$out")"
[[ "$(bash -c "${cmd% -delete} -print" 2>&1 | grep -c '/c[0-9]*\.md$')" == 20 ]] \
  && ok "a project path with a quote and a space: the command is still copy-ready" || bad "quoting (cmd=$cmd)"

F="$(new_fixture)"; closed_files "$F" 20
NOPY="$ROOT/nopy"; mkdir -p "$NOPY"
for t in date stat sed find uname git; do command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$NOPY/$t"; done
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" PATH="$NOPY" /bin/bash "$MODE_HELPER" --project "$F/proj" --report 2>&1)"
{ [[ "$(field REASON "$out")" == python3_not_found ]] && [[ "$(field CLOSED_COUNT "$out")" == 20 ]] \
  && [[ "$(field HINT "$out")" == yes ]] && [[ "$(field HINT_CMD "$out")" == "find '"*"/.claude/plans/.closed' -mindepth 1 -maxdepth 1 -type f -delete" ]]; } \
  && ok "without python3: move mode, and the report still counts and hints (bash only)" || bad "report without python3 (out=$out)"

echo "== 6. binding: the command prose closes files only through the helpers"

CMDS="$REPO/commands"
lock_removals="$(grep -rn -E '(rm|[Dd]elete|[Rr]emove)[^|]{0,12}`?\.claude/plans/\.execute\.lock|execute\.lock` must not exist' "$CMDS" \
  | grep -v -E 'never removed|Never delete|is never removed' || true)"
[[ -z "$lock_removals" ]] && ok "no command removes the execute lock or requires it to be absent" \
  || bad "a command still removes the lock or reads its absence: $lock_removals"
[[ "$(grep -c 'scripts/execute-lock.sh" acquire' "$CMDS/execute.md")" -eq 1 && "$(grep -c 'scripts/execute-lock.sh" check' "$CMDS/execute.md")" -eq 2 ]] \
  && ok "execute.md takes the lock once (step 1) and checks it in A4 and P4 through execute-lock.sh" || bad "execute.md lock calls"
[[ "$(grep -c 'release --project' "$CMDS/execute.md")" -eq 1 ]] \
  && ok "execute.md defines the release once (step 1); every other release points there" || bad "execute.md release definition count"
grep -q 'scripts/execute-lock.sh" check' "$CMDS/worktree-clean.md" \
  && ok "worktree-clean.md asks execute-lock.sh instead of testing the lock file's existence" || bad "worktree-clean.md lock check"
# DECISION=confirm is answered by the human in both readers — never read as proceed (R1-1 of slice-050).
for f in execute.md worktree-clean.md; do
  { grep -q '`confirm` (`REASON=own_process`)\|`DECISION=confirm` (`REASON=own_process`)' "$CMDS/$f" \
    && grep -q 'Only on `\[N\]`' "$CMDS/$f"; } \
    && ok "$f asks the human on DECISION=confirm and releases only on [N]" || bad "$f does not handle DECISION=confirm"
done
! grep -q -F -e 'takes it over (`execute-lock.sh` → `REASON=own_process`)' -e 'or is this very Claude Code process' \
    "$CMDS/execute.md" "$CMDS/worktree-clean.md" \
  && ok "no command prose still says an own-process lock is taken over" || bad "prose still takes an own-process lock over"
# An abort before this invocation took the lock releases nothing: in the same session a plain release would free a
# running run's lock (R2-1 of slice-050).
{ grep -q 'An abort in A4 or at step 1.s refusal releases nothing' "$CMDS/execute.md" \
  && ! grep -q 'or on graceful abort' "$CMDS/execute.md"; } \
  && ok "execute.md releases only a lock this invocation took — an A4 abort releases nothing" || bad "execute.md abort release rule"

# slice-066 (B20): the review-checkpoint record is append-only state — CRAFT never deletes its lines, the file or .craft/
# (D34). Matched on the old clause and on any remove / delete verb within a short span of the record's name.
step9="$(awk '/^### 9\./{f=1} /^### 10\./{f=0} f' "$CMDS/execute.md")"
# the span may cross a path's dots (`.craft/checkpoints.md`), not a sentence's end
step9_verbs="$(grep -n -i -E '(delet|remov|unlink|\brm\b)([^.]|\.[A-Za-z_/]){0,60}checkpoints\.md|checkpoints\.md([^.]|\.[A-Za-z_/]){0,60}(delet|remov|unlink|\brm\b)' <<<"$step9" || true)"
{ [[ -n "$step9" ]] \
  && ! grep -q -F -e 'delete its lines' -e 'an empty `.craft/` with them' <<<"$step9" \
  && [[ -z "$step9_verbs" ]] \
  && grep -q -F 'append-only state' <<<"$step9"; } \
  && ok "execute.md step 9 keeps the checkpoint record as state" \
  || bad "execute.md step 9 keeps the checkpoint record as state — old clause, a removal verb near checkpoints.md ($step9_verbs) or no 'append-only state'"

# The pinned set of close sites: a new one is added here deliberately.
EXPECTED_SITES="commands/abort.md commands/commit.md"
sites="$(cd "$REPO" && grep -rl 'craft:close-file' commands agents skills 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$sites" == "$EXPECTED_SITES" ]] && ok "the close sites are exactly: $EXPECTED_SITES" \
  || bad "close-site set drifted: '$sites' (expected '$EXPECTED_SITES')"
for f in $EXPECTED_SITES; do
  n_marker="$(grep -c 'craft:close-file' "$REPO/$f")"
  near="$(grep -A8 'craft:close-file' "$REPO/$f" | grep -c 'scripts/close-file.sh" --project')"
  { [[ "$n_marker" -eq 1 ]] && [[ "$near" -eq 1 ]]; } \
    && ok "$f: one close-file marker, with the close-file.sh call right below it" \
    || bad "$f: markers=$n_marker, calls near the marker=$near"
done
plan_rms="$(cd "$REPO" && grep -n -E '(^|[^A-Za-z_-])rm([^A-Za-z_-]|$)' commands/*.md agents/*.md skills/*/SKILL.md \
  | grep -v -E 'git rm|DELETE_CMD|an `rm` of your own|`rm`, `mv`, package installs' || true)"
[[ -z "$plan_rms" ]] && ok "no command, agent or skill tells the agent to rm a file itself" \
  || bad "an agent-issued rm is left in the prose: $plan_rms"
grep -q 'bash "<helper>" --project "<project-root>" --report' "$CMDS/prime.md" && grep -q 'scripts/delete-mode.sh' "$CMDS/prime.md" \
  && ok "prime.md reports the mode and the hint through delete-mode.sh --report" || bad "prime.md step 4g call"
grep -q 'close-file.sh" --project "\$PWD" --move' "$SCRIPT_DIR/plan-landing.sh" \
  && ok "plan-landing.sh sync closes its untracked copy through close-file.sh --move" || bad "plan-landing.sh sync close"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
