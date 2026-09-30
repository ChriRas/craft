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
# Settings levels read (the ones a script can read; deny and ask are what count):
#   user     $HOME/.claude/settings.json, and $CLAUDE_CONFIG_DIR/settings.json when set
#   project  <project>/.claude/settings.json (+ the git top level's)
#   local    <project>/.claude/settings.local.json (+ the git top level's)
#   managed  <managed dir>/managed-settings.json and <managed dir>/managed-settings.d/*.json,
#            <managed dir> = /Library/Application Support/ClaudeCode (macOS),
#            /etc/claude-code (Linux, WSL) — code.claude.com/docs/en/managed-settings, 2026-09-30
# KNOWN LIMITS: MDM plist, registry, server-managed policy and `--settings` flags are not
# readable here; a rule held only there is not seen (the permission check still applies).
#
# Output (key=value lines, exit 0 whenever MODE= is printed):
#   MODE=move|delete        move: a deny/ask rule matches, or doubt (see REASON=)
#   COMMAND=rm -- '<path>'  the command string that was matched, the path single-quoted
#   RULE=<rule>             the matching rule (deny before ask)
#   RULE_KIND=deny|ask
#   RULE_LEVEL=user|project|local|managed
#   RULE_SOURCE=<file>      the settings file that holds it
#   REASON=<why>            doubt that forced move mode (unparseable:<file>, unreadable:<file>,
#                           python3_not_found); one line each
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "MODE=move"
  echo "COMMAND=$COMMAND"
  echo "REASON=python3_not_found"
  report
  exit 0
fi

if [[ -n "${CRAFT_TEST_MANAGED_DIR+x}" ]]; then
  MANAGED_DIR="$CRAFT_TEST_MANAGED_DIR"
else
  case "$(uname -s 2>/dev/null)" in
    Darwin) MANAGED_DIR="/Library/Application Support/ClaudeCode" ;;
    *) MANAGED_DIR="/etc/claude-code" ;;
  esac
fi

TOPLEVEL="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"

# One "<level>\t<file>" line per candidate source; missing files are skipped in python.
sources() {
  printf 'user\t%s\n' "$HOME/.claude/settings.json"
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    printf 'user\t%s\n' "$CLAUDE_CONFIG_DIR/settings.json"
  fi
  local root
  for root in "$PROJECT" ${TOPLEVEL:+"$TOPLEVEL"}; do
    printf 'project\t%s\n' "$root/.claude/settings.json"
    printf 'local\t%s\n' "$root/.claude/settings.local.json"
  done
  printf 'managed\t%s\n' "$MANAGED_DIR/managed-settings.json"
  local dropin
  for dropin in "$MANAGED_DIR"/managed-settings.d/*.json; do
    [[ -e "$dropin" ]] && printf 'managed\t%s\n' "$dropin"
  done
  return 0
}

RESULT="$(sources | python3 -c '
import fnmatch, json, os, re, sys

command = sys.argv[1]

def spec_regex(spec):
    # code.claude.com/docs/en/permissions (2026-09-30): "*" stands for any text; a trailing
    # ":*" equals a trailing " *"; a trailing " *" that is the only wildcard also matches the
    # bare command; the rule matches the whole command text.
    if spec.endswith(":*"):
        spec = spec[:-2] + " *"
    if spec.count("*") == 1 and spec.endswith(" *"):
        return "^" + re.escape(spec[:-2]) + r"(?: .*)?$"
    return "^" + ".*".join(re.escape(p) for p in spec.split("*")) + "$"

def matches(rule):
    m = re.fullmatch(r"\s*([^()\s]+)\s*(?:\((.*)\))?\s*", rule, re.S)
    if not m:
        return False
    tool, spec = m.group(1), m.group(2)
    # deny and ask rules accept a glob in the tool-name position
    if not fnmatch.fnmatchcase("Bash", tool):
        return False
    if spec is None:
        return True
    return re.match(spec_regex(spec), command, re.S) is not None

seen, reasons, hits = set(), [], []
for line in sys.stdin.read().splitlines():
    level, _, path = line.partition("\t")
    if not path or path in seen or not os.path.exists(path):
        continue
    seen.add(path)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError:
        reasons.append("unreadable:" + path)
        continue
    except ValueError:
        reasons.append("unparseable:" + path)
        continue
    perms = data.get("permissions") if isinstance(data, dict) else None
    if not isinstance(perms, dict):
        continue
    for kind in ("deny", "ask"):
        rules = perms.get(kind)
        if not isinstance(rules, list):
            continue
        for rule in rules:
            if isinstance(rule, str) and matches(rule):
                hits.append((kind, rule, level, path))

hits.sort(key=lambda h: 0 if h[0] == "deny" else 1)
print("MODE=" + ("move" if hits or reasons else "delete"))
print("COMMAND=" + command)
if hits:
    kind, rule, level, path = hits[0]
    print("RULE=" + rule)
    print("RULE_KIND=" + kind)
    print("RULE_LEVEL=" + level)
    print("RULE_SOURCE=" + path)
for r in reasons:
    print("REASON=" + r)
' "$COMMAND")"

# A matcher that did not answer is doubt, and doubt means move.
if [[ "$RESULT" != MODE=* ]]; then
  echo "MODE=move"
  echo "COMMAND=$COMMAND"
  echo "REASON=matcher_failed"
  report
  exit 0
fi
printf '%s\n' "$RESULT"
report
