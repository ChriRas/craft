---
name: stack-bash
description: CRAFT stack-pack for shell projects written in Bash — scripts, tooling and libraries on bash 5 (quoting, arrays, set -euo pipefail and its pitfalls, traps and temp files), script and library structure, portability to POSIX sh and macOS's /bin/bash 3.2, ShellCheck and shfmt, and bats-core test patterns. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — Bash

The code-near personality layer for a project that is mainly shell — command-line tools, hooks, installers, release and CI
scripts, a library of sourced functions — written for GNU Bash 5, kept clean with ShellCheck and shfmt, and tested with bats-core.
It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`, `/craft:refactor` and `/craft:review` when
`rules.md` declares it in its `## Personality` block. It is a bash pack with a portability section, not a POSIX-first pack; zsh, fish
and PowerShell are out of scope, and a program with real data structures or concurrency belongs in a language of its own.
Project-specific conventions — the supported bash floor, exact commands, paths — live in the project's own `rules.md`, not here.
Versions and tool behaviour below were verified on 2026-11-11 (see `## Sources`); a newer release may have moved since.

## Stack

- **Language** — GNU Bash 5.3 (released 2025-07-30; patch level 5.3.20, 2026-09-14). New in 5.3: `${ cmd; }` command substitution
  without a fork, `trap -P`, `source -p`, `GLOBSORT`, `BASH_MONOSECONDS`. Idioms: `set -euo pipefail` with its pitfalls known,
  quoted expansions, arrays, `local` everywhere, `printf` over `echo`, a guarded `main`, an `EXIT` trap for cleanup.
- **Portability** — macOS 26.5.2 still ships `/bin/bash` 3.2.57, and its `/bin/sh` is a launcher for the shell `/private/var/select/sh` names (by default bash 3.2.57 in POSIX mode). POSIX.1-2024
  (Issue 8) defines `sh`, including `set -o pipefail` and `$'...'`; ShellCheck 0.11.0 still warns on both under `-s sh` (SC3040, SC3003). A script states its floor: POSIX sh, bash 3.2, 4.4 or 5.
- **Quality** — ShellCheck 0.11.0 (2025-08-03) for analysis, shfmt 3.14.1 (2026-09-06) for formatting, both as CI gates.
- **Tests** — bats-core 1.14.0 with bats-support 0.3.0, bats-assert 2.2.4 and bats-file 0.4.0 (see `references/test-patterns.md`).

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read the script headers, `.shellcheckrc`, `.editorconfig`, the
`test/` directory and the CI configuration first, and follow what they declare:

- **`set -uo pipefail` with explicit checks instead of `-euo`** — headers without `-e`, a trail of `cmd || exit 1`, `|| return`,
  `|| die`; typical of hooks and installers that must keep going (CRAFT's own scripts). Keep the style: add an explicit check for
  every command that can fail, never add `set -e` to such a file (it changes every `||`-less line), say in the header comment why.
- **POSIX-sh-only scripts** — `#!/bin/sh`, `# shellcheck shell=sh`, `shellcheck -s sh` in CI, dash or BusyBox as the target. No arrays,
  `[[ ]]`, `local`, `${v//}` or `mapfile`; run `dash script.sh` and `shellcheck -s sh` (macOS's `/bin/sh` is bash 3.2 and accepts bashisms).
- **Bash-3.2-bound scripts** — `#!/bin/bash` on a Mac, hooks and tools run by other programs with a minimal `PATH`, a comment or
  README line naming 3.2. Use the 3.2 table in `references/project-patterns.md` and run the result under `/bin/bash`, failing on any
  error text; `bash -n` and ShellCheck do not know the bash version.
- **shunit2 or bash_unit instead of bats-core** — shunit2: test files that define `testSomething` functions (`setUp`, `tearDown`,
  `assertEquals`) and source `shunit2` last, run with `bash test/foo_test.sh`; bash_unit: `test_something` functions (`setup`,
  `teardown`, `assert_equals`) run with `bash_unit tests/test_*`. Extend the suite in its own framework and style, add no second one.
- **No tests, or plain assertion scripts** — a `test.sh` that runs scripts and compares output. Follow it; a slice that needs a test
  adds to that harness. Introduce bats-core only when the slice is about the test setup itself.
- **No shfmt, or a house style** — tabs or four spaces, no `.editorconfig`, `shfmt` absent from CI. Match the neighbouring files, do
  not reformat whole files, run shfmt (`-d`) only when the project does. If `.editorconfig` exists, shfmt reads it; any parser or printer flag (`-i`, `-ln`, `-ci`, `-bn`) turns that off, `-d` / `-l` / `-w` do not.
- **No ShellCheck, or an old one** — findings in untouched code are not yours to fix; new code is clean. Check `shellcheck --version`
  before using a check newer than the project's.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — script shape, quoting and expansion, arrays and functions, `set -euo pipefail` and every
  place it does not apply, error handling, traps and temp files, pipelines, the code-quality checklist.
- `references/project-patterns.md` — project layout, a complete entry script, arguments, sourced libraries, calling other programs
  (BSD versus GNU userland), portability: POSIX sh and macOS `/bin/bash` 3.2, version guards.
- `references/test-patterns.md` — bats-core layout and anatomy, `run` and assertions, stubs, gotchas, running, mutation self-tests,
  ShellCheck and shfmt as gates.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Project and tooling — directory layout, `.shellcheckrc`, `.editorconfig`, the lint script, the test directory with bats and its helpers.
2. The contract — `usage` text, options, exit codes, what goes to stdout and stderr; written first, tested first.
3. Libraries — pure functions that take their inputs as arguments and set no shell options, each with a bats file.
4. Adapters — calls to external programs, the file system, the network and the clock behind small functions that a test can stub.
5. Entry scripts — option parsing, `main`, traps and cleanup, mapping failures to exit codes.
6. Tests — alongside each layer or right after; `shellcheck`, `shfmt -d` and `bats` pass before a layer counts as done.

## Anti-Patterns

- An unquoted expansion, `$*`, `ls` parsed in a `for`, `eval`, backticks, `echo` of data, or `cd` without a check.
- `local x=$(cmd)`, `export X=$(cmd)` or `((i++))` under `set -e`; `set -e` trusted inside `if f`, `f &&` or `f ||`, in a `$(...)`, or on `[[ ]] && x` as a last line.
- `set -euo pipefail` in a sourced library, or a library that prints, exits or does work when sourced.
- A `cmd | while read` loop whose variables are used afterwards; a producer piped into `head` or `grep -q` under `pipefail`.
- A temp file named `/tmp/name.$$`, no cleanup trap, several `trap ... EXIT` replacing each other, a config file written in place.
- `declare -A`, `mapfile`, `${v,,}` or `[[ -v ]]` in a script that claims bash 3.2, or a bashism under `#!/bin/sh`.
- Portability tested with `bash -n`, `BASH_COMPAT` or `/bin/sh` on a Mac, instead of a real run on the target.
- GNU-only flags or tools missing from macOS's base system (`sed -i`, `date -d`, `stat -c`, `grep -P`, `timeout`, `flock`) in a script that must run on macOS, and `readlink -f` where it must run on any POSIX system (not POSIX; use `cd -P` / `pwd -P` or a guarded `realpath`).
- Tests that call the real network, `$HOME` or the user's git config, share files between tests, or never fail (`run` without a check).
- A blanket `# shellcheck disable` at the top of a file, a rule switched off project-wide to pass a slice, or a ShellCheck/shfmt gate that checks only some files.

## Sources

> As of: 2026-11-11 · Basis: research

- GNU Bash releases, patches and manual — https://ftp.gnu.org/gnu/bash/, https://ftp.gnu.org/gnu/bash/bash-5.3-patches/, https://www.gnu.org/software/bash/manual/bash.html (Bash 5.3 released 2025-07-30, patches through bash53-020 on 2026-09-14, no 5.4 tarball; the `set -e` rules)
- Bash NEWS and CHANGES — https://tiswww.case.edu/php/chet/bash/NEWS, https://tiswww.case.edu/php/chet/bash/CHANGES (the release that introduced each feature: 4.0 `mapfile` and associative arrays, 4.1 `set -e` for `[[` / `((`, 4.2 `[[ -v ]]` and `lastpipe`, 4.3 namerefs, 4.4 `inherit_errexit` and empty arrays under `set -u`, 5.0 `EPOCHSECONDS`, 5.3 `${ cmd; }` and `trap -P`)
- POSIX.1-2024 (Issue 8), Shell Command Language and `set` — https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html, https://pubs.opengroup.org/onlinepubs/9799919799/utilities/set.html (`pipefail`, dollar-single-quotes; `local`, arrays and `[[ ]]` are not in the chapter)
- ShellCheck: releases, changelog, manual, wiki — https://github.com/koalaman/shellcheck/releases, https://github.com/koalaman/shellcheck/blob/master/CHANGELOG.md, https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md, https://www.shellcheck.net/wiki/SC2155 (0.11.0 of 2025-08-03, dialects, exit codes, directives, `.shellcheckrc`, optional checks, the development version's EditorConfig keys and SC2337)
- shfmt (mvdan/sh): releases, changelog, manual — https://github.com/mvdan/sh/releases, https://github.com/mvdan/sh/blob/master/CHANGELOG.md, https://github.com/mvdan/sh/blob/v3.14.1/cmd/shfmt/shfmt.1.scd (3.14.1 of 2026-09-06, flags, dialect detection, EditorConfig keys `shell_variant` and `switch_case_indent`, `--detect`, `shfmt -i 2 -ci -bn` as Google's style; the development manual renames the two keys)
- bats-core: releases, docs, support matrix — https://github.com/bats-core/bats-core/releases, https://bats-core.readthedocs.io/en/stable/, https://github.com/bats-core/bats-core/blob/master/docs/source/support-matrix.rst (1.14.0 of 2026-07-21, `run`, `setup` / `teardown`, tags, gotchas, bash 3.2.57 in the support matrix)
- bats-support, bats-assert, bats-file — https://github.com/bats-core/bats-support, https://github.com/bats-core/bats-assert, https://github.com/bats-core/bats-file (0.3.0 of 2022-03-04, 2.2.4 of 2025-10-14, 0.4.0 of 2023-08-23; the assertion API)
- shunit2 and bash_unit — https://github.com/kward/shunit2, https://github.com/bash-unit/bash_unit (shunit2 2.1.8 of 2020-03-29, bash_unit 2.3.3 of 2025-08-28; the commands named in `## Existing Projects`)
- dash (upstream) — https://git.kernel.org/pub/scm/utils/dash/dash.git/log/?qt=grep&q=pipefail (the commit "jobs: Implement pipefail option", 2024-04-05; 0.5.13 tags exist)
- Google Shell Style Guide — https://google.github.io/styleguide/shellguide.html (when shell is the right tool, naming, `main`)
- Hands-on check on 2026-11-11 (macOS 26.5.2, bash 5.3.20 and `/bin/bash` 3.2.57, ShellCheck 0.11.0; observed, not documented) — https://tiswww.case.edu/php/chet/bash/NEWS (every construct in the 3.2 table, the `set -e` table, the entry-script skeleton and the version guard were run on both bashes; ShellCheck was run on the examples and on a `.bats` file; shfmt and bats-core were not run, only read)
