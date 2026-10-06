#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-cache-guard.sh — self-contained tests for the autopilot's cache guard (slice-060, design record §7):
# the UserPromptSubmit hook hooks/cache-guard.sh, the arming helper scripts/cache-guard-marker.sh, the profile
# key that sets the threshold, and the sites that arm / disarm the guard. Run it directly:
#
#   bash scripts/test-cache-guard.sh
#
# The case table below was written BEFORE the hook existed (the plan's Test Strategy (a)); it is the contract
# the hook is judged by. The hook is bash-3.2-compatible on purpose (rules.md → Bash baseline), so every hook
# case runs twice — under the bash this harness runs in and under /bin/bash — and a run that prints error text
# on stderr fails (a 3.2 run skips a failing command and carries on green; `bash -n` accepts bash-4 constructs).
# All clocks are the real one, every fixture is built relative to it; times print in UTC (TZ=UTC).
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail
export TZ=UTC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/cache-guard.sh"
MARKER_SH="$SCRIPT_DIR/cache-guard-marker.sh"
USAGE="$SCRIPT_DIR/usage-state.sh"
TAPPER="$SCRIPT_DIR/statusline-tap.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
EXECUTE="$REPO_ROOT/commands/execute.md"
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
mkdir -p "$P/.claude/project" "$P/.claude/plans"
TAP="$ROOT/tap.json"
MARKER="$P/.claude/plans/.cache-guard"
NOW="$(date +%s)"
hhmm() { date -u -r "$1" +%H:%M 2>/dev/null || date -u -d "@$1" +%H:%M; }
stamp() { date -u -r "$1" +%Y%m%d%H%M 2>/dev/null || date -u -d "@$1" +%Y%m%d%H%M; }
S=11111111-aaaa-bbbb-cccc-000000000001      # the armed session
OTHER=22222222-aaaa-bbbb-cccc-000000000002  # any other session
EPIC=epic-003

# --- fixture builders -----------------------------------------------------------------------------
# payload <prompt> [session] — a UserPromptSubmit payload with the fields Claude Code 2.1.291 sends
payload() {
  python3 - "$1" "${2-$S}" <<'PY'
import json, sys
print(json.dumps({"session_id": sys.argv[2], "transcript_path": "/x/t.jsonl", "cwd": "/x", "prompt_id": "p-1",
                  "permission_mode": "default", "hook_event_name": "UserPromptSubmit", "prompt": sys.argv[1]}))
PY
}
# marker <session> <epic> — an armed marker, as scripts/cache-guard-marker.sh writes it
marker() { printf 'state=armed\nsession_id=%s\nepic=%s\narmed=2026-10-06T10:00:00Z\n' "$1" "$2" > "$MARKER"; }
# tap <session> <expires_at offset from now, s> <recache tokens> — a statusline JSON like Claude Code 2.1.290's
tap() {
  printf '{"session_id":"%s","prompt_cache":{"warm":false,"ttl":"1h","expires_at":%s,"requests":29,"recache_tokens_if_cold":%s},"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":%s}}}' \
    "$1" "$((NOW + $2))" "$3" "$((NOW + 7200))" > "$TAP"
}
profile() { printf '# CRAFT Profile\n\n> Preset: balanced\n\n%s\n\n## Operational Language\n\n- **Chat:** en\n' "$1" > "$P/.claude/project/craft-profile.md"; }
noprofile() { rm -f "$P/.claude/project/craft-profile.md"; }
reset() { rm -f "$MARKER" "$TAP"; noprofile; }

# --- running the hook -----------------------------------------------------------------------------
OUT=""; ERRTXT=""; RC=0
run_hook() { # <shell> <stdin>
  local errf="$ROOT/err"
  OUT="$(printf '%s' "$2" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" CRAFT_USAGE_TAP="$TAP" "$1" "$HOOK" 2>"$errf"))"; RC=$?
  ERRTXT="$(cat "$errf" 2>/dev/null)"
}
# classify the last output: pass (nothing), block (exactly {"decision":"block","reason":<text>}) or other
klass() {
  if [[ -z "$OUT" ]]; then echo pass; return; fi
  printf '%s' "$OUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("other"); sys.exit()
ok = isinstance(d, dict) and set(d) == {"decision", "reason"} and d["decision"] == "block" and isinstance(d["reason"], str) and d["reason"]
print("block" if ok else "other")'
}
# case_ <label> <stdin payload> <pass|block> — under both shells; exit 0, no stderr, stdout empty or the block JSON
case_() {
  local label="$1" input="$2" want="$3" sh got first=""
  for sh in "${LEGS[@]}"; do
    run_hook "$sh" "$input"
    got="$(klass)"
    if [[ "$RC" -ne 0 ]]; then bad "$label [$sh] — exit $RC"
    elif [[ -n "$ERRTXT" ]]; then bad "$label [$sh] — error text on stderr: $ERRTXT"
    elif [[ "$got" != "$want" ]]; then bad "$label [$sh] — got '$got' ($OUT), want '$want'"
    else ok "$label [$sh]"; fi
    if [[ -z "$first" ]]; then first="$OUT"; elif [[ "$OUT" != "$first" ]]; then bad "$label — bash and $OLD_BASH printed different output"; fi
  done
}

echo "== the hook: the files exist, and /bin/bash is a 3.2"
[[ -f "$HOOK" ]] && ok "hooks/cache-guard.sh exists" || { bad "hooks/cache-guard.sh is missing"; echo; echo "RESULT: $PASS passed, $FAIL failed"; exit 1; }
[[ -f "$MARKER_SH" ]] && ok "scripts/cache-guard-marker.sh exists" || bad "scripts/cache-guard-marker.sh is missing"
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

echo "== the hook: block and pass"
HUMAN="$(payload 'ja, mach weiter')"
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
case_ "armed, same session, cache cold, 150000 tokens → block" "$HUMAN" block
run_hook bash "$HUMAN"
reason="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reason"])')"
[[ "$reason" == *"/clear, then /craft:execute epic-003 --autopilot"* ]] && ok "the reason names the restart: /clear, then /craft:execute epic-003 --autopilot" || bad "the reason does not name the restart — '$reason'"
[[ "$reason" == *"$(hhmm "$((NOW - 60))")"* ]] && ok "the reason names when the cache expired (HH:MM from the tap)" || bad "the reason does not name the expiry time — '$reason'"
[[ "$reason" == *"150000"* ]] && ok "the reason names the tokens a re-write would cost" || bad "the reason does not name the token count — '$reason'"
reset; tap "$S" -60 150000
case_ "no marker file → pass" "$HUMAN" pass
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
case_ "a prompt from another session than the armed one → pass" "$(payload 'ja' "$OTHER")" pass
reset; marker "$S" "$EPIC"; tap "$S" 600 150000
case_ "cache still warm (expires in 10 min) → pass" "$HUMAN" pass
reset; marker "$S" "$EPIC"; tap "$OTHER" -60 150000
case_ "the tap belongs to another session → pass (cannot judge)" "$HUMAN" pass
reset; marker "$S" "$EPIC"
case_ "no tap file → pass" "$HUMAN" pass
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
touch -t "$(stamp "$((NOW - 3600))")" "$TAP"
case_ "stale tap (older than 300 s) → pass" "$HUMAN" pass
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
touch -t "$(stamp "$((NOW - 240))")" "$TAP"
case_ "a tap 240 s old is still a reading → block" "$HUMAN" block

echo "== the hook: the threshold on recache_tokens_if_cold (default 100000)"
reset; marker "$S" "$EPIC"; tap "$S" -60 99999
case_ "99999 tokens (below the default) → pass" "$HUMAN" pass
tap "$S" -60 100000
case_ "100000 tokens (at the default) → block" "$HUMAN" block
tap "$S" -60 100001
case_ "100001 tokens → block" "$HUMAN" block
profile '## Autopilot

- **Cache-guard-recache-tokens:** 500000'
tap "$S" -60 150000
case_ "profile threshold 500000, 150000 tokens → pass" "$HUMAN" pass
tap "$S" -60 600000
case_ "profile threshold 500000, 600000 tokens → block" "$HUMAN" block
tap "$S" -60 500000
case_ "profile threshold 500000, exactly 500000 tokens → block" "$HUMAN" block
profile '## Autopilot

> a comment

- **Budget-in-slice:** 95
- **Cache-guard-recache-tokens:** 5000
'
tap "$S" -60 6000
case_ "profile threshold 5000 among other keys and a comment, 6000 tokens → block" "$HUMAN" block
tap "$S" -60 4000
case_ "profile threshold 5000, 4000 tokens → pass" "$HUMAN" pass
profile '## Operational Language

- **Cache-guard-recache-tokens:** 500000'
tap "$S" -60 150000
case_ "the key outside ## Autopilot is not read → default 100000, 150000 tokens → block" "$HUMAN" block
for bad_value in abc 0 -5 1.5 '1 000' '' 99999999999999999999x; do
  profile "## Autopilot

- **Cache-guard-recache-tokens:** $bad_value"
  tap "$S" -60 150000
  case_ "invalid profile value '$bad_value' → the default (100000): 150000 tokens → block" "$HUMAN" block
  tap "$S" -60 99999
  case_ "invalid profile value '$bad_value' → the default (100000): 99999 tokens → pass" "$HUMAN" pass
done
noprofile

echo "== the hook: a builder's hand-back and a task notification are never a human prompt"
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
case_ "<agent-message from=…> hand-back → pass" "$(payload '<agent-message from="a1b2c3">
[Subagent hand-back] The text below is the final report of a subagent')" pass
case_ "<task-notification> → pass" "$(payload '<task-notification>
<task-id>b1</task-id>
</task-notification>')" pass
case_ "a hand-back with leading whitespace / newlines → pass" "$(payload '

  <agent-message from="a1">x')" pass
case_ "a human prompt that merely mentions <agent-message from= mid-text → block" "$(payload 'was bedeutet <agent-message from= in dem Hook?')" block
case_ "/clear (the very restart the block names) → pass" "$(payload '/clear')" pass
case_ "/exit → pass" "$(payload '/exit')" pass
case_ "/quit → pass" "$(payload '/quit')" pass
case_ "/clearly (not /clear) → block" "$(payload '/clearly not')" block
case_ "an empty prompt → block (it is a human prompt, only cold)" "$(payload '')" block

echo "== the hook: anything it cannot classify passes (fail open)"
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
case_ "the payload is not JSON → pass" 'not json at all' pass
case_ "the payload is a JSON array → pass" '["a"]' pass
case_ "the payload is empty → pass" '' pass
case_ "the payload has no prompt → pass" '{"session_id":"'"$S"'"}' pass
case_ "the payload has no session_id → pass" '{"prompt":"ja"}' pass
case_ "the prompt is not a string → pass" '{"session_id":"'"$S"'","prompt":7}' pass
case_ "the session_id is not a string → pass" '{"session_id":7,"prompt":"ja"}' pass
for badm in 'garbage' '' 'state=armed' 'state=armed
session_id='"$S" 'state=armed
session_id='"$S"'
epic=epic-x' 'state=armed
session_id='"$S"'
epic=' 'state=disarmed
session_id='"$S"'
epic='"$EPIC" 'session_id='"$S"'
epic='"$EPIC" 'state=armed
session_id=
epic='"$EPIC"; do
  printf '%s\n' "$badm" > "$MARKER"
  case_ "malformed or disarmed marker ($(printf '%s' "$badm" | tr '\n' '|')) → pass" "$HUMAN" pass
done
marker "$S" "$EPIC"
for badt in 'garbage' '[]' '{}' '{"session_id":"'"$S"'"}' \
  '{"session_id":"'"$S"'","prompt_cache":[]}' \
  '{"session_id":"'"$S"'","prompt_cache":{"recache_tokens_if_cold":150000}}' \
  '{"session_id":"'"$S"'","prompt_cache":{"expires_at":1,"recache_tokens_if_cold":"150000"}}' \
  '{"session_id":"'"$S"'","prompt_cache":{"expires_at":"1","recache_tokens_if_cold":150000}}' \
  '{"session_id":"'"$S"'","prompt_cache":{"expires_at":true,"recache_tokens_if_cold":150000}}' \
  '{"session_id":"'"$S"'","prompt_cache":{"expires_at":1,"recache_tokens_if_cold":-1}}' \
  '{"session_id":"'"$S"'","prompt_cache":{"expires_at":null,"recache_tokens_if_cold":null}}'; do
  printf '%s\n' "$badt" > "$TAP"
  case_ "malformed tap ($badt) → pass" "$HUMAN" pass
done

echo "== the hook: no python3 on the PATH → pass, silently (control: with python3 the same fixture blocks)"
reset; marker "$S" "$EPIC"; tap "$S" -60 150000
NOPY="$ROOT/nopy"; mkdir -p "$NOPY"
nopy_out="$(printf '%s' "$HUMAN" | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" CRAFT_USAGE_TAP="$TAP" "$OLD_BASH" "$HOOK" 2>"$ROOT/err"); echo "rc=$?")"
expect "no python3: exit 0 and empty stdout" "$nopy_out" "rc=0"
expect "no python3: no error text" "$(cat "$ROOT/err")" ""
nopy_out="$(printf '%s' "$HUMAN" | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" CRAFT_USAGE_TAP="$TAP" "$BASH" "$HOOK" 2>"$ROOT/err"); echo "rc=$?")"
expect "no python3 (bash 5): exit 0 and empty stdout" "$nopy_out" "rc=0"
case_ "control: the same fixture, python3 present → block" "$HUMAN" block

echo "== the hook: --restart prints the one definition of the restart instruction"
expect "--restart epic-003" "$("$OLD_BASH" "$HOOK" --restart epic-003 2>&1)" "/clear, then /craft:execute epic-003 --autopilot"
"$OLD_BASH" "$HOOK" --restart 'epic-x; echo hi' >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && ok "--restart refuses a malformed epic id (exit 2)" || bad "--restart accepted a malformed epic id (exit $rc)"

echo "== the arming helper"
unset CLAUDE_CODE_SESSION_ID
arm() { # <args…> — the helper, run in the fixture project
  (cd "$P" && CLAUDE_PROJECT_DIR="$P" CRAFT_USAGE_TAP="$TAP" CLAUDE_CODE_SESSION_ID="${SESS-$S}" bash "$MARKER_SH" "$@" 2>&1)
}
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
H="$(hhmm "$((NOW + 1800))")"
reset; tap "$S" 1800 150000
out="$(arm arm "$EPIC")"
expect "arm: ARMED=yes" "$(val "$out" ARMED)" "yes"
expect "arm: EXPIRES from this session's tap" "$(val "$out" EXPIRES)" "$H"
expect "arm: LINE is the expiry line, with the restart" "$(val "$out" LINE)" "Cache warm until $H — answer later → /clear, then /craft:execute epic-003 --autopilot"
expect "arm: the marker holds the armed state, the session, the epic" "$(sed -n '1,3p' "$MARKER" | tr '\n' '|')" "state=armed|session_id=$S|epic=epic-003|"
expect "arm: the marker has an armed= datetime" "$(sed -n '4p' "$MARKER" | sed 's/[0-9]/N/g')" "armed=NNNN-NN-NNTNN:NN:NNZ"
expect "arm: no temp file left next to the marker" "$(ls -A "$P/.claude/plans" | grep -c 'cache-guard\.')" "0"
tap "$S" -60 150000
case_ "round trip: armed by the helper, the cache has expired → the hook blocks" "$HUMAN" block
out="$(arm status)"
expect "status: ARMED=yes" "$(val "$out" ARMED)" "yes"
expect "status: EPIC" "$(val "$out" EPIC)" "epic-003"
expect "status: SESSION" "$(val "$out" SESSION)" "$S"
out="$(arm disarm)"
expect "disarm: ARMED=no" "$(val "$out" ARMED)" "no"
expect "disarm: the marker file stays (CRAFT never removes its state files) and says disarmed" "$(head -1 "$MARKER")" "state=disarmed"
case_ "round trip: disarmed, cold tap → the hook passes" "$HUMAN" pass
out="$(arm status)"; expect "status after disarm: ARMED=no" "$(val "$out" ARMED)" "no"
rm -f "$MARKER"
out="$(arm disarm)"; expect "disarm without a marker: exit clean, ARMED=no" "$(val "$out" ARMED)" "no"
[[ ! -e "$MARKER" ]] && ok "disarm without a marker creates none" || bad "disarm without a marker created one"
tap "$OTHER" 1800 150000
out="$(arm arm "$EPIC")"
expect "arm, the tap belongs to another session: still armed" "$(val "$out" ARMED)" "yes"
expect "… EXPIRES=unknown" "$(val "$out" EXPIRES)" "unknown"
expect "… LINE says the expiry is unknown, with the restart" "$(val "$out" LINE)" "Cache expiry unknown — answer later → /clear, then /craft:execute epic-003 --autopilot"
rm -f "$TAP"
out="$(arm arm "$EPIC")"; expect "arm without a tap: EXPIRES=unknown" "$(val "$out" EXPIRES)" "unknown"
printf 'garbage' > "$TAP"
out="$(arm arm "$EPIC")"; expect "arm with a malformed tap: EXPIRES=unknown" "$(val "$out" EXPIRES)" "unknown"
tap "$S" -60 150000
out="$(arm arm "$EPIC")"; expect "arm, the tap's cache has expired already: EXPIRES=unknown (never a past 'warm until')" "$(val "$out" EXPIRES)" "unknown"
tap "$S" 1800 150000
out="$(SESS="" arm arm "$EPIC")"
expect "arm without a session id: ARMED=no" "$(val "$out" ARMED)" "no"
expect "… REASON=no_session_id" "$(val "$out" REASON)" "no_session_id"
expect "… the LINE is still printed (expiry unknown)" "$(val "$out" LINE)" "Cache expiry unknown — answer later → /clear, then /craft:execute epic-003 --autopilot"
SESS="$OTHER" arm arm epic-004 >/dev/null
expect "re-arm replaces the marker (new session, new epic)" "$(sed -n '2,3p' "$MARKER" | tr '\n' '|')" "session_id=$OTHER|epic=epic-004|"
for badepic in '' 'epic-' 'epic-3x' 'slice-003' 'epic-003; echo hi' '../epic-003'; do
  out="$(arm arm "$badepic")"; rc=$?
  expect "arm refuses the epic id '$badepic'" "$(printf '%s\n' "$out" | grep -c '^ERROR=bad_epic')" "1"
done
# --project: the master's Bash call has no CLAUDE_PROJECT_DIR and a drifted cwd (review R1-3)
ELSEWHERE="$ROOT/elsewhere"; mkdir -p "$ELSEWHERE"
reset; tap "$S" 1800 150000
out="$(cd "$ELSEWHERE" && env -u CLAUDE_PROJECT_DIR CRAFT_USAGE_TAP="$TAP" CLAUDE_CODE_SESSION_ID="$S" bash "$MARKER_SH" arm "$EPIC" --project "$P" 2>&1)"
expect "--project: arm writes under the named project, whatever the cwd" "$(val "$out" MARKER)" "$MARKER"
[[ -f "$MARKER" && ! -e "$ELSEWHERE/.claude/plans/.cache-guard" ]] && ok "--project: the marker is in the project, none in the cwd" || bad "--project: marker not in the project / one left in the cwd"
out="$(cd "$ELSEWHERE" && env -u CLAUDE_PROJECT_DIR bash "$MARKER_SH" disarm --project "$P" 2>&1)"
expect "--project: disarm reaches the named project's marker" "$(head -1 "$MARKER")" "state=disarmed"
out="$(cd "$ELSEWHERE" && env -u CLAUDE_PROJECT_DIR bash "$MARKER_SH" status --project "$P" 2>&1)"; expect "--project: status" "$(val "$out" ARMED)" "no"
out="$(arm arm "$EPIC" --project)"; expect "--project without a value is an error" "$(printf '%s\n' "$out" | grep -c '^ERROR=missing_value')" "1"
out="$(arm arm "$EPIC" extra)"; expect "a second positional argument is an error" "$(printf '%s\n' "$out" | grep -c '^ERROR=unknown_argument')" "1"
out="$(arm arm)"; expect "arm without an epic is an error" "$(printf '%s\n' "$out" | grep -c '^ERROR=bad_epic')" "1"
out="$(arm sideways)"; expect "an unknown command is an error" "$(printf '%s\n' "$out" | grep -c '^ERROR=')" "1"
expect "the helper's restart text is the hook's (one definition)" "$(val "$(arm arm "$EPIC")" LINE | sed 's/.*→ //')" "$("$OLD_BASH" "$HOOK" --restart "$EPIC")"

echo "== the profile key"
expect "usage-state.sh declares the key in DEFAULTS with 100000" "$(sed -n 's/^DEFAULTS = {\(.*\)}$/\1/p' "$USAGE" | tr -d '" ' | tr ',' '\n' | sed -n 's/^Cache-guard-recache-tokens://p')" "100000"
hook_default="$(sed -n 's/^DEFAULT_RECACHE_TOKENS=\([0-9]*\)$/\1/p' "$HOOK")"
expect "the hook's default threshold equals the helper's DEFAULT (bound copy)" "$hook_default" "100000"
hook_stale="$(sed -n 's/^STALE_S=\([0-9]*\)$/\1/p' "$HOOK")"
usage_stale="$(sed -n 's/^STALE_S = \([0-9]*\)$/\1/p' "$USAGE")"
[[ -n "$hook_stale" && "$hook_stale" == "$usage_stale" ]] && ok "the hook's stale-tap age equals usage-state.sh's STALE_S ($usage_stale s — bound copy)" || bad "hook STALE_S '$hook_stale' ≠ usage-state.sh STALE_S '$usage_stale'"
tapline() { grep -F 'tap="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"' "$1" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//'; }
for f in "$HOOK" "$USAGE" "$TAPPER" "$MARKER_SH"; do
  sed 's/^[[:space:]]*//' "$f" 2>/dev/null | grep -qF 'tap="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"' \
    || sed 's/^[[:space:]]*//' "$f" 2>/dev/null | grep -qF 'TAP="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"' \
    && ok "$(basename "$f") derives the tap path by the one expression (bound copy)" || bad "$(basename "$f") does not carry the tap-path expression the statusline tap writes by"
done
upr() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$USAGE" --gate during --tap "$TAP" 2>&1); }
tap "$S" 1800 150000
profile '## Autopilot

- **Cache-guard-recache-tokens:** 250000'
expect "usage-state.sh accepts the key without a WARN" "$(upr | grep -c '^WARN=')" "0"
for bad_value in abc 0 -5 1.5 ''; do
  profile "## Autopilot

- **Cache-guard-recache-tokens:** $bad_value"
  w="$(upr | grep '^WARN=' | head -1)"
  expect "usage-state.sh warns about the invalid value '$bad_value' and names the default" "$w" "WARN=Autopilot → Cache-guard-recache-tokens: '$bad_value' invalid — a positive integer; using 100000"
done
profile '## Autopilot

- **Cache-guard-recache-token:** 250000'
expect "usage-state.sh still warns about a typo'd key" "$(upr | grep -c "^WARN=Autopilot → unknown key 'Cache-guard-recache-token'")" "1"
noprofile

echo "== registration, local state and the sites that arm / disarm"
python3 - "$HOOKS_JSON" <<'PY' && ok "hooks.json registers hooks/cache-guard.sh as a UserPromptSubmit command hook (bash, timeout, no matcher)" || bad "hooks.json does not register hooks/cache-guard.sh for UserPromptSubmit as expected"
import json, sys
d = json.load(open(sys.argv[1]))
groups = d["hooks"]["UserPromptSubmit"]
cmds = [h for g in groups for h in g["hooks"]]
assert any(h.get("type") == "command" and h.get("command") == "bash ${CLAUDE_PLUGIN_ROOT}/hooks/cache-guard.sh" and isinstance(h.get("timeout"), int) for h in cmds), cmds
assert all("matcher" not in g for g in groups)
assert "UserPromptSubmit" in d["description"] and "cache" in d["description"].lower()
PY
grep -qxF '.claude/plans/.cache-guard' <(bash "$SCRIPT_DIR/ensure-gitignore.sh" --print-paths) && ok "ensure-gitignore.sh lists .claude/plans/.cache-guard as CRAFT local state" || bad "ensure-gitignore.sh does not list .claude/plans/.cache-guard"
grep -qxF '.claude/plans/.cache-guard' "$REPO_ROOT/.gitignore" && ok "this repo's .gitignore ignores the marker" || bad "this repo's .gitignore does not ignore .claude/plans/.cache-guard"
grep -qxF '.claude/plans/.cache-guard' <(bash "$SCRIPT_DIR/ensure-gitignore.sh" --print-paths) \
  && grep -qF 'ensure-gitignore.sh --print-paths' "$SCRIPT_DIR/tree-dirt-state.sh" && ok "tree-dirt-state.sh reads that list, so the marker is no dirt" || bad "tree-dirt-state.sh no longer reads the local-state list"

section() { # <file> <heading regex> — the text from the matching ##/### heading to the next heading
  python3 - "$1" "$2" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out, on = [], False
for l in lines:
    if re.match(r"^#{2,3} ", l):
        if on:
            break
        on = re.match(sys.argv[2], l) is not None
    if on:
        out.append(l)
print("\n".join(out))
PY
}
count() { printf '%s\n' "$1" | grep -cF -- "$2"; }
AP="$(section "$EXECUTE" '^### ap — ')"
A2="$(section "$EXECUTE" '^### a2 — ')"
A5="$(section "$EXECUTE" '^### a5 — ')"
GUARD="$(section "$EXECUTE" '^### The cache guard')"
[[ -n "$GUARD" ]] && ok "execute.md has the section 'The cache guard'" || bad "execute.md has no section 'The cache guard'"
ARM='<!-- craft:cache-guard arm -->'; DISARM='<!-- craft:cache-guard disarm -->'
expect "ap arms the guard at the orphan question and at the plan gate" "$(count "$AP" "$ARM")" "2"
expect "ap disarms it when the human answers the orphan question or the gate" "$(count "$AP" "$DISARM")" "2"
expect "a2 disarms it before the builder spawn" "$(count "$A2" "$DISARM")" "1"
expect "a2 arms it at the stop the builder's outcome causes" "$(count "$A2" "$ARM")" "1"
expect "a5 arms it at the sign-off question" "$(count "$A5" "$ARM")" "1"
expect "a5 disarms it when the answer ends the run" "$(count "$A5" "$DISARM")" "1"
expect "the guard section arms at every other ⛔ stop" "$(count "$GUARD" "$ARM")" "1"
expect "the guard section disarms at the run's start" "$(count "$GUARD" "$DISARM")" "1"
for needle in 'scripts/cache-guard-marker.sh" arm <epic-NNN> --project "<project-root>"' 'scripts/cache-guard-marker.sh" disarm --project "<project-root>"' 'print its `LINE=` verbatim' \
  'never a stop' 'Cache warm until HH:MM' 'hooks/cache-guard.sh' '.claude/plans/.cache-guard'; do
  [[ "$GUARD" == *"$needle"* ]] && ok "the cache guard section carries: $needle" || bad "the cache guard section lacks: $needle"
done
other_arm="$(grep -c -- "$ARM" "$EXECUTE")"; sites=$(( $(count "$AP" "$ARM") + $(count "$A2" "$ARM") + $(count "$A5" "$ARM") + $(count "$GUARD" "$ARM") ))
expect "no arm marker outside the pinned sections" "$other_arm" "$sites"
other_dis="$(grep -c -- "$DISARM" "$EXECUTE")"; sites=$(( $(count "$AP" "$DISARM") + $(count "$A2" "$DISARM") + $(count "$A5" "$DISARM") + $(count "$GUARD" "$DISARM") ))
expect "no disarm marker outside the pinned sections" "$other_dis" "$sites"
# the one definition of the restart text is the hook's --restart: execute.md does not spell it out
if grep -n -- '/clear, then /craft:execute' "$EXECUTE" | grep -vq 'LINE'; then bad "execute.md spells the restart instruction out (a second definition — it is the hook's --restart)"; else ok "execute.md does not restate the restart instruction"; fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
