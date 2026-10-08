#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-pause-watch.sh — self-contained tests for the pause request of the auto slice flow (slice-075, D42):
# the UserPromptSubmit hook hooks/pause-watch.sh, the marker helper scripts/pause-request.sh (request / state /
# consume), flow-state.sh's STOP=pause-requested, the hooks.json registration, and the sites of the rule. Run it
# directly:
#
#   bash scripts/test-pause-watch.sh
#
# The case table below was written BEFORE the hook and the helper existed (the plan's Test Strategy); it is the
# contract they are judged by. The hook is bash-3.2-compatible on purpose (rules.md -> Bash baseline), so every hook
# case runs twice — under the bash this harness runs in and under /bin/bash — and a run that prints error text on
# stderr fails (a 3.2 run skips a failing command and carries on green). The hook is FAIL-OPEN and silent: whatever
# it cannot classify, the prompt passes — it never prints anything on stdout, never a block.
# What this harness cannot show: that Claude Code fires UserPromptSubmit for a message queued while a turn runs
# (undocumented) — that is the slice's interactive Phase-5 test, not a harness case.
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail
export TZ=UTC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/pause-watch.sh"
HELPER="$SCRIPT_DIR/pause-request.sh"
FLOW="$SCRIPT_DIR/flow-state.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
WORKFLOW="$REPO_ROOT/skills/workflow/SKILL.md"
PAUSE_MD="$REPO_ROOT/commands/pause.md"
HANDOFF_MD="$REPO_ROOT/commands/handoff.md"
OLD_BASH=/bin/bash

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
expect() { # <label> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — got '$2', want '$3'"; fi
}
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is required" >&2; exit 2; }
[[ -x "$OLD_BASH" ]] || { echo "FATAL: $OLD_BASH not found" >&2; exit 2; }

ROOT="$(mktemp -d)"
trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
PLANS="$P/.claude/plans"
MARKER="$PLANS/.pause-request"
PLAN="$PLANS/slice-001-demo.md"
mkdir -p "$P/.claude/project" "$PLANS"
S=11111111-aaaa-bbbb-cccc-000000000001      # this session
OTHER=22222222-aaaa-bbbb-cccc-000000000002  # any other session

# --- fixture builders -----------------------------------------------------------------------------
# payload <prompt> [session] — a UserPromptSubmit payload with the fields Claude Code sends
payload() {
  python3 - "$1" "${2-$S}" <<'PY'
import json, sys
print(json.dumps({"session_id": sys.argv[2], "transcript_path": "/x/t.jsonl", "cwd": "/x", "prompt_id": "p-1",
                  "permission_mode": "default", "hook_event_name": "UserPromptSubmit", "prompt": sys.argv[1]}))
PY
}
# plan <status> — the one slice plan of the fixture project
plan() { printf '# Slice 001 — demo\n\n> Status: %s\n> Slice-ID: slice-001\n\n## Goal\n\nx\n' "$1" > "$PLAN"; }
# plan_resumed <status> <datetime> — a resumed slice: the Pause Note carries the `> Resumed:` line /craft:continue 4a writes
plan_resumed() {
  printf '# Slice 001 — demo\n\n> Status: %s\n> Slice-ID: slice-001\n\n## Goal\n\nx\n\n## Pause Note\n\n> Resumed: %s → %s\n> Paused: 2026-10-08\n\nnote\n' "$1" "$2" "$1" > "$PLAN"
}
profile() { printf '# CRAFT Profile\n\n> Preset: balanced\n\n%s\n\n## Operational Language\n\n- **Chat:** en\n' "$1" > "$P/.claude/project/craft-profile.md"; }
noprofile() { rm -f "$P/.claude/project/craft-profile.md"; }
reset() { chmod u+w "$PLANS" 2>/dev/null; rm -f "$MARKER" "$PLANS"/slice-*.md; noprofile; plan implementing; }
marker_state() { sed -n 's/^STATE=//p' "$MARKER" 2>/dev/null | head -1; }
marker_key() { sed -n "s/^$1=//p" "$MARKER" 2>/dev/null | head -1; }
write_marker() { # <content with \n> — a marker as a helper or a hand would leave it
  printf "$1" > "$MARKER"
}

helper() { # <args…> — the helper in this session, project P
  (cd "$P" && CLAUDE_CODE_SESSION_ID="${SESS-$S}" bash "$HELPER" "$@" 2>&1)
}
key() { # <KEY> <output> — one value out of KEY=value lines
  printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1
}

# --- running the hook -----------------------------------------------------------------------------
OUT=""; ERRTXT=""; RC=0
run_hook() { # <shell> <stdin>
  local errf="$ROOT/err"
  OUT="$(printf '%s' "$2" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$1" "$HOOK" 2>"$errf"))"; RC=$?
  ERRTXT="$(cat "$errf" 2>/dev/null)"
}
# hook_case <label> <stdin payload> <request|none> — under both shells: exit 0, no stdout, no stderr, and the marker
# either requested for $S (request) or untouched-absent (none). The marker is cleared before every leg.
hook_case() {
  local label="$1" input="$2" want="$3" sh got
  for sh in "${LEGS[@]}"; do
    [[ -d "$MARKER" ]] || rm -f "$MARKER"
    run_hook "$sh" "$input"
    got=none; [[ "$(marker_state)" == requested && "$(marker_key SESSION)" == "$S" ]] && got=request
    if [[ "$RC" -ne 0 ]]; then bad "$label [$sh] — exit $RC"
    elif [[ -n "$OUT" ]]; then bad "$label [$sh] — the hook printed on stdout (it must never block): $OUT"
    elif [[ -n "$ERRTXT" ]]; then bad "$label [$sh] — error text on stderr: $ERRTXT"
    elif [[ "$got" != "$want" ]]; then bad "$label [$sh] — got '$got', want '$want'"
    else ok "$label [$sh]"; fi
  done
}

echo "== the files exist, and /bin/bash is a 3.2"
[[ -f "$HELPER" ]] && ok "scripts/pause-request.sh exists" || bad "scripts/pause-request.sh is missing"
[[ -f "$HOOK" ]] && ok "hooks/pause-watch.sh exists" || { bad "hooks/pause-watch.sh is missing"; echo; echo "RESULT: $PASS passed, $FAIL failed"; exit 1; }
OLD_MAJOR="$("$OLD_BASH" -c 'echo ${BASH_VERSINFO[0]}')"
LEGS=(bash "$OLD_BASH")
if [[ "$OLD_MAJOR" == 3 ]]; then
  ok "$OLD_BASH is a bash 3.x (the baseline hooks must run on)"
elif [[ "$(uname)" == Darwin ]]; then
  bad "$OLD_BASH is bash $OLD_MAJOR on macOS — the bash 3.2 leg cannot run (the system bash is 3.2)"
else
  LEGS=(bash)
  echo "  SKIP  $OLD_BASH is bash $OLD_MAJOR here — the 3.2 leg is skipped, the cases run under the current bash only (macOS runs both)"
fi

echo "== the hook: the word matrix (whole message, trimmed, case-folded)"
reset
hook_case "pause → request" "$(payload 'pause')" request
hook_case "'PAUSE ' (upper case, trailing blank) → request" "$(payload 'PAUSE ')" request
hook_case "'  Pause' + newline (leading blanks, trailing newline) → request" "$(payload $'  Pause\n')" request
hook_case "pausieren → request" "$(payload 'pausieren')" request
hook_case "Pausieren → request" "$(payload 'Pausieren')" request
hook_case "/craft:pause → request" "$(payload '/craft:pause')" request
hook_case "'pause bitte nach X' (merely contains the word) → none" "$(payload 'pause bitte nach X')" none
hook_case "'please pause' → none" "$(payload 'please pause')" none
hook_case "'pausiert' → none" "$(payload 'pausiert')" none
hook_case "'/craft:pause now' → none" "$(payload '/craft:pause now')" none
hook_case "'pause\\nmore' (a second line) → none" "$(payload $'pause\nmore')" none
hook_case "stop → none (deliberately no pause word)" "$(payload 'stop')" none
hook_case "halt → none (deliberately no pause word)" "$(payload 'halt')" none
hook_case "empty prompt → none" "$(payload '')" none
hook_case "'ja, mach weiter' → none" "$(payload 'ja, mach weiter')" none

echo "== the hook: fail open — nothing it cannot classify is a request, nothing is ever printed"
hook_case "not JSON → none" 'this is not json' none
hook_case "empty stdin → none" '' none
hook_case "a JSON array → none" '[]' none
hook_case "an empty object → none" '{}' none
hook_case "no session_id → none" '{"prompt":"pause"}' none
hook_case "an empty session_id → none" '{"session_id":"","prompt":"pause"}' none
hook_case "a non-string prompt → none" "{\"session_id\":\"$S\",\"prompt\":5}" none
hook_case "a session id with a slash (not a marker-safe id) → none" '{"session_id":"a/b","prompt":"pause"}' none
if [[ "$(id -u)" != 0 ]]; then
  reset; chmod a-w "$PLANS"
  hook_case "an unwritable plans directory → the prompt passes, no stderr" "$(payload 'pause')" none
  chmod u+w "$PLANS"
else
  echo "  SKIP  unwritable plans directory — running as root, chmod does not bite"
fi
reset; mkdir "$MARKER"    # a directory where the marker file belongs: the write cannot succeed
hook_case "a directory in the marker's place → none, no stderr" "$(payload 'pause')" none
rmdir "$MARKER"

echo "== the hook: only an auto-flow session with an active slice"
reset; profile $'## Slice Flow\n\n- **Mode:** manual'
hook_case "Mode: manual → none (the countdown's own pause stays)" "$(payload 'pause')" none
reset; profile $'## Slice Flow\n\n- **Mode:** auto'
hook_case "Mode: auto → request" "$(payload 'pause')" request
reset; profile $'## Slice Flow\n\n```\n- **Mode:** manual\n```\n\n- **Mode:** auto'
hook_case "a manual line in a fenced example is no content → request" "$(payload 'pause')" request
reset; profile $'## Slice Flow\n\n<!--\n- **Mode:** manual\n-->\n'
hook_case "a manual line in an HTML comment is no content → request" "$(payload 'pause')" request
reset; profile $'## Execution\n\n- **Mode:** manual\n\n## Slice Flow\n\n- **Mode:** auto'
hook_case "Execution -> Mode: manual is another key → request" "$(payload 'pause')" request
reset; profile $'## Slice Flow\n\n- **Mode:** manual\n\n## Execution\n\n- **Mode:** auto'
hook_case "Slice Flow -> Mode: manual, a later block says auto → none" "$(payload 'pause')" none
reset; noprofile
hook_case "no profile (the default is auto) → request" "$(payload 'pause')" request
reset; rm -f "$PLAN"
hook_case "no slice plan at all → none" "$(payload 'pause')" none
for st in implementing testing review refactoring reviewing committing; do
  reset; plan "$st"
  hook_case "slice at $st → request" "$(payload 'pause')" request
done
for st in planning paused blocked committed awaiting-release awaiting-approval; do
  reset; plan "$st"
  hook_case "slice at $st → none" "$(payload 'pause')" none
done
reset; plan paused; printf '# Slice 002\n\n> Status: implementing\n\n## Goal\n' > "$PLANS/slice-002-other.md"
hook_case "one paused and one implementing slice → request (an active slice exists)" "$(payload 'pause')" request
reset; printf '# Slice 001\n\n## Goal\n\n> Status: implementing\n' > "$PLAN"
hook_case "a Status line below the first ## heading is no frontmatter → none" "$(payload 'pause')" none
reset; printf '# Epic\n\n> Status: implementing\n' > "$PLANS/epic-001-x.md"; rm -f "$PLAN"
hook_case "an epic plan is no slice plan → none" "$(payload 'pause')" none

echo "== the hook: an existing marker"
reset
for sh in "${LEGS[@]}"; do
  write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
  run_hook "$sh" "$(payload 'pause')"
  [[ "$(marker_key SINCE)" != "2026-10-08T10:00:00Z" ]] && ok "a request of this session is restamped, not kept [$sh]" || bad "a request of this session kept its old SINCE [$sh]"
  write_marker "STATE=requested\nSESSION=$OTHER\nSINCE=2026-10-08T10:00:00Z\n"
  run_hook "$sh" "$(payload 'pause')"
  expect "a request of another session is replaced [$sh]" "$(marker_key SESSION)" "$S"
  write_marker "STATE=consumed\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\nCONSUMED=2026-10-08T10:05:00Z\n"
  run_hook "$sh" "$(payload 'pause')"
  expect "a consumed marker is requested again [$sh]" "$(marker_state)" "requested"
  write_marker "garbage\n"
  run_hook "$sh" "$(payload 'pause')"
  expect "a malformed marker is replaced [$sh]" "$(marker_state)" "requested"
done
reset
run_hook bash "$(payload 'pause')"
since="$(marker_key SINCE)"
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ok "the hook stamps SINCE as a UTC datetime" || bad "the hook's SINCE is not a UTC datetime — '$since'"
st="$(helper state --project "$P")"
expect "the helper reads the hook's marker (LIVE=yes for this session)" "$(key LIVE "$st")" "yes"

echo "== the helper: request / state / consume — the marker is kept as state, never removed"
reset
out="$(helper state --project "$P")"
expect "no marker → STATE=none" "$(key STATE "$out")" "none"
expect "no marker → LIVE=no" "$(key LIVE "$out")" "no"
out="$(helper consume --project "$P")"
expect "consume without a marker → CONSUMED=no" "$(key CONSUMED "$out")" "no"
[[ ! -e "$MARKER" ]] && ok "consume without a marker writes nothing" || bad "consume without a marker created the marker"
out="$(helper request --project "$P")"
expect "request → REQUESTED=yes" "$(key REQUESTED "$out")" "yes"
expect "request names this session" "$(key SESSION "$out")" "$S"
expect "the marker says STATE=requested" "$(marker_state)" "requested"
expect "the marker holds this session" "$(marker_key SESSION)" "$S"
since1="$(marker_key SINCE)"
[[ "$since1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ok "request stamps SINCE as a UTC datetime" || bad "request's SINCE is not a UTC datetime — '$since1'"
out="$(helper state --project "$P")"
expect "state: STATE=requested" "$(key STATE "$out")" "requested"
expect "state: LIVE=yes for this session" "$(key LIVE "$out")" "yes"
expect "state: SINCE as written" "$(key SINCE "$out")" "$since1"
sleep 1
helper request --project "$P" >/dev/null
[[ "$(marker_key SINCE)" > "$since1" ]] && ok "a second request restamps SINCE (a fresh stamp survives a later resume)" || bad "a second request kept the old SINCE"
since1="$(marker_key SINCE)"
out="$(SESS="$OTHER" helper state --project "$P")"
expect "state in another session: STATE=requested, LIVE=no" "$(key STATE "$out")/$(key LIVE "$out")" "requested/no"
out="$(SESS="" helper state --project "$P")"
expect "state without a session id: LIVE=no (doubt is no request)" "$(key LIVE "$out")" "no"
out="$(helper consume --project "$P")"
expect "consume → CONSUMED=yes" "$(key CONSUMED "$out")" "yes"
expect "the marker says STATE=consumed" "$(marker_state)" "consumed"
expect "consume keeps SESSION" "$(marker_key SESSION)" "$S"
expect "consume keeps SINCE" "$(marker_key SINCE)" "$since1"
[[ "$(marker_key CONSUMED)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ok "consume stamps CONSUMED as a UTC datetime" || bad "consume's CONSUMED is not a UTC datetime"
out="$(helper state --project "$P")"
expect "state after consume: STATE=consumed, LIVE=no" "$(key STATE "$out")/$(key LIVE "$out")" "consumed/no"
out="$(helper consume --project "$P")"
expect "a second consume → CONSUMED=no (nothing left to consume)" "$(key CONSUMED "$out")" "no"
[[ -f "$MARKER" ]] && ok "the marker is still there (kept as state, never removed)" || bad "the marker was removed"
helper request --project "$P" >/dev/null
expect "a request after a consume starts a new one" "$(marker_state)" "requested"
# consume writes over a request of another session too — the human paused the slice, the request is moot
write_marker "STATE=requested\nSESSION=$OTHER\nSINCE=2026-10-08T10:00:00Z\n"
out="$(helper consume --project "$P")"
expect "consume settles a request of another session as well" "$(key CONSUMED "$out")/$(marker_state)" "yes/consumed"
# request over a marker of another session
write_marker "STATE=requested\nSESSION=$OTHER\nSINCE=2026-10-08T10:00:00Z\n"
helper request --project "$P" >/dev/null
expect "request replaces a request of another session" "$(marker_key SESSION)" "$S"
# malformed markers: no request, and consume does not rewrite what it cannot read
for bad_content in 'garbage\n' 'STATE=requested\nSESSION=%s\n' 'STATE=maybe\nSESSION=%s\nSINCE=2026-10-08T10:00:00Z\n' \
                   'STATE=requested\nSESSION=%s\nSINCE=yesterday\n' 'STATE=requested\nSESSION=%s\nSINCE=2026-10-08T10:00:00Z\nSTATE=consumed\n' \
                   'STATE=requested\nSESSION=a b\nSINCE=2026-10-08T10:00:00Z\n' ''; do
  # shellcheck disable=SC2059
  printf "$bad_content" "$S" > "$MARKER"
  out="$(helper state --project "$P")"
  expect "malformed marker → STATE=invalid, LIVE=no — $(printf '%q' "$bad_content" | cut -c1-48)" "$(key STATE "$out")/$(key LIVE "$out")" "invalid/no"
done
printf 'garbage\n' > "$MARKER"
out="$(helper consume --project "$P")"
expect "consume does not rewrite a malformed marker" "$(key CONSUMED "$out")/$(cat "$MARKER")" "no/garbage"
helper request --project "$P" >/dev/null
expect "request replaces a malformed marker" "$(marker_state)" "requested"
printf 'STATE=requested\r\nSESSION=%s\r\nSINCE=2026-10-08T10:00:00Z\r\n' "$S" > "$MARKER"
out="$(helper state --project "$P")"
expect "a CRLF marker reads (LIVE=yes)" "$(key LIVE "$out")" "yes"
# errors and failures
out="$(SESS="" helper request --project "$P")"
expect "request without a session id → REQUESTED=no, REASON=no_session_id" "$(key REQUESTED "$out")/$(key REASON "$out")" "no/no_session_id"
out="$(SESS="a/b" helper request --project "$P")"
expect "request with an unsafe session id → REASON=bad_session_id" "$(key REASON "$out")" "bad_session_id"
out="$(helper bogus 2>&1)"; rc=$?
[[ $rc -eq 2 && "$out" == *"unknown_command"* ]] && ok "an unknown command exits 2 with unknown_command" || bad "unknown command — exit $rc, '$out'"
out="$(helper state --project "$ROOT/nowhere" 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && ok "an unreachable --project exits 2" || bad "an unreachable --project — exit $rc, '$out'"
if [[ "$(id -u)" != 0 ]]; then
  rm -f "$MARKER"; chmod a-w "$PLANS"
  out="$(helper request --project "$P")"; rc=$?
  chmod u+w "$PLANS"
  [[ $rc -eq 0 && "$(key REQUESTED "$out")" == no && "$(key REASON "$out")" == write_failed ]] && ok "an unwritable plans directory → REQUESTED=no, REASON=write_failed, exit 0" || bad "unwritable plans directory — exit $rc, '$out'"
fi
echo "== the helper: a request older than the plan's resume is no request"
reset
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
plan_resumed implementing 2026-10-08T11:00:00Z
out="$(helper state --project "$P" --plan "$PLAN")"
expect "SINCE before the plan's Resumed: → LIVE=no" "$(key LIVE "$out")" "no"
expect "…and STATE stays requested (the marker itself is unchanged)" "$(key STATE "$out")" "requested"
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T12:00:00Z\n"
out="$(helper state --project "$P" --plan "$PLAN")"
expect "SINCE after the plan's Resumed: → LIVE=yes" "$(key LIVE "$out")" "yes"
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
plan implementing
out="$(helper state --project "$P" --plan "$PLAN")"
expect "a plan that was never resumed → LIVE=yes" "$(key LIVE "$out")" "yes"
printf '# Slice 001\n\n> Status: implementing\n\n## Pause Note\n\n> Resumed: 2026-10-08T09:00:00Z → implementing\n\n## Earlier Pause Notes\n\n> Resumed: 2026-10-08T12:00:00Z → testing\n' > "$PLAN"
out="$(helper state --project "$P" --plan "$PLAN")"
expect "only the ## Pause Note section counts (a later date elsewhere is ignored) → LIVE=yes" "$(key LIVE "$out")" "yes"
# the old request is typed again after a resume: the restamp makes it count (an old SINCE kept would swallow it)
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T09:00:00Z\n"
printf '# Slice 001\n\n> Status: implementing\n\n## Pause Note\n\n> Resumed: 2026-10-08T10:00:00Z → implementing\n' > "$PLAN"
helper request --project "$P" >/dev/null
out="$(helper state --project "$P" --plan "$PLAN")"
expect "the word typed again after a resume counts (request restamps over a pre-resume SINCE)" "$(key LIVE "$out")" "yes"
printf '# Slice 001\n\n> Status: implementing\n\n## Pause Note\n\n> Resumed: 2026-10-08 12:00 → implementing\n' > "$PLAN"
out="$(helper state --project "$P" --plan "$PLAN")"
expect "a Resumed: stamp that is not UTC ISO cannot be compared → LIVE=no (doubt is no request)" "$(key LIVE "$out")" "no"
out="$(helper state --project "$P" --plan "$ROOT/no-such-plan.md")"
expect "a plan that cannot be read → LIVE=no (doubt is no request)" "$(key LIVE "$out")" "no"

echo "== flow-state.sh: STOP=pause-requested"
flow() { # <from|-> <plan> — flow-state in this session
  local from=() ; [[ "$1" == - ]] || from=(--from "$1")
  (cd "$P" && CLAUDE_CODE_SESSION_ID="${SESS-$S}" bash "$FLOW" --project "$P" "${from[@]+"${from[@]}"}" "$2" 2>&1)
}
reset
expect "no marker, implementing → NEXT=/craft:build" "$(key NEXT "$(flow - "$PLAN")")" "/craft:build"
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
out="$(flow - "$PLAN")"
expect "a live request at implementing → STOP=pause-requested" "$(key STOP "$out")" "pause-requested"
expect "…and no NEXT= line" "$(key NEXT "$out")" ""
expect "…MODE and STATUS still print" "$(key MODE "$out")/$(key STATUS "$out")" "auto/implementing"
out="$(flow implementing "$PLAN")"
expect "a live request wins over no-progress (the sub-task boundary asks with --from) → STOP=pause-requested" "$(key STOP "$out")" "pause-requested"
reset; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
rm -f "$MARKER"
expect "the same call without a request says no-progress" "$(key STOP "$(flow implementing "$PLAN")")" "no-progress"
for st in testing review refactoring reviewing committing; do
  reset; plan "$st"; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
  expect "a live request at $st → STOP=pause-requested (where NEXT= would have started a phase)" "$(key STOP "$(flow - "$PLAN")")" "pause-requested"
done
reset; plan testing
expect "…and without a request the testing status would have chained" "$(key NEXT "$(flow - "$PLAN")")" "/craft:test"
write_marker "STATE=consumed\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\nCONSUMED=2026-10-08T10:05:00Z\n"
expect "a consumed request → NEXT= again" "$(key NEXT "$(flow - "$PLAN")")" "/craft:test"
write_marker "STATE=requested\nSESSION=$OTHER\nSINCE=2026-10-08T10:00:00Z\n"
expect "a request of another session → NEXT= (not a pause)" "$(key NEXT "$(flow - "$PLAN")")" "/craft:test"
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "no session id in the environment → NEXT= (a request that cannot be attributed is none)" "$(key NEXT "$(SESS="" flow - "$PLAN")")" "/craft:test"
printf 'garbage\n' > "$MARKER"
expect "a malformed marker → NEXT= (a phantom pause would halt a flow the human did not stop)" "$(key NEXT "$(flow - "$PLAN")")" "/craft:test"
plan_resumed testing 2026-10-08T11:00:00Z
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "a request older than the plan's resume → NEXT=" "$(key NEXT "$(flow - "$PLAN")")" "/craft:test"
write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T12:00:00Z\n"
expect "a request newer than the plan's resume → STOP=pause-requested" "$(key STOP "$(flow - "$PLAN")")" "pause-requested"
reset; plan testing; profile $'## Slice Flow\n\n- **Mode:** manual'; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "manual mode → STOP=manual (the pause word is the countdown's, not the request's)" "$(key STOP "$(flow - "$PLAN")")" "manual"
reset; plan paused; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "a slice already paused → STOP=paused (the status stop comes first)" "$(key STOP "$(flow - "$PLAN")")" "paused"
reset; plan blocked; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "a blocked slice → STOP=blocked" "$(key STOP "$(flow - "$PLAN")")" "blocked"
reset; write_marker "STATE=requested\nSESSION=$S\nSINCE=2026-10-08T10:00:00Z\n"
expect "no plan → STOP=no-plan (nothing to pause)" "$(key STOP "$(flow - "$PLANS/slice-999-none.md")")" "no-plan"
out="$(flow - "$PLAN")"
[[ "$(printf '%s\n' "$out" | grep -c '^\(NEXT\|STOP\)=')" == 1 ]] && ok "exactly one NEXT= / STOP= line" || bad "not exactly one NEXT=/STOP= line — $out"
grep -q 'pause-requested' "$FLOW" && ! grep -q '(reserved)' "$FLOW" && ok "flow-state.sh documents pause-requested as live, no longer reserved" || bad "flow-state.sh still marks pause-requested reserved (or does not name it)"

echo "== hooks.json: the registration"
python3 - "$HOOKS_JSON" <<'PY' && ok "hooks.json: UserPromptSubmit runs cache-guard.sh and pause-watch.sh, both with a timeout" || bad "hooks.json: the UserPromptSubmit registration of pause-watch.sh is missing or wrong"
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h for g in d["hooks"]["UserPromptSubmit"] for h in g["hooks"]]
names = {h["command"].rsplit("/", 1)[-1]: h for h in cmds}
assert "cache-guard.sh" in names and "pause-watch.sh" in names, names
h = names["pause-watch.sh"]
assert h["type"] == "command" and h["command"] == "bash ${CLAUDE_PLUGIN_ROOT}/hooks/pause-watch.sh", h
assert isinstance(h.get("timeout"), int) and 0 < h["timeout"] <= 30, h
PY
python3 -c 'import json,sys; sys.exit(0 if "pause-watch" in json.load(open(sys.argv[1]))["description"] else 1)' "$HOOKS_JSON" && ok "hooks.json: the description names pause-watch" || bad "hooks.json: the description does not name pause-watch"

echo "== the sites of the rule"
grep -q 'pause-request.sh' "$WORKFLOW" && grep -q 'pause-requested' "$WORKFLOW" && ok "skills/workflow/SKILL.md: the Auto flow rule names pause-request.sh and pause-requested" || bad "skills/workflow/SKILL.md does not carry the pause rule"
grep -q 'pause-request.sh" request' "$WORKFLOW" && ok "the rule: the agent records a queued pause word itself (pause-request.sh request)" || bad "the rule does not tell the agent to record a queued pause word"
grep -qi 'sub-task' <(sed -n '/Auto flow (the Slice Flow rule/,/^---$/p' "$WORKFLOW") && ok "the rule names the sub-task boundary" || bad "the rule does not name the sub-task boundary"
grep -q 'pause-request.sh' "$PAUSE_MD" && grep -q 'consume' "$PAUSE_MD" && ok "commands/pause.md consumes the request" || bad "commands/pause.md does not consume the request"
grep -q 'pause-request.sh' "$HANDOFF_MD" && grep -q 'consume' "$HANDOFF_MD" && ok "commands/handoff.md consumes the request" || bad "commands/handoff.md does not consume the request"
for f in "$PAUSE_MD" "$HANDOFF_MD"; do
  fm="$(sed -n '1,/^---$/p;' "$f" | sed -n '/^allowed-tools:/p')"
  [[ "$fm" == *'"Bash"'* ]] && ok "$(basename "$f") allows Bash (it runs the helper)" || bad "$(basename "$f") does not allow Bash in its frontmatter"
done
for f in commit abort; do
  grep -q 'pause-request.sh" consume' "$REPO_ROOT/commands/$f.md" && ok "commands/$f.md settles a pending request (no leak into the next slice)" || bad "commands/$f.md does not settle a pending pause request"
done
grep -q 'Any `STOP=` settles a pending pause request' "$WORKFLOW" && ok "the rule: any STOP= at a phase end settles a pending request" || bad "the rule does not settle a request on another STOP="
BUILD_MD="$REPO_ROOT/commands/build.md"
grep -q 'pause-requested' "$BUILD_MD" && ok "commands/build.md checks the pause request at the sub-task boundary" || bad "commands/build.md does not check the pause request at the sub-task boundary"
# The hook's copies are bound, not trusted (rules.md): its "in flight" statuses to flow-state's map, its Mode reading to flow-state --mode,
# its writer to the helper's reader (both directions).
want="$(bash "$FLOW" --map | awk -F'\t' '$2 == "NEXT" && $1 != "planning" { print $1 }' | sort | tr '\n' ' ')"
have="$(printf '%s' "$(sed -n 's/^ACTIVE = (\(.*\))$/\1/p' "$HOOK")" | tr ',' '\n' | tr -d '" ' | sort | tr '\n' ' ')"
expect "the hook's in-flight statuses = flow-state --map's NEXT statuses minus planning" "$have" "$want"
for body in $'- **Mode:** auto' $'- **Mode:** manual' $'```\n- **Mode:** manual\n```' $'<!--\n- **Mode:** manual\n-->' ''; do
  reset; profile "## Slice Flow"$'\n\n'"$body"
  fmode="$(bash "$FLOW" --mode --project "$P" | sed -n 's/^MODE=//p')"
  [[ "$fmode" == manual ]] && wantw=none || wantw=request
  hook_case "hook and flow-state --mode agree (flow-state says $fmode) → $wantw — $(printf '%s' "$body" | tr '\n' ' ')" "$(payload 'pause')" "$wantw"
done
reset; helper request --project "$P" >/dev/null; run_hook bash "$(payload 'pause')"
out="$(helper state --project "$P")"
expect "a marker the helper wrote, rewritten by the hook, is still read by the helper (LIVE=yes)" "$(key LIVE "$out")" "yes"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
