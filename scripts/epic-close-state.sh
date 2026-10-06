#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# epic-close-state.sh — can /craft:commit close this epic now? (slice-061 / slice-062, roadmap B24 / B26, D37 / D38)
#
# WHY ------------------------------------------------------------------------
# After an autopilot run's a5 [Y] — and after a sequential run's s5 — no CRAFT command wrote the epic
# archive or closed the epic plan: /craft:commit closed an epic only in Epic-finalize mode, which it
# detects by an epic worktree neither run creates. epic-001…003 were closed by hand. /craft:commit's
# Epic-close mode closes them now, and whether an epic is ready for that is decided here, once — derived
# from git and the epic plan, never stored (the pattern of execute-resume-state.sh and plan-gate-state.sh).
#
# WHAT -----------------------------------------------------------------------
#   epic-close-state.sh --trunk <branch> [<epic-plan>…]
#
# Run from the project root (or set CLAUDE_PROJECT_DIR); plan paths are relative to it. Without a plan,
# every .claude/plans/epic-*.md is judged. One line per plan, then the counts:
#
#   EPIC=<epic-id>|- PLAN=<path> KIND=<kind>|- STATE=<state> BRANCH=<branch>|- BRANCH_STATE=<branch-state>|- REASON=<reason>|-
#   EPIC_COUNT=<n>
#   CLOSABLE_COUNT=<n>
#
# KIND is `autopilot` when the epic plan's `## Autopilot Log` holds a log line
# (`- <datetime> · <▶|✓|⛔|■> · <id> · <text>`), else `sequential` — a sequential run, or an epic worked
# slice by slice by hand; `-` on a malformed plan. The checks run in this order; the first that fails names
# the state, and a later one is not judged (its fields read `-`):
#
#   malformed        the plan is unreadable, or its frontmatter (above the first `## `) lacks
#                    `> Epic-ID:` or `> Epic-Slug:` — REASON epic_plan_unreadable | epic_frontmatter:<key>
#   (autopilot only — the human's a5 answer; a sequential epic has none and skips these three)
#   not-signed-off   no `■` line for this epic-ID in that section: a run still open, or a5's question never
#                    answered (REASON no_answer) — or the last one is no a5 answer at all: a run that stopped
#                    before a5, e.g. at the plan gate's or the orphan question's `[N]` (REASON run_stopped)
#   not-merged       the LAST `■` line of this epic is a5's `[N]`, `complete, not merged` (REASON not_merged),
#                    or a merge into another branch (REASON merged_into:<branch>)
#   pr-path          the last `■` line is `PR #<N> opened` — the pull-request path, which this mode does not
#                    close (D37). REASON pr_opened
#   (both kinds)
#   entries-open     `epic-entry-link.sh resolve` does not report every entry `landed` — REASON
#                    not_landed:<slice-id or ->:<state> (the first such entry) | no_entries | unresolved (an
#                    IGNORED line) | resolve_failed
#   branch-unmerged  the epic branch `<epic-id>-<epic-slug>` is not merged into the trunk. BRANCH_STATE
#                    unmerged (it exists, and no merge commit on the trunk has its tip as a non-first parent —
#                    the ancestor trap: a branch without own commits is an ancestor of every trunk, yet nothing
#                    was merged; commits added after the merge read the same) | missing (autopilot only: it is
#                    gone, and no merge commit on the trunk is titled `Merge <epic-id>: …`, a5's subject).
#                    REASON branch_unmerged | branch_missing
#   closable         all of the above hold. BRANCH_STATE merged (the branch exists) | deleted (autopilot: it is
#                    gone, its merge is on the trunk — deleted by hand, or by a close that stopped after its
#                    branch step) | none (sequential: there is no epic branch). REASON -
#
# Only the `## Autopilot Log` section counts (up to the next `# ` / `## ` heading), outside example regions
# (fenced blocks, multi-line HTML comments — scripts/example-regions.sh decides). CRLF reads as LF.
#
# Errors — `ERROR=<reason>` on stderr, a non-zero exit, no STATE line:
#   2  usage (no --trunk, or an unknown option)
#   3  project_dir_unreachable
#   4  helper_missing:<name>
#   5  not_a_git_repo · trunk_missing:<branch>
#
# Read-only: it writes nothing but its own temp files (removed on exit). The contract is
# scripts/test-epic-close-state.sh, written before this file.

set -uo pipefail

die() { echo "ERROR=$2" >&2; exit "$1"; }

TRUNK=""
PLANS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trunk) [[ $# -ge 2 && -n "$2" ]] || die 2 "usage"; TRUNK="$2"; shift 2 ;;
    -*) die 2 "usage" ;;
    *) PLANS+=("$1"); shift ;;
  esac
done
[[ -n "$TRUNK" ]] || die 2 "usage"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$SCRIPT_DIR/epic-entry-link.sh"
REGIONS="$SCRIPT_DIR/example-regions.sh"
[[ -f "$LINK" ]] || die 4 "helper_missing:epic-entry-link.sh"
[[ -f "$REGIONS" ]] || die 4 "helper_missing:example-regions.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" 2>/dev/null || die 3 "project_dir_unreachable"

git rev-parse --git-dir >/dev/null 2>&1 || die 5 "not_a_git_repo"
git show-ref --verify --quiet "refs/heads/$TRUNK" || die 5 "trunk_missing:$TRUNK"

if [[ ${#PLANS[@]} -eq 0 ]]; then
  shopt -s nullglob
  PLANS=(.claude/plans/epic-*.md)
  shopt -u nullglob
fi

TMP="$(mktemp -d)" || die 4 "helper_missing:mktemp"
trap 'rm -rf "$TMP"' EXIT

LOG_LINE='^- [^ ]+ · (▶|✓|⛔|■) · [^ ]+ · '

# is <branch> merged into the trunk? Only a merge commit whose non-first parent is the branch tip counts
# (the ancestor trap — the same rule as execute-resume-state.sh's is_merged).
is_merged() {
  local tip fields i
  tip="$(git rev-parse "refs/heads/$1")"
  while read -r -a fields; do
    for (( i = 2; i < ${#fields[@]}; i++ )); do [[ "${fields[$i]}" == "$tip" ]] && return 0; done
  done < <(git rev-list --merges --parents "refs/heads/$TRUNK" 2>/dev/null)
  return 1
}

frontmatter() { # blanked-file key
  awk -v key="$2" '
    /^## / { exit }
    { if (match($0, "^>[ \t]*" key ":[ \t]*[^ \t]+")) { v = substr($0, RSTART, RLENGTH); sub("^>[ \t]*" key ":[ \t]*", "", v); print v; exit } }
  ' "$1"
}

CLOSABLE=0
COUNT=0
emit() { # epic plan state branch branch-state reason — KIND is judge()'s `kind`
  printf 'EPIC=%s PLAN=%s KIND=%s STATE=%s BRANCH=%s BRANCH_STATE=%s REASON=%s\n' "$1" "$2" "$kind" "$3" "$4" "$5" "$6"
  [[ "$3" == "closable" ]] && CLOSABLE=$((CLOSABLE + 1))
}

judge() {
  local plan="$1" blank="$TMP/plan" kind=- id slug branch log last text resolved line sid state
  if [[ ! -f "$plan" || ! -r "$plan" ]] || ! bash "$REGIONS" blank markdown "$plan" 2>/dev/null | tr -d '\r' > "$blank"; then
    emit - "$plan" malformed - - epic_plan_unreadable; return
  fi
  id="$(frontmatter "$blank" Epic-ID)"
  [[ -n "$id" ]] || { emit - "$plan" malformed - - "epic_frontmatter:Epic-ID"; return; }
  slug="$(frontmatter "$blank" Epic-Slug)"
  [[ -n "$slug" ]] || { emit "$id" "$plan" malformed - - "epic_frontmatter:Epic-Slug"; return; }
  branch="$id-$slug"

  log="$(awk '$0 == "## Autopilot Log" { f = 1; next } f && /^##? / { exit } f' "$blank" | grep -E "$LOG_LINE")"
  if [[ -n "$log" ]]; then
    kind=autopilot
    last="$(grep -F -- " · ■ · $id · " <<<"$log" | tail -n 1)"
    [[ -n "$last" ]] || { emit "$id" "$plan" not-signed-off - - no_answer; return; }
    text="${last#* · ■ · "$id" · }"
    text="${text%"${text##*[![:space:]]}"}"
    case "$text" in
      "merged into $TRUNK") ;;
      "merged into "*) emit "$id" "$plan" not-merged - - "merged_into:${text#merged into }"; return ;;
      "PR #"*" opened") emit "$id" "$plan" pr-path - - pr_opened; return ;;
      "complete, not merged") emit "$id" "$plan" not-merged - - not_merged; return ;;
      *) emit "$id" "$plan" not-signed-off - - run_stopped; return ;;
    esac
  else
    kind=sequential
  fi

  resolved="$(CLAUDE_PROJECT_DIR="$PWD" bash "$LINK" resolve "$plan" 2>/dev/null)" ||
    { emit "$id" "$plan" entries-open - - resolve_failed; return; }
  grep -q '^ENTRY_COUNT=' <<<"$resolved" || { emit "$id" "$plan" entries-open - - resolve_failed; return; }
  [[ "$(sed -n 's/^ENTRY_COUNT=//p' <<<"$resolved")" != "0" ]] || { emit "$id" "$plan" entries-open - - no_entries; return; }
  while IFS= read -r line; do
    [[ "$line" == SLICE=* ]] || continue
    sid="$(sed -n 's/^SLICE=\([^ ]*\) .*/\1/p' <<<"$line")"
    state="$(sed -n 's/.* STATE=\([^ ]*\) .*/\1/p' <<<"$line")"
    [[ "$state" == "landed" ]] || { emit "$id" "$plan" entries-open - - "not_landed:$sid:$state"; return; }
  done <<<"$resolved"
  grep -q '^RESULT=ok$' <<<"$resolved" || { emit "$id" "$plan" entries-open - - unresolved; return; }

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    is_merged "$branch" || { emit "$id" "$plan" branch-unmerged "$branch" unmerged branch_unmerged; return; }
    emit "$id" "$plan" closable "$branch" merged -
  elif [[ "$kind" == sequential ]]; then
    emit "$id" "$plan" closable "$branch" none -
  elif git log --merges --format='%s' "refs/heads/$TRUNK" 2>/dev/null | grep -q -- "^Merge $id: "; then
    emit "$id" "$plan" closable "$branch" deleted -
  else
    emit "$id" "$plan" branch-unmerged "$branch" missing branch_missing
  fi
}

for p in "${PLANS[@]+"${PLANS[@]}"}"; do
  COUNT=$((COUNT + 1))
  judge "$p"
done
echo "EPIC_COUNT=$COUNT"
echo "CLOSABLE_COUNT=$CLOSABLE"
