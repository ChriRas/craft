# bats-core — Test Patterns, ShellCheck and shfmt

Tests for shell scripts use bats-core 1.14.0 (2026-07-21) with its helper libraries bats-support 0.3.0, bats-assert 2.2.4 and
bats-file 0.4.0; ShellCheck 0.11.0 is the static gate and shfmt 3.14.1 the formatter. The bats examples were read from the
projects' documentation and parsed with ShellCheck 0.11.0, which understands `@test`; **bats and shfmt themselves were not run**
when this pack was written — run a first suite before trusting a detail. `SKILL.md` → `## Existing Projects` covers shunit2,
bash_unit and projects without tests.

## Install and layout

- **Install** — `brew install bats-core`, or `npm install --save-dev bats`, or bats-core as a git submodule. The libraries are
  submodules next to the tests (the tutorial's layout) or installed system-wide and found through `BATS_LIB_PATH`:

```text
test/
  deploy.bats
  test_helper/
    common-setup.bash
    bats-support/       # git submodule: bats-core/bats-support
    bats-assert/        # git submodule: bats-core/bats-assert
  fixtures/
```

- **`load 'test_helper/bats-support/load'`** loads a library relative to the test file (`load` tries `<name>.bash` first, then the exact
  name; the `.bash` lookup is deprecated, so give exact filenames). For a system-wide install, `bats_load_library bats-support` searches
  `BATS_LIB_PATH` (colon-separated) for `bats-support/load.bash`.
- **Shared setup** goes in `test/test_helper/common-setup.bash` as one function the tests call from `setup`:

```bash
# shellcheck shell=bash
_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  PROJECT_ROOT=$(cd -- "$BATS_TEST_DIRNAME/.." >/dev/null 2>&1 && pwd)
  PATH="$PROJECT_ROOT/bin:$PATH"
}
```

  Use `$BATS_TEST_FILENAME` or `$BATS_TEST_DIRNAME`, not `${BASH_SOURCE[0]}` or `$0` (those point at the bats executable or the
  preprocessed file).

## Anatomy of a test file

```bash
#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load 'test_helper/common-setup'
  _common_setup
  cd "$BATS_TEST_TMPDIR" || return 1
  export TMPDIR=$BATS_TEST_TMPDIR   # the script's temp files land here, not in the shared system directory
  printf 'data\n' > in.txt
}

@test "prints usage and exits 0 for --help" {
  run -0 deploy --help
  assert_line --index 0 --partial 'Usage: deploy'
}

@test "exits 2 and names the option for an unknown flag" {
  run -2 --separate-stderr deploy --nope
  assert_equal "$stderr" 'deploy: unknown option: --nope'
}

@test "fails on a missing input file" {
  run ! deploy missing.txt
  assert_output --partial 'not a file: missing.txt'
}

@test "a dry run plans the copy and leaves no work directory behind" {
  run -0 deploy --dry-run in.txt
  assert_output 'would copy in.txt to ./out'
  run ! compgen -G "$BATS_TEST_TMPDIR/deploy.*"
}

@test "arguments after -- are files, not options" {
  : > ./-n
  run -0 deploy -- -n
  assert_output 'copy -n to ./out'
}
```

- **`run`** executes its arguments in a subshell, stores the status in `$status`, stdout and stderr combined in `$output`, the lines
  in `${lines[@]}` (empty lines dropped; `--keep-empty-lines` keeps them) and always returns 0. `run -N cmd` also asserts the status
  is N, `run ! cmd` asserts it is non-zero; `--separate-stderr` fills `$stderr` and `${stderr_lines[@]}`. All `run` options come
  before the command; `--` protects a command that starts with `-`.
- **`bats_require_minimum_version 1.5.0`** (the function itself needs bats 1.7.0 or later) at the top of a file that uses these
  `run` flags: older versions then fail loudly instead of passing for the wrong reason.
- **Every test starts from a clean state**: bats runs the tests of a file one after the other in isolation, each between `setup` and `teardown`.
  `setup_file` / `teardown_file` run once per file (values exported in `setup_file` reach the tests); `setup_suite` /
  `teardown_suite` once per run, defined in a `setup_suite.bash` next to the first `.bats` file.
- **Temporary files** — `$BATS_TEST_TMPDIR` (per test), `$BATS_FILE_TMPDIR` (per file), `$BATS_SUITE_TMPDIR` (per run). bats removes them
  after the run unless `--no-tempdir-cleanup` is given. bats-file adds `temp_make` / `temp_del` for a directory named after the test.
- **`teardown` runs even after a failed test**; `bats::on_failure` (a function you define) runs only on failure, before `teardown` —
  use it to print state that would otherwise be lost.
- **Naming** — test names are sentences about behaviour ("exits 2 and names the option for an unknown flag"), one behaviour per test.
  `skip "reason"` marks a test that cannot run here (a missing tool, the wrong OS) and keeps the reason visible.

## Assertions

bats-assert (needs bats-support) works on what `run` stored:

| Function | Checks |
|---|---|
| `assert_success` / `assert_failure [N]` | `$status` is 0 / non-zero (or exactly N); prints status and output on failure |
| `assert_output 'text'` | `$output` equals the text; `--partial` (`-p`) contains it; `--regexp` (`-e`) matches it; no argument: output is not empty |
| `assert_line [--index N] 'text'` | some line (or line N) equals / `--partial` / `--regexp` |
| `refute_output`, `refute_line` | the negations |
| `assert_stderr`, `assert_stderr_line` | the same for `$stderr` after `--separate-stderr` |
| `assert_equal actual expected`, `assert_regex value pattern` | plain values |

bats-file adds filesystem assertions: `assert_file_exists`, `assert_dir_exists`, `assert_file_executable`, `assert_file_contains`,
`assert_file_empty`, `assert_symlink_to` and their negations. With only `[ ]` and `$output`, a test works too — the failure message
is just worse. A line such as `[ "$output" = "x" ]` is a valid assertion because bats runs a test with `set -e`.

## Testing a script: black box and white box

- **Black box (default)**: `run deploy --flag` through the real entry point, with `PATH`, the working directory and the environment
  set in `setup`. Assert status, stdout, stderr and the effect on the file system. This is what keeps working after a refactor.
- **White box**: source the script and call a function. It needs the guarded `main` (`BASH_SOURCE[0] == $0`,
  `references/project-patterns.md`); without it, sourcing runs the script. `run` executes in a subshell, so state set by the function
  does not survive it: call the function directly, or print its result and assert on `$output`.

```bash
@test "sourcing the script defines main without running it" {
  source "$PROJECT_ROOT/bin/deploy"
  run type -t main
  assert_output 'function'
}
```

- **A script that calls `exit`** kills the test if you source it; test it through `run`. The test that proves cleanup ran (the temp
  directory is gone, the lock released) checks the file system after `run` returns.

## Test doubles for commands

Put a stub first on `PATH` instead of changing the script: the script under test stays exactly what ships.

```bash
@test "the script calls curl with --fail" {
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/curl.calls"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  run -0 fetch-config http://example.invalid/
  assert_equal "$(cat "$BATS_TEST_TMPDIR/curl.calls")" '--fail -- http://example.invalid/'
}
```

- A stub **records its arguments** to a file and **returns what the test needs** (print a fixture, `exit 7` for a failure path).
- A **function** can stand in for a command inside sourced code (`curl() { ...; }`, `export -f curl` for child shells); it does not
  reach a script run through `run` unless exported. A stub on `PATH` does.
- **Never stub what you are testing**, and never let a test reach the network, the real home directory or the user's git config:
  set `HOME="$BATS_TEST_TMPDIR"` and `export GIT_CONFIG_GLOBAL=/dev/null` where it matters.
- **Time and randomness** enter through an argument or variable the script reads (`NOW=${NOW:-$EPOCHSECONDS}`), so a test pins them.

## Gotchas (from the bats-core docs)

- **A negated command does not fail a test**: `! cmd` is exempt from `set -e` unless it is the last line. Use `run ! cmd`.
- **`run` hides a failure**: `run cmd` always succeeds; check `$status` or use `run -0`. When all you need is "it succeeded", call
  the command without `run`.
- **`run cmd1 | cmd2` pipes `run`'s output, not `cmd1`'s**: use `run bats_pipe cmd1 \| cmd2` or `run bash -c '...'`.
- **`[[ ]]` and `(( ))` on bash 3.2 do not fail a test** unless they are the last command (bash below 4.1 ignores `set -e` for them).
  Write `[[ -f $f ]] || false`.
- **A background process keeps bats waiting** because it inherits file descriptor 3: start it with `cmd 3>&-`. Print from a test with
  `echo '# text' >&3` (stdout of a passing test is hidden).
- **Variables declared with `declare` in a `load`ed file are local to `load`**; use plain assignments or `declare -g`.
- **Code outside tests and hooks runs once per test** (each test re-reads the file): keep the file top-level to definitions.
- **Test names in a loop** cannot be created with `@test` — register them with `bats_test_function`.
- **Do not `return 1` to mean true.** Exit 0 is success.

## Running

```bash
bats test/                         # the .bats files directly in test/
bats -r test/                      # recurse
bats test/deploy.bats --filter 'dry run'      # by name (regex)
bats --print-output-on-failure test/          # show $output of failed tests
bats --formatter tap test/                    # TAP; --report-formatter junit --output reports/ for CI
bats --jobs 4 test/                           # parallel: needs GNU parallel or rush; tests must not share files
```

- A run exits 0 when every test passes and 1 otherwise; no tests found is also 1 (`--allow-empty-suite` changes that).
- **Tags** — `# bats test_tags=slow` above a test (or `# bats file_tags=...`), then `--filter-tags slow` or `--filter-tags '!slow'`.
- **`--trace`** prints each command (`set -x`), `--timing` adds durations, `--abort` stops at the first failure, `--errexit` (1.14)
  applies `set -e` to commands inside `run`.
- **`run` and `set -e` in your functions (1.14)** — since bats-core 1.14.0 `run` honours `set -e` inside the functions it calls
  (changelog #1118; earlier versions suppressed it unintentionally, and `--errexit` is the separate flag above). A function under
  test that relied on a failing command not stopping it now stops at the first failure. The changelog's wrapper restores the old
  behaviour for one call: `suppress_errexit() { "$@" || return $?; }`, then `run suppress_errexit my_function`. Pin the bats
  version a suite is written for.
- Run the suite **once per supported bash**: `/bin/bash` on macOS for a 3.2-bound project, a current bash otherwise.

## Tests that prove the tests bite

A test that cannot fail is worse than none. For code that matters, add a mutation check next to the behaviour check: copy the script
into `$BATS_TEST_TMPDIR`, break one line with `sed`, check the mutation applied, and assert that the copy now behaves differently
from the real script — the behaviour test above would fail on it. (The `sed` pattern and the mutant were run in plain bash on 3.2.57
with the skeleton of `references/project-patterns.md`; the bats wrapper was not.)

```bash
@test "mutant: without the missing-file check the behaviour test above would go red" {
  sed 's/\[\[ -f \$f \]\] || die "not a file: \$f"/:/' "$PROJECT_ROOT/bin/deploy" > "$BATS_TEST_TMPDIR/deploy"
  chmod +x "$BATS_TEST_TMPDIR/deploy"
  ! cmp -s "$PROJECT_ROOT/bin/deploy" "$BATS_TEST_TMPDIR/deploy" || fail "the mutation did not apply"
  run -0 "$BATS_TEST_TMPDIR/deploy" missing.txt   # the mutant accepts what the real script rejects
}
```

For a harness without bats the same idea is a list of mutated copies that must go red, plus a legitimate edit that must stay green and a
positive control; write the harness so it fails when a mutation does not apply (the `sed` pattern matched nothing).

## ShellCheck and shfmt as gates

One script runs both on every tracked shell file; CI and the pre-commit hook call it.

```bash
#!/usr/bin/env bash
# scripts/lint — ShellCheck and shfmt over every tracked shell file
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1

files=()
# bin/ and scripts/ may hold Python or Node helpers too: keep only files with a sh or bash shebang there
while IFS= read -r -d '' f; do
  case $f in
  *.sh | *.bash | *.bats) ;;
  *) head -n1 -- "$f" | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)' || continue ;;
  esac
  files+=("$f")
done < <(git ls-files -z -- '*.sh' '*.bash' '*.bats' 'bin/*' 'scripts/*')
((${#files[@]})) || { echo "lint: no shell files" >&2; exit 1; }

rc=0
shellcheck -x "${files[@]}" || rc=1
shfmt -d "${files[@]}" || rc=1
exit "$rc"
```

- **ShellCheck** — `shellcheck file...` exits 0 (clean), 1 (findings), 2 (a file could not be read), 3 and 4 (bad flags). It picks the
  dialect from a `# shellcheck shell=` line, the shebang, or a `.bash` / `.bats` / `.dash` / `.ksh` extension. A repository `.shellcheckrc`:

```ini
shell=bash
external-sources=true
source-path=SCRIPTDIR/../lib
enable=require-double-brackets
```

  `-x` (or `external-sources=true`) follows `source` commands; without it they are not read. `-S warning` hides notes and style
  messages, `-f diff` prints a patch, `-f gcc` one line per finding. Optional checks (`shellcheck --list-optional`) worth knowing:
  `check-set-e-suppressed` (a function in `if` / `&&` runs with `-e` off, SC2310), `check-extra-masked-returns` (a failing command
  inside `$(...)` as an argument, SC2312), `require-variable-braces`, `quote-safe-variables`, `deprecate-which`.
- **Suppress narrowly**: `# shellcheck disable=SC2034 # exported for sourced plugins` on the line above one command, with a reason.
  A file-wide `disable` or a whole-project `.shellcheckrc` exclusion to get a slice through hides the next real finding.
  `disable=SC3000-SC4000` silences every portability warning; prefer `shell=bash` on a file that is bash on purpose.
- **ShellCheck 0.11.0 and what is coming**: the development version adds EditorConfig keys (`shellcheck.shell=bash`) and SC2337
  (`grep -q` in a pipeline under `pipefail`); the released 0.11.0 does neither. Pin the version in CI and read its changelog on an upgrade.
- **shfmt** — `shfmt -d .` prints a diff and exits non-zero when formatting differs (CI); `shfmt -l -w .` rewrites the files. It finds
  shell files by extension and shebang (`--detect=exec` also reads the shebang of executable files with a non-shell extension, `--detect=all` of every regular file). The defaults are tabs and the
  language dialect from the filename: **a `.sh` file is read as POSIX unless its shebang names bash**, so bash syntax in a `.sh` without
  a shebang is a parse error — set `-ln bash`, or `shell_variant = bash` in `.editorconfig` (3.14.1; the development version renames it
  `language_dialect` and still accepts the old name). `-ln bats` formats `.bats` files.
- **Settings live in `.editorconfig`** (`indent_style = space`, `indent_size = 2`, `binary_next_line`, `switch_case_indent` (`case_indent` in the development version),
  `space_redirects`, ...) so editors and CI agree. Giving shfmt any parser or printer flag on the command line switches EditorConfig
  formatting options off, so choose one place. `-i 2 -ci -bn` is close to Google's shell style.
- **shfmt parses**, so `shfmt -p file >/dev/null` is a static syntax check for POSIX and `shfmt file >/dev/null` for bash; it is
  stricter than `bash -n`, and still says nothing about which bash release runs the file.
- **Neither tool runs the code.** They sit next to the tests, not in place of them.

## What to cover

- Each option and its error case; `--help` and a usage error; exit codes as documented.
- The effect on the file system and the absence of leftovers (temp files, lock, partial output) on success, failure and interruption.
- Input at the edges: empty, spaces and newlines in names, a name starting with `-`, a very long argument list, a missing tool.
- Idempotency: running twice gives the same result.
- On the supported bash versions: the suite passes on the floor version and on the newest one.
