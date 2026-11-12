# Bash Projects — Layout, Scripts, Libraries, Portability

Patterns for a project made of shell scripts — a tool, a set of hooks, an installer, a script library. "Observed" marks what was
run on 2026-11-11 with bash 5.3.20, macOS's `/bin/bash` 3.2.57 and ShellCheck 0.11.0. Style rules are in
`references/code-quality-standards.md`.

## Project layout

```text
bin/mytool              # entry points: executable, no extension, #!/usr/bin/env bash
lib/mytool/log.bash     # sourced libraries: no shebang, no execute bit, .bash extension
lib/mytool/fs.bash
scripts/                # maintenance scripts: lint, release, test runner
test/mytool.bats        # one .bats file per script or library
test/test_helper/       # bats-support, bats-assert (submodules) and common.bash
test/fixtures/          # input files and expected output
.shellcheckrc           # shell=bash, external-sources=true, source-path=SCRIPTDIR/../lib
.editorconfig           # indent for shfmt (ShellCheck reads shellcheck.* keys from it in its development version, not in 0.11.0)
```

- **Executables without extension, libraries with `.bash`**: callers should not know what language a command is written in, and the
  extension tells ShellCheck and shfmt the dialect for libraries that have no shebang.
- **One responsibility per file.** A script over a few hundred lines wants its functions moved into `lib/` and tests per library.
  When the logic needs data structures, parsing or concurrency, a real language is the better tool: Google's shell style guide
  limits shell to small utilities and wrappers and says to rewrite a script past 100 lines or with non-straightforward control flow.
- **Run from anywhere**: resolve the script's own directory, never assume the current directory (see the library loader below).
- **Executable bit in git**: `git update-index --chmod=+x bin/mytool` when the file system does not keep it.

## A complete entry script

The skeleton below was run under 5.3.20 and 3.2.57 (all paths: help, errors, dry run, sourcing) and passes ShellCheck 0.11.0.

```bash
#!/usr/bin/env bash
# deploy — copy FILEs into a work directory
set -euo pipefail

readonly PROG=${0##*/}

usage() {
  cat <<EOF
Usage: $PROG [-n] [-o DIR] [--] FILE...
  -n, --dry-run     print what would be done
  -o, --output DIR  target directory (default: ./out)
  -h, --help        show this help
EOF
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-1}"
}

tmpdir=
cleanup() {
  [[ -z $tmpdir ]] || rm -rf -- "$tmpdir"
}

main() {
  local dry_run=0 out=./out f
  local -a files=()

  while (($#)); do
    case $1 in
      -h | --help) usage; return 0 ;;
      -n | --dry-run) dry_run=1 ;;
      -o | --output)
        (($# >= 2)) || die "$1 needs a value" 2
        out=$2
        shift
        ;;
      --) shift; break ;;
      -*) die "unknown option: $1" 2 ;;
      *) break ;;
    esac
    shift
  done
  files=("$@")
  ((${#files[@]})) || { usage >&2; return 2; }

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/$PROG.XXXXXX")

  for f in "${files[@]}"; do
    [[ -f $f ]] || die "not a file: $f"
    if ((dry_run)); then
      printf 'would copy %s to %s\n' "$f" "$out"
    else
      printf 'copy %s to %s\n' "$f" "$out"
    fi
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
```

## Arguments, input, output

- **Parse in a `while (($#)); do case ...` loop** (above) for long options; `getopts` for short ones only (it is a POSIX builtin
  and works in `sh`, but takes no `--long`). The `getopt` command differs: macOS ships a BSD `getopt` without long options (observed) — do not use it in portable code.
- **`--help` prints to stdout and exits 0; a usage error prints to stderr and exits 2.** Unknown option: error, never ignore.
- **`--` ends options** for your own parser and for every command you call with user data (`rm -- "$f"`, `grep -e "$p" -- "$f"`).
- **Configuration order**: defaults in the script, then a config file, then environment variables, then flags. Name variables with
  a prefix (`MYTOOL_HOME`) and document them in `usage`.
- **Stdin/stdout contract**: read a file named `-` as stdin only when the script says so; print machine-readable results to stdout
  and progress or logs to stderr. Colour only when `[[ -t 2 ]]` and `NO_COLOR` is unset.
- **Logging helpers** (`log`, `warn`, `die`) live in one library and write to stderr with `printf`; they do not call `exit` except `die`.
- **Exit codes** are part of the interface: document them next to `usage`, keep 2 for usage errors.

## Sourced libraries

```bash
# lib/mytool/log.bash — sourced, never executed; sets no shell options
[[ -n ${_MYTOOL_LOG_LOADED:-} ]] && return 0
_MYTOOL_LOG_LOADED=1

mytool_log() { printf '%s\n' "$*" >&2; }
```

```bash
# bin/mytool
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/../lib/mytool/log.bash
source "$script_dir/../lib/mytool/log.bash"
```

- **A library defines functions and constants only** — no output, no `cd`, no `set -e` / `-u` / `pipefail`, no `exit`, no work at
  source time. Guard against double loading; prefix every function and global (`mytool_`), because bash has one namespace.
- **`source` finds files relative to the current directory and `PATH`**, not to the script: always build the path from
  `BASH_SOURCE[0]`. `source -p PATH file` (5.3) searches a given path instead of `PATH`.
- **ShellCheck follows `source` only when told**: it needs `-x` (or `external-sources=true` in `.shellcheckrc`), and it needs to know
  where the file is — a `# shellcheck source=SCRIPTDIR/../lib/mytool/log.bash` line above the command (a plain relative path resolves
  against ShellCheck's working directory, not the script's), or `source-path=SCRIPTDIR/../lib` in `.shellcheckrc`. `# shellcheck source=/dev/null` skips a file that is not in the repo.
  A library without shebang needs `# shellcheck shell=bash` on its first line (or the `.bash` extension).
- **Return values from sourced functions**: set a named global (`MYTOOL_RESULT`) or print and capture; a nameref (`local -n`, 4.3) is
  the clean way for arrays.
- **Testable by design**: a script whose `main` is guarded (`BASH_SOURCE[0] == $0`) can be sourced by a test that then calls its
  functions (`references/test-patterns.md`).

## Calling other programs

- **Check for a tool once, early**: `command -v jq >/dev/null 2>&1 || die "jq is required"`. `command -v` is POSIX; `which` is not.
- **Build commands as arrays** and run `"${cmd[@]}"`; never assemble a command in a string for `eval`.
- **Do not trust `PATH` in security-sensitive scripts**: set it, or call tools by absolute path.
- **BSD versus GNU userland on macOS** (observed on macOS 26.5.2):

| Task | GNU / Linux | macOS (BSD) | Portable |
|---|---|---|---|
| in-place edit | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` (the bare form fails) | `sed 's/a/b/' f > "$tmp" && mv "$tmp" f` |
| file size | `stat -c %s f` | `stat -f %z f` (`-c` is illegal) | `wc -c < f` |
| date arithmetic | `date -d yesterday` | `date -v-1d` (`-d` is illegal) | compute with `$EPOCHSECONDS` (5.0) or `awk` |
| PCRE | `grep -P` | not supported | `grep -E`, or `[[ =~ ]]` |
| canonical path | `readlink -f f` | worked on 26 (observed), not POSIX | directory: `cd -P -- "$(dirname -- "$f")" && pwd -P`; the file itself: `realpath f` (POSIX.1-2024; `/bin/realpath` on macOS 26, observed), guarded with `command -v realpath` |
| timeout, lock | `timeout`, `flock` | absent from the base system | `read -t`, `mkdir` lock |
| version sort | `sort -V` | worked on 26 (observed) | avoid on old systems |

  Homebrew's `coreutils`, `gnu-sed` and `grep` install the GNU tools with a `g` prefix (`gsed`, `gdate`); a script that needs GNU
  behaviour says so and checks for it, it does not assume.

## Portability

**Decide the floor once and write it down** (header comment, README, `usage`): POSIX `sh`, bash 3.2, bash 4.4, or bash 5. The
floor decides the syntax; ShellCheck cannot tell: it knows the dialects `sh`, `bash`, `dash`, `ksh` and `busybox`, not bash versions,
and stayed silent on `mapfile`, `${v,,}`, `declare -A` and `${a[-1]}` under `shell=bash` (observed).

### POSIX sh

POSIX.1-2024 (Issue 8) defines the Shell Command Language. Under `#!/bin/sh` use only that:

- **In POSIX.1-2024**: `set -o pipefail`, `$'...'` quoting, `command -v`, `printf`, `$(( ))`, `${v#p}` `${v%p}` `${v:-d}`, `case`, `trap`,
  `getopts`, `[ ]` and `test`, here-documents, `read -r`.
- **Not in POSIX**: arrays, `[[ ]]`, `local`, `declare`, `source` (use `.`), `==` in `[ ]`, `echo -e`, `<(...)`, `${v//a/b}`, `${v,,}`, `(( ))`,
  `mapfile`, `mktemp`, `&>`, `function f`. ShellCheck reports them under `--shell=sh` as SC3xxx
  (observed: SC3030 arrays, SC3010 `[[ ]]`, SC3043 `local`, SC3057 string indexing, SC3054 array references).
- **A shell that implements the standard is not guaranteed**: the dash on this Mac rejects `set -o pipefail` (`Illegal option -o pipefail`)
  and prints `$'a\tb'` literally (observed), although POSIX.1-2024 lists both. Upstream dash added `pipefail` in a commit of 2024-04-05
  that releases from 0.5.13 on carry; older dash lacks it. ShellCheck 0.11.0 still warns on both under `-s sh` (SC3040, SC3003); only its
  development version follows POSIX.1-2024 here. Check the target shells before relying on a newly standardised feature.
- **`/bin/sh` is not a test of POSIX**: on macOS 26 it is a launcher that by default starts bash 3.2.57 in POSIX mode (it still ran arrays and `[[ ]]`, observed), so a
  bashism passes on the Mac and fails on Debian's dash. Test with `dash script.sh` (or BusyBox `ash`) and `shellcheck -s sh`.

### macOS `/bin/bash` 3.2

macOS 26.5.2 still ships `/bin/bash` 3.2.57 (observed 2026-11-11); `/bin/sh` is a launcher that by default runs it in POSIX mode. Anything started with
`#!/bin/bash` or from a hook, a launchd job or `ssh` with a minimal `PATH` may run it. A script bound to it avoids, with the release
that introduced the feature:

| Construct | Introduced | On 3.2.57 (observed) |
|---|---|---|
| `declare -A` associative arrays | 4.0 | message; without `-e` it **carries on** (`m[a]=1` writes index 0 of a plain array), under `set -e` it stops with status 2 |
| `mapfile` / `readarray` | 4.0 (`-d` 4.4) | `command not found` |
| `${v,,}` `${v^^}` | 4.0 | `bad substitution` |
| `&>>`, `\|&`, `;&`, `;;&` | 4.0 | syntax error |
| `coproc`, `shopt -s globstar` | 4.0 | `coproc cmd`: `command not found` (status 127), without `-e` the script carries on, under `set -e` it stops; only `coproc NAME { … }` is a syntax error; `globstar`: `invalid shell option` |
| `{fd}>file` redirections | 4.1 | error |
| `(( ))` and `[[ ]]` obey `set -e` | 4.1 | they do **not**: a failing test does not stop the script |
| `[[ -v var ]]`, `printf '%(%s)T'`, `shopt -s lastpipe`, `declare -g`, `${a[-1]}` | 4.2 | error |
| `declare -n` / `local -n` namerefs, `wait -n` | 4.3 | error |
| `${v@Q}`, `shopt -s inherit_errexit`, `local -`, empty `"${a[@]}"` under `set -u` | 4.4 | error (`unbound variable` for the array) |
| `EPOCHSECONDS`, `EPOCHREALTIME`, `BASH_ARGV0` | 5.0 | empty / plain variable |
| `SRANDOM`, `${v@U}` `${v@L}` | 5.1 | empty / error |
| `${ cmd; }`, `trap -P`, `source -p`, `GLOBSORT` | 5.3 | error / plain variable |

Fine on 3.2: `local`, `printf -v`, `$'...'`, `[[ =~ ]]`, `+=` on arrays, `set -o pipefail`, `<<<`, `<( )`.

**Check portability by running the real thing**, not by reading:

- Run the script and its tests under the target bash and fail on **any** shell error text, not only on a status: without `-e`, 3.2 skips a
  failing command and carries on green (`declare -A` above). `bash -n` is no evidence — it parses, and accepts bash 4 constructs.
  `BASH_COMPAT=32` is none either: on 5.3 it kept `mapfile` and `declare -A` working (observed).
- A bats suite is meant to run on 3.2 too: bats-core's support matrix lists 3.2.57 (read in its docs; a bats run on 3.2 was not made
  for this pack). Run bats itself under the target bash and compare.
- Use two independent detectors: a scanner for bash 4 constructs (the table above is its word list) and real runs on the target
  bash that fail on error text.

**A version guard works only as its own top-level command, before the constructs it protects.** On 3.2 a guard followed by a function
using `|&` printed the message and exited 1 (observed); with the guard and `|&` inside one function, 3.2 died at parse time with a
syntax error before the guard ran.

```bash
#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  printf '%s: needs bash 4.4 or newer (this is %s)\n' "${0##*/}" "$BASH_VERSION" >&2
  exit 1
fi
```

On macOS the usual answer is `brew install bash` plus `#!/usr/bin/env bash`; a hook or a tool started by something else with a
fixed `PATH` still gets 3.2, so say in the README which interpreter is required.
