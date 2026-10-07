#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-autopilot-briefing.sh — self-contained tests for autopilot-briefing.sh (slice-069, roadmap B27): the
# autopilot's run-start briefing — "Stops for you at: …" included — is printed by a helper the master only
# relays at /craft:execute a1 and at the plan gate, never written from memory (slice-063's probe: the a1 block
# was printed but not bound).
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-autopilot-briefing.sh
#
# Fixtures are real git repositories (execute-resume-state.sh reads the branch and the tree). The harness
# writes nothing outside its own mktemp directory (removed on exit) and unsets an inherited
# CLAUDE_PROJECT_DIR — the real project's value would leak into every fixture run (slice-063's lesson).
#
# The second half pins the sites in commands/execute.md that run and relay the helper. Prose is not
# checkable, so those are phrase pins by name; whether the master relays the output unchanged stays a known
# limit (same as a5's digest) that only a real run shows.

set -uo pipefail
unset CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/autopilot-briefing.sh"
for f in "$HELPER" "$SCRIPT_DIR/execute-resume-state.sh" "$SCRIPT_DIR/epic-entry-link.sh" \
         "$SCRIPT_DIR/example-regions.sh" "$SCRIPT_DIR/tree-dirt-state.sh"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
EPIC=".claude/plans/epic-900-demo.md"

# --- fixtures -----------------------------------------------------------------------------------------------

EPIC_HEADING='# Epic 900 — Demo'
EPIC_FM='> Epic-ID: epic-900
> Epic-Slug: demo'

# fx <spec>… — a fresh git repository on the epic branch epic-900-demo. A spec is
#   <nnn>:<slug>:<state>[:<depends>]    state = landed | the plan's Status;  depends = slice-X,slice-Y
# and becomes a linked entry of the epic plan, in the order given, plus a plan (or an archive when landed).
# EPIC_HEADING / EPIC_FM override the heading and the frontmatter; "-" leaves an entry unlinked.
fx() {
  rm -rf "$P"
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
  local spec n slug state deps entries=""
  for spec in "$@"; do
    IFS=: read -r n slug state deps <<<"$spec"
    if [[ "$n" == "-" ]]; then
      entries+="- [ ] $slug — intent of $slug"$'\n'
      continue
    fi
    entries+="- [ ] slice-$n — $slug — intent of $slug"$'\n'
    if [[ "$state" == "landed" ]]; then
      printf '# Slice %s — %s\n\n> Completed: 2026-10-02\n\n## What\n\nx\n' "$n" "$slug" > "$P/.claude/project/slices/slice-$n-$slug.md"
    else
      local dl="${deps//,/, }"
      printf '# Slice %s — %s\n\n> Status: %s\n> Slice-ID: slice-%s\n> Slice-Slug: %s\n> Depends-On: [%s]\n\n## Goal\n\ng\n' \
        "$n" "$slug" "$state" "$n" "$slug" "$dl" > "$P/.claude/plans/slice-$n-$slug.md"
    fi
  done
  printf '%s\n\n%s\n\n## Vision\n\nv\n\n## Slice Decomposition\n\n%s\n## Autopilot Log\n\n(none)\n' \
    "$EPIC_HEADING" "$EPIC_FM" "$entries" > "$P/$EPIC"
  git -C "$P" init -q -b main
  git -C "$P" config user.email t@example.com
  git -C "$P" config user.name t
  git -C "$P" config core.autocrlf false
  git -C "$P" add -A
  git -C "$P" commit -q -m init
  git -C "$P" checkout -q -b epic-900-demo
}

# run <args…> — stdout only; stderr and the exit code land in $ERR / $RC. Runs in the fixture, no project env.
run() {
  local o e
  e="$ROOT/stderr"
  o="$(cd "$P" && env -u CLAUDE_PROJECT_DIR bash "$HELPER" "$@" 2>"$e")"
  RC=$?
  ERR="$(cat "$e")"
  OUT="$o"
}
expect() { # <label> <actual> <wanted>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — got '$2', want '$3'"; fi
}
# expect_error <label> <exit> <reason> — a named error on stderr, nothing on stdout
expect_error() {
  if [[ "$RC" == "$2" && "$ERR" == *"ERROR=$3"* && -z "$OUT" ]]; then ok "$1"
  else bad "$1 — got exit $RC, stderr '$ERR', stdout '${OUT:0:80}'"; fi
}
# expect_block <label> <order-line-body> [trunk] [epic-id] [title] — the whole block, byte for byte
STOPS='   Stops for you at: Phase-5 checks that are refused or missing, a bug the autonomous debug loop could not fix, review
   ping-pong (a finding whose one autonomous loop-back did not hold, or the round cap), scope questions, blockers,
   failures, the usage budget (the limits in craft-profile.md → ## Autopilot; without a usage reading after every
   slice) — and at the end (with the UX demo script).'
block() { # <order-line-body> [trunk] [title]
  printf '▶ Autopilot run — epic-900 "%s"\n   Builds in place on epic-900-demo; %s is not touched until you say yes at the end.\n   This checkout is occupied: do not edit files or switch branches here until the run stops.\n   Order: %s\n%s\n   Stop:   Esc.   Resume after any stop:   /craft:execute epic-900 --autopilot' \
    "${3-Demo}" "${2-main}" "$1" "$STOPS"
}
expect_block() { # <label> <order-line-body> [trunk] [title]
  if [[ "$RC" == "0" && -z "$ERR" && "$OUT" == "$(block "$2" "${3-main}" "${4-Demo}")" ]]; then ok "$1"
  else
    bad "$1 — exit $RC, stderr '$ERR'; the block differs:"
    diff <(block "$2" "${3-main}" "${4-Demo}") <(printf '%s\n' "$OUT") | sed 's/^/        /'
  fi
}

echo "CASES:"

# 1. a fresh epic: the whole block, exactly
fx 901:alpha:planning 902:beta:planning 903:gamma:planning
run --trunk main "$EPIC"
expect_block "a fresh epic: the exact block" "slice-901 (build) → slice-902 (build) → slice-903 (build)"
expect "the Stops lines in the block are the table's, byte-equal" \
  "$(printf '%s\n' "$OUT" | sed -n '/^   Stops for you at:/,/^   slice) — and at the end/p')" "$STOPS"
expect "the block ends with the Esc / resume line, as one line" "$(printf '%s\n' "$OUT" | tail -n 1)" \
  "   Stop:   Esc.   Resume after any stop:   /craft:execute epic-900 --autopilot"

# 2. the trunk is the one passed, not main by assumption
run --trunk develop "$EPIC"
expect_block "--trunk names the trunk in line 2" "slice-901 (build) → slice-902 (build) → slice-903 (build)" develop

# 3. Depends-On reorders; ties keep decomposition order (902 first, then the freed 901 beats 903)
fx 901:alpha:planning:slice-902 902:beta:planning 903:gamma:planning
run --trunk main "$EPIC"
expect_block "Depends-On: the dependency first, ties in decomposition order" \
  "slice-902 (build) → slice-901 (build) → slice-903 (build)"
fx 901:alpha:planning:slice-903 902:beta:planning 903:gamma:planning:slice-902
run --trunk main "$EPIC"
expect_block "a chain 901 → 903 → 902 reads 902, 903, 901" "slice-902 (build) → slice-903 (build) → slice-901 (build)"
fx 901:alpha:planning:slice-902,slice-903 902:beta:planning 903:gamma:planning
run --trunk main "$EPIC"
expect_block "two dependencies: both first, in decomposition order" "slice-902 (build) → slice-903 (build) → slice-901 (build)"

# 4. a dependency on a landed slice counts as met; the landed part appears in decomposition order
fx 901:alpha:planning:slice-902 902:beta:landed 903:gamma:planning
run --trunk main "$EPIC"
expect_block "a landed dependency is met and shown under [landed: …]" "slice-901 (build) → slice-903 (build)   [landed: slice-902]"
fx 901:alpha:landed 902:beta:landed 903:gamma:planning
run --trunk main "$EPIC"
expect_block "two landed: listed in decomposition order" "slice-903 (build)   [landed: slice-901, slice-902]"
fx 901:alpha:landed 902:beta:landed 903:gamma:landed
run --trunk main "$EPIC"
expect_block "everything landed: no order to print" "(nothing left to build)   [landed: slice-901, slice-902, slice-903]"

# 5. no [landed: …] part when nothing has landed (case 1) — and a dependency outside the epic changes nothing
fx 901:alpha:planning:slice-999 902:beta:planning
run --trunk main "$EPIC"
expect_block "a dependency outside the epic does not affect the order" "slice-901 (build) → slice-902 (build)"

# 5b. a dependency on the slice in flight does not move it: the resume slice comes first anyway
fx 901:alpha:planning 902:beta:implementing:slice-901 903:gamma:planning
run --trunk main "$EPIC"
expect_block "a resume slice comes first, whatever its place and its Depends-On" \
  "slice-902 (resume at implementing) → slice-901 (build) → slice-903 (build)"
fx 901:alpha:committing 902:beta:planning
run --trunk main "$EPIC"
expect_block "resume at committing" "slice-901 (resume at committing) → slice-902 (build)"
fx 901:alpha:landed 902:beta:testing 903:gamma:planning:slice-902
run --trunk main "$EPIC"
expect_block "resume with a landed slice and a slice that depends on it" \
  "slice-902 (resume at testing) → slice-903 (build)   [landed: slice-901]"

# 6. a held slice stays in the order, marked
fx 901:alpha:planning:slice-902 902:beta:paused 903:gamma:planning
run --trunk main "$EPIC"
expect_block "a paused slice is held, in topological place" \
  "slice-902 (held at paused) → slice-901 (build) → slice-903 (build)"
fx 901:alpha:blocked 902:beta:planning
run --trunk main "$EPIC"
expect_block "a blocked slice is held" "slice-901 (held at blocked) → slice-902 (build)"

# 7. the title: after the first ' — ' of the first '# ' heading; without one, the whole heading
EPIC_HEADING='# Epic 900 — Demo — and more'; fx 901:alpha:planning
run --trunk main "$EPIC"
expect_block "the title is everything after the FIRST ' — '" "slice-901 (build)" main "Demo — and more"
EPIC_HEADING='# Plain Demo Epic'; fx 901:alpha:planning
run --trunk main "$EPIC"
expect_block "a heading without ' — ' is the whole title" "slice-901 (build)" main "Plain Demo Epic"
EPIC_HEADING='# Epic 900 — Demo'

# 7b. an example region is no content: a multi-line HTML comment above the heading holds a decoy heading and a decoy
#     frontmatter key, and neither is read (example-regions.sh decides what is an example)
fx 901:alpha:planning
{ printf '<!--\n# Decoy — Wrong Title\n> Epic-ID: epic-111\n-->\n'; cat "$P/$EPIC"; } > "$P/$EPIC.new" && mv "$P/$EPIC.new" "$P/$EPIC"
run --trunk main "$EPIC"
expect_block "a decoy heading and Epic-ID inside an HTML comment are not read" "slice-901 (build)"

# 8. CRLF files read the same; the output has LF line ends and no CR
fx 901:alpha:planning:slice-902 902:beta:planning
for f in "$P/$EPIC" "$P"/.claude/plans/slice-90*.md; do sed 's/$/\r/' "$f" > "$f.crlf" && mv "$f.crlf" "$f"; done
git -C "$P" add -A >/dev/null 2>&1; git -C "$P" commit -q -m crlf >/dev/null 2>&1
run --trunk main "$EPIC"
expect_block "CRLF epic plan and slice plans give the same block" "slice-902 (build) → slice-901 (build)"
expect "no CR in the output" "$(printf '%s' "$OUT" | grep -c $'\r')" "0"

# 9. the project dir: CLAUDE_PROJECT_DIR is honored from another cwd
fx 901:alpha:planning
OUT="$(cd "$ROOT" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" --trunk main "$EPIC" 2>"$ROOT/stderr")"; RC=$?; ERR="$(cat "$ROOT/stderr")"
expect_block "CLAUDE_PROJECT_DIR is the project, whatever the cwd" "slice-901 (build)"

# 10. errors are named, exit non-zero, and print nothing on stdout — never a partial block
fx 901:alpha:planning 902:beta:planning
run
expect_error "no argument → usage" 2 "usage"
run "$EPIC"
expect_error "no --trunk → usage" 2 "usage"
run "$EPIC" --trunk
expect_error "--trunk without a value → usage" 2 "usage"
run --trunk main
expect_error "no epic plan argument → usage" 2 "usage"
run --trunk main "$EPIC" extra
expect_error "a second positional argument → usage" 2 "usage"
run --trunk main --bogus "$EPIC"
expect_error "an unknown option → usage" 2 "usage"
OUT="$(cd "$ROOT" && CLAUDE_PROJECT_DIR="$ROOT/absent" bash "$HELPER" --trunk main "$EPIC" 2>"$ROOT/stderr")"; RC=$?; ERR="$(cat "$ROOT/stderr")"
expect_error "an unreachable project dir" 3 "project_dir_unreachable"
run --trunk main ".claude/plans/epic-999-absent.md"
expect_error "an unreadable epic plan" 4 "epic_plan_unreadable"
EPIC_FM='> Epic-Slug: demo'; fx 901:alpha:planning
run --trunk main "$EPIC"
expect_error "no Epic-ID in the frontmatter" 4 "epic_frontmatter:Epic-ID"
EPIC_FM='> Epic-ID: epic-900'; fx 901:alpha:planning
run --trunk main "$EPIC"
expect_error "no Epic-Slug in the frontmatter" 4 "epic_frontmatter:Epic-Slug"
EPIC_FM='> Epic-ID: epic-900
> Epic-Slug: demo'
EPIC_HEADING='Epic 900 without a heading mark'; fx 901:alpha:planning
run --trunk main "$EPIC"
expect_error "no '# ' heading → no title" 4 "epic_title_missing"
EPIC_HEADING='# Epic 900 — Demo'
fx 901:alpha:planning -:unlinked-entry:planning
run --trunk main "$EPIC"
expect_error "an unlinked entry → the resume helper's refusal, named" 5 "resume_state_failed:slices_from:unresolved:unlinked-entry:unlinked"
fx 901:alpha:implementing 902:beta:reviewing
run --trunk main "$EPIC"
expect_error "two slices in flight → RESULT=conflict, named" 5 "resume_conflict:slice-901:multiple_open"
fx 901:alpha:planning 902:beta:planning
echo stray > "$P/stray.txt"
run --trunk main "$EPIC"
expect_error "a dirty tree with no slice in flight → RESULT=conflict, named" 5 "resume_conflict:dirty_without_open_slice"
fx 901:alpha:planning 902:beta:planning
git -C "$P" checkout -q main
run --trunk main "$EPIC"
expect_error "the checkout is not on the epic branch → conflict, named" 5 "resume_conflict:wrong_branch"
fx 901:alpha:planning:slice-902 902:beta:planning:slice-901 903:gamma:planning
run --trunk main "$EPIC"
expect_error "a Depends-On cycle, with its members" 6 "depends_on_cycle:slice-901,slice-902"
fx 901:alpha:planning:slice-901
run --trunk main "$EPIC"
expect_error "a slice that depends on itself is a cycle" 6 "depends_on_cycle:slice-901"
# a plan that is not UTF-8 text is a named error, never a traceback
fx 901:alpha:planning 902:beta:planning
printf 'caf\xe9\n' >> "$P/.claude/plans/slice-902-beta.md"
git -C "$P" add -A; git -C "$P" commit -q -m latin1
run --trunk main "$EPIC"
expect_error "a slice plan that is not UTF-8 → plan_unreadable, named" 4 "plan_unreadable:"
# the cycle check runs on the open slices only: a landed slice's archive has no Depends-On to read
fx 901:alpha:landed 902:beta:planning:slice-901
run --trunk main "$EPIC"
expect_block "a landed slice cannot be in a cycle" "slice-902 (build)   [landed: slice-901]"

# a missing helper: a copy of the script next to every helper but one
mkdir -p "$ROOT/lone"
cp "$HELPER" "$SCRIPT_DIR/epic-entry-link.sh" "$SCRIPT_DIR/example-regions.sh" "$ROOT/lone/"
fx 901:alpha:planning
OUT="$(cd "$P" && env -u CLAUDE_PROJECT_DIR bash "$ROOT/lone/autopilot-briefing.sh" --trunk main "$EPIC" 2>"$ROOT/stderr")"; RC=$?; ERR="$(cat "$ROOT/stderr")"
expect_error "a helper missing next to the script" 4 "helper_missing:execute-resume-state.sh"
# python3 missing: an empty PATH leaves only builtins, which is all the helper uses before that check
mkdir -p "$ROOT/emptybin"
OUT="$(cd "$P" && PATH="$ROOT/emptybin" "$BASH" "$HELPER" --trunk main "$EPIC" 2>"$ROOT/stderr")"; RC=$?; ERR="$(cat "$ROOT/stderr")"
expect_error "python3 missing" 4 "helper_missing:python3"

# 11. read-only: the plans byte-equal and git status unchanged after a run
fx 901:alpha:planning:slice-902 902:beta:implementing 903:gamma:landed
before_plans="$(cd "$P" && cat "$EPIC" .claude/plans/slice-*.md | cksum)"
before_status="$(git -C "$P" status --porcelain)"
before_head="$(git -C "$P" rev-parse HEAD)"
run --trunk main "$EPIC"
after_plans="$(cd "$P" && cat "$EPIC" .claude/plans/slice-*.md | cksum)"
expect "read-only: the plans are byte-equal after a run" "$after_plans" "$before_plans"
expect "read-only: git status is unchanged" "$(git -C "$P" status --porcelain)" "$before_status"
expect "read-only: HEAD is unchanged" "$(git -C "$P" rev-parse HEAD)" "$before_head"
expect "read-only: no stray file in the project" "$(ls -A "$P/.claude/plans" | tr '\n' ' ')" "epic-900-demo.md slice-901-alpha.md slice-902-beta.md "

# --- pins on commands/execute.md ----------------------------------------------------------------------------
# What the master must relay is checked by name: a phrase at the site that runs the helper. A mere mention
# elsewhere in the file never counts, because each pin reads one section.

EXEC="$REPO/commands/execute.md"
[[ -f "$EXEC" ]] || { echo "FATAL: not found: $EXEC" >&2; exit 2; }
section() { # <start-regex> <end-regex> — the lines from the first start match up to (not including) the next end match
  awk -v s="$1" -v e="$2" '
    !on && $0 ~ s { on = 1; print; next }
    on && $0 ~ e { exit }
    on { print }' "$EXEC"
}
pin() { # <label> <section-text> <fixed phrase>
  if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 — not found: $3"; fi
}
pin_absent() { # <label> <section-text> <fixed phrase>
  if grep -qF -- "$3" <<<"$2"; then bad "$1 — still there: $3"; else ok "$1"; fi
}

echo
echo "execute.md PINS:"
A1="$(section '^### a1 — ' '^### a2 — ')"
[[ -n "$A1" ]] && ok "a1 section found" || bad "a1 section not found"
pin "a1 runs the helper" "$A1" 'scripts/autopilot-briefing.sh'
pin "a1 prints its stdout unchanged" "$A1" 'unchanged'
pin "a1 names the failure stop" "$A1" '⛔ · <epic-id> · briefing failed: <reason>'
pin "a1 releases the lock on a failed briefing" "$A1" 'release the lock'
pin "a1 does not log run started on a failed briefing" "$A1" '`run started` is not logged'
pin "a1 still logs run started after the relay" "$A1" '▶ · <epic-id> · run started'
pin_absent "a1 has no 'only the order line' rule any more" "$A1" 'only the order line'

AP5="$(section '^5[.] [*][*]The gate[*][*]' '^The master judges none of the plans')"
[[ -n "$AP5" ]] && ok "ap step 5 section found" || bad "ap step 5 section not found"
pin "ap step 5 runs the helper" "$AP5" 'scripts/autopilot-briefing.sh'
pin "ap step 5 relays its stdout unchanged" "$AP5" 'unchanged'
pin "ap step 5 names the ⚠ line for a helper error" "$AP5" '⚠ run briefing not generated: <ERROR=>'
pin "ap step 5 does not stop on the error" "$AP5" 'no stop'

S1="$(section '^### s1 — ' '^### s2 — ')"
[[ -n "$S1" ]] && ok "s1 section found" || bad "s1 section not found"
pin "s1 names the decomposition-order tie-break" "$S1" 'keep decomposition order'
pin "s1 ties it to the briefing's order" "$S1" 'the order the briefing prints'

OFB="$(section '^Autopilot — briefing [(]a1[)]:' '^Autopilot — stopped [(]a2[)]:')"
[[ -n "$OFB" ]] && ok "Output Format briefing section found" || bad "Output Format briefing section not found"
pin "the Output Format points to the helper" "$OFB" 'scripts/autopilot-briefing.sh'
pin "the Output Format relays unchanged" "$OFB" 'unchanged'
pin_absent "the Output Format no longer restates the block" "$OFB" 'Builds in place on'

GATE="$(section '^Autopilot — plan gate [(]ap[)]:' '^Autopilot — briefing [(]a1[)]:')"
[[ -n "$GATE" ]] && ok "Output Format plan gate section found" || bad "Output Format plan gate section not found"
pin "the plan gate's 'How the run will go' points to the helper" "$(grep -F 'How the run will go:' <<<"$GATE")" 'autopilot-briefing.sh'

if grep -qF 'Stops for you at:' "$EXEC"; then bad "execute.md carries a 'Stops for you at:' line — its content is defined once, in the helper"
else ok "execute.md carries no 'Stops for you at:' line (defined once, in the helper)"; fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
