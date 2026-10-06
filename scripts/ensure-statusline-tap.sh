#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# ensure-statusline-tap.sh — wire the usage tap into the user's statusLine, on a yes (slice-059, D36)
#
# WHY ------------------------------------------------------------------------
# The autopilot's budget guard (slice-058, scripts/usage-state.sh) reads the plan's usage windows only from
# the statusline JSON, through scripts/statusline-tap.sh sitting in front of the user's own statusline
# command. A plugin cannot put it there — a plugin's settings.json carries only `agent` and
# `subagentStatusLine`, and Claude Code runs no plugin install or update hook — so without this helper every
# user wires it by hand, and the guard runs blind (conservative mode) for each one who does not. D36: CRAFT
# may write the user's `statusLine`, but only after a yes, with a backup, and reversibly.
#
# WHAT -----------------------------------------------------------------------
#   ensure-statusline-tap.sh [--check | --apply | --remove] [--project <dir>]
#
#   --check   (default) report the wiring; never writes.
#   --apply   wire the tap: back the settings file up, then write `statusLine.command` =
#             `sh <tap> <inner>` and `refreshInterval: 30` when missing. Only from STATUS absent / misrouted /
#             no-refresh; any other status refuses and writes nothing. Idempotent.
#   --remove  take the tap out: back up, then `command` = the inner command again (a `sh -c '<cmd>'` exactly as
#             --apply writes it is unwrapped to <cmd>, and a leading `--` dropped); with a restored command the
#             rest of `statusLine` stays (`refreshInterval` included); no inner command → the whole `statusLine` key
#             goes. No tap → CHANGED=no.
#
# The file written is the USER level: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json (a symlink is followed,
# the file's mode kept). <tap> is the marketplace clone's scripts/statusline-tap.sh — the clone found through
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/known_marketplaces.json, never assumed: first the marketplace the
# installed `craft@<marketplace>` came from (plugins/installed_plugins.json, user scope first), else the entry named
# `craft`, else the first whose clone lists the plugin `craft` (review R1-1: a dev setup may list a directory
# marketplace on a working tree first). Written as `~/…` when it lies under $HOME. The installed plugin cache is
# never a target: it is named by version and moves with every release.
#
# <inner> is the user's own command: kept as is when it is one plain command, wrapped as `sh -c '<cmd>'` when it
# is not — an unquoted ; & | < > ( ) { } or newline, a $( … ) or backtick outside single quotes, a leading
# VAR=value assignment, a leading shell keyword or a # comment. Behind the tap, the outer shell would run such a
# command's other parts before or around the tap (README → Requirements).
#
# CRAFT's tap is a word naming statusline-tap.sh that is the target itself, a file carrying CRAFT's header, or — the
# file is gone — one in CRAFT's .../scripts/ layout; a tap is read only as the command's first word (or a shell's
# first argument). Any other statusline-tap.sh is the user's own command (BUG-1: a user's statusline script may carry
# that name), and a CRAFT tap anywhere else — a later word, the next line, inside a `sh -c '…'` string, in the inner
# command of a tap (a double tap) — makes the command unrecognized: wrapping it would run two taps (review R1-2).
#
# Output (stdout, key=value):
#   SETTINGS=<file>            the user settings file
#   TAP_PATH=<file>|-          the marketplace clone's tap (- when no clone was found)
#   WIRING=absent|ok|misrouted|unrecognized   what the user file holds now
#   REFRESH=yes|no             refreshInterval present
#   OVERRIDDEN_BY=<file>       one per project / local / managed file that sets its own statusLine, the winning one
#                              first (managed: the last drop-in, then managed-settings.json → local → project)
#   OVERRIDE_WIRED=yes|no      with OVERRIDDEN_BY: the winning one runs the target tap with refreshInterval
#                              (KNOWN LIMIT: the winner is the file, not Claude Code's merge of an object across files)
#   CURRENT=<command>          the current statusLine command (empty when none)
#   TAP_CURRENT=<word>         the tap word CRAFT recognised in CURRENT (with WIRING ok / misrouted)
#   PROPOSED=<command>         the command --apply writes (only for absent / misrouted / no-refresh)
#   STATUS=wired|absent|misrouted|no-refresh|overridden|tap-missing|unrecognized
#   REASON=<text>              for tap-missing / unrecognized / a refusal
#   CHANGED=yes|no, BACKUP=<file>|-, RESTORED=<command>|(none)   (--apply / --remove)
# After a write, WIRING / REFRESH / CURRENT / TAP_CURRENT / STATUS describe the file as written and STATUS_BEFORE=
# names the state the run started from (review R1-3). BACKUP=- means no settings file existed: --apply created it.
# STATUS precedence: overridden (a higher level wins, a write here would change nothing visible) → unrecognized
# (a tap this helper cannot parse) → tap-missing (no clone, or the clone has no tap yet — wiring a missing file
# would break the statusline) → misrouted (a tap from any other path: a working tree, the versioned cache) →
# absent → no-refresh → wired.
#
# Exit: 0 wired / written / nothing to do · 10 --check: an offer is due (absent, misrouted, no-refresh) ·
#       11 not offerable or refused (overridden, tap-missing, unrecognized) · 2 usage · 3 no python3 ·
#       5 a settings file is not a JSON object · 6 the post-write check failed: the file WAS written, the backup
#       (named) holds the previous content · 7 the write failed (ERROR=write_failed:…; the settings file is
#       unchanged; a backup, when named, was taken).
#
# Settings levels read for OVERRIDDEN_BY (the ones a script can read, as scripts/permission-rule-match.sh):
# <project>/.claude/settings.json and settings.local.json (+ the git top level's), the managed settings
# file and managed-settings.d/*.json. Test-only override: CRAFT_TEST_MANAGED_DIR (the managed settings directory).
# KNOWN LIMITS: MDM plist, registry, server-managed policy and `--settings` flags are not read.

set -uo pipefail

MODE="check"
PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    --remove) MODE="remove"; shift ;;
    --project) PROJECT="${2:-}"; [[ -n "$PROJECT" ]] || { echo "ERROR=missing_project" >&2; exit 2; }; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "ERROR=python3_not_found" >&2; exit 3; }

PROJECT="${PROJECT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
TOPLEVEL="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -n "${CRAFT_TEST_MANAGED_DIR+x}" ]]; then
  MANAGED_DIR="$CRAFT_TEST_MANAGED_DIR"
else
  case "$(uname -s 2>/dev/null)" in
    Darwin) MANAGED_DIR="/Library/Application Support/ClaudeCode" ;;
    *) MANAGED_DIR="/etc/claude-code" ;;
  esac
fi

CRAFT_MODE="$MODE" CRAFT_PROJECT="$PROJECT" CRAFT_TOPLEVEL="$TOPLEVEL" CRAFT_MANAGED_DIR="$MANAGED_DIR" \
CRAFT_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" python3 - <<'PY'
import glob, json, os, re, shlex, shutil, sys, time

mode = os.environ["CRAFT_MODE"]
cfg = os.environ["CRAFT_CONFIG_DIR"]
home = os.path.expanduser("~")
settings_path = os.path.join(cfg, "settings.json")

def die(code, msg):
    sys.stderr.write(msg + "\n")
    sys.exit(code)

def load(path):
    """dict, or None when the file is absent; exit 5 when it is not a JSON object."""
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        die(5, "ERROR=settings_unparseable:%s:%s" % (path, exc))
    if not isinstance(data, dict):
        die(5, "ERROR=settings_unparseable:%s:top-level JSON is not an object" % path)
    return data

def real(p):
    return os.path.realpath(os.path.expandvars(os.path.expanduser(p)))

# --- the target: the marketplace clone's tap ---------------------------------------------------------------
def find_clone():
    try:
        with open(os.path.join(cfg, "plugins", "known_marketplaces.json"), encoding="utf-8") as fh:
            known = json.load(fh)
    except (OSError, ValueError):
        return None, "no readable plugins/known_marketplaces.json under %s" % cfg
    if not isinstance(known, dict):
        return None, "known_marketplaces.json is not an object"

    def carries_craft(name):
        entry = known.get(name)
        loc = entry.get("installLocation") if isinstance(entry, dict) else None
        if not isinstance(loc, str) or not loc:
            return None
        try:
            with open(os.path.join(loc, ".claude-plugin", "marketplace.json"), encoding="utf-8") as fh:
                m = json.load(fh)
        except (OSError, ValueError):
            return None
        plugins = m.get("plugins") if isinstance(m, dict) else None
        if isinstance(plugins, list) and any(isinstance(p, dict) and p.get("name") == "craft" for p in plugins):
            return loc
        return None

    # The marketplace the installed craft came from wins (review R1-1), user scope first; then the entry named
    # `craft`; then any marketplace that carries the plugin.
    order = []
    try:
        with open(os.path.join(cfg, "plugins", "installed_plugins.json"), encoding="utf-8") as fh:
            installed = json.load(fh)
        plugins = installed.get("plugins", installed) if isinstance(installed, dict) else {}
        keyed = []
        for key, recs in (plugins.items() if isinstance(plugins, dict) else []):
            if isinstance(key, str) and key.startswith("craft@"):
                recs = recs if isinstance(recs, list) else [recs]
                user = any(isinstance(r, dict) and r.get("scope") == "user" for r in recs)
                keyed.append((0 if user else 1, key[len("craft@"):]))
        order += [name for _, name in sorted(keyed)]
    except (OSError, ValueError):
        pass
    order += ["craft"] + [k for k in known if k != "craft"]
    seen_names = set()
    for name in order:
        if name in seen_names:
            continue
        seen_names.add(name)
        loc = carries_craft(name)
        if loc:
            return loc, None
    return None, "no marketplace in known_marketplaces.json carries the plugin craft"

clone, clone_reason = find_clone()
tap_path = os.path.join(clone, "scripts", "statusline-tap.sh") if clone else None
tap_exists = bool(tap_path) and os.path.isfile(tap_path)

def tap_word(path):
    if path.startswith(home + os.sep):
        rel = path[len(home) + 1:]
        if shlex.quote(rel) == rel:
            return "~/" + rel
    return shlex.quote(path)

# --- reading a command: words with their raw end offsets ----------------------------------------------------
def words(s, limit):
    """The first `limit` shell words of s as (value, end) pairs; None when a quote is unbalanced."""
    out, i, n = [], 0, len(s)
    while len(out) < limit:
        while i < n and s[i] in " \t\n":
            i += 1
        if i >= n:
            break
        val = ""
        while i < n and s[i] not in " \t\n":
            c = s[i]
            if c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    return None
                val += s[i + 1:j]; i = j + 1
            elif c == '"':
                i += 1
                while i < n and s[i] != '"':
                    if s[i] == "\\" and i + 1 < n:
                        i += 1
                    val += s[i]; i += 1
                if i >= n:
                    return None
                i += 1
            elif c == "\\" and i + 1 < n:
                val += s[i + 1]; i += 2
            else:
                val += c; i += 1
        out.append((val, i))
    return out

SHELLS = {"sh", "bash", "dash", "zsh"}
TAP_NAME = "statusline-tap.sh"
TAP_HEADER = "# craft (Coding with Rules, Autonomy, Feedback, Tests)"

def is_craft_tap(word, layout=True):
    """CRAFT's tap, not just a file of that name (BUG-1: a user's own statusline script may carry it): the target
    itself, a file that carries CRAFT's header, or — a file that is gone, and only when `layout` — CRAFT's
    .../scripts/statusline-tap.sh."""
    if os.path.basename(word) != TAP_NAME:
        return False
    path = real(word)
    if tap_path is not None and path == os.path.realpath(tap_path):
        return True
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                head = fh.read(2048)
        except OSError:
            return False
        return TAP_HEADER in head and TAP_NAME in head
    return layout and os.path.basename(os.path.dirname(path)) == "scripts"

def mentions_craft_tap(text):
    """A CRAFT tap anywhere in text — a word of its own, or a piece of a word: a `sh -c '…'` string, `x;sh tap`."""
    ws = words(text, 1000) or []
    if any(is_craft_tap(w) for w, _ in ws):
        return True
    # A piece of a word (a `sh -c '…'` string, `x;sh tap`) counts only by the target path or CRAFT's header — never by
    # the layout rule, and never relative: a quoted foreign path with a space splits into pieces that only look like
    # CRAFT's layout (review R2, P1-a).
    pieces = [p for p in re.split(r"[\s;&|()`'\"<>{}]+", text) if p]
    return any(is_craft_tap(p, layout=False) for p in pieces if p.startswith(("/", "~", "$")))

def parse(command):
    """(wiring, tap token value or None, inner raw text)."""
    if TAP_NAME not in command:
        return "absent", None, command.strip()
    ws = words(command, 1000)
    if ws is None:
        return "unrecognized", None, ""
    idx = None
    if ws and is_craft_tap(ws[0][0]):
        idx = 0
    elif len(ws) > 1 and os.path.basename(ws[0][0]) in SHELLS and is_craft_tap(ws[1][0]):
        idx = 1
    if idx is None:
        if mentions_craft_tap(command):
            return "unrecognized", None, ""
        return "absent", None, command.strip()
    inner = command[ws[idx][1]:].strip()
    if inner == "--" or inner.startswith("-- ") or inner.startswith("--\t"):
        inner = inner[2:].strip()
    if mentions_craft_tap(inner):
        return "unrecognized", None, ""      # a double tap: removing one would leave the other (review R1-2)
    return "tapped", ws[idx][0], inner

KEYWORDS = {"if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
            "function", "!", "{", "}", "[[", "time", "select"}

def plain(cmd):
    """One plain command the tap can run as its arguments."""
    if not cmd:
        return True
    q = None
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if q == "'":
            if c == "'":
                q = None
        elif q == '"':
            if c == "\\":
                i += 1
            elif c == '"':
                q = None
            elif c == "`" or cmd.startswith("$(", i):
                return False
        else:
            if c == "\\":
                i += 1
            elif c in "'\"":
                q = c
            elif c in ";&|<>(){}\n`":
                return False
            elif cmd.startswith("$(", i):
                return False
            elif c == "#" and (i == 0 or cmd[i - 1] in " \t"):
                return False
        i += 1
    if q is not None:
        return False
    first = words(cmd, 1)
    if not first:
        return False
    w = first[0][0]
    if w in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
        return False
    return True

def wrap(cmd):
    return cmd if plain(cmd) else "sh -c " + shlex.quote(cmd)

def unwrap(inner):
    """A `sh -c '<cmd>'` exactly as wrap() writes it → <cmd>; anything else as is."""
    m = re.match(r"^sh -c (.+)$", inner, re.S)
    if m:
        try:
            parts = shlex.split(m.group(1))
        except ValueError:
            return inner
        if len(parts) == 1 and shlex.quote(parts[0]) == m.group(1) and not plain(parts[0]):
            return parts[0]
    return inner

# --- what the levels hold -----------------------------------------------------------------------------------
user = load(settings_path)
user_real = os.path.realpath(settings_path)
roots = [os.environ["CRAFT_PROJECT"]]
if os.environ.get("CRAFT_TOPLEVEL"):
    roots.append(os.environ["CRAFT_TOPLEVEL"])
mdir = os.environ["CRAFT_MANAGED_DIR"]
# Highest precedence first: managed, then local, then project — the first one that sets statusLine wins.
# Claude Code merges managed-settings.json first and then the drop-ins in alphabetical order, so the LAST drop-in wins
# (code.claude.com/docs/en/managed-settings, read 2026-10-06; review R2, P1-c).
higher = sorted(glob.glob(os.path.join(mdir, "managed-settings.d", "*.json")), reverse=True)
higher += [os.path.join(mdir, "managed-settings.json")]
higher += [os.path.join(r, ".claude", "settings.local.json") for r in roots]
higher += [os.path.join(r, ".claude", "settings.json") for r in roots]
overridden, override_data, seen = [], [], set()
for f in higher:
    rf = os.path.realpath(f)
    if rf in seen or rf == user_real or not os.path.isfile(f):
        continue
    seen.add(rf)
    data = load(f)
    if data is not None and "statusLine" in data:
        overridden.append(f)
        override_data.append(data)

def state(settings):
    sl = (settings or {}).get("statusLine")
    if sl is None:
        return "absent", None, "", "", False
    if not isinstance(sl, dict):
        return "unrecognized", None, "", "", False
    command = sl.get("command") or ""
    if not isinstance(command, str):
        return "unrecognized", None, "", "", False
    refresh = "refreshInterval" in sl
    kind, token, inner = parse(command)
    if kind == "tapped":
        ok = tap_path is not None and real(token) == os.path.realpath(tap_path)
        kind = "ok" if ok else "misrouted"
    return kind, token, inner, command, refresh

def judge(settings):
    """Everything the report says about one version of the user settings."""
    wiring, token, inner, current, refresh = state(settings)
    if overridden:
        status = "overridden"
    elif wiring == "unrecognized":
        status = "unrecognized"
    elif not tap_exists:
        status = "tap-missing"
    elif wiring == "misrouted":
        status = "misrouted"
    elif wiring == "absent":
        status = "absent"
    elif not refresh:
        status = "no-refresh"
    else:
        status = "wired"
    if status == "tap-missing":
        reason = clone_reason or ("%s does not exist yet — the marketplace clone predates the release that ships it" % tap_path)
    elif status == "unrecognized":
        reason = "the statusLine setting is not a plain command this helper can read — wire it by hand (README → Requirements)"
    elif status == "overridden":
        reason = "a higher settings level sets its own statusLine: " + ", ".join(overridden)
    else:
        reason = None
    proposed = None
    if status in ("absent", "misrouted", "no-refresh"):
        proposed = ("sh " + tap_word(tap_path) + (" " + wrap(inner) if inner else "")).rstrip()
        if status == "no-refresh":
            proposed = current
    return {"wiring": wiring, "token": token, "inner": inner, "current": current, "refresh": refresh,
            "status": status, "reason": reason, "proposed": proposed}

def report(j, extra=()):
    print("SETTINGS=%s" % settings_path)
    print("TAP_PATH=%s" % (tap_path or "-"))
    print("WIRING=%s" % j["wiring"])
    print("REFRESH=%s" % ("yes" if j["refresh"] else "no"))
    for f in overridden:
        print("OVERRIDDEN_BY=%s" % f)
    if overridden:
        win = state(override_data[0])
        print("OVERRIDE_WIRED=%s" % ("yes" if win[0] == "ok" and win[4] else "no"))   # wired = the tap + refreshInterval
    print("CURRENT=%s" % j["current"].replace("\n", "\\n"))
    if j["wiring"] in ("ok", "misrouted"):
        print("TAP_CURRENT=%s" % j["token"])
    if j["proposed"] is not None:
        print("PROPOSED=%s" % j["proposed"].replace("\n", "\\n"))
    print("STATUS=%s" % j["status"])
    if j["reason"]:
        print("REASON=%s" % j["reason"])
    for line in extra:
        print(line)

before = judge(user)

if mode == "check":
    report(before)
    sys.exit(0 if before["status"] == "wired" else 10 if before["proposed"] is not None else 11)

# --- writing ------------------------------------------------------------------------------------------------
def indent_of(text):
    for ln in text.splitlines()[1:]:
        m = re.match(r"^([ \t]+)\S", ln)
        if m:
            return "\t" if m.group(1).startswith("\t") else len(m.group(1))
    return 2

def write(data):
    """Back up, then replace the settings file atomically; exit 7 when anything of it fails (review R1-3)."""
    target = os.path.realpath(settings_path)
    backup = "-"
    tmp = target + ".craft-tmp"
    try:
        original = None
        if os.path.exists(target):
            with open(target, encoding="utf-8") as fh:
                original = fh.read()
        if original is not None:
            stamp = time.strftime("%Y%m%d-%H%M%S")
            name = os.path.join(os.path.dirname(settings_path), "settings.json.bak-craft-" + stamp)
            n = 1
            while os.path.exists(name):
                n += 1
                name = os.path.join(os.path.dirname(settings_path), "settings.json.bak-craft-%s-%d" % (stamp, n))
            shutil.copy2(target, name)
            backup = name                       # named only once it exists (review R2, P1-b)
        text = json.dumps(data, indent=indent_of(original) if original else 2, ensure_ascii=False)
        if original is None or original.endswith("\n"):
            text += "\n"
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        if original is not None:
            shutil.copymode(target, tmp)
        os.replace(tmp, target)
    except OSError as exc:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)                  # the helper's own temp file, never the user's
        except OSError:
            pass
        die(7, "ERROR=write_failed:%s:%s (settings unchanged; backup: %s)" % (settings_path, exc, backup))
    return backup

def written(extra):
    after = judge(load(settings_path))
    report(after, ["STATUS_BEFORE=%s" % before["status"]] + extra)

if mode == "apply":
    if before["proposed"] is None:
        if before["status"] == "wired":
            report(before, ["CHANGED=no", "BACKUP=-"])
            sys.exit(0)
        report(before)
        sys.exit(11)
    proposed = before["proposed"]
    data = user if user is not None else {}
    sl = data.get("statusLine")
    if not isinstance(sl, dict):
        sl = {"type": "command"}
        data["statusLine"] = sl
    sl.setdefault("type", "command")
    sl["command"] = proposed
    if "refreshInterval" not in sl:
        sl["refreshInterval"] = 30
    backup = write(data)
    after = state(load(settings_path))
    if after[0] != "ok" or not after[4] or after[3] != proposed:
        die(6, "ERROR=post_write_check_failed:%s (the file was written; previous content in backup: %s)" % (settings_path, backup))
    written(["CHANGED=yes", "BACKUP=%s" % backup])
    sys.exit(0)

# mode == "remove"
if before["wiring"] == "unrecognized":
    report(before)
    sys.exit(11)
if before["wiring"] == "absent":
    report(before, ["CHANGED=no", "BACKUP=-", "RESTORED=(none)"])
    sys.exit(0)
restored = unwrap(before["inner"])
data = user
if restored:
    data["statusLine"]["command"] = restored
else:
    del data["statusLine"]
backup = write(data)
after = state(load(settings_path))
if after[0] != "absent" or (restored and after[3] != restored):
    die(6, "ERROR=post_write_check_failed:%s (the file was written; previous content in backup: %s)" % (settings_path, backup))
written(["CHANGED=yes", "BACKUP=%s" % backup, "RESTORED=%s" % (restored or "(none)")])
sys.exit(0)
PY
