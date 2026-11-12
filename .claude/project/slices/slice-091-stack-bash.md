# Slice 091 — stack-bash

> Completed: 2026-11-12
> Commits: e965731..d4a5557 (on epic-006-stack-packs, no PR) · epic-006 entry `stack-bash`

## What

The `stack-bash` stack-pack: a plugin-shipped pack for shell projects written in Bash. `skills/stack-bash/SKILL.md` (99 lines) carries the Stack
(Bash 5.3, macOS `/bin/bash` 3.2.57, POSIX.1-2024, ShellCheck 0.11.0, shfmt 3.14.1, bats-core 1.14.0), seven `## Existing Projects` entries,
the Build Order, the Anti-Patterns and eleven dated https sources (`Basis: research`, as of 2026-11-11). Three references hold the depth:
code-quality standards with a table of every place `set -e` does not apply, project patterns with a complete entry script and the
POSIX / macOS 3.2 portability tables, and test patterns for bats-core plus ShellCheck and shfmt as gates. The docs badge and counts, the Tier-2
card (DE/EN), the README lines and the CHANGELOG name the new pack.

## Why

A project that declares `Stack-Pack: stack-bash` (the onboard heuristic already proposes it) got the "declared but not found" warning; now the
code-near phases load a researched pack. The user's decisions shaped it: `set -euo pipefail` as the default header with its pitfalls spelled
out and CRAFT's own `set -uo pipefail` style named as the alternative, shfmt next to ShellCheck, and portability to POSIX sh and macOS 3.2
as a section rather than a POSIX-first pack. The claims that matter most were run on bash 5.3.20 and 3.2.57, not just read.

## Walk-through

1. Research against primary sources: GNU Bash FTP listing, manual and NEWS/CHANGES (feature-by-release), the POSIX.1-2024 shell chapter,
   ShellCheck's changelog and manual, shfmt's manual and changelog, bats-core 1.14.0's docs and the helper libraries' READMEs (fetched and read).
2. Hands-on checks with the local bash 5.3.20 and `/bin/bash` 3.2.57 and ShellCheck 0.11.0: a feature matrix for 3.2, the `set -e` pitfalls,
   the entry-script skeleton (all paths), the version guard and the `.bats` examples parsed. bats and shfmt were not run.
3. `SKILL.md` from the template, then the three references (181, 233 and 283 lines).
4. Wiring: `docs/index.html` (skills badge 14 to 15, inventory 9 packs, Tier-2 card, two stack-pack lists), `README.md`, `CHANGELOG.md`.
5. `bash scripts/test-stack-packs.sh` (204 contract checks green for the whole tree, 44 of 44 self-test checks: 39 mutations red, 3 edits
   green, positive control), `bash scripts/test-docs-site.sh` GREEN and `claude plugin validate .` passed; Phase 5 verified by `verify-run.sh`, 4 of 4 checks.
6. Review loop-back (round 2 to Phase 4): the bats-core 1.14 `run` / `set -e` behaviour (changelog #1118, wrapper from the changelog), a correct
   canonical-path form (`cd -P` / `pwd -P`, POSIX.1-2024 `realpath`, observed on macOS 26), and the `coproc` row of the 3.2 table (`coproc cmd` is
   `command not found` and the script carries on; only `coproc NAME { … }` is a syntax error, reproduced on 3.2.57); verified again, round 3 of the evidence.
   Review round 3 (the final one) held every earlier finding and fixed two Light ones in-phase (the coproc row under `set -e`, a `readlink -f`
   bullet that contradicted the references); the full harnesses ran green again at the commit.

## Decisions

- **Scope from epic-006 (user):** bash ≥ 5, ShellCheck, bats-core; POSIX sh as a section, not a POSIX-first pack.
- **Error handling: `set -euo pipefail` as the default, with its pitfalls (user, 2026-11-09)** — when `-e` does not fire
  (conditions, `||` / `&&` chains, subshells, command substitution) and when to leave it off deliberately. CRAFT's own
  scripts use `set -uo pipefail` with explicit checks instead; the pack names that as the alternative, not the default.
- **Formatter: shfmt (user)**, next to ShellCheck for analysis.
- **Portability: POSIX sh and macOS `/bin/bash` 3.2 (user)** — which bash-4/5 constructs break there and how to check
  it. Taken from CRAFT's own hook experience (rules.md: `bash -n` is no evidence; a real 3.2 run is). What macOS ships
  today is verified in the build.
- **Depends on slice-083 only (user).** The epic's sequential order (shared docs lines) lands it last.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: `set -uo pipefail` with explicit checks instead of `-euo`, POSIX-sh-only or bash-3.2-bound scripts, shunit2 / bash_unit or no tests instead of bats-core, no shfmt. The rule itself (the project's toolchain wins, never migrate unasked) is the baseline's, not repeated here.
- **Build findings worth the content review (slice-builder, 2026-11-11).** Hands-on on bash 5.3.20 and `/bin/bash` 3.2.57 (macOS 26.5.2): `declare -A` on 3.2 prints a message but carries on without `-e` (under `set -e` it stops with status 2, review R2-1), writing an ordinary array's index 0 (a silent wrong result); `((i++))` and a failing `[[ ]]` stop a `set -e` script on 5.3 but not on 3.2; `local x=$(false)` masks the status; `x=$(false; echo hi)` continues without `inherit_errexit`; `yes | grep -q y` is 141 under `pipefail`; a version guard works only as its own top-level command (with `|&` in the same function, 3.2 dies at parse time); `BASH_COMPAT=32` keeps `mapfile` and `declare -A`; ShellCheck `shell=bash` does not flag bash 4 constructs; macOS `/bin/sh` is bash 3.2.57 and accepts bashisms. Not run (execution of downloaded code was denied by the permission classifier / tool not installed): bats-core and shfmt - their sections rest on the documentation and on ShellCheck parsing the `.bats` examples, and the pack says so. ShellCheck 0.11.0's changelog and manual on master differ (EditorConfig keys, SC2337 are unreleased) - the pack names that.
- **Phase 5 content review (for the user).** What to read: `skills/stack-bash/SKILL.md` (Stack, 7 Existing Projects entries, Build Order, Anti-Patterns) and its `## Sources` (11 lines, all https, dated 2026-11-11); the `set -euo pipefail` table in `references/code-quality-standards.md`; the 3.2 table and version-guard in `references/project-patterns.md`; the gate section in `references/test-patterns.md`. Decide: is `set -euo pipefail` the right default header as written, and are the shfmt/bats-core sections acceptable as documentation-based.
- Phase 7 skipped (project rule)
- **Review round 2 → loop-back to Phase 4** (2026-11-12) — three earlier-round lines left open at the fix cap (R1-9, R1-12, R1-13, Light/Local) routed to Phase 4; route chosen by the user. Round 3 is the final round (ROUND_CAP 3).

## Commits

- `e965731` — feat(skills): add the stack-bash pack
- `d4a5557` — docs: wire stack-bash into the docs site, README and changelog
