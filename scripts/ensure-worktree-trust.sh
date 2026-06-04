#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# ensure-worktree-trust.sh — keep the worktree base directory trusted
#
# WHY ------------------------------------------------------------------------
# /craft:execute creates one git worktree per slice *outside* the project root
# (default pattern `../<repo>-worktrees/<slice-id>-<slug>/`). Claude Code only
# trusts the project root plus `permissions.additionalDirectories`, so every
# file operation a slice-builder subagent performs inside an external worktree
# would otherwise raise a per-path permission prompt — stalling the autonomous
# run and tempting users to hand-collect hundreds of path-specific allow rules.
#
# The root fix is a single entry: the *base* directory that holds all worktrees
# goes into `permissions.additionalDirectories` of the project-local
# `.claude/settings.local.json`. Then the whole worktree tree inherits the same
# trust level as the project root — no per-path prompts, ever.
#
# WHAT -----------------------------------------------------------------------
# Derives the absolute worktree base directory from a path pattern + repo root
# (platform-neutral, via python3 path normalisation — no string hacks), then
# either reports (`--check`) or idempotently records (`--apply`) it.
#
#   --check    (default)  Resolve + report. Never writes. Exit 0 = already
#                         trusted, exit 10 = absent (caller should --apply).
#   --apply               Idempotently merge the base dir into
#                         additionalDirectories, preserving every existing
#                         allow/deny/array; create settings.local.json if
#                         missing; ensure it is gitignored; verify the result
#                         is valid JSON containing the entry.
#   --pattern <pat>       Worktree path pattern (default below). May be relative
#                         (`../<repo>-worktrees/<slice-id>-<slug>/`) or absolute.
#
# Output is line-oriented key=value so the calling command can parse it:
#   BASE_DIR=<abs path>      the resolved worktree base directory
#   SETTINGS=exists|missing  whether settings.local.json existed beforehand
#   GITIGNORED=yes|no        whether the settings file is covered by .gitignore
#   STATUS=present|absent    whether BASE_DIR was already trusted
#   CHANGED=yes|no           (apply only) whether a write happened
#   ERROR=<reason>           on failure (stderr), with a non-zero exit code
#
# The script never deletes or rewrites unrelated settings. All writes are atomic
# (temp file + rename). On any structural problem it exits non-zero and writes
# nothing, leaving manual remediation to the caller.

set -uo pipefail

MODE="check"
PATTERN='../<repo>-worktrees/<slice-id>-<slug>/'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   MODE="check"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --pattern) PATTERN="${2:-}"; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR=python3_not_found" >&2
  echo "Add the worktree base directory to permissions.additionalDirectories manually." >&2
  exit 3
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT_DIR}" >&2; exit 4; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

export CRAFT_REPO_ROOT="${REPO_ROOT}"
export CRAFT_PATTERN="${PATTERN}"
export CRAFT_MODE="${MODE}"

python3 - <<'PY'
import json, os, sys

repo_root = os.environ["CRAFT_REPO_ROOT"]
pattern   = os.environ["CRAFT_PATTERN"]
mode      = os.environ["CRAFT_MODE"]

repo_name = os.path.basename(os.path.normpath(repo_root))

# Substitute the <repo> token, then strip the per-worktree leaf segment — the
# only part that varies per slice (<slice-id>/<slug>). What remains is the base
# directory every worktree shares. Resolve it against the repo root so relative
# patterns ("../x") become absolute, normalised, and existence-independent.
substituted = pattern.replace("<repo>", repo_name).rstrip("/")
leafless    = os.path.dirname(substituted)
base_abs    = os.path.normpath(os.path.join(repo_root, leafless))

settings_path  = os.path.join(repo_root, ".claude", "settings.local.json")
gitignore_path = os.path.join(repo_root, ".gitignore")
ignore_line    = ".claude/settings.local.json"

# --- load current settings (tolerate absence; refuse corruption) -------------
existed = os.path.exists(settings_path)
try:
    if existed:
        with open(settings_path, encoding="utf-8") as fh:
            settings = json.load(fh)
        if not isinstance(settings, dict):
            raise ValueError("top-level JSON is not an object")
    else:
        settings = {}
except (json.JSONDecodeError, OSError, ValueError) as exc:
    sys.stderr.write("ERROR=settings_unparseable:%s\n" % exc)
    sys.exit(5)

current_dirs = settings.get("permissions", {}).get("additionalDirectories", [])
present = base_abs in current_dirs

# --- gitignore coverage (exact-line match; good enough + idempotent) ---------
ignored = False
if os.path.exists(gitignore_path):
    with open(gitignore_path, encoding="utf-8") as fh:
        ignored = any(line.strip() == ignore_line for line in fh)

def emit(status, changed=None):
    print("BASE_DIR=%s" % base_abs)
    print("SETTINGS=%s" % ("exists" if existed else "missing"))
    print("GITIGNORED=%s" % ("yes" if ignored else "no"))
    print("STATUS=%s" % status)
    if changed is not None:
        print("CHANGED=%s" % ("yes" if changed else "no"))

# --- check mode: report only -------------------------------------------------
if mode == "check":
    emit("present" if present else "absent")
    sys.exit(0 if present else 10)

# --- apply mode: idempotent merge --------------------------------------------
wrote_settings = False
if not present or not existed:
    perms = settings.setdefault("permissions", {})
    if not isinstance(perms, dict):
        sys.stderr.write("ERROR=permissions_not_object\n")
        sys.exit(5)
    ad = perms.setdefault("additionalDirectories", [])
    if not isinstance(ad, list):
        sys.stderr.write("ERROR=additionalDirectories_not_array\n")
        sys.exit(5)
    if base_abs not in ad:
        ad.append(base_abs)
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    tmp = settings_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, settings_path)
    wrote_settings = True

# ensure the personal override file stays out of version control
if not ignored:
    with open(gitignore_path, "a", encoding="utf-8") as fh:
        fh.write("\n# Claude Code local state (kept out of version control)\n")
        fh.write(ignore_line + "\n")
    ignored = True

# --- post-write verification: valid JSON that contains the entry -------------
try:
    with open(settings_path, encoding="utf-8") as fh:
        verify = json.load(fh)
except (json.JSONDecodeError, OSError) as exc:
    sys.stderr.write("ERROR=post_write_invalid_json:%s\n" % exc)
    sys.exit(6)

if base_abs not in verify.get("permissions", {}).get("additionalDirectories", []):
    sys.stderr.write("ERROR=post_write_entry_missing\n")
    sys.exit(6)

# 'existed' reflects the pre-run state — refresh it so the report is truthful
existed = True
emit("present", changed=wrote_settings)
sys.exit(0)
PY
