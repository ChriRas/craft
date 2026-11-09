# Slice 085 — stack-php-symfony

> Completed: 2026-11-09
> Commits: 68a3394..b6ecb5c (autopilot run, on epic-006-stack-packs, no PR) · epic-006 entry `stack-php-symfony`

## What

`skills/stack-php-symfony/` is a new plugin-shipped stack-pack for Symfony: a 120-line `SKILL.md` (Stack, seven
`## Existing Projects` entries, Reference Files, Build Order, Anti-Patterns, dated Sources) and five references —
`code-quality-standards.md` (138 lines), `framework-patterns.md` (186; layout, DI and configuration, controllers and
routing, Messenger, Security, assets), `doctrine-patterns.md` (156), `twig-forms-patterns.md` (137) and
`test-patterns.md` (182). The docs badge and inventory (8 -> 9 skills, 6 universal + 3 stack-packs), the Tier-2 card
(DE/EN), the README lines and the CHANGELOG name it. (Sizes read off the landed files.)

## Why

- A project that declares `Stack-Pack: stack-php-symfony` should get researched, current Symfony idioms instead of the
  "declared but not found" warning (epic-006, D43). Content comes from research only: every version and tool claim was
  checked on 2026-11-09 against symfony.com (releases, releases.json, docs for 8.1 / 7.4 / 6.4, UPGRADE notes),
  Packagist, the Symfony recipes, the DoctrineBundle and Doctrine ORM repositories and docs, and carries an https source
  in `## Sources`.
- The user chose the current line with the 7.4 LTS differences marked, a scope of core + Doctrine + Messenger + Security
  + Twig + Forms, and PHPUnit with `KernelTestCase` / `WebTestCase`; `## Existing Projects` keeps the pack from migrating
  older majors, annotation or XML projects, projects without Flex or on Pest.

## Walk-through

Research first (release lines and support dates, PHP floors, the 8.0 removals, DoctrineBundle 3 / ORM 3 changes, test
tooling), then `SKILL.md` from `templates/stack-pack/`, then the five references with examples checked against the
vendors' documentation and source, then the docs / README / CHANGELOG wiring. The contract's C6 first caught Twig `{{ }}`
syntax in prose, which was rewritten. Phase 5 was verified by command (`verify-run.sh` run 1 and, after the review fixes,
run 2, 4/4 checks each). Phase 8 round 1 found 3 Heavy and 7 Light findings, all local edits, all fixed in-phase (five
over the guide value of 5, each small): ORM 3.4+ does map backed property hooks (the pack had said the opposite);
`eraseCredentials()` is still abstract on 7.3 / 7.4; a Forms example bound a DTO to an entity `data_class`; plus seven
version-scope and example slips. The human content review of the pack text and its source list happens at the epic-end
sign-off.

## Decisions

- **Version lines: current + LTS (user, 2026-11-09).** The pack teaches the current stable line's idioms and marks
  where the LTS line differs, so it serves new and long-lived projects alike. Which line is current and which is LTS,
  and their support dates, are verified in the build (symfony.com/releases), not recalled.
- **Scope: core + Doctrine ORM, Messenger, Security, Twig + Forms (user).** DI and configuration, controllers and
  routing, and tests are always in. To hold the contract's size budget (SKILL.md ≤ 120, each reference ≤ 300 lines) the
  references are split by topic into five files.
- **Tests: PHPUnit with `KernelTestCase` / `WebTestCase` (user).** Consistent with `stack-php` (PHPUnit default); a Pest
  project overrides it in its own `rules.md`.
- **Depends on slice-084 (user).** Built after `stack-php`: it reuses that slice's verified PHP / PHPUnit / PHPStan
  research and touches the same docs lines, so the two run in sequence.
- **Monolithic (D27).** The PHP idioms the Symfony pack needs are restated in it, not referenced from `stack-php` — a
  project declares one pack.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section:
  an older Symfony major than the LTS line, annotations instead of attributes, YAML / XML instead of PHP configuration,
  a project without Flex, Pest instead of PHPUnit. The rule itself (the project's toolchain wins, never migrate unasked)
  is the baseline's, not repeated here.
- **Content review for the user (built 2026-11-09).** Read `skills/stack-php-symfony/SKILL.md` and its five references
  plus `## Sources` (checked by C5). Judgement calls worth a look: (1) the pack teaches 8.1 and marks 7.4 LTS, and states
  that 8.1 ends January 2027 and 8.2 is due this month; (2) PER-CS is the default style with `@Symfony` named as the
  alternative the project keeps if it has it; (3) Doctrine: DoctrineBundle 3 / ORM 3, native lazy objects, entities
  non-final unless on bundle 3, backed property hooks map since ORM 3.4; (4) Existing Projects lists seven alternatives;
  (5) Twig components and `zenstruck/foundry` are named in one line each without a how-to.
- **Phase 7 skipped (project rule).**

## Commits

- `68a3394` — feat(skills): add the stack-php-symfony pack
- `b6ecb5c` — docs: wire stack-php-symfony into the docs site, README and changelog
