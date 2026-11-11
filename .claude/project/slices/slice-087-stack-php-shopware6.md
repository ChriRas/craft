# Slice 087 — stack-php-shopware6

> Completed: 2026-11-11
> Commits: 884c87f..a41a2c6 (on epic-006-stack-packs, no PR) · epic-006 entry `stack-php-shopware6`

## What

`skills/stack-php-shopware6/` is a new plugin-shipped stack-pack for Shopware 6: a `SKILL.md` (113 lines: Stack, eight
`## Existing Projects` entries, Reference Files, Build Order, Anti-Patterns, ten dated Sources lines) and seven references —
`code-quality-standards.md` (127 lines), `plugin-patterns.md` (278; composer.json, lifecycle, `services.php`, subscribers,
`config.xml`, migrations, scheduled tasks, queue, routes and scopes), `dal-patterns.md` (180; attribute and definition
entities, flags, associations, `EntityExtension`, `Criteria`, writes, indexers), `app-patterns.md` (135; manifest, the signed
registration handshake, app server, webhooks, app scripts), `storefront-patterns.md` (163; Twig overrides, components, JS
plugins, SCSS, themes), `administration-patterns.md` (182; modules, components, Pinia, ACL, Meteor Admin SDK, SFC status) and
`test-patterns.md` (249; PHPUnit, Jest, Playwright). The docs badge and inventory (10 -> 11 skills, 6 universal + 5
stack-packs), the Tier-2 card (DE/EN), the README lines and the CHANGELOG name the pack. A project declaring
`Stack-Pack: stack-php-shopware6` now gets `✓ Stack-pack loaded` instead of the "declared but not found" warning.

## Why

- epic-006 ships researched stack-packs (D43); Shopware 6 needs its own because its idioms (DAL instead of an ORM, plugin
  bundles versus apps, TwigJS and Vue 3 in the Administration, `sw_extends` in the Storefront) sit on top of Symfony and
  differ between 6.5, 6.6 and 6.7. Every version claim was checked on 2026-11-11 against Packagist, the platform
  repository (`releases.json`, `UPGRADE-6.8.md`, `RELEASE_INFO-6.7.md`, `Bundle.php` across tags, the 6.6.x and 6.5.x
  branches) and the developer docs repository, and carries an https source in `## Sources`.
- The slice plan's decisions held: all four extension kinds, 6.7 plus the older supported line, tests on three levels, one slice
  with seven references (SKILL.md 113 of 120 lines, references 127 to 278 of 300), monolithic per D27 (Symfony restated).

## Walk-through

Research came first and drove the shape: Packagist gave the lines (6.7.16.0, 6.6.10.31, 6.5.8.19, PHP 8.2 to 8.5, Symfony
7.4), `releases.json` the support dates, `Bundle.php` diffed across tags gave the XML-configuration deprecation (first in
v6.7.14.0), and the docs repository gave the idioms. Where the docs disagree with the code or with each other, the pack says
so (the Store API route form of ADR 2026-09-24 versus core's `Abstract…Route`, Test Utils 1 boilerplate, `fetchAssoc` under
DBAL 4, `beforeDestroy`, the `commponents` spelling, the experimental SFC system). Then SKILL.md and the references were
written to the contract (C1 to C7), the wiring edits followed the slice-086 pattern, and `scripts/test-stack-packs.sh` caught
one thing the writing missed: Twig print syntax inside inline code counts as a `{{…}}` placeholder (C6), fixed by describing
the function instead. Phase 5 ran by command: four checks, all pass. Review round 1 found 1 Heavy (the `cache-relevant`
config attribute without its 6.7.12.0 boundary) and 12 Light, 10 fixed in-phase; round 2 bounded the same attribute for apps
(R2-1), fixed three Light findings in-phase, and the three left at the fix cap (R1-4, R1-5, R1-13) went back to Phase 4: the
Playwright task taken from the test's fixtures with no literal price, `->name` on the attribute entity, the duplicated
existing-toolchain clause dropped. Phase 5 again by command: round 2, four of four checks pass.

## Decisions

- **Scope: all four extension kinds (user, 2026-11-09)** — PHP plugins (with the DAL, services, subscribers,
  migrations, scheduled tasks, routes), apps, the Storefront and themes, and the Administration.
- **Versions: 6.7 + the still-supported older minor line (user).** The pack teaches 6.7 idioms and marks where the older
  line differs. Which line still receives security updates is verified in the build against Shopware's own release
  information, not recalled.
- **Tests on three levels (user):** PHPUnit (unit and integration with Shopware's test behaviours), JS unit tests for
  the Administration and Storefront, Playwright for E2E. The JS runner and the acceptance-test tooling are verified in
  the build.
- **One slice, seven reference files (user)** — not split into a backend and a frontend slice: the size budget holds per
  file (SKILL.md ≤ 120, each reference ≤ 300 lines), and one epic entry stays one slice.
- **Depends on slice-085 (user).** Shopware 6 is a Symfony application, so it builds on the Symfony pack's verified
  research; it does not need API Platform's. slice-086 depends on slice-085 too — the epic still runs its slices in
  sequence (they touch the same docs lines), so 086 lands before 087 by order, not by dependency. Monolithic (D27): the
  Symfony core is restated in this pack.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: an
  older 6.x minor line than the supported ones, the Administration's older Vue major where a line still ships it, Jest /
  Cypress instead of the current JS and E2E tooling — each verified in the build. The rule itself (the project's
  toolchain wins, never migrate unasked) is the baseline's, not repeated here.
- **Content review brief (Phase 5, build-time).** What the pack says: seven reference files plus SKILL.md, verified on
  2026-11-11 against Packagist (shopware/core 6.7.16.0 / 6.6.10.31 / 6.5.8.19), the platform repo (`releases.json`,
  `UPGRADE-6.8.md`, `RELEASE_INFO-6.7.md`, `Bundle.php` at tags v6.7.13.0 / v6.7.14.0, the 6.6.x and 6.5.x branches) and
  the developer docs repo (`github.com/shopware/docs`). The source list is `## Sources` in SKILL.md. Judgement calls to
  read first: (1) the support-date reading of `releases.json` (field names are the file's, not defined there); (2) PHP
  service configuration as the default and XML marked deprecated from 6.7.14.0 (found by diffing `Bundle.php` across
  tags); (3) the Store API route example in the docs follows an ADR of 2026-09-24 while core routes on 6.7 still use
  `Abstract…Route` — the pack says both and defers to the project's neighbours; (4) SFC extension system documented as
  experimental (6.7.16.0, stable planned for 6.9); (5) places where the docs still show older code are named in the pack
  (Test Utils 1 boilerplate, `fetchAssoc`, `beforeDestroy`, the `commponents` folder spelling); (6) the 6.8 readiness
  lists are from `UPGRADE-6.8.md` on trunk, not a released version.
- **Phase 7 skipped (project rule).**
- **Review round 2 → loop-back to Phase 4** (2026-11-11) — fix cap (5) reached in round 1 with 3 local-edit findings
  open (R1-4, R1-5, R1-13), routed to Phase 4 in round 2's Step 7; route chosen by the user.

## Commits

- `884c87f` — feat(skills): add the stack-php-shopware6 pack
- `a41a2c6` — docs: wire stack-php-shopware6 into the docs site, README and changelog
