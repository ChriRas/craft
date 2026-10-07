#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# autopilot-briefing.sh — the autopilot's run-start briefing, generated, never written from memory (slice-069, B27)
#
# WHY ------------------------------------------------------------------------
# At the start of an autopilot run (/craft:execute → a1) and at its plan gate (ap step 5) the human reads one
# block: where the run builds, that the checkout is occupied, the slice order, where it stops for them, how to
# stop. slice-063's probe showed the master printing that block from context — "printed, but not bound": the
# "Stops for you at" lines and the order were its own wording, and prose does not bind it (rules.md → "What an
# agent must carry or read out verbatim is checked by command"). This helper prints the whole block; a1 and the
# plan gate only relay it, the way a5 relays epic-digest.sh. THIS HEADER is the one place that defines the
# block — commands/execute.md points here and does not restate it.
#
# WHAT -----------------------------------------------------------------------
#   autopilot-briefing.sh --trunk <trunk> <epic-plan>
#
# Run from the project root (or set CLAUDE_PROJECT_DIR); <epic-plan> is relative to it, <trunk> is the branch the
# run lands on at its end (the epic branch itself is `<Epic-ID>-<Epic-Slug>`, /craft:execute a0 item 3). The
# slices are the epic's decomposition entries in their order. Their states are NOT decided here: this helper asks
#   execute-resume-state.sh --mode sequential --landing direct --trunk <epic-branch> --slices-from <epic-plan>
# (the one place that decides create / resume / held / skip, B8) and reads ACTION= and PLAN_STATUS= per slice.
# It reads `Depends-On:` off the plans that `epic-entry-link.sh resolve` names for the open slices.
# Example regions (fenced blocks, multi-line HTML comments) of the epic plan are no content: a `# ` line or a
# frontmatter key inside one is not read — scripts/example-regions.sh decides. CRLF input is read as LF; the
# output has LF line ends. Needs bash >= 5 and python3 — only the master's Bash tool runs it.
#
# Output (stdout, exit 0) — this block, and nothing else:
#
#   ▶ Autopilot run — <epic-id> "<title>"
#      Builds in place on <epic-id>-<epic-slug>; <trunk> is not touched until you say yes at the end.
#      This checkout is occupied: do not edit files or switch branches here until the run stops.
#      Order: <slice> (<mark>) → <slice> (<mark>) → …   [landed: <slice>, <slice>, …]
#      Stops for you at: <the fixed text below, four lines>
#      Stop:   Esc.   Resume after any stop:   /craft:execute <epic-id> --autopilot
#
# - <title>: the text after the first ` — ` of the epic plan's first `# ` heading; without one, the whole
#   heading text.
# - Order: the epic's slices that have not landed.
#     · a slice whose ACTION is `resume` comes FIRST, marked `(resume at <PLAN_STATUS>)` — an earlier invocation
#       started it and stopped mid-slice, whatever its place (/craft:execute s1);
#     · the rest follow in topological order by `Depends-On:`, a tie in decomposition order (s1 states the same
#       tie-break): repeatedly the first slice, in decomposition order, whose open dependencies are all placed.
#       A slice is marked `(build)` (ACTION=create) or `(held at <PLAN_STATUS>)` (ACTION=held: paused / blocked).
#       A dependency that is landed, outside the epic, or the resume slice does not affect the order;
#     · nothing left → `(nothing left to build)`;
#     · then `   [landed: <ids>]` in decomposition order, only when a slice has landed (ACTION=skip).
# - Stops for you at: four fixed lines, moved verbatim from /craft:execute's former Output Format. The text lives in
#   ONE place here, the STOPS list of the Python block below; the test harness holds the same text and compares it byte
#   for byte (a bound copy). It is not restated in this header, so it cannot drift from the code.
#
# Errors — `ERROR=<reason>` on stderr, a non-zero exit, and NOTHING on stdout (never a partial block):
#   2  usage                      (no --trunk, no or several epic plans, an unknown option, a missing value)
#   3  project_dir_unreachable
#   4  epic_plan_unreadable · plan_unreadable:<path> (a plan that is not UTF-8 text) · epic_frontmatter:Epic-ID · epic_frontmatter:Epic-Slug · epic_title_missing
#      · helper_missing:<name> · helper_missing:python3 · tmp_unwritable
#   5  resume_state_failed:<ERROR= of execute-resume-state.sh> · resolve_failed
#      · resume_conflict:<slice-id>:<REASON> (a slice line is a conflict) · resume_conflict:<reason> (run-wide:
#        a dirty tree with no slice in flight, a checkout not on the epic branch)
#   6  depends_on_cycle:<slice-ids, decomposition order> — the open slices that could not be placed
#
# Read-only: it writes nothing but its own temp files (removed on exit). The contract is
# scripts/test-autopilot-briefing.sh, written before this file.

set -uo pipefail

die() { echo "ERROR=$2" >&2; exit "$1"; }

TRUNK=""
EPIC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trunk) [[ $# -ge 2 && -n "$2" ]] || die 2 "usage"; TRUNK="$2"; shift 2 ;;
    --*) die 2 "usage" ;;
    *) [[ -z "$EPIC" && -n "$1" ]] || die 2 "usage"; EPIC="$1"; shift ;;
  esac
done
[[ -n "$TRUNK" && -n "$EPIC" ]] || die 2 "usage"

# Builtins only until the python3 check: the script's own directory without `dirname`.
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
LINK="$SCRIPT_DIR/epic-entry-link.sh"
REGIONS="$SCRIPT_DIR/example-regions.sh"
RESUME="$SCRIPT_DIR/execute-resume-state.sh"
for h in "$LINK" "$REGIONS" "$RESUME"; do
  [[ -f "$h" ]] || die 4 "helper_missing:${h##*/}"
done
command -v python3 >/dev/null 2>&1 || die 4 "helper_missing:python3"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" 2>/dev/null || die 3 "project_dir_unreachable"
PROJECT="$PWD"

[[ -f "$EPIC" && -r "$EPIC" ]] || die 4 "epic_plan_unreadable"

TMP="$(mktemp -d)" || die 4 "tmp_unwritable"
trap 'rm -rf "$TMP"' EXIT

bash "$REGIONS" blank markdown "$EPIC" > "$TMP/epic.blank" 2>/dev/null || die 4 "epic_plan_unreadable"

cat > "$TMP/briefing.py" <<'PY'
import re, sys

STOPS = [
    "   Stops for you at: Phase-5 checks that are refused or missing, a bug the autonomous debug loop could not fix, review",
    "   ping-pong (a finding whose one autonomous loop-back did not hold, or the round cap), scope questions, blockers,",
    "   failures, the usage budget (the limits in craft-profile.md → ## Autopilot; without a usage reading after every",
    "   slice) — and at the end (with the UX demo script).",
]

def fail(code, reason):
    sys.stderr.write("ERROR=%s\n" % reason)
    sys.exit(code)

def lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError):
        fail(4, "plan_unreadable:%s" % path)
    out = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    if out and out[-1] == "":
        out.pop()
    return out

def frontmatter(blank, key):
    for l in blank:
        if l.startswith("## "):
            break
        m = re.match(r"^>\s*" + re.escape(key) + r":\s*(\S+)", l)
        if m:
            return m.group(1)
    return None

mode = sys.argv[1]

if mode == "meta":
    # meta <epic.blank> — prints Epic-ID, Epic-Slug and the title, one per line
    blank = lines(sys.argv[2])
    epic_id = frontmatter(blank, "Epic-ID")
    if not epic_id:
        fail(4, "epic_frontmatter:Epic-ID")
    slug = frontmatter(blank, "Epic-Slug")
    if not slug:
        fail(4, "epic_frontmatter:Epic-Slug")
    heading = next((l[2:].strip() for l in blank if l.startswith("# ")), None)
    if heading is None or heading == "":
        fail(4, "epic_title_missing")
    title = heading.split(" — ", 1)[1] if " — " in heading else heading
    sys.stdout.write("%s\n%s\n%s\n" % (epic_id, slug, title))
    sys.exit(0)

# render <trunk> <epic-id> <epic-slug> <title> <resume-state output> <resolve output>
trunk, epic_id, slug, title = sys.argv[2:6]
resume = lines(sys.argv[6])
resolved = lines(sys.argv[7])

if "RESULT=ok" not in resume and "RESULT=conflict" not in resume:
    fail(5, "resume_state_failed:no_result")

def field(line, key):
    m = re.search(r"(?:^| )" + key + r"=(\S*)", line)
    return m.group(1) if m else ""

slices = []   # (id, action, reason, plan_status) in decomposition order
for l in resume:
    if l.startswith("SLICE="):
        slices.append((field(l, "SLICE"), field(l, "ACTION"), field(l, "REASON"), field(l, "PLAN_STATUS")))

if "RESULT=conflict" in resume:
    for sid, action, reason, _ps in slices:
        if action == "conflict":
            fail(5, "resume_conflict:%s:%s" % (sid, reason))
    run_wide = next((l.split("=", 1)[1] for l in resume if l.startswith("RESULT_REASON=")), "-")
    fail(5, "resume_conflict:%s" % (run_wide if run_wide not in ("", "-") else "unknown"))

plans = {}
for l in resolved:
    if l.startswith("SLICE=") and field(l, "STATE") == "plan":
        m = re.search(r" PLAN=(.*?) ENTRY=", l)
        if m:
            plans[field(l, "SLICE")] = m.group(1)

def depends_on(sid):
    path = plans.get(sid)
    if not path:
        return []
    for l in lines(path):
        if l.startswith("## "):
            break
        m = re.match(r"^>\s*Depends-On:\s*(.*)$", l)
        if m:
            return re.findall(r"slice-\d+", m.group(1))
    return []

landed, resume_slice, rest = [], None, []
for sid, action, reason, ps in slices:
    if action == "skip":
        landed.append(sid)
    elif action == "resume":
        resume_slice = (sid, "resume at %s" % ps)
    elif action == "held":
        rest.append((sid, "held at %s" % ps))
    elif action == "create":
        rest.append((sid, "build"))
    else:
        fail(5, "resume_state_failed:unexpected_action:%s:%s" % (sid, action))

# topological order over the open slices that are neither landed nor the resume slice:
# repeatedly the first one, in decomposition order, whose dependencies inside that set are all placed
ids = [sid for sid, _m in rest]
deps = {sid: [d for d in depends_on(sid) if d in ids] for sid in ids}
placed, order = set(), []
while len(order) < len(rest):
    nxt = next((i for i, (sid, _m) in enumerate(rest) if sid not in placed and all(d in placed for d in deps[sid])), None)
    if nxt is None:
        fail(6, "depends_on_cycle:" + ",".join(sid for sid, _m in rest if sid not in placed))
    placed.add(rest[nxt][0])
    order.append(rest[nxt])

parts = ([resume_slice] if resume_slice else []) + order
order_line = " → ".join("%s (%s)" % (sid, mark) for sid, mark in parts) if parts else "(nothing left to build)"
if landed:
    order_line += "   [landed: %s]" % ", ".join(landed)

out = [
    "▶ Autopilot run — %s \"%s\"" % (epic_id, title),
    "   Builds in place on %s-%s; %s is not touched until you say yes at the end." % (epic_id, slug, trunk),
    "   This checkout is occupied: do not edit files or switch branches here until the run stops.",
    "   Order: " + order_line,
]
out += STOPS
out.append("   Stop:   Esc.   Resume after any stop:   /craft:execute %s --autopilot" % epic_id)
sys.stdout.write("\n".join(out) + "\n")
PY

meta="$(python3 "$TMP/briefing.py" meta "$TMP/epic.blank")" || exit $?
EPIC_ID="$(sed -n 1p <<<"$meta")"
SLUG="$(sed -n 2p <<<"$meta")"
TITLE="$(sed -n '3,$p' <<<"$meta")"

CLAUDE_PROJECT_DIR="$PROJECT" bash "$RESUME" --mode sequential --landing direct --trunk "$EPIC_ID-$SLUG" \
  --slices-from "$EPIC" > "$TMP/resume.out" 2> "$TMP/resume.err"
rc=$?
if [[ $rc -ne 0 ]]; then
  reason="$(sed -n 's/^ERROR=//p' "$TMP/resume.err" | sed -n 1p)"
  die 5 "resume_state_failed:${reason:-exit_$rc}"
fi

CLAUDE_PROJECT_DIR="$PROJECT" bash "$LINK" resolve "$EPIC" > "$TMP/resolve.out" 2>/dev/null || die 5 "resolve_failed"

python3 "$TMP/briefing.py" render "$TRUNK" "$EPIC_ID" "$SLUG" "$TITLE" "$TMP/resume.out" "$TMP/resolve.out"
