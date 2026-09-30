#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# execute-lock.sh — the /craft:execute run lock as state, never removed (B19, D34)
#
# WHY ------------------------------------------------------------------------
# The lock used to be a file whose existence meant "a run is in progress", released by
# removing it. Under a user rule that denies removing files it was never released, and the
# next run found it and decided by its own judgment to take it over (slice-049 T1-a). Its
# owner was "the current PID" — the Bash-tool shell, which has exited before the next call,
# so no owner could ever be checked.
#
# Now the lock is never removed: its content carries its state, and whether a new run may
# take it is a fixed rule over that content, decided here and nowhere else. The owner is
# the Claude Code process — CLAUDE_PID, set in every Bash-tool and hook subprocess
# (code.claude.com/docs/en/env-vars, 2026-09-30) — plus its start time, so a reused PID is
# not mistaken for the owner.
#
# WHAT -----------------------------------------------------------------------
#   execute-lock.sh check   --project <dir>
#   execute-lock.sh acquire --project <dir> --target <epic-NNN|slice-NNN>
#   execute-lock.sh release --project <dir> [--force]
#
# The lock file is <dir>/.claude/plans/.execute.lock, key=value lines:
#   STATE=held|released  TARGET=<t>  OWNER_PID=<pid>  OWNER_START=<ps lstart, may be empty>
#   SESSION=<CLAUDE_CODE_SESSION_ID or ->  SINCE=<UTC ISO>  [RELEASED=<UTC ISO>]
#
# The rule (check prints it; acquire acts on it):
#   absent                                   → DECISION=proceed   REASON=absent
#   STATE=released                           → DECISION=proceed   REASON=released
#   held, owner PID is the caller's CLAUDE_PID → DECISION=confirm  REASON=own_process
#       (an earlier run from this same process: ended — an Esc-interrupted run leaves exactly
#        this — or still running: an interactive session runs Agent spawns in the background and
#        ends the turn while the run lives, and subagents share the parent's CLAUDE_PID. The lock
#        cannot tell which, so the caller asks the human; only on their "it ended" does it release
#        the lock — plain `release`, it owns it — and acquire again. slice-050 review R1-1)
#   held, owner PID not running              → DECISION=takeover  REASON=owner_gone
#   held, owner PID running, other start time → DECISION=takeover REASON=owner_reused
#   held by another running process          → DECISION=stop      REASON=held_by_live_owner
#   legacy lock (no STATE= line; PID + target text from before B19):
#       its first number is a running process named `claude` → DECISION=stop     REASON=legacy_owner_live
#       otherwise                                            → DECISION=takeover REASON=legacy_owner_gone
#       (a legacy PID was the Bash-tool shell, gone by the next call — so a legacy lock of a run
#        that is still active reads gone too; the format cannot tell, which is why it was replaced)
#   STATE=held without a usable OWNER_PID, or an unknown STATE → DECISION=stop REASON=unreadable
#   (doubt stops: the human decides, and `release --force` is theirs to run)
#
# Output (key=value lines):
#   check:   LOCK=absent|held|released|legacy|unreadable  [TARGET= OWNER_PID= SESSION= SINCE=]
#            OWNER_ALIVE=yes|no|-  DECISION=proceed|takeover|confirm|stop  REASON=…   exit 0
#   acquire: the check lines, then RESULT=acquired|taken_over (exit 0) or RESULT=refused (exit 10 —
#            on DECISION=stop, and on DECISION=confirm, which only the human's answer resolves);
#            a caller without CLAUDE_PID gets only RESULT=refused REASON=no_identity (exit 10 —
#            no owner, no lock); a lock that cannot be written: ERROR=write_failed, exit 5, no RESULT=
#   release: RESULT=released | unchanged (already released) | absent        exit 0
#            RESULT=refused REASON=not_owner (held by another process; --force releases it) exit 10
# Exit 2: usage error.
#
# It never removes the lock file. Two runs acquiring in the same instant can both win — the
# window is one write; the same held before B19.

set -uo pipefail

fail() { echo "ERROR=$1" >&2; exit "$2"; }

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
PROJECT=""; TARGET=""; FORCE="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--project" 2; PROJECT="$2"; shift 2 ;;
    --target)  [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--target" 2; TARGET="$2"; shift 2 ;;
    --force)   FORCE="yes"; shift ;;
    *) fail "unknown_argument:$1" 2 ;;
  esac
done
case "$CMD" in
  check|release) ;;
  acquire) [[ -n "$TARGET" ]] || fail "missing_value:--target" 2 ;;
  *) fail "unknown_command:${CMD:-none}" 2 ;;
esac
[[ -n "$PROJECT" ]] || fail "missing_project" 2
[[ -d "$PROJECT" ]] || fail "project_not_found:$PROJECT" 2

LOCK="$PROJECT/.claude/plans/.execute.lock"
SELF="${CLAUDE_PID:-}"
[[ "$SELF" =~ ^[0-9]+$ ]] || SELF=""

value() { # key — its value in the lock file (first occurrence)
  sed -n "s/^$1=//p" "$LOCK" 2>/dev/null | head -1
}
running() { # pid — true while a process with that PID exists
  ps -p "$1" -o pid= >/dev/null 2>&1
}
start_of() { # pid — the process start time, empty when ps cannot tell
  ps -o lstart= -p "$1" 2>/dev/null | sed 's/[[:space:]]*$//'
}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Evaluate the lock → sets LOCK_STATE, OWNER, ALIVE, DECISION, REASON.
evaluate() {
  OWNER="-"; ALIVE="-"
  if [[ ! -e "$LOCK" ]]; then
    LOCK_STATE="absent"; DECISION="proceed"; REASON="absent"; return
  fi
  local state
  state="$(value STATE)"
  if [[ -z "$state" ]] && ! grep -q '^STATE=' "$LOCK" 2>/dev/null; then
    LOCK_STATE="legacy"
    OWNER="$(grep -Eo '[0-9]+' "$LOCK" 2>/dev/null | head -1)"
    [[ -n "$OWNER" ]] || OWNER="-"
    local comm
    comm="$(ps -o comm= -p "$OWNER" 2>/dev/null | sed 's/[[:space:]]*$//')"
    if [[ "$OWNER" != "-" ]] && running "$OWNER" && [[ "${comm##*/}" == claude ]]; then
      ALIVE="yes"; DECISION="stop"; REASON="legacy_owner_live"
    else
      ALIVE="no"; DECISION="takeover"; REASON="legacy_owner_gone"
    fi
    return
  fi
  case "$state" in
    released) LOCK_STATE="released"; DECISION="proceed"; REASON="released"; return ;;
    held) LOCK_STATE="held" ;;
    *) LOCK_STATE="unreadable"; DECISION="stop"; REASON="unreadable"; return ;;
  esac
  OWNER="$(value OWNER_PID)"
  if [[ ! "$OWNER" =~ ^[0-9]+$ ]]; then
    OWNER="-"; LOCK_STATE="unreadable"; DECISION="stop"; REASON="unreadable"; return
  fi
  if [[ -n "$SELF" && "$OWNER" == "$SELF" ]]; then
    ALIVE="yes"; DECISION="confirm"; REASON="own_process"; return
  fi
  if ! running "$OWNER"; then
    ALIVE="no"; DECISION="takeover"; REASON="owner_gone"; return
  fi
  local recorded current
  recorded="$(value OWNER_START)"; current="$(start_of "$OWNER")"
  if [[ -n "$recorded" && -n "$current" && "$recorded" != "$current" ]]; then
    ALIVE="no"; DECISION="takeover"; REASON="owner_reused"; return
  fi
  ALIVE="yes"; DECISION="stop"; REASON="held_by_live_owner"
}

report() {
  echo "LOCK=$LOCK_STATE"
  if [[ "$LOCK_STATE" != absent ]]; then
    echo "TARGET=$(value TARGET)"
    echo "OWNER_PID=$OWNER"
    echo "SESSION=$(value SESSION)"
    echo "SINCE=$(value SINCE)"
  fi
  echo "OWNER_ALIVE=$ALIVE"
  echo "DECISION=$DECISION"
  echo "REASON=$REASON"
}

write_lock() { # state target owner start session since [released]
  mkdir -p "$(dirname "$LOCK")" || fail "write_failed" 5
  {
    echo "STATE=$1"
    echo "TARGET=$2"
    echo "OWNER_PID=$3"
    echo "OWNER_START=$4"
    echo "SESSION=$5"
    echo "SINCE=$6"
    if [[ -n "${7:-}" ]]; then echo "RELEASED=$7"; fi
  } > "$LOCK" 2>/dev/null || fail "write_failed" 5
}

evaluate
case "$CMD" in
  check)
    report
    exit 0
    ;;
  acquire)
    # No identity is decided before the check lines, so the output holds one REASON= only.
    if [[ -z "$SELF" ]]; then
      echo "RESULT=refused"; echo "REASON=no_identity"; exit 10
    fi
    report
    if [[ "$DECISION" == stop || "$DECISION" == confirm ]]; then
      echo "RESULT=refused"; exit 10
    fi
    write_lock held "$TARGET" "$SELF" "$(start_of "$SELF")" "${CLAUDE_CODE_SESSION_ID:--}" "$(now)"
    [[ "$(value STATE)" == held && "$(value OWNER_PID)" == "$SELF" ]] || fail "write_failed" 5
    if [[ "$DECISION" == takeover ]]; then echo "RESULT=taken_over"; else echo "RESULT=acquired"; fi
    exit 0
    ;;
  release)
    case "$LOCK_STATE" in
      absent) echo "RESULT=absent"; exit 0 ;;
      released) echo "RESULT=unchanged"; exit 0 ;;
    esac
    if [[ "$FORCE" != yes ]] && { [[ -z "$SELF" ]] || [[ "$OWNER" != "$SELF" ]]; }; then
      echo "OWNER_PID=$OWNER"; echo "RESULT=refused"; echo "REASON=not_owner"; exit 10
    fi
    write_lock released "$(value TARGET)" "$(value OWNER_PID)" "$(value OWNER_START)" "$(value SESSION)" "$(value SINCE)" "$(now)"
    [[ "$(value STATE)" == released ]] || fail "write_failed" 5
    echo "RESULT=released"
    exit 0
    ;;
esac
