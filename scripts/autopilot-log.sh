#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# autopilot-log.sh — writes one line of an epic plan's `## Autopilot Log`, stamped with the clock (slice-063, B23)
#
# WHY ------------------------------------------------------------------------
# The log is an autopilot run's durable record: a re-run, plan-gate-state.sh, usage-state.sh and
# epic-close-state.sh read it. The master used to write its lines by hand, and prose did not bind it:
# slice-049's probe logged round, invented times; slice-057's probe 1 stamped a line `19:13:55` in a file
# last written at `19:13:50`; slice-056's probe 3 re-ran without a1's briefing. This helper reads the
# clock, places the line and checks it landed; the master passes the event and relays the printed line
# (rules.md → "What an agent must carry or read out verbatim is checked by command").
#
# WHAT -----------------------------------------------------------------------
#   autopilot-log.sh append <epic-plan> <glyph> <id> <text>
#
# Run from the project root (or set CLAUDE_PROJECT_DIR); <epic-plan> is relative to it or absolute.
#   <glyph>  ▶ (a run, a planning step or a slice started) · ✓ (landed, or the plan gate approved)
#            · ⛔ (stopped for a human) · ■ (the run ended)
#   <id>     the plan's own Epic-ID (`epic-<NNN>`) or a slice-ID (`slice-<NNN>`)
#   <text>   one line, no CR — the event, e.g. `run started`, `merged into main`
#
# The line written — the one format of a log line; commands/execute.md does not restate it:
#   - <YYYY-MM-DDTHH:MM:SSZ> · <glyph> · <id> · <text>
# with the datetime read off the clock (UTC) at the write. CRAFT_LOG_TEST_NOW replaces the clock for
# scripts/test-autopilot-log.sh only; no command names it.
#
# Placement: the line becomes the LAST line of the `## Autopilot Log` section — directly below its last log
# line, or, before the first one, one blank line below the section's note — with one blank line before the
# next heading. A missing section is inserted directly above `## Recap Draft` (its place in the template),
# else at the end of the file; the section's `(no autopilot run yet)` line is dropped. Headings inside an
# example region (scripts/example-regions.sh) are not headings. CRLF plans get a CRLF line; every other byte
# outside the section stays as it was. Lines are never rewritten.
#
# The gate (a1, B23): a SLICE STEP — a `▶` or `✓` line with a slice-ID, except ap's
# `▶ · <slice-id> · planned from entry …` — is written only while
#   - the execute lock (.claude/plans/.execute.lock, scripts/execute-lock.sh) is held for this epic, and
#   - the section holds a line `- <dt> · ▶ · <epic-id> · run started` with <dt> at or after the lock's SINCE=,
# i.e. this invocation has passed a1 (/craft:execute → a1 logs `run started` after its briefing). ⛔ and ■
# lines and the epic's own lines pass without it: ap runs before a1, and s1's stop on a held slice may too.
#
# Output (stdout, exit 0): LINE=<the line exactly as written, without its CR>
#
# Errors — `ERROR=<reason>` on stderr, a non-zero exit, NOTHING on stdout, and the plan unchanged (except
# copy_failed, whose new content stays in the named file):
#   2  usage · glyph · id · text · id_mismatch:<the plan's Epic-ID> · test_now
#   3  project_dir_unreachable
#   4  epic_plan_unreadable · epic_frontmatter:Epic-ID · helper_missing:<name>
#   5  gate:no_lock · gate:lock_released · gate:lock_unreadable · gate:lock_target:<target> · gate:no_run_started
#   6  epic_plan_unwritable:read_only · epic_plan_unwritable · epic_plan_unwritable:copy_failed:<file>
#      · not_landed (written, but the re-read does not hold the line exactly once more than before)
#
# The contract is scripts/test-autopilot-log.sh, written before this file. bash ≥ 5 and python3: only the
# master's Bash tool runs it, never a hook.

set -uo pipefail

die() { echo "ERROR=$2" >&2; exit "$1"; }

[[ $# -eq 5 && "$1" == "append" ]] || die 2 "usage"
EPIC="$2" GLYPH="$3" ID="$4" TEXT="$5"
case "$GLYPH" in ▶|✓|⛔|■) ;; *) die 2 "glyph" ;; esac
[[ "$ID" =~ ^(epic|slice)-[0-9]{3,}$ ]] || die 2 "id"
[[ -n "$TEXT" && "$TEXT" != *$'\n'* && "$TEXT" != *$'\r'* ]] || die 2 "text"
if [[ -n "${CRAFT_LOG_TEST_NOW:-}" ]]; then
  [[ "$CRAFT_LOG_TEST_NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die 2 "test_now"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGIONS="$SCRIPT_DIR/example-regions.sh"
[[ -f "$REGIONS" ]] || die 4 "helper_missing:example-regions.sh"
command -v python3 >/dev/null 2>&1 || die 4 "helper_missing:python3"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" 2>/dev/null || die 3 "project_dir_unreachable"
[[ -f "$EPIC" && -r "$EPIC" ]] || die 4 "epic_plan_unreadable"

TMP="$(mktemp -d)" || die 6 "epic_plan_unwritable"
KEEP=""
trap '[[ -n "$KEEP" ]] || rm -rf "$TMP"' EXIT

bash "$REGIONS" blank markdown "$EPIC" > "$TMP/blank" 2>/dev/null || die 4 "epic_plan_unreadable"

NOW="${CRAFT_LOG_TEST_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
LINE="- $NOW · $GLYPH · $ID · $TEXT"

# Compose the new content (python: placement, gate). Exit codes and ERROR= lines are this script's.
python3 - "$EPIC" "$TMP/blank" "$TMP/new" ".claude/plans/.execute.lock" "$GLYPH" "$ID" "$TEXT" "$LINE" <<'PY'
import os, re, sys

epic, blank_path, out_path, lock_path, glyph, ident, text, line = sys.argv[1:9]

def fail(code, reason):
    sys.stderr.write("ERROR=%s\n" % reason)
    sys.exit(code)

with open(epic, encoding="utf-8", newline="") as f:
    raw = f.read()
with open(blank_path, encoding="utf-8", newline="") as f:
    blank_raw = f.read()

final_nl = raw.endswith("\n")
lines = raw.split("\n")
if final_nl:
    lines.pop()
blank = blank_raw.split("\n")
if blank_raw.endswith("\n"):
    blank.pop()
crlf = bool(lines) and lines[0].endswith("\r")
eol_cr = "\r" if crlf else ""
if len(blank) != len(lines):
    fail(4, "epic_plan_unreadable")

def bare(s):
    return s[:-1] if s.endswith("\r") else s

HEADING = re.compile(r"^#{1,2}\s")
LOG_LINE = re.compile(r"^- \S+ · (▶|✓|⛔|■) · \S+ · ")

def heading_at(name):
    for i, l in enumerate(blank):
        if bare(l).rstrip() == name:
            return i
    return None

# the plan's Epic-ID — from the frontmatter, above the first `## ` heading
epic_id = None
for l in blank:
    b = bare(l)
    if b.startswith("## "):
        break
    m = re.match(r"^>\s*Epic-ID:\s*(\S+)", b)
    if m:
        epic_id = m.group(1)
        break
if not epic_id:
    fail(4, "epic_frontmatter:Epic-ID")
if ident.startswith("epic-") and ident != epic_id:
    fail(2, "id_mismatch:" + epic_id)

start = heading_at("## Autopilot Log")
end = None
if start is not None:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if HEADING.match(bare(blank[j])):
            end = j
            break

# the gate — a slice step needs this invocation's `run started`
step = ident.startswith("slice-") and glyph in ("▶", "✓") and not text.startswith("planned from entry ")
if step:
    try:
        with open(lock_path, encoding="utf-8") as f:
            kv = dict(l.rstrip("\n").split("=", 1) for l in f if "=" in l)
    except FileNotFoundError:
        fail(5, "gate:no_lock")
    except (OSError, UnicodeDecodeError):
        fail(5, "gate:lock_unreadable")
    state, target, since = kv.get("STATE"), kv.get("TARGET"), kv.get("SINCE", "")
    if state == "released":
        fail(5, "gate:lock_released")
    if state != "held" or not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", since):
        fail(5, "gate:lock_unreadable")
    if target != epic_id:
        fail(5, "gate:lock_target:%s" % target)
    started = False
    if start is not None:
        run = re.compile(r"^- (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) · ▶ · " + re.escape(epic_id) + r" · run started$")
        for j in range(start + 1, end):
            m = run.match(bare(blank[j]))
            if m and m.group(1) >= since:
                started = True
    if not started:
        fail(5, "gate:no_run_started")

new_line = line + eol_cr
at_end = False
if start is None:
    section = ["## Autopilot Log" + eol_cr, eol_cr, new_line, eol_cr]
    recap = heading_at("## Recap Draft")
    if recap is not None:
        lines[recap:recap] = section
    else:
        if lines and bare(lines[-1]).strip() != "":
            lines.append(eol_cr)
        lines.extend(section[:-1])
        at_end = True
else:
    body = [l for k, l in enumerate(lines[start + 1:end], start + 1)
            if not (bare(blank[k]).strip() == "(no autopilot run yet)")]
    while body and bare(body[-1]).strip() == "":
        body.pop()
    if not (body and LOG_LINE.match(bare(body[-1]))):
        body.append(eol_cr)
    body.append(new_line)
    if end < len(lines):
        body.append(eol_cr)
    else:
        at_end = True
    lines[start + 1:end] = body

with open(out_path, "w", encoding="utf-8", newline="") as f:
    f.write("\n".join(lines) + ("\n" if final_nl or at_end else ""))
PY
rc=$?
[[ $rc -eq 0 ]] || exit "$rc"

count() { tr -d '\r' < "$1" | grep -cFx -- "$LINE"; }
before="$(count "$EPIC")"

[[ -w "$EPIC" ]] || die 6 "epic_plan_unwritable:read_only"
# write through the existing file: mode, owner and a symlink stay as they are
if ! { cat "$TMP/new" > "$EPIC"; } 2>/dev/null || ! cmp -s "$TMP/new" "$EPIC"; then
  KEEP="yes"
  die 6 "epic_plan_unwritable:copy_failed:$TMP/new"
fi
[[ "$(count "$EPIC")" == "$((before + 1))" ]] || die 6 "not_landed"

echo "LINE=$LINE"
