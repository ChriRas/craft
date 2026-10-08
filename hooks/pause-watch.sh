#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests) — UserPromptSubmit hook: the pause request of the auto slice
# flow (slice-075, D42)
#
# WHY ------------------------------------------------------------------------
# During auto slice flow the human can stop the flow by sending the one word `pause` while a phase runs. Claude Code
# queues such a message and delivers it at the next tool boundary of the running turn. This hook records it the
# moment it is submitted — a marker the agent reads at the next sub-task or phase boundary through flow-state.sh
# (STOP=pause-requested), then finishes the running step, writes the handoff and pauses the slice the normal way.
# Whether UserPromptSubmit fires for a message queued mid-turn is NOT documented; the agent records a queued pause
# word itself (scripts/pause-request.sh request), so the feature works either way — this hook is the early path,
# and the only one while the agent is idle between turns.
#
# WHAT -----------------------------------------------------------------------
# Reads the UserPromptSubmit payload on stdin and writes .claude/plans/.pause-request when ALL of these hold:
#   1. the prompt, trimmed and case-folded, is exactly `pause`, `pausieren` or `/craft:pause` (a message that merely
#      contains the word, `stop` and `halt` are none — too easily meant otherwise),
#   2. the session id is a marker-safe id (the marker is bound to ONE session; /clear changes it),
#   3. the project runs auto flow: its profile's `## Slice Flow` -> `Mode:` is not `manual` (default auto; lines in a
#      fenced block or an HTML comment are no content; `Execution -> Mode` is another key),
#   4. a slice is in flight: some .claude/plans/slice-*.md has a frontmatter `> Status:` (above its first `## `) of
#      implementing, testing, review, refactoring, reviewing or committing.
# It NEVER prints anything and NEVER blocks — the prompt always passes (the agent also sees the word and acts on it) —
# and always exits 0. FAIL OPEN: a malformed payload, an unreadable plan or profile, an unwritable marker, no
# python3 — anything this hook cannot classify records nothing and lets the prompt through, silently.
#
# The marker format is defined in scripts/pause-request.sh (the reader and settler); this hook writes the same lines:
#   STATE=requested  SESSION=<id>  SINCE=<UTC datetime>
# Every request restamps SINCE and replaces whatever marker is there (consumed, foreign, malformed or an older request
# of this session): a newer SINCE can only make a real request count, never invent one — an old SINCE kept over a
# plan's later resume would swallow the word the human typed again. The file is never removed. test-pause-watch.sh binds the two writers.
#
# Runtime: bash 3.2-compatible on purpose (rules.md -> Bash baseline — hooks run with whatever bash Claude Code hands
# them), python3 for the JSON (absent -> nothing is recorded). No other command runs before python3 is found.

proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# Nothing to do in a project that has no plans directory (every non-CRAFT project): no python, no marker.
[ -d "$proj/.claude/plans" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

IFS= read -r -d '' PYSRC <<'PY'
import json, os, re, sys, time

proj = sys.argv[1]
WORDS = ("pause", "pausieren", "/craft:pause")
ACTIVE = ("implementing", "testing", "review", "refactoring", "reviewing", "committing")
SID_RE = r"[A-Za-z0-9._-]+"


def flow_is_auto():
    try:
        with open(os.path.join(proj, ".claude/project/craft-profile.md"), encoding="utf-8") as fh:
            text = fh.read()
    except Exception:
        return True                       # no profile: the default is auto (an unreadable one cannot say otherwise)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    out, fenced = [], False
    for line in text.split("\n"):
        if re.match(r"^[ \t]*(```|~~~)", line):
            fenced = not fenced
            continue
        if not fenced:
            out.append(line)
    text = "\n".join(out)
    block = re.search(r"^## Slice Flow[ \t]*\r?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not block:
        return True
    modes = []
    for raw in block.group(1).split("\n"):
        m = re.fullmatch(r"-[ \t]+\*\*Mode:\*\*[ \t]*(.*?)", raw.rstrip("\r").strip())
        if m:
            modes.append(m.group(1))
    return not modes or modes != ["manual"]


def slice_in_flight():
    plans = os.path.join(proj, ".claude/plans")
    for name in os.listdir(plans):
        if not (name.startswith("slice-") and name.endswith(".md")):
            continue
        try:
            with open(os.path.join(plans, name), encoding="utf-8") as fh:
                for raw in fh:
                    line = raw.rstrip("\r\n")
                    if line.startswith("## "):
                        break
                    m = re.match(r">[ \t]*Status:[ \t]*(.*)$", line)
                    if m:
                        if m.group(1).replace("`", "").strip() in ACTIVE:
                            return True
                        break
        except Exception:
            continue
    return False


def hook():
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        return
    session, prompt = payload.get("session_id"), payload.get("prompt")
    if not isinstance(session, str) or not isinstance(prompt, str) or not re.fullmatch(SID_RE, session):
        return
    if prompt.strip().lower() not in WORDS:
        return
    if not flow_is_auto() or not slice_in_flight():
        return
    marker = os.path.join(proj, ".claude/plans/.pause-request")
    tmp = "%s.%d.tmp" % (marker, os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("STATE=requested\nSESSION=%s\nSINCE=%s\n" % (session, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())))
        os.replace(tmp, marker)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass


try:
    hook()
except Exception:
    pass
PY

python3 -I -c "$PYSRC" "$proj" >/dev/null 2>&1
exit 0
