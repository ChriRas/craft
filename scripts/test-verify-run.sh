#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-verify-run.sh — self-contained tests for the autopilot's Phase-5 verification (D35):
# scripts/verify-run.sh (parse the <!-- craft:verify --> block, judge every command against the
# user's rules first, run the checks, append the evidence round) and the subcommand-aware rule
# matching of scripts/permission-rule-match.sh it relies on.
#
# No test runner exists in this repo, so this harness stands alone: it builds settings and plan
# fixtures under a temp dir, points $HOME and the managed-settings directory at them, and asserts
# on the helper's key=value output and on the plan file. Run it directly:
#
#   bash scripts/test-verify-run.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY="$SCRIPT_DIR/verify-run.sh"
MATCHER="$SCRIPT_DIR/permission-rule-match.sh"
[[ -f "$VERIFY" && -f "$MATCHER" ]] || { echo "FATAL: helper not found next to this harness" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$ROOT"
unset CLAUDE_CONFIG_DIR

new_fixture() { # → a fixture dir holding home/, managed/, proj/ — no rule anywhere yet
  local d
  d="$(mktemp -d "$ROOT/fx.XXXXXX")"
  mkdir -p "$d/home/.claude" "$d/managed" "$d/proj"
  printf '%s' "$d"
}
rules() { # fixture kind rule… — the user settings file with those rules of one kind
  local f="$1" kind="$2"; shift 2
  local list="" r
  for r in "$@"; do list="$list${list:+,}\"$r\""; done
  printf '{ "permissions": { "%s": [%s] } }\n' "$kind" "$list" > "$f/home/.claude/settings.json"
}
plan() { # fixture — write proj/plan.md from stdin (the Test Strategy body), with the usual sections
  { printf '# Slice 900 — fixture\n\n## Goal\n\nx\n\n## Test Strategy\n\n'
    cat
    printf '\n## Sub-Tasks\n\n- [ ] x\n\n## Verification Evidence\n\n(none yet)\n\n## Pause Note\n\n(none)\n'
  } > "$1/proj/plan.md"
}
run() { # fixture — verify-run.sh on the fixture's plan
  HOME="$1/home" CRAFT_TEST_MANAGED_DIR="$1/managed" bash "$VERIFY" --project "$1/proj" plan.md 2>&1
}
match() { # fixture command — permission-rule-match.sh
  HOME="$1/home" CRAFT_TEST_MANAGED_DIR="$1/managed" bash "$MATCHER" --project "$1/proj" --command "$2" 2>&1
}
field() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }
outside_evidence() { # plan — the plan with the Verification Evidence section cut out
  awk '/^## Verification Evidence/{skip=1; next} /^## /{skip=0} !skip' "$1"
}

echo "== 1. pass"
F="$(new_fixture)"
plan "$F" <<'EOF'
Prose first.

<!-- craft:verify -->
- check exit-zero :: exit=0 :: `true`
- check exit-three :: exit=3 :: exit 3
- check says-hi :: contains=hi there :: echo "well, hi there"
EOF
cp "$F/proj/plan.md" "$ROOT/before.md"
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == pass ]] && [[ "$(field CHECKS "$out")" == 3 ]] && [[ "$(field PASSED "$out")" == 3 ]] \
  && [[ "$(field FAILED "$out")" == - ]] && [[ "$(field ROUND "$out")" == 1 ]]; } \
  && ok "every expectation met (exit=0, exit=3, contains=): RESULT=pass, 3/3, round 1" || bad "pass (out=$out)"
{ [[ "$(grep -c '^### Run 1 — ' "$F/proj/plan.md")" == 1 ]] && grep -q '^- result · pass · 3/3 checks passed' "$F/proj/plan.md" \
  && ! grep -q '^(none yet)' <(sed -n '/^## Verification Evidence/,/^## Pause Note/p' "$F/proj/plan.md"); } \
  && ok "the round is appended under ## Verification Evidence, the placeholder replaced" || bad "evidence round"
diff <(outside_evidence "$ROOT/before.md") <(outside_evidence "$F/proj/plan.md") >/dev/null \
  && ok "the rest of the plan is byte-identical" || bad "plan changed outside the evidence section"

echo "== 2. fail"
F="$(new_fixture)"
plan "$F" <<'EOF'
<!-- craft:verify -->
- check good :: exit=0 :: true
- check wrong-exit :: exit=0 :: exit 4
- check missing-text :: contains=needle :: echo haystack
- check text-but-red :: contains=needle :: echo needle; exit 1
EOF
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == fail ]] && [[ "$(field PASSED "$out")" == 1 ]] \
  && [[ "$(field FAILED "$out")" == "wrong-exit,missing-text,text-but-red" ]]; } \
  && ok "an unmet exit code, a missing text and a found text with a red exit fail — each named, the rest still run" \
  || bad "fail (out=$out)"
grep -q '^- wrong-exit · `exit 4` · expected exit=0 · observed exit 4 · fail' "$F/proj/plan.md" \
  && ok "the evidence line names command, expectation and observation" || bad "fail evidence line"

echo "== 3. none"
F="$(new_fixture)"; plan "$F" <<'EOF'
Only prose — run the harness by hand.
EOF
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == none ]] && grep -q '^- result · none' "$F/proj/plan.md"; } \
  && ok "no verify block: RESULT=none, recorded" || bad "none (out=$out)"
F="$(new_fixture)"; plan "$F" <<'EOF'
An example of the format:

```
<!-- craft:verify -->
- check shown-only :: exit=0 :: touch SHOULD-NOT-EXIST
```

<!--
<!-- craft:verify -->
- check commented :: exit=0 :: touch SHOULD-NOT-EXIST
-->
EOF
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == none ]] && [[ ! -e "$F/proj/SHOULD-NOT-EXIST" ]]; } \
  && ok "a block inside a fence or a multi-line HTML comment is an example: none, nothing ran" || bad "example regions (out=$out)"
F="$(new_fixture)"
{ printf '# Slice 900\n\n## Goal\n\n<!-- craft:verify -->\n- check elsewhere :: exit=0 :: touch SHOULD-NOT-EXIST\n\n## Test Strategy\n\nprose\n'; } > "$F/proj/plan.md"
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == none ]] && [[ ! -e "$F/proj/SHOULD-NOT-EXIST" ]] && grep -q '^## Verification Evidence' "$F/proj/plan.md"; } \
  && ok "a marker outside ## Test Strategy is not read; a plan without the section gets one appended" || bad "outside TS (out=$out)"

echo "== 4. malformed"
for body in \
  $'<!-- craft:verify -->\n- check Bad_Name :: exit=0 :: true' \
  $'<!-- craft:verify -->\n- check no-expect :: true' \
  $'<!-- craft:verify -->\n- check a :: exit=0 :: true\n- check a :: exit=0 :: true' \
  $'<!-- craft:verify -->\n\n- check detached :: exit=0 :: true' \
  $'<!-- craft:verify -->\n- check one :: exit=0 :: true\n\n<!-- craft:verify -->\n- check two :: exit=0 :: true' \
  $'<!-- craft:verify -->\n- check ok :: exit=0 :: true\n- check Bad_Name :: exit=0 :: true' \
  $'<!-- craft:verify -->\n- check one :: exit=0 :: true\n\n- check two :: exit=0 :: false' \
  $'<!-- craft:verify -->\n- check one :: exit=0 :: true\n  (runs the unit suite)\n- check two :: exit=0 :: false' \
  $'<!-- craft:verify -->\n- check one :: exit=0 :: true\n- chek two :: exit=0 :: true\n- check three :: exit=0 :: false' \
  $'- check early :: exit=0 :: false\n<!-- craft:verify -->\n- check late :: exit=0 :: true'; do
  F="$(new_fixture)"; printf '%s\n' "$body" | plan "$F"
  out="$(run "$F")"
  [[ "$(field RESULT "$out")" == fail && "$(field REASON "$out")" == malformed:* ]] \
    && ok "malformed ($(field REASON "$out")): fail, never a pass" || bad "malformed not caught (body=$body, out=$out)"
done

F="$(new_fixture)"
printf '<!-- craft:verify -->\n- check ok :: exit=0 :: true\n\n- check the logs manually after deploy\n- checkout the docs, too\n' | plan "$F"
out="$(run "$F")"
[[ "$(field RESULT "$out")" == pass ]] && ok "prose bullets starting 'check' (no ' :: ') are not read as stray checks" || bad "prose false positive (out=$out)"

F="$(new_fixture)"; printf '<!-- craft:verify -->\n- check ok :: exit=0 :: true\n' | plan "$F"
run "$F" >/dev/null
{ printf '\n## Review Findings\n\n### Round 1 — 2026-09-30 (Phase-8)\n\n- R1-1 · Light · Local · x · fixed in-phase\n\n'
  printf '### Round 2 — 2026-09-30 (Phase-8)\n\n- R2-1 · Light · Local · y · fixed in-phase\n'; } >> "$F/proj/plan.md"
run "$F" >/dev/null
{ grep -q '^### Run 1 — [0-9TZ:-]* · review rounds: 0$' "$F/proj/plan.md" && grep -q '^### Run 2 — [0-9TZ:-]* · review rounds: 2$' "$F/proj/plan.md"; } \
  && ok "each round records the review rounds the plan held when it ran (0, then 2)" || bad "review rounds field"

echo "== 5. refused — the user's rules govern the checks"
F="$(new_fixture)"; rules "$F" deny 'Bash(rm:*)'
plan "$F" <<'EOF'
<!-- craft:verify -->
- check first :: exit=0 :: touch RAN-FIRST
- check sneaky :: exit=0 :: echo cleanup && rm -f scratch.txt
EOF
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == refused ]] && [[ "$(field REASON "$out")" == rule:sneaky ]] \
  && [[ "$(field RULE "$out")" == 'Bash(rm:*)' ]] && [[ ! -e "$F/proj/RAN-FIRST" ]] \
  && grep -q '^- result · refused · nothing ran' "$F/proj/plan.md"; } \
  && ok "a deny rule on a subcommand refuses the whole block before anything ran (the earlier check did not run)" \
  || bad "refused (out=$out)"
F="$(new_fixture)"; rules "$F" ask 'Bash(git clean *)'
printf '<!-- craft:verify -->\n- check tidy :: exit=0 :: cd . && git clean -n\n' | plan "$F"
out="$(run "$F")"
[[ "$(field RESULT "$out")" == refused ]] && ok "an ask rule refuses too (it would prompt at every run)" || bad "ask (out=$out)"
for level in managed project local; do
  F="$(new_fixture)"
  case $level in
    managed) f="$F/managed/managed-settings.json" ;;
    project) mkdir -p "$F/proj/.claude"; f="$F/proj/.claude/settings.json" ;;
    local)   mkdir -p "$F/proj/.claude"; f="$F/proj/.claude/settings.local.json" ;;
  esac
  printf '{ "permissions": { "deny": ["Bash(curl *)"] } }\n' > "$f"
  printf '<!-- craft:verify -->\n- check fetch :: exit=0 :: curl -s https://example.invalid\n' | plan "$F"
  out="$(run "$F")"
  [[ "$(field RESULT "$out")" == refused ]] && ok "a rule on the $level level refuses" || bad "$level level (out=$out)"
done
F="$(new_fixture)"; printf '{ "permissions": { "deny": [ ' > "$F/home/.claude/settings.json"
printf '<!-- craft:verify -->\n- check fine :: exit=0 :: touch RAN\n' | plan "$F"
out="$(run "$F")"
{ [[ "$(field RESULT "$out")" == refused ]] && [[ "$(field REASON "$out")" == unparseable:* ]] && [[ ! -e "$F/proj/RAN" ]]; } \
  && ok "unparseable settings: doubt refuses, nothing ran" || bad "doubt (out=$out)"
F="$(new_fixture)"; rules "$F" allow 'Bash(rm:*)'
printf '<!-- craft:verify -->\n- check ok :: exit=0 :: true\n' | plan "$F"
out="$(run "$F")"
[[ "$(field RESULT "$out")" == pass ]] && ok "an allow rule alone refuses nothing" || bad "allow only (out=$out)"

echo "== 5b. the shared matcher splits and unwraps like Claude Code"
F="$(new_fixture)"; rules "$F" deny 'Bash(rm:*)'
for c in 'echo x && rm -f y' 'echo x; rm y' 'a || rm y' 'ls | xargs rm' 'echo "$(rm -f y)"' 'echo `rm y`' \
         'for f in a b; do rm $f; done' '(cd x; rm y)' 'timeout 30 rm y' 'FOO=bar rm y' 'nice -n 5 rm y' \
         'command rm y' $'true\nrm y' "rm -- '/a b/c.md'" \
         '/bin/rm y' "sh -c 'rm y'" 'bash -c "rm -f y"' 'env rm y' 'env FOO=1 rm y' 'sudo rm y' 'sudo -u root rm y' \
         'timeout -s KILL 5 rm y' 'bash -lc "rm y"' 'sh -ec "rm y"' 'env -u X rm y'; do
  [[ "$(field MATCH "$(match "$F" "$c")")" == yes ]] && ok "matched: $c" || bad "not matched: $c"
done
for c in 'echo rm' 'grep -c rm notes.txt' 'bash scripts/test-x.sh' 'command -v rm'; do
  [[ "$(field MATCH "$(match "$F" "$c")")" == no ]] && ok "not matched (no rm subcommand): $c" || bad "false match: $c"
done

# Process markers unique to this run, so a concurrent run (or a leftover) cannot answer pgrep for us.
TAG="$$$RANDOM"
no_leftover() { # pattern — true when no process matches; a missing pgrep is reported, never a silent pass
  if ! command -v pgrep >/dev/null 2>&1; then
    echo "  SKIP  pgrep not installed — process-group cleanup not checked"; return 2
  fi
  ! pgrep -f "$1" >/dev/null 2>&1
}

echo "== 6. timeout"
F="$(new_fixture)"
printf '<!-- craft:verify -->\n- check hangs :: exit=0 timeout=2 :: sleep 37.%s; true\n- check after :: exit=0 :: true\n' "$TAG" | plan "$F"
start=$(date +%s); out="$(run "$F")"; took=$(( $(date +%s) - start ))
{ [[ "$(field RESULT "$out")" == fail ]] && [[ "$(field FAILED "$out")" == hangs ]] && [[ "$took" -lt 20 ]] \
  && grep -q 'observed timed out after 2s · fail' "$F/proj/plan.md"; } \
  && ok "a hanging check is killed after its timeout (${took}s) and fails; the next check still runs" || bad "timeout (took=${took}s, out=$out)"
no_leftover "sleep 37.$TAG"; rc=$?; [[ $rc -eq 2 ]] || { [[ $rc -eq 0 ]] \
  && ok "…and its whole process group is gone — no grandchild outlives the check" || bad "a grandchild of the timed-out check survived"; }

echo "== 7. rounds are appended, never rewritten"
F="$(new_fixture)"
printf '<!-- craft:verify -->\n- check ok :: exit=0 :: true\n' | plan "$F"
run "$F" >/dev/null; first="$(sed -n '/^### Run 1 — /,/^- result/p' "$F/proj/plan.md")"
out="$(run "$F")"
{ [[ "$(field ROUND "$out")" == 2 ]] && [[ "$(grep -c '^### Run [0-9]* — ' "$F/proj/plan.md")" == 2 ]] \
  && [[ "$(sed -n '/^### Run 1 — /,/^- result/p' "$F/proj/plan.md")" == "$first" ]]; } \
  && ok "a second run appends round 2; round 1 is byte-identical" || bad "append-only (out=$out)"

echo "== 6b. a check judged on exit, not on its pipe"
F="$(new_fixture)"
printf '<!-- craft:verify -->\n- check starts-server :: exit=0 timeout=15 :: sleep 23.%s & echo started\n' "$TAG" | plan "$F"
start=$(date +%s); out="$(run "$F")"; took=$(( $(date +%s) - start ))
{ [[ "$(field RESULT "$out")" == pass ]] && [[ "$took" -lt 12 ]]; } \
  && ok "a check that exits 0 but leaves a background child passes when it exits (${took}s), not at the timeout" \
  || bad "background child (took=${took}s, out=$out)"
no_leftover "sleep 23.$TAG"; rc=$?; [[ $rc -eq 2 ]] || { [[ $rc -eq 0 ]] \
  && ok "…and the background child it left is cleaned up with its process group" || bad "the check's background child survived"; }

echo "== 7b. the evidence never opens an example region"
F="$(new_fixture)"
plan "$F" <<'EOF2'
<!-- craft:verify -->
- check noisy :: exit=0 :: printf 'report\n```\n~~~\n<!-- generated\n'
EOF2
{ printf '\n## Review Findings\n\n### Round 1 — 2026-09-30 (Phase-8)\n\n'
  printf -- '- R1-1 · Heavy · Rethink · something open · escalated → route pending\n'; } >> "$F/proj/plan.md"
out="$(run "$F")"
rfs="$(bash "$SCRIPT_DIR/review-findings-state.sh" "$F/proj/plan.md" 2>&1)"
{ [[ "$(field RESULT "$out")" == pass ]] && [[ -z "$(bash "$SCRIPT_DIR/example-regions.sh" report markdown "$F/proj/plan.md")" ]] \
  && [[ "$(field OPEN_COUNT "$rfs")" == 1 ]] && [[ "$(field ROUNDS "$rfs")" == 1 ]]; } \
  && ok "output ending in a fence, a tilde fence and '<!--' is neutralised: no example region opens, the open finding stays open" \
  || bad "evidence opened an example region (rfs=$rfs)"
F="$(new_fixture)"
plan "$F" <<'EOF2'
<!-- craft:verify -->
- check ok :: exit=0 :: true
EOF2
python3 - "$F/proj/plan.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("## Sub-Tasks", "An example of a round:\n\n```\n### Run 1 — 2026-01-01T00:00:00Z\n```\n\n## Sub-Tasks", 1)
open(p, "w").write(s)
PY2
out="$(run "$F")"
{ [[ "$(field ROUND "$out")" == 1 ]] && ! grep -q '^(none yet)' <(sed -n '/^## Verification Evidence/,/^## Pause Note/p' "$F/proj/plan.md"); } \
  && ok "a '### Run' shown elsewhere in the plan is not counted: the first real round is round 1" || bad "round counting (out=$out)"

echo "== 7c. the template's example check parses"
ex="$(sed -n 's/.*e\.g\. `\(- check [^`]*\)`.*/\1/p' "$REPO/templates/slice-plan.md.template" | head -1)"
F="$(new_fixture)"; mkdir -p "$F/proj/tests"; printf 'true\n' > "$F/proj/tests/run.sh"
printf '<!-- craft:verify -->\n%s\n' "$ex" | plan "$F"
out="$(run "$F")"
{ [[ -n "$ex" ]] && [[ "$(field RESULT "$out")" == pass ]]; } \
  && ok "the slice-plan template's example line ('$ex') is valid grammar" || bad "template example (ex=$ex, out=$out)"

echo "== 8. no removal, no python3"
body="$(awk '/python3 -c '"'"'$/{f=1;next} f&&/^'"'"' "\$COMMAND"\)"$/{exit} f' "$MATCHER")"
{ [[ -n "$body" ]] && [[ "$body" != *"'"* ]]; } \
  && ok "the matcher's embedded python holds no single quote (one would end the bash string: every answer would turn to doubt)" \
  || bad "a single quote inside the matcher's python body (or the body was not found)"
no_removal() { # file — no non-comment line runs rm / unlink, except the helper's own temp-file trap
  ! grep -v '^[[:space:]]*#' "$1" | grep -v "trap 'rm -f \"\$BLANKED\"' EXIT" \
    | grep -Eq '(^|[;&|(`[:space:]])(rm|unlink)([[:space:]]|$)|os\.(remove|unlink|rmdir|removedirs)|shutil\.rmtree|\.unlink\('
}
no_removal "$VERIFY" && ok "verify-run.sh removes nothing but its own temp file (D34)" || bad "verify-run.sh removes something"
F="$(new_fixture)"; printf '<!-- craft:verify -->\n- check ok :: exit=0 :: touch RAN\n' | plan "$F"
NOPY="$ROOT/nopy"; mkdir -p "$NOPY"
for t in bash dirname mktemp sed awk grep cat date; do command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$NOPY/$t"; done
out="$(HOME="$F/home" CRAFT_TEST_MANAGED_DIR="$F/managed" PATH="$NOPY" bash "$VERIFY" --project "$F/proj" plan.md 2>&1)"
{ [[ "$(field RESULT "$out")" == refused ]] && [[ "$(field REASON "$out")" == python3_not_found ]] && [[ ! -e "$F/proj/RAN" ]]; } \
  && ok "without python3: refused, nothing ran" || bad "no python3 (out=$out)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
