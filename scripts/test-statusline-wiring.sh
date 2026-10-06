#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-statusline-wiring.sh — harness for scripts/ensure-statusline-tap.sh (slice-059, D36)
#
# Self-contained: every case runs against mktemp fixtures — a fixture $HOME with its own ~/.claude
# (settings.json, plugins/known_marketplaces.json, a marketplace clone carrying the real statusline-tap.sh),
# a fixture project and a fixture managed-settings directory. CLAUDE_CONFIG_DIR is unset for every helper run,
# so nothing outside the mktemp directory is read or written (removed on exit).
#
# Covers: every --check state and that --check never writes; --apply for plain and compound commands, the
# re-route of a misrouted tap (inner command kept, a broken compound wrapped), refreshInterval added / kept,
# other keys, indentation, a symlinked file and the file mode preserved, idempotency, the backup byte-equal;
# every refusal writes nothing; --apply → --remove restores each original command; the written command really
# runs — executed with a JSON on stdin, its output equal to the original command's and the tap file written;
# and the pinned call sites in commands/prime.md and commands/onboard.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/ensure-statusline-tap.sh"
TAPPER="$SCRIPT_DIR/statusline-tap.sh"
for f in "$HELPER" "$TAPPER"; do
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
H="$ROOT/home"
CFG="$H/.claude"
MKT="$CFG/plugins/marketplaces/craft"
PRJ="$ROOT/proj"
MANAGED="$ROOT/managed"
S="$CFG/settings.json"
TAPW="~/.claude/plugins/marketplaces/craft/scripts/statusline-tap.sh"   # how the helper writes the tap path

reset() { # a fresh fixture: marketplace clone with the tap, known_marketplaces.json, no settings file
  rm -rf "$H" "$PRJ" "$MANAGED"
  mkdir -p "$MKT/.claude-plugin" "$MKT/scripts" "$PRJ/.claude" "$MANAGED"
  printf '{"name":"craft","plugins":[{"name":"craft","source":"./"}]}\n' > "$MKT/.claude-plugin/marketplace.json"
  cp "$TAPPER" "$MKT/scripts/statusline-tap.sh"
  printf '{"craft":{"source":{"source":"github","repo":"x/craft"},"installLocation":"%s"}}\n' "$MKT" \
    > "$CFG/plugins/known_marketplaces.json"
}
settings() { printf '%s\n' "$1" > "$S"; }   # <json>
sl() { # <command> [refresh] — a settings file with just a statusLine
  python3 -c 'import json,sys
d={"type":"command","command":sys.argv[1]}
if len(sys.argv)>2: d["refreshInterval"]=int(sys.argv[2])
print(json.dumps({"statusLine":d},indent=2))' "$@" > "$S"
}
run() { (cd "$PRJ" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_PROJECT_DIR HOME="$H" CRAFT_TEST_MANAGED_DIR="$MANAGED" \
  bash "$HELPER" --project "$PRJ" "$@" 2>&1); }
rc() { (cd "$PRJ" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_PROJECT_DIR HOME="$H" CRAFT_TEST_MANAGED_DIR="$MANAGED" \
  bash "$HELPER" --project "$PRJ" "$@" >/dev/null 2>&1); echo $?; }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
jget() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d.get(k) if isinstance(d,dict) else None
print("<none>" if d is None else d)' "$S" "$1"; }
sig() { python3 -c 'import os,sys,hashlib
p=sys.argv[1]
print(hashlib.sha256(open(p,"rb").read()).hexdigest() if os.path.exists(p) else "-", os.stat(p).st_mtime_ns if os.path.exists(p) else "-")' "$S"; }
backups() { ls "$CFG" | grep -c '^settings.json.bak-craft-' ; }
section() { awk -v h="$2" 'index($0, h) == 1 {p=1; next} /^##+ /{p=0} p' "$1"; }   # <file> <heading prefix>
has() { if grep -qiE -- "$2"; then echo yes; else echo no; fi <<<"$1"; }          # <text> <ERE>

echo "== --check: every state"
reset
out="$(run --check)"
expect "no settings file → absent"            "$(val "$out" STATUS)" "absent"
expect "absent → exit 10"                      "$(rc --check)" "10"
expect "PROPOSED is the bare tap"              "$(val "$out" PROPOSED)" "sh $TAPW"
expect "TAP_PATH is the marketplace clone's"   "$(val "$out" TAP_PATH)" "$MKT/scripts/statusline-tap.sh"
settings '{"model":"opus"}'
expect "settings without statusLine → absent"  "$(val "$(run --check)" STATUS)" "absent"
sl "sh ~/.claude/my.sh" 30
out="$(run --check)"
expect "a plain own command → absent"          "$(val "$out" STATUS)" "absent"
expect "PROPOSED chains it behind the tap"     "$(val "$out" PROPOSED)" "sh $TAPW sh ~/.claude/my.sh"
sl "sh /work/CRAFT/scripts/statusline-tap.sh sh ~/.claude/my.sh" 30
out="$(run --check)"
expect "a working-tree tap → misrouted"        "$(val "$out" STATUS)" "misrouted"
expect "misrouted keeps the inner command"     "$(val "$out" PROPOSED)" "sh $TAPW sh ~/.claude/my.sh"
expect "misrouted → exit 10"                   "$(rc --check)" "10"
sl "sh ~/.claude/plugins/cache/craft/craft/1.6.0/scripts/statusline-tap.sh -- ccstatusline" 30
out="$(run --check)"
expect "a versioned cache tap → misrouted"     "$(val "$out" STATUS)" "misrouted"
expect "a -- separator is dropped"             "$(val "$out" PROPOSED)" "sh $TAPW ccstatusline"
sl "sh $TAPW ccstatusline"
expect "wired without refreshInterval → no-refresh" "$(val "$(run --check)" STATUS)" "no-refresh"
expect "no-refresh → exit 10"                  "$(rc --check)" "10"
sl "sh $TAPW ccstatusline" 30
expect "wired"                                 "$(val "$(run --check)" STATUS)" "wired"
expect "wired → exit 0"                        "$(rc --check)" "0"
sl "bash $MKT/scripts/statusline-tap.sh ccstatusline" 30
expect "an absolute path and bash count as wired" "$(val "$(run --check)" STATUS)" "wired"
sl "$MKT/scripts/statusline-tap.sh ccstatusline" 30
expect "the tap run directly counts as wired"  "$(val "$(run --check)" STATUS)" "wired"
sl "sh ~/.claude/my.sh" 30
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$PRJ/.claude/settings.json"
out="$(run --check)"
expect "a project statusLine → overridden"     "$(val "$out" STATUS)" "overridden"
expect "OVERRIDDEN_BY names the file"          "$(val "$out" OVERRIDDEN_BY)" "$PRJ/.claude/settings.json"
expect "overridden → exit 11"                  "$(rc --check)" "11"
expect "overridden proposes nothing"           "$(val "$out" PROPOSED)" ""
rm "$PRJ/.claude/settings.json"
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$PRJ/.claude/settings.local.json"
expect "a local statusLine → overridden"       "$(val "$(run --check)" STATUS)" "overridden"
rm "$PRJ/.claude/settings.local.json"
mkdir -p "$MANAGED/managed-settings.d"
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$MANAGED/managed-settings.d/10-x.json"
expect "a managed drop-in statusLine → overridden" "$(val "$(run --check)" STATUS)" "overridden"
rm -rf "$MANAGED/managed-settings.d"
printf '{"model":"opus"}\n' > "$PRJ/.claude/settings.json"
expect "a project file without statusLine does not override" "$(val "$(run --check)" STATUS)" "absent"
rm "$PRJ/.claude/settings.json"
rm "$MKT/scripts/statusline-tap.sh"
out="$(run --check)"
expect "the clone has no tap yet → tap-missing" "$(val "$out" STATUS)" "tap-missing"
expect "tap-missing → exit 11"                 "$(rc --check)" "11"
expect "tap-missing says the clone predates it" "$(val "$out" REASON | grep -c 'predates the release')" "1"
reset
rm "$CFG/plugins/known_marketplaces.json"
expect "no known_marketplaces.json → tap-missing" "$(val "$(run --check)" STATUS)" "tap-missing"
reset
printf '{"other":{"installLocation":"%s"}}\n' "$ROOT/nowhere" > "$CFG/plugins/known_marketplaces.json"
expect "no marketplace carries craft → tap-missing" "$(val "$(run --check)" STATUS)" "tap-missing"
reset
sl "cd /x && sh /work/scripts/statusline-tap.sh foo" 30
expect "a tap not at the start → unrecognized" "$(val "$(run --check)" STATUS)" "unrecognized"
expect "unrecognized → exit 11"                "$(rc --check)" "11"
sl "sh '/work/scripts/statusline-tap.sh foo" 30
expect "an unbalanced quote → unrecognized"    "$(val "$(run --check)" STATUS)" "unrecognized"
settings '{"statusLine":"sh x"}'
expect "a statusLine that is no object → unrecognized" "$(val "$(run --check)" STATUS)" "unrecognized"
sl "sh ~/.claude/my.sh" 30
before="$(sig)"; run --check >/dev/null; expect "--check never writes" "$(sig)" "$before"
settings '{"statusLine": {'
before="$(sig)"
expect "broken JSON → exit 5"                  "$(rc --check)" "5"
expect "broken JSON is left as is"             "$(sig)" "$before"

echo "== --apply"
reset
printf '{\n    "model": "opus",\n    "permissions": {\n        "deny": ["Bash(rm:*)"]\n    },\n    "statusLine": {\n        "type": "command",\n        "command": "a | b",\n        "padding": 0\n    }\n}\n' > "$S"
cp "$S" "$ROOT/orig.json"
out="$(run --apply)"
expect "apply → CHANGED=yes"                   "$(val "$out" CHANGED)" "yes"
expect "a pipe is wrapped in sh -c"            "$(jget statusLine.command)" "sh $TAPW sh -c 'a | b'"
expect "refreshInterval added"                 "$(jget statusLine.refreshInterval)" "30"
expect "padding kept"                          "$(jget statusLine.padding)" "0"
expect "model kept"                            "$(jget model)" "opus"
expect "permissions kept"                      "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["permissions"]["deny"])' "$S")" "['Bash(rm:*)']"
expect "the 4-space indent kept"               "$(sed -n 2p "$S" | grep -c '^    "model"')" "1"
expect "the backup is named"                   "$(val "$out" BACKUP | grep -c 'settings.json.bak-craft-')" "1"
expect "the backup is byte-equal"              "$(cmp -s "$(val "$out" BACKUP)" "$ROOT/orig.json" && echo same)" "same"
expect "after apply --check → wired"           "$(val "$(run --check)" STATUS)" "wired"
before="$(sig)"
out="$(run --apply)"
expect "a second apply → CHANGED=no"           "$(val "$out" CHANGED)" "no"
expect "a second apply writes nothing"         "$(sig)" "$before"
expect "a second apply takes no backup"        "$(backups)" "1"

reset
sl "sh ~/.claude/my.sh" 10
run --apply >/dev/null
expect "an existing refreshInterval is kept"   "$(jget statusLine.refreshInterval)" "10"
expect "a plain command is not wrapped"        "$(jget statusLine.command)" "sh $TAPW sh ~/.claude/my.sh"
reset
sl "sh $TAPW ccstatusline"
run --apply >/dev/null
expect "no-refresh: only refreshInterval added" "$(jget statusLine.command)|$(jget statusLine.refreshInterval)" "sh $TAPW ccstatusline|30"
reset
run --apply >/dev/null
expect "no file: one is created with the bare tap" "$(jget statusLine.command)|$(jget statusLine.type)" "sh $TAPW|command"
expect "no file: no backup"                    "$(backups)" "0"
reset
sl "sh /work/CRAFT/scripts/statusline-tap.sh sh ~/.claude/my.sh" 30
run --apply >/dev/null
expect "misrouted: re-routed, inner kept"      "$(jget statusLine.command)" "sh $TAPW sh ~/.claude/my.sh"
reset
sl "sh /work/CRAFT/scripts/statusline-tap.sh a | b" 30
run --apply >/dev/null
expect "misrouted: a broken compound behind it is wrapped" "$(jget statusLine.command)" "sh $TAPW sh -c 'a | b'"

reset
mkdir -p "$ROOT/dotfiles"
printf '{"statusLine":{"type":"command","command":"ccstatusline"}}\n' > "$ROOT/dotfiles/settings.json"
ln -s "$ROOT/dotfiles/settings.json" "$S"
chmod 600 "$ROOT/dotfiles/settings.json"
run --apply >/dev/null
expect "a symlinked settings file stays a symlink" "$([[ -L "$S" ]] && echo link)" "link"
expect "the link's target is written"          "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$ROOT/dotfiles/settings.json")" "sh $TAPW ccstatusline"
expect "the file mode is kept"                 "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$ROOT/dotfiles/settings.json")" "0o600"

echo "== refusals write nothing"
reset
sl "sh ~/.claude/my.sh" 30
rm "$MKT/scripts/statusline-tap.sh"
before="$(sig)"
expect "tap-missing: apply → exit 11"          "$(rc --apply)" "11"
expect "tap-missing: nothing written"          "$(sig)" "$before"
reset
sl "sh ~/.claude/my.sh" 30
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$PRJ/.claude/settings.local.json"
before="$(sig)"
expect "overridden: apply → exit 11"           "$(rc --apply)" "11"
expect "overridden: nothing written"           "$(sig)" "$before"
reset
sl "cd /x && sh /work/scripts/statusline-tap.sh foo" 30
before="$(sig)"
expect "unrecognized: apply → exit 11"         "$(rc --apply)" "11"
expect "unrecognized: remove → exit 11"        "$(rc --remove)" "11"
expect "unrecognized: nothing written"         "$(sig)" "$before"
settings '{"statusLine": {'
before="$(sig)"
expect "broken JSON: apply → exit 5"           "$(rc --apply)" "5"
expect "broken JSON: nothing written"          "$(sig)" "$before"
expect "no backup taken by a refusal"          "$(backups)" "0"

echo "== --remove and the round trip"
# Each fixture: the original command, as Claude Code would run it.
FIXTURES=(
  'sh ~/.claude/my.sh'
  'cat | tr a-z A-Z'
  'a=$(cat); echo "got ${#a}"'
  'cat && echo done'
  'X=1 sh -c '"'"'cat; echo $X'"'"''
  'printf "%s\n" "it'"'"'s" ; cat'
  "jq -r '.model.display_name'"
  'echo `cat | wc -c`'
)
for f in "${FIXTURES[@]}"; do
  reset
  sl "$f"
  run --apply >/dev/null
  out="$(run --remove)"
  expect "round trip: $f" "$(jget statusLine.command)" "$f"
done
reset
sl "ccstatusline" 30
run --apply >/dev/null
out="$(run --remove)"
expect "remove → CHANGED=yes"                  "$(val "$out" CHANGED)" "yes"
expect "remove names what it restored"         "$(val "$out" RESTORED)" "ccstatusline"
expect "remove keeps refreshInterval"          "$(jget statusLine.refreshInterval)" "30"
expect "remove takes a backup"                 "$(backups)" "2"
out="$(run --remove)"
expect "remove without a tap → CHANGED=no"     "$(val "$out" CHANGED)" "no"
reset
run --apply >/dev/null
run --remove >/dev/null
expect "remove of a bare tap drops statusLine" "$(jget statusLine)" "<none>"
reset
sl "sh /work/CRAFT/scripts/statusline-tap.sh sh ~/.claude/my.sh" 30
run --remove >/dev/null
expect "remove works on a misrouted tap"       "$(jget statusLine.command)" "sh ~/.claude/my.sh"
reset
sl "sh ~/.claude/plugins/marketplaces/craft/scripts/statusline-tap.sh sh -c 'cat | wc -l'" 30
rm "$MKT/scripts/statusline-tap.sh"
run --remove >/dev/null
expect "remove works while the tap is missing" "$(jget statusLine.command)" "cat | wc -l"

echo "== a foreign statusline-tap.sh is the user's own command (BUG-1)"
# The user's own statusline script may carry the tap's name (this repo's author ran one before slice-058). CRAFT's
# tap is recognised by its path or its content, a missing file only by CRAFT's ".../scripts/statusline-tap.sh" layout.
own() { mkdir -p "$CFG"; printf '#!/bin/sh\nccstatusline\n' > "$CFG/statusline-tap.sh"; }       # a foreign script
WT="$ROOT/wt/scripts/statusline-tap.sh"
wt() { mkdir -p "$(dirname "$WT")"; cp "$TAPPER" "$WT"; }                                            # CRAFT's, elsewhere
reset; own
sl "sh ~/.claude/statusline-tap.sh" 30
out="$(run --check)"
expect "BUG-1: a foreign statusline-tap.sh → absent"     "$(val "$out" STATUS)" "absent"
expect "BUG-1: it is chained behind the tap"             "$(val "$out" PROPOSED)" "sh $TAPW sh ~/.claude/statusline-tap.sh"
run --apply >/dev/null
expect "BUG-1: apply chains it"                          "$(jget statusLine.command)" "sh $TAPW sh ~/.claude/statusline-tap.sh"
expect "BUG-1: after apply → wired"                      "$(val "$(run --check)" STATUS)" "wired"
expect "BUG-1: remove → exit 0"                          "$(rc --remove)" "0"
expect "BUG-1: remove restores the foreign command"      "$(jget statusLine.command)" "sh ~/.claude/statusline-tap.sh"
expect "BUG-1: after remove → absent"                    "$(val "$(run --check)" STATUS)" "absent"
reset; own
sl "sh $CFG/statusline-tap.sh --compact" 30
expect "BUG-1: a foreign one with arguments → absent"    "$(val "$(run --check)" STATUS)" "absent"
reset; own; wt
sl "sh $WT sh ~/.claude/statusline-tap.sh" 30
out="$(run --check)"
expect "BUG-1: CRAFT's tap elsewhere (by content) → misrouted" "$(val "$out" STATUS)" "misrouted"
expect "BUG-1: the foreign inner command is kept"        "$(val "$out" PROPOSED)" "sh $TAPW sh ~/.claude/statusline-tap.sh"
run --apply >/dev/null
expect "BUG-1: the real shape: remove → exit 0"          "$(rc --remove)" "0"
expect "BUG-1: the real shape: remove restores the inner" "$(jget statusLine.command)" "sh ~/.claude/statusline-tap.sh"
reset
sl "sh ~/bin/statusline-tap.sh" 30
expect "BUG-1: a missing file outside CRAFT's layout → absent" "$(val "$(run --check)" STATUS)" "absent"
reset; wt
sl "cd /x && sh $WT foo" 30
expect "BUG-1: CRAFT's tap (by content) not first → unrecognized" "$(val "$(run --check)" STATUS)" "unrecognized"
reset; own
sl "cd /x && sh ~/.claude/statusline-tap.sh" 30
out="$(run --check)"
expect "BUG-1: a foreign one not first → absent"         "$(val "$out" STATUS)" "absent"
expect "BUG-1: … and wrapped as the user's command"      "$(val "$out" PROPOSED)" "sh $TAPW sh -c 'cd /x && sh ~/.claude/statusline-tap.sh'"

echo "== review round 1 (R1-1 … R1-7)"
mkt() { # <dir> — a marketplace clone carrying craft and the real tap
  mkdir -p "$1/.claude-plugin" "$1/scripts"
  printf '{"name":"x","plugins":[{"name":"craft","source":"./"}]}\n' > "$1/.claude-plugin/marketplace.json"
  cp "$TAPPER" "$1/scripts/statusline-tap.sh"
}
DEV="$ROOT/dev"
reset; mkt "$DEV"
printf '{"dev":{"installLocation":"%s"},"craft":{"installLocation":"%s"}}\n' "$DEV" "$MKT" > "$CFG/plugins/known_marketplaces.json"
expect "R1-1: the entry named craft beats an earlier dev marketplace" "$(val "$(run --check)" TAP_PATH)" "$MKT/scripts/statusline-tap.sh"
printf '{"version":2,"plugins":{"craft@craft":[{"scope":"user","installPath":"x"}]}}\n' > "$CFG/plugins/installed_plugins.json"
sl "sh $DEV/scripts/statusline-tap.sh ccstatusline" 30
expect "R1-1: a tap on the dev marketplace is misrouted" "$(val "$(run --check)" STATUS)" "misrouted"
printf '{"version":2,"plugins":{"craft@dev":[{"scope":"project","installPath":"x"}],"craft@craft":[{"scope":"user","installPath":"y"}]}}\n' > "$CFG/plugins/installed_plugins.json"
expect "R1-1: the user-scope install's marketplace wins" "$(val "$(run --check)" TAP_PATH)" "$MKT/scripts/statusline-tap.sh"
printf '{"version":2,"plugins":{"craft@dev":[{"scope":"user","installPath":"x"}]}}\n' > "$CFG/plugins/installed_plugins.json"
expect "R1-1: craft installed from dev → dev's tap is the target" "$(val "$(run --check)" TAP_PATH)" "$DEV/scripts/statusline-tap.sh"

SPACE="$ROOT/my mkt"
reset; mkt "$SPACE"
printf '{"craft":{"installLocation":"%s"}}\n' "$SPACE" > "$CFG/plugins/known_marketplaces.json"
sl "ccstatusline" 30
expect "R1-4: a clone outside \$HOME is written quoted" "$(val "$(run --check)" PROPOSED)" "sh '$SPACE/scripts/statusline-tap.sh' ccstatusline"
run --apply >/dev/null
expect "R1-4: … and reads as wired"           "$(val "$(run --check)" STATUS)" "wired"
printf '{"a":1}' | env -u CRAFT_USAGE_TAP -u CLAUDE_CONFIG_DIR HOME="$H" PATH="$PATH" sh -c "$(jget statusLine.command | sed 's/ ccstatusline$//')" >/dev/null 2>&1
expect "R1-4: … and the quoted tap runs"      "$(cat "$CFG/craft/usage-tap.json" 2>/dev/null)" '{"a":1}'

reset
printf '{\n\t"model": "opus",\n\t"statusLine": {\n\t\t"type": "command",\n\t\t"command": "ccstatusline"\n\t}\n}\n' > "$S"
run --apply >/dev/null
expect "R1-4: tab indentation kept"           "$(sed -n 2p "$S" | grep -c "$(printf '^\t"model"')")" "1"

reset
sl "ccstatusline" 30
chmod 500 "$CFG"
before="$(sig)"
expect "R1-3: a failed write → exit 7"        "$(rc --apply)" "7"
expect "R1-3: … names the failure"            "$(run --apply | grep -c '^ERROR=write_failed:')" "1"
chmod 700 "$CFG"
expect "R1-3: … and leaves the file unchanged" "$(sig)" "$before"

reset
mkdir -p "$ROOT/other/scripts"; printf '#!/bin/sh\nccstatusline\n' > "$ROOT/other/scripts/statusline-tap.sh"
sl "sh $ROOT/other/scripts/statusline-tap.sh" 30
expect "R1-4: a foreign scripts/statusline-tap.sh that exists → absent" "$(val "$(run --check)" STATUS)" "absent"

reset
sl "$(printf 'echo hi\nsh %s x' "$TAPW")" 30
expect "R1-2: a tap on the next line → unrecognized" "$(val "$(run --check)" STATUS)" "unrecognized"
sl "bash -c 'sh $MKT/scripts/statusline-tap.sh foo'" 30
expect "R1-2: a tap inside sh -c → unrecognized" "$(val "$(run --check)" STATUS)" "unrecognized"
sl "sh $TAPW sh /old/scripts/statusline-tap.sh foo" 30
expect "R1-2: a double tap → unrecognized"    "$(val "$(run --check)" STATUS)" "unrecognized"
before="$(sig)"
expect "R1-2: … remove refuses it (exit 11)"  "$(rc --remove)" "11"
expect "R1-2: … and writes nothing"           "$(sig)" "$before"

reset
sl "ccstatusline" 30
out="$(run --apply)"
expect "R1-3: after apply STATUS is the written state" "$(val "$out" STATUS)|$(val "$out" WIRING)" "wired|ok"
expect "R1-3: … STATUS_BEFORE names the start" "$(val "$out" STATUS_BEFORE)" "absent"
expect "R1-5: … TAP_CURRENT names the tap"    "$(val "$out" TAP_CURRENT)" "$TAPW"
out="$(run --remove)"
expect "R1-3: after remove STATUS is absent"  "$(val "$out" STATUS)|$(val "$out" STATUS_BEFORE)" "absent|wired"
reset
out="$(run --apply)"
expect "R1-6: no file → BACKUP=-"             "$(val "$out" BACKUP)" "-"

reset; own; wt
sl "sh $WT sh ~/.claude/statusline-tap.sh" 30
expect "R1-5: TAP_CURRENT is CRAFT's tap, not the foreign one" "$(val "$(run --check)" TAP_CURRENT)" "$WT"
sl "ccstatusline" 30
expect "R1-5: no TAP_CURRENT without a tap"   "$(val "$(run --check)" TAP_CURRENT)" ""

reset
sl "ccstatusline" 30
printf '{"statusLine":{"type":"command","command":"sh %s x","refreshInterval":30}}\n' "$TAPW" > "$PRJ/.claude/settings.json"
out="$(run --check)"
expect "R1-7: an override that runs the tap → OVERRIDE_WIRED=yes" "$(val "$out" STATUS)|$(val "$out" OVERRIDE_WIRED)" "overridden|yes"
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$PRJ/.claude/settings.local.json"
expect "R1-7: local wins over project → OVERRIDE_WIRED=no" "$(val "$(run --check)" OVERRIDE_WIRED)" "no"
expect "R1-7: local is named first"           "$(val "$(run --check)" OVERRIDDEN_BY)" "$PRJ/.claude/settings.local.json"

echo "== review round 2 (R2)"
reset
mkdir -p "$ROOT/x/my scripts"; printf '#!/bin/sh\nccstatusline\n' > "$ROOT/x/my scripts/statusline-tap.sh"
sl "sh \"$ROOT/x/my scripts/statusline-tap.sh\"" 30
expect "R2: a quoted foreign path with a space → absent, not unrecognized" "$(val "$(run --check)" STATUS)" "absent"
reset
sl "ccstatusline" 30
chmod 500 "$CFG"
out="$(run --apply)"
chmod 700 "$CFG"
expect "R2: a failed backup names no backup"   "$(printf '%s\n' "$out" | grep -c 'backup: -)')" "1"
expect "R2: … and leaves no temp file"         "$(ls -a "$CFG" | grep -c 'craft-tmp')" "0"
reset
sl "ccstatusline" 30
mkdir -p "$MANAGED/managed-settings.d"
printf '{"statusLine":{"type":"command","command":"x"}}\n' > "$MANAGED/managed-settings.json"
printf '{"statusLine":{"type":"command","command":"sh %s x","refreshInterval":30}}\n' "$TAPW" > "$MANAGED/managed-settings.d/10-tap.json"
out="$(run --check)"
expect "R2: the last drop-in beats managed-settings.json" "$(val "$out" OVERRIDDEN_BY)|$(val "$out" OVERRIDE_WIRED)" "$MANAGED/managed-settings.d/10-tap.json|yes"
printf '{"statusLine":{"type":"command","command":"y"}}\n' > "$MANAGED/managed-settings.d/20-other.json"
out="$(run --check)"
expect "R2: a later drop-in wins over an earlier one" "$(val "$out" OVERRIDDEN_BY)|$(val "$out" OVERRIDE_WIRED)" "$MANAGED/managed-settings.d/20-other.json|no"
reset
sl "ccstatusline" 30
printf '{"statusLine":{"type":"command","command":"sh %s x"}}\n' "$TAPW" > "$PRJ/.claude/settings.json"
expect "R2: an override with the tap but no refreshInterval is not wired" "$(val "$(run --check)" OVERRIDE_WIRED)" "no"
expect "R2: prime 4h offers no copy after exit 6 without a backup" "$(has "$(section "$REPO_ROOT/commands/prime.md" '### 4h. ')" 'backup: -`, the file did not exist')" "yes"
expect "R2: prime 4h says the whole statusLine key goes"  "$(has "$(section "$REPO_ROOT/commands/prime.md" '### 4h. ')" 'the whole `statusLine` key is gone')" "yes"

echo "== the written command really runs"
# Run the original command and the wired one the way Claude Code does (sh -c, the JSON on stdin) and compare.
# Fixture programs: ~/.claude/my.sh echoes its stdin reversed by line count; jq is replaced by a stub on PATH.
BIN="$ROOT/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\npython3 -c "import json,sys;print(json.load(sys.stdin)[\\"model\\"][\\"display_name\\"])"\n' > "$BIN/jq"
chmod +x "$BIN/jq"
JSON='{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12}}}'
for f in "${FIXTURES[@]}"; do
  reset
  printf '#!/bin/sh\nprintf "my:"; wc -c\n' > "$CFG/my.sh"
  sl "$f"
  run --apply >/dev/null
  wired="$(jget statusLine.command)"
  want="$(printf '%s' "$JSON" | env HOME="$H" PATH="$BIN:$PATH" sh -c "$f" 2>&1)"
  rm -f "$CFG/craft/usage-tap.json"
  got="$(printf '%s' "$JSON" | env -u CRAFT_USAGE_TAP -u CLAUDE_CONFIG_DIR HOME="$H" PATH="$BIN:$PATH" sh -c "$wired" 2>&1)"
  expect "runs like the original: $f"   "$got" "$want"
  expect "and writes the tap: $f"       "$(cat "$CFG/craft/usage-tap.json" 2>/dev/null)" "$JSON"
done

echo "== pinned call sites"
P="$REPO_ROOT/commands/prime.md"
O="$REPO_ROOT/commands/onboard.md"
H4H="$(section "$P" '### 4h. ')"
expect "prime has step 4h"                     "$(grep -c '^### 4h\. ' "$P")" "1"
expect "prime 4h names the helper"            "$(has "$H4H" 'scripts/ensure-statusline-tap\.sh')" "yes"
expect "prime 4h runs it with --check"        "$(has "$H4H" '^bash "<helper>" --project "<project-root>" --check$')" "yes"
expect "prime 4h offers --apply"               "$(has "$H4H" '[-]-apply')" "yes"
expect "prime 4h writes only on a yes"         "$(has "$H4H" 'on a yes')" "yes"
expect "prime 4h never offers --remove unasked" "$(has "$H4H" 'never offer')" "yes"
expect "prime 4h names TAP_CURRENT, not CURRENT, for a misroute (R1-5)" "$(has "$H4H" 'from `<TAP_CURRENT>`')" "yes"
expect "prime 4h reads OVERRIDE_WIRED (R1-7)"   "$(has "$H4H" 'OVERRIDE_WIRED=yes')" "yes"
expect "prime 4h offers the backup back after exit 6 (R1-8)" "$(has "$H4H" 'exits 6.*was written but did not check out')" "yes"
expect "prime 4h maps --remove's outcomes (R1-9)" "$(has "$H4H" 'Statusline tap removed')" "yes"
expect "prime 4h reports absent as a · line (R1-11)" "$(has "$H4H" '^- \*\*`STATUS=absent`\*\* \(exit 10\) → `· ')" "yes"
expect "prime 4d's no-tap hint points at 4h"   "$(has "$(section "$P" '### 4d. ')" 'step 4h')" "yes"
expect "prime's Output Format has the tap line" "$(has "$(section "$P" '## Output Format')" 'Statusline tap')" "yes"
ONB="$(section "$O" '## Statusline Tap')"
expect "onboard has the Statusline Tap sub-procedure" "$(grep -c '^## Statusline Tap (shared sub-procedure)' "$O")" "1"
expect "onboard runs prime's step 4h"         "$(has "$ONB" 'commands/prime\.md` → \*\*step 4h\*\*')" "yes"
expect "onboard does not restate the helper"   "$(has "$ONB" 'ensure-statusline-tap')" "no"
expect "both onboard modes run it"             "$(grep -c 'Statusline Tap sub-procedure' "$O" | awk '{print ($1 >= 2) ? "yes" : "no"}')" "yes"

echo "== usage"
expect "an unknown argument → exit 2"          "$(rc --bogus)" "2"
expect "--project without a value → exit 2"    "$(rc --project)" "2"
NOPY="$ROOT/nopy"
mkdir -p "$NOPY"
for t in git uname dirname; do p="$(command -v "$t")" && ln -s "$p" "$NOPY/$t"; done
expect "no python3 → exit 3"                   "$( (cd "$PRJ" && env -i HOME="$H" PATH="$NOPY" "$(command -v bash)" "$HELPER" --check >/dev/null 2>&1); echo $?)" "3"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "RESULT: $PASS passed, 0 failed"
  exit 0
fi
echo "RESULT: $PASS passed, $FAIL failed"
exit 1
