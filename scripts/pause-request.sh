#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# pause-request.sh — the pause request of the auto slice flow: record it, read it, settle it (slice-075, D42)
#
# WHY ------------------------------------------------------------------------
# During auto slice flow (skills/workflow/SKILL.md -> Auto flow) the human can stop the flow by sending the one
# word `pause` (also `pausieren`, `/craft:pause`). Claude Code delivers such a message at the next tool boundary of
# the running turn, so the request has to outlive that turn's current step: it is recorded in a marker, and the
# agent reads it at the next sub-task or phase boundary through flow-state.sh (STOP=pause-requested). Two writers
# record it — the UserPromptSubmit hook hooks/pause-watch.sh, and the agent itself via `request` when it sees the
# queued word in its own context (whether the hook fires for a queued message is undocumented, so neither path
# is trusted alone). Reading and settling go through this helper only: the agent never parses the marker.
#
# WHAT -----------------------------------------------------------------------
#   pause-request.sh request [--project <root>]
#       Write the marker `STATE=requested` for this session (CLAUDE_CODE_SESSION_ID), stamped now. A request of
#       this session already there is restamped (a request is idempotent in effect, and a fresh SINCE is what survives a later
#       resume). Fail open: a request that
#       cannot be written costs one more step before the human types again, so it reports REQUESTED=no, exit 0.
#   pause-request.sh state [--project <root>] [--plan <slice plan>]
#       What the marker says, and whether it is a request that counts (LIVE=yes) — the one judge flow-state.sh asks.
#   pause-request.sh consume [--project <root>]
#       Settle a request: write `STATE=consumed` over a requested marker — whichever session made it (the slice is
#       paused, so the request is moot). /craft:pause and /craft:handoff call it. A marker that is not `requested`
#       (none, consumed, malformed) is left exactly as it is: CONSUMED=no.
#
# The marker — .claude/plans/.pause-request, plain KEY=value lines, kept as state and NEVER removed (D34; the cache
# guard's pattern; hooks/pause-watch.sh writes the same format and carries a copy of this spec):
#   STATE=requested|consumed      SESSION=<session id>      SINCE=<UTC datetime>      [CONSUMED=<UTC datetime>]
# A marker is valid only if every line is KEY=value (CRLF and blank lines tolerated), STATE is requested or consumed,
# SESSION matches [A-Za-z0-9._-]+ and SINCE is YYYY-MM-DDTHH:MM:SSZ, no key twice. Anything else is STATE=invalid.
#
# LIVE=yes needs ALL of: STATE=requested; SESSION equals this session's id (a request of another session — /clear
# changes the id — is none of ours; an environment without an id cannot attribute one); and, with --plan, SINCE not
# older than the latest `> Resumed: <datetime> →` line of the plan's `## Pause Note` (/craft:continue 4a writes it:
# a request made before the resume is answered by the pause that preceded it; a `Resumed:` stamp that is not
# YYYY-MM-DDTHH:MM:SSZ cannot be compared, so it is LIVE=no — doubt is no request). DOUBT MEANS NO REQUEST: an unreadable
# marker or plan is LIVE=no — a phantom pause would halt a flow the human did not stop, a missed one costs one more
# step (and the human can type again).
#
# Output (key=value lines, exit 0 whenever it ran):
#   request:  REQUESTED=yes|no  SESSION=<id>  SINCE=<datetime>  MARKER=<path>  [REASON=no_session_id|bad_session_id|write_failed]
#   state:    STATE=requested|consumed|invalid|none  SESSION=<id|empty>  SINCE=<datetime|empty>  LIVE=yes|no  MARKER=<path>
#   consume:  CONSUMED=yes|no  MARKER=<path>
#   ERROR=<reason> on stderr, exit 2 (usage: unknown_command:<arg>, unknown_argument:<arg>, missing_value:<flag>,
#   project_dir_unreachable:<dir>).
#
# The project is --project <root>, else CLAUDE_PROJECT_DIR, else the cwd (a Bash tool call has no CLAUDE_PROJECT_DIR,
# so the agent passes --project). Runtime: bash >= 5 (scripts/ baseline); the hook, which cannot call a bash 5 helper,
# carries its own copy of the writer — test-pause-watch.sh binds the two.

set -uo pipefail

die() { echo "ERROR=$2" >&2; exit "$1"; }

CMD="${1:-}"
case "$CMD" in request|state|consume) shift ;; *) die 2 "unknown_command:$CMD" ;; esac
PROJECT="" PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 && -n "$2" ]] || die 2 "missing_value:--project"; PROJECT="$2"; shift 2 ;;
    --plan)
      [[ "$CMD" == state ]] || die 2 "unknown_argument:$1"
      [[ $# -ge 2 && -n "$2" ]] || die 2 "missing_value:--plan"; PLAN="$2"; shift 2 ;;
    *) die 2 "unknown_argument:$1" ;;
  esac
done

ROOT="${PROJECT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[[ -d "$ROOT" ]] || die 2 "project_dir_unreachable:$ROOT"
MARKER="$ROOT/.claude/plans/.pause-request"
SESSION="${CLAUDE_CODE_SESSION_ID:-}"
DT_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
SID_RE='^[A-Za-z0-9._-]+$'
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# write_marker <content> — atomic: a temp file next to the marker, then a rename
write_marker() {
  local tmp="$MARKER.$$.tmp"
  mkdir -p "$(dirname "$MARKER")" 2>/dev/null || return 1
  if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$MARKER" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

# read_marker — sets M_STATE (none|requested|consumed|invalid), M_SESSION, M_SINCE
M_STATE="none" M_SESSION="" M_SINCE=""
read_marker() {
  M_STATE="none" M_SESSION="" M_SINCE=""
  [[ -e "$MARKER" ]] || return 0
  local state="" session="" since="" seen_state=0 seen_session=0 seen_since=0 seen_consumed=0 line key val
  if [[ ! -f "$MARKER" ]]; then M_STATE="invalid"; return 0; fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^([A-Z]+)=(.*)$ ]]; then M_STATE="invalid"; return 0; fi
    key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
    case "$key" in
      STATE)    (( seen_state++ ));    state="$val" ;;
      SESSION)  (( seen_session++ ));  session="$val" ;;
      SINCE)    (( seen_since++ ));    since="$val" ;;
      CONSUMED) (( seen_consumed++ )); [[ "$val" =~ $DT_RE ]] || { M_STATE="invalid"; return 0; } ;;
      *)        M_STATE="invalid"; return 0 ;;
    esac
  done < "$MARKER"
  if (( seen_state != 1 || seen_session != 1 || seen_since != 1 || seen_consumed > 1 )); then M_STATE="invalid"; return 0; fi
  case "$state" in requested|consumed) ;; *) M_STATE="invalid"; return 0 ;; esac
  if [[ ! "$session" =~ $SID_RE || ! "$since" =~ $DT_RE ]]; then M_STATE="invalid"; return 0; fi
  M_STATE="$state" M_SESSION="$session" M_SINCE="$since"
}

case "$CMD" in
  request)
    read_marker
    if [[ -z "$SESSION" ]]; then
      echo "REQUESTED=no"; echo "SESSION="; echo "SINCE="; echo "MARKER=$MARKER"; echo "REASON=no_session_id"; exit 0
    elif [[ ! "$SESSION" =~ $SID_RE ]]; then
      echo "REQUESTED=no"; echo "SESSION=$SESSION"; echo "SINCE="; echo "MARKER=$MARKER"; echo "REASON=bad_session_id"; exit 0
    fi
    # Always restamped: a newer SINCE can only make a real request count (an old one kept over a plan's later resume
    # would swallow the word typed again), never invent one.
    since="$(now_iso)"; written=yes
    write_marker "$(printf 'STATE=requested\nSESSION=%s\nSINCE=%s' "$SESSION" "$since")" || written=no
    echo "REQUESTED=$written"; echo "SESSION=$SESSION"; echo "SINCE=$since"; echo "MARKER=$MARKER"
    [[ "$written" == yes ]] || echo "REASON=write_failed"
    exit 0
    ;;
  consume)
    read_marker
    done_="no"
    if [[ "$M_STATE" == requested ]]; then
      write_marker "$(printf 'STATE=consumed\nSESSION=%s\nSINCE=%s\nCONSUMED=%s' "$M_SESSION" "$M_SINCE" "$(now_iso)")" && done_="yes"
    fi
    echo "CONSUMED=$done_"; echo "MARKER=$MARKER"
    exit 0
    ;;
  state)
    read_marker
    live="no"
    if [[ "$M_STATE" == requested && -n "$SESSION" && "$M_SESSION" == "$SESSION" ]]; then
      live="yes"
      if [[ -n "$PLAN" ]]; then
        if [[ ! -f "$PLAN" ]]; then
          live="no"
        else
          # The latest `> Resumed: <datetime> →` line inside the plan's ## Pause Note section (ISO UTC sorts as text).
          resumed="" in_note=0 unreadable=0
          while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ "$line" =~ ^##[[:space:]]+(.*[^[:space:]])[[:space:]]*$ ]]; then
              [[ "${BASH_REMATCH[1]}" == "Pause Note" ]] && in_note=1 || in_note=0
              continue
            fi
            (( in_note )) || continue
            if [[ "$line" =~ ^\>[[:space:]]*Resumed:[[:space:]]*([^[:space:]]*) ]]; then
              dt="${BASH_REMATCH[1]}"
              if [[ ! "$dt" =~ $DT_RE ]]; then unreadable=1      # a resume stamp we cannot compare: doubt is no request
              elif [[ "$dt" > "$resumed" ]]; then resumed="$dt"; fi
            fi
          done < "$PLAN"
          if (( unreadable )) || [[ -n "$resumed" && "$M_SINCE" < "$resumed" ]]; then live="no"; fi
        fi
      fi
    fi
    echo "STATE=$M_STATE"; echo "SESSION=$M_SESSION"; echo "SINCE=$M_SINCE"; echo "LIVE=$live"; echo "MARKER=$MARKER"
    exit 0
    ;;
esac
