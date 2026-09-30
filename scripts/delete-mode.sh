#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# delete-mode.sh — may the agent remove this file, or must CRAFT move it? (B19, D34)
#
# WHY ------------------------------------------------------------------------
# A user may deny or ask on removing files (`Bash(rm:*)` in ~/.claude/settings.json is the
# case that stopped slice-049's autopilot run at every plan close). A deny set at any
# level cannot be lifted by another level, and an ask rule prompts even in auto mode —
# so CRAFT must not issue the removal at all. This helper decides, for one concrete
# file, whether the removal command the agent would issue matches such a rule. The
# caller moves the file instead when it does (scripts/close-file.sh).
#
# The helper never removes anything, and it decides on the CONCRETE command string the
# agent would issue — `rm -- '<path>'`, which close-file.sh prints as DELETE_CMD from this
# helper's COMMAND= line — never on a paraphrase. If it misses a rule (a level it cannot read), the agent issues the command
# and Claude Code's own permission check still stops it: a detection gap costs a prompt
# or a stop, never a removal the user forbade (D34).
#
# WHAT -----------------------------------------------------------------------
#   delete-mode.sh --project <dir> [--path <file>] [--report]
#
#   --project <dir>  the project root (required); its .claude/settings*.json are read,
#                    and those of the git top level when it differs.
#   --path <file>    the file to close, as the caller will name it — close-file.sh passes
#                    its absolute path (default: a stand-in plan path under the project, for
#                    a mode line that names no file).
#   --report         /craft:prime's view: also report what piled up in .claude/plans/.closed/
#                    and, over the threshold, the command the human runs to empty it.
#                    CRAFT never runs that command — it is a hint (D34).
#
# Which settings levels are read, how a rule matches and what counts as doubt is defined once, in
# scripts/permission-rule-match.sh (shared with verify-run.sh, D35); this helper builds the command,
# asks it, and maps a match or doubt to move mode.
#
# Output (key=value lines, exit 0 whenever MODE= is printed):
#   MODE=move|delete        move: a deny/ask rule matches, or doubt (see REASON=)
#   COMMAND=rm -- '<path>'  the command string that was matched, the path single-quoted
#   RULE=<rule>             the matching rule (deny before ask)
#   RULE_KIND=deny|ask
#   RULE_LEVEL=user|project|local|managed
#   RULE_SOURCE=<file>      the settings file that holds it
#   REASON=<why>            doubt that forced move mode (unparseable:<file>, unreadable:<file>,
#                           python3_not_found, matcher_failed); one line each
#   with --report, after the lines above:
#   CLOSED_COUNT=<n>        files in .claude/plans/.closed/ (0 when it does not exist)
#   CLOSED_OLDEST_DAYS=<d>  age of the oldest one in whole days (- when there is none)
#   HINT=yes|no             yes at CLOSED_MAX_FILES files or more, or when one is older than
#                           CLOSED_MAX_DAYS days
#   HINT_CMD=<command>      (HINT=yes) one line for the human: removes the files in .closed/ and
#                           nothing else — an absolute path, a find bounded to that directory
# Exit 2: usage error (no MODE= printed).
#
# Test-only override: CRAFT_TEST_MANAGED_DIR (the managed settings directory).

set -uo pipefail

# Pure bash: this helper must also run on a PATH that holds no dirname (the python3-missing case).
case "${BASH_SOURCE[0]}" in */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;; *) SCRIPT_DIR="." ;; esac

# The cleanup hint's thresholds — defined here, once.
CLOSED_MAX_FILES=20
CLOSED_MAX_DAYS=30

PROJECT=""
TARGET="<stand-in>"
REPORT="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --path) TARGET="${2:-}"; shift 2 ;;
    --report) REPORT="yes"; shift ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done
[[ -n "$PROJECT" ]] || { echo "ERROR=missing_project" >&2; exit 2; }
[[ -n "$TARGET" ]] || { echo "ERROR=missing_path" >&2; exit 2; }
[[ -d "$PROJECT" ]] || { echo "ERROR=project_not_found:$PROJECT" >&2; exit 2; }
[[ "$TARGET" != "<stand-in>" ]] || TARGET="$(cd "$PROJECT" && pwd -P)/.claude/plans/slice-000-example.md"

# shq — the argument as one single-quoted POSIX shell word (an embedded ' becomes '\''). The one
# quoting rule for every command line this helper prints: a path with a space stays one argument.
shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The command is matched with the path as given; close-file.sh passes an absolute one, so the
# printed command does not depend on the agent's working directory.
COMMAND="rm -- $(shq "$TARGET")"

# report — the --report lines; a no-op without --report. Bash only: it also runs when
# python3 is missing.
report() {
  [[ "$REPORT" == yes ]] || return 0
  local dir abs count=0 oldest="" now m f days="-"
  dir="$PROJECT/.claude/plans/.closed"
  if [[ -d "$dir" ]]; then
    now="$(date +%s)"
    for f in "$dir"/* "$dir"/.[!.]*; do
      [[ -f "$f" ]] || continue
      count=$((count + 1))
      m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)"
      [[ "$m" =~ ^[0-9]+$ ]] || continue
      if [[ -z "$oldest" || "$m" -lt "$oldest" ]]; then oldest="$m"; fi
    done
    [[ -n "$oldest" ]] && days=$(( (now - oldest) / 86400 ))
  fi
  echo "CLOSED_COUNT=$count"
  echo "CLOSED_OLDEST_DAYS=$days"
  if [[ "$count" -ge "$CLOSED_MAX_FILES" ]] || { [[ "$days" != "-" ]] && [[ "$days" -gt "$CLOSED_MAX_DAYS" ]]; }; then
    abs="$(cd "$dir" && pwd -P)"
    echo "HINT=yes"
    echo "HINT_CMD=find $(shq "$abs") -mindepth 1 -maxdepth 1 -type f -delete"
  else
    echo "HINT=no"
  fi
}

# The rule semantics live in one place: permission-rule-match.sh (shared with verify-run.sh, D35).
# A match or doubt moves; only a clean "no" deletes.
# "$BASH" (the running interpreter) and bash builtins only: this path must answer on a PATH that
# holds no tool at all (the python3-missing case).
MATCHED="$("$BASH" "$SCRIPT_DIR/permission-rule-match.sh" --project "$PROJECT" --command "$COMMAND" 2>/dev/null)"
MATCH=""; REST=""
while IFS= read -r line; do
  case "$line" in
    MATCH=*) [[ -n "$MATCH" ]] || MATCH="${line#MATCH=}" ;;
    ?*) REST="$REST$line"$'\n' ;;
  esac
done <<< "$MATCHED"
case "$MATCH" in
  yes | no | doubt) ;;
  *) MATCH="doubt"; REST="REASON=matcher_failed"$'\n' ;;
esac
if [[ "$MATCH" == no ]]; then echo "MODE=delete"; else echo "MODE=move"; fi
echo "COMMAND=$COMMAND"
printf '%s' "$REST"
report
