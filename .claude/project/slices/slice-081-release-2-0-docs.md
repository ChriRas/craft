# Slice 081 — Release 2.0 docs: CHANGELOG, README, CONTRIBUTING, docs site

> Completed: 2026-10-09
> Commits: ec25d98..4539a20 (direct on main, no PR)

## What

Everything a reader meets on GitHub now tells the 2.0 story and is release-ready: the CHANGELOG's `[Unreleased]`
section reads as the finished 2.0 release notes, the README presents the autopilot as the headline capability, a new
bilingual CONTRIBUTING guide (`CONTRIBUTING.md` / `CONTRIBUTING.de.md`) shows how to contribute, and the docs site was
checked against the tree in full, not only patched with the delta since 1.8.0. The version stays 1.8.0 — the bump is a
release step of its own.

## Why

- All release docs land in one slice so the 2.0 story is told once and consistently; content now, bump later, because
  the GitHub test on a protected trunk is still owed and may bring fixes.
- The docs site got the full mode because 2.0 is a major. The full audit surfaced product defects (inert profile
  fields, `execute.md` contradicting itself, a breaker re-spawn that exists only in `model-defaults.md`, a trailer remark
  at commit) — the docs describe the actual behavior, the defects became roadmap entries B34–B37, and no command changed
  in this slice.
- Walk-through: `scripts/test-docs-site.sh` was extended first (CONTRIBUTING linked both ways, README links it, one-line
  CHANGELOG items, skills counted by `SKILL.md`), each new check shown to bite on a mutated copy. Then the CHANGELOG, the
  README and the two CONTRIBUTING files. For the docs site four read-only audit agents produced about 70 findings, and
  four writer agents applied them one after another to the one file, each followed by the harness. Last, the CLAUDE.md
  pointer, the roadmap entries and two fact fixes in the README (context-mode is required; "4 user-facing skills").
  Phase 5: harness GREEN, browser check in EN, DE and the light theme, the human's `[W]`. Review round 1: 7 Light
  findings, all fixed in-phase (release steps incl. `marketplace.json` and the kept empty `[Unreleased]`, German wording,
  the epic close shipped in 1.8.0, onboard's [D]/[G], slice range 071–077, the docs-site contract's skill count,
  D1–D42).

## Decisions

- **One slice for all release docs** (user, Phase 3): CHANGELOG, README, CONTRIBUTING and the docs site land together,
  so the 2.0 story is told once and consistently.
- **Content now, bump later** (user, Phase 3): the version stays 1.8.0 and the CHANGELOG keeps `[Unreleased]` with a
  finished 2.0 opening and upgrade note. *Why not* bump now: the GitHub test with a protected trunk is still owed and may
  bring fixes; the bump, push, tag and release are a short step of their own afterwards. The docs therefore never claim
  2.0.0 as released (`test-docs-site.sh` binds the badge to `plugin.json`).
- **"GitHub docs" = the docs site (GitHub Pages) and the release text** (user, Phase 3) — no `.github/` templates.
- **The release text lives in the CHANGELOG section** (user, Phase 3), as rules.md → Deployment prescribes; no separate
  notes file.
- **The docs site gets the full mode** of `.claude/skills/docs-site/SKILL.md` (user, Phase 3): 2.0 is a major, so every
  section is checked against the tree, not only the delta since 1.8.0.
- **CONTRIBUTING in two files** (user, Phase 3): `CONTRIBUTING.md` (English, GitHub links it automatically) and
  `CONTRIBUTING.de.md` (German), linked both ways — bilingual like the docs site.
- **Tested by harness, browser and fact check** (user, Phase 3): new `test-docs-site.sh` checks (shown to bite), a
  rendered EN/DE check in Phase 5, and a claim-by-claim review against the tree in Phase 8.
- **A skill is a directory holding `SKILL.md`** (Phase 4 finding): `skills/agent-browser/` is an empty directory that
  was never in git, yet the docs badge said 8 skills and the README listed "browser automation" as a skill — a fresh
  clone has 7 (6 universal + the `stack-php-laravel` stack-pack); browser automation is the `agent-browser` CLI.
  `test-docs-site.sh` counts only directories with `SKILL.md`; the empty local directory is left alone.
- **"What's New in 2.0" in the README while `plugin.json` says 1.8.0**: the README reaches readers only with the push,
  and the push is the release (rules.md → Deployment), which carries the bump — so the section is right the moment it is
  published. The docs site, bound to `plugin.json` by its harness, keeps the badge at the current version until then.
- **Full mode as a four-perspective audit, then sequential section writers** (Phase 4): four read-only agents audited
  the page against the tree; four writer agents then applied the findings one after another. *Why not* parallel
  writers: one file, and parallel edits would collide.
- **Inert profile fields are documented honestly, fixed later** (user, Phase 4): `Auto-commit` without effect,
  `Approval` read by no command, `Approval-granularity: per-slice | per-epic` never implemented, `pull-request` without
  `Protected-main: yes` without a landing path, `Permissions → Scope` and `> Preset:` labels only, and
  `commands/execute.md` contradicting itself. The docs describe the actual behavior; each product finding is a roadmap
  entry (B34–B37); no code changes in this slice.
- **Docs-site writers 2–4 applied after the resume** (Phase 4): writer 2's items were already on the page from a run
  before the pause (verified, two additions); writers 3 and 4 applied theirs. Writer 3 narrowed one finding: the
  breaker's re-spawn on deep-reason exists only in `model-defaults.md` — `/craft:review` Step 9 blocks the slice — so
  the docs do not claim it (B36).
- **README's companion-plugin claim fixed in-slice, not deferred**: "Neither is required" contradicted prime's
  pre-flight, which stops without context-mode; the README now says context7 is optional and context-mode required.
  CLAUDE.md's stale example-regions consumer list was corrected here too.
- **"4 user-facing skills", not "4 slash-invocable skills"** (user, Phase 4): per the current Claude Code skills docs
  (verified 2026-10-09) every skill without `user-invocable: false` can be typed — all 7 of CRAFT's. The 4 (craft,
  debug, brainstorm, grill-me) are the ones meant for the user, so the count stays and the wording changes (README, docs
  site EN/DE, the docs-site skill's contract).

## Commits

- `ec25d98` — docs: add the contributing guide in English and German
- `c163bdc` — docs(changelog): complete [Unreleased] as the 2.0 release notes
- `ef10e74` — docs(readme): present 2.0 with the autopilot as the headline
- `cdae9b2` — docs(pages): bring the docs site up to date for 2.0
- `e3c3310` — test(docs-site): check the contributing guide, one-line changelog items and skills by SKILL.md
- `ef85a2a` — docs: point to CONTRIBUTING and name the decision log D1–D42
- `e8878d6` — docs(roadmap): record B34–B37 and the 2.0 release preparation
- `4539a20` — chore(plans): bump slice counter to 82 and epic counter to 6
