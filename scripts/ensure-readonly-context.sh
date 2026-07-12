#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# ensure-readonly-context.sh — keep declared connected projects readable (F1)
#
# WHY ------------------------------------------------------------------------
# A project may declare external "connected projects" as read-only context
# sources (see the `## Read-Only Context Sources` block in
# `.claude/project/rules.md`). The PreToolUse guard (readonly-context-guard.sh)
# blocks *writes* to them, but a path *outside* the project root is not even
# *readable* until it is trusted. Claude Code trusts the project root plus
# `permissions.additionalDirectories`, so each declared connected project must be
# recorded there — once — for the agent to read it without a per-path prompt.
#
# The in-repo `research/` folder needs nothing here: it lives inside the project
# root, so it is already readable. This helper only handles the *external*
# declared paths.
#
# WHAT -----------------------------------------------------------------------
# Parses the declared connected-project paths from rules.md, then either reports
# (`--check`) or idempotently records (`--apply`) them in additionalDirectories.
#
#   --check    (default)  Resolve + report each declared path. Never writes.
#                         Exit 0 = all present (or none declared), exit 10 =
#                         one or more absent (caller should --apply).
#   --apply               Idempotently merge every declared path into
#                         additionalDirectories, preserving existing entries;
#                         create settings.local.json if missing; ensure it is
#                         gitignored; verify the result is valid JSON.
#
# Output is line-oriented key=value so the calling command can parse it:
#   DECLARED=<n>              number of connected projects declared in rules.md
#   ROOT=<abs> STATUS=...     one line per declared path (present|absent)
#   SETTINGS=exists|missing   whether settings.local.json existed beforehand
#   GITIGNORED=yes|no         whether the settings file is covered by .gitignore
#   STATUS=present|absent     aggregate: absent if any single path is absent
#   CHANGED=yes|no            (apply only) whether a write happened
#   ERROR=<reason>            on failure (stderr), with a non-zero exit code
#
# Never deletes or rewrites unrelated settings. All writes are atomic (temp file
# + rename). On any structural problem it exits non-zero and writes nothing.

set -uo pipefail

MODE="check"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR=python3_not_found" >&2
  echo "Add declared connected projects to permissions.additionalDirectories manually." >&2
  exit 3
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${PROJECT_DIR}" 2>/dev/null || { echo "ERROR=project_dir_unreachable:${PROJECT_DIR}" >&2; exit 4; }
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

export CRAFT_REPO_ROOT="${REPO_ROOT}"
export CRAFT_MODE="${MODE}"

python3 - <<'PY'
import json, os, sys

repo_root = os.environ["CRAFT_REPO_ROOT"]
mode      = os.environ["CRAFT_MODE"]

rules_path     = os.path.join(repo_root, ".claude", "project", "rules.md")
settings_path  = os.path.join(repo_root, ".claude", "settings.local.json")
gitignore_path = os.path.join(repo_root, ".gitignore")
ignore_line    = ".claude/settings.local.json"

# --- parse declared connected-project paths from rules.md --------------------
# Bullets under the `## Read-Only Context Sources` heading, up to the next `## `.
# Mirror the guard's parser: strip the bullet marker, backticks, and any trailing
# "— note" / "# note" / "<placeholder>". The in-repo research/ folder is never
# listed here (it is convention-protected and already readable).
#
# Path normalization (os.path.normpath, below) is kept in lockstep with the guard's
# normalize_path() in hooks/readonly-context-guard.sh so a declared "../" path is
# recorded here exactly as the guard blocks it. scripts/test-readonly-context.sh
# asserts the two agree on a shared fixture set.
declared = []
if os.path.exists(rules_path):
    inblock = False
    with open(rules_path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("## Read-Only Context Sources"):
                inblock = True
                continue
            if inblock and line.startswith("## "):
                inblock = False
            if inblock:
                stripped = line.lstrip()
                if stripped.startswith("- "):
                    val = stripped[2:].strip().strip("`").strip()
                    # drop a trailing note / placeholder marker
                    for sep in (" —", " #", " <"):
                        idx = val.find(sep)
                        if idx != -1:
                            val = val[:idx]
                    val = val.strip().strip("`").strip()
                    if val:
                        # Only the "~/" (and bare "~") form is expanded — the guard's
                        # pure-Bash side cannot resolve "~user", so gating both sides
                        # identically keeps a "~user" bullet literal in guard and helper
                        # alike instead of silently diverging.
                        if val == "~" or val.startswith("~/"):
                            val = os.path.expanduser(val)
                        if not os.path.isabs(val):
                            val = os.path.join(repo_root, val)
                        declared.append(os.path.normpath(val))

# de-duplicate, keep order
seen = set()
declared = [p for p in declared if not (p in seen or seen.add(p))]

# --- load current settings (tolerate absence; refuse corruption) ------------
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
missing = [p for p in declared if p not in current_dirs]

ignored = False
if os.path.exists(gitignore_path):
    with open(gitignore_path, encoding="utf-8") as fh:
        ignored = any(line.strip() == ignore_line for line in fh)

def report(changed=None):
    print("DECLARED=%d" % len(declared))
    for p in declared:
        print("ROOT=%s STATUS=%s" % (p, "absent" if p in missing else "present"))
    print("SETTINGS=%s" % ("exists" if existed else "missing"))
    print("GITIGNORED=%s" % ("yes" if ignored else "no"))
    print("STATUS=%s" % ("absent" if missing else "present"))
    if changed is not None:
        print("CHANGED=%s" % ("yes" if changed else "no"))

# --- check mode: report only -------------------------------------------------
if mode == "check":
    report()
    sys.exit(10 if missing else 0)

# --- apply mode: idempotent merge -------------------------------------------
wrote = False
if missing or not existed:
    perms = settings.setdefault("permissions", {})
    if not isinstance(perms, dict):
        sys.stderr.write("ERROR=permissions_not_object\n"); sys.exit(5)
    ad = perms.setdefault("additionalDirectories", [])
    if not isinstance(ad, list):
        sys.stderr.write("ERROR=additionalDirectories_not_array\n"); sys.exit(5)
    for p in missing:
        if p not in ad:
            ad.append(p)
    if missing:
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)
        tmp = settings_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(settings, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, settings_path)
        wrote = True

# keep the personal override file out of version control
if declared and not ignored:
    with open(gitignore_path, "a", encoding="utf-8") as fh:
        fh.write("\n# Claude Code local state (kept out of version control)\n")
        fh.write(ignore_line + "\n")
    ignored = True

# --- post-write verification -------------------------------------------------
if wrote:
    try:
        with open(settings_path, encoding="utf-8") as fh:
            verify = json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        sys.stderr.write("ERROR=post_write_invalid_json:%s\n" % exc); sys.exit(6)
    verify_dirs = verify.get("permissions", {}).get("additionalDirectories", [])
    for p in declared:
        if p not in verify_dirs:
            sys.stderr.write("ERROR=post_write_entry_missing:%s\n" % p); sys.exit(6)
    existed = True

missing = []  # after apply, everything declared is present
report(changed=wrote)
sys.exit(0)
PY
