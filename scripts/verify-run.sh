#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# verify-run.sh — run a slice's machine-readable checks and write the evidence itself (D35)
#
# WHY ------------------------------------------------------------------------
# Inside an autopilot run, Phase 5 is no human exercise: the slice is verified by executing its
# committed Test Strategy. An agent's report of that is no evidence (slice-045, slice-049), so the
# checks are run here and the evidence round is written into the plan by this script, not by the
# builder. A command run inside `bash verify-run.sh` never reaches Claude Code's permission check,
# so every check command is judged against the user's deny / ask rules first
# (scripts/permission-rule-match.sh, the matcher D34's delete-mode.sh uses) — a match or doubt
# refuses the whole block before anything runs.
#
# WHAT -----------------------------------------------------------------------
#   verify-run.sh --project <dir> <plan>
#
# The block, inside the plan's `## Test Strategy` (a single-line marker, never a fence — a fenced
# block is an example to scripts/example-regions.sh and would never be found):
#
#   <!-- craft:verify -->
#   - check <name> :: <expectation> :: <command>
#
#   <name>         [a-z0-9][a-z0-9-]*, unique in the block
#   <expectation>  exit=<n>  |  contains=<text>  (exit 0 and <text> in stdout+stderr),
#                  optionally followed by " timeout=<seconds>" (default 600)
#   <command>      the rest of the line, run by `bash -c` from the project root; one pair of
#                  surrounding backticks is stripped. Each check runs in its own process group,
#                  which is killed when the check exits — start and probe a server in ONE command
#
# The block is the run of `- check ` lines directly below the marker — no blank or other line between
# them; a check-shaped line anywhere else in `## Test Strategy` makes the block malformed (it would never
# run). Lines inside an example region (a fence, a multi-line HTML comment) do not count. One marker per
# `## Test Strategy`. Commands, expectations and output excerpts copied into the evidence are neutralised
# (no backtick or tilde fence, no HTML comment delimiter), so the evidence never opens an example region.
#
# Output (key=value lines, exit 0 whenever RESULT= is printed):
#   RESULT=pass|fail|refused|none
#     pass     every check met its expectation
#     fail     a check did not, timed out, or the block is malformed (REASON=malformed:<why>)
#     refused  a check command matches a deny / ask rule, or the matcher is in doubt — nothing ran
#     none     no verify block in `## Test Strategy`
#   CHECKS=<n>  PASSED=<n>  FAILED=<name,…|->  ROUND=<n>
#   REASON=<why> (refused / malformed), RULE= / RULE_SOURCE= (refused by a rule; the first one)
# Each round's heading is `### Run <r> — <UTC datetime> · review rounds: <N>` — N is the number of
# `### Round` headings in the plan's `## Review Findings` when it ran (read by /craft:execute a3).
# Every run appends one round under `## Verification Evidence` (the section is added at the end of
# the plan when missing); the rest of the plan stays byte-identical, earlier rounds are never rewritten.
# Exit 2: usage error; 3: plan not found or not writable (no RESULT=).
#
# It never removes a file (D34): the plan is rewritten through a temp file and an atomic rename.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT=""
PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --*) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
    *) [[ -z "$PLAN" ]] || { echo "ERROR=one_plan_only" >&2; exit 2; }; PLAN="$1"; shift ;;
  esac
done
[[ -n "$PROJECT" && -d "$PROJECT" ]] || { echo "ERROR=missing_project" >&2; exit 2; }
[[ -n "$PLAN" ]] || { echo "ERROR=missing_plan" >&2; exit 2; }
case "$PLAN" in /*) ;; *) PLAN="$PROJECT/$PLAN" ;; esac
[[ -f "$PLAN" && -w "$PLAN" ]] || { echo "ERROR=plan_not_found:$PLAN" >&2; exit 3; }

if ! command -v python3 >/dev/null 2>&1; then
  # No parser, no runner: nothing runs, and doubt is a refusal, never a pass.
  echo "RESULT=refused"; echo "CHECKS=0"; echo "PASSED=0"; echo "FAILED=-"; echo "ROUND=-"
  echo "REASON=python3_not_found"
  exit 0
fi

# The plan with every example region blanked, line count kept (the one definition of "example").
BLANKED="$(mktemp)"
trap 'rm -f "$BLANKED"' EXIT
if ! bash "$SCRIPT_DIR/example-regions.sh" blank markdown "$PLAN" > "$BLANKED" 2>/dev/null; then
  echo "RESULT=fail"; echo "CHECKS=0"; echo "PASSED=0"; echo "FAILED=-"; echo "ROUND=-"
  echo "REASON=malformed:example_regions_unavailable"
  exit 0
fi

PROJECT="$(cd "$PROJECT" && pwd -P)"
python3 - "$PLAN" "$BLANKED" "$PROJECT" "$SCRIPT_DIR/permission-rule-match.sh" <<'PY'
import datetime, os, re, signal, subprocess, sys, tempfile

plan, blanked, project, matcher = sys.argv[1:5]
DEFAULT_TIMEOUT = 600
MARKER = "<!-- craft:verify -->"
LINE_RE = re.compile(r"- check ([a-z0-9][a-z0-9-]*) :: (exit=(\d+)|contains=(.+?))(?: timeout=(\d+))? :: (.+)")

with open(plan, encoding="utf-8", newline="") as fh:
    original = fh.read()
lines = open(blanked, encoding="utf-8", newline="").read().split("\n")

def emit(result, checks=0, passed=0, failed=(), rnd="-", extra=()):
    print("RESULT=" + result)
    print("CHECKS=%d" % checks)
    print("PASSED=%d" % passed)
    print("FAILED=" + (",".join(failed) if failed else "-"))
    print("ROUND=%s" % rnd)
    for e in extra:
        print(e)

# --- parse: the marker inside ## Test Strategy, then the run of `- check ` lines ---------------
in_ts, markers, ts_lines = False, [], []
for i, raw in enumerate(lines):
    line = raw.rstrip("\r")
    if line.startswith("## "):
        in_ts = line.strip() == "## Test Strategy"
        continue
    if in_ts:
        ts_lines.append(i)
        if line.strip() == MARKER:
            markers.append(i)

checks, reasons = [], []
if len(markers) > 1:
    reasons.append("malformed:%d_markers" % len(markers))
elif markers:
    j = markers[0] + 1
    names = set()
    while j < len(lines) and lines[j].rstrip("\r").startswith("- check "):
        text = lines[j].rstrip("\r")
        m = LINE_RE.fullmatch(text)
        if not m:
            reasons.append("malformed:line_%d" % (j + 1))
        else:
            name = m.group(1)
            if name in names:
                reasons.append("malformed:duplicate_%s" % name)
            names.add(name)
            cmd = m.group(6).strip()
            if len(cmd) >= 2 and cmd.startswith("`") and cmd.endswith("`"):
                cmd = cmd[1:-1]
            checks.append({
                "name": name,
                "exit": int(m.group(3)) if m.group(3) is not None else None,
                "contains": m.group(4),
                "expect": m.group(2),
                "timeout": int(m.group(5)) if m.group(5) else DEFAULT_TIMEOUT,
                "command": cmd,
            })
        j += 1
    if not checks and not reasons:
        reasons.append("malformed:no_checks")
    # A check line outside the block — above the marker, or after a blank line, a note or a typo — would
    # silently never run: every check-shaped line (a bullet "check …" carrying " :: ") anywhere else in
    # ## Test Strategy makes the block malformed — doubt, never a pass. Prose bullets carry no " :: ".
    block = set(range(markers[0], j))
    for k in ts_lines:
        if k not in block and re.match(r"\s*[-*+]\s+che?c?k\b.* :: ", lines[k]):
            reasons.append("malformed:check_outside_block_line_%d" % (k + 1))

# How many review rounds the plan holds now (## Review Findings, example regions blanked): recorded in
# each evidence round, so /craft:execute a3 can tell a pass that came before a later review loop-back
# from one after it without comparing clocks (slice-051 R2-3).
REVIEW_ROUNDS, in_rf = 0, False
for raw in lines:
    line = raw.rstrip("\r")
    if line.startswith("## "):
        in_rf = line.strip() == "## Review Findings"
        continue
    if in_rf and re.match(r"### Round \d+ — ", line):
        REVIEW_ROUNDS += 1

# --- evidence writer: append one round, everything else byte-identical ------------------------
def append_round(body_lines):
    nl = "\r\n" if "\r\n" in original else "\n"
    text = original
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    m = re.search(r"(?m)^## Verification Evidence[ \t]*\r?$", text)
    # rounds are counted inside the section only: a "### Run" shown elsewhere in the plan is not one
    rounds = 0
    if m:
        nxt = re.search(r"(?m)^## ", text[m.end():])
        end = m.end() + nxt.start() if nxt else len(text)
        section = text[m.end():end]
        rounds = len(re.findall(r"(?m)^### Run \d+ — ", section))
    rnd = rounds + 1
    block = nl.join(["### Run %d — %s · review rounds: %d" % (rnd, stamp, REVIEW_ROUNDS), ""] + body_lines) + nl
    if m:
        # a template placeholder "(none yet)" is replaced by the first round
        if not rounds:
            section = re.sub(r"(?m)^\(none yet\)[ \t]*\r?\n?", "", section, count=1)
        section = section.rstrip("\r\n") + nl + nl + block + (nl if nxt else "")
        text = text[:m.end()] + section + text[end:]
    else:
        text = text.rstrip("\r\n") + nl + nl + "## Verification Evidence" + nl + nl + block
    d = os.path.dirname(plan) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".verify-", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    os.chmod(tmp, os.stat(plan).st_mode & 0o7777)
    os.replace(tmp, plan)
    return rnd

def neutral(s):
    # Text copied into the plan (commands, expectations, output) must never open an example region:
    # scripts/example-regions.sh would read the rest of the plan as an example and hide, e.g., an open
    # review finding from review-findings-state.sh (slice-051 R1-1). So no backtick / tilde fence and
    # no HTML comment delimiter survives.
    return (s.replace("`", "'").replace("~~~", "~ ~ ~")
             .replace("<!--", "<! --").replace("-->", "-- >"))

def code(s):
    return "`%s`" % neutral(s)

if reasons:
    rnd = append_round(["- result · fail · the verify block is malformed: " + ", ".join(reasons)])
    emit("fail", len(checks), 0, [], rnd, ["REASON=" + r for r in reasons])
    sys.exit(0)

if not markers:
    rnd = append_round(["- result · none · no `%s` block in `## Test Strategy` — nothing ran" % MARKER.replace("`", "'")])
    emit("none", 0, 0, [], rnd)
    sys.exit(0)

# --- the user's rules first: every command, before anything runs -----------------------------
for c in checks:
    try:
        out = subprocess.run(["bash", matcher, "--project", project, "--command", c["command"]],
                             capture_output=True, text=True, timeout=60).stdout
    except Exception:
        out = ""
    fields = {}
    for line in out.splitlines():
        k, _, v = line.partition("=")
        fields.setdefault(k, v)
    match = fields.get("MATCH")
    if match != "no":
        why = ("rule %s (%s) in %s" % (fields.get("RULE"), fields.get("RULE_KIND"), fields.get("RULE_SOURCE"))
               if match == "yes" else "doubt: " + (fields.get("REASON") or "matcher_failed"))
        rnd = append_round(["- %s · %s · refused — %s" % (c["name"], code(c["command"]), why),
                            "- result · refused · nothing ran"])
        extra = ["REASON=" + ("rule:" + c["name"] if match == "yes" else (fields.get("REASON") or "matcher_failed"))]
        if match == "yes":
            extra += ["RULE=" + fields.get("RULE", ""), "RULE_SOURCE=" + fields.get("RULE_SOURCE", "")]
        emit("refused", len(checks), 0, [], rnd, extra)
        sys.exit(0)

# --- run ------------------------------------------------------------------------------------
body, passed, failed = [], 0, []
for c in checks:
    # Output goes to an anonymous temp file, not a pipe: a check that exits but leaves a background child
    # holding stdout is judged when it exits, not when the pipe closes. Afterwards its whole process group
    # is killed, so nothing it started outlives the check.
    with tempfile.TemporaryFile() as out_fh:
        proc = subprocess.Popen(["bash", "-c", c["command"]], cwd=project, stdin=subprocess.DEVNULL,
                                stdout=out_fh, stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        try:
            proc.wait(timeout=c["timeout"])
        except subprocess.TimeoutExpired:
            timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.wait()
        out_fh.seek(0)
        output = out_fh.read().decode("utf-8", "replace")
    rc = proc.returncode
    if timed_out:
        ok, observed = False, "timed out after %ds" % c["timeout"]
    elif c["exit"] is not None:
        ok, observed = rc == c["exit"], "exit %d" % rc
    else:
        found = c["contains"] in output
        ok, observed = (rc == 0 and found), "exit %d, %s" % (rc, "contains it" if found else "text not found")
    passed += ok
    if not ok:
        failed.append(c["name"])
    body.append("- %s · %s · expected %s · observed %s · %s"
                % (c["name"], code(c["command"]), neutral(c["expect"]), observed, "pass" if ok else "fail"))
    tail = [l for l in output.rstrip("\n").split("\n") if l.strip()][-3:]
    for l in tail:
        body.append("  > " + neutral(l[:200]))

result = "pass" if not failed else "fail"
body.append("- result · %s · %d/%d checks passed" % (result, passed, len(checks)))
rnd = append_round(body)
emit(result, len(checks), passed, failed, rnd)
PY
