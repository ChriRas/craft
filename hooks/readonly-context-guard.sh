#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# readonly-context-guard.sh — PreToolUse guard for read-only context sources (F1)
#
# WHY ------------------------------------------------------------------------
# A CRAFT project may keep reference material the agent should *read* but never
# *mutate*: an in-repo `research/` dump folder, and any declared external
# "connected projects". Claude Code's `additionalDirectories` grants read access
# but has no read-only flag, so nothing stops a Write/Edit from clobbering that
# reference material. This PreToolUse hook supplies the missing teeth: it denies
# any Write / Edit / NotebookEdit whose target lands inside a read-only root.
#
# WHAT -----------------------------------------------------------------------
# Reads the PreToolUse event JSON on stdin, extracts the tool name and target
# path, and compares the (absolute) target against the read-only roots:
#   1. convention — `<project>/research/` (always protected; no declaration).
#   2. declared   — bullet paths under the `## Read-Only Context Sources`
#                   section of `.claude/project/rules.md` (connected projects).
# On a match it prints a PreToolUse deny decision and exits 0; otherwise it
# prints nothing and exits 0 (the tool proceeds normally).
#
# CLOSED PLANS (B19) — `<project>/.claude/plans/.closed/` holds plans CRAFT closed by
# moving them (a user rule denies or asks on removing files). It is neither read nor
# written: Read / Grep / Glob whose target, search path, pattern or glob lands in it are
# denied too, and so is a write — for any path with a `.claude/plans/.closed` segment, in
# whichever checkout. Reading stays allowed everywhere else — research/ and
# connected projects are read-only, not read-blocked. On macOS / Linux / WSL, Claude Code
# searches through Bash `find` / `grep` by default, which no hook can judge reliably; Grep
# skips the directory once it is gitignored, and Glob may list its names, never content
# (code.claude.com/docs/en/tools-reference, 2026-09-30).
# KNOWN LIMIT: "gitignored" holds only once /craft:prime step 4f's block is applied; until
# then a Grep over a parent directory can return closed plans' content (no CRAFT scanner
# does such a Grep).
#
# FAIL-OPEN: if jq is missing or the event JSON is unparseable, the guard cannot
# know the target, so it allows the call (a stray write to research/ is a soft
# loss, but blocking *every* write would brick the agent). The miss is logged to
# stderr, which Claude Code surfaces in debug output.

set -uo pipefail

# normalize_path PATH — pure-lexical path normalization (NO filesystem or symlink
# access: a Write target legitimately may not exist yet). Resolves "." and ".."
# segments and collapses redundant "/" purely textually. Kept in lockstep with the
# sync helper scripts/ensure-readonly-context.sh, which normalizes the same declared
# bullets with python3 os.path.normpath; this function reproduces normpath semantics
# over the whole input domain, including the POSIX double-slash rule (exactly two
# leading slashes are preserved; three or more collapse to one). The guard↔helper
# agreement is asserted on a shared fixture set by scripts/test-readonly-context.sh.
normalize_path() {
  local path="$1" abs=0 root="/" rest comp n=0 i result=""
  local -a stack=()
  [[ -n "$path" ]] || { printf '.'; return 0; }   # normpath("") == "."
  if [[ "$path" == /* ]]; then
    abs=1
    [[ "$path" == //* && "$path" != ///* ]] && root="//"
  fi
  # Split on "/" by parameter expansion, not `IFS=/ read`: `read` stops at the first
  # newline, but normpath treats "\n" as an ordinary path character.
  rest="$path"
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    case "$comp" in
      ''|.) ;;                                  # drop empty (from "//") and "."
      ..)
        if (( n > 0 )) && [[ "${stack[n-1]}" != ".." ]]; then
          (( n-- ))                             # pop a real segment
        elif (( ! abs )); then
          stack[n]=".."; (( n++ ))              # relative path: keep a leading ".."
        fi                                      # absolute "..": drop (cannot pass root)
        ;;
      *) stack[n]="$comp"; (( n++ )) ;;
    esac
  done
  for (( i = 0; i < n; i++ )); do result="$result/${stack[i]}"; done
  if (( abs )); then
    result="${root}${result#/}"                 # "/", "/.." → "/"; "//a" keeps its root
  else
    if [[ -n "$result" ]]; then result="${result#/}"; else result="."; fi  # "a/.." → "."
  fi
  printf '%s' "$result"
}

# Diagnostic mode (never triggered by a PreToolUse event, which passes no argv):
# emit the lexical normalization of a path and exit. Lets the test harness assert
# guard↔helper normalizer agreement against this exact function instead of a copy.
if [[ "${1:-}" == "--normalize" ]]; then
  normalize_path "${2:-}"; printf '\n'
  exit 0
fi

# --- read the event -----------------------------------------------------------
input="$(cat)"

# jq parses the event; without it the guard is disabled (fail-open).
if ! command -v jq >/dev/null 2>&1; then
  echo "readonly-context-guard: jq not found — guard disabled (fail-open)" >&2
  exit 0
fi

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || {
  echo "readonly-context-guard: unparseable event JSON — allowing (fail-open)" >&2
  exit 0
}

# The write-family tools are guarded against every read-only root; the read-family
# tools only against the closed-plans directory. Re-checking here means a broader
# matcher can never turn the guard into a blocker for anything else.
case "$tool_name" in
  Write|Edit|NotebookEdit|Read|Grep|Glob) ;;
  *) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)}"
project_dir="${project_dir:-$PWD}"

# in_closed CANDIDATE BASE — true when CANDIDATE (a path or a glob pattern), joined to
# BASE when relative and normalized, lands in a closed-plans directory — this project's
# or any other checkout's (a session started in a slice worktree reads the main one's too).
in_closed() {
  local c="$1" b="$2"
  [[ -n "$c" ]] || return 1
  case "$c" in
    /*) : ;;
    *) c="$b/$c" ;;
  esac
  c="$(normalize_path "$c")"
  [[ "$c" == */.claude/plans/.closed || "$c" == */.claude/plans/.closed/* ]]
}
deny_closed() {
  # The reason sets the boundary itself: an open "ask the human" let an agent offer to
  # loosen the block as one option among others (slice-050, Phase 5).
  jq -cn --arg r "$1 is blocked on purpose: .claude/plans/.closed/ holds plans CRAFT closed by moving them instead of deleting them (B19). Do not read it another way, and do not suggest changing or disabling this block. If the human needs the plan, they can open it themselves." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# --- read family: only the closed-plans directory -------------------------------
# Read carries file_path; Grep path (+ glob); Glob path (+ pattern). A relative
# pattern or glob is taken relative to the search path, which defaults to the project.
case "$tool_name" in
  Read|Grep|Glob)
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    sp="$(printf '%s' "$input" | jq -r '.tool_input.path // empty' 2>/dev/null)"
    pat="$(printf '%s' "$input" | jq -r '.tool_input.pattern // empty' 2>/dev/null)"
    gl="$(printf '%s' "$input" | jq -r '.tool_input.glob // empty' 2>/dev/null)"
    base="$project_dir"
    if [[ -n "$sp" ]]; then
      case "$sp" in /*) base="$sp" ;; *) base="$project_dir/$sp" ;; esac
    fi
    in_closed "$fp" "$project_dir" && deny_closed "$tool_name of $fp"
    in_closed "$sp" "$project_dir" && deny_closed "$tool_name in $sp"
    in_closed "$gl" "$base" && deny_closed "$tool_name with glob $gl"
    if [[ "$tool_name" == Glob ]]; then
      in_closed "$pat" "$base" && deny_closed "Glob of $pat"
    fi
    exit 0
    ;;
esac

# Write/Edit carry file_path; NotebookEdit carries notebook_path.
target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
[[ -n "$target" ]] || exit 0

# --- resolve paths ------------------------------------------------------------

# Target is normally already absolute (Claude requires absolute paths for
# Write/Edit); join defensively if a relative path ever arrives.
case "$target" in
  /*) abs_target="$target" ;;
  *)  abs_target="$project_dir/$target" ;;
esac

# Normalize away "." / ".." / redundant "/" so a traversal segment can neither
# slip past the guard (commands/../research/x) nor false-deny a real write
# (research/../commands/x). Roots below are normalized the same way.
abs_target="$(normalize_path "$abs_target")"
in_closed "$abs_target" "$project_dir" && deny_closed "$tool_name of $abs_target"

# is_under CANDIDATE ROOT — true when CANDIDATE is ROOT itself or sits below it.
# The `/` boundary check prevents `/a/research` from matching `/a/research-x`.
is_under() {
  local c="$1" r="${2%/}"
  [[ -n "$r" ]] || return 1
  [[ "$c" == "$r" || "$c" == "$r"/* ]]
}

# --- collect read-only roots --------------------------------------------------
# 1. Convention: the in-repo research/ folder.
roots=("$(normalize_path "$project_dir/research")")
labels=("research/ (in-repo reference dump)")

# 2. Declared connected projects: bullet paths under the rules.md section.
rules_file="$project_dir/.claude/project/rules.md"
if [[ -f "$rules_file" ]]; then
  while IFS= read -r decl; do
    [[ -n "$decl" ]] || continue
    # Expand only the "~/" (and bare "~") form — never "~user", whose home the
    # helper resolves via os.path.expanduser and this guard cannot. Both sides are
    # gated identically so a "~user" bullet stays literal in guard and helper alike;
    # rules.md declares absolute paths anyway.
    case "$decl" in
      '~'|'~/'*) decl="$HOME${decl#\~}" ;;
    esac
    case "$decl" in
      /*) : ;;                                # already absolute
      *)  decl="$project_dir/$decl" ;;        # resolve relative to the project
    esac
    decl="$(normalize_path "$decl")"          # match the helper's os.path.normpath
    roots+=("$decl")
    labels+=("declared connected project ($decl)")
  done < <(
    awk '
      /^## Read-Only Context Sources/ { inblock = 1; next }
      inblock && /^## /               { inblock = 0 }
      inblock && /^[[:space:]]*-[[:space:]]/ {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)   # drop the bullet marker
        gsub(/`/, "", line)                            # drop backticks
        sub(/[[:space:]]+(—|#|<).*$/, "", line)        # drop trailing note/placeholder
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)  # trim
        if (line != "") print line
      }
    ' "$rules_file"
  )
fi

# --- decide -------------------------------------------------------------------
i=0
for root in "${roots[@]}"; do
  if is_under "$abs_target" "$root"; then
    reason="${labels[$i]} is a read-only context source — reading is allowed, writing is blocked. Blocked path: ${abs_target}"
    jq -cn --arg r "$reason" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  i=$((i + 1))
done

# No read-only root matched — allow the tool call to proceed.
exit 0
