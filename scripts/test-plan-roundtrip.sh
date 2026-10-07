#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-plan-roundtrip.sh — self-contained tests for scripts/plan-roundtrip.sh (B15, slice-067):
# parallel worktree mode's plan round trip (hand-in, read-back, release) and the slice commit
# that /craft:execute step 6 makes inside the worktree before the read-back.
#
# No test runner exists in this repo (plugin assets, not runtime software), so this harness
# stands alone: each case builds a throwaway repository with real `git worktree add` fixtures
# under a mktemp -d root, drives the helper and asserts on its KEY=VALUE output. The lifecycle
# cases run every git command the command prose prescribes — from the hand-in to a landed merge
# and a removed worktree — in a root project with the CRAFT ignore block, in one without a
# `.craft/` ignore and in a subdirectory project without the block. It also pins the sites in
# commands/execute.md, commands/commit.md and agents/slice-builder.md that call the helper.
# Run it directly:
#
#   bash scripts/test-plan-roundtrip.sh
#
# It writes nothing outside its own mktemp directory (removed on exit by the trap below — an
# `rm` in a script file, never an agent-issued command, D34). The fixtures themselves remove
# nothing: the premise cases that must show a refused `git worktree remove` use git's own refusal.
# What it cannot show: that a real /craft:execute master composes the step-6 commits, and that
# /craft:commit picks Slice-finalize from the read-back plan (command prose; slice-067 → Test
# Strategy names the hands-on run).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/plan-roundtrip.sh"
DIRT="$SCRIPT_DIR/tree-dirt-state.sh"
CLOSE="$SCRIPT_DIR/close-file.sh"
EXECUTE="$REPO_ROOT/commands/execute.md"
COMMIT="$REPO_ROOT/commands/commit.md"
BUILDER="$REPO_ROOT/agents/slice-builder.md"
for f in "$DIRT" "$CLOSE" "$EXECUTE" "$COMMIT" "$BUILDER"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP/home" "$TMP/managed"
# close-file.sh asks delete-mode.sh which settings levels hold a rule: an empty home, no managed file
closer() { HOME="$TMP/home" CRAFT_TEST_MANAGED_DIR="$TMP/managed" bash "$CLOSE" "$@" 2>&1; }

# ── fixtures ────────────────────────────────────────────────────────────────
N=0
REPO=""; PROJ=""; PFX=""; WT=""; WPROJ=""
SLICE_REL=".claude/plans/slice-001-a.md"   # project-relative
CRAFT_BLOCK="$(bash "$SCRIPT_DIR/ensure-gitignore.sh" --print-paths)"
[[ -n "$CRAFT_BLOCK" ]] || { echo "FATAL: ensure-gitignore.sh --print-paths printed nothing" >&2; exit 2; }

# fixture <block|noignore|plans-ignored|subdir>
#   block         project at the repository root, .gitignore holds the CRAFT local-state block
#   noignore      root project, the block minus `.craft/` and `.claude/plans/.closed/`
#   plans-ignored root project, only `.claude/plans/` ignored (the status stays empty after a hand-in)
#   bare          project at the repository root, no .gitignore at all (the CRAFT block absent)
#   subdir        project in sub/, no .gitignore anywhere (the CRAFT block absent)
#   subdir-block  project in sub/, the CRAFT block in sub/.gitignore (it anchors below the prefix: it covers nothing at
#                 the worktree root, where .craft/ and the hook state of a human's session live)
fixture() {
  N=$((N + 1))
  local base="$TMP/c$N"
  REPO="$base/repo"; WT="$base/wt"; PFX=""; PROJ="$REPO"
  git init -q -b main "$REPO"
  case "$1" in subdir|subdir-block) PFX="sub/"; PROJ="$REPO/sub" ;; esac
  WPROJ="$WT"; [[ -n "$PFX" ]] && WPROJ="$WT/${PFX%/}"
  mkdir -p "$PROJ/.claude/plans" "$PROJ/src"
  printf 'root\n' > "$REPO/README"
  printf 'v1\n' > "$PROJ/src/code.txt"
  printf 'old\n' > "$PROJ/src/old.txt"
  case "$1" in
    block)         printf '%s\n' "$CRAFT_BLOCK" > "$PROJ/.gitignore" ;;
    noignore)      printf '%s\n' "$CRAFT_BLOCK" | grep -vxF -e '.craft/' -e '.claude/plans/.closed/' > "$PROJ/.gitignore" ;;
    plans-ignored) printf '.claude/plans/\n' > "$PROJ/.gitignore" ;;
    subdir)        ;;
    bare)          ;;
    subdir-block)  printf '%s\n' "$CRAFT_BLOCK" > "$PROJ/.gitignore" ;;
  esac
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m init
  splan "$PROJ/$SLICE_REL" implementing
}
splan() { # path status
  mkdir -p "$(dirname "$1")"
  printf '# Slice 001 — fixture\n\n> Status: %s\n> Slice-ID: slice-001\n> Slice-Slug: a\n\n## Goal\n\nfixture\n' "$2" > "$1"
}
setstatus() { # plan-file status — in place, through a temp file (no leftovers)
  sed "s/^> Status: .*/> Status: $2/" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
worktree() { git -C "$REPO" worktree add -q "$WT" -b slice-001-a main; }
commit_main_plan() { git -C "$REPO" add -f "$PFX$SLICE_REL" && git -C "$REPO" commit -q -m "plan"; }
rt() { (cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER" "$@" 2>&1); }
rt_exit() { (cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
dirt() { (cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" bash "$DIRT" --checkout "$WT" --scope slice-worktree 2>&1); }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
expect() { # name output key want
  local got
  got="$(val "$2" "$3")"
  if [[ "$got" == "$4" ]]; then ok "$1"; else bad "$1 — $3=$got, want $4"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}
same() { cmp -s "$1" "$2"; }
hash_of() { git hash-object -- "$1"; }
tree_listing() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(git hash-object -- "$f")" "$f"; done); }
status_of() { git -C "$WT" status --porcelain --untracked-files=all 2>&1; }
remove_wt() { git -C "$REPO" worktree remove "$WT" >/dev/null 2>&1; printf '%s' "$?"; }
WPLAN() { printf '%s/%s%s' "$WT" "$PFX" "$SLICE_REL"; }   # the worktree's copy of the plan
RECORD() { printf '%s/.craft/plan-roundtrip' "$WT"; }

echo "── in: the hand-in ──────────────────────────────────────────────────"

fixture block; worktree
before="$(tree_listing "$REPO")"
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "untracked plan → RESULT=copied"           "$out" RESULT copied
same "$PROJ/$SLICE_REL" "$(WPLAN)" && ok "  … byte-equal in the worktree (cmp)" || bad "  … worktree copy differs"
expect "  … SLICE_ID read from the plan"          "$out" SLICE_ID slice-001
[[ "$(sed -n 's/^SLICE_ID=//p' "$(RECORD)")" == slice-001 ]] && ok "  … record names the Slice-ID" || bad "  … record lacks SLICE_ID="
h="$(hash_of "$PROJ/$SLICE_REL")"
{ [[ "$(sed -n 's/^MAIN=//p' "$(RECORD)")" == "$h" ]] && [[ "$(sed -n 's/^WORKTREE=//p' "$(RECORD)")" == "$h" ]]; } \
  && ok "  … record holds both hashes" || bad "  … record hashes wrong: $(tr '\n' '|' < "$(RECORD)")"
[[ "$(sed -n 's/^PLAN=//p' "$(RECORD)")" == "$PFX$SLICE_REL" ]] && ok "  … record names the plan path" || bad "  … record PLAN= wrong"
[[ "$before" == "$(tree_listing "$REPO")" ]] && ok "  … the main checkout is never written (hashes before = after)" || bad "  … the main checkout changed"

fixture block; commit_main_plan; worktree
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "a plan the base holds byte-identical → unchanged" "$out" RESULT unchanged
[[ -f "$(RECORD)" ]] && ok "  … the record is written all the same" || bad "  … no record"

fixture block; commit_main_plan; worktree
printf 'edited after the commit\n' >> "$PROJ/$SLICE_REL"
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "a tracked plan edited after its commit → copied" "$out" RESULT copied
same "$PROJ/$SLICE_REL" "$(WPLAN)" && ok "  … over the base version, byte-equal" || bad "  … still the base version"

fixture subdir; worktree
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "a project below the repository root → copied" "$out" RESULT copied
same "$PROJ/$SLICE_REL" "$WT/sub/$SLICE_REL" && ok "  … at <worktree>/<prefix>/.claude/plans/…" || bad "  … not at the prefixed path"
[[ ! -e "$WT/$SLICE_REL" ]] && ok "  … and not at the worktree root" || bad "  … a copy sits at the worktree root"
[[ -f "$WT/.craft/plan-roundtrip" ]] && ok "  … the record sits at the worktree root" || bad "  … no record at the worktree root"

fixture block; worktree
before="$(tree_listing "$WT")"
[[ "$(rt_exit in --worktree "$WT" .claude/plans/nope.md)" == 4 ]] && ok "a missing plan → exit 4" || bad "a missing plan → exit 4"
out="$(rt in --worktree "$WT" .claude/plans/nope.md)"
[[ "$out" == *ERROR=plan_not_found* ]] && ok "  … ERROR=plan_not_found" || bad "  … no ERROR=plan_not_found: $out"
[[ "$before" == "$(tree_listing "$WT")" && ! -e "$WT/.craft" ]] && ok "  … nothing written" || bad "  … something was written"
[[ "$(rt_exit in --worktree "$TMP/nowhere" "$SLICE_REL")" == 4 ]] && ok "a missing worktree → exit 4" || bad "a missing worktree → exit 4"
out="$(rt in --worktree "$TMP/nowhere" "$SLICE_REL")"
[[ "$out" == *ERROR=worktree_not_found* && ! -e "$TMP/nowhere" ]] && ok "  … ERROR=worktree_not_found, nothing created" || bad "  … $out"

fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
printf 'builder edit\n' >> "$(WPLAN)"
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "a second hand-in over an edited worktree copy → conflict" "$out" RESULT conflict
expect "  … REASON=worktree_changed"              "$out" REASON worktree_changed
grep -qF 'builder edit' "$(WPLAN)" && ok "  … the worktree copy keeps its edit" || bad "  … the worktree copy was overwritten"

# a reused worktree an interrupted run left without a hand-in (git worktree add, then nothing)
fixture block; worktree
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "reuse without a record: the hand-in still delivers the plan" "$out" RESULT copied
same "$PROJ/$SLICE_REL" "$(WPLAN)" && ok "  … byte-equal in the worktree" || bad "  … the plan is not in the worktree"
fixture block; commit_main_plan; worktree
printf 'edited after the commit\n' >> "$PROJ/$SLICE_REL"
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "reuse without a record: a tracked plan edited since → the HEAD version is replaced" "$out" RESULT copied
fixture block; commit_main_plan; worktree
printf 'builder work\n' >> "$(WPLAN)"; printf 'main edit\n' >> "$PROJ/$SLICE_REL"
h="$(hash_of "$(WPLAN)")"
out="$(rt in --worktree "$WT" "$SLICE_REL")"
expect "reuse without a record: a worktree copy that is not HEAD's version → conflict" "$out" RESULT conflict
expect "  … REASON=worktree_changed"              "$out" REASON worktree_changed
[[ "$(hash_of "$(WPLAN)")" == "$h" ]] && ok "  … the worktree copy is never overwritten" || bad "  … the worktree copy was overwritten"

echo "── record self-ignore (P1-1) ────────────────────────────────────────"

fixture plans-ignored; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
st="$(status_of)"
{ [[ "$st" != *plan-roundtrip* && "$st" != *".craft/.gitignore"* ]]; } \
  && ok "record self-ignore: the worktree status stays empty without a .craft/ ignore" \
  || bad "record self-ignore: the worktree status stays empty without a .craft/ ignore — $st"
[[ -z "$st" ]] && ok "  … literally empty" || bad "  … status not empty: $st"
[[ "$(cat "$WT/.craft/.gitignore")" == $'/.gitignore\n/plan-roundtrip' ]] && ok "  … .craft/.gitignore holds exactly the two lines" || bad "  … .craft/.gitignore: $(tr '\n' '|' < "$WT/.craft/.gitignore")"
printf 'handoff\n' > "$WT/.craft/handoff.md"
[[ "$(status_of)" == *'?? .craft/handoff.md'* ]] && ok "  … another file under .craft/ is still listed by git status" || bad "  … .craft/handoff.md is hidden"

fixture plans-ignored; worktree
mkdir -p "$WT/.craft"; printf 'x\n' > "$WT/.craft/plan-roundtrip"
[[ "$(remove_wt)" != 0 ]] && ok "record self-ignore: a bare record blocks git worktree remove" || bad "record self-ignore: a bare record blocks git worktree remove (premise broken: the removal succeeded)"

fixture plans-ignored; worktree
mkdir -p "$WT/.craft"; printf '/.gitignore\n/checkpoints.md\n' > "$WT/.craft/.gitignore"
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
g="$(cat "$WT/.craft/.gitignore")"
{ grep -qxF '/.gitignore' <<<"$g" && grep -qxF '/checkpoints.md' <<<"$g" && grep -qxF '/plan-roundtrip' <<<"$g"; } \
  && ok "record self-ignore: an existing .craft/.gitignore keeps its lines" || bad "record self-ignore: an existing .craft/.gitignore keeps its lines — $(tr '\n' '|' <<<"$g")"
[[ "$(grep -c . <<<"$g")" == 3 ]] && ok "  … exactly one line appended" || bad "  … line count wrong"
printf 'checkpoint line\n' > "$WT/.craft/checkpoints.md"
[[ -z "$(status_of)" ]] && ok "  … and the status stays empty" || bad "  … status not empty: $(status_of)"
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
[[ "$(grep -c . "$WT/.craft/.gitignore")" == 3 ]] && ok "  … a repeated hand-in appends nothing" || bad "  … a repeated hand-in changed .craft/.gitignore"

echo "── back: the read-back ──────────────────────────────────────────────"

fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing; printf '\n## Recap Draft\n\nrecap\n' >> "$(WPLAN)"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "a worktree plan at committing → copied"  "$out" RESULT copied
same "$(WPLAN)" "$PROJ/$SLICE_REL" && ok "  … the main plan is byte-equal to it" || bad "  … the main plan differs"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "a second back → unchanged"                "$out" RESULT unchanged
h="$(hash_of "$PROJ/$SLICE_REL")"
{ [[ "$(sed -n 's/^MAIN=//p' "$(RECORD)")" == "$h" ]] && [[ "$(sed -n 's/^WORKTREE=//p' "$(RECORD)")" == "$h" ]]; } \
  && ok "  … the record follows the read-back" || bad "  … the record is stale after the read-back"

fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
printf 'a human edit in the main checkout\n' >> "$PROJ/$SLICE_REL"
h="$(hash_of "$PROJ/$SLICE_REL")"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "the main plan edited after the hand-in → conflict" "$out" RESULT conflict
expect "  … REASON=main_changed"                  "$out" REASON main_changed
[[ "$(hash_of "$PROJ/$SLICE_REL")" == "$h" ]] && ok "  … main byte-unchanged" || bad "  … main was overwritten"

fixture block; worktree
cp "$PROJ/$SLICE_REL" "$(WPLAN)" 2>/dev/null || { mkdir -p "$(dirname "$(WPLAN)")"; cp "$PROJ/$SLICE_REL" "$(WPLAN)"; }
setstatus "$(WPLAN)" committing
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "no record → conflict"                     "$out" RESULT conflict
expect "  … REASON=no_record"                     "$out" REASON no_record
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
sed 's/^SLICE_ID=.*/SLICE_ID=slice-099/' "$(RECORD)" > "$(RECORD).tmp" && mv "$(RECORD).tmp" "$(RECORD)"
h="$(hash_of "$PROJ/$SLICE_REL")"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "a record for another Slice-ID → conflict" "$out" RESULT conflict
expect "  … REASON=record_other_slice"            "$out" REASON record_other_slice
[[ "$(hash_of "$PROJ/$SLICE_REL")" == "$h" ]] && ok "  … main untouched" || bad "  … main was written"

# the human reconciled by hand (the plans are identical now): nothing to overwrite, whatever the record says
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
printf 'a human edit in the main checkout\n' >> "$PROJ/$SLICE_REL"
cp "$(WPLAN)" "$PROJ/$SLICE_REL"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "after a hand reconciliation (identical plans) → unchanged, not a conflict" "$out" RESULT unchanged
[[ "$(sed -n 's/^MAIN=//p' "$(RECORD)")" == "$(hash_of "$PROJ/$SLICE_REL")" ]] && ok "  … and the record follows" || bad "  … the record is stale"

fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" review
h="$(hash_of "$PROJ/$SLICE_REL")"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
expect "a worktree plan below committing → refused" "$out" RESULT refused
expect "  … REASON=not_committing"                "$out" REASON not_committing
[[ "$(hash_of "$PROJ/$SLICE_REL")" == "$h" ]] && ok "  … nothing written" || bad "  … main was written"

fixture block; worktree
[[ "$(rt_exit back --worktree "$WT" "$SLICE_REL")" == 4 ]] && ok "the worktree plan missing → exit 4" || bad "the worktree plan missing → exit 4"
out="$(rt back --worktree "$WT" "$SLICE_REL")"
[[ "$out" == *ERROR=worktree_plan_missing* ]] && ok "  … ERROR=worktree_plan_missing" || bad "  … $out"

echo "── release: the worktree copy is no obstacle ────────────────────────"

# tracked and modified → restored to HEAD
fixture block; commit_main_plan; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "release: a tracked copy → RESULT=released" "$out" RESULT released
expect "  … ACTION=none"                          "$out" ACTION none
[[ -z "$(git -C "$WT" status --porcelain --untracked-files=all -- "$PFX$SLICE_REL")" ]] && ok "  … restored to the worktree's HEAD" || bad "  … still modified: $(status_of)"
grep -qF 'Status: implementing' "$(WPLAN)" && ok "  … the HEAD version is back" || bad "  … not the HEAD version"
grep -qF 'Status: committing' "$PROJ/$SLICE_REL" && ok "  … the read-back copy in main is untouched" || bad "  … main lost the read-back"

# untracked → ACTION=close
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "release: an untracked copy → ACTION=close" "$out" ACTION close
expect "  … RESULT=released"                      "$out" RESULT released
expect "  … PROJECT= names the worktree's project dir" "$out" PROJECT "$WPROJ"
[[ -f "$(WPLAN)" ]] && ok "  … the helper itself removed nothing" || bad "  … the copy is gone"

# edited after the read-back → conflict
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
printf 'edited after the read-back\n' >> "$(WPLAN)"
h="$(hash_of "$(WPLAN)")"
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "release: a copy edited after the read-back → conflict" "$out" RESULT conflict
expect "  … REASON=worktree_changed"              "$out" REASON worktree_changed
[[ "$(hash_of "$(WPLAN)")" == "$h" ]] && ok "  … the copy is unchanged" || bad "  … the copy was touched"
[[ "$(remove_wt)" != 0 ]] && ok "  … and the removal is still refused" || bad "  … the removal succeeded over an unread edit"

# no record → conflict (a worktree made by a run before this slice)
fixture block; worktree
mkdir -p "$(dirname "$(WPLAN)")"; cp "$PROJ/$SLICE_REL" "$(WPLAN)"
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "release: no record → conflict"            "$out" RESULT conflict
expect "  … REASON=no_record"                     "$out" REASON no_record

# the plan already closed → nothing to release
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
mv "$(WPLAN)" "$TMP/gone-$N.md"
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "release: no copy in the worktree → ACTION=none" "$out" ACTION none

# the premise: a bare .closed/ copy blocks the removal
fixture noignore; worktree
mkdir -p "$WPROJ/.claude/plans/.closed"; printf 'closed\n' > "$WPROJ/.claude/plans/.closed/slice-001-a.md"
[[ "$(remove_wt)" != 0 ]] && ok "closed copy: a bare .closed/ copy blocks git worktree remove" || bad "closed copy: a bare .closed/ copy blocks git worktree remove (premise broken)"

# the cure: release, then close-file.sh --move, in a project without the CRAFT block
fixture noignore; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "  (release before the close) ACTION=close" "$out" ACTION close
[[ "$(cat "$WPROJ/.claude/plans/.closed/.gitignore" 2>/dev/null)" == '*' ]] && ok "  … .closed/.gitignore holds the one line *" || bad "  … no .closed/.gitignore with *"
mv_out="$(closer --project "$(val "$out" PROJECT)" --move "$(val "$out" PLAN)")"
expect "  … close-file.sh --move moved the copy"  "$mv_out" RESULT moved
rc="$(remove_wt)"
[[ "$rc" == 0 ]] && ok "closed copy: a move-mode close without the CRAFT block does not block removal" || bad "closed copy: a move-mode close without the CRAFT block does not block removal — $(git -C "$REPO" worktree remove "$WT" 2>&1)"

# with the CRAFT block, git already ignores the path
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
rt release --worktree "$WT" "$SLICE_REL" >/dev/null
[[ ! -e "$WPROJ/.claude/plans/.closed/.gitignore" ]] && ok "with the CRAFT block, release writes no .closed/.gitignore" || bad "with the CRAFT block, release wrote a .closed/.gitignore"

# delete mode: close-file.sh prints DELETE_CMD naming the worktree copy; the fixture never runs it
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
setstatus "$(WPLAN)" committing
rt back --worktree "$WT" "$SLICE_REL" >/dev/null
out="$(rt release --worktree "$WT" "$SLICE_REL")"
del="$(closer --project "$(val "$out" PROJECT)" "$(val "$out" PLAN)")"
expect "delete mode: close-file.sh hands the command back" "$del" RESULT delete
[[ "$(val "$del" DELETE_CMD)" == *"$(WPLAN)"* ]] && ok "  … DELETE_CMD names the worktree copy" || bad "  … DELETE_CMD: $(val "$del" DELETE_CMD)"
[[ -f "$(WPLAN)" ]] && ok "  … nothing removed (D34: the agent issues it under the permission check)" || bad "  … the copy is gone"

# the .primed seed execute step 5 puts at the worktree root blocks the removal in a project that does not ignore it
fixture subdir; worktree
mkdir -p "$WT/.claude/plans"; : > "$WT/.claude/plans/.primed"
[[ "$(remove_wt)" != 0 ]] && ok "primed seed: a bare .claude/plans/.primed at the worktree root blocks git worktree remove" || bad "primed seed: premise broken (the removal succeeded)"
fixture subdir; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
mkdir -p "$WT/.claude/plans"; : > "$WT/.claude/plans/.primed"
rt release --worktree "$WT" "$SLICE_REL" >/dev/null
st="$(status_of)"
[[ "$st" != *.primed* && "$st" != *"plans/.gitignore"* ]] && ok "primed seed: release hides it from git (a self-ignoring .claude/plans/.gitignore)" || bad "primed seed: release leaves it visible — $st"

# a Phase-5 handoff leaves CRAFT files at the worktree root that a subdirectory project's CRAFT block does not cover
fixture subdir-block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
mkdir -p "$WT/.craft" "$WT/.claude/plans"; printf 'r\n' > "$WT/.craft/handoff-resolved-2026-10-07T10-00-00Z.md"; : > "$WT/.claude/plans/.hook-env"
st="$(status_of)"
[[ "$st" == *handoff-resolved* && "$st" == *.hook-env* ]] && ok "root files: a resolved marker and the hook state are visible to git in a subdirectory project with the block (premise)" || bad "root files: premise broken — $st"
setstatus "$(WPLAN)" committing; rt back --worktree "$WT" "$SLICE_REL" >/dev/null
rt release --worktree "$WT" "$SLICE_REL" >/dev/null
st="$(status_of)"
[[ "$st" != *handoff-resolved* && "$st" != *.hook-env* && "$st" != *"plans/.gitignore"* ]] && ok "root files: release hides the resolved marker and the hook state" || bad "root files: release leaves them visible — $st"
printf 'checkpoint\n' > "$WT/.craft/checkpoints.md"
[[ "$(status_of)" != *checkpoints* ]] && ok "  … and anything else CRAFT later puts under .craft/" || bad "  … .craft/ is only partly hidden"

# on a conflict the worktree stays in use: a live handoff stays visible, nothing is hidden
fixture subdir-block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
mkdir -p "$WT/.craft" "$WT/.claude/plans"; printf 'live\n' > "$WT/.craft/handoff.md"; : > "$WT/.claude/plans/.hook-env"
setstatus "$(WPLAN)" committing; rt back --worktree "$WT" "$SLICE_REL" >/dev/null
printf 'edited after the read-back\n' >> "$(WPLAN)"
out="$(rt release --worktree "$WT" "$SLICE_REL")"
expect "root files: a conflicting release is a conflict" "$out" RESULT conflict
{ [[ "$(cat "$WT/.craft/.gitignore")" == $'/.gitignore\n/plan-roundtrip' ]] && [[ "$(status_of)" == *'.craft/handoff.md'* && "$(status_of)" == *.hook-env* ]]; } \
  && ok "  … hides nothing: the live handoff and the hook state stay visible, .craft/.gitignore keeps its two lines" || bad "  … a conflicting release hid files: $(status_of | tr '\n' '|')"

# a project whose block already ignores them gets no extra file
fixture block; worktree
rt in --worktree "$WT" "$SLICE_REL" >/dev/null
mkdir -p "$WT/.claude/plans" "$WT/.craft"; : > "$WT/.claude/plans/.hook-env"; printf 'r\n' > "$WT/.craft/handoff-resolved-x.md"
setstatus "$(WPLAN)" committing; rt back --worktree "$WT" "$SLICE_REL" >/dev/null
rt release --worktree "$WT" "$SLICE_REL" >/dev/null
[[ ! -e "$WT/.claude/plans/.gitignore" ]] && ok "root files: with the block at the worktree root release adds no .claude/plans/.gitignore" || bad "root files: release wrote a .claude/plans/.gitignore the block made needless"
[[ "$(cat "$WT/.craft/.gitignore")" == $'/.gitignore\n/plan-roundtrip' ]] && ok "  … and leaves .craft/.gitignore at its two lines" || bad "  … .craft/.gitignore changed: $(tr '\n' '|' < "$WT/.craft/.gitignore")"

# a .claude/plans/.gitignore the project tracks is never touched
fixture noignore; mkdir -p "$PROJ/.claude/plans"; printf '# mine\n' > "$PROJ/.claude/plans/.gitignore"
git -C "$REPO" add -f "$PFX.claude/plans/.gitignore"; git -C "$REPO" commit -q -m "tracked plans ignore"
worktree; rt in --worktree "$WT" "$SLICE_REL" >/dev/null
: > "$WT/.claude/plans/.hook-env"
setstatus "$(WPLAN)" committing; rt back --worktree "$WT" "$SLICE_REL" >/dev/null
rt release --worktree "$WT" "$SLICE_REL" >/dev/null
[[ "$(cat "$WT/.claude/plans/.gitignore")" == '# mine' ]] && ok "root files: a tracked .claude/plans/.gitignore is left alone" || bad "root files: a tracked .claude/plans/.gitignore was rewritten"

echo "── lifecycle: the commit gap, from hand-in to a removed worktree ────"

lifecycle() { # kind name
  local kind="$1" name="$2" fails=0 why="" dirt_out paths=() line code_rel
  fixture "$kind"; worktree
  rt in --worktree "$WT" "$SLICE_REL" >/dev/null                                   # 1. hand-in
  code_rel="${PFX}src/code.txt"
  printf 'v2\n' > "$WPROJ/src/code.txt"; printf 'new\n' > "$WPROJ/src/new.txt"; mv "$WPROJ/src/old.txt" "$TMP/old-$N.txt"
  setstatus "$(WPLAN)" committing; printf '\n## Recap Draft\n\nrecap\n' >> "$(WPLAN)"   # 2. the builder's edits
  mkdir -p "$WT/.claude/plans"; touch "$WT/.claude/plans/.primed"                    #    … and execute step 5's seed
  : > "$WT/.claude/plans/.hook-env"; mkdir -p "$WT/.craft"                           #    … a human session's hook state at the root,
  printf 'resolved\n' > "$WT/.craft/handoff-resolved-2026-10-07T10-00-00Z.md"          #    … the marker a re-run renamed (the Phase-5 handoff)
  [[ -z "$PFX" ]] || : > "$WPROJ/.claude/plans/.hook-env"                             #    … and below the prefix
  dirt_out="$(dirt)"                                                                  # 3. exactly the DIRT= paths
  while IFS= read -r line; do case "$line" in DIRT=*) paths+=("${line#DIRT=???}") ;; esac; done <<<"$dirt_out"
  [[ ${#paths[@]} -eq 3 ]] || { fails=1; why+=" paths=${#paths[@]}($(printf '%s;' "${paths[@]}"))"; }
  git -C "$WT" add -A -- "${paths[@]}" >/dev/null 2>&1 || { fails=1; why+=" add"; }
  git -C "$WT" commit -q -m "feat(fixture): the slice work" -- "${paths[@]}" >/dev/null 2>&1 || { fails=1; why+=" commit"; }
  [[ "$(dirt)" == *"DIRTY=no"* ]] || { fails=1; why+=" dirty-after-commit($(dirt | tr '\n' '|'))"; }
  names="$(git -C "$WT" show --name-only --format= HEAD)"
  [[ "$names" != *plans* && "$names" != *.craft* && "$names" != *.primed* ]] || { fails=1; why+=" plan-or-craft-committed"; }
  [[ "$(git -C "$WT" rev-list --count main..HEAD)" -gt 0 ]] || { fails=1; why+=" not-ahead"; }
  out="$(rt back --worktree "$WT" "$SLICE_REL")"                                      # 4. back
  [[ "$(val "$out" RESULT)" == copied ]] || { fails=1; why+=" back=$(val "$out" RESULT)"; }
  git -C "$REPO" merge -q --no-ff slice-001-a -m "Merge slice-001" >/dev/null 2>&1 || { fails=1; why+=" merge"; }   # 5. merge
  [[ "$(cat "$PROJ/src/code.txt")" == v2 ]] || { fails=1; why+=" trunk-lacks-code-change"; }
  same "$PROJ/$SLICE_REL" "$(WPLAN)" || { fails=1; why+=" main-plan-differs"; }
  out="$(rt release --worktree "$WT" "$SLICE_REL")"                                   # 6. release, then close
  [[ "$(val "$out" ACTION)" == close ]] || { fails=1; why+=" release=$(val "$out" ACTION)/$(val "$out" RESULT)"; }
  if [[ "$(val "$out" ACTION)" == close ]]; then
    closer --project "$(val "$out" PROJECT)" --move "$(val "$out" PLAN)" >/dev/null || { fails=1; why+=" close"; }
  fi
  rm_out="$(git -C "$REPO" worktree remove "$WT" 2>&1)" || { fails=1; why+=" worktree-remove(${rm_out##*fatal: }; left: $(git -C "$WT" status --porcelain --untracked-files=all | tr '\n' '|'))"; }   # 7.
  git -C "$REPO" branch -d slice-001-a >/dev/null 2>&1 || { fails=1; why+=" branch-d"; }
  if (( fails == 0 )); then ok "$name"; else bad "$name —$why"; fi
}
lifecycle block      "lifecycle: root project with the CRAFT block lands and removes its worktree"
lifecycle noignore   "lifecycle: project without a .craft/ ignore lands and removes its worktree"
lifecycle subdir     "lifecycle: subdirectory project without the CRAFT block lands and removes its worktree"
lifecycle subdir-block "lifecycle: subdirectory project with the CRAFT block, after a Phase-5 handoff, lands and removes its worktree"
lifecycle bare       "lifecycle: root project without any .gitignore, after a Phase-5 handoff, lands and removes its worktree"

echo "── pins: the helper and the sites that call it ──────────────────────"

[[ -f "$HELPER" ]] || bad "scripts/plan-roundtrip.sh does not exist"
if [[ -f "$HELPER" ]]; then
  if grep -v '^[[:space:]]*#' "$HELPER" | grep -qE '(^|[^A-Za-z_./-])(rm|rmdir|unlink)([[:space:]]|$)|git (rm|clean)|worktree remove|--force'; then
    bad "the helper holds a removal command (D34)"
  else
    ok "the helper holds no removal command (D34)"
  fi
fi

step5="$(awk '/^### 5\./{f=1} /^### 6\./{f=0} f' "$EXECUTE")"
step6="$(awk '/^### 6\./{f=1} /^### 7\./{f=0} f' "$EXECUTE")"
step1b="$(awk '/^### 1b\./{f=1} /^### 1c\./{f=0} f' "$EXECUTE")"
step1c="$(awk '/^### 1c\./{f=1} /^### 2\./{f=0} f' "$EXECUTE")"
[[ "$step5" == *'plan-roundtrip.sh" in'* ]] && ok "commands/execute.md calls plan-roundtrip.sh \" in\" in step 5" || bad "commands/execute.md step 5 does not call plan-roundtrip.sh \" in"
a="${step6%%--scope slice-worktree*}"; b="${step6%%plan-roundtrip.sh\" back*}"
if [[ "$step6" == *'--scope slice-worktree'* && "$step6" == *'plan-roundtrip.sh" back'* && "$step6" == *tree-dirt-state.sh* && ${#a} -lt ${#b} ]]; then
  ok "in step 6, tree-dirt-state.sh with --scope slice-worktree comes before plan-roundtrip.sh \" back"
else
  bad "step 6 does not run tree-dirt-state.sh --scope slice-worktree before plan-roundtrip.sh \" back"
fi
[[ "$step1b" == *'step 6'* && "$step1b" == *'per sub-task'* ]] && ok "step 1b names step 6 as the place of the per-sub-task commits" || bad "step 1b does not name step 6 for the per-sub-task commits"
reuse_part="${step5#*ACTION=reuse}"
[[ "$reuse_part" == *'plan-roundtrip.sh" in'* ]] && ok "commands/execute.md step 5 hands the plan in on ACTION=reuse too (no record yet)" || bad "commands/execute.md step 5 does not hand the plan in on ACTION=reuse"
[[ "$step6" == *plan-roundtrip.sh* && "$step6" != *'craft:writes'* ]] && ok "the step-6 prose carries no craft:writes marker (the read-back is a copy)" || bad "the step-6 prose carries a craft:writes marker (or no read-back)"

step7="$(awk '/^### Step 7 /{f=1} /^### Step 7b/{f=0} f' "$COMMIT")"
rel_at="${step7%%plan-roundtrip.sh\" release*}"; rm_at="${step7%%git worktree remove*}"
if [[ "$step7" == *'plan-roundtrip.sh" release'* && ${#rel_at} -lt ${#rm_at} ]]; then
  ok "commands/commit.md calls plan-roundtrip.sh \" release in Step 7 before the slice worktree's git worktree remove"
else
  bad "commands/commit.md Step 7 does not call plan-roundtrip.sh \" release before git worktree remove"
fi
a3="$(awk '/^### A3/{f=1} /^### A4/{f=0} f' "$COMMIT")"
[[ "$a3" == *'--scope slice-worktree'* ]] && ok "commands/commit.md A3 names --scope slice-worktree" || bad "commands/commit.md A3 does not name --scope slice-worktree"

if grep -qF 'plan_not_committed' "$BUILDER"; then bad "agents/slice-builder.md still names plan_not_committed"; else ok "agents/slice-builder.md no longer names plan_not_committed"; fi
if grep -qF 'may produce sub-task-level commits' "$BUILDER"; then bad "agents/slice-builder.md still says the worktree may produce sub-task-level commits"; else ok "agents/slice-builder.md no longer says the worktree \"may produce sub-task-level commits\""; fi
if [[ "$step1c" == *plan_not_committed* ]]; then
  # only for the epic line: the fix text must say so
  [[ "$step1c" == *'epic line'* ]] && ok "step 1c names plan_not_committed for the epic line" || bad "step 1c names plan_not_committed without saying it is an epic-line reason"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
