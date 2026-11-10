#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# usage-state.sh — the autopilot's budget verdict: may the run start, continue or keep going? (slice-058)
#
# WHY ------------------------------------------------------------------------
# An autopilot run leaves the human away for hours (D32). It must not start a slice the 5h window cannot
# carry, must stop a running slice when the window runs out, and must stop before the weekly window is
# gone (design record autopilot-mode.md §6). Those are judgments on numbers, and a number an agent
# carries in its head is one it can get wrong (rules.md: a number that describes a run is read off that
# run). So one helper reads the numbers and states the verdict; the master and the builder only act on
# VERDICT=. Its input is the tap scripts/statusline-tap.sh writes from the statusline JSON.
#
# WHAT -----------------------------------------------------------------------
#   usage-state.sh --gate before|during|after [--epic-plan <file>] [--slice <slice-id>]
#                  [--tap <file>] [--last-reading <file>] [--profile <file>] [--now <epoch seconds>]
#   usage-state.sh --check-line start|landed --epic-plan <file> --slice <slice-id> --expect <LOG_FIELD>
#
#   before   /craft:execute → Autopilot run → a2, before a builder spawn. Needs --epic-plan for the forecast.
#   during   slice-builder at every boundary of its spawn (agents/slice-builder.md → The budget guard).
#   after    /craft:execute → Autopilot run → a3 / a4, after a slice landed. With --epic-plan and --slice it
#            also states the slice's Δ five_hour for the landed line.
#
# Run from the project root (CLAUDE_PROJECT_DIR, else the cwd); relative paths resolve against it.
#   --tap      default: $CRAFT_USAGE_TAP, else ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json —
#              the path statusline-tap.sh writes.
#   --last-reading  default: the tap's path without `.json`, plus `.last-reading.json` — the copy statusline-tap.sh
#              keeps of the last JSON that carried `rate_limits` (slice-093).
#   --profile  default: .claude/project/craft-profile.md (absent → the defaults below).
#   --now      the clock, for the harness; default: the system clock. Times print in local time (TZ).
#
# The usage, read off the tap:
#   rate_limits.five_hour.used_percentage / .resets_at, rate_limits.seven_day.used_percentage / .resets_at
#   (epoch seconds), prompt_cache.ttl. No other field is required (`spend_limit` is absent on some accounts).
#   UNKNOWN — and MODE=conservative — when the tap is missing, unreadable or not a JSON object, older than
#   300 s (STALE_S), lacks either window's used_percentage, or a window's resets_at has passed (the reading
#   is from before that reset — review R1-18). Never a guess.
#
# The last reading (slice-093): the tap is shared by every session, and a session without `rate_limits` yet (just
#   started, just compacted) replaces a good reading from another one. When the tap has no reading, the helper reads
#   the last reading by the same rules, at most 1800 s old (ESTIMATE_MAX_AGE_S) instead of 300 s. Usable →
#   MODE=estimated: its numbers are judged against the lower limit LIMIT_ESTIMATED — the reading is old, the window
#   has moved on since. Not usable either → MODE=conservative, UNKNOWN naming both causes.
#
# The limits, from the profile's `## Autopilot` block (craft-profile.md):
#   - **Budget-before-slice:** 85   LIMIT_BEFORE    used + forecast above it → do not start
#   - **Budget-in-slice:** 95       LIMIT_DURING    five_hour at or above it → stop at the boundary
#   - **Budget-seven-day:** 90      LIMIT_SEVEN_DAY seven_day at or above it → do not start / go on
#   - **Budget-estimated:** 80      LIMIT_ESTIMATED with only the last reading (MODE=estimated): five_hour (+ the
#                                   forecast, before) at or above it → stop, in every gate (slice-093); never above
#                                   LIMIT_BEFORE or LIMIT_DURING — a lower one of those lowers it (a WARN= line when
#                                   the profile sets Budget-estimated above them)
#   - **Cache-guard-recache-tokens:** 150000   not a budget — the threshold of hooks/cache-guard.sh (slice-060): below
#                                       that many tokens a cold-cache re-write is cheaper than a restart. A positive
#                                       integer; this helper only validates it (hooks/cache-guard.sh reads it itself — it is
#                                       bash 3.2 and cannot call this helper) and prints no LIMIT_ line for it.
#   An integer 1–100 each (the budgets); a missing block or field takes the default, an invalid value the default plus
#   a WARN= line, any other `- **<key>:**` in the block (a typo) a WARN= line and nothing else, and so does any
#   other non-blank line that is not a `>` comment (a malformed one, review R2: a stricter limit must never
#   be dropped silently). The overage heuristic is fixed: a window at 99 % or more while the cache TTL is 5m —
#   the harness drops to the 5-minute TTL when it bills usage credits (design §6). It stops every gate.
#
# The forecast (before): the mean, rounded up, of the `Δ five_hour +<n> %` fields the epic plan's
#   `## Autopilot Log` carries on its `✓` lines — derived, never stored. `Δ five_hour ?` and any other
#   shape are no sample. No sample → FORECAST=0 (the first slice relies on the in-slice stop).
#
# The delta (after, with --slice): the last `▶` line for that slice in the log whose last ` · ` field
#   reads `five_hour <p> % until <HH:MM>` (the LOG_FIELD a2 logged; other ▶ lines of the slice are skipped)
#   against the tap now. `?` — no sample for the forecast — when there is no such line, that line is a
#   resume (`— resume at <Status>`, not `— create`) or an earlier invocation's (an epic's `run started` line
#   follows it), the usage is unknown, the window's reset time moved (it reset in between) or the difference
#   is negative: only a slice built start to end in one invocation measures its whole cost (review R1-16).
#
# The check (--check-line, review R1-3): the master's carry of LOG_FIELD into the log is checked by command,
#   not trusted. The last line of the epic plan's `## Autopilot Log` must be, for `start`,
#     - <YYYY-MM-DDTHH:MM:SSZ> · ▶ · <slice-id> · slice <k>/<n> <…> — <create | resume at <Status>> · <expect>
#   and for `landed`
#     - <YYYY-MM-DDTHH:MM:SSZ> · ✓ · <slice-id> · landed on <branch> (<range>) · <…> · <expect>
#   with <expect> the LOG_FIELD verbatim. Output: LINE_OK=yes|no, REASON=<why> on no; exit 0.
# Log lines inside a fence or a multi-line HTML comment are examples, not content (example-regions.sh).
#
# The verdict — callers act on VERDICT= only:
#   gate     unknown usage        overage   seven_day ≥ L7   five_hour rule
#   before   go (conservative)    stop      stop             five_hour + FORECAST > LIMIT_BEFORE → stop
#   during   go (conservative)    stop      —                five_hour ≥ LIMIT_DURING → stop
#   after    stop (conservative)  stop      stop             —
# A conservative `before` lets the slice run blind and its `after` stops the run: with no reading the
# run stops after every slice and the human's re-run is the answer (design §6, "conservative mode").
# MODE=estimated (the last reading, slice-093) — no overage check (99 % is past LIMIT_ESTIMATED anyway):
#   before   seven_day ≥ L7 → stop; five_hour + FORECAST ≥ LIMIT_ESTIMATED → stop; else go
#   during   five_hour ≥ LIMIT_ESTIMATED → stop; else go
#   after    seven_day ≥ L7 → stop; five_hour ≥ LIMIT_ESTIMATED → stop; else go — the run goes on
#
# Output (key=value lines, exit 0 whenever VERDICT= is printed; free text last on its line):
#   TAP=<path>  AGE_S=<n|->  FIVE_HOUR=<n|->  FIVE_HOUR_RESETS=<HH:MM|->  SEVEN_DAY=<n|->
#   SEVEN_DAY_RESETS=<YYYY-MM-DD HH:MM|->  TTL=<value|->  FORECAST=<n>  SAMPLES=<n>
#   LIMIT_BEFORE=<n>  LIMIT_DURING=<n>  LIMIT_SEVEN_DAY=<n>  LIMIT_ESTIMATED=<n>
#   (FIVE_HOUR / SEVEN_DAY / *_RESETS / TTL are the last reading's under MODE=estimated, `-` under conservative)
#   WARN=<text>                         one per invalid or unknown profile key, or an unreadable epic plan;
#                                       a profile one reads `Autopilot → …` (/craft:prime prefixes it)
#   MODE=normal|estimated|conservative
#   UNKNOWN=<cause>                     with MODE=estimated / conservative: why the tap has no reading (no tap at <path> |
#                                       tap unreadable: <path> | tap <n> s old, stale after 300 s |
#                                       no rate_limits in the tap | the reading predates the <window> reset at
#                                       <time>); conservative adds `; <why the last reading is no reading either>`
#                                       when a last reading exists
#   ESTIMATE=last reading <n> s old     with MODE=estimated
#   DELTA=<+n|?>                        after with --slice only
#   LOG_FIELD=<text>                    before: `five_hour <p> % until <HH:MM>`, `five_hour ~<p> % until <HH:MM>`
#                                       (estimated — no Δ sample: only an exact reading measures a slice) or `usage unknown`;
#                                       after with --slice: `Δ five_hour <+n|?> %` — appended verbatim as the
#                                       last ` · ` field of the ▶ / ✓ log line
#   VERDICT=go|stop
#   REASON=<text>                       why — for a stop, the line the ⛔ log line carries
#   ERROR=<reason> on a usage error (stderr), exit 2; python3 missing → ERROR=python3_not_found, exit 3.
#   A caller that gets no VERDICT= line treats it as a stop — the master and the builder alike.
#
# Runtime: bash >= 5 (scripts/, no hook reaches this) and python3 — both required by /craft:prime.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR=$2" >&2; exit "$1"; }

GATE=""
CHECK=""
EXPECT=""
EPIC=""
SLICE=""
TAP="${CRAFT_USAGE_TAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/craft/usage-tap.json}"
LAST=""
PROFILE=".claude/project/craft-profile.md"
NOW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gate) GATE="${2:-}"; shift 2 ;;
    --check-line) CHECK="${2:-}"; shift 2 ;;
    --expect) EXPECT="${2-}"; shift 2 ;;
    --epic-plan) EPIC="${2:-}"; shift 2 ;;
    --slice) SLICE="${2:-}"; shift 2 ;;
    --tap) TAP="${2:-}"; shift 2 ;;
    --last-reading) LAST="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --now) NOW="${2:-}"; shift 2 ;;
    *) die 2 "unknown_argument:$1" ;;
  esac
done
if [[ -n "$CHECK" ]]; then
  [[ -z "$GATE" ]] || die 2 "gate_and_check_line"
  case "$CHECK" in start|landed) ;; *) die 2 "bad_check_line:$CHECK" ;; esac
  [[ -n "$EPIC" && -n "$SLICE" && -n "$EXPECT" ]] || die 2 "check_line_needs_epic_plan_slice_expect"
else
  case "$GATE" in before|during|after) ;; *) die 2 "missing_gate" ;; esac
fi
[[ -z "$NOW" || "$NOW" =~ ^[0-9]+$ ]] || die 2 "bad_now:$NOW"
[[ -z "$SLICE" || "$SLICE" =~ ^slice-[0-9]+$ ]] || die 2 "bad_slice:$SLICE"
[[ -z "$SLICE" || -n "$EPIC" ]] || die 2 "slice_needs_epic_plan"
command -v python3 >/dev/null 2>&1 || die 3 "python3_not_found"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -d "$ROOT" ]] && cd "$ROOT" || die 2 "project_dir_unreachable:$ROOT"

# The epic plan with every example region blanked, line count kept. An epic plan that cannot be read
# costs the forecast and the delta, never the verdict on the window itself.
BLANKED=""
if [[ -n "$EPIC" ]]; then
  BLANKED="$(mktemp)"
  trap 'rm -f "$BLANKED"' EXIT
  if ! bash "$SCRIPT_DIR/example-regions.sh" blank markdown "$EPIC" > "$BLANKED" 2>/dev/null; then
    : > "$BLANKED"
    EPIC_WARN="epic plan unreadable: $EPIC — no forecast, no delta"
  fi
fi

[[ -n "$LAST" ]] || LAST="${TAP%.json}.last-reading.json"

python3 - "$GATE" "$TAP" "$PROFILE" "${BLANKED:-}" "$SLICE" "${NOW:-}" "${EPIC_WARN:-}" "$CHECK" "$EXPECT" "$LAST" <<'PY'
import json, math, os, re, sys, time

gate, tap, profile, blanked, slice_id, now_arg, epic_warn, check, expect, last_path = sys.argv[1:11]
now = int(now_arg) if now_arg else int(time.time())
STALE_S = 300
ESTIMATE_MAX_AGE_S = 1800
DEFAULTS = {"Budget-before-slice": 85, "Budget-in-slice": 95, "Budget-seven-day": 90, "Budget-estimated": 80, "Cache-guard-recache-tokens": 150000}
OVERAGE_PCT = 99
warns = [epic_warn] if epic_warn else []

def hhmm(ts):
    return time.strftime("%H:%M", time.localtime(ts))

def day_hhmm(ts):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))

# --- limits ------------------------------------------------------------------------------------
limits = dict(DEFAULTS)
given = set()  # the budget keys the profile sets validly
try:
    with open(profile, encoding="utf-8") as fh:
        text = fh.read()
except OSError:
    text = ""
block = re.search(r"^## Autopilot[ \t]*\r?$(.*?)(?=^## |\Z)", text, re.M | re.S)
if block:
    for raw in block.group(1).split("\n"):
        line = raw.rstrip("\r").strip()
        if not line or line.startswith(">"):
            continue
        m = re.fullmatch(r"- \*\*([A-Za-z-]+):\*\*[ \t]*(.*?)", line)
        if not m:
            warns.append(f"Autopilot → unreadable line '{line}' — ignored")
            continue
        key, val = m.group(1), m.group(2)
        if key not in DEFAULTS:
            warns.append(f"Autopilot → unknown key '{key}' — ignored")
            continue
        if key == "Cache-guard-recache-tokens":
            # Not a budget: the threshold of hooks/cache-guard.sh (slice-060), read there, only validated here.
            if re.fullmatch(r"[0-9]+", val) and int(val) >= 1:
                limits[key] = int(val)
            else:
                warns.append(f"Autopilot → {key}: '{val}' invalid — a positive integer; using {DEFAULTS[key]}")
        elif re.fullmatch(r"\d+", val) and 1 <= int(val) <= 100:
            limits[key] = int(val)
            given.add(key)
        else:
            warns.append(f"Autopilot → {key}: '{val}' invalid — an integer 1–100; using {DEFAULTS[key]}")
L_BEFORE, L_DURING, L_SEVEN = (limits["Budget-before-slice"], limits["Budget-in-slice"], limits["Budget-seven-day"])
L_EST = limits["Budget-estimated"]
# The estimated limit is the LOWER one (review R1-1): a profile that lowers Budget-before-slice or Budget-in-slice below
# it lowers it with them, or an old reading would let a run go on where an exact one stops. A value the profile sets
# above them is named; the default following a lowered limit is not.
if L_EST > min(L_BEFORE, L_DURING):
    if "Budget-estimated" in given:
        warns.append(f"Autopilot → Budget-estimated: {L_EST} is above Budget-before-slice / Budget-in-slice — "
                     f"using {min(L_BEFORE, L_DURING)}")
    L_EST = min(L_BEFORE, L_DURING)

# --- usage -------------------------------------------------------------------------------------
def read_usage(path, what, max_age):
    """(age, fields, cause): fields = (five, seven, five_reset, seven_reset, ttl); cause None when usable."""
    age = None
    try:
        age = max(0, now - int(os.path.getmtime(path)))
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError
    except FileNotFoundError:
        return age, (None,) * 5, f"no {what} at {path}"
    except (OSError, ValueError):
        return age, (None,) * 5, f"{what} unreadable: {path}"
    def num(*keys):
        cur = data
        for k in keys:
            if not isinstance(cur, dict) or k not in cur:
                return None
            cur = cur[k]
        return cur if isinstance(cur, (int, float)) and not isinstance(cur, bool) else None
    f5 = num("rate_limits", "five_hour", "used_percentage")
    f7 = num("rate_limits", "seven_day", "used_percentage")
    r5 = num("rate_limits", "five_hour", "resets_at")
    r7 = num("rate_limits", "seven_day", "resets_at")
    pc = data.get("prompt_cache")
    t = pc.get("ttl") if isinstance(pc, dict) and isinstance(pc.get("ttl"), str) else None
    fields = (f5, f7, r5, r7, t)
    if age > max_age:
        return age, fields, f"{what} {age} s old, stale after {max_age} s"
    if f5 is None or f7 is None:
        return age, fields, f"no rate_limits in the {what}"
    label = "the reading" if what == "tap" else f"the {what}"
    if r5 is not None and r5 <= now:
        return age, fields, f"{label} predates the five_hour reset at {hhmm(r5)}"
    if r7 is not None and r7 <= now:
        return age, fields, f"{label} predates the seven_day reset at {day_hhmm(r7)}"
    return age, fields, None

# The tap first; without a reading there, the last reading the tap kept (slice-093) — judged against L_EST.
age, (five, seven, five_reset, seven_reset, ttl), unknown = read_usage(tap, "tap", STALE_S)
mode = "normal" if unknown is None else "conservative"
est_age = None
if unknown is not None:
    est_age, est_fields, est_cause = read_usage(last_path, "last reading", ESTIMATE_MAX_AGE_S)
    if est_cause is None:
        mode = "estimated"
        five, seven, five_reset, seven_reset, ttl = est_fields
    elif os.path.lexists(last_path):
        unknown = f"{unknown}; {est_cause}"
if mode != "conservative":
    five, seven = math.ceil(five), math.ceil(seven)
else:
    five = seven = None

def resets(which):
    ts = five_reset if which == "five" else seven_reset
    if ts is None:
        return ""
    return f" — resets {hhmm(ts) if which == 'five' else day_hhmm(ts)}"

# --- the log -----------------------------------------------------------------------------------
log = []
if blanked:
    with open(blanked, encoding="utf-8", newline="") as fh:
        lines = fh.read().split("\n")
    inside = False
    for ln in lines:
        s = ln.rstrip("\r")
        if s.startswith("## "):
            inside = s.rstrip() == "## Autopilot Log"
            continue
        if inside:
            log.append(s)
if check:
    DT = r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"
    body = [s for s in log if s.strip()]
    last_line = body[-1] if body else ""
    if check == "start":
        ok = re.fullmatch(DT.join(["- ", f" · ▶ · {re.escape(slice_id)} · slice \\d+/\\d+ .+ — (create|resume at \\S+) · "])
                          + re.escape(expect), last_line)
        ok = ok and re.fullmatch(r"five_hour ~?\d+ % until \d\d:\d\d|usage unknown", expect)
    else:
        ok = re.fullmatch(DT.join(["- ", f" · ✓ · {re.escape(slice_id)} · landed on \\S+ \\(\\S+\\) · .+ · "])
                          + re.escape(expect), last_line)
        ok = ok and re.fullmatch(r"Δ five_hour (\+\d+|\?) %", expect)
    print("LINE_OK=" + ("yes" if ok else "no"))
    if not ok:
        print(f"REASON=the last ## Autopilot Log line is not the {check} line for {slice_id} ending in '{expect}': "
              + (last_line or "(no line)"))
    sys.exit(0)

LINE_RE = re.compile(r"^- \S+ · (▶|✓) · (slice-\d+) · (.*)$")
RUN_RE = re.compile(r"^- \S+ · ▶ · epic-\d+ · run started")
samples = []
start = None            # (percent, HH:MM, created-in-this-line, line index)
last_run = -1
for i, s in enumerate(log):
    if RUN_RE.match(s):
        last_run = i
        continue
    m = LINE_RE.match(s)
    if not m:
        continue
    kind, sid, rest = m.groups()
    head, _, last = rest.rpartition(" · ")
    if kind == "✓":
        d = re.fullmatch(r"Δ five_hour \+(\d+) %", last)
        if d:
            samples.append(int(d.group(1)))
    elif sid == slice_id:
        st = re.fullmatch(r"five_hour (\d+) % until (\d\d:\d\d)", last)
        if st:
            start = (int(st.group(1)), st.group(2), head.endswith(" — create"), i)
forecast = math.ceil(sum(samples) / len(samples)) if samples else 0

# --- verdict -----------------------------------------------------------------------------------
verdict, reason = "go", ""
overage = (mode == "normal" and ttl == "5m" and max(five, seven) >= OVERAGE_PCT)
est = f" (estimated: last reading {est_age} s old — {unknown})" if mode == "estimated" else ""
if mode == "estimated":
    if gate in ("before", "after") and seven >= L_SEVEN:
        verdict, reason = "stop", f"seven_day ~{seven} % ≥ {L_SEVEN} %{resets('seven')}{est}"
    elif gate == "before" and five + forecast >= L_EST:
        verdict, reason = "stop", f"five_hour ~{five} % + forecast {forecast} % ≥ {L_EST} %{resets('five')}{est}"
    elif gate in ("during", "after") and five >= L_EST:
        verdict, reason = "stop", f"five_hour ~{five} % ≥ {L_EST} %{resets('five')}{est}"
    else:
        reason = (f"five_hour ~{five} % + forecast {forecast} % < {L_EST} %" if gate == "before"
                  else f"five_hour ~{five} % < {L_EST} %") + f", seven_day ~{seven} %{est}"
elif unknown is not None:
    if gate == "after":
        verdict, reason = "stop", f"usage unknown ({unknown}) — stopped after the slice"
    else:
        reason = f"usage unknown ({unknown}) — the run stops after this slice"
elif overage:
    which = "five" if five >= OVERAGE_PCT else "seven"
    pct = five if which == "five" else seven
    verdict = "stop"
    reason = f"overage: {'five_hour' if which == 'five' else 'seven_day'} {pct} % at cache TTL 5m{resets(which)}"
elif gate in ("before", "after") and seven >= L_SEVEN:
    verdict, reason = "stop", f"seven_day {seven} % ≥ {L_SEVEN} %{resets('seven')}"
elif gate == "before" and five + forecast > L_BEFORE:
    verdict, reason = "stop", f"five_hour {five} % + forecast {forecast} % > {L_BEFORE} %{resets('five')}"
elif gate == "during" and five >= L_DURING:
    verdict, reason = "stop", f"five_hour {five} % ≥ {L_DURING} %{resets('five')}"
else:
    reason = (f"five_hour {five} % + forecast {forecast} % ≤ {L_BEFORE} %, seven_day {seven} % < {L_SEVEN} %"
              if gate == "before" else
              f"five_hour {five} % < {L_DURING} %" if gate == "during" else
              f"seven_day {seven} % < {L_SEVEN} %")

delta = None
if gate == "after" and slice_id:
    delta = "?"
    if (mode == "normal" and start is not None and start[2] and start[3] > last_run
            and five_reset is not None and hhmm(five_reset) == start[1]):
        d = five - start[0]
        if d >= 0:
            delta = f"+{d}"

def show(v):
    return "-" if v is None else str(v)

print(f"TAP={tap}")
print(f"AGE_S={show(age)}")
print(f"FIVE_HOUR={show(five)}")
print(f"FIVE_HOUR_RESETS={hhmm(five_reset) if five_reset is not None else '-'}")
print(f"SEVEN_DAY={show(seven)}")
print(f"SEVEN_DAY_RESETS={day_hhmm(seven_reset) if seven_reset is not None else '-'}")
print(f"TTL={show(ttl)}")
print(f"FORECAST={forecast}")
print(f"SAMPLES={len(samples)}")
print(f"LIMIT_BEFORE={L_BEFORE}")
print(f"LIMIT_DURING={L_DURING}")
print(f"LIMIT_SEVEN_DAY={L_SEVEN}")
print(f"LIMIT_ESTIMATED={L_EST}")
for w in warns:
    print(f"WARN={w}")
print(f"MODE={mode}")
if unknown is not None:
    print(f"UNKNOWN={unknown}")
if mode == "estimated":
    print(f"ESTIMATE=last reading {est_age} s old")
if delta is not None:
    print(f"DELTA={delta}")
if gate == "before":
    print("LOG_FIELD=" + ("usage unknown" if mode == "conservative" or five_reset is None
                          else f"five_hour {'~' if mode == 'estimated' else ''}{five} % until {hhmm(five_reset)}"))
elif delta is not None:
    print(f"LOG_FIELD=Δ five_hour {delta} %")
print(f"VERDICT={verdict}")
print(f"REASON={reason}")
PY
