#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# check-plugin-cache-drift.sh — does the running plugin match the working tree? (B2)
#
# WHY ------------------------------------------------------------------------
# Claude Code copies marketplace plugins into ~/.claude/plugins/cache/<mkt>/<plugin>/<version>/
# and executes that copy — not the repository the plugin is developed in. When CRAFT is
# dogfooded in its own source repo, a session can therefore run *older* command logic than
# the working tree shows, and no slice touching commands/ can be verified live in the
# session that writes it. The cache directory is named by the plugin version, which does
# not change while the repo does, so a version compare detects nothing. This helper compares
# the *content* of the runtime surface instead.
#
# WHAT -----------------------------------------------------------------------
#   --plugin-root <dir>   (required) the running plugin's root, i.e. ${CLAUDE_PLUGIN_ROOT}
#   --project <dir>       the project root (default: CLAUDE_PROJECT_DIR, else git toplevel, else pwd)
#
# The project counts as the plugin's source repo ("dev repo") when its
# .claude-plugin/plugin.json carries the same "name" as the running plugin's manifest.
# If the plugin root *is* the project (e.g. `claude --plugin-dir .`), the runtime is the
# working tree by definition.
#
# Repo-side files come from `git ls-files -co --exclude-standard` (tracked + untracked, minus
# ignored), so uncommitted edits count and ignored clutter does not. Only RUNTIME_PATHS are
# compared — documentation (README, CHANGELOG, docs/) never changes what a session executes.
#
# Output is line-oriented key=value:
#   STATUS=in-sync|diverged|not-dev-repo|unknown
#   RUNTIME=cache|working-tree      (dev repo only)
#   DIFF_COUNT=<n>                  (dev repo only)
#   DIFF=<modified|added|removed>:<relative path>   one line per differing file
#   REASON=<text>                   (not-dev-repo / unknown only)
#
# Exit codes: 0 in-sync or not-dev-repo · 10 diverged · 3 unknown (check could not run)
# · 2 usage error. Read-only: never writes anything.

set -uo pipefail

# The runtime surface — the single definition of what a session executes from the plugin
# root. Component names that do not exist yet are listed on purpose: absent on both sides
# is not a difference, and a future component is covered the day it appears.
RUNTIME_PATHS=(
  .claude-plugin
  commands
  skills
  agents
  hooks
  templates
  scripts
  workflows
  monitors
  output-styles
  bin
  .mcp.json
  .lsp.json
  settings.json
  craft-profile-defaults.md
  model-defaults.md
)

PLUGIN_ROOT=""
PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root|--project)
      # A flag with no (or an empty) value is a usage error — without this guard a trailing
      # flag makes `shift 2` fail silently and the loop re-reads the same flag forever.
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:$1" >&2; exit 2; }
      if [[ "$1" == "--plugin-root" ]]; then PLUGIN_ROOT="$2"; else PROJECT="$2"; fi
      shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done

unknown() {
  echo "STATUS=unknown"
  echo "REASON=$1"
  exit 3
}

not_dev_repo() {
  echo "STATUS=not-dev-repo"
  echo "REASON=$1"
  exit 0
}

[[ -n "$PLUGIN_ROOT" ]] || { echo "ERROR=missing_argument:--plugin-root" >&2; exit 2; }
if [[ -z "$PROJECT" ]]; then
  PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
fi

# Decided before any tool check, so a project that is not a plugin source stays silent even on a
# machine without python3.
[[ -f "$PROJECT/.claude-plugin/plugin.json" ]] || not_dev_repo "project has no .claude-plugin/plugin.json"

command -v python3 >/dev/null 2>&1 || unknown "python3 not found"
command -v git >/dev/null 2>&1 || unknown "git not found"

# Manifest name, or empty when the file is missing or unparseable.
manifest_name() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    name = json.load(open(sys.argv[1], encoding="utf-8")).get("name", "")
    print(name if isinstance(name, str) else "")
except Exception:
    print("")
PY
}

[[ -d "$PLUGIN_ROOT" ]] || unknown "plugin root not found: $PLUGIN_ROOT"
[[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]] || unknown "plugin manifest not found under $PLUGIN_ROOT"

project_name="$(manifest_name "$PROJECT/.claude-plugin/plugin.json")"
plugin_name="$(manifest_name "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
[[ -n "$plugin_name" ]] || unknown "plugin manifest unreadable or has no name"
[[ -n "$project_name" && "$project_name" == "$plugin_name" ]] \
  || not_dev_repo "project manifest name '${project_name}' is not the running plugin '${plugin_name}'"

real_project="$(cd "$PROJECT" && pwd -P)"
real_plugin="$(cd "$PLUGIN_ROOT" && pwd -P)"
if [[ "$real_project" == "$real_plugin" ]]; then
  echo "STATUS=in-sync"
  echo "RUNTIME=working-tree"
  echo "DIFF_COUNT=0"
  exit 0
fi

git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || unknown "project is not a git work tree"

tmp="$(mktemp -d)" || unknown "mktemp failed"
trap 'rm -rf "$tmp"' EXIT

# Both sides list the same kinds of entries — regular files and symlinks, should the cache
# preserve any (this repo tracks none today) — and both drop macOS `.DS_Store` clutter, so
# neither side can report a difference the other side never lists. Every listing or read
# failure ends in STATUS=unknown: an incomplete listing must never pass for a real diff.

# NUL-separated names on stdin → one name per line on stdout, `.DS_Store` dropped. A name that
# contains a newline cannot be compared line by line, so it aborts the check (exit 2).
nul_to_lines() {
  local f
  while IFS= read -r -d '' f; do
    [[ "$f" == *$'\n'* ]] && return 2
    [[ "${f##*/}" == ".DS_Store" ]] && continue
    printf '%s\n' "$f"
  done
}

# Repo side: tracked + untracked-not-ignored, restricted to entries that exist on disk
# (a tracked file deleted in the working tree is gone from what a --plugin-dir run would load).
git -C "$PROJECT" ls-files -co --exclude-standard -z -- "${RUNTIME_PATHS[@]}" > "$tmp/repo.raw" 2>/dev/null \
  || unknown "git ls-files failed in $PROJECT"
nul_to_lines < "$tmp/repo.raw" > "$tmp/repo.all" \
  || unknown "unsupported file name (contains a newline) under $PROJECT"
while IFS= read -r f; do
  [[ -f "$PROJECT/$f" || -L "$PROJECT/$f" ]] && printf '%s\n' "$f"
done < "$tmp/repo.all" | LC_ALL=C sort -u > "$tmp/repo"

# Cache side: every file or symlink under the runtime surface; any failing `find` (e.g. an
# unreadable directory) fails the listing instead of silently shortening it.
list_cache() {
  cd "$PLUGIN_ROOT" || return 1
  local p rc=0
  for p in "${RUNTIME_PATHS[@]}"; do
    if [[ -d "$p" && ! -L "$p" ]]; then
      find "$p" \( -type f -o -type l \) -print0 || rc=1
    elif [[ -f "$p" || -L "$p" ]]; then
      printf '%s\0' "$p"
    fi
  done
  return "$rc"
}
( list_cache ) > "$tmp/cache.raw" 2>/dev/null || unknown "cannot list plugin root $PLUGIN_ROOT"
nul_to_lines < "$tmp/cache.raw" > "$tmp/cache.all" \
  || unknown "unsupported file name (contains a newline) under $PLUGIN_ROOT"
LC_ALL=C sort -u "$tmp/cache.all" > "$tmp/cache"

LC_ALL=C comm -23 "$tmp/repo" "$tmp/cache" | sed 's/^/added:/'   >  "$tmp/diff"
LC_ALL=C comm -13 "$tmp/repo" "$tmp/cache" | sed 's/^/removed:/' >> "$tmp/diff"
# cmp exits 1 on a difference and 2 when a file cannot be read — only 1 is a real modification.
LC_ALL=C comm -12 "$tmp/repo" "$tmp/cache" | while IFS= read -r f; do
  cmp -s "$PROJECT/$f" "$PLUGIN_ROOT/$f"
  case $? in
    0) ;;
    1) printf 'modified:%s\n' "$f" ;;
    *) printf 'unreadable:%s\n' "$f" ;;
  esac
done >> "$tmp/diff"
unreadable="$(grep -m1 '^unreadable:' "$tmp/diff")"
[[ -z "$unreadable" ]] || unknown "cannot read ${unreadable#unreadable:}"

count="$(grep -c . "$tmp/diff")"
if [[ "$count" -eq 0 ]]; then
  echo "STATUS=in-sync"
  echo "RUNTIME=cache"
  echo "DIFF_COUNT=0"
  exit 0
fi

echo "STATUS=diverged"
echo "RUNTIME=cache"
echo "DIFF_COUNT=$count"
LC_ALL=C sort -t: -k2 "$tmp/diff" | sed 's/^/DIFF=/'
exit 10
