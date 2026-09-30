#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# permission-rule-match.sh — does a user's deny or ask rule match this Bash command? (D34, D35)
#
# WHY ------------------------------------------------------------------------
# A command a CRAFT helper runs inside `bash helper.sh` never reaches Claude Code's permission
# check — the check judges the `bash helper.sh` line, not what the script does. So a helper that
# runs or issues a command on the user's behalf must ask first whether one of the user's rules
# would have stopped it: delete-mode.sh for the removal it hands to the agent (D34), verify-run.sh
# for every check it runs in an autopilot Phase 5 (D35). This is the one matcher both call — two
# copies of the rule semantics would drift.
#
# It decides on the CONCRETE command string, exactly as it will be issued or run — never on a
# paraphrase — and it never runs the command. Like Claude Code, it tries each rule against every
# subcommand as well (compound commands, substitutions, wrappers — see the matcher below). Doubt (a settings file it cannot read or parse, no
# python3, a matcher that did not answer) is its own answer; each caller treats doubt like a match.
#
# WHAT -----------------------------------------------------------------------
#   permission-rule-match.sh --project <dir> --command <command>
#
#   --project <dir>    the project root (required); its .claude/settings*.json are read, and
#                      those of the git top level when it differs.
#   --command <cmd>    the Bash command string to judge (required, non-empty).
#
# Settings levels read (the ones a script can read; deny and ask are what count, allow is not):
#   user     $HOME/.claude/settings.json, and $CLAUDE_CONFIG_DIR/settings.json when set
#   project  <project>/.claude/settings.json (+ the git top level's)
#   local    <project>/.claude/settings.local.json (+ the git top level's)
#   managed  <managed dir>/managed-settings.json and <managed dir>/managed-settings.d/*.json,
#            <managed dir> = /Library/Application Support/ClaudeCode (macOS),
#            /etc/claude-code (Linux, WSL) — code.claude.com/docs/en/managed-settings, 2026-09-30
# KNOWN LIMITS: MDM plist, registry, server-managed policy and `--settings` flags are not
# readable here; a rule held only there is not seen.
#
# Output (key=value lines, exit 0 whenever MATCH= is printed):
#   MATCH=yes|no|doubt
#   RULE=<rule>             (yes) the matching rule — deny before ask
#   RULE_KIND=deny|ask
#   RULE_LEVEL=user|project|local|managed
#   RULE_SOURCE=<file>      the settings file that holds it
#   REASON=<why>            (doubt, and alongside a match) unparseable:<file>, unreadable:<file>,
#                           python3_not_found, matcher_failed — one line each
# Exit 2: usage error (no MATCH= printed).
#
# Test-only override: CRAFT_TEST_MANAGED_DIR (the managed settings directory).

set -uo pipefail

PROJECT=""
COMMAND=""
HAVE_COMMAND="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --command) COMMAND="${2:-}"; HAVE_COMMAND="yes"; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done
[[ -n "$PROJECT" ]] || { echo "ERROR=missing_project" >&2; exit 2; }
[[ "$HAVE_COMMAND" == yes && -n "$COMMAND" ]] || { echo "ERROR=missing_command" >&2; exit 2; }
[[ -d "$PROJECT" ]] || { echo "ERROR=project_not_found:$PROJECT" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "MATCH=doubt"
  echo "REASON=python3_not_found"
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

# code.claude.com/docs/en/permissions (2026-09-30), "Compound commands" and "Wrappers": deny and ask
# rules apply when ANY subcommand matches — split at && || ; | |& & and newlines, including a command
# nested in a subshell, a command substitution or a control-flow body — after stripping the wrappers
# timeout / time / nice / nohup / stdbuf / command / builtin / noglob, a bare xargs, and any leading
# variable assignment. So a rule is tried against the whole command AND every subcommand, raw and
# normalised. Beyond the matching Claude Code does it also tries the program basename (/bin/rm), strips
# env / sudo / doas, and reads the string of bash|sh|zsh -c as a command of its own — each only adds
# refusals. KNOWN LIMITS (a form not matched runs — a caller that runs commands has no permission check
# behind it): commands inside a script or file a check calls, eval, aliases, functions, interpreters
# other than the shells above (python -c, perl -e, …). In the safe direction: separators and
# parentheses inside quotes are split too, so quoted text naming a denied command (grep -E "(curl|x)")
# can refuse an innocent check — a stop that names the rule, never a run.
import shlex
SEPARATORS = re.compile(r"\|&|&&|\|\||[;|&\n]")
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "for", "case", "esac",
            "!", "{", "}", "(", ")", "in", "select", "function"}
WRAPPERS_WITH_ARG = {"timeout": 1, "nice": 0, "stdbuf": 0}

def bodies(text):
    # command substitutions and subshell / group bodies, innermost first, as commands of their own
    found, rest = [], text
    for pattern in (r"\$\(([^()]*)\)", r"`([^`]*)`", r"\(([^()]*)\)", r"\{([^{}]*)\}"):
        while True:
            m = re.search(pattern, rest)
            if not m:
                break
            found.append(m.group(1))
            rest = rest[:m.start()] + " " + rest[m.end():]
    return found + [rest]

def strip_words(words):
    # leading keywords, assignments and wrappers, repeatedly — returns the words of the actual command
    changed = True
    while words and changed:
        changed = False
        w = words[0]
        base = w.rsplit("/", 1)[-1]
        if w in KEYWORDS or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", w):
            words = words[1:]; changed = True
        elif base in ("time", "nohup", "builtin", "noglob") or (base == "command" and words[1:2] != ["-v"]):
            words = words[1:]
            while words and words[0].startswith("-"):
                words = words[1:]
            changed = True
        elif base in ("env", "sudo", "doas"):
            # beyond the Claude Code wrapper list: each only adds refusals (slice-051 R1-9)
            words = words[1:]
            while words and (words[0].startswith("-") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0])):
                flag = words.pop(0)
                if ((base == "sudo" and flag in ("-u", "-g", "-C", "-D", "-h", "-p", "-U"))
                        or (base == "env" and flag in ("-u", "-C", "-S"))) and words:
                    words.pop(0)
            changed = True
        elif base in WRAPPERS_WITH_ARG:
            words = words[1:]
            while words and words[0].startswith("-"):
                flag = words.pop(0)
                if flag in ("-n", "-s", "-k", "-o", "-e", "-i", "--signal", "--kill-after") and words:
                    words.pop(0)
            for _ in range(WRAPPERS_WITH_ARG[base]):
                if words:
                    words.pop(0)
            changed = True
        elif base == "xargs" and len(words) > 1 and not words[1].startswith("-"):
            words = words[1:]; changed = True
    return words

def candidates(cmd, depth=0):
    out = {cmd.strip()}
    for body in bodies(cmd):
        for seg in SEPARATORS.split(body):
            seg = seg.strip()
            if not seg:
                continue
            out.add(seg)
            try:
                words = shlex.split(seg, posix=True)
            except ValueError:
                words = seg.split()
            words = strip_words(words)
            if not words:
                continue
            out.add(" ".join(words))
            if "/" in words[0]:
                # /bin/rm x is rm x (beyond the Claude Code matching; only adds refusals)
                out.add(" ".join([words[0].rsplit("/", 1)[-1]] + words[1:]))
            # bash -c "<string>": the string is a command of its own
            # (also inside a flag cluster: -lc, -ec, -xc)
            if words[0].rsplit("/", 1)[-1] in ("bash", "sh", "zsh", "dash", "ksh") and depth < 3:
                for i, w in enumerate(words[1:], 1):
                    if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", w):
                        if i + 1 < len(words):
                            out.update(candidates(words[i + 1], depth + 1))
                        break
    return [c for c in out if c]

CANDIDATES = candidates(command)

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
    rx = spec_regex(spec)
    return any(re.match(rx, c, re.S) is not None for c in CANDIDATES)

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
print("MATCH=" + ("yes" if hits else ("doubt" if reasons else "no")))
if hits:
    kind, rule, level, path = hits[0]
    print("RULE=" + rule)
    print("RULE_KIND=" + kind)
    print("RULE_LEVEL=" + level)
    print("RULE_SOURCE=" + path)
for r in reasons:
    print("REASON=" + r)
' "$COMMAND")"

# A matcher that did not answer is doubt.
if [[ "$RESULT" != MATCH=* ]]; then
  echo "MATCH=doubt"
  echo "REASON=matcher_failed"
  exit 0
fi
printf '%s\n' "$RESULT"
