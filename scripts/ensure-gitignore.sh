#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# ensure-gitignore.sh — keep CRAFT's local state out of version control (B4)
#
# WHY ------------------------------------------------------------------------
# CRAFT writes local, per-clone state into the project: the per-session prime
# marker, the hook's bash record, the /craft:execute run lock, the local settings
# file, and the worktree handoff marker. Left unignored, a primed session shows
# untracked files in every `git status` (CRAFT's clean-tree checks do not count them —
# scripts/tree-dirt-state.sh reads this list). Consumer
# projects ignore these paths in inconsistent hand-written shapes — or not at all —
# so /craft:onboard (new projects) and /craft:prime (existing ones) run this helper.
#
# WHAT -----------------------------------------------------------------------
# Decides, per CRAFT path, whether a rule in the project's own .gitignore files
# already ignores it, then either reports (`--check`) or appends the uncovered
# paths to a marked block in the project's .gitignore (`--apply`).
#
# The project is CLAUDE_PROJECT_DIR (else the cwd), which need not be the git top
# level — the hook and /craft:prime write the markers relative to it, so probes run
# from there and the block goes into <project>/.gitignore, where its entries are
# anchored to the project, not to the repository root.
#
#   --check    (default)  Report each path. Never writes.
#   --apply               Append only the absent paths to the `# CRAFT local state`
#                         block — extending an existing block, else adding one at
#                         the end; create .gitignore if missing. Idempotent. Keeps
#                         the file's CRLF line endings; refuses a symlinked .gitignore.
#   --print-paths         Print the CRAFT local-state paths, one per line, and exit —
#                         scripts/tree-dirt-state.sh reads the list from here.
#   --verdict <path>      Print one word for <path> — yes (covered) | negated | no (absent)
#                         — and exit 0. Never writes. The settings helpers
#                         (ensure-readonly-context.sh, ensure-worktree-trust.sh) report
#                         their GITIGNORED= from this; exit 2/4 means no verdict.
#
# Coverage is what git actually does, not what a grep of .gitignore suggests:
# `git check-ignore -v --no-index` names the deciding rule. A path counts as
# covered only when that rule comes from a .gitignore inside the repo and is not a
# negation — a rule in the user's global excludes file or in .git/info/exclude
# lives in one clone only and would leave teammates uncovered. A deciding negation
# from the project's own .gitignore files (`!path`, wherever it stands, nested files
# included) is the project's decision to keep that path visible: it reads `negated`,
# is never appended, and does not count as missing (B9). git names a negation only
# when it matches the path itself, so a broader un-ignore such as `!.claude/plans/`
# after `.claude/*` leaves the file without a deciding rule — `absent`, and appended.
# Known limit: git names no rule for a negated *directory* either (`.craft/` then `!.craft/`),
# so that one negation reads `absent` and is overridden by the append. Detecting it would
# mean parsing .gitignore files by hand — the second, drifting copy of git's rules this
# helper exists to avoid.
#
# `--no-index` keeps a tracked file from reading as "not ignored"; TRACKED flags it,
# because ignoring a file does not untrack it — except a negated path: the project keeps
# it visible on purpose, and advising `git rm --cached` would contradict that.
#
# Output is line-oriented key=value so the calling command can parse it:
#   ENTRY=<path> STATUS=covered|negated|absent   one line per CRAFT path
#   TRACKED=<path>                       a CRAFT path git already tracks (ignore alone won't hide it); never for a negated path
#   GITIGNORE=exists|missing             whether .gitignore existed beforehand
#   MISSING=<n>                          number of absent paths (before apply); negated ones are not missing
#   STATUS=present|absent                aggregate: absent if any path is absent
#   CHANGED=yes|no                       (apply only) whether a write happened
#   ERROR=<reason>                       on failure (stderr), with a non-zero exit code
#
# Exit codes:
#   0   all covered (check), or apply succeeded / nothing to do
#   10  check only: one or more paths absent — the caller should offer --apply
#   2   unknown argument
#   4   project dir unreachable, or not inside a git work tree
#   5   write refused or failed (symlinked .gitignore, temp/backup/rename error); file untouched
#   6   apply wrote, but a rule still un-ignores a path; .gitignore restored byte-identical —
#       a safety net: a negation that matches a path already reads `negated` and is never appended
#
# Never rewrites or reorders existing lines; the write is atomic (temp file + rename),
# and no temp or backup file outlives the run. Bash-3.2-compatible on purpose — it runs
# wherever /craft:prime runs.

set -uo pipefail

# The CRAFT local-state paths — defined once, here. A trailing slash marks a
# directory; it is probed through a file inside it.
CRAFT_PATHS=(
  ".claude/plans/.primed"
  ".claude/plans/.hook-env"
  ".claude/plans/.execute.lock"
  ".claude/settings.local.json"
  ".craft/"
)
BLOCK_HEADER="# CRAFT local state (per-session markers, run lock, local settings, worktree handoff)"
BLOCK_PREFIX="# CRAFT local state"

MODE="check"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    --print-paths) printf '%s\n' "${CRAFT_PATHS[@]}"; exit 0 ;;
    --verdict)
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:--verdict" >&2; exit 2; }
      MODE="verdict"; VERDICT_PATH="$2"; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT_DIR}" >&2; exit 4; }
[[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || {
  echo "ERROR=not_a_git_work_tree:${PROJECT_DIR}" >&2; exit 4
}
# Paths below are relative to the project dir; git check-ignore and ls-files resolve
# them from the cwd, and name rule sources relative to the repository root.
GITIGNORE=".gitignore"

probe_for() {
  case "$1" in
    */) printf '%shandoff.md' "$1" ;;
    *)  printf '%s' "$1" ;;
  esac
}

# classify <path> — covered | negated | absent, by the deciding rule git names. Only a
# rule from an in-repo .gitignore counts, either way.
classify() {
  local out source pattern
  out="$(git check-ignore -v --no-index -- "$(probe_for "$1")" 2>/dev/null)" || { echo absent; return; }
  source="${out%%:*}"
  pattern="${out#*:}"; pattern="${pattern#*:}"; pattern="${pattern%%	*}"
  case "${source}" in
    /*) echo absent; return ;;   # a global excludes file, even one named ~/.gitignore
    .gitignore|*/.gitignore) ;;
    *) echo absent; return ;;
  esac
  case "${pattern}" in
    '!'*) echo negated ;;
    *) echo covered ;;
  esac
}
is_covered() { [[ "$(classify "$1")" == "covered" ]]; }

is_tracked() {
  [[ -n "$(git ls-files -- "$1" 2>/dev/null)" ]]
}

# --- verdict mode: one word for one path --------------------------------------
if [[ "${MODE}" == "verdict" ]]; then
  case "$(classify "${VERDICT_PATH}")" in
    covered) echo yes ;;
    negated) echo negated ;;
    *) echo no ;;
  esac
  exit 0
fi

GITIGNORE_STATE="missing"
[[ -f "${GITIGNORE}" ]] && GITIGNORE_STATE="exists"

ABSENT=()
report() {
  local p s
  for p in "${CRAFT_PATHS[@]}"; do
    echo "ENTRY=${p} STATUS=$(classify "${p}")"
  done
  for p in "${CRAFT_PATHS[@]}"; do
    [[ "$(classify "${p}")" != "negated" ]] && is_tracked "${p}" && echo "TRACKED=${p}"
  done
  echo "GITIGNORE=${GITIGNORE_STATE}"
}

for p in "${CRAFT_PATHS[@]}"; do
  [[ "$(classify "${p}")" == "absent" ]] && ABSENT+=("${p}")
done
MISSING=${#ABSENT[@]}

# --- check mode: report only -------------------------------------------------
if [[ "${MODE}" == "check" ]]; then
  report
  echo "MISSING=${MISSING}"
  if (( MISSING > 0 )); then echo "STATUS=absent"; exit 10; fi
  echo "STATUS=present"; exit 0
fi

# --- apply mode: append the absent paths to the marked block -----------------
if (( MISSING == 0 )); then
  report
  echo "MISSING=0"
  echo "STATUS=present"
  echo "CHANGED=no"
  exit 0
fi

# Renaming over a symlink would replace the link with a regular file and leave its
# target untouched — refuse instead of guessing which file the project meant.
[[ -L "${GITIGNORE}" ]] && { echo "ERROR=gitignore_is_symlink:${PROJECT_DIR}/${GITIGNORE}" >&2; exit 5; }

TMP="${GITIGNORE}.craft-tmp.$$"
BACKUP="${GITIGNORE}.craft-bak.$$"
KEEP_BACKUP=0
cleanup() {
  [[ -f "${TMP}" ]] && unlink "${TMP}"
  [[ "${KEEP_BACKUP}" == 0 && -f "${BACKUP}" ]] && unlink "${BACKUP}"
  return 0
}
trap cleanup EXIT

# A CRLF file keeps CRLF: the appended lines use the line ending the file already has.
EOL=$'\n'
[[ -f "${GITIGNORE}" ]] && grep -q $'\r' "${GITIGNORE}" && EOL=$'\r\n'
ENTRIES=""
for p in "${ABSENT[@]}"; do ENTRIES="${ENTRIES}${p}${EOL}"; done

if [[ -f "${GITIGNORE}" ]] && grep -q "^${BLOCK_PREFIX}" "${GITIGNORE}"; then
  # Extend the existing block: insert after its last non-blank line. The entries
  # travel through the environment — `awk -v` rejects embedded newlines on BSD awk.
  CRAFT_PREFIX="${BLOCK_PREFIX}" CRAFT_ENTRIES="${ENTRIES}" awk '
    function flush() { if (inblock) { printf "%s", ENVIRON["CRAFT_ENTRIES"]; inblock = 0; done = 1 } }
    {
      if (!done && index($0, ENVIRON["CRAFT_PREFIX"]) == 1) { inblock = 1; print; next }
      if (inblock && $0 ~ /^[[:space:]]*$/) { flush() }
      print
    }
    END { flush() }
  ' "${GITIGNORE}" > "${TMP}" || { echo "ERROR=write_failed:${TMP}" >&2; exit 5; }
else
  {
    if [[ -s "${GITIGNORE}" ]]; then
      cat "${GITIGNORE}"
      [[ -n "$(tail -c 1 "${GITIGNORE}")" ]] && printf '%s' "${EOL}"
      printf '%s' "${EOL}"
    fi
    printf '%s%s%s' "${BLOCK_HEADER}" "${EOL}" "${ENTRIES}"
  } > "${TMP}" || { echo "ERROR=write_failed:${TMP}" >&2; exit 5; }
fi
if [[ -f "${GITIGNORE}" ]]; then
  cp -p "${GITIGNORE}" "${BACKUP}" || { echo "ERROR=write_failed:${BACKUP}" >&2; exit 5; }
fi
mv "${TMP}" "${GITIGNORE}" || { echo "ERROR=write_failed:${GITIGNORE}" >&2; exit 5; }

# --- post-write verification -------------------------------------------------
# A later rule can still defeat the new entries (e.g. a negation below an existing
# block). Then the project deliberately un-ignores CRAFT state: restore the file
# untouched and let the human decide instead of fighting the rule.
for p in "${ABSENT[@]}"; do
  if ! is_covered "${p}"; then
    if [[ -f "${BACKUP}" ]]; then
      mv "${BACKUP}" "${GITIGNORE}" || {
        KEEP_BACKUP=1
        echo "ERROR=restore_failed:original kept at ${PROJECT_DIR}/${BACKUP}" >&2; exit 6
      }
    else
      unlink "${GITIGNORE}"
    fi
    echo "ERROR=post_write_uncovered:${p}" >&2; exit 6
  fi
done

report
echo "MISSING=${MISSING}"
echo "STATUS=present"
echo "CHANGED=yes"
exit 0
