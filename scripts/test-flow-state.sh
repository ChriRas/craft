#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-flow-state.sh — self-contained tests for flow-state.sh (slice-074, D42): the auto slice flow's one
# verdict. At the end of an interactive phase command the agent asks the helper what comes next and acts on
# NEXT= / STOP= only; this harness is the contract the helper is judged by.
#
# The case table was written before the helper. Run it directly:
#
#   bash scripts/test-flow-state.sh
#
# Covers: every plan status x both modes, the defaults (no profile / no block / no key -> auto), invalid values
# (doubt means stop), the block boundary (`Execution -> Mode` is not `Slice Flow -> Mode`), CRLF, a missing or
# malformed plan, `--from` (a phase that ended where it started does not chain), `--mode`, `--map`, exactly one of
# NEXT= / STOP= on every verdict — and the pins: the sites that carry the rule (the phase commands, the workflow
# skill, plan.md, prime, onboard, the profile surface).
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/flow-state.sh"
REGIONS="$SCRIPT_DIR/example-regions.sh"

[[ -f "$HELPER" ]] || { echo "FATAL: not found: $HELPER" >&2; exit 2; }
[[ -f "$REGIONS" ]] || { echo "FATAL: not found: $REGIONS" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
P="$ROOT/proj"
PLAN="$P/.claude/plans/slice-900-demo.md"
PROFILE="$P/.claude/project/craft-profile.md"

reset() {
  rm -rf "$P"
  mkdir -p "$P/.claude/plans" "$P/.claude/project"
}

# plan <status> — a plan with the status in its frontmatter and a decoy `> Status:` line in the body
plan() {
  printf '# Slice 900 — Demo\n\n> Status: %s\n> Slice-ID: slice-900\n> Phase: 4\n\n## Goal\n\ng\n\n## Decisions Made During This Slice\n\n> Status: committing\n\n- x\n' \
    "$1" > "$PLAN"
}

# profile <flow-block-body> — a profile whose Execution block also carries a `- **Mode:**` key
profile() {
  printf '# CRAFT Profile\n\n> Preset: balanced\n\n## Execution\n\n- **Mode:** worktree\n\n## Slice Flow\n\n%s\n\n## Autopilot\n\n- **Budget-before-slice:** 85\n' \
    "$1" > "$PROFILE"
}

OUT=""
RC=0
run() { OUT="$("${BASH:-bash}" "$HELPER" "$@" 2>/dev/null)"; RC=$?; }
val() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | tail -n 1; }
has() { printf '%s\n' "$OUT" | grep -q "^$1=" ; }
count() { printf '%s\n' "$OUT" | grep -c "^$1=" ; }

# verdict <label> <expected NEXT=|STOP= value, as "NEXT=/craft:x" or "STOP=y"> <args...>
verdict() {
  local label="$1" want="$2"; shift 2
  run "$@"
  local n s got=""
  n="$(count NEXT)"; s="$(count STOP)"
  if (( n + s != 1 )); then
    bad "$label — exactly one of NEXT= / STOP= expected, got NEXT x$n STOP x$s ($(printf '%s' "$OUT" | tr '\n' ' '))"
    return
  fi
  has NEXT && got="NEXT=$(val NEXT)"
  has STOP && got="STOP=$(val STOP)"
  if [[ "$got" == "$want" && $RC -eq 0 ]]; then ok "$label"; else bad "$label — wanted '$want' (exit 0), got '$got' (exit $RC)"; fi
}

expect_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — wanted '$3', got '$2'"; fi; }

echo "STATUS x MODE:"
reset
profile '- **Mode:** auto'
for pair in \
  "planning|NEXT=/craft:build" \
  "implementing|NEXT=/craft:build" \
  "testing|NEXT=/craft:test" \
  "review|NEXT=/craft:recap" \
  "refactoring|NEXT=/craft:refactor" \
  "reviewing|NEXT=/craft:review" \
  "committing|NEXT=/craft:commit" \
  "committed|STOP=committed" \
  "blocked|STOP=blocked" \
  "paused|STOP=paused" \
  "awaiting-release|STOP=awaiting-release" \
  "awaiting-approval|STOP=awaiting-approval" \
  "bogus-status|STOP=unknown-status"; do
  st="${pair%%|*}"; want="${pair#*|}"
  plan "$st"
  verdict "auto: $st -> $want" "$want" --project "$P" "$PLAN"
  expect_eq "auto: $st reports MODE=auto STATUS=$st" "$(val MODE) $(val STATUS)" "auto $st"
done
profile '- **Mode:** manual'
for st in planning implementing testing review refactoring reviewing committing committed blocked paused awaiting-release awaiting-approval bogus-status; do
  plan "$st"
  verdict "manual: $st -> STOP=manual" "STOP=manual" --project "$P" "$PLAN"
  expect_eq "manual: $st reports MODE=manual STATUS=$st" "$(val MODE) $(val STATUS)" "manual $st"
done

echo "DEFAULTS (no profile, no block, no key -> auto):"
reset; plan implementing
verdict "no profile file -> auto" "NEXT=/craft:build" --project "$P" "$PLAN"
expect_eq "no profile file: MODE=auto" "$(val MODE)" "auto"
expect_eq "no profile file: no WARN" "$(count WARN)" "0"
printf '# CRAFT Profile\n\n## Execution\n\n- **Mode:** worktree\n' > "$PROFILE"
verdict "profile without a Slice Flow block -> auto (Execution's Mode is not read)" "NEXT=/craft:build" --project "$P" "$PLAN"
profile '> only a comment here'
verdict "Slice Flow block without the key -> auto" "NEXT=/craft:build" --project "$P" "$PLAN"
expect_eq "block without the key: no WARN" "$(count WARN)" "0"
profile ''
verdict "empty Slice Flow block -> auto" "NEXT=/craft:build" --project "$P" "$PLAN"
verdict "--profile names the file explicitly" "NEXT=/craft:build" --profile "$PROFILE" "$PLAN"
profile '- **Mode:** manual'
verdict "--profile with manual" "STOP=manual" --profile "$PROFILE" "$PLAN"
verdict "--profile wins over the project's own profile file" "STOP=manual" --project "$ROOT" --profile "$PROFILE" "$PLAN"

echo "INVALID VALUES (doubt means stop):"
for v in sometimes Auto MANUAL on '' 'auto manual'; do
  profile "- **Mode:** $v"
  verdict "Mode: '$v' -> STOP=invalid-mode" "STOP=invalid-mode" --project "$P" "$PLAN"
  expect_eq "Mode: '$v': MODE=invalid" "$(val MODE)" "invalid"
  if has WARN; then ok "Mode: '$v': a WARN= line"; else bad "Mode: '$v': no WARN= line"; fi
done
profile '- **Mode:** sometimes'
run --project "$P" "$PLAN"
case "$(val WARN)" in *sometimes*auto*manual*|*sometimes*) ok "the WARN names the bad value" ;; *) bad "the WARN does not name the bad value: $(val WARN)" ;; esac
profile "- **Mode:** auto
- **Mode:** manual"
verdict "two Mode lines -> STOP=invalid-mode" "STOP=invalid-mode" --project "$P" "$PLAN"
profile '- **Mode:** auto
- **Speed:** fast'
verdict "an unknown key warns, the mode is still honored" "NEXT=/craft:build" --project "$P" "$PLAN"
case "$(val WARN)" in *Speed*) ok "the unknown key is named in a WARN=" ;; *) bad "unknown key: no WARN naming it ($(val WARN))" ;; esac
profile '- **Mode:** auto
stray text that is not a key'
verdict "a stray line warns, the mode is still honored" "NEXT=/craft:build" --project "$P" "$PLAN"
if has WARN; then ok "the stray line warns"; else bad "the stray line did not warn"; fi
profile '- **Mode:** manual
> a comment line is no warning'
run --project "$P" "$PLAN"
expect_eq "a '>' comment line in the block is no warning" "$(count WARN)" "0"

echo "BLOCK BOUNDARY:"
printf '# CRAFT Profile\n\n## Slice Flow\n\n- **Mode:** auto\n\n## Autopilot\n\n- **Mode:** manual\n' > "$PROFILE"
verdict "a Mode line in the block AFTER is not read" "NEXT=/craft:build" --project "$P" "$PLAN"
printf '# CRAFT Profile\n\n## Execution\n\n- **Mode:** manual\n\n## Slice Flow\n\n- **Mode:** auto\n' > "$PROFILE"
verdict "a Mode line in the block BEFORE is not read" "NEXT=/craft:build" --project "$P" "$PLAN"
printf '# CRAFT Profile\n\n## Slice Flow\n\n```\n- **Mode:** manual\n```\n\n- **Mode:** auto\n' > "$PROFILE"
verdict "a Mode line in a fenced example is not read" "NEXT=/craft:build" --project "$P" "$PLAN"
printf '# CRAFT Profile\n\n## Slice Flow\n\n- **Mode:** manual\n' > "$PROFILE"
verdict "the block as the file's last section" "STOP=manual" --project "$P" "$PLAN"

echo "CRLF:"
printf '# CRAFT Profile\r\n\r\n## Slice Flow\r\n\r\n- **Mode:** manual\r\n' > "$PROFILE"
verdict "CRLF profile, manual" "STOP=manual" --project "$P" "$PLAN"
expect_eq "CRLF profile: no WARN" "$(count WARN)" "0"
printf '# CRAFT Profile\r\n\r\n## Slice Flow\r\n\r\n- **Mode:** auto\r\n' > "$PROFILE"
verdict "CRLF profile, auto" "NEXT=/craft:build" --project "$P" "$PLAN"
printf '# Slice 900\r\n\r\n> Status: testing\r\n> Slice-ID: slice-900\r\n\r\n## Goal\r\n' > "$PLAN"
verdict "CRLF plan" "NEXT=/craft:test" --project "$P" "$PLAN"
expect_eq "CRLF plan: STATUS has no CR" "$(val STATUS)" "testing"

echo "THE PLAN (a missing or malformed plan stops):"
profile '- **Mode:** auto'
verdict "plan file missing -> STOP=no-plan" "STOP=no-plan" --project "$P" "$P/.claude/plans/slice-999-none.md"
verdict "plan path is a directory -> STOP=no-plan" "STOP=no-plan" --project "$P" "$P/.claude/plans"
printf '# Slice 900\n\n## Goal\n\nno status line at all\n' > "$PLAN"
verdict "plan without a Status line -> STOP=unknown-status" "STOP=unknown-status" --project "$P" "$PLAN"
printf '# Slice 900\n\n## Goal\n\ng\n\n> Status: committing\n' > "$PLAN"
verdict "a Status line after the first section is no frontmatter -> STOP=unknown-status" "STOP=unknown-status" --project "$P" "$PLAN"
printf '# Slice 900\n\n> Status: `testing`  \n\n## Goal\n' > "$PLAN"
verdict "backticks and trailing blanks around the status are tolerated" "NEXT=/craft:test" --project "$P" "$PLAN"
printf '# Slice 900\n\n> Status:\n\n## Goal\n' > "$PLAN"
verdict "an empty status -> STOP=unknown-status" "STOP=unknown-status" --project "$P" "$PLAN"
plan testing
profile '- **Mode:** manual'
verdict "manual outranks a missing plan" "STOP=manual" --project "$P" "$P/.claude/plans/slice-999-none.md"
profile '- **Mode:** nope'
verdict "an invalid mode outranks a missing plan" "STOP=invalid-mode" --project "$P" "$P/.claude/plans/slice-999-none.md"

echo "--from (a phase that ended where it started does not chain):"
profile '- **Mode:** auto'
plan reviewing
verdict "--from reviewing at reviewing -> STOP=no-progress" "STOP=no-progress" --project "$P" --from reviewing "$PLAN"
plan implementing
verdict "--from reviewing, now implementing (a loop-back) -> NEXT=/craft:build" "NEXT=/craft:build" --project "$P" --from reviewing "$PLAN"
plan testing
verdict "--from implementing, now testing -> NEXT=/craft:test" "NEXT=/craft:test" --project "$P" --from implementing "$PLAN"
plan testing
verdict "--from testing at testing (a [U] iteration) -> STOP=no-progress" "STOP=no-progress" --project "$P" --from testing "$PLAN"
plan paused
verdict "--from implementing, now paused -> STOP=paused (the status stop wins)" "STOP=paused" --project "$P" --from implementing "$PLAN"
profile '- **Mode:** manual'
plan reviewing
verdict "--from with manual -> STOP=manual" "STOP=manual" --project "$P" --from reviewing "$PLAN"

# The pause request (slice-075): a live request of THIS session wins over NEXT= and over no-progress; the full matrix
# (consumed, foreign session, malformed, pre-resume, manual) is test-pause-watch.sh's.
profile '- **Mode:** auto'
plan testing
printf 'STATE=requested\nSESSION=sess-1\nSINCE=2026-10-08T10:00:00Z\n' > "$P/.claude/plans/.pause-request"
CLAUDE_CODE_SESSION_ID=sess-1 verdict "a live pause request at testing -> STOP=pause-requested (not NEXT=/craft:test)" "STOP=pause-requested" --project "$P" "$PLAN"
plan implementing
CLAUDE_CODE_SESSION_ID=sess-1 verdict "a live pause request wins over no-progress (--from implementing) -> STOP=pause-requested" "STOP=pause-requested" --project "$P" --from implementing "$PLAN"
CLAUDE_CODE_SESSION_ID=sess-2 verdict "a pause request of another session -> no-progress as without it" "STOP=no-progress" --project "$P" --from implementing "$PLAN"
plan paused
CLAUDE_CODE_SESSION_ID=sess-1 verdict "a pause request at a paused slice -> STOP=paused (the status stop comes first)" "STOP=paused" --project "$P" "$PLAN"
profile '- **Mode:** manual'
plan testing
CLAUDE_CODE_SESSION_ID=sess-1 verdict "a pause request in manual mode, plan in flight -> STOP=pause-requested (slice-077, decision [G])" "STOP=pause-requested" --project "$P" "$PLAN"
plan paused
CLAUDE_CODE_SESSION_ID=sess-1 verdict "manual + a pause request at a paused plan -> STOP=manual" "STOP=manual" --project "$P" "$PLAN"
plan committed
CLAUDE_CODE_SESSION_ID=sess-1 verdict "manual + a pause request at a committed plan -> STOP=manual" "STOP=manual" --project "$P" "$PLAN"
CLAUDE_CODE_SESSION_ID=sess-1 verdict "manual + a pause request, plan file missing -> STOP=manual" "STOP=manual" --project "$P" "$P/.claude/plans/nope.md"
plan testing
CLAUDE_CODE_SESSION_ID=sess-2 verdict "manual + a pause request of another session -> STOP=manual" "STOP=manual" --project "$P" "$PLAN"
profile '- **Mode:** sideways'
CLAUDE_CODE_SESSION_ID=sess-1 verdict "invalid mode + a live pause request, plan in flight -> STOP=pause-requested" "STOP=pause-requested" --project "$P" "$PLAN"
plan paused
CLAUDE_CODE_SESSION_ID=sess-1 verdict "invalid mode + a pause request at a paused plan -> STOP=invalid-mode" "STOP=invalid-mode" --project "$P" "$PLAN"
rm -f "$P/.claude/plans/.pause-request"
profile '- **Mode:** manual'
plan testing
verdict "manual without a pause request -> STOP=manual" "STOP=manual" --project "$P" "$PLAN"
profile '- **Mode:** sideways'
verdict "invalid mode without a pause request -> STOP=invalid-mode" "STOP=invalid-mode" --project "$P" "$PLAN"
rm -f "$P/.claude/plans/.pause-request"

# The --from value is the status AFTER the command's own Pre-flight write (review R1-1): a build that found
# `planning` writes `implementing` first, so a build that stopped early must read as no progress.
profile '- **Mode:** auto'
plan implementing
verdict "build that found planning, wrote implementing and stopped early: --from implementing -> STOP=no-progress" "STOP=no-progress" --project "$P" --from implementing "$PLAN"
plan reviewing
verdict "review that found refactoring, wrote reviewing and was gated: --from reviewing -> STOP=no-progress" "STOP=no-progress" --project "$P" --from reviewing "$PLAN"
plan reviewing
verdict "refactor with Phase 7 dropped: its skip gate advances, no --from -> NEXT=/craft:review" "NEXT=/craft:review" --project "$P" "$PLAN"
plan refactoring
verdict "refactor with Phase 7 kept that stopped: --from refactoring -> STOP=no-progress" "STOP=no-progress" --project "$P" --from refactoring "$PLAN"

echo "--mode (profile only, for /craft:prime):"
profile '- **Mode:** manual'
run --project "$P" --mode
expect_eq "--mode: MODE=manual" "$(val MODE)" "manual"
expect_eq "--mode: no NEXT= / STOP= / STATUS=" "$(count NEXT)$(count STOP)$(count STATUS)" "000"
expect_eq "--mode: exit 0" "$RC" "0"
reset
run --project "$P" --mode
expect_eq "--mode without a profile: MODE=auto" "$(val MODE)" "auto"
profile '- **Mode:** wat'
run --project "$P" --mode
expect_eq "--mode with an invalid value: MODE=invalid" "$(val MODE)" "invalid"
if has WARN; then ok "--mode with an invalid value: a WARN= line"; else bad "--mode with an invalid value: no WARN="; fi

echo "--map (the status -> command map, bound to the phase graph by test-workflow-status-graph.sh):"
run --map
expect_eq "--map: exit 0" "$RC" "0"
lines="$(printf '%s\n' "$OUT" | grep -c .)"
expect_eq "--map: twelve statuses" "$lines" "12"
bad_lines="$(printf '%s\n' "$OUT" | grep -vcE '^[a-z-]+	(NEXT	/craft:[a-z-]+|STOP	[a-z-]+)$')"
expect_eq "--map: every line is <status><TAB>NEXT<TAB>/craft:<cmd> or <status><TAB>STOP<TAB><reason>" "$bad_lines" "0"
expect_eq "--map: implementing -> /craft:build" "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "implementing" { print $2 " " $3 }')" "NEXT /craft:build"
expect_eq "--map: paused -> STOP paused" "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "paused" { print $2 " " $3 }')" "STOP paused"

echo "USAGE:"
run
expect_eq "no arguments: exit 2, nothing on stdout" "$RC:$OUT" "2:"
run --bogus
expect_eq "unknown option: exit 2" "$RC" "2"
run --project
expect_eq "option without a value: exit 2" "$RC" "2"
run --project "$P" a b
expect_eq "two plans: exit 2" "$RC" "2"
run --project "$ROOT/nowhere" "$PLAN"
expect_eq "--project that is not a directory: exit 2, nothing on stdout (not a silent auto)" "$RC:$OUT" "2:"
run --project "$ROOT/nowhere" --mode
expect_eq "--project that is not a directory, with --mode: exit 2" "$RC" "2"
run --map --mode
expect_eq "--map and --mode together: exit 2" "$RC" "2"

echo "PINS (the sites that carry the rule):"
blank() { "${BASH:-bash}" "$REGIONS" blank markdown "$1" 2>/dev/null; }

for cmd in build test recap refactor review commit plan; do
  f="$REPO/commands/$cmd.md"
  n="$(blank "$f" | grep -c '^<!-- craft:flow -->')"
  expect_eq "commands/$cmd.md carries <!-- craft:flow --> exactly once" "$n" "1"
  if [[ "$cmd" != "commit" ]]; then
    hand="$(blank "$f" | grep -A8 '^<!-- craft:flow -->' | grep -c '${CLAUDE_PLUGIN_ROOT}/scripts/flow-state.sh')"
    if (( hand >= 1 )); then ok "commands/$cmd.md: hands over \${CLAUDE_PLUGIN_ROOT}/scripts/flow-state.sh within 8 lines"; else bad "commands/$cmd.md: does not hand over the resolved helper path (a skill read as a file is not substituted)"; fi
  fi
  near="$(blank "$f" | grep -A8 '^<!-- craft:flow -->' | grep -c 'skills/workflow/SKILL.md')"
  if (( near >= 1 )); then ok "commands/$cmd.md: the marker points at skills/workflow/SKILL.md within 8 lines"; else bad "commands/$cmd.md: the marker does not point at the rule within 8 lines"; fi
done

skill="$REPO/skills/workflow/SKILL.md"
expect_eq "skills/workflow/SKILL.md carries the rule once (craft:flow-rule)" "$(blank "$skill" | grep -c '^<!-- craft:flow-rule -->')" "1"
rule="$(blank "$skill" | sed -n '/^<!-- craft:flow-rule -->/,/^## /p')"
# the per-command --from table: one row per command, with the value that command's own work began in
for pair in '/craft:build|implementing' '/craft:test|testing' '/craft:recap|the status it found' '/craft:refactor|refactoring' '/craft:review|reviewing'; do
  c="${pair%%|*}"; v="${pair#*|}"
  row="$(printf '%s\n' "$rule" | grep -F "| \`$c\` |" | head -n 1)"
  case "$row" in *"$v"*) ok "the rule's --from table: $c -> $v" ;; *) bad "the rule's --from table has no row '$c' carrying '$v'" ;; esac
done
case "$rule" in *"refused in its Pre-flight"*"no"*"Auto flow step"*) ok "the rule keeps a Pre-flight refusal out of the flow" ;; *) bad "the rule does not keep a Pre-flight refusal out of the flow" ;; esac
case "$rule" in *"advisory"*"never chains"*) ok "the rule keeps an advisory review out of the flow" ;; *) bad "the rule does not keep an advisory review out of the flow" ;; esac
for needle in 'scripts/flow-state.sh' 'NEXT=' 'STOP=' 'Subagent Mode' 'Slice Flow' 'Doubt means stop' '--from'; do
  case "$rule" in *"$needle"*) ok "the rule names '$needle'" ;; *) bad "the rule does not name '$needle'" ;; esac
done

plan_md="$(blank "$REPO/commands/plan.md")"
case "$plan_md" in *"Build now"*) ok "commands/plan.md asks 'Build now'" ;; *) bad "commands/plan.md has no 'Build now' click" ;; esac

# recap's Step 4 (slice-076, T2): under Mode: auto the "Ready for Phase 7/8?" question is not asked, so the step asks the
# helper's --mode BEFORE its question
recap_step4="$(blank "$REPO/commands/recap.md" | sed -n '/^### 4\. /,/^## Output Format/p')"
recap_before_q="${recap_step4%%Ready for Phase*}"
case "$recap_step4" in *"Ready for Phase"*) ok "recap Step 4 still asks the question where the mode is not auto" ;; *) bad "recap Step 4 lost its question (manual / invalid / helper failure must still ask)" ;; esac
case "$recap_before_q" in *"flow-state.sh"*"--mode"*) ok "recap Step 4 names flow-state.sh and --mode before its question" ;; *) bad "recap Step 4 does not name flow-state.sh and --mode before its question (under auto it would still ask)" ;; esac
case "$recap_before_q" in *'${CLAUDE_PLUGIN_ROOT}/scripts/flow-state.sh'*) ok "recap Step 4 hands over the resolved helper path" ;; *) bad "recap Step 4 does not hand over \${CLAUDE_PLUGIN_ROOT}/scripts/flow-state.sh" ;; esac

for f in prime onboard; do
  c="$(cat "$REPO/commands/$f.md")"
  case "$c" in *"Slice Flow"*) ok "commands/$f.md names the Slice Flow block" ;; *) bad "commands/$f.md does not name the Slice Flow block" ;; esac
done
case "$(cat "$REPO/commands/prime.md")" in *"flow=<mode>"*) ok "prime's report line carries flow=<mode>" ;; *) bad "prime's report line has no flow=<mode> segment" ;; esac
case "$(cat "$REPO/commands/prime.md")" in *"flow-state.sh"*) ok "prime validates through flow-state.sh" ;; *) bad "prime does not call flow-state.sh" ;; esac

tpl="$(cat "$REPO/templates/craft-profile.md.template")"
case "$tpl" in *"## Slice Flow"*"{{slice_flow_mode}}"*) ok "the profile template carries the Slice Flow block with its placeholder" ;; *) bad "the profile template lacks the Slice Flow block / {{slice_flow_mode}}" ;; esac
for pair in balanced:auto autonomous:auto careful:manual; do
  name="${pair%%:*}"; want="${pair#*:}"
  got="$(awk '/^## Slice Flow/ {inb=1; next} /^## / {inb=0} inb && /^- \*\*Mode:\*\*/ { sub(/^- \*\*Mode:\*\* */, ""); sub(/\r$/, ""); print }' "$REPO/templates/profiles/$name.md")"
  expect_eq "preset $name ships Slice Flow Mode: $want" "$got" "$want"
done
defaults="$(cat "$REPO/craft-profile-defaults.md")"
case "$defaults" in *"| Slice Flow | Mode | \`auto\`"*) ok "craft-profile-defaults.md has the Slice Flow row (default auto)" ;; *) bad "craft-profile-defaults.md lacks the Slice Flow | Mode | \`auto\` row" ;; esac
case "$defaults" in *"Slice Flow"*"careful"*|*"careful"*"Slice Flow"*) ok "the preset table names the flow per preset" ;; *) bad "the preset table lacks the flow column" ;; esac

echo
if (( FAIL == 0 )); then
  echo "RESULT: $PASS passed, 0 failed"
else
  echo "RESULT: $PASS passed, $FAIL failed"
fi
[[ $FAIL -eq 0 ]]
