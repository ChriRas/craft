# Slice 030 — normalize-readonly-guard-paths

> Completed: 2026-07-12
> Commits: 4f4d76d..47fe3cc (branch only — direct-to-main)

## What

The read-only context guard (`hooks/readonly-context-guard.sh`, shipped in slice-029) now
decides deny/allow on the **canonical** form of a path rather than its literal spelling. Before
this slice a single `..` segment defeated it in both directions: `commands/../research/x.md` was
*allowed* (the string did not start with the protected prefix — the guard was one traversal
segment away from being bypassed entirely), while the legitimate write `research/../commands/x.md`
was *denied* (the string did start with the prefix, though the path resolves elsewhere). Both now
decide correctly. The same normalization is applied to the read-only **roots**, so a connected
project declared in `rules.md` with a `..` or `~/` segment is guarded under exactly the canonical
path the sync helper records in `additionalDirectories`.

## Why

- **A guard that is one `..` away from being bypassed is not a guard.** slice-029 gave the
  read-only context sources teeth; a literal string-prefix comparison meant those teeth could be
  stepped around by any agent (or subagent) that happened to emit a non-canonical path. The
  false-deny half was the milder but more visible failure: legitimate writes blocked for no
  reason the user could see.
- **The guard and the sync helper must agree on what a declared root *is*.** They are two halves
  of one contract: the helper records a path as readable in `additionalDirectories`, the guard
  blocks writes under it. Any divergence in how they resolve a declared bullet produces the
  precise hole slice-029 set out to close — a path that is readable but unguarded.

## Decisions

- **Normalization is pure-lexical, not filesystem-based** — no `realpath -e`, no symlink
  resolution, no existence check. *Why not* a filesystem-based resolver: the guard fires on a
  *Write* whose target legitimately may not exist yet, so a resolver that requires existence
  would have to guess. Textual resolution of `.`, `..` and `//` is both correct and portable
  here, and matches Claude's canonical absolute paths.
- **Divergence closed by "aligned implementations + cross-check test", not one shared
  normalizer** (user decision, 2026-07-09) — the guard gets its own pure-Bash `normalize_path`
  reproducing `os.path.normpath`; the helper keeps its working python3 `normpath`; the harness
  asserts the two agree on a shared fixture set. *Why not* the slice-029 reviewer's literal
  "share one normalizer": the guard is a hot PreToolUse hook that must stay dependency-light
  (`jq`-only, fail-open) — forcing python3 into it, or rewriting the helper's parser into Bash
  to share a library, is more churn and arguably worsens the helper. Drift is caught by a test
  rather than prevented structurally, which is proportionate for a soft guard.
- **`normalize_path` implements `normpath` over the *whole* input domain, not a "realistic
  subset"** (Phase-8 correction) — including the POSIX double-slash rule (exactly two leading
  slashes preserved, three or more collapsed). *Why not* the original "no leading-`//` quirk"
  carve-out: a differential fuzz showed the only two divergences in the entire input space were
  leading-`//` and the empty string, and *neither was in the agreement fixture set* — so the
  tripwire protecting the decision above could not have fired on either known deviation. A
  caveat in a comment is not an assertion.
- **Tilde expansion is gated to the `~/` form on both sides** (Phase-8 correction) — the guard's
  `${decl/#\~/$HOME}` mangled `~alice/ref` into `/Users/craschkealice/ref` while the helper's
  `os.path.expanduser` resolved it correctly, so a `~user` bullet would have been recorded
  readable by the helper while the guard watched a path that does not exist. *Why not* teach the
  guard to resolve `~user`: pure Bash cannot, so the only way to keep the two sides aligned is
  for neither to expand it. `rules.md` declares absolute paths anyway.
- **The guard's Bash-write gap stays out of scope** — the guard covers only the structured file
  tools (`Write`/`Edit`/`NotebookEdit`), not Bash-based writes (`echo > research/x`). Unchanged
  by this slice; carried forward as a follow-up.
- **Dogfooding find (workflow gap, promoted to the roadmap as B1)** — a project whose `rules.md`
  drops Phase 7, as CRAFT's own does, can never reach `/craft:review`'s Phase-8 mode:
  `/craft:test` sets `Status: review`, `/craft:recap` only advances to `refactoring`, and
  `reviewing` is set exclusively by `/craft:refactor`. With no Phase 7 nothing performs that
  promotion, so `/craft:review` falls into advisory mode and Commit is never gated. Worked around
  here by setting `Status: reviewing` by hand after human confirmation.

## Commits

- `4f4d76d` — fix(hooks): decide the read-only guard on lexically normalized paths
- `093684a` — test(scripts): cover path traversal and guard<->helper normalizer agreement
- `e175213` — docs: surface the read-only context harness in CLAUDE.md and rules.md
- `47fe3cc` — chore(plans): bump slice counter to 31

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review. Each is a candidate for a future slice.

- **Bash-write gap (inherited from slice-029, still open).** The guard denies only
  `Write`/`Edit`/`NotebookEdit`. A Bash-based write (`echo > research/x`, `sed -i`, `cp`) reaches
  the read-only sources unimpeded. Closing it means guarding the `Bash` tool — a different and
  larger problem (parsing arbitrary shell for write intent), deliberately not attempted here.
- **Phase-8 unreachable when Phase 7 is dropped** — see roadmap **B1**. Found while running this
  very slice through the CRAFT loop.

## Phase-8 Review Record

Reviewed by the `code-reviewer` subagent (fresh context, opus): **0 Heavy, 5 Light** — no
Commit-blocking finding, and no silent revocation of any prior decision. All five were local
edits and all five were resolved in-phase (the fifth — documenting the harness in `CLAUDE.md` +
`rules.md` — after explicit human confirmation, since those are durable knowledge). The reviewer's
differential fuzz of `normalize_path` against `os.path.normpath` (35 inputs, bash 5.3 *and* macOS
stock bash 3.2) is what surfaced the two divergences the fixture set was blind to; it also
verified the `--normalize` diagnostic mode cannot fire in production by checking the hook's
registration in `hooks/hooks.json` (registered with no argv).

Harness: **43/43 green** under bash 5.3 and bash 3.2 (was 33/33 pre-review). `claude plugin
validate` ✔.
