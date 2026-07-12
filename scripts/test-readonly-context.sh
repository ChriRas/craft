#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-readonly-context.sh — self-contained tests for the F1 read-only context
# guard (readonly-context-guard.sh) and sync helper (ensure-readonly-context.sh).
#
# No test runner exists in this repo (plugin assets, not runtime software), so
# this harness stands alone: it builds a throwaway project fixture under a temp
# dir, drives the two scripts with synthetic inputs, asserts their behaviour, and
# exits non-zero if any case fails. Run it directly:
#
#   bash scripts/test-readonly-context.sh
#
# It writes nothing outside its own mktemp fixture (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_ROOT/hooks/readonly-context-guard.sh"
HELPER="$SCRIPT_DIR/ensure-readonly-context.sh"

[[ -f "$GUARD"  ]] || { echo "FATAL: guard not found at $GUARD"   >&2; exit 2; }
[[ -f "$HELPER" ]] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.claude/project" "$FIX/research" "$FIX/commands"

# rules.md declares two external connected projects: one plain, and one whose
# declared path carries a ".." segment — the latter proves the guard normalizes
# declared *roots* (not just the target), matching the helper's os.path.normpath.
CONNECTED="$FIX/connected-ref"
CONNECTED_TRAVERSE_DECL="$FIX/ref-parent/child/../real"   # normalizes to $FIX/ref-parent/real
CONNECTED_TRAVERSE="$FIX/ref-parent/real"
# A third bullet in "~/" form: guard (pure Bash) and helper (os.path.expanduser) must
# expand it to the same root, or the helper grants read access to a path the guard
# does not watch. Nothing is written under $HOME — the guard only decides on strings.
HOME_DECL_RAW="~/craft-readonly-fixture"
HOME_DECL="$HOME/craft-readonly-fixture"
cat > "$FIX/.claude/project/rules.md" <<EOF
# Rules
## Read-Only Context Sources (optional)
> Reference material the agent may read but never write.
- $CONNECTED
- $CONNECTED_TRAVERSE_DECL
- $HOME_DECL_RAW
## Self-Verification Settings (optional)
- Max attempts: 5
EOF

# --- guard helpers -----------------------------------------------------------
guard() { # tool  pathkey  path
  printf '{"tool_name":"%s","tool_input":{"%s":"%s"},"cwd":"%s"}' "$1" "$2" "$3" "$FIX" \
    | CLAUDE_PROJECT_DIR="$FIX" bash "$GUARD"
}
deny()  { local o; o="$(guard "$1" "$2" "$3")"; [[ "$o" == *'"permissionDecision":"deny"'* ]] && ok "$4" || bad "$4 (got: ${o:-<empty>})"; }
allow() { local o; o="$(guard "$1" "$2" "$3")"; [[ -z "$o" ]] && ok "$4" || bad "$4 (got: $o)"; }

echo "GUARD:"
deny  Write        file_path     "$FIX/research/x.md"                  "Write into research/ is denied"
deny  Edit         file_path     "$FIX/research/context-mode/README"   "Edit of a nested research file is denied"
deny  NotebookEdit notebook_path "$FIX/research/nb.ipynb"              "NotebookEdit into research/ is denied"
deny  Write        file_path     "$CONNECTED/src/x.md"                 "Write into a declared connected project is denied"
allow Write        file_path     "$FIX/commands/x.md"                  "Write into a normal repo path is allowed"
allow Write        file_path     "/tmp/undeclared-external.md"         "Write into an undeclared external path is allowed"
allow Read         file_path     "$FIX/research/x.md"                  "Read of research/ is allowed (write-tool gate)"
allow Read         file_path     "$CONNECTED/x.md"                     "Read of a connected project is allowed (write-tool gate)"
allow Write        file_path     "$FIX/research-notes/x.md"            "Sibling research-notes/ is not a false-positive match"

# traversal / normalization cases (slice-030): "." / ".." / redundant "/" are
# resolved lexically before the prefix comparison.
deny  Write file_path "$FIX/commands/../research/x.md" "Traversal into research (commands/../research/x) is denied after normalization"
allow Write file_path "$FIX/research/../commands/x.md" "Traversal out of research (research/../commands/x) is allowed after normalization"
deny  Write file_path "$FIX/research/./x.md"           "Dot segment (research/./x) is denied after normalization"
deny  Write file_path "$FIX/research//x.md"            "Redundant slash (research//x) is denied after normalization"
deny  Write file_path "$CONNECTED/sub/../x.md"         "Traversal within a declared connected project is denied after normalization"
deny  Write file_path "$CONNECTED_TRAVERSE/x.md"       "Declared root carrying '..' is normalized, so a write under its canonical form is denied"
deny  Write file_path "$HOME_DECL/x.md"                "Declared '~/' root is expanded, so a write under the real home path is denied"

# guard↔helper normalizer agreement: the guard's own normalize_path (invoked via
# --normalize) must match python3 os.path.normpath on a shared fixture set, so a
# declared path is blocked by the guard exactly as the helper records it. Asserting
# the real guard function (not a copy) is what prevents the two parsers drifting.
# The fixtures deliberately include the inputs where a naive Bash normalizer *does*
# deviate from normpath — empty string, the POSIX "//" root, an embedded newline,
# whitespace and glob characters — since a tripwire that only covers the easy cases
# is not a tripwire.
echo "AGREEMENT:"
for raw in \
  "/a/b/../c" "/a/./b" "/a//b" "a/b/../../c" "research/../commands/x" \
  "$FIX/commands/../research/x.md" "/x/.." "a/.." "./a/b" "/a/b/" \
  "" "//a/b" "///a/b" "//" "/a b/c" "/a/*/b" "/a/.../b" $'/a\nb/c'; do
  g="$(bash "$GUARD" --normalize "$raw")"
  h="$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$raw")"
  [[ "$g" == "$h" ]] && ok "normalizer agrees on '${raw//$'\n'/\\n}' → '${g//$'\n'/\\n}'" || bad "normalizer disagreement on '${raw//$'\n'/\\n}': guard='$g' helper='$h'"
done

# --- helper: check/apply/idempotency/preservation ----------------------------
echo "HELPER:"
# pre-seed settings with unrelated entries that must survive the merge.
cat > "$FIX/.claude/settings.local.json" <<'EOF'
{ "permissions": { "allow": ["Bash(git status:*)"], "additionalDirectories": ["/pre/existing"] } }
EOF

out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --check)"; rc=$?
{ [[ $rc -eq 10 ]] && [[ "$out" == *"STATUS=absent"* ]]; } && ok "--check reports absent (exit 10) when a declared path is untrusted" || bad "--check absent (rc=$rc)"

out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=yes"* ]]; } && ok "--apply merges the declared path (exit 0, CHANGED=yes)" || bad "--apply (rc=$rc, out=$out)"

# preservation + correct new entry
python3 - "$FIX/.claude/settings.local.json" "$CONNECTED" <<'PY' && ok "existing settings preserved and new path added" || bad "settings merge lost data"
import json, sys
d = json.load(open(sys.argv[1])); ad = d["permissions"]["additionalDirectories"]
sys.exit(0 if ("/pre/existing" in ad and sys.argv[2] in ad and d["permissions"]["allow"] == ["Bash(git status:*)"]) else 1)
PY

# Pipeline agreement: the roots the helper *records* must be the roots the guard
# *blocks* — the normalizer-agreement loop above only proves normalize_path itself
# agrees, not that the bullet→root pipeline (tilde expansion, relative-join,
# normalization) lands on the same string on both sides. The guard's deny cases
# above prove it blocks $CONNECTED_TRAVERSE and $HOME_DECL; this asserts the helper
# grants read access to exactly those, and not to some divergent spelling.
python3 - "$FIX/.claude/settings.local.json" "$CONNECTED_TRAVERSE" "$HOME_DECL" <<'PY' && ok "helper records the same roots the guard blocks ('..'-bearing and '~/' bullets)" || bad "guard↔helper pipeline divergence: a declared root is readable but unguarded"
import json, sys
ad = json.load(open(sys.argv[1]))["permissions"]["additionalDirectories"]
sys.exit(0 if (sys.argv[2] in ad and sys.argv[3] in ad) else 1)
PY

out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --check)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"STATUS=present"* ]]; } && ok "--check reports present (exit 0) after apply" || bad "--check present (rc=$rc)"

out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --apply)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"CHANGED=no"* ]]; } && ok "--apply is idempotent (CHANGED=no on re-run)" || bad "--apply idempotency (out=$out)"

grep -q '^\.claude/settings\.local\.json$' "$FIX/.gitignore" && ok "settings.local.json is gitignored" || bad "gitignore not updated"

# corrupt settings.local.json → helper must refuse (non-zero) and leave the file untouched.
printf '{ this is not valid json' > "$FIX/.claude/settings.local.json"
before="$(cat "$FIX/.claude/settings.local.json")"
CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --apply >/dev/null 2>&1; rc=$?
after="$(cat "$FIX/.claude/settings.local.json")"
{ [[ $rc -ne 0 ]] && [[ "$before" == "$after" ]]; } && ok "corrupt settings.local.json → --apply refuses (non-zero) and leaves file untouched" || bad "corrupt-settings refusal (rc=$rc, changed=$([[ "$before" == "$after" ]] && echo no || echo yes))"
printf '{}' > "$FIX/.claude/settings.local.json"   # restore a valid file for the next case

# no declarations → silent present
cat > "$FIX/.claude/project/rules.md" <<'EOF'
# Rules
## Read-Only Context Sources (optional)
> note
(no connected projects declared)
## Self-Verification Settings (optional)
EOF
out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HELPER" --check)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"DECLARED=0"* ]]; } && ok "--check with no declarations is a clean no-op (DECLARED=0, exit 0)" || bad "no-declaration case (rc=$rc, out=$out)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
