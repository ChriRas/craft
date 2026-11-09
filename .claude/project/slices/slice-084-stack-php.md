# Slice 084 — stack-php

> Completed: 2026-11-09
> Commits: bb1c9c4..ad678f6 (autopilot run, on epic-006-stack-packs, no PR) · epic-006 entry `stack-php`

## What

`skills/stack-php/` is a new plugin-shipped stack-pack for plain PHP without a framework: a 106-line `SKILL.md` (Stack,
six `## Existing Projects` entries, Reference Files, Build Order, Anti-Patterns, dated Sources) and three references —
`code-quality-standards.md` (PHP 8.2-8.5 idioms, checklist, error handling, PHPStan and PER-CS/PHP-CS-Fixer setup),
`project-patterns.md` (Composer, PSR-4, dependency injection without a framework, configuration, entry points) and
`test-patterns.md` (PHPUnit 13). The docs badge and inventory (7 -> 8 skills, 6 universal + 2 stack-packs), the Tier-2 card
(DE/EN), the README lines and the CHANGELOG name it. (Sizes read off the landed files; the recap draft's "102 lines, five
entries" predates review round 1, which added the "another PHP framework" entry.)

## Why

- A project that declares `Stack-Pack: stack-php` should get researched, current PHP idioms instead of the "declared but
  not found" warning (epic-006, D43). Content comes from research only: every version and tool claim was checked on
  2026-11-09 against php.net, phpunit.de and docs.phpunit.de, Packagist, phpstan.org, php-fig.org, the PHP-CS-Fixer /
  PHP_CodeSniffer / Composer / Psalm repositories, and carries an https source in `## Sources`.
- PHPUnit as the default test tool and PHPStan + PER-CS as quality rules are the user's choices; the contract's
  `## Existing Projects` keeps the pack from migrating a project that uses Pest, Psalm, PHP_CodeSniffer, another
  framework or an older PHP.

## Walk-through

Research first (support dates, current majors and their PHP floors, rule levels, rule-set names), then the SKILL.md from
`templates/stack-pack/`, then the three references with examples checked against the vendors' own documentation, then the
docs/README/CHANGELOG wiring. Phase 5 was verified by command (`verify-run.sh` run 1, 4/4 checks). Phase 8 round 1 found
0 Heavy and 6 Light local edits, all fixed in-phase (one over the guide value of 5) — among them a `#[\Deprecated]`
example that is fatal on a class in PHP 8.5 and a `dump-autoload` without `--optimize`. The human content review of the
pack text and its source list happens at the epic-end sign-off.

## Decisions

- **Tests: PHPUnit (user, 2026-11-09).** The framework-neutral default for libraries and framework-less apps; a Pest
  project overrides it in its own `rules.md` (the reverse of `stack-php-laravel`, which says Pest).
- **Quality tools: PHPStan + PER Coding Style (user).** PHPStan at a high level for static analysis; PER Coding Style
  (PHP-FIG) as the style, enforced with PHP-CS-Fixer or PHP_CodeSniffer. Psalm is not the default. Versions and levels
  are verified in the build, not recalled.
- **Depends on slice-083** — the pack is built against the contract and template that slice landed.
- **Wiring per epic-006 (amended by slice-083):** docs count/text, README line, CHANGELOG line — no detection row.
- **Verified 2026-11-09 (build):** PHP 8.4 / 8.5 active, 8.3 / 8.2 security-only (8.2 ends 2026-12-31), 8.6.0 at RC5
  (php.net); PHPUnit 13.4.6 needs PHP >= 8.4 (12 -> 8.3, 11 -> 8.2), doc-comment annotations removed in 12; PHPStan 2.3.5,
  levels 0-10 plus `max`; PER Coding Style 3.1.0 (extends and replaces PSR-12); PHP-CS-Fixer 3.95.30 (`@PER-CS` aliases
  the latest revision, currently `@PER-CS3x0`); PHP_CodeSniffer 4.0.4 ships PSR12 but no PER standard; Composer 2.11.1;
  Pest 5.3.5 (PHPUnit ^13.4.5); Psalm 7.2.0. All source URLs answered HTTP 200 on that day.
- **Pack scope for the content review (Phase 5 content review is the human's, at the epic-end sign-off in an autopilot
  run):** `skills/stack-php/SKILL.md` plus `references/` code-quality-standards, project-patterns, test-patterns; the
  source list is `## Sources` in SKILL.md.
- **Phase 7 skipped (project rule).**
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section:
  Pest instead of PHPUnit, Psalm or no static analysis instead of PHPStan, PSR-12 / PHP_CodeSniffer rule sets or a house
  style instead of PER-CS, an older supported PHP version. The rule itself (the project's toolchain wins, never migrate
  unasked) is the baseline's, not repeated here.

## Commits

- `bb1c9c4` — feat(skills): add the stack-php pack for plain PHP without a framework
- `ad678f6` — docs: wire stack-php into the docs site, README and changelog
