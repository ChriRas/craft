# Slice 092 — pack-existing-projects

> Completed: 2026-11-09
> Commits: 1569f83..22401d6 (direct on main, no PR) · epic-006 entry `pack-existing-projects`

## What

A stack-pack can no longer lead the agent to migrate an existing project's toolchain as a side effect. The
Senior-Developer baseline states once that a project's existing toolchain wins over a pack's default and that migrating
it is the human's decision, and every pack must carry a `## Existing Projects` section directly after `## Stack` — how
to recognise the older or alternative tools of its stack and their equivalent commands — enforced by
`scripts/test-stack-packs.sh`.

## Why

- Raised by the user for `stack-python`: `/craft:onboard` proposes it for a plain `requirements.txt` too, and a pack that
  teaches only uv would lead the agent to `uv add` where `pip install` is right. The question holds for every pack, so
  the answer became part of the contract (D43 amended).
- The rule lives only in the baseline — nine copies of one sentence are the duplication the tabu forbids; a pack holds
  only what is stack-specific. The harness binds presence, position and at least one entry; the section's content stays
  a review matter, because prose is not checkable.

## Walk-through

`scripts/test-stack-packs.sh` now requires `Existing Projects` as the second section in C2; the new C7 checks that it
sits directly after `## Stack` and holds at least one `- ` line; B1 requires exactly one content line in
`skills/senior-developer/SKILL.md` marked `<!-- craft:existing-toolchain -->` (a fenced one does not count —
`example-regions.sh` decides). The template and `stack-php-laravel` (PHPUnit instead of Pest, no Filament, an older
Laravel major, an older PHP — each recognised from `composer.json`) satisfy it; ten new mutations prove each check
bites (29 earlier mutations unchanged, 39 in all — read off the run after review round 1). The docs page (DE/EN),
CLAUDE.md and the CHANGELOG describe the extended contract. Phase 8 round 1 found five Light local edits, all fixed
in-phase — among them a Laravel line that would have let a `^8.2` project use PHP 8.5 idioms, and an opening sentence
that restated the baseline rule instead of pointing to it.

## Decisions

- **Origin (user, 2026-11-09).** Asked about `stack-python`: the plan set uv + Ruff as the default and said nothing
  about the many projects that still use pip / venv. The detection table proposes `stack-python` for a plain
  `requirements.txt`, so a pack that teaches only its default would lead the agent to `uv add` where `pip install` and a
  `requirements.txt` line are right. The question holds for every pack, so it is answered in the contract.
- **The rule lives once, in the baseline (user).** One marked line in `skills/senior-developer/SKILL.md` (Tier 1, loaded
  every session): the project's existing toolchain wins over a pack's default, migrating is the human's decision. Each
  pack's `## Existing Projects` holds only what is stack-specific — how to recognise the alternative tools and their
  equivalent commands. *Why not* the rule in every pack: nine copies of one sentence, the duplication the tabu forbids;
  D27's monolithic packs are about stack knowledge, not about a universal rule.
- **Position and check (user).** `## Existing Projects` sits directly after `## Stack` (it qualifies the Stack defaults);
  the harness checks presence, position and at least one entry, and binds the baseline's marked rule. The section's
  content stays a review matter — prose is not checkable.
- **The eight pack plans were updated in this planning turn (user)** — each names its stack's alternative tools for the
  section, and slices 084, 089, 090 and 091 now depend on slice-092 (the others follow through their chains).

## Commits

- `1569f83` — docs(decisions): amend D43 — packs respect a project's existing toolchain
- `9c4822e` — feat(skills): require ## Existing Projects in every stack-pack
- `22401d6` — docs: describe the Existing Projects contract in the harness lists, docs site and changelog
