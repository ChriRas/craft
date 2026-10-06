#!/bin/sh
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# statusline-tap.sh — leave the statusline JSON where the autopilot's budget guard can read it (slice-058)
#
# WHY ------------------------------------------------------------------------
# An autopilot run must not start a slice the 5h window cannot carry, and a builder must stop when the
# window runs out (D32, design record autopilot-mode.md §6). The only in-session source of the window is
# the JSON Claude Code pipes into the statusline command: `rate_limits.{five_hour,seven_day}` and
# `prompt_cache.ttl`. Nothing else can read that pipe, so this wrapper sits in it: it keeps the latest
# JSON in a tap file and hands the same bytes on to the statusline command the user already has.
# scripts/usage-state.sh reads the tap.
#
# WHAT -----------------------------------------------------------------------
#   statusline-tap.sh [--] [<statusline command> [args…]]
#
# Wired by the user — by hand, or on a yes by scripts/ensure-statusline-tap.sh, which /craft:prime and
# /craft:onboard offer (D36: only after confirmation, with a backup, reversible). In settings.json:
#   "statusLine": { "type": "command", "refreshInterval": 30,
#     "command": "sh ~/.claude/plugins/marketplaces/craft/scripts/statusline-tap.sh <your command>" }
# The marketplace clone's path is stable; the installed plugin cache is named by version and moves on
# every release. `refreshInterval` keeps the JSON coming while the master waits on a builder — the
# statusline's event triggers go quiet then (slice-044). README → Requirements carries the full recipe.
#
# Per call:
#   1. stdin is written to a temp file next to the tap (one per process — sessions share the tap);
#   2. the temp file is held open and replaces the tap by rename (atomic: a reader sees the old JSON or
#      the new one) — BEFORE the statusline command runs: Claude Code kills a statusline that is still
#      running when the next refresh comes, and a kill then neither skips the tap nor leaves the temp
#      file behind (slice-058 review R1-2);
#   3. the statusline command, if given, reads the held file as its stdin — the bytes it would have had —
#      and its stdout, stderr and exit code are the wrapper's.
# Without a command the wrapper prints nothing and exits 0.
#
# The tap is per USER, not per project: `rate_limits` are account-wide, so the freshest statusline of any
# session is the right reading. Its path: $CRAFT_USAGE_TAP, else ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json.
#
# Fail open — the statusline is the user's, the tap only CRAFT's: when the tap directory or the temp
# file cannot be written, stdin goes straight to the statusline command and the tap stays as it was
# (usage-state.sh then reads it as stale). A failing statusline command still leaves the tap written.
#
# Runtime: POSIX sh — Claude Code runs the statusline with whatever shell the user's command names, and
# a hook-like caller must not depend on a bash version (rules.md → Bash baseline). No python3.

if [ "${1:-}" = "--" ]; then
  shift
fi

tap="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"
dir=$(dirname -- "$tap")
tmp="$dir/.usage-tap.$$.tmp"

mkdir -p -- "$dir" 2>/dev/null

# The redirection opens the temp file before cat runs: if it cannot be opened, cat never reads, and
# stdin is still there for the statusline command below.
if { cat > "$tmp"; } 2>/dev/null && exec 3< "$tmp"; then
  if [ -s "$tmp" ]; then
    mv -f -- "$tmp" "$tap" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
  else
    rm -f -- "$tmp" 2>/dev/null
  fi
  rc=0
  if [ "$#" -gt 0 ]; then
    "$@" <&3
    rc=$?
  fi
  exec 3<&-
  exit "$rc"
fi

rm -f -- "$tmp" 2>/dev/null
if [ "$#" -gt 0 ]; then
  "$@"
  exit $?
fi
exit 0
