#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests) — UserPromptSubmit hook: the autopilot's cache guard
# (slice-060, design record autopilot-mode.md §7)
#
# WHY ------------------------------------------------------------------------
# An autopilot session that waits on the human (the plan gate, a ⛔ stop, the a5 sign-off) keeps a large prompt
# cache that expires after an hour. A prompt that arrives after that re-writes the whole context at the full
# input price for one "ja". This hook blocks such a prompt BEFORE any request is sent (a UserPromptSubmit block
# sends no main-conversation request — design record §2) and names the restart instead: /clear, then
# /craft:execute <epic> --autopilot — the re-run resumes the epic.
#
# WHAT -----------------------------------------------------------------------
# Reads the UserPromptSubmit payload on stdin; prints either nothing (the prompt passes) or exactly
#   {"decision":"block","reason":"<text>"}
# and always exits 0. It blocks only when ALL of these hold:
#   1. the arming marker .claude/plans/.cache-guard (written by scripts/cache-guard-marker.sh at a turn that ends
#      waiting on the human) says `state=armed` and names this prompt's session (`session_id=`, an `epic=epic-NNN`),
#   2. the statusline tap (scripts/statusline-tap.sh) belongs to the same session, is at most STALE_S seconds old
#      and says the prompt cache has expired (prompt_cache.expires_at < now),
#   3. a re-write would cost at least the threshold — prompt_cache.recache_tokens_if_cold >= the profile's
#      `## Autopilot` key Cache-guard-recache-tokens (default DEFAULT_RECACHE_TOKENS; an invalid value takes the
#      default — scripts/usage-state.sh is the one that warns about it),
#   4. the prompt is a human's: not a subagent's hand-back or a task notification (UserPromptSubmit also fires for
#      those and its payload has no source field — they start with `<agent-message from=` / `<task-notification>`,
#      design record §2 — blocking one would block the very result the master waits for) and not /clear, /exit or
#      /quit (the block names /clear as the way out).
# Everything else passes, silently. FAIL OPEN: a missing, stale, foreign-session or malformed tap, a malformed or
# disarmed marker, a malformed payload, no python3 — anything this hook cannot classify lets the prompt through.
#
# The marker is plain key=value lines (the helper writes them, this hook only reads):
#   state=armed  session_id=<id>  epic=epic-NNN  armed=<UTC datetime>        — written by `arm`
#   state=disarmed  disarmed=<UTC datetime>                                    — written by `disarm`
# The marker is bound to ONE session: after /clear the session_id changes (env-vars.md: CLAUDE_CODE_SESSION_ID
# "is updated on /clear"), so a marker left armed blocks nothing in the restarted session.
#
#   cache-guard.sh --restart epic-NNN   prints the restart instruction — its ONE definition: the block's reason
#                                       and scripts/cache-guard-marker.sh's expiry line both use it. Exit 2 on
#                                       anything but an epic id.
#
# The tap path, DEFAULT_RECACHE_TOKENS and STALE_S are copies of what usage-state.sh / statusline-tap.sh declare
# (this hook is bash 3.2 and cannot call a bash >= 5 helper); scripts/test-cache-guard.sh binds each copy.
#
# Runtime: bash 3.2-compatible on purpose (rules.md → Bash baseline — hooks run with whatever bash Claude Code
# hands them), python3 for the JSON (absent → the prompt passes). No other command runs before python3 is found.

DEFAULT_RECACHE_TOKENS=100000
STALE_S=300
tap="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"

mode=hook
epic_arg=""
if [ "${1:-}" = "--restart" ]; then
  mode=restart
  epic_arg="${2:-}"
fi

# Unarmed (no marker file — every prompt of a project that never ran an autopilot): nothing to read, nothing to start.
[ "$mode" = hook ] && [ ! -f "$proj/.claude/plans/.cache-guard" ] && exit 0
command -v python3 >/dev/null 2>&1 || { [ "$mode" = restart ] && exit 2; exit 0; }

IFS= read -r -d '' PYSRC <<'PY'
import json, os, re, sys, time

default_tokens, stale_s, proj, tap_path, mode, epic_arg = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
EPIC_RE = r"epic-[0-9]+"


def restart(epic):
    # The one definition of the restart instruction.
    return "/clear, then /craft:execute %s --autopilot" % epic


def threshold():
    try:
        with open(os.path.join(proj, ".claude/project/craft-profile.md"), encoding="utf-8") as fh:
            text = fh.read()
    except Exception:
        return default_tokens
    block = re.search(r"^## Autopilot[ \t]*\r?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not block:
        return default_tokens
    value = default_tokens
    for raw in block.group(1).split("\n"):
        m = re.fullmatch(r"- \*\*Cache-guard-recache-tokens:\*\*[ \t]*(.*?)", raw.rstrip("\r").strip())
        if m and re.fullmatch(r"[0-9]+", m.group(1)) and int(m.group(1)) >= 1:
            value = int(m.group(1))
    return value


def hook():
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        return
    session, prompt = payload.get("session_id"), payload.get("prompt")
    if not isinstance(session, str) or not session or not isinstance(prompt, str):
        return
    head = prompt.lstrip()
    if head.startswith("<agent-message from=") or head.startswith("<task-notification>"):
        return
    words = head.split(None, 1)
    if words and words[0] in ("/clear", "/exit", "/quit"):
        return
    with open(os.path.join(proj, ".claude/plans/.cache-guard"), encoding="utf-8") as fh:
        marker = {}
        for line in fh.read().split("\n"):
            key, sep, val = line.rstrip("\r").partition("=")
            if sep and key not in marker:
                marker[key] = val
    if marker.get("state") != "armed" or marker.get("session_id") != session:
        return
    epic = marker.get("epic", "")
    if not re.fullmatch(EPIC_RE, epic):
        return
    age = time.time() - os.path.getmtime(tap_path)
    with open(tap_path, encoding="utf-8") as fh:
        tap = json.load(fh)
    if age > stale_s or not isinstance(tap, dict) or tap.get("session_id") != session:
        return
    cache = tap.get("prompt_cache")
    if not isinstance(cache, dict):
        return
    expires, tokens = cache.get("expires_at"), cache.get("recache_tokens_if_cold")
    for v in (expires, tokens):
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return
    if tokens < 0 or expires >= time.time() or tokens < threshold():
        return
    reason = ("Prompt cache expired at %s — answering here would re-write about %d tokens at the full input price. "
              "Restart instead: %s (the re-run resumes the epic)."
              % (time.strftime("%H:%M", time.localtime(expires)), tokens, restart(epic)))
    print(json.dumps({"decision": "block", "reason": reason}))   # ASCII-escaped: a C locale cannot encode the dash


if mode == "restart":
    if re.fullmatch(EPIC_RE, epic_arg):
        print(restart(epic_arg))
        sys.exit(0)
    sys.exit(2)
try:
    hook()
except Exception:
    pass
PY

python3 -c "$PYSRC" "$DEFAULT_RECACHE_TOKENS" "$STALE_S" "$proj" "$tap" "$mode" "$epic_arg" 2>/dev/null
rc=$?
if [ "$mode" = restart ]; then
  exit "$rc"
fi
exit 0
