---
name: stack-php
description: CRAFT stack-pack for plain PHP projects without a framework (libraries, CLI tools, small apps) — language idioms, Composer project patterns, and PHPUnit test patterns with PHPStan and PER Coding Style as the quality rules. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — PHP (no framework)

The code-near personality layer for a PHP 8.4 / 8.5 project without a framework — a library, a CLI tool or a small
application wired by hand — built on Composer, tested with PHPUnit and kept clean with PHPStan and PER Coding Style. It is
loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`, `/craft:refactor` and `/craft:review`
when `rules.md` declares it in its `## Personality` block. A project on Laravel, Symfony or Shopware declares that
framework's pack instead (a pack is monolithic). Project-specific conventions — domain rules, exact tool commands, the
supported PHP range — live in the project's own `rules.md`, not here. Versions and levels below were verified on
2026-11-09 (see `## Sources`); a newer release may have moved since.

## Stack

- **Language** — PHP 8.4 / 8.5: `declare(strict_types=1)`, `final readonly` classes, backed enums, full type hints,
  constructor property promotion. 8.4 adds property hooks and asymmetric visibility, 8.5 the pipe operator and clone-with;
  both are in `references/code-quality-standards.md`. Support on 2026-11-09: 8.4 and 8.5 are actively supported, 8.3 and
  8.2 get security fixes only (8.2 ends on 2026-12-31); 8.6 is at release-candidate stage.
- **Dependencies** — Composer 2.11 with PSR-4 autoloading, `composer.lock` committed, constructor injection wired in one
  composition root; no framework container (see `references/project-patterns.md`).
- **Tests** — PHPUnit 13 (requires PHP 8.4 or newer; PHPUnit 12 for 8.3, 11 for 8.2) — attributes, data providers, test
  doubles. A project on Pest: see `## Existing Projects`.
- **Quality** — PHPStan 2.x at its strictest level that the codebase passes (`max` for new code); PER Coding Style 3.1
  enforced with PHP-CS-Fixer's `@PER-CS` rule set (currently the 3.0 rules, `@PER-CS3x0`).

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.json` and the config files at the project
root first and follow what they declare:

- **Pest instead of PHPUnit** — `pestphp/pest` in `require-dev`, a `tests/Pest.php`, tests written as `it(...)` /
  `test(...)` closures; run them with `vendor/bin/pest`. Pest sits on top of PHPUnit, so a PHPUnit class in `tests/` still
  runs — write a new test in the style of its neighbours, never add a second runner.
- **Psalm instead of PHPStan** — `vimeo/psalm` in `require-dev` and a `psalm.xml`; run `vendor/bin/psalm`. Its levels run
  from 1 (strictest) to 8, and a baseline is created with `--set-baseline`. Keep the project's level and baseline; do not
  add a `phpstan.neon`.
- **No static analysis** — neither `phpstan.neon(.dist)` nor `psalm.xml` exists. Write fully typed code and docblock array
  shapes all the same, but do not add an analyser to the slice; if it would pay off, name it as a follow-up.
- **PSR-12, PHP_CodeSniffer or a house style instead of PER-CS** — a `phpcs.xml(.dist)` with `squizlabs/php_codesniffer`
  (run `vendor/bin/phpcs`, fix with `vendor/bin/phpcbf`; it ships a `PSR12` standard but no PER standard), or a
  `.php-cs-fixer.dist.php` naming other rule sets (`@PSR12`, `@Symfony`, custom rules). The project's rules win: format new
  code the way the neighbouring files are formatted and never reformat files the slice does not touch.
- **Another framework** (Slim, Laminas / Mezzio, CakePHP, Yii, WordPress, Drupal …) — the framework's container, routing
  and conventions win over this pack's hand-wired composition root; use the pack for language idioms and quality tooling only.
- **An older PHP or older PHPUnit** — `require.php` (and `config.platform.php`) in `composer.json` set the floor; use no
  language feature above it (readonly properties 8.1, `final readonly` classes 8.2, `#[\Override]` and typed class
  constants 8.3, property hooks and asymmetric visibility 8.4, pipe operator and clone-with 8.5). The installed PHPUnit
  major follows the floor; 11 and older still accept `@dataProvider`-style doc-comment annotations, which 12 removed —
  follow the form the neighbouring tests use.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP 8.2 to 8.5 language idioms, the code-quality checklist, error handling,
  PHPStan and PER-CS rules.
- `references/project-patterns.md` — Composer and `composer.json`, PSR-4 layout, dependency injection without a framework,
  configuration, entry points.
- `references/test-patterns.md` — PHPUnit 13 unit and integration test patterns, data providers, test doubles, `phpunit.xml.dist`.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Composer and tooling — `composer.json`, autoload mapping, `phpunit.xml.dist`, `phpstan.neon.dist`, the fixer config.
2. Domain types — value objects, backed enums, exceptions.
3. Services — use-case logic behind small interfaces, dependencies by constructor.
4. Adapters — persistence, HTTP clients, filesystem and clock behind those interfaces.
5. Entry points and composition root — `public/index.php`, `bin/<tool>`, the one place that wires everything.
6. Tests — alongside each layer or right after; PHPStan and the fixer pass before a layer counts as done.

## Anti-Patterns

- No `declare(strict_types=1)`, partial type hints, or `mixed` and bare `array` where a value object or an array shape fits.
- Business logic in `public/index.php`, a bin script or a bootstrap file instead of a service.
- Global state: singletons, static service locators, `global`, reading `$_ENV` or `getenv()` deep inside the domain.
- `new SomeAdapter()` inside business logic — a hidden dependency that no test can replace.
- `require` / `include` of class files instead of the Composer autoloader.
- The error-control operator `@`, an empty `catch`, or catching `\Throwable` only to carry on.
- A PHPStan baseline or `ignoreErrors` that grows to hide new findings; a fixer run that rewrites files outside the slice.
- `composer update` on a server, an uncommitted `composer.lock` in an application, or `*` / `dev-main` version constraints.
- Tests that sleep, hit the network or the wall clock, or mock a value object instead of constructing it.

## Sources

> As of: 2026-11-09 · Basis: research

- PHP: Supported Versions — https://www.php.net/supported-versions.php (8.2 to 8.5 support dates; 8.6.0 RC5 banner)
- PHP: Active releases feed — https://www.php.net/releases/active.php (latest patch per branch: 8.2.35, 8.3.36, 8.4.27, 8.5.12)
- PHP 8.5, 8.4, 8.3, 8.2 and 8.1 release announcements — https://www.php.net/releases/8.5/en.php, https://www.php.net/releases/8.4/en.php, https://www.php.net/releases/8.3/en.php, https://www.php.net/releases/8.2/en.php, https://www.php.net/releases/8.1/en.php (the language features named per version)
- PHPUnit: Supported Versions — https://phpunit.de/supported-versions.html (13 needs PHP 8.4, 12 needs 8.3, 11 needs 8.2)
- PHPUnit 12 and 13 announcements — https://phpunit.de/announcements/phpunit-12.html, https://phpunit.de/announcements/phpunit-13.html (doc-comment annotations removed in 12; `seal()` in 13)
- PHPUnit 13.4 manual — https://docs.phpunit.de/en/13.4/ (writing tests, attributes, test doubles, configuration)
- Packagist, current releases and PHP requirements — https://packagist.org/packages/phpunit/phpunit, https://packagist.org/packages/phpstan/phpstan, https://packagist.org/packages/friendsofphp/php-cs-fixer, https://packagist.org/packages/squizlabs/php_codesniffer, https://packagist.org/packages/composer/composer, https://packagist.org/packages/pestphp/pest, https://packagist.org/packages/vimeo/psalm, https://packagist.org/packages/symfony/clock (PHPUnit 13.4.6, PHPStan 2.3.5, PHP-CS-Fixer 3.95.30, PHP_CodeSniffer 4.0.4, Composer 2.11.1, Pest 5.3.5 on PHPUnit 13, Psalm 7.2.0; symfony/clock as a PSR-20 implementation)
- PHPStan: Rule Levels, Getting Started, The Baseline, Extension Library — https://phpstan.org/user-guide/rule-levels, https://phpstan.org/user-guide/getting-started, https://phpstan.org/user-guide/baseline, https://phpstan.org/user-guide/extension-library (levels 0 to 10 and `max`, the baseline, strict-rules and phpunit extensions)
- PHP-FIG: PER Coding Style 3.1 and the PSR index — https://www.php-fig.org/per/coding-style/, https://www.php-fig.org/psr/ (the style rules; PER extends and replaces PSR-12; PSR-3, 4, 11, 20 accepted)
- PHP-CS-Fixer: README, configuration and rule sets — https://github.com/PHP-CS-Fixer/PHP-CS-Fixer, https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/doc/config.rst, https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/doc/ruleSets/PER-CS.rst (`init`, `fix`, `check`; `@PER-CS` aliases the latest PER-CS revision)
- PHP_CodeSniffer: README and shipped standards — https://github.com/PHPCSStandards/PHP_CodeSniffer, https://github.com/PHPCSStandards/PHP_CodeSniffer/tree/4.x/src/Standards (`phpcs` / `phpcbf`; PSR12 shipped, no PER standard)
- Composer 2.11 documentation — https://github.com/composer/composer/blob/2.11.1/doc/01-basic-usage.md, https://github.com/composer/composer/blob/2.11.1/doc/02-libraries.md, https://github.com/composer/composer/blob/2.11.1/doc/03-cli.md, https://github.com/composer/composer/blob/2.11.1/doc/06-config.md (lock file, PSR-4, `audit`, `validate`, platform config)
- PHPStan: Ignoring Errors — https://phpstan.org/user-guide/ignoring-errors (`@phpstan-ignore <identifier>`)
- Composer scripts — https://github.com/composer/composer/blob/2.11.1/doc/articles/scripts.md (`vendor/bin` first on the `PATH` while scripts run)
- Psalm documentation — https://github.com/vimeo/psalm/tree/master/docs/running_psalm (installation, error levels 1 to 8, baseline)
