#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-handoff-marker-state.sh — self-contained tests for the B7 handoff-marker
# helper (handoff-marker-state.sh) and the SessionStart hook that uses it
# (hooks/worktree-handoff-notify.sh).
#
# No test runner exists in this repo (plugin assets, not runtime software), so this
# harness stands alone: it builds a throwaway repo with real git worktrees under a temp
# dir, writes slice plans and handoff markers into them, drives the helper and the hook,
# and exits non-zero if any case fails. Run it directly:
#
#   bash scripts/test-handoff-marker-state.sh
#
# It writes nothing outside its own mktemp directory (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/handoff-marker-state.sh"
HOOK="$REPO_ROOT/hooks/worktree-handoff-notify.sh"
SKILL="$REPO_ROOT/skills/workflow/SKILL.md"
for f in "$HELPER" "$HOOK" "$SKILL"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

WT="$ROOT/wt"
mkdir -p "$WT/.craft" "$WT/.claude/plans"

marker() { # status [slice-id] [written]
  printf -- '---\nSlice-ID: %s\nStatus: %s\nPhase: 5\nWritten: %s\n---\n\n# Handoff: fixture\n\nStatus: body text must not be read\n' \
    "${2:-slice-007}" "$1" "${3:-2026-09-14T10:00:00Z}" > "$WT/.craft/handoff.md"
}
plan() { # status
  rm -f "$WT/.claude/plans/"*.md
  printf '# Slice 007 — fixture\n\n> Status: %s\n> Slice-ID: slice-007\n' "$1" > "$WT/.claude/plans/slice-007-fixture.md"
}
state() { # → STATE value
  bash "$HELPER" "$WT" 2>&1 | sed -n 's/^STATE=//p'
}
reason() {
  bash "$HELPER" "$WT" 2>&1 | sed -n 's/^REASON=//p'
}

# --- the pairing matrix ----------------------------------------------------------------
PLAN_STATES="planning implementing testing review refactoring reviewing committing paused blocked"
check_row() { # marker-status live-plan-state
  local s want got bad_list=""
  for s in $PLAN_STATES; do
    marker "$1"; plan "$s"
    want="STALE"; [[ "$s" == "$2" ]] && want="LIVE"
    got="$(state)"
    [[ "$got" == "$want" ]] || bad_list="$bad_list $s:$got"
  done
  [[ -z "$bad_list" ]] && ok "$1 is LIVE only at plan status '$2'" || bad "$1 pairing wrong at:$bad_list"
}
check_row awaiting-test paused
check_row awaiting-protocol paused
check_row awaiting-scope-decision paused
check_row awaiting-refactor-decision paused
check_row awaiting-block-decision blocked
check_row awaiting-rethink-decision reviewing

bad_list=""
for s in $PLAN_STATES; do
  marker failure; plan "$s"
  [[ "$(state)" == "LIVE" ]] || bad_list="$bad_list $s"
done
[[ -z "$bad_list" ]] && ok "failure is LIVE at every plan status" || bad "failure not LIVE at:$bad_list"

# --- doubt means LIVE --------------------------------------------------------------------
rm -f "$WT/.craft/handoff.md"
{ [[ "$(state)" == "NONE" ]] && [[ "$(reason)" == "no_marker" ]]; } && ok "no marker → STATE=NONE" || bad "no marker (state=$(state))"

marker awaiting-test; plan testing; rm -f "$WT/.claude/plans/"*.md
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "plan_not_found" ]]; } && ok "plan missing (e.g. .claude/plans/ gitignored) → LIVE" || bad "plan missing (state=$(state))"

plan testing; cp "$WT/.claude/plans/slice-007-fixture.md" "$WT/.claude/plans/slice-007-other.md"
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "plan_ambiguous" ]]; } && ok "two plans for one slice-ID → LIVE" || bad "ambiguous plan (state=$(state))"

plan testing; printf '# Slice 007\n\nno status here\n' > "$WT/.claude/plans/slice-007-fixture.md"
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "plan_status_missing" ]]; } && ok "plan without a Status line → LIVE" || bad "status missing (state=$(state))"

printf '> Status: planning | implementing | testing\n' > "$WT/.claude/plans/slice-007-fixture.md"
[[ "$(state)" == "LIVE" ]] && ok "unfilled template status (a|b|c) → LIVE" || bad "template status (state=$(state))"

marker awaiting-nonsense; plan testing
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "unknown_marker_status" ]]; } && ok "unknown marker status → LIVE" || bad "unknown status (state=$(state))"

marker awaiting-test; plan testing
mv "$WT/.claude/plans/slice-007-fixture.md" "$WT/.claude/plans/slice-0070-decoy.md"
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "plan_not_found" ]]; } && ok "slice-007 does not match a slice-0070-… plan (no prefix collision)" || bad "prefix collision (state=$(state), reason=$(reason))"
rm -f "$WT/.claude/plans/"*.md

marker awaiting-test '../../etc'; plan testing
{ [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "no_slice_id" ]]; } && ok "malformed Slice-ID (no glob outside plans/) → LIVE" || bad "malformed slice-id (state=$(state))"

marker awaiting-test; printf '# Slice 007\r\n\r\n> Status: testing\r\n' > "$WT/.claude/plans/slice-007-fixture.md"
[[ "$(state)" == "STALE" ]] && ok "CRLF plan is read correctly (STALE)" || bad "CRLF plan (state=$(state))"

# --- episodes (B11): a marker counts only while the plan is still in the marker's episode ---------
# plan_ep <status> <header lines, printf %b> [body, printf %b] — header fields sit above the first `## `
plan_ep() {
  rm -f "$WT/.claude/plans/"*.md
  printf '# Slice 007 — fixture\n\n> Status: %s\n> Slice-ID: slice-007\n%b\n## Goal\n\nfixture\n%b' "$1" "$2" "${3:-}" \
    > "$WT/.claude/plans/slice-007-fixture.md"
}
marker_ep() { # status episode
  printf -- '---\nSlice-ID: slice-007\nStatus: %s\nPhase: 5\nWritten: 2026-09-15T10:00:00Z\nEpisode: %s\n---\n\n# Handoff: fixture\n' \
    "$1" "$2" > "$WT/.craft/handoff.md"
}
expect() { # label want-state want-reason
  local st rs
  st="$(state)"; rs="$(reason)"
  { [[ "$st" == "$2" ]] && [[ "$rs" == "$3" ]]; } && ok "$1 → $2 ($3)" || bad "$1 (state=$st, reason=$rs; want $2/$3)"
}
T1='2026-09-15T10:00:00Z'; T2='2026-09-15T14:30:00Z'

marker_ep awaiting-test "$T1"
plan_ep paused "> Paused-status: testing\n> Paused-since: $T1\n";   expect "pause(T1) + marker(T1)" LIVE paired
plan_ep testing "";                                                expect "  … resumed (plan back at Paused-status, record removed)" STALE unpaired
plan_ep paused "> Paused-status: review\n> Paused-since: $T2\n";   expect "  … then re-paused (T2) for another reason" STALE episode_mismatch
plan_ep paused "> Paused-status: testing\n";                       expect "marker with episode, plan paused without Paused-since" LIVE episode_unknown
plan_ep paused "" "\n> Paused-since: $T1\n";                        expect "  … a Paused-since line in the plan body is not the header stamp" LIVE episode_unknown
printf '# Slice 007\r\n\r\n> Status: paused\r\n> Paused-since: %s\r\n\r\n## Goal\r\n' "$T1" > "$WT/.claude/plans/slice-007-fixture.md"
expect "CRLF plan header stamp matches" LIVE paired
for s in awaiting-protocol awaiting-scope-decision awaiting-refactor-decision; do
  marker_ep "$s" "$T1"; plan_ep paused "> Paused-since: $T2\n"
  [[ "$(reason)" == "episode_mismatch" ]] && ok "$s follows the Paused-since episode" || bad "$s episode (reason=$(reason))"
done

marker_ep awaiting-block-decision "$T1"
plan_ep blocked "> Blocker-type: decision\n> Blocked-since: $T1\n> Blocked-status: implementing\n"; expect "block(T1) + marker(T1)" LIVE paired
plan_ep implementing "";                                                                           expect "  … unblocked" STALE unpaired
plan_ep blocked "> Blocker-type: external\n> Blocked-since: $T2\n> Blocked-status: implementing\n"; expect "  … blocked again after the unblock (T2)" STALE episode_mismatch

marker awaiting-test; plan_ep paused "> Paused-since: $T2\n"
expect "legacy marker without Episode: judged by status alone" LIVE paired
printf -- '---\nSlice-ID: slice-007\nStatus: awaiting-test\nWritten: %s\n---\n\nEpisode: %s\n' "$T1" "$T1" > "$WT/.craft/handoff.md"
expect "  … an Episode: line in the marker body is not its episode (still status alone)" LIVE paired
# A frontmatter that never closes has no fields — and the answer must not depend on the marker's size
plan_ep paused "> Paused-since: $T2\n"
printf -- '---\nSlice-ID: slice-007\nStatus: awaiting-test\nEpisode: %s\n\n# Handoff: no closing fence\n' "$T1" > "$WT/.craft/handoff.md"
expect "unclosed marker frontmatter: no episode, status alone" LIVE paired
for i in $(seq 1 4000); do echo "body line $i"; done >> "$WT/.craft/handoff.md"
expect "  … the same marker with a 4000-line body gives the same answer" LIVE paired

# A malformed or unconfirmable episode is doubt, never a mismatch: it must not hide a waiting slice (R1-1).
plan_ep paused "> Paused-since: $T1\n"
for bad_ep in "\"$T1\"" "\`$T1\`" "2026-09-15 10:00:00" "2026-09-15T10:00:00.000Z" "2026-09-15T12:00:00+02:00" "n/a"; do
  marker_ep awaiting-test "$bad_ep"
  { [[ "$(state)" == "LIVE" ]] && [[ "$(reason)" == "episode_unknown" ]]; } && ok "marker Episode: $bad_ep → LIVE (episode_unknown)" \
    || bad "malformed marker episode '$bad_ep' (state=$(state), reason=$(reason))"
done
marker_ep awaiting-test "$T1"; plan_ep paused "> Paused-since: \`$T1\`\n"; expect "plan stamp in backticks" LIVE episode_unknown
marker_ep awaiting-test "$T2"; plan_ep paused "> Paused-since: $T1\n";     expect "marker episode later than the plan's (a miscopy, e.g. Written:)" LIVE episode_unknown

ROUND1_OPEN='\n## Review Findings\n\n### Round 1 — 2026-09-15 (Phase-8)\n\n- R1-1 · Heavy · Rethink · redesign · escalated → route pending\n'
ROUND1_ROUTED='\n## Review Findings\n\n### Round 1 — 2026-09-15 (Phase-8)\n\n- R1-1 · Heavy · Rethink · redesign · escalated → Phase 4 loop-back\n'
ROUND2_OPEN="$ROUND1_ROUTED"'\n### Round 2 — 2026-09-16 (Phase-8)\n\n- R2-1 · Heavy · Rethink · again · escalated → route pending\n'
marker_ep awaiting-rethink-decision 1
plan_ep reviewing "" "$ROUND1_OPEN";   expect "rethink marker (round 1), round 1 still open" LIVE paired
# No writer produces this record — an interactive review appends round 2 before it routes — but a
# hand-routed round must not keep the marker live: the findings_closed guard.
plan_ep reviewing "" "$ROUND1_ROUTED"; expect "  … round 1 routed by hand, no round 2 yet (guard)" STALE findings_closed
plan_ep reviewing "" "$ROUND2_OPEN";   expect "  … round 2 recorded with its own open line" STALE episode_mismatch
marker_ep awaiting-rethink-decision 2; expect "a round-2 rethink marker in round 2" LIVE paired
marker_ep awaiting-rethink-decision R2; expect "rethink Episode: R2 (not a round number)" LIVE episode_unknown
marker_ep awaiting-rethink-decision 3; expect "rethink marker round later than the record's" LIVE episode_unknown
marker_ep awaiting-rethink-decision 0; expect "rethink Episode: 0 (no round a writer copies)" LIVE episode_unknown

# The helper runs the findings parser with its own interpreter (${BASH}), not whatever `bash` PATH
# finds: a PATH whose `bash` always fails must not change the answer.
mkdir -p "$ROOT/failbash" && printf '#!/bin/sh\nexit 97\n' > "$ROOT/failbash/bash" && chmod +x "$ROOT/failbash/bash"
marker_ep awaiting-rethink-decision 1; plan_ep reviewing "" "$ROUND1_ROUTED"
out="$(PATH="$ROOT/failbash:$PATH" "$BASH" "$HELPER" "$WT" 2>&1)"
[[ "$out" == *"REASON=findings_closed"* ]] && ok "the findings parser runs with the helper's own bash, not PATH's" || bad "parser interpreter (out=$out)"

mkdir -p "$ROOT/nofindings" && cp "$HELPER" "$ROOT/nofindings/"
marker_ep awaiting-rethink-decision 1; plan_ep reviewing "" "$ROUND1_OPEN"
out="$(bash "$ROOT/nofindings/handoff-marker-state.sh" "$WT" 2>&1)"
{ [[ "$out" == *"STATE=LIVE"* ]] && [[ "$out" == *"REASON=episode_unknown"* ]]; } \
  && ok "findings parser missing next to the helper → LIVE (episode_unknown)" || bad "no findings parser (out=$out)"

marker_ep awaiting-test "$T1"; plan_ep paused "> Paused-since: $T2\n"
out="$(bash "$HELPER" "$WT" --resolve)"
{ [[ "$out" == *"RESOLVED=$WT/.craft/handoff-resolved-"* ]] && [[ ! -e "$WT/.craft/handoff.md" ]]; } \
  && ok "--resolve renames an episode-mismatched marker like any STALE one" || bad "resolve episode_mismatch (out=$out)"
rm -f "$WT/.craft/"handoff-resolved-*.md "$WT/.claude/plans/"*.md

# --- --resolve ---------------------------------------------------------------------------
rm -f "$WT/.craft/"handoff-resolved-*.md
marker awaiting-test; plan paused
out="$(bash "$HELPER" "$WT" --resolve)"
{ [[ "$out" == *"RESOLVED=no"* ]] && [[ -f "$WT/.craft/handoff.md" ]]; } && ok "--resolve leaves a LIVE marker untouched" || bad "LIVE resolve (out=$out)"

plan testing
out="$(bash "$HELPER" "$WT" --resolve)"
target="$WT/.craft/handoff-resolved-2026-09-14T10-00-00Z.md"
{ [[ "$out" == *"STATE=STALE"* ]] && [[ "$out" == *"RESOLVED=$target"* ]] && [[ ! -e "$WT/.craft/handoff.md" ]] && [[ -f "$target" ]]; } \
  && ok "--resolve renames a STALE marker to handoff-resolved-<Written>.md" || bad "STALE resolve (out=$out)"

out="$(bash "$HELPER" "$WT" --resolve)"
{ [[ "$out" == *"STATE=NONE"* ]] && [[ "$out" == *"RESOLVED=no"* ]]; } && ok "re-running --resolve is a no-op" || bad "resolve re-run (out=$out)"

before="$(cat "$target")"
marker awaiting-refactor-decision; plan reviewing
out="$(bash "$HELPER" "$WT" --resolve)"
{ [[ "$out" == *"RESOLVED=$WT/.craft/handoff-resolved-2026-09-14T10-00-00Z-2.md"* ]] && [[ "$(cat "$target")" == "$before" ]]; } \
  && ok "a second resolve with the same Written stamp gets -2, the earlier file is not overwritten" || bad "collision (out=$out)"

marker failure; plan implementing
out="$(bash "$HELPER" "$WT" --resolve)"
{ [[ "$out" == *"RESOLVED=no"* ]] && [[ -f "$WT/.craft/handoff.md" ]]; } && ok "failure is not renamed by --resolve alone" || bad "failure resolve (out=$out)"
out="$(bash "$HELPER" "$WT" --resolve --retry)"
{ [[ "$out" == *"RESOLVED=$WT/.craft/handoff-resolved-"* ]] && [[ ! -e "$WT/.craft/handoff.md" ]]; } && ok "failure is renamed with --resolve --retry" || bad "failure retry (out=$out)"

marker awaiting-test; plan paused
out="$(bash "$HELPER" "$WT" --resolve --retry)"
{ [[ "$out" == *"RESOLVED=no"* ]] && [[ -f "$WT/.craft/handoff.md" ]]; } && ok "--retry does not rename a LIVE non-failure marker" || bad "retry on live (out=$out)"

marker awaiting-test 'slice-007' 'not a/date:*'; plan testing
out="$(bash "$HELPER" "$WT" --resolve)"
name="$(printf '%s\n' "$out" | sed -n 's/^RESOLVED=//p')"
{ [[ "$(dirname "$name")" == "$WT/.craft" ]] && [[ -f "$name" ]]; } && ok "an odd Written value cannot escape .craft/ in the resolved name" || bad "stamp sanitizing (name=$name)"

# --- arguments ----------------------------------------------------------------------------
bash "$HELPER" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "missing worktree argument → exit 2" || bad "missing arg (rc=$rc)"
bash "$HELPER" "$WT" --retry >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "--retry without --resolve → exit 2" || bad "retry without resolve (rc=$rc)"
bash "$HELPER" "$ROOT/does-not-exist" >/dev/null 2>&1; rc=$?
[[ $rc -eq 4 ]] && ok "unreachable worktree → exit 4" || bad "unreachable (rc=$rc)"

# --- SKILL.md table agrees with the helper -----------------------------------------------
# The pairing is described twice: executable in the helper, readable in the workflow skill.
# This binds them. Rows look like: | `awaiting-test` | `paused` |  or  | `failure` | — … |
skill_pairs="$(grep -E '^\| `(awaiting-[a-z-]+|failure)` \|' "$SKILL" \
  | sed -E 's/^\| `([a-z-]+)` \| *(`([a-z]+)`)?.*$/\1=\3/' | sort)"
helper_pairs="$(bash "$HELPER" --print-pairing | sort)"
{ [[ -n "$skill_pairs" ]] && [[ "$skill_pairs" == "$helper_pairs" ]]; } \
  && ok "skills/workflow/SKILL.md pairing table matches the helper's" || bad "SKILL↔helper pairing drift: skill=[$(echo $skill_pairs)] helper=[$(echo $helper_pairs)]"

# The episode sources are described twice as well: EPISODES in the helper, the episode table in SKILL.md.
# Rows look like: | `paused` | the plan header's `Paused-since:` … |  or  | `reviewing` | the review round count …
skill_eps="$(awk '/^\| Plan at \| The episode is/{f=1; next} f && !/^\|/{f=0} f' "$SKILL" | grep -E '^\| `[a-z]+` \|' \
  | sed -E 's/^\| `([a-z]+)` \| ([^|]*)\|.*$/\1 \2/' \
  | sed -E 's/^([a-z]+) .*`([A-Z][A-Za-z-]+):`.*$/\1=\2/; s/^([a-z]+) .*round count.*$/\1=round/' | sort)"
helper_eps="$(bash "$HELPER" --print-episodes | sort)"
{ [[ -n "$skill_eps" ]] && [[ "$skill_eps" == "$helper_eps" ]]; } \
  && ok "skills/workflow/SKILL.md episode table matches the helper's EPISODES" || bad "SKILL↔helper episode drift: skill=[$(echo $skill_eps)] helper=[$(echo $helper_eps)]"
missing_ep=""
while IFS= read -r p; do
  [[ -z "${p#*=}" ]] && continue
  printf '%s\n' "$helper_eps" | grep -q "^${p#*=}=" || missing_ep="$missing_ep ${p#*=}"
done <<EOF
$helper_pairs
EOF
[[ -z "$missing_ep" ]] && ok "every paired plan status has an episode source" || bad "paired plan status without an episode:$missing_ep"

# --- the writers agree with the pairing --------------------------------------------------
# Liveness is only right if each writer really leaves the plan at the paired status. Every
# place that writes a handoff marker carries `<!-- craft:handoff status=<s> plan=<p> -->`
# (`plan=-` for failure). This binds the markers' presence and declared plan status to the
# helper — not the meaning of the prose beneath them (the slice-031 residual, disclosed).
writer_markers="$(grep -rhoE '<!-- craft:handoff status=[a-z-]+ plan=[a-z-]+ -->' "$REPO_ROOT/commands" "$REPO_ROOT/agents" "$REPO_ROOT/skills" \
  | sed -E 's/<!-- craft:handoff status=([a-z-]+) plan=([a-z-]+) -->/\1=\2/' | sed 's/=-$/=/' | sort -u)"
mismatch=""
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  printf '%s\n' "$helper_pairs" | grep -qxF -- "$m" || mismatch="$mismatch $m"
done <<EOF
$writer_markers
EOF
[[ -z "$mismatch" ]] && ok "every craft:handoff writer marker declares the plan status the helper pairs it with" \
  || bad "writer marker disagrees with the pairing:$mismatch (helper: $(echo $helper_pairs))"
missing_writer=""
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  printf '%s\n' "$writer_markers" | grep -qxF -- "$p" || missing_writer="$missing_writer ${p%%=*}"
done <<EOF
$helper_pairs
EOF
[[ -z "$missing_writer" ]] && ok "every paired marker status has at least one craft:handoff writer marker" \
  || bad "pairing entries with no writer marker:$missing_writer"

# "At least one" cannot see a deleted second writer (failure has two). Pin the full set of
# (file, status) writer pairs; a new writer must be added here deliberately.
EXPECTED_WRITERS="agents/slice-builder.md awaiting-block-decision
agents/slice-builder.md failure
commands/build.md awaiting-protocol
commands/build.md awaiting-scope-decision
commands/refactor.md awaiting-refactor-decision
commands/review.md awaiting-rethink-decision
commands/test.md awaiting-test
commands/test.md failure"
actual_writers="$(cd "$REPO_ROOT" && grep -roE '<!-- craft:handoff status=[a-z-]+ plan=[a-z-]+ -->' commands agents skills \
  | sed -E 's/^([^:]+):<!-- craft:handoff status=([a-z-]+) plan=.*$/\1 \2/' | sort)"
[[ "$actual_writers" == "$EXPECTED_WRITERS" ]] && ok "the craft:handoff writer markers are exactly the 8 expected (file, status) pairs" \
  || bad "writer marker set changed: got [$(printf '%s' "$actual_writers" | tr '\n' ';')]"

# Episodes (B11) are only as good as their writers, too. Every non-failure writer marker must name
# `Episode:` nearby (the build overrides share the paragraph just above their bullets; slice-builder's
# block marker precedes its template), and every `craft:writes status=paused` the pause record. Like
# the markers themselves, this binds the declaration's presence, not the prose's meaning (slice-031).
near() { # file line pattern radius → 0 when the pattern occurs within ±radius lines
  awk -v l="$2" -v r="$4" 'NR >= l - r && NR <= l + r' "$REPO_ROOT/$1" | grep -qF -- "$3"
}
no_episode=""
while IFS=: read -r f l rest; do
  [[ -z "$f" ]] && continue
  [[ "$rest" == *"status=failure "* ]] && continue
  near "$f" "$l" 'Episode:' 15 || no_episode="$no_episode $f:$l"
done <<EOF
$(cd "$REPO_ROOT" && grep -rnoE '<!-- craft:handoff status=[a-z-]+ plan=[a-z-]+ -->' commands agents skills)
EOF
[[ -z "$no_episode" ]] && ok "every non-failure craft:handoff writer names the marker's Episode: next to its write" \
  || bad "handoff writer without an Episode: nearby:$no_episode"
no_record=""
while IFS=: read -r f l rest; do
  [[ -z "$f" ]] && continue
  near "$f" "$l" 'ause record' 3 || no_record="$no_record $f:$l"
done <<EOF
$(cd "$REPO_ROOT" && grep -rnoE '<!-- craft:writes status=paused -->' commands agents skills)
EOF
[[ -z "$no_record" ]] && ok "every craft:writes status=paused writer names the pause record next to its write" \
  || bad "paused writer without the pause record nearby:$no_record"
# Writers without a status marker (refactor's Subagent Mode may not declare a write; slice-builder's
# restatements and failure path) are pinned by name: each file must point at the pause record.
for f in commands/refactor.md agents/slice-builder.md commands/execute.md; do
  grep -qF 'Pause record' "$REPO_ROOT/$f" && ok "$f points its pauses at the Pause record" || bad "$f pauses without the Pause record"
done
grep -qF '4a. Resume a paused slice' "$REPO_ROOT/commands/continue.md" && grep -qF 'Paused-status' "$REPO_ROOT/commands/continue.md" \
  && ok "commands/continue.md defines the resume (4a) that restores Paused-status" || bad "commands/continue.md lost its resume step"

# --- the readers: every command that reads a marker is named where the lifecycle is defined ----
# A reader that counts or shows markers without the helper brings stale markers back (B7); one that
# removes a worktree without reading it deletes a live one unseen (B10). Pin the set of commands
# calling the helper, and bind it to the Readers bullet of skills/workflow/SKILL.md both ways.
EXPECTED_READERS="abort
execute
worktree-clean
worktree-status"
actual_readers="$(cd "$REPO_ROOT/commands" && grep -lF 'scripts/handoff-marker-state.sh' *.md | sed 's/\.md$//' | sort)"
[[ "$actual_readers" == "$EXPECTED_READERS" ]] && ok "the commands reading a handoff marker are exactly abort, execute, worktree-clean, worktree-status" \
  || bad "reader command set changed: got [$(printf '%s' "$actual_readers" | tr '\n' ';')]"
readers_bullet="$(awk '/^- \*\*Readers\*\*/{f=1; print; next} f && /^- \*\*/{f=0} f' "$SKILL")"
skill_readers="$(printf '%s\n' "$readers_bullet" | grep -oE '/craft:[a-z-]+' | sed 's|/craft:||' | sort -u)"
[[ -n "$readers_bullet" && "$skill_readers" == "$actual_readers" ]] && ok "SKILL.md Readers bullet names exactly the commands that call the helper" \
  || bad "Readers bullet ↔ commands drift: skill=[$(echo $skill_readers)] commands=[$(echo $actual_readers)]"
for r in abort worktree-clean; do
  grep -qF 'MARKER_STATUS' "$REPO_ROOT/commands/$r.md" && ok "commands/$r.md shows the live marker's status before removal" \
    || bad "commands/$r.md reads the helper but never shows MARKER_STATUS"
  grep -qF 'state unknown (helper could not run)' "$REPO_ROOT/commands/$r.md" && ok "  … and says what to show on the helper fallback" \
    || bad "commands/$r.md has no text for the helper fallback (no MARKER_STATUS to show)"
done

# --- the SessionStart hook ------------------------------------------------------------------
MAIN="$ROOT/main"
mkdir -p "$MAIN" && git -C "$MAIN" init -q && git -C "$MAIN" -c user.email=t@x -c user.name=t commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$ROOT/wt-live" -b slice-001-live
git -C "$MAIN" worktree add -q "$ROOT/wt-stale" -b slice-002-stale
put() { # worktree slice-id marker-status plan-status
  mkdir -p "$1/.craft" "$1/.claude/plans"
  printf -- '---\nSlice-ID: %s\nStatus: %s\nPhase: 5\nWritten: 2026-09-14T10:00:00Z\n---\n\n# Handoff: %s\n' "$2" "$3" "$2 title" > "$1/.craft/handoff.md"
  printf '> Status: %s\n' "$4" > "$1/.claude/plans/$2-x.md"
}
put "$ROOT/wt-live" slice-001 awaiting-test paused
put "$ROOT/wt-stale" slice-002 awaiting-test testing

out="$(CLAUDE_PROJECT_DIR="$MAIN" bash "$HOOK" 2>&1)"
{ [[ "$out" == *"slice-001 (awaiting-test)"* ]] && [[ "$out" != *"slice-002"* ]]; } \
  && ok "hook lists the live marker and stays silent about the stale one" || bad "hook live/stale (out=$out)"

put "$ROOT/wt-live" slice-001 awaiting-test testing
out="$(CLAUDE_PROJECT_DIR="$MAIN" bash "$HOOK" 2>&1)"
[[ -z "$out" ]] && ok "hook is silent when every marker is stale" || bad "hook all stale (out=$out)"
[[ -f "$ROOT/wt-stale/.craft/handoff.md" ]] && ok "hook never renames a marker (read-only)" || bad "hook renamed a marker"

# fail-open: a hook copy with no helper next to it lists every marker, as before B7
put "$ROOT/wt-live" slice-001 awaiting-test paused
mkdir -p "$ROOT/lonely/hooks" && cp "$HOOK" "$ROOT/lonely/hooks/"
out="$(CLAUDE_PROJECT_DIR="$MAIN" CLAUDE_PLUGIN_ROOT="$ROOT/lonely" bash "$ROOT/lonely/hooks/worktree-handoff-notify.sh" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"slice-001"* ]] && [[ "$out" == *"slice-002"* ]]; } \
  && ok "hook without a helper falls back to listing every marker (fail-open)" || bad "hook fail-open (rc=$rc, out=$out)"

# fail-open: a helper that exists but fails (non-zero, no output) must not hide a marker either
put "$ROOT/wt-stale" slice-002 awaiting-test testing
mkdir -p "$ROOT/broken/hooks" "$ROOT/broken/scripts" && cp "$HOOK" "$ROOT/broken/hooks/"
printf '#!/usr/bin/env bash\nexit 3\n' > "$ROOT/broken/scripts/handoff-marker-state.sh"
out="$(CLAUDE_PROJECT_DIR="$MAIN" bash "$ROOT/broken/hooks/worktree-handoff-notify.sh" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$out" == *"slice-001"* ]] && [[ "$out" == *"slice-002"* ]]; } \
  && ok "hook with a failing helper (exit 3, no output) lists every marker (fail-open)" || bad "hook failing helper (rc=$rc, out=$out)"

if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]]; then
  # PATH=/bin first, so the hook's own `bash "$HELPER"` call also resolves to the old bash
  out="$(PATH="/bin:$PATH" CLAUDE_PROJECT_DIR="$MAIN" /bin/bash "$HOOK" 2>&1)"; rc=$?
  { [[ $rc -eq 0 ]] && [[ "$out" == *"slice-001"* ]] && [[ "$out" != *"slice-002"* ]] && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash $(/bin/bash -c 'echo $BASH_VERSION'): hook + helper give the same answer, no shell errors" || bad "bash 3.2 hook (rc=$rc, out=$out)"
  marker awaiting-test; plan testing
  out="$(/bin/bash "$HELPER" "$WT" 2>&1)"
  { [[ "$out" == *"STATE=STALE"* ]] && [[ "$out" != *"line "*": "* ]]; } && ok "under /bin/bash 3.2: helper runs without shell errors" || bad "bash 3.2 helper (out=$out)"
  rm -f "$WT/.claude/plans/"*.md
  out="$(/bin/bash "$HELPER" "$WT" 2>&1)"
  { [[ "$out" == *"REASON=plan_not_found"* ]] && [[ "$out" != *"unbound variable"* ]] && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash 3.2: an empty plan list under set -u gives plan_not_found, no shell error" || bad "bash 3.2 empty array (out=$out)"
  marker failure; plan implementing
  out="$(/bin/bash "$HELPER" "$WT" --resolve --retry 2>&1)"
  { [[ "$out" == *"RESOLVED=$WT/.craft/handoff-resolved-"* ]] && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash 3.2: --resolve --retry renames without shell errors" || bad "bash 3.2 resolve (out=$out)"
  marker_ep awaiting-test "$T1"; plan_ep paused "> Paused-since: $T2\n"
  out="$(/bin/bash "$HELPER" "$WT" 2>&1)"
  { [[ "$out" == *"REASON=episode_mismatch"* ]] && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash 3.2: a header-stamp episode mismatch, no shell errors" || bad "bash 3.2 episode (out=$out)"
  marker_ep awaiting-rethink-decision 1; plan_ep reviewing "" "$ROUND1_ROUTED"
  out="$(PATH="$ROOT/failbash:$PATH" /bin/bash "$HELPER" "$WT" 2>&1)"
  { [[ "$out" == *"REASON=findings_closed"* ]] && [[ "$out" != *"line "*": "* ]]; } \
    && ok "under /bin/bash 3.2: the findings parser runs with the helper's bash (findings_closed), no shell errors" || bad "bash 3.2 findings episode (out=$out)"
  rm -f "$WT/.claude/plans/"*.md
else
  echo "  SKIP  no bash < 4 at /bin/bash — old-bash runs not exercised"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
