#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-usage-state.sh — self-contained tests for the autopilot's budget guard (slice-058):
# scripts/statusline-tap.sh (the sensor) and scripts/usage-state.sh (the verdict), and the sites that
# act on the verdict. Run it directly:
#
#   bash scripts/test-usage-state.sh
#
# Times are compared in UTC (TZ=UTC). It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail
export TZ=UTC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/usage-state.sh"
TAPPER="$SCRIPT_DIR/statusline-tap.sh"
for f in "$HELPER" "$TAPPER" "$SCRIPT_DIR/example-regions.sh"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
expect() { # <label> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — got '$2', want '$3'"; fi
}

ROOT="$(mktemp -d)"
trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
mkdir -p "$P/.claude/project" "$P/.claude/plans"
TAP="$ROOT/tap.json"
EPIC=".claude/plans/epic-009-fixture.md"

R5=$(( ($(date +%s) / 3600 + 3) * 3600 ))        # five_hour resets_at: a whole hour ahead, like the real tap
R7=$(( R5 + 3 * 86400 ))                          # seven_day resets_at
H5="$(date -u -r "$R5" +%H:%M 2>/dev/null || date -u -d "@$R5" +%H:%M)"
D7="$(date -u -r "$R7" '+%Y-%m-%d %H:%M' 2>/dev/null || date -u -d "@$R7" '+%Y-%m-%d %H:%M')"

# tap <five> <seven> [ttl] [five_resets] — a statusline JSON like Claude Code 2.1.289's
tap() {
  printf '{"session_id":"s","prompt_cache":{"ttl":"%s","expires_at":1},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' \
    "${3:-1h}" "$1" "${4:-$R5}" "$2" "$R7" > "$TAP"
}
mtime() { python3 -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))' "$1"; }
# run <args…> — the helper with the clock 10 s after the tap was written
run() {
  local now; now=$(( $(mtime "$TAP" 2>/dev/null || date +%s) + ${AGE:-10} ))
  (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" --tap "$TAP" --now "$now" "$@" 2>&1)
}
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
profile() { printf '# CRAFT Profile\n\n> Preset: balanced\n\n%s\n\n## Operational Language\n\n- **Chat:** en\n' "$1" > "$P/.claude/project/craft-profile.md"; }
noprofile() { rm -f "$P/.claude/project/craft-profile.md"; }
# epic <log body> — an epic plan whose ## Autopilot Log holds the body
epic() {
  printf '# Epic 009 — Fixture\n\n> Epic-ID: epic-009\n\n## Slice Decomposition\n\n- [ ] slice-101 — alpha — a\n\n## Autopilot Log\n\n%s\n\n## Recap Draft\n\n%s\n' \
    "$1" "${2:-(not yet recorded)}" > "$P/$EPIC"
}
landed() { printf -- '- 2026-10-06T10:%s:00Z · ✓ · %s · landed on epic-009-fixture (a..b) · verified by command (3/3, run 1, x) · Δ five_hour %s %%' "$1" "$2" "$3"; }
started() { printf -- '- 2026-10-06T10:%s:00Z · ▶ · %s · slice 1/2 %s "Alpha · beta" — create · %s' "$1" "$2" "$2" "$3"; }
resumed() { printf -- '- 2026-10-06T10:%s:00Z · ▶ · %s · slice 1/2 %s "Alpha" — resume at testing · %s' "$1" "$2" "$2" "$3"; }
runstart() { printf -- '- 2026-10-06T10:%s:00Z · ▶ · epic-009 · run started' "$1"; }

echo "== usage unknown → conservative"
noprofile
rm -f "$TAP"
out="$(run --gate before)"
expect "no tap: before goes"                "$(val "$out" VERDICT)" "go"
expect "no tap: MODE"                        "$(val "$out" MODE)" "conservative"
expect "no tap: LOG_FIELD"                   "$(val "$out" LOG_FIELD)" "usage unknown"
expect "no tap: REASON names the path"       "$(val "$out" REASON)" "usage unknown (no tap at $TAP) — the run stops after this slice"
expect "no tap: during goes"                 "$(val "$(run --gate during)" VERDICT)" "go"
expect "no tap: after stops"                 "$(val "$(run --gate after)" VERDICT)" "stop"
tap 10 10
expect "age 300 s is fresh"                  "$(val "$(AGE=300 run --gate before)" MODE)" "normal"
out="$(AGE=301 run --gate after)"
expect "age 301 s is stale"                  "$(val "$out" MODE)" "conservative"
expect "stale: after stops"                  "$(val "$out" VERDICT)" "stop"
expect "stale: REASON"                       "$(val "$out" REASON)" "usage unknown (tap 301 s old, stale after 300 s) — stopped after the slice"
expect "stale: UNKNOWN names the cause"      "$(val "$out" UNKNOWN)" "tap 301 s old, stale after 300 s"
expect "stale: no percentage reported"       "$(val "$out" FIVE_HOUR)" "-"
expect "a reading: no UNKNOWN line"          "$(val "$(run --gate before)" UNKNOWN)" ""
PAST=$(( $(date +%s) - 3600 ))
printf '{"rate_limits":{"five_hour":{"used_percentage":70,"resets_at":%s},"seven_day":{"used_percentage":5,"resets_at":%s}}}' "$PAST" "$R7" > "$TAP"
out="$(run --gate before)"
expect "a passed five_hour reset → conservative (R1-18)" "$(val "$out" MODE)" "conservative"
expect "the expired window is named"         "$(val "$out" UNKNOWN)" "the reading predates the five_hour reset at $(date -u -r "$PAST" +%H:%M 2>/dev/null || date -u -d "@$PAST" +%H:%M)"
printf '{"rate_limits":{"five_hour":{"used_percentage":70,"resets_at":%s},"seven_day":{"used_percentage":5,"resets_at":%s}}}' "$R5" "$PAST" > "$TAP"
expect "a passed seven_day reset → conservative" "$(val "$(run --gate before)" MODE)" "conservative"

printf 'not json' > "$TAP"
expect "malformed tap → conservative"       "$(val "$(run --gate before)" MODE)" "conservative"
printf '[1,2]' > "$TAP"
expect "a JSON array → conservative"        "$(val "$(run --gate before)" REASON)" "usage unknown (tap unreadable: $TAP) — the run stops after this slice"
printf '{"prompt_cache":{"ttl":"1h"}}' > "$TAP"
expect "no rate_limits → conservative"      "$(val "$(run --gate before)" REASON)" "usage unknown (no rate_limits in the tap) — the run stops after this slice"
printf '{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1}}}' > "$TAP"
expect "no seven_day → conservative"        "$(val "$(run --gate before)" MODE)" "conservative"
printf '{"rate_limits":{"five_hour":{"used_percentage":"10"},"seven_day":{"used_percentage":10}}}' > "$TAP"
expect "a string percentage → conservative" "$(val "$(run --gate before)" MODE)" "conservative"
printf '{"rate_limits":{"five_hour":{"used_percentage":12.2},"seven_day":{"used_percentage":3}}}' > "$TAP"
out="$(run --gate before)"
expect "no resets_at: still judged"         "$(val "$out" VERDICT)" "go"
expect "a fraction rounds up"               "$(val "$out" FIVE_HOUR)" "13"
expect "no resets_at: LOG_FIELD unknown"    "$(val "$out" LOG_FIELD)" "usage unknown"

echo "== before: five_hour + forecast vs. 85, seven_day vs. 90"
epic "(no autopilot run yet)"
tap 85 10
out="$(run --gate before --epic-plan "$EPIC")"
expect "85 % + 0 is not above 85"           "$(val "$out" VERDICT)" "go"
expect "LOG_FIELD names the reset"          "$(val "$out" LOG_FIELD)" "five_hour 85 % until $H5"
expect "fields: FIVE_HOUR_RESETS"           "$(val "$out" FIVE_HOUR_RESETS)" "$H5"
expect "fields: SEVEN_DAY_RESETS"           "$(val "$out" SEVEN_DAY_RESETS)" "$D7"
expect "fields: TTL"                        "$(val "$out" TTL)" "1h"
expect "fields: AGE_S"                      "$(val "$out" AGE_S)" "10"
tap 86 10
out="$(run --gate before --epic-plan "$EPIC")"
expect "86 % + 0 stops"                     "$(val "$out" VERDICT)" "stop"
expect "the stop's REASON"                  "$(val "$out" REASON)" "five_hour 86 % + forecast 0 % > 85 % — resets $H5"
epic "$(started 00 slice-101 "five_hour 1 % until $H5")
$(landed 01 slice-101 +7)
$(landed 02 slice-102 +6)"
tap 78 10
out="$(run --gate before --epic-plan "$EPIC")"
expect "forecast = mean rounded up (6.5 → 7)" "$(val "$out" FORECAST)" "7"
expect "two samples"                        "$(val "$out" SAMPLES)" "2"
expect "78 + 7 = 85 goes"                   "$(val "$out" VERDICT)" "go"
tap 79 10
expect "79 + 7 stops"                       "$(val "$(run --gate before --epic-plan "$EPIC")" REASON)" "five_hour 79 % + forecast 7 % > 85 % — resets $H5"
tap 10 89
expect "seven_day 89 goes"                  "$(val "$(run --gate before)" VERDICT)" "go"
tap 10 90
out="$(run --gate before)"
expect "seven_day 90 stops before"          "$(val "$out" REASON)" "seven_day 90 % ≥ 90 % — resets $D7"
expect "seven_day 90 stops after"           "$(val "$(run --gate after)" VERDICT)" "stop"
expect "seven_day 90 does not stop during"  "$(val "$(run --gate during)" VERDICT)" "go"
tap 20 30
expect "after goes below the limits"        "$(val "$(run --gate after)" VERDICT)" "go"

echo "== during: five_hour vs. 95"
tap 94 10
expect "94 goes"                            "$(val "$(run --gate during)" VERDICT)" "go"
tap 95 10
out="$(run --gate during)"
expect "95 stops"                           "$(val "$out" VERDICT)" "stop"
expect "the stop's REASON"                  "$(val "$out" REASON)" "five_hour 95 % ≥ 95 % — resets $H5"
expect "during prints no LOG_FIELD"         "$(val "$out" LOG_FIELD)" ""

echo "== overage: a window ≥ 99 % at cache TTL 5m"
tap 10 99 5m
out="$(run --gate during)"
expect "seven_day 99 at 5m stops during"    "$(val "$out" VERDICT)" "stop"
expect "overage REASON"                     "$(val "$out" REASON)" "overage: seven_day 99 % at cache TTL 5m — resets $D7"
tap 10 99 1h
expect "seven_day 99 at 1h: no overage during" "$(val "$(run --gate during)" VERDICT)" "go"
tap 10 98 5m
expect "seven_day 98 at 5m: no overage"     "$(val "$(run --gate during)" VERDICT)" "go"
tap 99 10 5m
expect "five_hour 99 at 5m names overage"   "$(val "$(run --gate before)" REASON)" "overage: five_hour 99 % at cache TTL 5m — resets $H5"
tap 99 10 1h
expect "five_hour 99 at 1h is the limit rule" "$(val "$(run --gate before)" REASON)" "five_hour 99 % + forecast 0 % > 85 % — resets $H5"

echo "== the profile's ## Autopilot block"
profile "## Autopilot

- **Budget-before-slice:** 70
- **Budget-in-slice:** 80
- **Budget-seven-day:** 60
- **Something-else:** 5"
tap 71 10
out="$(run --gate before)"
expect "LIMIT_BEFORE from the profile"      "$(val "$out" LIMIT_BEFORE)" "70"
expect "LIMIT_DURING from the profile"      "$(val "$out" LIMIT_DURING)" "80"
expect "LIMIT_SEVEN_DAY from the profile"   "$(val "$out" LIMIT_SEVEN_DAY)" "60"
expect "71 stops under a 70 limit"          "$(val "$out" VERDICT)" "stop"
expect "an unknown key WARNs (R1-4)"       "$(printf '%s\n' "$out" | grep '^WARN=')" "WARN=Autopilot → unknown key 'Something-else' — ignored"
tap 80 10
expect "80 stops during under an 80 limit"  "$(val "$(run --gate during)" VERDICT)" "stop"
profile "## Autopilot

- **Budget-before-slice:** abc
- **Budget-in-slice:** 0
- **Budget-seven-day:** 101"
out="$(run --gate before)"
expect "invalid values: three WARN lines"   "$(printf '%s\n' "$out" | grep -c '^WARN=')" "3"
expect "invalid value → default"            "$(val "$out" LIMIT_BEFORE)" "85"
expect "0 → default"                        "$(val "$out" LIMIT_DURING)" "95"
expect "101 → default"                      "$(val "$out" LIMIT_SEVEN_DAY)" "90"
expect "the WARN text"                      "$(printf '%s\n' "$out" | grep '^WARN=' | head -1)" "WARN=Autopilot → Budget-before-slice: 'abc' invalid — an integer 1–100; using 85"
profile "## Autopilot

> a comment line is fine

- **Budget-in-slice**: 50
- **Budget in slice:** 40"
out="$(run --gate during)"
expect "malformed lines: two WARN lines (R2)" "$(printf '%s\n' "$out" | grep -c '^WARN=Autopilot → unreadable line')" "2"
expect "malformed lines: the limit stays the default" "$(val "$out" LIMIT_DURING)" "95"
for f in "$REPO_ROOT/templates/craft-profile.md.template" "$REPO_ROOT"/templates/profiles/*.md; do
  expect "$(basename "$f"): the shipped block WARNs nothing" "$(cd "$P" && bash "$HELPER" --gate before --tap "$TAP" --profile "$f" 2>&1 | grep -c '^WARN=')" "0"
done
profile "## Execution

- **Budget-before-slice:** 10"
expect "a key outside ## Autopilot counts not" "$(val "$(run --gate before)" LIMIT_BEFORE)" "85"
noprofile
expect "no profile → defaults"              "$(val "$(run --gate before)" LIMIT_SEVEN_DAY)" "90"

echo "== forecast samples"
epic "$(landed 01 slice-101 '?')
$(landed 02 slice-102 5)
- 2026-10-06T10:03:00Z · ✓ · slice-103 · landed on x (a..b) · Δ five_hour +4 %
\`\`\`
$(landed 04 slice-104 +90)
\`\`\`
- 2026-10-06T10:05:00Z · ✓ · epic-009 · plan gate approved: slice-101" "$(landed 06 slice-106 +80)"
out="$(run --gate before --epic-plan "$EPIC")"
expect "only '+4' counts (?, unsigned, fenced, another section, epic lines do not)" "$(val "$out" SAMPLES)" "1"
expect "forecast 4"                         "$(val "$out" FORECAST)" "4"
printf '# Epic\r\n\r\n## Autopilot Log\r\n\r\n%s\r\n' "$(landed 01 slice-101 +3)" > "$P/$EPIC"
expect "a CRLF log line counts"             "$(val "$(run --gate before --epic-plan "$EPIC")" FORECAST)" "3"
out="$(run --gate before --epic-plan .claude/plans/missing.md)"
expect "unreadable epic plan: still a verdict" "$(val "$out" VERDICT)" "go"
expect "unreadable epic plan: a WARN"       "$(printf '%s\n' "$out" | grep -c '^WARN=epic plan unreadable')" "1"

echo "== after: the slice's Δ five_hour"
epic "$(started 00 slice-101 "five_hour 20 % until $H5")"
tap 27 10
out="$(run --gate after --epic-plan "$EPIC" --slice slice-101)"
expect "Δ = now − start"                    "$(val "$out" DELTA)" "+7"
expect "LOG_FIELD for the landed line"      "$(val "$out" LOG_FIELD)" "Δ five_hour +7 %"
epic "$(started 00 slice-101 "five_hour 20 % until $H5")
$(started 05 slice-101 "five_hour 25 % until $H5")"
expect "the last create line counts"        "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "+2"
epic "$(started 00 slice-101 "five_hour 20 % until $H5")
$(resumed 05 slice-101 "five_hour 25 % until $H5")"
expect "a resume is no sample (R1-16)"      "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "?"
epic "$(runstart 00)
$(started 01 slice-101 "five_hour 20 % until $H5")
- 2026-10-06T10:02:00Z · ▶ · slice-101 · planned from entry foo"
expect "a non-matching ▶ line is skipped (R1-12)" "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "+7"
epic "$(runstart 00)
$(started 01 slice-101 "five_hour 20 % until $H5")
$(runstart 02)"
expect "started in an earlier invocation → ? (R1-16)" "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "?"
epic "$(started 00 slice-101 "five_hour 20 % until 23:59")"
expect "reset in between → ?"               "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "?"
epic "$(started 00 slice-101 "five_hour 40 % until $H5")"
expect "negative → ?"                       "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "?"
epic "$(started 00 slice-102 "five_hour 1 % until $H5")
$(started 01 slice-101 "usage unknown")"
out="$(run --gate after --epic-plan "$EPIC" --slice slice-101)"
expect "no reading at start → ?"            "$(val "$out" DELTA)" "?"
expect "LOG_FIELD with ?"                   "$(val "$out" LOG_FIELD)" "Δ five_hour ? %"
rm -f "$TAP"
epic "$(started 00 slice-101 "five_hour 20 % until $H5")"
expect "unknown usage now → ?"              "$(val "$(run --gate after --epic-plan "$EPIC" --slice slice-101)" DELTA)" "?"
tap 27 10
expect "after without --slice: no DELTA"    "$(val "$(run --gate after --epic-plan "$EPIC")" DELTA)" ""

echo "== --check-line: the master's carry checked by command (R1-3)"
chk() { (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" --check-line "$@" 2>&1); }
F5="five_hour 20 % until $H5"
epic "$(runstart 00)
$(started 01 slice-101 "$F5")"
expect "a start line as written"            "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "$F5")" LINE_OK)" "yes"
expect "another slice's ID"                 "$(val "$(chk start --epic-plan "$EPIC" --slice slice-102 --expect "$F5")" LINE_OK)" "no"
expect "a field that differs from LOG_FIELD" "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "five_hour 21 % until $H5")" LINE_OK)" "no"
epic "$(started 01 slice-101 "five_hour 20% until $H5")"
out="$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "$F5")"
expect "a paraphrase (20%) fails"           "$(val "$out" LINE_OK)" "no"
expect "the REASON quotes the line"         "$(val "$out" REASON | grep -c 'five_hour 20% until')" "1"
epic "- 2026-10-06T10:01:00Z · ▶ · epic-009 · slice 1/2 slice-101 \"A\" — create · $F5"
expect "the epic-ID in the ID field fails"  "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "$F5")" LINE_OK)" "no"
epic "$(started 01 slice-101 "$F5")
$(runstart 02)"
expect "not the last line fails"            "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "$F5")" LINE_OK)" "no"
epic "$(started 01 slice-101 "$F5")
- 2026-10-06T10:02:00Z · ⛔ · epic-009 · something else"
expect "a later ⛔ line: the start line is not last" "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "$F5")" LINE_OK)" "no"
epic "$(resumed 01 slice-101 "usage unknown")"
expect "a resume line with usage unknown"   "$(val "$(chk start --epic-plan "$EPIC" --slice slice-101 --expect "usage unknown")" LINE_OK)" "yes"
epic "$(started 01 slice-101 "$F5")
$(landed 09 slice-101 +6)"
expect "a landed line as written"           "$(val "$(chk landed --epic-plan "$EPIC" --slice slice-101 --expect "Δ five_hour +6 %")" LINE_OK)" "yes"
expect "a landed Δ that differs"            "$(val "$(chk landed --epic-plan "$EPIC" --slice slice-101 --expect "Δ five_hour +7 %")" LINE_OK)" "no"
epic "$(landed 09 slice-101 '?')"
expect "a landed ? line"                    "$(val "$(chk landed --epic-plan "$EPIC" --slice slice-101 --expect "Δ five_hour ? %")" LINE_OK)" "yes"
epic "\`\`\`
$(landed 09 slice-101 +6)
\`\`\`"
expect "a fenced line is no line"           "$(val "$(chk landed --epic-plan "$EPIC" --slice slice-101 --expect "Δ five_hour +6 %")" LINE_OK)" "no"
(cd "$P" && bash "$HELPER" --check-line start --epic-plan "$EPIC" --slice slice-101 >/dev/null 2>&1); expect "--check-line without --expect → exit 2" "$?" "2"
(cd "$P" && bash "$HELPER" --gate after --check-line start --epic-plan "$EPIC" --slice slice-101 --expect x >/dev/null 2>&1); expect "--gate with --check-line → exit 2" "$?" "2"

echo "== usage errors"
(cd "$P" && bash "$HELPER" >/dev/null 2>&1); expect "no --gate → exit 2" "$?" "2"
(cd "$P" && bash "$HELPER" --gate later >/dev/null 2>&1); expect "an unknown gate → exit 2" "$?" "2"
(cd "$P" && bash "$HELPER" --gate after --slice slice-1 >/dev/null 2>&1); expect "--slice without --epic-plan → exit 2" "$?" "2"
(cd "$P" && bash "$HELPER" --gate after --now soon >/dev/null 2>&1); expect "a bad --now → exit 2" "$?" "2"
(cd "$P" && bash "$HELPER" --gate before --bogus >/dev/null 2>&1); expect "an unknown argument → exit 2" "$?" "2"

echo "== statusline-tap.sh"
T="$ROOT/tapdir/usage-tap.json"
printf '{"a":1}\n\n' > "$ROOT/in.json"
for sh in /bin/sh /bin/bash; do
  rm -rf "$ROOT/tapdir"
  CRAFT_USAGE_TAP="$T" "$sh" "$TAPPER" -- cat < "$ROOT/in.json" > "$ROOT/out.json"
  cmp -s "$ROOT/in.json" "$ROOT/out.json" && ok "$sh: the command reads stdin byte-equal" || bad "$sh: the command's stdin differs"
  cmp -s "$ROOT/in.json" "$T" && ok "$sh: the tap holds the JSON byte-equal" || bad "$sh: the tap differs"
done
out="$(printf '{"b":2}' | CRAFT_USAGE_TAP="$T" sh "$TAPPER" sh -c 'cat >/dev/null; echo shown; exit 7')"; rc=$?
expect "the command's stdout is the statusline" "$out" "shown"
expect "the command's exit code is kept"    "$rc" "7"
expect "a failing command still taps"       "$(cat "$T")" '{"b":2}'
out="$(printf '{"c":3}' | CRAFT_USAGE_TAP="$T" sh "$TAPPER")"; rc=$?
expect "no command: prints nothing"         "$out" ""
expect "no command: exit 0"                 "$rc" "0"
expect "no command: still taps"             "$(cat "$T")" '{"c":3}'
printf '{"d":4}' | CRAFT_USAGE_TAP="$T" sh "$TAPPER" echo hi >/dev/null
expect "a command that ignores stdin: tapped" "$(cat "$T")" '{"d":4}'
printf '' | CRAFT_USAGE_TAP="$T" sh "$TAPPER" cat >/dev/null
expect "empty stdin leaves the tap as it was" "$(cat "$T")" '{"d":4}'
expect "no temp file left behind"           "$(ls -A "$ROOT/tapdir")" "usage-tap.json"
# R1-2: Claude Code kills a statusline still running at the next refresh — the tap must already be written.
K="$ROOT/kill/usage-tap.json"
printf '{"k":1}' > "$ROOT/k.json"
CRAFT_USAGE_TAP="$K" sh "$TAPPER" sleep 2 < "$ROOT/k.json" > /dev/null &
kpid=$!
sleep 0.5
kill "$kpid" 2>/dev/null
wait "$kpid" 2>/dev/null
expect "killed mid-command: the tap is written" "$(cat "$K" 2>/dev/null)" '{"k":1}'
expect "killed mid-command: no temp file left"  "$(ls -A "$ROOT/kill")" "usage-tap.json"
out="$(printf '{"g":7}' | CRAFT_USAGE_TAP="$T" sh "$TAPPER" cat)"
expect "the command still reads the bytes after the rename" "$out" '{"g":7}'
mkdir -p "$ROOT/ro"; chmod 555 "$ROOT/ro"
if [[ -w "$ROOT/ro" ]]; then
  ok "fail open: skipped (running as a user who can write anywhere)"
else
  out="$(printf '{"e":5}' | CRAFT_USAGE_TAP="$ROOT/ro/sub/tap.json" sh "$TAPPER" cat)"; rc=$?
  expect "fail open: the statusline still gets stdin" "$out" '{"e":5}'
  expect "fail open: exit 0"                "$rc" "0"
  expect "fail open: nothing written"       "$(ls -A "$ROOT/ro")" ""
fi
chmod 755 "$ROOT/ro"
mkdir -p "$ROOT/cfg"
printf '{"f":6}' | env -u CRAFT_USAGE_TAP CLAUDE_CONFIG_DIR="$ROOT/cfg" sh "$TAPPER" >/dev/null
expect "default path under CLAUDE_CONFIG_DIR" "$(cat "$ROOT/cfg/craft/usage-tap.json" 2>/dev/null)" '{"f":6}'
tap 30 20
cat "$TAP" | env -u CRAFT_USAGE_TAP CLAUDE_CONFIG_DIR="$ROOT/cfg" sh "$TAPPER" >/dev/null
out="$(cd "$P" && env -u CRAFT_USAGE_TAP CLAUDE_CONFIG_DIR="$ROOT/cfg" bash "$HELPER" --gate before)"
expect "tap → helper on the default path"   "$(val "$out" LOG_FIELD)" "five_hour 30 % until $H5"
grep -qE '\[\[|\$\(\(|local |function |declare |pipefail' "$TAPPER" && bad "statusline-tap.sh uses a non-POSIX construct" || ok "statusline-tap.sh stays POSIX sh"

echo "== the sites that act on the verdict"
EXECUTE="$REPO_ROOT/commands/execute.md"; BUILD="$REPO_ROOT/commands/build.md"
BUILDER="$REPO_ROOT/agents/slice-builder.md"; PRIME="$REPO_ROOT/commands/prime.md"
pin() { # <file> <needle> <what>
  if [[ -f "$1" ]] && grep -qF -- "$2" "$1"; then ok "$(basename "$1"): $3"; else bad "$(basename "$1") no longer $3 ('$2')"; fi
}
pin "$EXECUTE" 'scripts/usage-state.sh" --gate <before|after>' "calls the helper's before / after gates"
pin "$EXECUTE" "budget guard's \`before\` gate (above); a stop ends the run there" "runs the before gate in a2"
pin "$EXECUTE" '· ▶ · <slice-id> · slice <k>/<n> "<title>" — <create | resume at <Status>> · <LOG_FIELD>' "logs the ▶ line with the slice-ID and LOG_FIELD last (the delta reads it)"
pin "$EXECUTE" '· ✓ · <slice-id> · landed on <epic-branch>' "logs the ✓ line with the slice-ID in the ID field"
pin "$EXECUTE" 'scripts/usage-state.sh" --check-line <start|landed>' "checks the carry of LOG_FIELD by command (R1-3)"
pin "$EXECUTE" "log check (\`start\`)" "runs the log check in a2"
pin "$EXECUTE" "log check (\`landed\`)" "runs the log check in a3"
pin "$EXECUTE" 'this one `⛔` line, not the Handoff line below' "writes one ⛔ line for a builder's budget stop (R1-11)"
pin "$EXECUTE" '· <the phrase from 1> · <LOG_FIELD>' "logs the Δ as the ✓ line's last field (the forecast reads it)"
pin "$EXECUTE" '`--slice <slice-id>`' "passes --slice to the after gate"
pin "$EXECUTE" '⛔ · <epic-id> · budget: <REASON>' "logs a budget stop"
pin "$EXECUTE" 'after <the reset time it names> | now (no usage reading) | after wiring the tap | after fixing <what failed>' "tells the human when to re-run per stop kind (R1-9)"
pin "$EXECUTE" 'Autopilot — stopped after a landed slice (a4, budget only)' "has a stopped block for an a4 stop (R1-10)"
pin "$EXECUTE" '**No `VERDICT=` line**' "stops when the helper gives no verdict"
pin "$EXECUTE" '`reason=budget`' "classifies the builder's budget stop"
DEBUG="$REPO_ROOT/skills/debug/SKILL.md"
pin "$BUILDER" 'scripts/usage-state.sh" --gate during' "runs the during gate (its one definition)"
pin "$BUILDER" 'before each phase step after step 1' "asks at every phase boundary, not only in Phase 4 (R1-1)"
pin "$BUILDER" 'before each attempt of `skills/debug/SKILL.md`' "asks before each autonomous debug attempt (R1-1)"
pin "$BUILDER" 'before steps 2, 3, 4, 5 and 6' "asks before reporting committing (R2, reopens R1-1)"
pin "$BUILDER" 'again when a review loop-back sends you back there' "asks before a loop-back's first sub-task (R2)"
pin "$EXECUTE" 'once per invocation, before its first slice step — a2' "logs run started before a3 too (R2, reopens R1-16)"
pin "$EXECUTE" 'slice the budget guard stopped (`reason=budget`)' "exempts a budget stop from P2 (R2)"
pin "$EXECUTE" 'No correction is needed: the re-run writes a fresh' "a failed start check needs no hand edit (R2)"
pin "$EXECUTE" 'A `go` with `MODE=conservative` → print its `REASON`' "tells the human a conservative run stops after the slice (R2)"
pin "$PRIME" '`MODE=normal`, `VERDICT=stop` →' "warns when a run would not start (R2)"
pin "$DEBUG" '*Max attempts* counts again from 1 — a known limit' "states the debug-loop restart honestly (R2)"
for f in "$REPO_ROOT/templates/craft-profile.md.template" "$REPO_ROOT"/templates/profiles/*.md "$REPO_ROOT/craft-profile-defaults.md"; do
  grep -qF 'stops at the next sub-task boundary' "$f" && bad "$(basename "$f") still says the builder stops at a sub-task boundary only (R2)" || ok "$(basename "$f") describes every boundary of the spawn"
done
pin "$BUILDER" '`reason=budget — budget check failed:' "stops when its gate cannot judge (R1-17)"
pin "$BUILDER" 'reason=budget — <REASON>' "names the budget stop in its paused line"
pin "$BUILD" '`agents/slice-builder.md` → *The budget guard*' "points at the one definition"
pin "$DEBUG" '`agents/slice-builder.md` → *The budget guard*' "runs the guard before each attempt"
grep -qF -- 'usage-state.sh' "$BUILD" && bad "build.md restates the budget gate (a second definition)" || ok "build.md keeps no copy of the budget gate"
pin "$PRIME" '--gate before' "reports the budget in 4d"
pin "$PRIME" 'skip items 2 and 3, and go on with item 4' "reports the budget without a profile (R1-8)"
pin "$PRIME" 'no usage reading: <UNKNOWN>' "names the helper's UNKNOWN verbatim (R1-13)"
pin "$PRIME" 'when `UNKNOWN` starts with `no tap at`' "tells a missing tap from an old one (R1-18)"
# Every value the helper prints for VERDICT= has its own bullet in the budget guard (R1-6: a bare word was at HEAD).
expect "the helper's VERDICT values" "$(sed -n 's/^#   VERDICT=//p' "$HELPER")" "go|stop"
pin "$EXECUTE" '- **`go`** → the run goes on' "handles VERDICT=go in its own bullet"
pin "$EXECUTE" '- **A `stop`** → print and log' "handles VERDICT=stop in its own bullet"
# The profile copies of the limits are bound to the helper's DEFAULTS, both directions.
defaults="$(sed -n 's/^DEFAULTS = {\(.*\)}$/\1/p' "$HELPER" | tr -d '" ' | tr ',' '\n' | sort)"
[[ -n "$defaults" ]] && ok "the helper declares DEFAULTS" || bad "the helper's DEFAULTS line is gone"
for f in "$REPO_ROOT/templates/craft-profile.md.template" "$REPO_ROOT"/templates/profiles/*.md; do
  copy="$(awk '/^## Autopilot[[:space:]]*$/{on=1;next} /^## /{on=0} on' "$f" | sed -n 's/^- \*\*\(Budget-[a-z-]*\):\*\* \([0-9]*\)$/\1:\2/p' | sort)"
  expect "$(basename "$f"): the ## Autopilot block equals the helper's DEFAULTS" "$copy" "$defaults"
done
for kv in $defaults; do  # R1-5: the documented defaults are bound by value, not just by key
  pin "$REPO_ROOT/craft-profile-defaults.md" "| Autopilot | ${kv%%:*} | \`${kv#*:}\` |" "documents ${kv%%:*} = ${kv#*:}"
done
dv() { printf '%s\n' "$defaults" | sed -n "s/^$1://p"; }
pin "$REPO_ROOT/docs/index.html" "<strong><code>$(dv Budget-before-slice)</code></strong> / <strong><code>$(dv Budget-in-slice)</code></strong> / <strong><code>$(dv Budget-seven-day)</code></strong>" "states the helper's defaults in the config row"
for f in "$REPO_ROOT/README.md" "$REPO_ROOT/docs/index.html"; do
  grep -qE '(85|95|90)(&nbsp;| )%' "$f" && bad "$(basename "$f") repeats a budget limit in prose (unbound copy)" || ok "$(basename "$f") points at the profile block instead of repeating the limits"
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
