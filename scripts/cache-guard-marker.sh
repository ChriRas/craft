#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# cache-guard-marker.sh — arm / disarm the autopilot's cache guard and state the cache expiry (slice-060)
#
# WHY ------------------------------------------------------------------------
# hooks/cache-guard.sh blocks a human prompt that arrives after the prompt cache expired — but only while the
# guard is ARMED for the session, i.e. the master's last turn ended waiting on the human (design record §7). The
# master arms it through this helper, never by writing the marker itself: the marker binds the guard to the
# session (a session id the master would have to carry by hand), and the expiry line the human reads is computed
# from the tap, not from memory (rules.md: a number an agent states is read off a helper).
#
# WHAT -----------------------------------------------------------------------
#   cache-guard-marker.sh arm <epic-NNN> [--project <root>]   write the marker (state=armed, this session, the epic) and print the
#                                          expiry line. Fail open: a guard that cannot arm costs only a late
#                                          re-write, so it reports ARMED=no and exits 0.
#   cache-guard-marker.sh disarm [--project <root>]           write state=disarmed over an existing marker. The file is never removed
#                                          (CRAFT keeps its state files, like .execute.lock); no marker → nothing.
#   cache-guard-marker.sh status [--project <root>]           what the marker says.
#
# The project is --project <root>, else CLAUDE_PROJECT_DIR, else the cwd. The master passes --project: a Bash tool call
# has no CLAUDE_PROJECT_DIR and its cwd can drift, while the hook reads <CLAUDE_PROJECT_DIR>/.claude/plans/.cache-guard.
# The marker is that file — plain key=value lines, whose format hooks/cache-guard.sh's header defines (not restated here).
# The session id is CLAUDE_CODE_SESSION_ID (env-vars.md: set in Bash tool subprocesses, "matches the session_id
# field in the hook JSON input and is updated on /clear"). The tap is $CRAFT_USAGE_TAP, else the path
# statusline-tap.sh writes.
#
# Output (key=value lines, exit 0 whenever it ran):
#   ARMED=yes|no      EPIC=<epic-NNN>   SESSION=<id>   MARKER=<path>
#   EXPIRES=<HH:MM|unknown>   the local time the main-conversation cache expires — from the tap's
#                             prompt_cache.expires_at, only when the tap belongs to THIS session and the time is
#                             still ahead; otherwise unknown (never a guess, never a time that has passed)
#   LINE=<text>       what the master prints at the human stop, verbatim:
#                       Cache warm until HH:MM — answer later → <restart>      | Cache expiry unknown — answer later → <restart>
#                     <restart> is hooks/cache-guard.sh --restart's output — the one definition of the instruction
#   REASON=<why>      with ARMED=no on arm: no_session_id | bad_session_id | write_failed
#   ERROR=<reason>    on stderr, exit 2 (usage: bad_epic:<arg>, unknown_command:<arg>) or 3 (python3_not_found,
#                     restart_unavailable)
#
# The expiry is read before the turn's last request, so it is at most one statusline refresh early — the safe side.
#
# Runtime: bash >= 5 (scripts/) and python3 — both required by /craft:prime.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/cache-guard.sh"

die() { echo "ERROR=$2" >&2; exit "$1"; }

CMD="${1:-}"
case "$CMD" in arm|disarm|status) shift ;; *) die 2 "unknown_command:$CMD" ;; esac
EPIC=""; PROJECT=""; HAVE_EPIC=no
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 && -n "$2" ]] || die 2 "missing_value:--project"; PROJECT="$2"; shift 2 ;;
    *) [[ "$CMD" == arm && "$HAVE_EPIC" == no ]] || die 2 "unknown_argument:$1"; EPIC="$1"; HAVE_EPIC=yes; shift ;;
  esac
done
[[ "$CMD" != arm || "$HAVE_EPIC" == yes ]] && : || die 2 "bad_epic:"
command -v python3 >/dev/null 2>&1 || die 3 "python3_not_found"

ROOT="${PROJECT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[[ -d "$ROOT" ]] || die 2 "project_dir_unreachable:$ROOT"
MARKER="$ROOT/.claude/plans/.cache-guard"
TAP="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"
SESSION="${CLAUDE_CODE_SESSION_ID:-}"
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# write_marker <content> — atomic: a temp file next to the marker, then a rename
write_marker() {
  local tmp="$MARKER.$$.tmp"
  mkdir -p "$(dirname "$MARKER")" 2>/dev/null || return 1
  if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$MARKER" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

case "$CMD" in
  status)
    state="no"; epic=""; sess=""
    if [[ -f "$MARKER" ]]; then
      while IFS= read -r line; do
        line="${line%$'\r'}"
        case "$line" in
          state=armed) state="yes" ;;
          epic=*) epic="${line#epic=}" ;;
          session_id=*) sess="${line#session_id=}" ;;
        esac
      done < "$MARKER"
    fi
    [[ "$state" == yes ]] || { epic=""; sess=""; }
    echo "ARMED=$state"; echo "EPIC=$epic"; echo "SESSION=$sess"; echo "MARKER=$MARKER"
    exit 0
    ;;
  disarm)
    if [[ -f "$MARKER" ]]; then
      write_marker "$(printf 'state=disarmed\ndisarmed=%s\n' "$(now_iso)")" || true
    fi
    echo "ARMED=no"; echo "MARKER=$MARKER"
    exit 0
    ;;
esac

# --- arm ---------------------------------------------------------------------------------------
[[ "$EPIC" =~ ^epic-[0-9]+$ ]] || die 2 "bad_epic:$EPIC"
RESTART="$(bash "$HOOK" --restart "$EPIC" 2>/dev/null)" || die 3 "restart_unavailable"
[[ -n "$RESTART" ]] || die 3 "restart_unavailable"

EXPIRES="$(python3 - "$TAP" "$SESSION" <<'PY'
import json, sys, time
tap, session = sys.argv[1], sys.argv[2]
try:
    with open(tap, encoding="utf-8") as fh:
        d = json.load(fh)
    exp = d["prompt_cache"]["expires_at"]
    if d.get("session_id") == session and session and not isinstance(exp, bool) and isinstance(exp, (int, float)) and exp > time.time():
        print(time.strftime("%H:%M", time.localtime(exp)))
        sys.exit(0)
except Exception:
    pass
print("unknown")
PY
)"
[[ -n "$EXPIRES" ]] || EXPIRES="unknown"
if [[ "$EXPIRES" == unknown ]]; then
  LINE="Cache expiry unknown — answer later → $RESTART"
else
  LINE="Cache warm until $EXPIRES — answer later → $RESTART"
fi

armed="yes"; reason=""
if [[ -z "$SESSION" ]]; then
  armed="no"; reason="no_session_id"
elif [[ ! "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
  armed="no"; reason="bad_session_id"
elif ! write_marker "$(printf 'state=armed\nsession_id=%s\nepic=%s\narmed=%s\n' "$SESSION" "$EPIC" "$(now_iso)")"; then
  armed="no"; reason="write_failed"
fi

echo "ARMED=$armed"
echo "EPIC=$EPIC"
echo "SESSION=$SESSION"
echo "MARKER=$MARKER"
echo "EXPIRES=$EXPIRES"
echo "LINE=$LINE"
[[ -z "$reason" ]] || echo "REASON=$reason"
exit 0
