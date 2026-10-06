#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-autopilot-log.sh — self-contained tests for autopilot-log.sh (slice-063, roadmap B23): every line of an
# epic plan's `## Autopilot Log` is written by a helper that reads the clock itself and places the line, and a
# slice step cannot be logged in an invocation that has not logged `run started` (a1). slice-049 and slice-057's
# probe 1 showed the master stamping a log line with a time it did not read off the clock; slice-056's probe 3 a
# re-run that skipped a1's briefing.
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-autopilot-log.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/autopilot-log.sh"
for f in "$HELPER" "$SCRIPT_DIR/example-regions.sh"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
EPIC=".claude/plans/epic-900-demo.md"
LOCK="$P/.claude/plans/.execute.lock"
T0="2026-10-06T10:00:00Z"

NOTE='> Appended by `/craft:execute <epic> --autopilot`, one line per event. Never rewritten.'

reset() {
  rm -rf "$P"
  mkdir -p "$P/.claude/plans"
}

# epic [<log-section-body>] — the epic plan; "-" leaves the `## Autopilot Log` section out
epic() {
  local body="${1-$NOTE

(no autopilot run yet)}" log=""
  [[ "$body" == "-" ]] || log="## Autopilot Log

$body

"
  printf '# Epic 900 — Demo\n\n> Status: planning\n> Epic-ID: epic-900\n> Epic-Slug: demo\n\n## Vision\n\nv\n\n%s## Recap Draft\n\n(not yet recorded)\n' \
    "$log" > "$P/$EPIC"
}

# lock <state> [<target>] [<since>] — the execute lock as execute-lock.sh writes it
lock() {
  printf 'STATE=%s\nTARGET=%s\nOWNER_PID=1\nOWNER_START=\nSESSION=-\nSINCE=%s\n' "$1" "${2:-epic-900}" "${3:-$T0}" > "$LOCK"
}

# run <now|-> <args…> — "-" reads the real clock; stdout / stderr / exit land in $OUT / $ERR / $RC
run() {
  local now="$1" e="$ROOT/stderr"
  shift
  if [[ "$now" == "-" ]]; then
    OUT="$(cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" "$@" 2>"$e")"
  else
    OUT="$(cd "$P" && CLAUDE_PROJECT_DIR="$P" CRAFT_LOG_TEST_NOW="$now" bash "$HELPER" "$@" 2>"$e")"
  fi
  RC=$?
  ERR="$(cat "$e")"
}
expect() { # <label> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — got '$2', want '$3'"; fi
}
# expect_error <label> <exit> <reason> — a named error on stderr, nothing on stdout
expect_error() {
  if [[ "$RC" == "$2" && "$ERR" == *"ERROR=$3"* && -z "$OUT" ]]; then ok "$1"
  else bad "$1 — got exit $RC, stderr '$ERR', stdout '${OUT:0:80}'"; fi
}
# unchanged <label> <copy> — the epic plan is byte-equal to the copy taken before the call
unchanged() {
  if cmp -s "$2" "$P/$EPIC"; then ok "$1"; else bad "$1 — the epic plan changed"; fi
}
snap() { cp "$P/$EPIC" "$ROOT/before"; }
# the `## Autopilot Log` section's lines, heading excluded, up to the next `## ` heading
section() { awk '$0 == "## Autopilot Log" { f = 1; next } f && /^##? / { exit } f' "$P/$EPIC"; }

echo "CASES:"

# 1. the first line: the placeholder dropped, the note kept, one blank line around the log line, the line the
#    helper prints is the line it wrote, and its datetime is the clock's
reset; epic
run "$T0" append "$EPIC" ▶ epic-900 "run started"
expect "exit 0 on a plain append" "$RC" "0"
expect "the printed line is the written one" "$OUT" "LINE=- $T0 · ▶ · epic-900 · run started"
expect "nothing on stderr on success" "$ERR" ""
want="
$NOTE

- $T0 · ▶ · epic-900 · run started"
expect "the placeholder is dropped and the line sits in the section" "$(section)" "$want"
expect "one blank line, then the next heading" "$(grep -B 2 '^## Recap Draft$' "$P/$EPIC")" "- $T0 · ▶ · epic-900 · run started

## Recap Draft"

# 2. a second line goes directly below the last log line — the section's last line, above the blank and the next heading
run "2026-10-06T10:00:07Z" append "$EPIC" ⛔ slice-901 "stopped: review — answer the finding"
want="
$NOTE

- $T0 · ▶ · epic-900 · run started
- 2026-10-06T10:00:07Z · ⛔ · slice-901 · stopped: review — answer the finding"
expect "a second line is the section's new last line" "$(section)" "$want"
expect "the written line is in the file exactly once" "$(grep -cFx -- "${OUT#LINE=}" "$P/$EPIC")" "1"

# 3. everything outside the section is byte-equal
reset; epic
cp "$P/$EPIC" "$ROOT/orig"
run "$T0" append "$EPIC" ■ epic-900 "complete, not merged"
diff <(grep -v -x -e "- $T0 · ■ · epic-900 · complete, not merged" "$P/$EPIC" | cat -s) \
     <(grep -v -x -e '(no autopilot run yet)' "$ROOT/orig" | cat -s) >/dev/null \
  && ok "only the placeholder went and the line came — every other byte as it was" \
  || bad "lines outside the log line and the placeholder changed"

# 4. a section missing: inserted directly above ## Recap Draft
reset; epic "-"
run "$T0" append "$EPIC" ▶ epic-900 "run started"
expect "exit 0 when the section is missing" "$RC" "0"
expect "the section is inserted above ## Recap Draft" \
  "$(grep -n -e '^## Autopilot Log$' -e '^## Recap Draft$' -e "^- $T0" "$P/$EPIC" | cut -d: -f2-)" \
  "## Autopilot Log
- $T0 · ▶ · epic-900 · run started
## Recap Draft"
expect "the inserted section holds only the line" "$(section)" "
- $T0 · ▶ · epic-900 · run started"

# 5. a section missing and no ## Recap Draft: appended at the end of the file
reset; printf '# Epic 900 — Demo\n\n> Epic-ID: epic-900\n\n## Vision\n\nv\n' > "$P/$EPIC"
run "$T0" append "$EPIC" ▶ epic-900 "run started"
expect "the section goes to the end of the file" "$(tail -n 3 "$P/$EPIC")" "## Autopilot Log

- $T0 · ▶ · epic-900 · run started"
expect "the file still ends with a newline" "$(tail -c 1 "$P/$EPIC" | od -An -c | tr -d ' ')" '\n'

# 6. the section is the file's last, and the file has no final newline
reset; printf '# Epic 900 — Demo\n\n> Epic-ID: epic-900\n\n## Autopilot Log\n\n- %s · ▶ · epic-900 · run started' "$T0" > "$P/$EPIC"
run "2026-10-06T10:01:00Z" append "$EPIC" ✓ epic-900 "plan gate approved: slice-901"
expect "a last section without a final newline gets the line below its last" "$(tail -n 2 "$P/$EPIC")" \
  "- $T0 · ▶ · epic-900 · run started
- 2026-10-06T10:01:00Z · ✓ · epic-900 · plan gate approved: slice-901"

# 7. CRLF: the new line is written CRLF too, no other line changes
reset; epic "$NOTE

- $T0 · ▶ · epic-900 · run started"
sed 's/$/\r/' "$P/$EPIC" > "$ROOT/crlf" && cp "$ROOT/crlf" "$P/$EPIC"
run "2026-10-06T10:02:00Z" append "$EPIC" ▶ epic-900 "plan gate shown: slice-901"
expect "exit 0 on a CRLF plan" "$RC" "0"
expect "every line still ends in CR" "$(grep -vc $'\r$' "$P/$EPIC")" "0"
expect "the CRLF line landed below the last log line" "$(tr -d '\r' < "$P/$EPIC" | grep -n '^- ' | cut -d: -f2-)" \
  "- $T0 · ▶ · epic-900 · run started
- 2026-10-06T10:02:00Z · ▶ · epic-900 · plan gate shown: slice-901"
expect "the printed line carries no CR" "$(printf '%s' "$OUT" | grep -c $'\r')" "0"

# 8. a `## Autopilot Log` inside a fence is an example, not the section
reset; epic
perl -0pi -e 's/\n\nv\n/\n\n```\n## Autopilot Log\n\n- decoy\n```\n/' "$P/$EPIC"
run "$T0" append "$EPIC" ▶ epic-900 "run started"
expect "the fenced decoy is untouched" "$(sed -n '/^```$/,/^```$/p' "$P/$EPIC" | tr '\n' '|')" '```|## Autopilot Log||- decoy|```|'
expect "the line went into the real section" "$(section | tail -n 2 | head -n 1)" "- $T0 · ▶ · epic-900 · run started"

# 9. the real clock: an ISO UTC datetime no earlier than before the call and no later than after it
reset; epic
before="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run - append "$EPIC" ▶ epic-900 "run started"
after="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
dt="$(sed -n 's/^LINE=- \([^ ]*\) · .*/\1/p' <<<"$OUT")"
if [[ "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && ! "$dt" < "$before" && ! "$dt" > "$after" ]]; then
  ok "the datetime is the clock's ($dt)"
else bad "the datetime '$dt' is not the clock's ($before .. $after)"; fi

# 10. the gate (a1): a slice step needs a `run started` of this epic at or after the lock's SINCE
STEP_TEXT='slice 1/2 "Alpha" — create · five_hour 10 % until 14:00'
reset; epic; snap
run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a slice start with no lock is refused" 5 "gate:no_lock"
unchanged "  … and nothing is written" "$ROOT/before"
lock released; run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a slice start under a released lock is refused" 5 "gate:lock_released"
lock held epic-777; run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a slice start under another target's lock is refused" 5 "gate:lock_target:epic-777"
printf 'garbage\n' > "$LOCK"; run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a slice start under an unreadable lock is refused" 5 "gate:lock_unreadable"
lock held; run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a slice start with no run started is refused" 5 "gate:no_run_started"
unchanged "  … and nothing is written" "$ROOT/before"

reset; epic "$NOTE

- 2026-10-06T09:59:59Z · ▶ · epic-900 · run started"; lock held; snap
run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a run started before the lock's SINCE (an earlier invocation) does not count" 5 "gate:no_run_started"
unchanged "  … and nothing is written" "$ROOT/before"
run "$T0" append "$EPIC" ✓ slice-901 "landed on epic-900-demo (a..b) · Phase 5 by you ([W]) · Δ five_hour +3 %"
expect_error "a landed line is a slice step too" 5 "gate:no_run_started"

reset; epic "$NOTE

- $T0 · ▶ · epic-900 · run started"; lock held
run "2026-10-06T10:00:30Z" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect "a run started at the lock's SINCE counts" "$RC" "0"
reset; epic "$NOTE

- 2026-10-06T10:00:05Z · ▶ · epic-900 · run started"; lock held
run "2026-10-06T10:00:30Z" append "$EPIC" ✓ slice-901 "landed on epic-900-demo (a..b) · Phase 5 by you ([W]) · Δ five_hour +3 %"
expect "a run started after the lock's SINCE counts" "$RC" "0"

reset; epic "$NOTE

- 2026-10-06T10:00:05Z · ▶ · epic-901 · run started"; lock held; snap
run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "another epic's run started does not count" 5 "gate:no_run_started"
reset; epic "$NOTE

- 2026-10-06T10:00:05Z · ▶ · epic-900 · run started again"; lock held
run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a line that only begins like run started does not count" 5 "gate:no_run_started"
reset; epic; lock held
perl -0pi -e "s/\n\nv\n/\n\n- 2026-10-06T10:00:05Z · ▶ · epic-900 · run started\n\n\`\`\`\n- 2026-10-06T10:00:05Z · ▶ · epic-900 · run started\n\`\`\`\n/" "$P/$EPIC"
run "$T0" append "$EPIC" ▶ slice-901 "$STEP_TEXT"
expect_error "a run started outside the section or in a fence does not count" 5 "gate:no_run_started"

# what the gate lets through without a run started: ap's planned line, every ⛔ line, every epic line
reset; epic
run "$T0" append "$EPIC" ▶ slice-901 "planned from entry alpha"
expect "ap's 'planned from entry' line needs no run started (ap runs before a1)" "$RC" "0"
run "$T0" append "$EPIC" ⛔ slice-901 "stopped: held at paused — answer the pause note"
expect "a ⛔ slice line needs no run started (s1's held stop can come before a1)" "$RC" "0"
run "$T0" append "$EPIC" ▶ epic-900 "plan gate shown: slice-901"
expect "an epic line needs no lock" "$RC" "0"

# 11. arguments are checked before anything is read or written
reset; epic; snap
run "$T0" append "$EPIC" ▶ epic-900
expect_error "too few arguments → usage" 2 "usage"
run "$T0" write "$EPIC" ▶ epic-900 "x"
expect_error "an unknown subcommand → usage" 2 "usage"
run "$T0" append "$EPIC" '*' epic-900 "x"
expect_error "a glyph outside ▶ ✓ ⛔ ■" 2 "glyph"
run "$T0" append "$EPIC" ▶ slice-9 "x"
expect_error "an ID that is no slice- or epic-ID" 2 "id"
run "$T0" append "$EPIC" ▶ epic-900 ""
expect_error "an empty text" 2 "text"
run "$T0" append "$EPIC" ▶ epic-900 $'two\nlines'
expect_error "a text with a newline" 2 "text"
run "$T0" append "$EPIC" ▶ epic-900 $'cr\r'
expect_error "a text with a carriage return" 2 "text"
run "$T0" append "$EPIC" ▶ epic-901 "run started"
expect_error "an epic-ID other than the plan's" 2 "id_mismatch:epic-900"
unchanged "  … and no refused call wrote anything" "$ROOT/before"
run "not-a-date" append "$EPIC" ▶ epic-900 "x"
expect_error "a test clock that is no ISO datetime" 2 "test_now"

# 12. the plan itself
reset
run "$T0" append ".claude/plans/epic-999-absent.md" ▶ epic-900 "x"
expect_error "an unreadable epic plan" 4 "epic_plan_unreadable"
reset; printf '# Epic 900\n\n## Autopilot Log\n\n(no autopilot run yet)\n' > "$P/$EPIC"; snap
run "$T0" append "$EPIC" ▶ epic-900 "run started"
expect_error "an epic plan without Epic-ID" 4 "epic_frontmatter:Epic-ID"
unchanged "  … and nothing is written" "$ROOT/before"
if [[ "$(id -u)" != "0" ]]; then
  reset; epic; chmod 444 "$P/$EPIC"; snap
  run "$T0" append "$EPIC" ▶ epic-900 "run started"
  expect_error "a read-only epic plan is refused, never written around" 6 "epic_plan_unwritable:read_only"
  unchanged "  … and nothing is written" "$ROOT/before"
  chmod 644 "$P/$EPIC"
fi
# the two write failures after the -w check (review R1-6) — the paths that replace a5's former grep checks (BUG-1).
# PATH shims make them reachable: a `cmp` that always differs (the copy did not check out), a `grep` whose exact-line
# count reads 0 (the line did not land); every other grep call passes through to the real one.
mkdir -p "$ROOT/shim-cmp" "$ROOT/shim-grep"
printf '#!/bin/sh\nexit 1\n' > "$ROOT/shim-cmp/cmp"
printf '#!/bin/sh\ncase " $* " in *" -cFx "*) echo 0; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v grep)" > "$ROOT/shim-grep/grep"
chmod +x "$ROOT/shim-cmp/cmp" "$ROOT/shim-grep/grep"
shimrun() { # <shim> <args…> — like run, with one shim first on PATH
  local d="$ROOT/shim-$1" e="$ROOT/stderr"; shift
  OUT="$(cd "$P" && PATH="$d:$PATH" CLAUDE_PROJECT_DIR="$P" CRAFT_LOG_TEST_NOW="$T0" bash "$HELPER" "$@" 2>"$e")"
  RC=$?; ERR="$(cat "$e")"
}
reset; epic
shimrun cmp append "$EPIC" ■ epic-900 "complete, not merged"
expect_error "a copy that does not check out → copy_failed" 6 "epic_plan_unwritable:copy_failed:"
kept="$(sed -n 's/.*copy_failed://p' <<<"$ERR")"
if [[ -f "$kept" ]] && grep -qFx -- "- $T0 · ■ · epic-900 · complete, not merged" "$kept"; then
  ok "  … the named file keeps the complete new content"
else bad "  … the file copy_failed names ('$kept') does not hold the new content"; fi
reset; epic
shimrun grep append "$EPIC" ■ epic-900 "complete, not merged"
expect_error "a line the re-read does not find → not_landed, nothing printed" 6 "not_landed"

reset; epic
OUT="$(cd "$ROOT" && CLAUDE_PROJECT_DIR="$ROOT/nope" bash "$HELPER" append "$EPIC" ▶ epic-900 x 2>"$ROOT/stderr")"; RC=$?; ERR="$(cat "$ROOT/stderr")"
expect_error "an unreachable project dir" 3 "project_dir_unreachable"

# 13. the master never stamps a line itself: commands/execute.md names the helper, no hand-written datetime format,
#     and never the test clock
EX="$REPO/commands/execute.md"
if [[ -f "$EX" ]]; then
  grep -q 'scripts/autopilot-log.sh" append' "$EX" && ok "execute.md writes the log through autopilot-log.sh" \
    || bad "execute.md does not call autopilot-log.sh append"
  n="$(grep -c 'date -u +%Y' "$EX")"
  expect "execute.md carries no datetime command of its own (the helper reads the clock)" "$n" "0"
  n="$(grep -c 'CRAFT_LOG_TEST_NOW' "$EX")"
  expect "execute.md never names the test clock" "$n" "0"
  n="$(grep -cE '`- <(ISO )?datetime> · ' "$EX")"
  expect "execute.md spells no log line with a datetime field (the helper's header defines the format)" "$n" "0"
  # a1 (B23 #1): the gate's refusal sends the master back to a1 — named in a1 and in the log section
  a1="$(awk '/^### a1 /{f=1; next} f && /^### /{exit} f' "$EX")"
  [[ "$a1" == *'**Every invocation, a re-run included**'* && "$a1" == *'ERROR=gate:no_run_started'* \
     && "$a1" == *'emit the briefing,'* ]] \
    && ok "a1 says the log helper refuses a slice step until this invocation's run started, and what a refusal means" \
    || bad "a1 does not name the log gate — a re-run could skip the briefing unnoticed (slice-056 probe 3)"
  log="$(awk '/^### The Autopilot Log/{f=1; next} f && /^### /{exit} f' "$EX")"
  [[ "$log" == *'**`ERROR=gate:no_run_started`** → a1 was skipped in this invocation: run a1 now'* ]] \
    && ok "the log section routes a gate refusal back to a1" || bad "the log section does not route a gate refusal to a1"
  # keyed on the missing LINE=, not on an exit code: a denied call has none (slice-057 BUG-1, review R1-4); the remedy
  # depends on the line's kind — a released lock refuses a slice step again (review R1-1)
  [[ "$log" == *'**No `LINE=` line** — any other non-zero exit, a call the permission check denied'* \
     && "$log" == *'not logged: <ERROR=, or a one-line cause>'* && "$log" == *"a3's \`✓\` line → it is lost"* \
     && "$log" == *'After `ERROR=not_landed`'* ]] \
    && ok "the log section stops the run when no LINE= came back, with a remedy per line kind" \
    || bad "the log section leaves a failed log write unhandled"
  # B23 #2: the master's files have one home inside the project
  own="$(awk '/^### The master.s own files/{f=1; next} f && /^### /{exit} f' "$EX")"
  [[ "$own" == *'goes to `.craft/tmp/` in the project root'* && "$own" == *'Never `/tmp`, `$TMPDIR` or another path outside the project'* ]] \
    && ok "execute.md names .craft/tmp/ as the master's only place for its own files, never /tmp" \
    || bad "execute.md does not name the master's scratch place (slice-056 probe 3 wrote to /tmp)"
else
  bad "commands/execute.md not found"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
