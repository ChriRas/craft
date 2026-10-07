# CRAFT

CRAFT is a Claude Code plugin — *Coding with Rules, Autonomy, Feedback, Tests*. This
repository is the plugin's own source, and it dogfoods CRAFT: its development runs
through the CRAFT workflow.

## Project Knowledge

- [`.claude/project/intent.md`](./.claude/project/intent.md) — Vision, goals, architectural decisions.
- [`.claude/project/rules.md`](./.claude/project/rules.md) — Stack, conventions, deployment, tabus.
- [`.claude/project/slices/`](./.claude/project/slices/) — Archived completed slices (Decision Log).

## Design Records

- [`brainstorm-decisions.md`](./brainstorm-decisions.md) — the full decision log (D1–D38).
- [`plugin-architecture.md`](./plugin-architecture.md) — the build blueprint.
- [`README.md`](./README.md) — plugin overview and command reference.

## Active Work

- [`.claude/plans/`](./.claude/plans/) — currently active slice plans (ephemeral; deleted on Phase 8 cleanup).

## Common Commands

```bash
# Validate the plugin manifest + asset structure
claude plugin validate .

# Read-only context guard + sync helper — self-contained Bash harness. It also
# asserts that the guard's normalize_path and the helper's os.path.normpath agree,
# which is the only thing keeping the two implementations from drifting. It also asserts that this
# helper and scripts/ensure-worktree-trust.sh take the settings file's GITIGNORED= verdict from
# scripts/ensure-gitignore.sh and never write .gitignore themselves; the verdict covers the repository-root
# .claude/settings.local.json (the file they write), also in a project that sits in a subdirectory of its
# repository, and execute.md's GITIGNORED=no line is pinned to name that file. Keep green.
bash scripts/test-readonly-context.sh

# Workflow phase-transition graph — the Status graph declared in skills/workflow/SKILL.md
# (## Phase Transition Rules) must stay closed under both Phase-7 configurations, the
# commands' <!-- craft:writes --> / <!-- craft:reads --> markers must match the table in
# BOTH directions, and /craft:continue must route each status to the graph's consumer.
# The markers are the contract — prose is deliberately NOT checked, because a grep cannot
# tell a prescription from a prohibition. Mark any new Status write, or the graph goes
# blind. Run after touching any command's Status handling. Keep green.
bash scripts/test-workflow-status-graph.sh

# Docs-site consistency — docs/index.html (the bilingual GitHub Pages site) must stay
# in sync with the plugin surface: version badge == plugin.json, asset counts ==
# directory listings, EN/DE parity, anchors, tag balance. This is the staleness
# detector for the published docs. The editorial contract and regeneration guide live
# in .claude/skills/docs-site/SKILL.md. Run after touching docs/ or any plugin asset.
# Keep green.
bash scripts/test-docs-site.sh

# Plugin cache drift helper — scripts/check-plugin-cache-drift.sh decides whether the
# running plugin (the installed cache copy) matches this working tree, by content: the
# version cannot tell, it stays the same while the repo changes. /craft:prime step 5c
# reports it. Covers in-sync / diverged (modified, added, removed) / not-dev-repo /
# unknown, and that docs-only or gitignored edits raise no false alarm. Keep green.
bash scripts/test-plugin-cache-drift.sh

# Toolchain check — scripts/check-toolchain.sh reports bash (>= 5.0, one constant) and python3
# with an OS-aware install command (brew / apt / dnf / yum / pacman / apk / zypper / Windows), and
# compares the bash the SessionStart hook recorded in .claude/plans/.hook-env. /craft:prime runs
# it in pre-flight. The harness drives every platform via test-only overrides and runs the hook
# under /bin/bash (3.2 on macOS) — hooks/, this helper, the handoff-marker helper the hook calls and the
# review-findings parser that helper calls must stay bash-3.2-compatible. It also pins prime's hook-bash line
# (informational `·`, never `⚠`) and the status-graph harness's guard (stops only for a too-old bash, never for
# a missing python3). Keep green.
bash scripts/test-toolchain-check.sh

# Local-state gitignore helper — scripts/ensure-gitignore.sh decides, via git check-ignore, whether
# the project's own .gitignore files cover CRAFT's local state (.primed, .hook-env, .execute.lock,
# .closed/, settings.local.json, .craft/) and appends the missing paths to one "# CRAFT local state" block.
# /craft:onboard applies it, /craft:prime step 4f offers it. Covers broader rules, a project negation
# (reads negated, never appended — a negated directory is the pinned known limit), global excludes
# (never coverage), idempotency, conflict restore, and a /bin/bash 3.2 run. Keep green.
bash scripts/test-gitignore-sync.sh

# Handoff marker lifecycle — scripts/handoff-marker-state.sh decides whether a worktree's
# .craft/handoff.md is still live: the slice plan in that worktree is the truth, and each marker status
# pairs with one plan status and, through the marker's Episode:, with one episode of it — the plan's
# Paused-since / Blocked-since stamp or its review round (tables in skills/workflow/SKILL.md; the harness
# fails when they disagree), so a re-entered status never revives an old marker. The SessionStart hook,
# /craft:worktree-status, /craft:execute and slice-builder count only LIVE markers; slice-builder renames a
# stale one; /craft:continue's resume moves a plan off paused. Covers the full pairing matrix, the episode
# matrix (resume, a later pause, a later block, a new review round, malformed episodes, legacy markers), doubt-means-live, --resolve/--retry,
# the hook's fail-open path, the pinned writer and reader sets (every writer names Episode: and the pause
# record; /craft:abort and /craft:worktree-clean show a live marker before removal) and /bin/bash 3.2 runs.
# Keep green.
bash scripts/test-handoff-marker-state.sh

# Review findings record — scripts/review-findings-state.sh is the one parser of a slice plan's
# ## Review Findings: rounds, finding IDs (R<round>-<n>), the resolution (the last ' · ' field) and
# which lines are open. /craft:review Steps 6/7 and its Subagent-Mode gate, /craft:commit Step 5
# (follow-ups) and scripts/handoff-marker-state.sh (a review episode, B11) call it. It also derives the ping-pong
# breaker (slice-052) — TRIP= / REOPEN= / ROUND_CAP= (a `- note · extra round granted` line raises the cap) — which
# /craft:review Pre-flight step 4 (the round cap) and Step 9 (the autopilot breaker) read; nothing stores a counter.
# Covers legacy records, every resolution value (incl. accepted → known limit, archived via --followups), the quoted-value
# false positive, malformed-means-open, advisory rounds, --followups, the Step-6 agreement, the breaker (first reopen of a
# looped-back line, round cap, answered reopens, doubt, grants) and bash 3.2. Keep green.
bash scripts/test-review-findings-state.sh

# Execute re-run state — scripts/execute-resume-state.sh decides what a /craft:execute re-run finds per
# slice: create, reuse (an existing worktree), skip (merged by a merge commit, or archived), resume (the
# sequential slice an earlier run left open), held (paused/blocked) or conflict (a leftover branch,
# worktree or path, a dirty tree or wrong branch nothing accounts for). /craft:execute step 1c calls it
# before anything is created. Covers real git fixtures, the ancestor trap, both landings, an autopilot run's
# epic branch passed as the trunk (slice-049 — no helper change, the sequential rows answer it), and that
# commands/execute.md handles every ACTION value. Since slice-067 (B15) the plan guard `plan_not_committed` is
# epic-line only: a slice's plan is handed into its worktree (plan-roundtrip.sh, below), so a slice whose plan is
# untracked, ignored or edited since its commit reads `create`. Also covers scripts/tree-dirt-state.sh: CRAFT's plans,
# counters and local state are no dirt for /craft:execute A3, /craft:commit and the re-run, and those
# commands judge the tree only through it. Since slice-066 (B20) it also runs `git worktree remove` for real on an
# epic worktree holding step 9's checkpoint record: the record, kept as state and self-ignored through its nested
# .craft/.gitignore (also under a project's `!.craft/` negation), lets the removal succeed, while a bare record
# still blocks it and any other file under .craft/ still is dirt; execute.md step 9 is pinned to those two lines.
# Its `--scope slice-worktree` (slice-067) also counts neither `.craft/` nor any local-state path of that list at the
# worktree root (the seeded `.claude/plans/.primed`, a session's `.hook-env`) — in a subdirectory project too — and is
# what /craft:execute step 6 commits from. Keep green.
bash scripts/test-execute-resume-state.sh

# Plan round trip — scripts/plan-roundtrip.sh (slice-067, B15) is parallel worktree mode's plan hand-in (`in`, step 5),
# read-back (`back`, step 6, only at `committing`, after step 6 committed the slice's work on its branch) and release
# (`release`, /craft:commit Step 7, before `git worktree remove`). A record in <worktree>/.craft/plan-roundtrip keeps any
# copy nobody read from being overwritten (a conflict, never a write) and hides itself through <worktree>/.craft/.gitignore
# (the pattern of slice-066's checkpoint record); no removal command lives in the helper (D34). Covers real worktree
# fixtures from the hand-in to a landed `git merge --no-ff` and a removed worktree — in a root project with the CRAFT
# block, one without a `.craft/` ignore, one without any .gitignore and a subdirectory project with and without the
# block, the last three after a planted Phase-5 handoff (a resolved marker and `.hook-env` at the worktree root, which
# `release` hides; on a conflict it hides nothing) — the premise cases (a bare record, a bare `.closed/` copy, a bare
# `.primed` seed and a resolved marker each block `git worktree remove`), the hand-in on a reused worktree without a
# record, and the pinned sites in execute.md, commit.md and slice-builder.md. Keep green.
bash scripts/test-plan-roundtrip.sh

# Tracked plan landing — scripts/plan-landing.sh takes a tracked slice plan off the trunk under
# pull-request + Protected-main: `close` commits the plan's removal on the PR branch (by pathspec — a
# `git rm --cached` + pathspec commit would re-track it) and `sync` drops the local plan copy before it
# checks out and fast-forwards the merged trunk, putting the copy back when that fails. /craft:commit
# Step 6 (first pass) and Step 7 (second pass) call it. Covers a bare-origin fixture with a simulated
# merge, R1-2/R2-6 of slice-039, the rollback paths, a fresh clone reading the slice as landed, and
# that commands/commit.md calls both. Keep green.
bash scripts/test-plan-landing.sh

# Epic entry link — scripts/epic-entry-link.sh defines an epic's decomposition entry format once and links
# an entry to its slice-ID: /craft:plan offers `candidates` and runs `link` after it allocates the ID, and
# /craft:execute A6 resolves entries only through `resolve` (plan | landed | missing | ambiguous | unlinked),
# so an epic re-run still finds a slice whose plan is gone. Covers idempotent links, a live ID never overwritten
# while a dead one (aborted slice) is relinked, target IDs that do not exist or sit in another epic, ambiguous /
# missing entries, CRLF / indented and nested fences / ignored list items / the section boundary, byte-exact
# in-place writes that never report a failed write as success, a landed slice read as archived by
# execute-resume-state fed from `resolve`, and that plan.md / execute.md (every state) / epic.md / the epic
# template use it. Keep green.
bash scripts/test-epic-entry-link.sh

# Example regions — scripts/example-regions.sh is the ONE answer to "is this line an example
# rather than content?", shared by epic-entry-link.sh, review-findings-state.sh,
# test-workflow-status-graph.sh, test-model-enum.sh and verify-run.sh. Four scripts used to decide it separately
# with naive parity toggles and demonstrably disagreed. It PARSES the constructs instead of
# counting them: fenced blocks (nested, indented, blockquoted, unclosed), multi-line HTML comment
# blocks, and <pre> in the one binding site that is not Markdown (docs/index.html). The CALLER
# passes the mode; the helper takes it as an argument and exits 2 without one. A SINGLE-LINE HTML comment is never an example, because CRAFT's markers ARE HTML comments.
# `blank` keeps the line count so callers keep their line numbers; `report` names an unclosed
# fence, which is how a harness learns it is checking fewer things than it thinks. bash 3.2 and no
# python3, because review-findings-state.sh reaches it from the SessionStart hook and that path
# must not gain a dependency that can be missing; a consumer without the helper FAILS rather than
# answering. The case table is the contract and was written before the helper existed. Keep green.
bash scripts/test-example-regions.sh

# Model enum + capability tiers — the allowed model values are DECLARED once, in model-defaults.md
# under a `craft:model-enum canonical` marker, and every other site that names them carries the same
# marker and is compared against that declaration in both directions, with an expected binding-site count per file, and a tree-wide scan
# so a marked file missing from that list fails instead of going unchecked. This comment names no
# values on purpose, and the harness carries no copy of the value LIST — its self-test fixtures are
# built from the canonical line at run time, so adding a value to the FRONTMATTER enum is an edit to
# the seven marked lines a human reads (in six files) and nothing else; adding a SPAWN-REACHABLE
# value is that line plus SPAWN_EXPECTED_VALUES in the harness, which fails loudly and says so. (Two fixtures do name a single agent model; the
# harness header says so.) A list in either place would be exactly the unbound copy the mechanism exists to prevent. The copies in the templates and the docs page cannot
# be removed — they exist so a human reads the values where they are — so they are bound instead. It also pins the two rules that keep
# `fable` human-chosen (no shipped agent declares it) and the agent frontmatter honest against
# model-defaults.md → Cache TTL (1h for an agent that waits, the 5m default for a short-burst one —
# code-reviewer's BARE frontmatter is asserted, so it reads as a decision, not an oversight), and it
# binds EVERY agent in agents/ to BOTH tables that describe its model — the cross-check loops over
# the directory, so a third agent is covered the moment it exists and fails the run until its tier
# row exists; the edits adding one are listed in model-defaults.md → Resolution Order, which also
# says which of them still fail quietly. KNOWN LIMITS: described ONCE, in
# model-defaults.md → How a copy is bound → Known limits of the binding mechanism. slice-047 closed
# the ten holes that block used to list (fences nested/unbalanced/tilde/blockquoted, an HTML comment
# block, a <pre> in the docs page, the raw table reads, the hardcoded tier set, the ambiguous
# self-test mutation); TWO remain there, and neither is a fence problem. Do not restate them here —
# this block is a pointer on purpose. 57 mutation fixtures that must go red,
# 3 legitimate edits that must stay green, and a positive control prove the checks bite. Read those
# numbers off a run (`| grep -c "correctly RED"`), never re-derive them — they were wrong in four
# places at once in round 8 because each surface was updated by hand at a different time. It also binds a
# SECOND declaration, model-defaults.md → Spawn-Reachable Values: the values a spawn parameter can carry,
# which three commands read at run time — bound by a declared value count, a subset relation to the enum,
# and a presence check on the rule and its heading. Keep green.
bash scripts/test-model-enum.sh

# Delete-safe closing — B19 / D34: CRAFT never goes around a user rule that denies or asks on removing
# files. scripts/delete-mode.sh decides, on the concrete `rm -- <path>` the agent would issue and over every
# settings level a script can read, whether such a rule applies (doubt means move); scripts/close-file.sh
# then moves the file into the gitignored .claude/plans/.closed/ or prints DELETE_CMD for the agent — it never
# removes anything itself; scripts/execute-lock.sh keeps the /craft:execute lock as state (held / released,
# owner = CLAUDE_PID + start time) with one fixed takeover rule. Covers the rule matrix, move / collision /
# refusal cases, every lock state incl. legacy locks, the guard's read block on .closed/ under bash 5 and
# /bin/bash 3.2, that no scanner sees .closed/, the pinned close sites (commit.md, abort.md) with no
# agent-issued rm left in the prose, and prime's cleanup hint (run for real on a fixture). Since slice-066 (B20) it
# also pins that execute.md step 9 keeps the checkpoint record as state — no removal of its lines, the file or .craft/.
# Keep green.
bash scripts/test-delete-safe.sh

# Autopilot verification — D35: inside an autopilot run, Phase 5 is verified by command, not by the builder's report.
# scripts/verify-run.sh parses a slice plan's <!-- craft:verify --> block (a single-line marker inside ## Test
# Strategy, never a fence — example-regions.sh decides what is an example), judges EVERY check command against the
# user's deny / ask rules before anything runs (scripts/permission-rule-match.sh — the one matcher, shared with
# delete-mode.sh, subcommand-aware like Claude Code: compound commands, substitutions, wrappers, assignments), runs
# the checks with a timeout and appends the evidence round to the plan itself. Covers pass / fail / none / malformed /
# refused (a subcommand rule, an ask rule, every settings level, doubt — and that nothing ran), timeouts, append-only
# rounds, `--only` (a named subset — the autopilot debug loop's verdict, slice-053; its round never reads as a Phase-5
# pass) and the no-python3 path. Keep green.
bash scripts/test-verify-run.sh

# Autopilot plan gate — scripts/plan-gate-state.sh decides which slice plans of an epic still await the autopilot's
# plan gate (slice-054): a plan a slice-planner wrote carries `> Planned-by:` in its frontmatter, and it awaits until
# a `plan gate approved: <ids>` line in the epic plan's ## Autopilot Log names it — derived, never stored. Covers
# hand-planned epics (no gate), partial and foreign-epic approvals, malformed approval lines (approve nothing), lines
# outside the log or in a fence, CRLF, NEEDS-HUMAN: counting (bold, checkbox, numbered forms too), ORPHAN plans — active
# plans no entry of any epic links, which /craft:execute → ap asks about before planning — and pins that execute.md /
# plan.md / the agent use it. Since slice-055 it also parses the epic plan's ## Plan Review (the plan-architect's rounds):
# open findings, malformed lines (counted open, autonomy 0) and the autonomous revision rounds left per planning pass.
# Keep green.
bash scripts/test-plan-gate-state.sh

# Autopilot epic-end digest — scripts/epic-digest.sh prints the whole "Autopilot — epic complete" block that
# /craft:execute a5 relays unchanged (slice-057, B22): per slice the first sentence of ## What, its follow-ups and its
# Phase-7 candidates (matched at the line start), then the epic plan's ## UX Demo Script byte-equal. The master wrote
# this block from memory before (slice-056 probes 3 and 4). Covers the exact block, the demo script byte-equal, CRLF,
# first-sentence rules, fenced decoys, and named errors that print nothing on stdout (a slice not landed, an archive
# missing or doubled, no ## What, no demo script). Keep green.
bash scripts/test-epic-digest.sh

# Autopilot budget guard — scripts/usage-state.sh is the one judge of whether the plan's usage windows allow an autopilot
# run to start a slice (before), go on within one (during, the slice-builder at every boundary of its spawn) or go on after one
# (after); the master and the builder act on VERDICT= only (slice-058, design record §6). Its input is the tap
# scripts/statusline-tap.sh (POSIX sh, wired by the user into statusLine) writes; limits come from craft-profile.md →
# ## Autopilot, the forecast is derived from the Δ five_hour fields of the epic's ## Autopilot Log. Covers missing / stale /
# malformed taps (conservative mode), every limit at its edge, the fixed overage heuristic, profile overrides and invalid
# values, forecast samples (fenced, CRLF, another section), the per-slice delta (reset, resume, negative), the tap's
# byte-equal pass-through and fail-open path, the pinned call sites in execute.md / build.md / slice-builder / prime.md and
# the profile copies bound to the helper's DEFAULTS. Keep green.
bash scripts/test-usage-state.sh

# Statusline tap wiring — scripts/ensure-statusline-tap.sh (slice-059, D36) wires the usage tap the budget guard reads into
# the USER's statusLine, only on a yes: /craft:prime step 4h and /craft:onboard offer --apply; --remove takes it out again.
# The marketplace clone is found through known_marketplaces.json and never wired while its tap does not exist; a project /
# local / managed statusLine wins and is only reported. Covers every --check state (absent, misrouted working tree / cache,
# no-refresh, overridden at each level, tap-missing, unrecognized) and that --check never writes, --apply for plain and
# compound commands (sh -c wrap), re-routes, key / indent / symlink / mode preservation, idempotency and the byte-equal
# backup, refusals that write nothing, the --apply → --remove round trip, the written command actually executed against
# the original, a foreign script that carries the tap's name (BUG-1), the clone chosen among several marketplaces, hidden
# and double taps, a failed write (exit 7), and the pinned prime / onboard sites. Keep green.
bash scripts/test-statusline-wiring.sh

# Autopilot cache guard — slice-060 (design record §7): while an autopilot session waits on the human, the UserPromptSubmit
# hook hooks/cache-guard.sh blocks a prompt that arrives after the prompt cache expired (no request is sent) and names the
# restart (/clear, then /craft:execute <epic> --autopilot); scripts/cache-guard-marker.sh arms / disarms it per session and
# states the expiry line every human stop prints. Covers block / pass for every fixture (marker armed / absent / disarmed /
# another session, tap warm / cold / missing / stale / another session, tokens below / at / above the threshold, profile
# override and invalid values, hand-back and task-notification prompts, /clear, malformed payload / marker / tap, no
# python3) under BOTH the running bash and a real /bin/bash 3.2 (any stderr text fails), the helper's round trip with the
# hook, the profile key's warning, the copies bound to usage-state.sh / statusline-tap.sh (tap path, default threshold,
# stale age), the hooks.json registration, and the sites in commands/execute.md that arm and disarm (markers). Keep green.
bash scripts/test-cache-guard.sh

# Epic close — scripts/epic-close-state.sh (slice-061 / slice-062, B24 / B26, D37 / D38) decides whether /craft:commit's
# Epic-close mode can close an epic now. KIND=autopilot: its ## Autopilot Log's last ■ line is a5's `merged into <trunk>`;
# KIND=sequential (no autopilot log — a sequential run or a hand-worked epic): no a5 answer needed. Both: every
# decomposition entry landed (epic-entry-link.sh resolve), and an epic branch, if any, is merged — a merge commit on the
# trunk with the branch tip as a non-first parent (the ancestor trap: a branch without own commits is no merge), or, an
# autopilot branch gone, a5's merge subject. Covers real git fixtures for every STATE (closable, not-signed-off incl.
# run_stopped, not-merged incl. another trunk, pr-path, entries-open, branch-unmerged, malformed) in both kinds, the last
# answer winning, ■ lines in a fence / outside the log / of another epic, CRLF, scan mode, errors, that it writes nothing,
# the epic archive template (templates/epic-archive.md.template: its sections and frontmatter keys, no ## Commits), and the
# pinned sites in commands/commit.md (the template in Step 5, Epic-close and P3) and execute.md a5 and s5 — and that no
# shipped file still names the mode by its slice-061 name. Keep green.
bash scripts/test-epic-close-state.sh

# Autopilot log — scripts/autopilot-log.sh (slice-063, B23) writes every line of an epic plan's ## Autopilot Log: it reads
# the clock itself (the master stamped invented times twice — slice-049, slice-057 probe 1), places the line as the
# section's last (a missing section above ## Recap Draft, CRLF, fenced decoys), checks it landed and prints it for the
# master to relay. Its gate holds a1: a slice step (▶ / ✓ with a slice-ID, ap's `planned from entry` aside) is refused
# until this invocation logged `run started` at or after the execute lock's SINCE= (slice-056 probe 3 re-ran without
# the briefing). Also pins execute.md: no hand-written log line or datetime command, the gate's route back to a1, and
# .craft/tmp/ as the master's only place for its own files. (--slices-from, the a4 re-run's slice list read off the epic
# plan, is covered in test-execute-resume-state.sh.) Keep green.
bash scripts/test-autopilot-log.sh

# Run THIS working tree as the plugin for one session (replaces the installed craft@craft;
# verified with Claude Code 2.1.270):
claude --plugin-dir /path/to/this/repo
```

This repo has no build tooling and no conventional test framework — it ships Markdown
commands/skills, JSON manifests, and Bash hooks. The twenty-three harnesses above are the
exception: they cover the `hooks/` + `scripts/` Bash surface, the phase-transition
graph the command Markdown encodes, the published docs-site's sync with the
plugin surface, the plugin runtime's drift from the working tree, the required toolchain,
the CRAFT local-state gitignore, the handoff-marker lifecycle, the review findings record, the execute re-run state, the plan round trip of parallel worktree mode, the tracked plan's landing under protected main, the epic entry ↔ slice-ID link, the autopilot's plan gate, the autopilot's log, the autopilot's epic-end digest, the epic close and its archive template, the autopilot's budget guard, the autopilot's cache guard, the statusline tap's wiring, the single declaration of the allowed model values, the
single definition of what counts as an example rather than content, delete-safe closing, and the autopilot's verification by command.

## Dogfooding Is Not Self-Verification

A normal session executes the **installed** CRAFT (`~/.claude/plugins/cache/craft/craft/<version>/`,
copied from the GitHub marketplace), **not** the files in this repo. Command prose, hooks, agents
and plugin-resolved paths (`${CLAUDE_PLUGIN_ROOT}/…`) come from that installed copy, so editing them
changes nothing about the session that makes the edit — the reviewer reads the new file while the
runtime obeys the old one. The exception: files a command reads by a **relative** path (e.g.
`skills/senior-developer/SKILL.md` in `/craft:prime` step 1) resolve against the project root, and in
this repo that is the working tree. So:

- `/craft:prime` step 5c shows `⚠ Plugin runtime ≠ working tree` with the differing files — from the
  first release that ships step 5c, or right away in a `--plugin-dir` session.
- To exercise changed command behavior, start a fresh session with `claude --plugin-dir <repo>`.
  Push + `/craft:upgrade` alone does **not** refresh the installed copy: `plugin.json` pins
  `version`, and Claude Code skips an update whose version it already has — only a release
  (version bump + push) does.
- Phase 5 here runs on automated evidence (see `rules.md` → Workflow Rules): the running session
  can show scripts and harnesses only; changed runtime behavior is shown by a headless probe
  (`claude -p "<command>" --plugin-dir <repo>`, run from a scratch copy) — or stated as unshown.
- A nested `claude` probe started **inside** this repo runs the SessionStart hook, which deletes
  `.claude/plans/.primed` and un-primes the running session — start probes from another directory.

## Workflow

Every session starts with `/craft:prime`, auto-triggered by the SessionStart hook. To
plan new work: `/craft:plan <feature-name>`. To resume open work: `/craft:continue`.
