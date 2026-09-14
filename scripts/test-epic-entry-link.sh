#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-epic-entry-link.sh — self-contained tests for the epic entry ↔ slice-ID helper
# (epic-entry-link.sh, B12 / slice-041).
#
# No test runner exists in this repo (plugin assets, not runtime software), so this
# harness stands alone: each case writes a throwaway project with epic and slice plans
# (and, where a landed slice matters, a git repository), drives the helper and asserts on
# its KEY=VALUE output and on the epic plan it rewrites. It also checks that a linked,
# landed entry reads as landed to scripts/execute-resume-state.sh, and binds the helper to
# commands/plan.md, commands/execute.md, commands/epic.md and the epic template. Run it directly:
#
#   bash scripts/test-epic-entry-link.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/epic-entry-link.sh"
RESUME="$SCRIPT_DIR/execute-resume-state.sh"
PLAN_CMD="$REPO_ROOT/commands/plan.md"
EXECUTE="$REPO_ROOT/commands/execute.md"
EPIC_CMD="$REPO_ROOT/commands/epic.md"
EPIC_TPL="$REPO_ROOT/templates/epic-plan.md.template"
for f in "$RESUME" "$PLAN_CMD" "$EXECUTE" "$EPIC_CMD" "$EPIC_TPL"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check()  { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
refute() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$n"; else ok "$n"; fi; }

TMP="$(mktemp -d)"
TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR

N=0
P=""
EPIC=".claude/plans/epic-001-ep.md"
fixture() { # fresh project with one epic: entries auth, profile, billing (unlinked)
  N=$((N + 1)); P="$TMP/c$N/proj"
  mkdir -p "$P/.claude/plans" "$P/.claude/project/slices"
  cat > "$P/$EPIC" <<'EOF'
# Epic 001 — fixture

> Status: active
> Epic-ID: epic-001
> Epic-Slug: ep

## Vision

A fixture epic.

## Slice Decomposition

> Initial decomposition into vertical slices.

- [ ] auth — login flow
- [ ] profile — edit the profile — with a dash in the intent
- [ ] billing — invoices

## Review Checkpoints

- [ ] auth — not a decomposition entry (another section)
EOF
}
splan() { # id slug
  printf '# Slice — fixture\n\n> Status: planning\n> Slice-ID: %s\n> Slice-Slug: %s\n> Depends-On: []\n' "$1" "$2" > "$P/.claude/plans/$1-$2.md"
}
archive() { printf '# Slice — archive\n' > "$P/.claude/project/slices/$1-$2.md"; }
run() { (cd "$P" && bash "$HELPER" "$@" 2>&1); }
line_of() { grep -E "^$1" "$P/$EPIC"; }   # a decomposition line by its start
# the value of KEY on the output line whose ENTRY= is <entry> (or the first KEY= anywhere when entry is empty)
field() { # output entry key
  local l
  if [[ -n "$2" ]]; then l="$(printf '%s\n' "$1" | grep -m1 -E "(^| )ENTRY=$2( |\$)")" || return 0
  else l="$(printf '%s\n' "$1" | grep -m1 -E "(^| )$3=")" || return 0; fi
  printf '%s\n' "$l" | tr ' ' '\n' | sed -n "s/^$3=//p" | head -1
}
expect() { # name output entry key want
  local got; got="$(field "$2" "$3" "$4")"
  if [[ "$got" == "$5" ]]; then ok "$1"; else bad "$1 — $4=$got, want $5"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}

[[ -f "$HELPER" ]] || bad "helper exists: $HELPER"


echo "── link: /craft:plan writes the slice-ID into its entry ──────────────"

fixture; splan slice-041 auth-login
cp "$P/$EPIC" "$TMP/expected"
sed -i.bak 's/^- \[ \] auth — login flow$/- [ ] slice-041 — auth — login flow/' "$TMP/expected" && rm -f "$TMP/expected.bak"
out="$(run link "$EPIC" auth slice-041)"
expect "unlinked entry → RESULT linked"                     "$out" "" RESULT linked
check  "  … the file equals the original with that one line changed (byte-exact)" cmp -s "$P/$EPIC" "$TMP/expected"
check  "  … a same-named line outside the decomposition is untouched" grep -q '^- \[ \] auth — not a decomposition entry' "$P/$EPIC"
cp "$P/$EPIC" "$TMP/before"
out="$(run link "$EPIC" auth slice-041)"
expect "linking again with the same ID → RESULT unchanged" "$out" "" RESULT unchanged
check  "  … the epic plan is byte-identical"                cmp -s "$P/$EPIC" "$TMP/before"
out="$(run link "$EPIC" auth slice-099)"
expect "entry linked to a live ID (plan present) → ERROR, never overwritten" "$out" "" ERROR "entry_linked_elsewhere:slice-041"
check  "  … still slice-041"                                line_of '- \[ \] slice-041 — auth — login flow$'
out="$(run link "$EPIC" profile slice-041)"
expect "the slice-ID already sits on another entry → ERROR" "$out" "" ERROR "slice_already_linked:auth"

fixture; archive slice-040 auth
run link "$EPIC" auth slice-040 >/dev/null
out="$(run link "$EPIC" auth slice-099)"
expect "entry linked to a landed ID (archive only) → ERROR, never overwritten" "$out" "" ERROR "entry_linked_elsewhere:slice-040"

fixture
out="$(run link "$EPIC" nosuch slice-041)"
expect "no entry of that short-name → ERROR entry_not_found" "$out" "" ERROR "entry_not_found:nosuch"
printf -- '- [ ] billing — a second billing entry\n' > "$TMP/extra"
sed -i.bak '/^- \[ \] billing — invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run link "$EPIC" billing slice-041)"
expect "two entries of that short-name → ERROR entry_ambiguous" "$out" "" ERROR "entry_ambiguous:billing"
out="$(run link "$EPIC" auth slice-41)"
expect "a malformed slice-ID → ERROR"                       "$out" "" ERROR "invalid_slice_id:slice-41"
out="$(run link "$EPIC" prof slice-041)"
expect "a prefix of a short-name is no match"               "$out" "" ERROR "entry_not_found:prof"
out="$(run link "$EPIC" 'a*' slice-041)"
expect "a glob pattern is no match"                         "$out" "" ERROR "entry_not_found:a*"

fixture; splan slice-041 auth-login; splan slice-043 user-profile
sed -i.bak 's/^- \[ \] auth — login flow$/- [x] auth — login flow/' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run link "$EPIC" auth slice-041)"
expect "a checked entry is linked too"                      "$out" "" RESULT linked
check  "  … keeps its checkbox"                             line_of '- \[x\] slice-041 — auth — login flow$'
printf -- '- [ ] user profile — a short-name with a space\n' > "$TMP/extra"
sed -i.bak '/^- \[ \] billing — invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run link "$EPIC" 'user profile' slice-043)"
expect "a short-name with a space is linked"                "$out" "" RESULT linked
check  "  … as that entry"                                  line_of '- \[ \] slice-043 — user profile — a short-name with a space$'

echo "── link: nothing else about the file changes ────────────────────────"

fixture; splan slice-041 auth-login
printf '%s' "$(cat "$P/$EPIC")" > "$TMP/nonl" && cp "$TMP/nonl" "$P/$EPIC"   # drop the final newline
sed 's/^- \[ \] auth — login flow$/- [ ] slice-041 — auth — login flow/' "$P/$EPIC" > "$TMP/exp-nonl"
printf '%s' "$(cat "$TMP/exp-nonl")" > "$TMP/expected"
chmod 644 "$P/$EPIC"
out="$(run link "$EPIC" auth slice-041)"
expect "no final newline: RESULT linked"                    "$out" "" RESULT linked
check  "  … byte-exact, the final newline still missing"    cmp -s "$P/$EPIC" "$TMP/expected"
check  "  … the file mode is kept"                          test "$(stat -c %a "$P/$EPIC" 2>/dev/null || stat -f %Lp "$P/$EPIC")" = 644

fixture; splan slice-041 auth-login
mv "$P/$EPIC" "$TMP/c$N/real-epic.md"; ln -s "$TMP/c$N/real-epic.md" "$P/$EPIC"
run link "$EPIC" auth slice-041 >/dev/null
check  "a symlinked epic plan stays a symlink"              test -L "$P/$EPIC"
check  "  … and its target carries the link"                grep -q '^- \[ \] slice-041 — auth — login flow$' "$TMP/c$N/real-epic.md"

fixture; splan slice-041 auth-login
sed -i.bak 's/$/\r/' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run link "$EPIC" auth slice-041)"
expect "a CRLF epic plan: the entry is found and linked"    "$out" "" RESULT linked
check  "  … the linked line keeps its CR"                   grep -q $'^- \\[ \\] slice-041 — auth — login flow\r$' "$P/$EPIC"
check  "  … every other line keeps its CR"                  test "$(grep -c $'\r$' "$P/$EPIC")" = "$(wc -l < "$P/$EPIC" | tr -d ' ')"

echo "── a dead link is free (R1-1) ───────────────────────────────────────"

fixture; splan slice-041 auth-login
run link "$EPIC" auth slice-041 >/dev/null
mv "$P/.claude/plans/slice-041-auth-login.md" "$TMP/c$N/"   # /craft:abort removed the plan; no archive
out="$(run resolve "$EPIC")"
expect "an aborted slice's ID resolves as missing"          "$out" auth STATE missing
out="$(run candidates)"
check  "candidates offers the entry again, naming the dead ID" \
  bash -c 'grep -q "^CANDIDATE EPIC=epic-001 EPIC_PLAN=.claude/plans/epic-001-ep.md LINK=slice-041 DUP=no ENTRY=auth INTENT=login flow$" <<<"$1"' _ "$out"
splan slice-050 auth-login
out="$(run link "$EPIC" auth slice-050)"
expect "link replaces the dead ID → RESULT relinked"        "$out" "" RESULT relinked
expect "  … REPLACED names the dead ID"                     "$out" "" REPLACED slice-041
check  "  … the entry carries the new ID"                   line_of '- \[ \] slice-050 — auth — login flow$'
out="$(run resolve "$EPIC")"
expect "  … and resolves to the new plan"                   "$out" auth STATE plan

echo "── candidates: the entries /craft:plan offers ───────────────────────"

fixture; splan slice-041 auth-login
printf '# Epic 002 — other\n\n> Status: active\n> Epic-ID: epic-002\n> Epic-Slug: other\n\n## Slice Decomposition\n\n- [ ] slice-007 — done — linked\n- [ ] search — find things\n' > "$P/.claude/plans/epic-002-other.md"
archive slice-007 done
run link "$EPIC" auth slice-041 >/dev/null
out="$(run candidates)"
expect "CANDIDATE_COUNT counts the unlinked entries of every epic" "$out" "" CANDIDATE_COUNT 3
check  "  … a live linked entry is not offered"             bash -c 'grep -q "^CANDIDATE " <<<"$1" && ! grep -q " ENTRY=auth " <<<"$1"' _ "$out"
check  "  … nor a landed linked entry of another epic"      bash -c 'grep -q "^CANDIDATE " <<<"$1" && ! grep -q " ENTRY=done " <<<"$1"' _ "$out"
check  "unlinked entries are offered with their epic and LINK=-" \
  bash -c 'grep -q "^CANDIDATE EPIC=epic-001 EPIC_PLAN=.claude/plans/epic-001-ep.md LINK=- DUP=no ENTRY=profile INTENT=edit the profile — with a dash in the intent$" <<<"$1" && grep -q "^CANDIDATE EPIC=epic-002 .*ENTRY=search " <<<"$1"' _ "$out"

N=$((N + 1)); P="$TMP/c$N/proj"; mkdir -p "$P/.claude/plans"
out="$(run candidates)"
expect "no epic plan → CANDIDATE_COUNT 0"                   "$out" "" CANDIDATE_COUNT 0

echo "── parsing edges ────────────────────────────────────────────────────"

fixture
cat >> "$P/$EPIC" <<'EOF'
EOF
python3 - "$P/$EPIC" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- [ ] billing — invoices\n", "- [ ] billing — invoices\n\n```\n## not a heading\n- [ ] example — an entry inside a fence\n```\n\n- [ ] after-fence — a real entry after the fence\n")
open(p, "w").write(s)
EOF
out="$(run resolve "$EPIC")"
check  "an entry inside a fenced block is not an entry"     bash -c '! grep -q "ENTRY=example" <<<"$1"' _ "$out"
expect "  … a heading inside a fence does not end the section" "$out" after-fence STATE unlinked
expect "  … ENTRY_COUNT 4"                                  "$out" "" ENTRY_COUNT 4

fixture
sed -i.bak 's/^## Slice Decomposition$/## Slice Decomposition  /' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run resolve "$EPIC")"
expect "a trailing space on the heading still finds the entries" "$out" "" ENTRY_COUNT 3

fixture
sed -i.bak 's/^## Slice Decomposition$/## Decomposition/' "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run resolve "$EPIC")"
expect "no decomposition entries → ENTRY_COUNT 0"           "$out" "" ENTRY_COUNT 0
expect "  … RESULT unresolved, never ok"                    "$out" "" RESULT unresolved

fixture
printf -- '- [ ] slice-100 — shaped like an ID\n' > "$TMP/extra"
sed -i.bak '/^- \[ \] billing — invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run resolve "$EPIC")"
expect "known limit: a short-name shaped like a slice-ID reads as linked" "$out" "shaped" STATE missing

echo "── round 2: fences, ignored lines, target checks, safe writes ────────"

fixture; splan slice-041 auth-login
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- [ ] auth — login flow\n", "- [ ] auth — login flow\n  ```bash\n  echo inside an indented fence\n  ```\n")
s = s.replace("## Vision\n\nA fixture epic.\n", "## Vision\n\n- a list item\n  ```\n  code in a list item\n  ```\n\n````md\n```\n## not a heading either\n```\n````\n")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
expect "an indented fence closes: the entries after it are read" "$out" "" ENTRY_COUNT 3
expect "  … a four-backtick fence is not closed by an inner three-backtick line" "$out" billing STATE unlinked
expect "  … nothing ignored"                                "$out" "" IGNORED_COUNT 0

fixture
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- [ ] profile — edit", "````md\n```\n- [ ] fake — an entry-shaped line inside a four-backtick block\n```\n````\n- [ ] profile — edit")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
check  "inside the decomposition, a three-backtick line does not close a four-backtick fence" \
  bash -c '! grep -q "ENTRY=fake" <<<"$1" && grep -q "^ENTRY_COUNT=3$" <<<"$1"' _ "$out"

fixture
printf -- '* [ ] starred — a star bullet\n  - [ ] nested — an indented entry\n```\n- [ ] hidden — behind a fence that never closes\n' > "$TMP/extra"
sed -i.bak '/^- \[ \] billing — invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run resolve "$EPIC")"
expect "list items that are not entries, and an unclosed fence, are IGNORED" "$out" "" IGNORED_COUNT 3
check  "  … each named with its line"                       bash -c 'grep -q "^IGNORED LINE=[0-9]* TEXT=\* \[ \] starred" <<<"$1" && grep -q "^IGNORED LINE=[0-9]* TEXT=unclosed fence" <<<"$1"' _ "$out"
expect "  … RESULT unresolved"                              "$out" "" RESULT unresolved

fixture
out="$(run link "$EPIC" auth slice-999)"
expect "link to an ID with no plan and no archive (a typo) → ERROR" "$out" "" ERROR "slice_not_found:slice-999:missing"
check  "  … the epic plan is untouched"                     line_of '- \[ \] auth — login flow$'

fixture; splan slice-041 auth-login
printf '# Epic 002 — other\n\n> Epic-ID: epic-002\n\n## Slice Decomposition\n\n- [ ] slice-041 — gamma — elsewhere\n' > "$P/.claude/plans/epic-002-other.md"
out="$(run link "$EPIC" auth slice-041)"
expect "link to an ID already on an entry of another epic → ERROR" "$out" "" ERROR "slice_linked_in_other_epic:.claude/plans/epic-002-other.md:gamma"

fixture
printf -- '- [ ] billing — a second billing entry\n' > "$TMP/extra"
sed -i.bak '/^- \[ \] billing — invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run candidates)"
check  "candidates marks entries sharing a short-name DUP=yes" bash -c 'test "$(grep -c "DUP=yes ENTRY=billing " <<<"$1")" = 2 && grep -q "DUP=no ENTRY=auth " <<<"$1"' _ "$out"

fixture; splan slice-041 auth-login
for k in $(seq 1 60); do printf 'filler line %s to make the epic plan larger than one block\n' "$k" >> "$P/$EPIC"; done
cp "$P/$EPIC" "$TMP/before"
out="$(cd "$P" && ( ulimit -f 1; bash "$HELPER" link "$EPIC" auth slice-041 ) 2>&1)"
check  "a write that cannot complete (file size limit) never reports success" bash -c '! grep -q "^RESULT=" <<<"$1"' _ "$out"
check  "  … and leaves the epic plan byte-identical"        cmp -s "$P/$EPIC" "$TMP/before"

echo "── round 3: fence shapes, ignored lines, target order, read-only ────"

fixture
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- [ ] profile — edit", "~~~\n```\n- [ ] fake — entry-shaped, inside a tilde fence\n~~~\n- [ ] profile — edit")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
check  "a backtick line does not close a tilde fence"      bash -c '! grep -q "ENTRY=fake" <<<"$1" && grep -q "^ENTRY_COUNT=3$" <<<"$1"' _ "$out"

fixture
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- [ ] profile — edit", "  ```\n  - [ ] step — a checkbox inside an indented fence\n  ```\n- [ ] profile — edit")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
expect "a checkbox inside an indented fence is neither an entry nor ignored" "$out" "" IGNORED_COUNT 0
expect "  … the entries around it are read"                "$out" "" ENTRY_COUNT 3

fixture
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("A fixture epic.\n", "A fixture epic.\n\n```\nnever closed\n")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
expect "an unclosed fence in Vision hides the section → ENTRY_COUNT 0" "$out" "" ENTRY_COUNT 0
expect "  … and is reported as IGNORED"                    "$out" "" IGNORED_COUNT 1
out="$(run candidates)"
check  "  … candidates names it too, so /craft:plan is not silent" bash -c 'grep -q "^IGNORED EPIC_PLAN=.claude/plans/epic-001-ep.md LINE=[0-9]* TEXT=unclosed fence" <<<"$1" && grep -q "^IGNORED_COUNT=1$" <<<"$1"' _ "$out"

fixture
python3 - "$P/$EPIC" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("A fixture epic.\n", "A fixture epic.\n\n```js``` snippets are inline code, not a fence\n")
open(p, "w").write(s)
PY
out="$(run resolve "$EPIC")"
expect "a backtick line with backticks in its info string opens no fence" "$out" "" ENTRY_COUNT 3

fixture; splan slice-041 auth; splan slice-042 profile; splan slice-043 billing
run link "$EPIC" auth slice-041 >/dev/null; run link "$EPIC" profile slice-042 >/dev/null; run link "$EPIC" billing slice-043 >/dev/null
printf -- '- [design notes](../design/x.md)\n* [ ] starred — a star bullet\n' > "$TMP/extra"
sed -i.bak '/— invoices$/r '"$TMP/extra" "$P/$EPIC" && rm -f "$P/$EPIC.bak"
out="$(run resolve "$EPIC")"
expect "a plain link bullet is not ignored, a checkbox bullet is" "$out" "" IGNORED_COUNT 1
expect "  … every entry live, one ignored line → RESULT unresolved" "$out" "" RESULT unresolved

fixture; splan slice-012 profile
run link "$EPIC" profile slice-012 >/dev/null
mv "$P/.claude/plans/slice-012-profile.md" "$TMP/c$N/"
out="$(run link "$EPIC" profile slice-012)"
expect "link with the entry's own dead ID is refused, never unchanged" "$out" "" ERROR "slice_not_found:slice-012:missing"

fixture; splan slice-041 auth; splan slice-041 auth-2
out="$(run link "$EPIC" auth slice-041)"
expect "link to an ID with two plans → ERROR"               "$out" "" ERROR "slice_not_found:slice-041:ambiguous"

fixture; splan slice-041 auth
chmod 444 "$P/$EPIC"; cp "$P/$EPIC" "$TMP/before"
tmpdir="$TMP/c$N/tmpdir"; mkdir -p "$tmpdir"
out="$(cd "$P" && TMPDIR="$tmpdir" bash "$HELPER" link "$EPIC" auth slice-041 2>&1)"
expect "a read-only epic plan → ERROR read_only"            "$out" "" ERROR "epic_plan_unwritable:$EPIC:read_only"
check  "  … no raw shell error, no temp file left, plan byte-identical" \
  bash -c '! grep -qi "permission denied" <<<"$1" && test -z "$(ls -A "$2")" && cmp -s "$3" "$4"' _ "$out" "$tmpdir" "$P/$EPIC" "$TMP/before"
chmod 644 "$P/$EPIC"

echo "── resolve: what /craft:execute A6 reads ────────────────────────────"

fixture; splan slice-041 auth-login; archive slice-040 profile
run link "$EPIC" auth slice-041 >/dev/null
run link "$EPIC" profile slice-040 >/dev/null
out="$(run resolve "$EPIC")"
expect "linked + plan present → STATE plan"                 "$out" auth STATE plan
expect "  … PLAN names it"                                  "$out" auth PLAN ".claude/plans/slice-041-auth-login.md"
expect "linked, plan gone, archive present → STATE landed"  "$out" profile STATE landed
expect "unlinked → STATE unlinked"                          "$out" billing STATE unlinked
expect "  … RESULT unresolved while an entry is unlinked"   "$out" "" RESULT unresolved
splan slice-042 billing; run link "$EPIC" billing slice-042 >/dev/null
mv "$P/.claude/plans/slice-042-billing.md" "$TMP/c$N/"
out="$(run resolve "$EPIC")"
expect "linked, neither plan nor archive → STATE missing"   "$out" billing STATE missing
expect "  … the only unresolved entry → RESULT unresolved"  "$out" "" RESULT unresolved
splan slice-042 billing; splan slice-042 billing-2
out="$(run resolve "$EPIC")"
expect "linked, two plans for the ID → STATE ambiguous"     "$out" billing STATE ambiguous
expect "  … the only unresolved entry → RESULT unresolved"  "$out" "" RESULT unresolved
out="$(run candidates)"
check  "  … an ambiguous link is not offered"               bash -c 'grep -q "^CANDIDATE_COUNT=0$" <<<"$1"' _ "$out"
splan slice-044 billing-new
out="$(run link "$EPIC" billing slice-044)"
expect "  … nor replaced"                                   "$out" "" ERROR "entry_linked_elsewhere:slice-042"
mv "$P/.claude/plans/slice-042-billing-2.md" "$TMP/c$N/"
out="$(run resolve "$EPIC")"
expect "every entry resolved → RESULT ok"                   "$out" "" RESULT ok
expect "  … ENTRY_COUNT 3 (Review Checkpoints not counted)" "$out" "" ENTRY_COUNT 3
out="$(run resolve .claude/plans/epic-404.md)"
expect "an unreadable epic plan → ERROR"                    "$out" "" ERROR "epic_plan_unreadable:.claude/plans/epic-404.md"
out="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$P" bash "$HELPER" resolve "$EPIC" 2>&1)"
expect "the project dir comes from CLAUDE_PROJECT_DIR"      "$out" "" RESULT ok

echo "── a re-run after the first slice landed ────────────────────────────"

fixture; splan slice-041 auth-login; splan slice-042 profile-edit; splan slice-043 billing
run link "$EPIC" auth slice-041 >/dev/null; run link "$EPIC" profile slice-042 >/dev/null; run link "$EPIC" billing slice-043 >/dev/null
( cd "$P" && git init -q -b main && printf '.claude/plans/\n' > .gitignore && git add . && git commit -q -m init )
mv "$P/.claude/plans/slice-041-auth-login.md" "$TMP/c$N/"; archive slice-041 auth-login
( cd "$P" && git add . && git commit -q -m "docs(slices): archive slice-041" )
out="$(run resolve "$EPIC")"
expect "sequential epic, slice 1 landed → its entry resolves as landed" "$out" auth STATE landed
expect "  … slice 2 still resolves to its plan"             "$out" profile STATE plan
args=()   # what A6 hands on: PLAN= for plan, SLICE= for landed
while IFS= read -r l; do
  st="$(printf '%s\n' "$l" | tr ' ' '\n' | sed -n 's/^STATE=//p')"
  case "$st" in
    plan)   args+=("$(printf '%s\n' "$l" | tr ' ' '\n' | sed -n 's/^PLAN=//p')") ;;
    landed) args+=("$(printf '%s\n' "$l" | tr ' ' '\n' | sed -n 's/^SLICE=//p')") ;;
  esac
done < <(printf '%s\n' "$out" | grep '^SLICE=')
check  "  … A6 hands on one argument per entry"             test "${#args[@]}" = 3
out="$(cd "$P" && bash "$RESUME" --mode sequential "${args[@]}" 2>&1)"
check  "  … and execute-resume-state, fed from resolve, skips slice-041 as archived" \
  bash -c "grep -q '^SLICE=slice-041 .*ACTION=skip REASON=archived' <<<\"\$1\"" _ "$out"

echo "── bound to the commands ────────────────────────────────────────────"

check "commands/plan.md offers candidates"                  grep -q 'epic-entry-link.sh" candidates' "$PLAN_CMD"
check "commands/plan.md links the entry"                    grep -q 'epic-entry-link.sh" link' "$PLAN_CMD"
check "commands/plan.md handles a relinked dead link"       grep -q 'RESULT=relinked' "$PLAN_CMD"
check "commands/execute.md A6 resolves through the helper"  grep -q 'epic-entry-link.sh" resolve' "$EXECUTE"
refute "commands/execute.md no longer matches an unlinked entry by judgment" grep -q 'resolves only while a plan matches it' "$EXECUTE"
A6="$(awk '/^### A6 /{p=1; next} /^### /{p=0} p' "$EXECUTE")"
states="$(sed -n 's/^#   *\(plan\|landed\|missing\|ambiguous\|unlinked\)  .*/\1/p' "$HELPER" 2>/dev/null)"
[[ -z "$states" ]] && states="$(grep -oE '^#[[:space:]]+(plan|landed|missing|ambiguous|unlinked)[[:space:]]{2,}' "$HELPER" | awk '{print $2}')"
check "  (the helper header lists five states)"             test "$(printf '%s\n' "$states" | grep -c .)" = 5
for s in $states; do
  check "  … execute.md A6 handles STATE=$s"                bash -c 'grep -qE "\`(STATE=)?$2\`" <<<"$1"' _ "$A6" "$s"
done
check "  … execute.md A6 rejects an epic with no entries"   bash -c 'grep -q "ENTRY_COUNT=0" <<<"$1"' _ "$A6"
check "  … execute.md A6 rejects IGNORED lines"             bash -c 'grep -q "IGNORED" <<<"$1"' _ "$A6"
check "commands/epic.md points at the entry format"         grep -q 'epic-entry-link.sh' "$EPIC_CMD"
check "the epic template points at the entry format"        grep -q 'epic-entry-link.sh' "$EPIC_TPL"
refute "  … without repeating the linked format"            grep -q 'slice-NNN — <short-name>' "$EPIC_TPL"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
