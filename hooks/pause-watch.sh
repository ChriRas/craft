#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests) — UserPromptSubmit hook: the pause request of the slice flow
# (slice-075, D42; both flow modes since slice-077)
#
# WHY ------------------------------------------------------------------------
# While a slice is in flight the human can ask for a pause by sending the one word `pause`. This hook records such a
# prompt the moment it is submitted — a marker the agent reads at the next sub-task or phase boundary through
# flow-state.sh (STOP=pause-requested), then finishes the running step, writes the handoff and pauses the slice the
# normal way.
# THE FINDING (human re-test T3, 2026-10-08): UserPromptSubmit did NOT fire for a message delivered mid-turn. Claude Code
# queues a message sent while a turn runs and hands it to the agent as an attachment at a tool boundary; no prompt is
# submitted, so no hook sees it. This hook therefore covers only a pause word sent as a PROMPT OF ITS OWN (the agent
# idle between turns, or a queued command Claude Code holds until the turn ends and then submits — `/craft:pause` is
# one). For a word delivered mid-turn the agent's own `scripts/pause-request.sh request` is the path
# (skills/workflow/SKILL.md -> The pause request); this hook is the early path for the prompt-of-its-own case.
# The mode does not matter (decision [G], re-test T5): the hook reads no profile, so a pause word works under
# `Mode: manual` as under `Mode: auto`.
#
# WHAT -----------------------------------------------------------------------
# Reads the UserPromptSubmit payload on stdin and writes .claude/plans/.pause-request when ALL of these hold:
#   1. the prompt, trimmed and case-folded, is exactly `pause`, `pausieren` or `/craft:pause` (a message that merely
#      contains the word, `stop` and `halt` are none — too easily meant otherwise),
#   2. the session id is a marker-safe id (the marker is bound to ONE session; /clear changes it),
#   3. a slice is in flight: some .claude/plans/slice-*.md has a frontmatter `> Status:` (above its first `## `) of
#      implementing, testing, review, refactoring, reviewing or committing.
# It NEVER prints anything and NEVER blocks — the prompt always passes (the agent also sees the word and acts on it) —
# and always exits 0. FAIL OPEN: a malformed payload, an unreadable plan, an unwritable marker, no
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
    if not slice_in_flight():
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
