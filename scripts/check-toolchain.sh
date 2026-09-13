#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# check-toolchain.sh — is the shell toolchain CRAFT needs present? (F4)
#
# WHY ------------------------------------------------------------------------
# CRAFT's scripts may use a current bash (>= BASH_MIN) and need python3. macOS still ships a
# frozen /bin/bash 3.2, and some Linux distributions package bash < 5.0, so a missing or old
# tool used to surface as a cryptic parse error deep inside a harness. `/craft:prime` runs this
# helper in its pre-flight and turns the result into an install command that fits the OS.
#
# The PATH is the trap. A desktop-app or IDE launch can hand Claude Code a minimal PATH, and a
# headless probe (2026-09-13) showed the Bash tool inheriting it just like the hooks — so a user can
# have bash 5 installed while this session only reaches /bin/bash 3.2. The helper therefore looks
# for a current bash off PATH and then names the PATH fix instead of an install command. Hooks and
# the Bash tool can still differ (e.g. a shell profile that puts Homebrew first): the SessionStart
# hook records the bash it ran with in .claude/plans/.hook-env, and this helper compares that record.
#
# THIS FILE MUST STAY BASH-3.2-COMPATIBLE: it has to run on the old bash it is meant to report
# (no associative arrays, no ${var,,}, no mapfile, no `;&`).
#
# WHAT -----------------------------------------------------------------------
#   --project <dir>   project root holding .claude/plans/.hook-env
#                     (default: CLAUDE_PROJECT_DIR, else git toplevel, else pwd)
#
# Output is line-oriented key=value:
#   BASH=ok|too-old  BASH_VERSION=<x.y.z>  BASH_PATH=<path>  BASH_MIN=<x.y>
#   PYTHON3=ok|missing  PYTHON3_VERSION=<x.y.z>
#   OS=darwin|linux|windows|unknown  OS_ID=<id from os-release, linux only>
#   HOOK_BASH=ok|too-old|unknown  HOOK_BASH_VERSION=<x.y.z>  HOOK_BASH_PATH=<path>
#   INSTALL_BASH=<command>  INSTALL_PYTHON3=<command>   only for a failing tool
#   BASH_OFF_PATH=<path>  BASH_OFF_PATH_VERSION=<x.y.z>  PATH_REMEDY=<text>
#                                                        bash too old on PATH, but a current one is
#                                                        installed elsewhere — replaces INSTALL_BASH
#   INSTALL_NOTE=<text>                                  bash-specific note (only when bash is too old)
#                                                        and/or a platform caveat
#   HOOK_REMEDY=<text>                                   only when HOOK_BASH=too-old
#   STATUS=ok|hook-mismatch|missing-tools
#
# Exit codes: 0 ok · 10 hook-mismatch only (warn, do not abort) · 20 missing-tools (abort)
# · 2 usage error. Read-only: never writes anything.
#
# Test-only overrides (used by scripts/test-toolchain-check.sh, never set in normal use):
#   CRAFT_TEST_UNAME, CRAFT_TEST_OS_RELEASE (path to an os-release file),
#   CRAFT_TEST_BASH_VERSION, CRAFT_TEST_PYTHON3_VERSION (a version, or "missing"),
#   CRAFT_TEST_BASH_CANDIDATES (space-separated off-PATH bash locations to probe; empty = none)

set -uo pipefail

# The single definition of the required bash, as major.minor.
BASH_MIN_MAJOR=5
BASH_MIN_MINOR=0

PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR=missing_value:$1" >&2; exit 2; }
      PROJECT="$2"; shift 2 ;;
    *) echo "ERROR=unknown_argument:$1" >&2; exit 2 ;;
  esac
done
if [[ -z "$PROJECT" ]]; then
  PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
fi

# at_least <version> — true when <version> (e.g. "5.3.15(1)-release") is >= BASH_MIN.
at_least() {
  local v="${1%%[(-]*}" major minor rest
  major="${v%%.*}"
  rest="${v#*.}"
  [[ "$rest" == "$v" ]] && rest="0"
  minor="${rest%%.*}"
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  # 10# forces base 10: a leading zero ("08") must not be read as an invalid octal number.
  if (( 10#$major != BASH_MIN_MAJOR )); then
    (( 10#$major > BASH_MIN_MAJOR ))
  else
    (( 10#$minor >= BASH_MIN_MINOR ))
  fi
}

# os_release_value <key> — the unquoted value of <key> from the os-release file, or empty.
os_release_value() {
  local file="${CRAFT_TEST_OS_RELEASE:-/etc/os-release}" line value
  [[ -r "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      "$1="*)
        value="${line#*=}"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        printf '%s' "$value"
        return 0 ;;
    esac
  done < "$file"
}

# --- bash (the one running this script = the bash the Bash tool resolves) ----------------------
bash_version="${CRAFT_TEST_BASH_VERSION:-${BASH_VERSION:-unknown}}"
bash_version="${bash_version%%[(-]*}"
bash_status="ok"
at_least "$bash_version" || bash_status="too-old"

# --- python3 -----------------------------------------------------------------------------------
python_version="${CRAFT_TEST_PYTHON3_VERSION:-}"
if [[ -z "$python_version" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    # Only a clean exit with a real version counts: shims and stubs (e.g. an unconfigured version
    # manager) may print a message on stdout and exit non-zero.
    if python_version="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"; then
      case "$python_version" in
        [0-9]*.[0-9]*) ;;
        *) python_version="missing" ;;
      esac
    else
      python_version="missing"
    fi
  else
    python_version="missing"
  fi
fi
python_status="ok"
[[ "$python_version" == "missing" ]] && python_status="missing"

# --- OS and install hints ----------------------------------------------------------------------
uname_s="${CRAFT_TEST_UNAME:-$(uname -s 2>/dev/null)}"
os="unknown"; os_id=""; install_bash=""; install_python=""
bash_note=""       # only relevant when bash itself is too old
platform_note=""   # relevant for any missing tool on this platform
case "$uname_s" in
  Darwin)
    os="darwin"
    install_bash="brew install bash"
    install_python="brew install python"
    bash_note="Homebrew: https://brew.sh — then start a new terminal so the new bash comes first on PATH" ;;
  Linux)
    os="linux"
    os_id="$(os_release_value ID)"
    os_like="$(os_release_value ID_LIKE)"
    version_id="$(os_release_value VERSION_ID)"
    family=""
    for token in $os_id $os_like; do
      case "$token" in
        debian|ubuntu)                              family="apt" ;;
        fedora|rhel|centos|rocky|almalinux|ol|amzn) family="dnf" ;;
        arch|manjaro)                               family="pacman" ;;
        alpine)                                     family="apk" ;;
        opensuse*|suse|sles)                        family="zypper" ;;
      esac
      [[ -n "$family" ]] && break
    done
    # Releases that predate dnf (yum only): Amazon Linux 2, and RHEL / CentOS / Oracle Linux 7.
    if [[ "$family" == "dnf" ]]; then
      case "$os_id:${version_id%%.*}" in
        amzn:2|rhel:7|centos:7|ol:7) family="yum" ;;
      esac
    fi
    case "$family" in
      yum)    install_bash="sudo yum install bash";     install_python="sudo yum install python3" ;;
      apt)    install_bash="sudo apt install bash";     install_python="sudo apt install python3" ;;
      dnf)    install_bash="sudo dnf install bash";     install_python="sudo dnf install python3" ;;
      pacman) install_bash="sudo pacman -S bash";       install_python="sudo pacman -S python" ;;
      apk)    install_bash="sudo apk add bash";         install_python="sudo apk add python3" ;;
      zypper) install_bash="sudo zypper install bash";  install_python="sudo zypper install python3" ;;
      *)      install_bash="install bash >= ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR} with your package manager"
              install_python="install python3 with your package manager" ;;
    esac
    # Releases whose own bash package is older than the minimum. Listed by repology (2026-09-13):
    # centos 7 (4.2), centos 8 / almalinux 8 / rocky 8 (4.4), ubuntu 18.04 (4.4), opensuse-leap 15
    # (4.4), amzn 2 (4.2). Inferred from their package base, not listed by repology: rhel 7/8 and
    # ol 7/8 (same packages as centos 7/8), sles 15 (same base as Leap 15).
    case "$os_id:${version_id%%.*}" in
      rhel:7|centos:7|ol:7|rhel:8|centos:8|rocky:8|almalinux:8|ol:8|opensuse-leap:15|sles:15|amzn:2|ubuntu:18)
        bash_note="${os_id} ${version_id} packages bash < ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}; use a newer release or build bash from source (https://www.gnu.org/software/bash/)" ;;
      *)
        bash_note="if your package manager reports bash as already current, this release packages bash < ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}; use a newer release or build bash from source (https://www.gnu.org/software/bash/)" ;;
    esac ;;
  MINGW*|MSYS*|CYGWIN*)
    os="windows"
    install_bash="use WSL 2 (recommended), or update Git for Windows to a release whose Git Bash has bash >= ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}"
    install_python="use WSL 2 (recommended), or install python3 on Git Bash's PATH"
    platform_note="Windows support is untested (roadmap F5); WSL 2 is the recommended setup" ;;
  *)
    install_bash="install bash >= ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}"
    install_python="install python3" ;;
esac

# --- hook bash (recorded by hooks/session-start.sh) --------------------------------------------
hook_status="unknown"; hook_version=""; hook_path=""
hook_env="$PROJECT/.claude/plans/.hook-env"
if [[ -r "$hook_env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      HOOK_BASH_VERSION=*) hook_version="${line#HOOK_BASH_VERSION=}" ;;
      HOOK_BASH_PATH=*)    hook_path="${line#HOOK_BASH_PATH=}" ;;
    esac
  done < "$hook_env"
  hook_version="${hook_version%%[(-]*}"
  if [[ -n "$hook_version" ]]; then
    if at_least "$hook_version"; then hook_status="ok"; else hook_status="too-old"; fi
  fi
fi

# --- a current bash installed off PATH? --------------------------------------------------------
# Launched from a desktop app or IDE, Claude Code can hand BOTH the Bash tool and the hooks a minimal
# PATH (observed in a headless probe, 2026-09-13). The user then already has a current bash — just not
# on this session's PATH — and "install bash" is the wrong advice; the PATH remedy is the right one.
off_path=""; off_path_version=""
if [[ "$bash_status" == "too-old" ]]; then
  for candidate in ${CRAFT_TEST_BASH_CANDIDATES-/opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash}; do
    [[ -x "$candidate" && "$candidate" != "${BASH:-}" ]] || continue
    # Ask the candidate for $BASH_VERSION instead of parsing `--version`: bash translates that line
    # ("GNU bash, Version 5.3.15" on a German system without LANG), which silently hid the fix.
    # LC_ALL=C and </dev/null keep a stray non-bash candidate from localizing or waiting on stdin.
    candidate_version="$(LC_ALL=C "$candidate" -c 'printf "%s" "$BASH_VERSION"' </dev/null 2>/dev/null)" || continue
    candidate_version="${candidate_version%%[(-]*}"
    case "$candidate_version" in [0-9]*.[0-9]*) ;; *) continue ;; esac
    if at_least "$candidate_version"; then
      off_path="$candidate"; off_path_version="$candidate_version"
      break
    fi
  done
fi

# --- report ------------------------------------------------------------------------------------
echo "BASH=$bash_status"
echo "BASH_VERSION=$bash_version"
echo "BASH_PATH=${BASH:-$(command -v bash 2>/dev/null)}"
echo "BASH_MIN=${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}"
echo "PYTHON3=$python_status"
echo "PYTHON3_VERSION=$python_version"
echo "OS=$os"
[[ -n "$os_id" ]] && echo "OS_ID=$os_id"
echo "HOOK_BASH=$hook_status"
[[ -n "$hook_version" ]] && echo "HOOK_BASH_VERSION=$hook_version"
[[ -n "$hook_path" ]] && echo "HOOK_BASH_PATH=$hook_path"

if [[ "$bash_status" != "ok" || "$python_status" != "ok" ]]; then
  if [[ -n "$off_path" ]]; then
    echo "BASH_OFF_PATH=$off_path"
    echo "BASH_OFF_PATH_VERSION=$off_path_version"
    off_dir="${off_path%/*}"
    path_bash="$(command -v bash 2>/dev/null)"
    if [[ "$path_bash" == "$off_path" ]]; then
      # PATH already resolves `bash` to the current one; this run was started with an explicit old bash.
      where=" and PATH already resolves bash to it — this run was started with ${BASH:-an older bash} explicitly; fix: run it with plain \`bash\`"
    else
      case ":${PATH:-}:" in
        *":${off_dir}:"*) where=", but an older bash (${path_bash:-bash} ${bash_version}) comes first on PATH; fix: put ${off_dir} first on PATH — for Claude Code, start it from a terminal" ;;
        *)                where=" but is not on this session's PATH; fix: start Claude Code from a terminal" ;;
      esac
    fi
    if [[ "$path_bash" == "$off_path" ]]; then
      echo "PATH_REMEDY=bash ${off_path_version} is installed at ${off_path}${where}"
    else
      echo "PATH_REMEDY=bash ${off_path_version} is installed at ${off_path}${where}, or add \"env\": {\"PATH\": \"<the literal output of echo \$PATH in a terminal, never \$PATH>\"} to ~/.claude/settings.json with ${off_dir} first, then restart (verified for hooks; the Bash tool is expected to inherit it too)"
    fi
  elif [[ "$bash_status" != "ok" ]]; then
    echo "INSTALL_BASH=$install_bash"
  fi
  [[ "$python_status" != "ok" ]] && echo "INSTALL_PYTHON3=$install_python"
  note=""
  [[ "$bash_status" != "ok" && -z "$off_path" && -n "$bash_note" ]] && note="$bash_note"
  [[ -n "$platform_note" ]] && note="${note:+$note · }$platform_note"
  [[ -n "$note" ]] && echo "INSTALL_NOTE=$note"
  echo "STATUS=missing-tools"
  exit 20
fi

if [[ "$hook_status" == "too-old" ]]; then
  # Verified (Claude Code 2.1.270): hook commands inherit an `env.PATH` set in settings.json; the
  # value is used as given — paste a literal PATH (whether "$PATH" would expand is unverified).
  bash_dir="the directory of a bash >= ${BASH_MIN_MAJOR}.${BASH_MIN_MINOR}"
  [[ -n "${BASH:-}" && "$BASH" == */* ]] && bash_dir="${BASH%/*}"
  # The record is written by the SessionStart hook per project folder: it is as old as this
  # session's start, and the last session started in this folder wins.
  echo "HOOK_REMEDY=hooks started this session with ${hook_path:-bash} ${hook_version} (this shell: bash ${bash_version}). CRAFT's own hooks are 3.2-compatible and unaffected; only scripts a hook runs would get the old bash. To align: start Claude Code from a terminal, or add \"env\": {\"PATH\": \"<the literal output of echo \$PATH in a terminal, never \$PATH>\"} to ~/.claude/settings.json with ${bash_dir} first, then restart — the record is rewritten at every session start"
  echo "STATUS=hook-mismatch"
  exit 10
fi

echo "STATUS=ok"
exit 0
