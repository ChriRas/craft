#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# close-file.sh — close one untracked CRAFT file without ever removing it here (B19, D34)
#
# WHY ------------------------------------------------------------------------
# CRAFT closes plan files (a committed slice, an aborted one, a synced local copy). A user
# who denies or asks on removing files must never see CRAFT go around that rule, and a
# helper that removes a file inside `bash helper.sh` would do exactly that whenever
# delete-mode.sh misses a rule. So this helper never removes: in move mode it moves the
# file into the gitignored .claude/plans/.closed/; in delete mode it only prints the
# removal command, and the agent issues it — Claude Code's permission check stays the
# final judge.
#
# WHAT -----------------------------------------------------------------------
#   close-file.sh --project <dir> [--move] <path>
#
#   --project <dir>  the project root; a relative <path> is resolved against it, and the
#                    move target is <dir>/.claude/plans/.closed/.
#   --move           move regardless of the settings — for a helper that cannot hand a
#                    command back mid-transaction (plan-landing.sh sync).
#   <path>           an existing, untracked regular file inside the project, outside .closed/.
#
# Output (key=value lines):
#   MODE=move|delete            from delete-mode.sh (or move, when --move is given)
#   RULE=… RULE_KIND=… RULE_LEVEL=… RULE_SOURCE=… REASON=…   passed through from delete-mode.sh
#   RESULT=moved TARGET=<path>  the file now lives at <path> (relative to the project root)
#   RESULT=delete DELETE_CMD=rm -- '<abs path>'   nothing was changed; the agent issues DELETE_CMD
#                                           itself, exactly as printed (delete-mode.sh's COMMAND=:
#                                           absolute, single-quoted — the string the rules were
#                                           matched against)
# A moved file's modification time is set to the close, so the cleanup hint counts from there.
# Exit: 0 ok · 2 usage · 4 refused (ERROR=not_found | outside_project | already_closed |
# tracked — a tracked file is closed with `git rm`, which git can undo) · 5 move failed
# (ERROR=move_failed; the file is where it was).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { echo "ERROR=$1" >&2; exit "$2"; }

PROJECT=""
FORCE_MOVE="no"
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 && -n "$2" ]] || fail "missing_value:--project" 2; PROJECT="$2"; shift 2 ;;
    --move) FORCE_MOVE="yes"; shift ;;
    --*) fail "unknown_argument:$1" 2 ;;
    *) [[ -z "$TARGET" ]] || fail "one_path_only" 2; TARGET="$1"; shift ;;
  esac
done
[[ -n "$PROJECT" ]] || fail "missing_project" 2
[[ -n "$TARGET" ]] || fail "missing_argument:<path>" 2
[[ -d "$PROJECT" ]] || fail "project_not_found:$PROJECT" 2

PROJ_ABS="$(cd "$PROJECT" && pwd -P)"
case "$TARGET" in
  /*) FILE="$TARGET" ;;
  *) FILE="$PROJECT/$TARGET" ;;
esac
[[ -f "$FILE" && ! -L "$FILE" ]] || fail "not_found:$TARGET" 4
FILE_ABS="$(cd "$(dirname "$FILE")" && pwd -P)/$(basename "$FILE")"
case "$FILE_ABS" in
  "$PROJ_ABS"/*) ;;
  *) fail "outside_project:$TARGET" 4 ;;
esac
CLOSED_DIR="$PROJ_ABS/.claude/plans/.closed"
case "$FILE_ABS" in
  "$CLOSED_DIR"/*) fail "already_closed:$TARGET" 4 ;;
esac
if git -C "$PROJ_ABS" ls-files --error-unmatch -- "$FILE_ABS" >/dev/null 2>&1; then
  fail "tracked:$TARGET" 4
fi

if [[ "$FORCE_MOVE" == "yes" ]]; then
  echo "MODE=move"
  MODE="move"
else
  # The absolute path: the printed command must not depend on the agent's working directory.
  DECISION="$(bash "$SCRIPT_DIR/delete-mode.sh" --project "$PROJECT" --path "$FILE_ABS")"
  MODE="$(printf '%s\n' "$DECISION" | sed -n 's/^MODE=//p' | head -1)"
  DELETE_CMD="$(printf '%s\n' "$DECISION" | sed -n 's/^COMMAND=//p' | head -1)"
  # A decision that did not arrive is doubt, and doubt means move.
  if [[ "$MODE" != move && ! ( "$MODE" == delete && -n "$DELETE_CMD" ) ]]; then
    MODE="move"; DECISION="MODE=move
REASON=delete_mode_unavailable"
  fi
  printf '%s\n' "$DECISION" | grep -v '^COMMAND='
fi

if [[ "$MODE" == delete ]]; then
  # Exactly the command delete-mode.sh matched the rules against — one definition of it.
  echo "RESULT=delete"
  echo "DELETE_CMD=$DELETE_CMD"
  exit 0
fi

mkdir -p "$CLOSED_DIR" || fail "move_failed:mkdir" 5
name="$(basename "$FILE_ABS")"
dest="$CLOSED_DIR/$name"
if [[ -e "$dest" ]]; then
  stem="${name%.*}"; ext=""
  [[ "$stem" != "$name" ]] && ext=".${name##*.}"
  [[ -n "$stem" ]] || { stem="$name"; ext=""; }
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  dest="$CLOSED_DIR/$stem.$stamp$ext"
  n=2
  while [[ -e "$dest" ]]; do
    dest="$CLOSED_DIR/$stem.$stamp-$n$ext"
    n=$((n + 1))
  done
fi
mv -- "$FILE_ABS" "$dest" 2>/dev/null || fail "move_failed:$TARGET" 5
[[ -f "$dest" && ! -e "$FILE_ABS" ]] || fail "move_failed:$TARGET" 5
# mv keeps the modification time; the cleanup hint (delete-mode.sh --report) measures a file's
# age from it, so it must count from the close, not from the plan's last edit.
touch -- "$dest" 2>/dev/null || true
echo "RESULT=moved"
echo "TARGET=${dest#"$PROJ_ABS"/}"
