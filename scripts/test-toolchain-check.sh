#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-toolchain-check.sh — self-contained tests for check-toolchain.sh and the SessionStart
# hook's bash record (F4).
#
# The helper reads the OS, /etc/os-release, and the bash/python3 versions from the machine it
# runs on; its test-only overrides (CRAFT_TEST_UNAME, CRAFT_TEST_OS_RELEASE,
# CRAFT_TEST_BASH_VERSION, CRAFT_TEST_PYTHON3_VERSION, CRAFT_TEST_BASH_CANDIDATES) let this harness drive every platform
# branch from one machine. The hook cases run hooks/session-start.sh for real — under
# /bin/bash when it exists, which on macOS is the frozen 3.2 the hooks must keep supporting.
# Run it directly:
#
#   bash scripts/test-toolchain-check.sh
#
# It writes nothing outside its own mktemp fixture (removed on exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/check-toolchain.sh"
HOOK="$REPO_ROOT/hooks/session-start.sh"
[[ -f "$HELPER" ]] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }
[[ -f "$HOOK" ]]   || { echo "FATAL: hook not found at $HOOK" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

# Constructs newer than bash 3.2 that `bash -n` does not reject (shared by the file scan and its self-test).
BASH4_PATTERN='\$\{[A-Za-z0-9_]+(\[[^]]*\])?(,,?|\^\^?)\}|\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAaKk]\}|(^|[[:space:];])(declare|local|typeset)[[:space:]]+-[A-Za-z]*[Ang]|(^|[[:space:];])(mapfile|readarray|coproc)([[:space:]]|$)|;;?&|\|&|&>>|\[\[[[:space:]]+-v[[:space:]]|EPOCHSECONDS|EPOCHREALTIME|BASH_ARGV0|BASHPID|wait[[:space:]]+-n|globstar|lastpipe|\$\{[A-Za-z_][A-Za-z0-9_]*:[^}:]*:-[0-9]|exec[[:space:]]+\{[A-Za-z_]+\}[<>]|read[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-[A-Za-z]*N|%\([^)]*\)T|\{[0-9]+\.\.[0-9]+\.\.[0-9]+\}'

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/empty-project"

osrel() {  # osrel <name> <content> → path of an os-release fixture
  printf '%s\n' "$2" > "$FIX/os-release.$1"
  printf '%s' "$FIX/os-release.$1"
}

# run [VAR=value …] → OUT, RC. Defaults: a current bash, python3 present, no hook record.
HELPER_BASH="${HELPER_BASH:-bash}"   # the bash that runs the helper; the 3.2 matrix below sets /bin/bash
run() {
  OUT="$(env CRAFT_TEST_BASH_VERSION=5.3.15 CRAFT_TEST_PYTHON3_VERSION=3.12.1 CRAFT_TEST_BASH_CANDIDATES= "$@" \
    "$HELPER_BASH" "$HELPER" --project "$FIX/empty-project" 2>&1)"
  RC=$?
}
has() { printf '%s\n' "$OUT" | grep -qxF "$1"; }
lacks_prefix() { ! printf '%s\n' "$OUT" | grep -q "^$1"; }

echo "BASH VERSION:"
run CRAFT_TEST_UNAME=Darwin
{ [[ $RC -eq 0 ]] && has "STATUS=ok" && has "BASH=ok" && lacks_prefix "INSTALL_"; } \
  && ok "current bash + python3 → ok, exit 0, no install hint" || bad "all good (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.0.0
{ [[ $RC -eq 0 ]] && has "BASH=ok"; } && ok "exactly 5.0 → ok (boundary)" || bad "5.0 boundary (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION='5.3.15(1)-release'
{ [[ $RC -eq 0 ]] && has "BASH_VERSION=5.3.15"; } && ok "raw BASH_VERSION form 5.3.15(1)-release parses" || bad "raw version form (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=4.4.20
{ [[ $RC -eq 20 ]] && has "BASH=too-old" && has "STATUS=missing-tools"; } \
  && ok "4.4 → too-old, exit 20" || bad "4.4 (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=3.2.57
{ [[ $RC -eq 20 ]] && has "BASH=too-old" && has "INSTALL_BASH=brew install bash"; } \
  && ok "macOS 3.2 → too-old with brew install bash" || bad "macOS 3.2 (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=10.1.0
{ [[ $RC -eq 0 ]] && has "BASH=ok"; } && ok "a future major (10.1) → ok, compared numerically" || bad "future major (rc=$RC, out=$OUT)"

echo "PYTHON3:"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_PYTHON3_VERSION=missing
{ [[ $RC -eq 20 ]] && has "PYTHON3=missing" && has "BASH=ok" && has "INSTALL_PYTHON3=brew install python" && lacks_prefix "INSTALL_BASH="; } \
  && ok "python3 missing → exit 20, python hint only" || bad "python3 missing (rc=$RC, out=$OUT)"

echo "LINUX DISTRIBUTIONS:"
f="$(osrel ubuntu 'ID=ubuntu
ID_LIKE=debian
VERSION_ID="24.04"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.20
{ [[ $RC -eq 20 ]] && has "OS_ID=ubuntu" && has "INSTALL_BASH=sudo apt install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=if your package manager reports bash as already current'; } \
  && ok "Ubuntu 24.04 → apt + generic Linux note (no release-specific one)" || bad "ubuntu (rc=$RC, out=$OUT)"

f="$(osrel rocky8 'NAME="Rocky Linux"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.10"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.20
{ [[ $RC -eq 20 ]] && has "INSTALL_BASH=sudo dnf install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=rocky 8.10 packages bash < 5.0'; } \
  && ok "Rocky 8 (quoted values, ID_LIKE) → dnf + old-release note" || bad "rocky 8 (rc=$RC, out=$OUT)"

f="$(osrel fedora 'ID=fedora
VERSION_ID=42')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.20
{ has "INSTALL_BASH=sudo dnf install bash" && ! printf '%s\n' "$OUT" | grep -q 'fedora 42 packages bash'; } \
  && ok "Fedora → dnf, no release-specific note" || bad "fedora (rc=$RC, out=$OUT)"

f="$(osrel amzn2 'ID="amzn"
ID_LIKE="centos rhel fedora"
VERSION_ID="2"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.2.46
{ has "INSTALL_BASH=sudo yum install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=amzn 2 packages bash'; } \
  && ok "Amazon Linux 2 → yum (no dnf there) + note" || bad "amazon linux 2 (rc=$RC, out=$OUT)"

f="$(osrel amzn2023 'ID="amzn"
ID_LIKE="fedora"
VERSION_ID="2023"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.2.46
{ has "INSTALL_BASH=sudo dnf install bash" && ! printf '%s\n' "$OUT" | grep -q 'amzn 2023 packages bash'; } \
  && ok "Amazon Linux 2023 → dnf, no release-specific note" || bad "amazon linux 2023 (rc=$RC, out=$OUT)"

f="$(osrel arch 'ID=arch')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_PYTHON3_VERSION=missing
{ has "INSTALL_PYTHON3=sudo pacman -S python"; } && ok "Arch → pacman (python package named python)" || bad "arch (rc=$RC, out=$OUT)"

f="$(osrel alpine 'ID=alpine
VERSION_ID=3.22.1')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.0
{ has "INSTALL_BASH=sudo apk add bash"; } && ok "Alpine → apk" || bad "alpine (rc=$RC, out=$OUT)"

f="$(osrel leap 'ID="opensuse-leap"
ID_LIKE="suse opensuse"
VERSION_ID="15.6"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.0
{ has "INSTALL_BASH=sudo zypper install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=opensuse-leap 15.6'; } \
  && ok "openSUSE Leap 15.6 → zypper + note" || bad "leap (rc=$RC, out=$OUT)"

f="$(osrel gentoo 'ID=gentoo')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.0
{ [[ $RC -eq 20 ]] && has "INSTALL_BASH=install bash >= 5.0 with your package manager"; } \
  && ok "unknown distribution → generic hint" || bad "unknown distro (rc=$RC, out=$OUT)"

run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$FIX/does-not-exist" CRAFT_TEST_BASH_VERSION=4.4.0
{ [[ $RC -eq 20 ]] && has "OS=linux" && has "INSTALL_BASH=install bash >= 5.0 with your package manager"; } \
  && ok "missing os-release → generic hint, no crash" || bad "missing os-release (rc=$RC, out=$OUT)"

echo "CURRENT BASH INSTALLED OFF PATH:"
mkdir -p "$FIX/cand-new" "$FIX/cand-old"
# The shims answer `-c` like bash does, but their `--version` is German on purpose — bash translates
# that line, and the helper must not depend on it.
printf '#!/bin/sh\n[ "$1" = "-c" ] && { printf "5.2.37(1)-release"; exit 0; }\necho "GNU bash, Version 5.2.37(1)-release (aarch64-apple-darwin24)"\n' > "$FIX/cand-new/bash"
printf '#!/bin/sh\n[ "$1" = "-c" ] && { printf "4.4.23(1)-release"; exit 0; }\necho "GNU bash, Version 4.4.23(1)-release (x86_64-pc-linux-gnu)"\n' > "$FIX/cand-old/bash"
chmod +x "$FIX/cand-new/bash" "$FIX/cand-old/bash"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=3.2.57 CRAFT_TEST_BASH_CANDIDATES="$FIX/cand-old/bash $FIX/cand-new/bash"
{ [[ $RC -eq 20 ]] && has "BASH=too-old" && has "BASH_OFF_PATH=$FIX/cand-new/bash" && has "BASH_OFF_PATH_VERSION=5.2.37" \
  && lacks_prefix "INSTALL_BASH=" && lacks_prefix "INSTALL_NOTE=" \
  && printf '%s\n' "$OUT" | grep -q "^PATH_REMEDY=bash 5.2.37 is installed at $FIX/cand-new/bash but is not on this session's PATH; fix: start Claude Code from a terminal" \
  && printf '%s\n' "$OUT" | grep -q 'never \$PATH' \
  && printf '%s\n' "$OUT" | grep -q "with $FIX/cand-new first, then restart"; } \
  && ok "too old on PATH, bash 5.2 installed off PATH (old candidate skipped) → PATH remedy, no install command, no brew note" \
  || bad "off-path current bash (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=3.2.57 CRAFT_TEST_BASH_CANDIDATES="$FIX/cand-old/bash $FIX/does-not-exist/bash"
{ [[ $RC -eq 20 ]] && has "INSTALL_BASH=brew install bash" && lacks_prefix "BASH_OFF_PATH=" && lacks_prefix "PATH_REMEDY="; } \
  && ok "only an old or missing bash off PATH → normal install command" || bad "off-path old only (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 CRAFT_TEST_BASH_CANDIDATES="$FIX/cand-new/bash"
{ [[ $RC -eq 0 ]] && lacks_prefix "BASH_OFF_PATH=" && lacks_prefix "PATH_REMEDY="; } \
  && ok "bash on PATH already current → off-PATH locations not reported" || bad "off-path when ok (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=3.2.57 CRAFT_TEST_BASH_CANDIDATES="$FIX/cand-new/bash" CRAFT_TEST_PYTHON3_VERSION=missing
{ [[ $RC -eq 20 ]] && printf '%s\n' "$OUT" | grep -q "^PATH_REMEDY=bash 5.2.37 is installed at $FIX/cand-new/bash but is not on this session's PATH" \
  && has "INSTALL_PYTHON3=brew install python"; } \
  && ok "off-PATH bash + python3 missing → PATH remedy for bash, install command for python3" || bad "off-path + python (rc=$RC, out=$OUT)"
if [[ -x /opt/homebrew/bin/bash && -x /bin/bash && "$(/bin/bash -c 'printf %s "${BASH_VERSINFO[0]}"')" -lt 5 ]]; then
  OUT="$(env -u CRAFT_TEST_BASH_CANDIDATES CRAFT_TEST_PYTHON3_VERSION=3.12.1 /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"; RC=$?
  { [[ $RC -eq 20 ]] && has "BASH_PATH=/bin/bash" && has "BASH_OFF_PATH=/opt/homebrew/bin/bash" && lacks_prefix "INSTALL_BASH="; } \
    && ok "real machine: /bin/bash 3.2 run finds /opt/homebrew/bin/bash off PATH by default" || bad "real off-path default (rc=$RC, out=$OUT)"
  # bash localizes `--version`; a desktop launch may carry no LANG at all. The fix must survive both.
  for loc in unset de_DE.UTF-8 ja_JP.UTF-8; do
    if [[ "$loc" == unset ]]; then
      OUT="$(env -u LANG -u LC_ALL -u LC_MESSAGES -u CRAFT_TEST_BASH_CANDIDATES CRAFT_TEST_PYTHON3_VERSION=3.12.1 /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"
    else
      OUT="$(env -u LC_ALL -u CRAFT_TEST_BASH_CANDIDATES LANG="$loc" LC_MESSAGES="$loc" CRAFT_TEST_PYTHON3_VERSION=3.12.1 /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"
    fi
    { has "BASH_OFF_PATH=/opt/homebrew/bin/bash" && lacks_prefix "INSTALL_BASH="; } \
      && ok "real machine, locale $loc: off-PATH bash still found (no install command)" || bad "locale $loc (out=$OUT)"
  done
  # Three situations, three different fixes.
  OUT="$(env -u CRAFT_TEST_BASH_CANDIDATES CRAFT_TEST_PYTHON3_VERSION=3.12.1 PATH="/opt/homebrew/bin:$PATH" /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"
  { printf '%s\n' "$OUT" | grep -q '^PATH_REMEDY=.*this run was started with /bin/bash explicitly; fix: run it with plain `bash`$'; } \
    && ok "PATH already resolves bash to the current one, run was /bin/bash explicitly → 'run it with plain bash', no Claude Code advice" || bad "explicit old bash (out=$OUT)"
  mkdir -p "$FIX/oldfirst"; ln -s /bin/bash "$FIX/oldfirst/bash"
  OUT="$(env -u CRAFT_TEST_BASH_CANDIDATES CRAFT_TEST_PYTHON3_VERSION=3.12.1 PATH="$FIX/oldfirst:/opt/homebrew/bin:/usr/bin:/bin" /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"
  { printf '%s\n' "$OUT" | grep -q "^PATH_REMEDY=.*an older bash ($FIX/oldfirst/bash 3.2.57) comes first on PATH; fix: put /opt/homebrew/bin first on PATH"; } \
    && ok "current bash on PATH but behind an older one → 'put <dir> first on PATH'" || bad "behind old bash (out=$OUT)"
fi

echo "NOTES FIT THE MISSING TOOL:"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_PYTHON3_VERSION=missing
{ [[ $RC -eq 20 ]] && lacks_prefix "INSTALL_NOTE="; } && ok "macOS, only python3 missing → no bash PATH note" || bad "darwin python-only note (rc=$RC, out=$OUT)"
f="$(osrel rocky8py 'ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.10"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=5.2.0 CRAFT_TEST_PYTHON3_VERSION=missing
{ [[ $RC -eq 20 ]] && has "INSTALL_PYTHON3=sudo dnf install python3" && lacks_prefix "INSTALL_NOTE="; } \
  && ok "Rocky 8 with bash 5.2, only python3 missing → no 'packages bash < 5.0' note" || bad "rocky python-only note (rc=$RC, out=$OUT)"

echo "MORE OLD RELEASES:"
f="$(osrel centos7 'ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.2.46
{ has "INSTALL_BASH=sudo yum install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=centos 7 packages bash < 5.0'; } \
  && ok "CentOS 7 → yum (no dnf) + release note" || bad "centos 7 (rc=$RC, out=$OUT)"
f="$(osrel ol8 'ID="ol"
ID_LIKE="fedora"
VERSION_ID="8.10"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.20
{ has "INSTALL_BASH=sudo dnf install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=ol 8.10 packages bash < 5.0'; } \
  && ok "Oracle Linux 8 → dnf + release note" || bad "oracle linux 8 (rc=$RC, out=$OUT)"
f="$(osrel sles15 'ID="sles"
ID_LIKE="suse"
VERSION_ID="15.6"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.0
{ has "INSTALL_BASH=sudo zypper install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=sles 15.6 packages bash < 5.0'; } \
  && ok "SLES 15 → zypper + release note" || bad "sles 15 (rc=$RC, out=$OUT)"
f="$(osrel ubuntu18 'ID=ubuntu
ID_LIKE=debian
VERSION_ID="18.04"')"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$f" CRAFT_TEST_BASH_VERSION=4.4.18
{ has "INSTALL_BASH=sudo apt install bash" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=ubuntu 18.04 packages bash < 5.0'; } \
  && ok "Ubuntu 18.04 → apt + release note" || bad "ubuntu 18.04 (rc=$RC, out=$OUT)"

echo "INPUT HARDENING:"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=08.1.0
{ [[ $RC -eq 0 ]] && has "BASH=ok" && [[ "$OUT" != *"value too great"* ]]; } \
  && ok "leading-zero version 08.1 → read as base 10 (8 >= 5), no octal arithmetic error" || bad "08.1 (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=04.9.0
{ [[ $RC -eq 20 ]] && has "BASH=too-old" && [[ "$OUT" != *"value too great"* ]]; } \
  && ok "leading-zero version 04.9 → too old" || bad "04.9 (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=05.2.0
{ [[ $RC -eq 0 ]] && has "BASH=ok"; } && ok "leading-zero version 05.2 → ok" || bad "05.2 (rc=$RC, out=$OUT)"
printf 'ID=ubuntu\r\nID_LIKE=debian\r\nVERSION_ID="24.04"\r\n' > "$FIX/os-release.crlf"
run CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$FIX/os-release.crlf" CRAFT_TEST_BASH_VERSION=4.4.0
{ has "OS_ID=ubuntu" && has "INSTALL_BASH=sudo apt install bash"; } \
  && ok "CRLF os-release → still recognized (ubuntu → apt)" || bad "crlf os-release (rc=$RC, out=$OUT)"
mkdir -p "$FIX/p-crlf/.claude/plans"
printf 'HOOK_BASH_VERSION=3.2.57(1)-release\r\nHOOK_BASH_PATH=/bin/bash\r\n' > "$FIX/p-crlf/.claude/plans/.hook-env"
OUT="$(env CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 CRAFT_TEST_PYTHON3_VERSION=3.12.1 bash "$HELPER" --project "$FIX/p-crlf" 2>&1)"; RC=$?
{ [[ $RC -eq 10 ]] && has "HOOK_BASH_PATH=/bin/bash"; } && ok "CRLF hook record → parsed, path without carriage return" || bad "crlf hook-env (rc=$RC, out=$OUT)"
mkdir -p "$FIX/fakepy-bad" "$FIX/fakepy-garbage"
printf '#!/bin/sh\necho "No version is set for command python3"\nexit 126\n' > "$FIX/fakepy-bad/python3"
printf '#!/bin/sh\necho "hello"\nexit 0\n' > "$FIX/fakepy-garbage/python3"
chmod +x "$FIX/fakepy-bad/python3" "$FIX/fakepy-garbage/python3"
for kind in bad garbage; do
  OUT="$(env PATH="$FIX/fakepy-$kind:$PATH" CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 bash "$HELPER" --project "$FIX/empty-project" 2>&1)"; RC=$?
  { [[ $RC -eq 20 ]] && has "PYTHON3=missing"; } && ok "python3 shim ($kind: stdout text, exit non-zero or no version) → missing" || bad "python3 shim $kind (rc=$RC, out=$OUT)"
done

echo "OTHER PLATFORMS:"
run CRAFT_TEST_UNAME=MINGW64_NT-10.0-26100 CRAFT_TEST_BASH_VERSION=4.4.23
{ [[ $RC -eq 20 ]] && has "OS=windows" && printf '%s\n' "$OUT" | grep -q '^INSTALL_BASH=use WSL 2 (recommended), or update Git for Windows' && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=Windows support is untested'; } \
  && ok "Git Bash (MINGW) → WSL 2 first / update Git for Windows + untested note" || bad "mingw (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=MINGW64_NT-10.0-26100 CRAFT_TEST_BASH_VERSION=5.2.37 CRAFT_TEST_PYTHON3_VERSION=missing
{ [[ $RC -eq 20 ]] && lacks_prefix "INSTALL_BASH=" && printf '%s\n' "$OUT" | grep -q '^INSTALL_NOTE=Windows support is untested'; } \
  && ok "Git Bash with current bash, python3 missing → platform note kept, no bash hint" || bad "mingw python-only (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=FreeBSD CRAFT_TEST_BASH_VERSION=4.4.0
{ [[ $RC -eq 20 ]] && has "OS=unknown" && has "INSTALL_BASH=install bash >= 5.0"; } \
  && ok "unknown OS → generic hint" || bad "unknown os (rc=$RC, out=$OUT)"

echo "HOOK RECORD:"
mkdir -p "$FIX/p-old/.claude/plans" "$FIX/p-new/.claude/plans"
printf 'HOOK_BASH_VERSION=3.2.57(1)-release\nHOOK_BASH_PATH=/bin/bash\n' > "$FIX/p-old/.claude/plans/.hook-env"
printf 'HOOK_BASH_VERSION=5.2.37(1)-release\nHOOK_BASH_PATH=/usr/bin/bash\n' > "$FIX/p-new/.claude/plans/.hook-env"
OUT="$(env CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 CRAFT_TEST_PYTHON3_VERSION=3.12.1 bash "$HELPER" --project "$FIX/p-old" 2>&1)"; RC=$?
running_bash_dir="$(bash -c 'printf %s "${BASH%/*}"')"
remedy="$(printf '%s\n' "$OUT" | sed -n 's/^HOOK_REMEDY=//p')"
{ [[ $RC -eq 10 ]] && has "HOOK_BASH=too-old" && has "HOOK_BASH_VERSION=3.2.57" && has "STATUS=hook-mismatch" \
  && [[ "$remedy" == *"hooks started this session with /bin/bash 3.2.57"* ]] && [[ "$remedy" == *'"env": {"PATH"'* ]] \
  && [[ "$remedy" == *"unaffected"* ]] && [[ "$remedy" == *"rewritten at every session start"* ]] \
  && [[ "$remedy" == *"with $running_bash_dir first"* ]] && [[ "$remedy" != *"$running_bash_dir/bash"* ]]; } \
  && ok "hook ran 3.2, tool bash 5.3 → hook-mismatch, exit 10, remedy names env.PATH and the bash directory once" || bad "hook mismatch (rc=$RC, out=$OUT)"
OUT="$(env CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 CRAFT_TEST_PYTHON3_VERSION=3.12.1 bash "$HELPER" --project "$FIX/p-new" 2>&1)"; RC=$?
{ [[ $RC -eq 0 ]] && has "HOOK_BASH=ok" && has "STATUS=ok"; } \
  && ok "hook ran 5.2 → ok" || bad "hook ok (rc=$RC, out=$OUT)"
run CRAFT_TEST_UNAME=Darwin
{ [[ $RC -eq 0 ]] && has "HOOK_BASH=unknown"; } && ok "no hook record → unknown, no warning" || bad "no hook record (rc=$RC, out=$OUT)"
OUT="$(env CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=3.2.57 CRAFT_TEST_PYTHON3_VERSION=3.12.1 bash "$HELPER" --project "$FIX/p-old" 2>&1)"; RC=$?
{ [[ $RC -eq 20 ]] && has "STATUS=missing-tools" && lacks_prefix "HOOK_REMEDY="; } \
  && ok "tool bash itself too old → missing-tools wins over hook mismatch" || bad "precedence (rc=$RC, out=$OUT)"

# A construct newer than the running bash often does NOT stop a script: bash 3.2 reports e.g.
# "${x,,}: bad substitution", abandons that one command, and carries on — a harness can stay green
# while the hook is broken. Runs under the old bash must therefore also be free of shell error text.
shell_errors() { printf '%s\n' "$1" | grep -iE 'bad substitution|syntax error|command not found|invalid option|not a valid identifier|unbound variable|bad array subscript' ; }

echo "HOOK UNDER THE SYSTEM BASH:"
HOOK_BASH="bash"
[[ -x /bin/bash ]] && HOOK_BASH="/bin/bash"
hook_version="$("$HOOK_BASH" -c 'printf %s "$BASH_VERSION"')"
mkdir -p "$FIX/onboarded/.claude/project" "$FIX/onboarded/.claude/plans" "$FIX/plain"
printf 'intent\n' > "$FIX/onboarded/.claude/project/intent.md"
: > "$FIX/onboarded/.claude/plans/.primed"
HOUT="$(CLAUDE_PROJECT_DIR="$FIX/onboarded" "$HOOK_BASH" "$HOOK" 2>&1)"; HRC=$?
{ [[ $HRC -eq 0 ]] && [[ ! -e "$FIX/onboarded/.claude/plans/.primed" ]] \
  && grep -qxF "HOOK_BASH_VERSION=$hook_version" "$FIX/onboarded/.claude/plans/.hook-env" \
  && [[ "$HOUT" == *"Auto-priming"* ]] && [[ -z "$(shell_errors "$HOUT")" ]]; } \
  && ok "session-start.sh under $HOOK_BASH ($hook_version) records its own bash, clears .primed, still auto-primes" \
  || bad "hook record (rc=$HRC, out=$HOUT, env=$(cat "$FIX/onboarded/.claude/plans/.hook-env" 2>&1))"
CLAUDE_PROJECT_DIR="$FIX/plain" "$HOOK_BASH" "$HOOK" >/dev/null 2>&1
{ [[ ! -e "$FIX/plain/.claude" ]]; } && ok "non-onboarded project → hook writes nothing" || bad "hook wrote into a non-onboarded project"
mkdir -p "$FIX/blocked/.claude/project"; printf 'intent\n' > "$FIX/blocked/.claude/project/intent.md"
mkdir -p "$FIX/blocked/.claude/plans/.hook-env"   # a directory: mkdir succeeds, the write fails
BERR="$(CLAUDE_PROJECT_DIR="$FIX/blocked" "$HOOK_BASH" "$HOOK" 2>&1 >/dev/null)"; BRC=$?
BOUT="$(CLAUDE_PROJECT_DIR="$FIX/blocked" "$HOOK_BASH" "$HOOK" 2>/dev/null)"
{ [[ $BRC -eq 0 ]] && [[ -z "$BERR" ]] && [[ "$BOUT" == *"Auto-priming"* ]]; } \
  && ok "record cannot be written (.hook-env is a directory) → hook stays silent on stderr, exit 0, still auto-primes" \
  || bad "unwritable record (rc=$BRC, stderr=$BERR, stdout=$BOUT)"

# Every hook, and the helper that must report an old bash, has to parse under the oldest bash
# the machine offers (3.2 on macOS). Skipped where no older system bash exists.
if [[ "$HOOK_BASH" == "/bin/bash" ]] && [[ "${hook_version%%.*}" -lt 5 ]]; then
  parse_fail=""
  for s in "$REPO_ROOT"/hooks/*.sh "$HELPER" "$SCRIPT_DIR/handoff-marker-state.sh" "$SCRIPT_DIR/review-findings-state.sh"; do
    /bin/bash -n "$s" 2>/dev/null || parse_fail="$parse_fail ${s#$REPO_ROOT/}"
  done
  [[ -z "$parse_fail" ]] && ok "hooks/*.sh, check-toolchain.sh, handoff-marker-state.sh and review-findings-state.sh parse under /bin/bash $hook_version" || bad "3.2 parse failure:$parse_fail"
  OUT="$(/bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"; RC=$?
  { [[ $RC -eq 20 ]] && has "BASH=too-old" && has "BASH_PATH=/bin/bash"; } \
    && ok "helper run BY /bin/bash $hook_version reports itself too old, with its real path" || bad "helper under old bash (rc=$RC, out=$OUT)"

  # `bash -n` is not enough: it accepts ${x,,}, declare -A, mapfile, readarray — all of which
  # fail only at runtime under 3.2. So the hooks also have to RUN under /bin/bash.
  #
  # The read-only guard is the fail-open one: a hook that dies protects nothing. Its own harness
  # calls it as `bash "$GUARD"`, so a PATH whose `bash` is /bin/bash runs all its cases under 3.2.
  mkdir -p "$FIX/shim"; ln -s /bin/bash "$FIX/shim/bash"
  shim_version="$(PATH="$FIX/shim:$PATH" bash -c 'printf %s "$BASH_VERSION"')"
  GOUT="$(PATH="$FIX/shim:$PATH" /bin/bash "$SCRIPT_DIR/test-readonly-context.sh" 2>&1)"; GRC=$?
  { [[ "$shim_version" == "$hook_version" ]] && [[ $GRC -eq 0 ]] && [[ "$GOUT" == *"RESULT: "*" passed, 0 failed"* ]] && [[ -z "$(shell_errors "$GOUT")" ]]; } \
    && ok "read-only guard + sync helper: every test-readonly-context.sh case passes under /bin/bash $hook_version, no shell errors" \
    || bad "guard under 3.2 (shim=$shim_version, rc=$GRC, shell errors: $(shell_errors "$GOUT" | head -2), tail=$(printf '%s\n' "$GOUT" | tail -1))"

  # worktree-handoff-notify.sh under /bin/bash against a real worktree carrying a handoff marker.
  git init -q "$FIX/wt-repo" && git -C "$FIX/wt-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
    && git -C "$FIX/wt-repo" worktree add -q "$FIX/wt-slice" -b slice-999-probe 2>/dev/null
  mkdir -p "$FIX/wt-slice/.craft"
  printf -- '---\nSlice-ID: slice-999\nStatus: awaiting-test\n---\n\n# Handoff: probe marker\n' > "$FIX/wt-slice/.craft/handoff.md"
  NOUT="$(CLAUDE_PROJECT_DIR="$FIX/wt-repo" /bin/bash "$REPO_ROOT/hooks/worktree-handoff-notify.sh" 2>&1)"; NRC=$?
  { [[ $NRC -eq 0 ]] && [[ "$NOUT" == *"slice-999 (awaiting-test): Handoff: probe marker"* ]] && [[ -z "$(shell_errors "$NOUT")" ]]; } \
    && ok "worktree-handoff-notify.sh runs under /bin/bash $hook_version and reports the handoff marker" \
    || bad "handoff notifier under 3.2 (rc=$NRC, out=$NOUT)"
else
  echo "  SKIP  no system bash older than 5 — 3.2 parse/run cases not applicable here"
fi

# Constructs newer than bash 3.2 that `bash -n` does not reject. Scanned on every machine (also where
# no old bash exists to run the hooks under); full-line comments are ignored, since the helper's own
# header names the forbidden constructs.
echo "NO BASH-4 CONSTRUCTS IN 3.2-BOUND FILES:"
bash4_hits=""
for s in "$REPO_ROOT"/hooks/*.sh "$HELPER" "$SCRIPT_DIR/handoff-marker-state.sh" "$SCRIPT_DIR/review-findings-state.sh"; do
  hits="$(grep -nE "$BASH4_PATTERN" "$s" \
    | grep -vE '^[0-9]+:[[:space:]]*#')"
  [[ -n "$hits" ]] && bash4_hits="$bash4_hits
  ${s#$REPO_ROOT/}: $hits"
done
[[ -z "$bash4_hits" ]] && ok "hooks/*.sh, check-toolchain.sh, handoff-marker-state.sh and review-findings-state.sh contain no construct newer than bash 3.2" \
  || bad "bash-4+ constructs in 3.2-bound files:$bash4_hits"

# The helper must itself run on the old bash it reports — every branch, not just the Darwin one.
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'printf %s "${BASH_VERSINFO[0]}"')" -lt 5 ]]; then
  echo "HELPER BRANCHES UNDER /bin/bash:"
  matrix_fail=""
  for fixture in os-release.ubuntu os-release.rocky8 os-release.centos7 os-release.amzn2 os-release.sles15 os-release.leap os-release.crlf os-release.gentoo; do
    OUT="$(env CRAFT_TEST_UNAME=Linux CRAFT_TEST_OS_RELEASE="$FIX/$fixture" CRAFT_TEST_BASH_VERSION=4.4.0 CRAFT_TEST_PYTHON3_VERSION=missing CRAFT_TEST_BASH_CANDIDATES="$FIX/cand-new/bash" /bin/bash "$HELPER" --project "$FIX/p-crlf" 2>&1)"
    { has "STATUS=missing-tools" && [[ -z "$(shell_errors "$OUT")" ]]; } || matrix_fail="$matrix_fail $fixture"
  done
  for uname in MINGW64_NT-10.0 FreeBSD Darwin; do
    OUT="$(env CRAFT_TEST_UNAME="$uname" CRAFT_TEST_BASH_VERSION=08.1.0 CRAFT_TEST_PYTHON3_VERSION=3.12.1 CRAFT_TEST_BASH_CANDIDATES= /bin/bash "$HELPER" --project "$FIX/p-old" 2>&1)"
    { has "STATUS=hook-mismatch" && [[ -z "$(shell_errors "$OUT")" ]]; } || matrix_fail="$matrix_fail $uname"
  done
  OUT="$(env PATH="$FIX/fakepy-bad:$PATH" CRAFT_TEST_UNAME=Darwin CRAFT_TEST_BASH_VERSION=5.3.15 /bin/bash "$HELPER" --project "$FIX/empty-project" 2>&1)"
  { has "PYTHON3=missing" && [[ -z "$(shell_errors "$OUT")" ]]; } || matrix_fail="$matrix_fail python-shim"
  [[ -z "$matrix_fail" ]] && ok "every helper branch (8 distros, Windows, BSD, macOS, hook record, CRLF, off-PATH, python shim) runs under /bin/bash without shell errors" \
    || bad "helper branches under /bin/bash failed:$matrix_fail"
fi

# The scanner itself: it must hit each construct and stay quiet on look-alikes that 3.2 accepts.
echo "SCANNER SELF-TEST:"
printf '%s\n' 'x=${y,,}' 'x=${1^^}' 'x=${arr[@],,}' 'declare -A m' 'local -n ref=x' 'declare -g g=1' 'mapfile -t a' 'readarray a' \
  'coproc c { :; }' 'cmd |& tee' 'cmd &>> log' 'case a in a) :;& esac' '[[ -v var ]]' 'x=${y@Q}' 'echo $EPOCHSECONDS' \
  'wait -n' 'shopt -s globstar' 'shopt -s lastpipe' 'x=${y:0:-1}' 'exec {fd}>file' 'read -N 3 x' 'echo $BASHPID' \
  "printf '%(%F)T'" 'echo {1..10..2}' > "$FIX/bash4.sample"
printf '%s\n' 'x=${y:-a,b}' 'x=${y#*,}' 'x=${y%%[(-]*}' 'declare -r c=1' 'local x' 'read -r line' 'echo {1..3}' \
  'x=${y:0:3}' 'cmd 2>&1' 'cmd >> log' 'case a in a) :;; esac' '# declare -A in a comment' "printf '%s' x" > "$FIX/bash32.sample"
scan() { grep -nE "$BASH4_PATTERN" "$1" | grep -vE '^[0-9]+:[[:space:]]*#'; }
missed=""; while IFS= read -r l; do printf '%s\n' "$l" > "$FIX/one"; [[ -n "$(scan "$FIX/one")" ]] || missed="$missed [$l]"; done < "$FIX/bash4.sample"
false_hits="$(scan "$FIX/bash32.sample")"
[[ -z "$missed" ]] && ok "scanner hits all $(grep -c . "$FIX/bash4.sample") bash-4+ constructs in its sample" || bad "scanner missed:$missed"
[[ -z "$false_hits" ]] && ok "scanner stays quiet on bash-3.2 look-alikes (defaults, trims, redirects, comments)" || bad "scanner false positives: $false_hits"

echo "USAGE:"
OUT="$(bash "$HELPER" --project 2>&1)"; RC=$?
{ [[ $RC -eq 2 ]] && [[ "$OUT" == *"ERROR=missing_value:--project"* ]]; } \
  && ok "--project with no value → usage error, exit 2" || bad "missing value (rc=$RC, out=$OUT)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
