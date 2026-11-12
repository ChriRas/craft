# Bash 5 — Code Quality Standards

The target is GNU Bash 5.x (5.3 is current), started as `#!/usr/bin/env bash`, linted with ShellCheck and formatted with shfmt.
A script that must also run on macOS's `/bin/bash` 3.2 or on plain `sh` follows `references/project-patterns.md` →
`## Portability`; a version in parentheses below is the bash release that introduced the feature (from the Bash NEWS file).
Examples marked "observed" were run on bash 5.3.20 and 3.2.57 on 2026-11-11.

## Mandatory shape

A script is a header, a few small functions, a `main` and a guarded call. Everything runnable lives in a function; the file does
nothing else on being sourced.

```bash
#!/usr/bin/env bash
# name.sh — one line: what it does and for whom
set -euo pipefail

readonly PROG=${0##*/}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-1}"
}

main() {
  local input=${1:?usage: $PROG FILE}
  [[ -r $input ]] || die "cannot read: $input"
  # ...
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
```

- **Two-space indent**, shfmt's output is the format (`references/test-patterns.md` → `## ShellCheck and shfmt as gates`).
- **`#!/usr/bin/env bash`** finds the bash on `PATH` (macOS: the Homebrew one when installed, else 3.2); `#!/bin/bash` pins the
  system's. Pick on purpose and say which in the script's header comment when it matters.
- **Messages go to stderr**, results to stdout; `printf` over `echo`.
- **Names** — `lower_case` for locals and functions, `UPPER_CASE` for constants and exported variables, `readonly` for constants.

## Quoting and expansion

- **Quote every expansion**: `"$var"`, `"$(cmd)"`, `"${arr[@]}"`, `"$@"` (never `$*`). Leave a word unquoted only on purpose:
  the right side of `[[ == ]]` as a glob, an arithmetic context, an assignment (`x=$y` needs no quotes).
- **Test patterns** — `[[ $f == *.txt ]]` is a glob, `[[ $f == "*.txt" ]]` is literal. For a regex keep it in a variable and
  leave it unquoted: `re='^[0-9]+$'; [[ $n =~ $re ]]`; captures land in `BASH_REMATCH`.
- **Built-in expansions beat forks** — `${f##*/}` for basename, `${f%/*}` for dirname, `${s//a/b}`, `${v:-default}`,
  `${v:?message}`, `${s,,}` (4.0), `${s^^}`. Use `sed` and `awk` for what these cannot do.
- **`$(...)`**, never backticks; it strips trailing newlines, so `x=$(cmd; echo .); x=${x%.}` when they matter.
- **`printf '%s\n' "$x"`**, not `echo "$x"`: `echo -n "a"` prints `a` without a newline, `echo "-n"` prints nothing (observed), and
  backslash handling differs between builds. `printf -v name '%s' "$x"` assigns without a subshell; `printf '%q'` quotes for reuse.
- **Globs** — `./*` not `*` (a file named `-rf` is an option), `--` ends options (`grep -e "$pat" -- "$file"`). Set `nullglob`
  or test `[[ -e $f ]] || continue` before using a glob that may match nothing.
- **Never parse `ls`.** Loop over a glob, or `find ... -print0` with `while IFS= read -r -d '' f; do ...; done < <(find ...)`.
- **`read -r`** always (without it a backslash is eaten); `IFS= read -r line` keeps leading and trailing blanks.
- **No `eval`.** Build commands as arrays; reach a variable by name with a nameref (`local -n ref=$name`, 4.3) or a case list.
- **Here-documents** — `<<'EOF'` for literal text (no expansion), `<<-EOF` strips leading tabs only, not spaces.

## Variables, arrays, functions

```bash
local -a cmd=(curl --fail --silent --show-error)
[[ -n ${token:-} ]] && cmd+=(--header "Authorization: Bearer $token")
cmd+=(-- "$url")
"${cmd[@]}"
```

- **`local` every function variable.** Declare and assign a command substitution separately (`local out; out=$(cmd)`):
  `local out=$(false)` takes the status of `local`, so `set -e` never sees the failure (observed; ShellCheck SC2155). The same holds
  for `export X=$(cmd)` and `readonly X=$(cmd)`.
- **Arrays for lists**, never a space-joined string: `files=("$@")`, `arr+=("x")`, `${#arr[@]}`, `"${arr[@]}"`, the last element
  `${arr[-1]}` (4.2), `mapfile -t lines < <(cmd)` (4.0), NUL-separated `mapfile -d '' -t files < <(find ... -print0)` (4.4).
  `mapfile` reads in the current shell, which is why it is used over `cmd | while read`.
- **Associative arrays** (`declare -A m`, 4.0) are bash-only and unordered; quote the key (`m[$key]`), test with `[[ -v m[$key] ]]`
  (4.3), loop with `for k in "${!m[@]}"`. On a bash below 4.0 `declare -A` fails with a message; without `-e` the script goes on, and
  `m[a]=1` then indexes an ordinary array with 0 — a silent wrong result; under `set -e` it stops with status 2 (both observed on 3.2.57).
- **Functions** — `name() { ...; }` without the `function` keyword. Data comes back on stdout (`x=$(f)`), a status through
  `return`; to get several values without a fork, assign to a name the caller passes (`local -n out=$1`) or, in 5.3, capture with
  `${ f; }` (runs in the current shell; 5.3 only). Validate the argument count at the top (`(($# == 2)) || return 2`).
- **Exit codes** — 0 success, 1 failure, 2 usage error; 126 and 127 are the shell's ("not executable", "not found"); 128+N is
  death by signal N (130 after Ctrl-C, 141 SIGPIPE, 143 SIGTERM). Only `main` and `die` call `exit`; library functions `return`.
- **Arithmetic** — `$(( ))` for values, `(( ))` for tests. A number with a leading zero is octal: `$((08))` is an error, `$((10#08))`
  is 8 (observed) — force base 10 on input you did not write, after checking `[[ $n =~ ^[0-9]+$ ]]`.
  Integers only; use `awk` or `bc` for fractions.
- **Increment with `i=$((i + 1))`**, not `((i++))`: the latter has the status 1 when it evaluates to 0 (`i` was 0) and stops a script
  under `set -e`.

## `set -euo pipefail` and its pitfalls

The default header is `set -euo pipefail`: `-e` stops on an unchecked failing command, `-u` makes an unset variable an error,
`-o pipefail` makes a pipeline fail when any stage does (POSIX.1-2024 has it too). It is a safety net, not control flow: bash's
manual lists where `-e` does not apply, and the rest of this section is those places. Put the options in the file (not on the
`#!` line: `bash script.sh` ignores the shebang's flags).

| Situation | What happens | Do instead |
|---|---|---|
| `if f`, `f && x`, `f \|\| x`, `! f`, `while f` where `f` is a function | `-e` is **off for the whole body of `f`**: `f() { false; echo reached; }` prints `reached` (observed) | Call `f` on its own line and check `$?`, or `f \|\| return`; ShellCheck's optional `check-set-e-suppressed` (SC2310) flags it |
| `local x=$(cmd)`, `export X=$(cmd)` | the status of `cmd` is lost (observed) | `local x; x=$(cmd)` |
| `x=$(cmd)` on its own | `cmd`'s status is the assignment's: `-e` stops (observed) | fine |
| `((i++))`, `((n))` with a result of 0 | status 1, stops the script on bash 4.1 and later (bash 3.2 does not stop — observed) | `i=$((i + 1))`; `(( ))` only inside `if` |
| `[[ -n $x ]] && echo "$x"` as the last command of a function | the function returns 1 when the test is false, and `-e` stops the caller (observed) | `if [[ -n $x ]]; then echo "$x"; fi` |
| `cmd1 && cmd2` where `cmd1` fails mid-list | no stop: only the last command of a `&&` / `\|\|` list counts | `if`, or `cmd1 \|\| return` |
| `x=$(false; echo hi)` | the subshell does not inherit `-e`; `x` is `hi` (observed) | `shopt -s inherit_errexit` (4.4) in the script, or chain with `&&` |
| `producer \| head -1`, `producer \| grep -q pat` | the producer dies of SIGPIPE, the pipeline's status is 141 under `pipefail` (observed with `yes`) | consume the whole stream (`grep pat >/dev/null`), or accept 141 on purpose: `rc=0; producer \| head -1 \|\| rc=$?` |
| `grep`, `diff`, `cmp`, `test` as plain statements | exit 1 means "no match" / "differs", not "error" | `if grep -q ...`, `grep ... \|\| true`, or `rc=0; grep ... \|\| rc=$?` and test `rc` |
| `${arr[@]}` of an empty array under `-u` | "unbound variable" on bash below 4.4 (observed on 3.2.57), fine on 4.4 and later | `${arr[@]+"${arr[@]}"}` where 3.2 matters |
| `cmd < <(producer)`, `wait` on a process substitution | the producer's status is not the command's | write to a temp file, or `coproc` / `wait` with care |
| `trap ... ERR` | fires where `-e` would, but is not inherited by functions, `$(...)` and subshells | `set -E` (errtrace) |

- **`-u`** — use `"${1:-}"` for optional arguments, `"${VAR:-default}"`, `[[ -v name ]]` to test existence.
- **Library files must not set `-e`, `-u` or `pipefail`**: a sourced file changes the caller's shell. Only the entry script does.
- **When to leave `-e` off on purpose** — a test runner or installer that must run every step and report at the end, a hook that must
  never block its host, a loop that collects failures, any script whose control flow is mostly "try, then decide". Keep
  `set -uo pipefail`, check what matters explicitly (`cmd || die "..."`, `cmd || return`), and say so in the header comment. CRAFT's
  own scripts take this route.
- **Debugging** — `bash -x script` (or `set -x`, `PS4='+ ${BASH_SOURCE[0]}:${LINENO}: '`) shows what ran; `bash -n` only parses and
  proves nothing about the target bash (`references/project-patterns.md`).

## Error handling

- **Fail with a message and a status**: `die "msg" [code]` as in the skeleton; name the file or value that was wrong.
- **Check what can fail**: `cd "$dir" || die "..."` (ShellCheck SC2164), `mkdir -p`, `mktemp`, `read`, `curl --fail`, `cp`. Under
  `-e` an unchecked failure stops the script silently, so a message needs the explicit `||`.
- **Validate input at the edge**: argument count, option values, `[[ -f $f && -r $f ]]`, numeric ranges. Reject, do not repair.
- **Retry loops** — bounded count, growing sleep, the last failure's status; never an endless `until`.
- **Locking** — `mkdir "$lockdir"` is atomic and portable; `flock` is not in macOS's base system. Remove the lock in the `EXIT` trap.
- **Dry-run flags** — one `run()` wrapper that prints or executes a command, not `if dry` around every call.

## Traps, signals, temporary files

```bash
tmpdir=
cleanup() {
  [[ -z $tmpdir ]] || rm -rf -- "$tmpdir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/$PROG.XXXXXX")
```

- **`trap cleanup EXIT`** runs on normal exit, on `exit` inside `die`, on `-e` failures and after `INT` / `TERM` once those traps
  call `exit`. `trap 'exit 130' INT` keeps the conventional status. `SIGKILL` cannot be trapped, so a temp dir can still leak.
- **Set the variable first, the trap next, the resource last** (or initialise `tmpdir=` before the trap, as above): a cleanup
  that runs before the resource exists must be a no-op.
- **`mktemp`** — always with a template for portability (`mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"` works on GNU and on macOS);
  bare `mktemp -d` works on both (observed); skip `-t`, its meaning differs between GNU and BSD. Never `/tmp/name.$$` (predictable). POSIX has no `mktemp`.
  `trap -P EXIT` (5.3) prints the current trap, so a library can append instead of replacing: read it, then set both.
- **One `EXIT` trap per shell**: a second `trap ... EXIT` replaces the first. Collect cleanups in one function that walks an array.
- **Subshells** do not run the parent's traps (the parent's `EXIT` trap fired once, not for `( : )` — observed); set the trap
  inside `( ... )` if it needs one.
- **Atomic writes** — write to a temp file in the target's directory, then `mv` it over the target (same filesystem, so `mv` is a
  rename). Never write a config file in place with `>`.
- **Background jobs** — `cmd & pid=$!`, `wait "$pid"` for its status; kill the job from the `EXIT` trap when the script ends first.

## Pipelines and processes

- **`cmd | while read`** runs the loop in a subshell: variables set inside are lost. Use `while ...; done < <(cmd)` (process
  substitution, bash only), `done < file`, or `shopt -s lastpipe` (4.2; works in scripts, not interactively).
- **Command substitution inside loops** forks per iteration; hoist it or use a built-in expansion.
- **`find` with `xargs`** — `find ... -print0 | xargs -0 cmd` works with BSD and GNU `xargs` (observed on macOS 26).
- **`cd` in a script** — `cd "$dir" || die`; prefer `( cd "$dir" && cmd )` so the caller's directory is kept.
- **Locating the script** — `script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)` (`-P` resolves symlinks in the
  directory; a symlink to the script file itself is not followed). Do not lean on `readlink -f`: it worked on macOS 26 (observed)
  but is not POSIX and a BSD without it fails. `realpath` is a POSIX.1-2024 utility (`/bin/realpath` on macOS 26, observed), so
  guard it with `command -v realpath` on older systems.
- **Timeouts** — `timeout` and `flock` are not in macOS's base system (neither is in `/usr/bin` on macOS 26; Homebrew's coreutils
  adds `timeout` and `gtimeout`); a portable script uses `read -t`, a `wait` loop or does without.

## Code-quality checklist

- [ ] `shellcheck` is clean (no new `# shellcheck disable=` without a reason on the line above) and `shfmt -d` shows no diff.
- [ ] The header sets the options on purpose: `set -euo pipefail`, or `set -uo pipefail` with the reason and explicit checks.
- [ ] Every expansion is quoted; no `ls` parsing, no `eval`, no backticks, no `echo` of data.
- [ ] Every function variable is `local`; no `local x=$(cmd)`; no `((i++))` under `-e`.
- [ ] Everything that can fail is checked or deliberately ignored (`|| true` with a comment).
- [ ] Temp files come from `mktemp` and are removed by one `EXIT` trap; the script is safe to interrupt.
- [ ] `main` is guarded (`BASH_SOURCE[0] == $0`) so tests can source the file; library files set no shell options.
- [ ] Messages on stderr, data on stdout, exit codes 0 / 1 / 2 as documented in `usage`.
- [ ] A script that claims bash 3.2 or POSIX sh was run there (`references/project-patterns.md`).
