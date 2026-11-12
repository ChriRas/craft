---
name: stack-php-symfony
description: CRAFT stack-pack for Symfony applications on the current line (8.x) with the 7.4 LTS differences marked — dependency injection and configuration, controllers and routing, Doctrine ORM, Messenger, Security, Twig and Forms, and PHPUnit tests with KernelTestCase and WebTestCase. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — Symfony

The code-near personality layer for a Symfony application — the full-stack framework with Flex, attribute routing,
autowired services, Doctrine ORM, Messenger, Security, Twig and Forms — written for the current line (Symfony 8.1) with
the 7.4 LTS differences marked. It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`,
`/craft:refactor` and `/craft:review` when `rules.md` declares it in its `## Personality` block. A project on API
Platform, Shopware or Laravel declares that pack instead, and one without Symfony declares `stack-php` (a pack is
monolithic: the PHP idioms are restated here). Project-specific conventions — domain rules, exact commands, the
supported Symfony range — live in the project's own `rules.md`, not here. Versions below were verified on 2026-11-09 (see
`## Sources`); a newer release may have moved since.

## Stack

- **Symfony** — 8.1 is the current stable line (8.1.11, requires PHP 8.4; bug and security fixes end January 2027).
  8.2 is in beta and due in November 2026 (support to July 2027). 7.4 is the LTS line (7.4.23, requires PHP 8.2; bugs
  until November 2028, security until November 2029); 6.4 gets bug fixes until November 2026 and security fixes until
  November 2027. 7.4 and 8.0 shipped with the same features; 8.0 carries none of 7.4's deprecated ones.
- **Language** — PHP 8.4 or newer on 8.x, 8.2 or newer on 7.4: `declare(strict_types=1)`, `final readonly` classes,
  backed enums, constructor promotion, attributes for routes, mapping, security and service wiring.
- **Persistence** — Doctrine ORM 3.7 with DBAL 4 through DoctrineBundle 3.3 (needs PHP 8.4; 2.19 for PHP 8.1 to 8.3) and
  DoctrineMigrationsBundle 4.0 (3.7 for older PHP); attribute mapping only; `make:migration` generates migrations.
- **Messaging, security, views** — Messenger with `#[AsMessageHandler]`, SecurityBundle with an `auto` password hasher
  and voters, Twig 3 with Forms; assets through AssetMapper (see `references/framework-patterns.md`).
- **Tests** — PHPUnit through `symfony/test-pack` (PHPUnit 13 on PHP 8.4; 12 on 8.3, 11 on 8.2) with `KernelTestCase`
  and `WebTestCase`, run as `php bin/phpunit`. A project on Pest: see `## Existing Projects`.
- **Quality** — PHPStan 2.x with `phpstan-symfony` and `phpstan-doctrine`, PHP-CS-Fixer (`@PER-CS`), and the framework's own
  linters: `lint:container`, `lint:twig`, `lint:yaml`, `doctrine:schema:validate`.

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.json`, `composer.lock`, `symfony.lock`
and the `config/` tree first and follow what they declare:

- **An older Symfony major than the LTS line** (6.4 or earlier) — `symfony/framework-bundle` in `composer.json`, the
  version in `composer.lock`. Write to that line's API: no `#[MapQueryString]` before 6.3, no `#[AsMessage]` before 7.2, no
  `{slug:product}` route mapping before 7.1; `UserInterface::eraseCredentials()` is required up to 7.4. Plan upgrades
  one minor at a time with deprecations fixed first (`setup/upgrade_major`), and never raise the major unasked.
- **7.4 LTS** — everything in this pack not marked 8.1 works, but PHP may be 8.2 or 8.3 (no property hooks, no `#[\Override]` before
  8.3, DoctrineBundle 2.19 instead of 3.x) and 7.4 still accepts what 8.0 removed: XML config, `#[TaggedIterator]`,
  `Request::get()`, and still requires `eraseCredentials()` (keep an empty `#[\Deprecated]` one). Write no new use of a deprecated form.
- **Annotations instead of attributes** — `doctrine/annotations` in `composer.lock`, `@Route`, `@ORM\Entity` in docblocks:
  attributes are the only supported form on ORM 3 and Symfony 7+; on an older project follow the neighbouring files and
  migrate a file only when the slice touches it.
- **YAML or XML instead of PHP configuration, XML mapping** — `config/packages/*.yaml` is the Flex default and valid on
  every line; XML as a configuration format is gone in 8.0 (service, route and extension files) while XML entity mapping (`*.orm.xml`) stays valid on ORM 3.
  Keep the project's format and write a new file in it.
- **A project without Flex** — no `symfony.lock`, no `flex` in `composer.json`, config files written by hand: nothing
  auto-registers bundles (edit `config/bundles.php`), attribute routing needs `resource: routing.controllers` (since 7.4; earlier `controllers: {resource: ../src/Controller/, type: attribute}`), and
  `composer require` runs no recipe — create the config the recipe would have.
- **Pest instead of PHPUnit** — `pestphp/pest` in `require-dev`, a `tests/Pest.php`; run `vendor/bin/pest`. Pest sits on
  PHPUnit, so `KernelTestCase` and `WebTestCase` classes in `tests/` still run; write a new test in the style of its
  neighbours and add no second runner.
- **Another code style or analyser** — `@Symfony` or a custom rule set in `.php-cs-fixer.dist.php`, a `phpcs.xml`, Psalm
  instead of PHPStan: the project's rules win; never reformat files the slice does not touch.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP 8.2 to 8.5 idioms for Symfony code, the quality checklist, error handling,
  PHPStan, PHP-CS-Fixer and the framework linters.
- `references/framework-patterns.md` — project layout, dependency injection and configuration, controllers and routing,
  Messenger, Security, assets.
- `references/doctrine-patterns.md` — entities, repositories, migrations, transactions, N+1, DoctrineBundle 3 and ORM 3.
- `references/twig-forms-patterns.md` — templates, Twig extensions, form types, validation constraints, CSRF.
- `references/test-patterns.md` — PHPUnit, `KernelTestCase`, `WebTestCase`, the test database, login, mailer and Messenger
  assertions, `phpunit.dist.xml`.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Dependencies and configuration — `composer require`, the recipe's config, env vars and `config/packages/`.
2. Domain model — Doctrine entities (attributes), enums, value objects, then `make:migration` and review the SQL.
3. Services — use-case classes autowired by constructor, repositories, Messenger messages and handlers.
4. Security — firewall, voters, `access_control`.
5. Entry points — controllers (thin: map input, call a service, return a response), forms and templates, console commands.
6. Tests — alongside each layer; PHPStan, `lint:*`, the fixer and `php bin/phpunit` pass before a layer counts as done.

## Anti-Patterns

- Business logic in a controller, a form type or a Twig template; a controller that talks to the `EntityManager` directly.
- `$container->get()`, a service locator or a public service instead of constructor injection; a bundle created to
  organise application code.
- Per-environment values in `services.yaml` (use env vars and secrets) or secrets committed in `.env`.
- Entities returned straight from an API or put into a Messenger message — send the id or a DTO.
- `flush()` inside a loop, lazy-loaded associations read in a loop (N+1), or `doctrine:schema:update --force` against a
  shared database instead of a reviewed migration.
- A form without CSRF protection on a state-changing route, `|raw` on user input, security checks only in templates.
- Several firewalls where one would do, a role check where a voter would say what is meant.
- Tests that boot the kernel for a pure unit, share state through the database, or hard-code `generateUrl()` results.

## Sources

> As of: 2026-11-09 · Basis: research

- Symfony Releases and releases.json — https://symfony.com/releases, https://symfony.com/releases/7.4, https://symfony.com/releases/8.1, https://symfony.com/releases.json (8.1.11 stable, 7.4.23 LTS, 8.2.0-BETA1; PHP floors; support end dates)
- Symfony 8.1 curated new features — https://symfony.com/blog/symfony-8-1-curated-new-features (what 8.1 added)
- Symfony 8.0 upgrade notes — https://github.com/symfony/symfony/blob/8.1/UPGRADE-8.0.md (what 8.0 removed: XML config, `eraseCredentials()`, `#[TaggedIterator]`, `Request::get()`)
- Symfony 8.1 documentation: Testing, Controller, Routing, Service Container, Configuration, Security, Doctrine, Messenger, Forms, Templates, Validation, Best Practices — https://symfony.com/doc/8.1/testing.html, https://symfony.com/doc/8.1/controller.html, https://symfony.com/doc/8.1/routing.html, https://symfony.com/doc/8.1/service_container.html, https://symfony.com/doc/8.1/configuration.html, https://symfony.com/doc/8.1/security.html, https://symfony.com/doc/8.1/doctrine.html, https://symfony.com/doc/8.1/messenger.html, https://symfony.com/doc/8.1/forms.html, https://symfony.com/doc/8.1/templates.html, https://symfony.com/doc/8.1/validation.html, https://symfony.com/doc/8.1/best_practices.html
- Symfony 7.4 documentation: Doctrine, Messenger, Routing, Configuration, Templates, Upgrading a Major Version — https://symfony.com/doc/7.4/doctrine.html, https://symfony.com/doc/7.4/messenger.html, https://symfony.com/doc/7.4/routing.html, https://symfony.com/doc/7.4/configuration.html, https://symfony.com/doc/7.4/templates.html, https://symfony.com/doc/7.4/setup/upgrade_major.html (what the LTS line documents and which versions introduced a feature)
- Symfony PHPUnit Bridge, Yaml component and Coding Standards — https://symfony.com/doc/8.1/components/phpunit_bridge.html, https://symfony.com/doc/7.4/components/yaml.html, https://symfony.com/doc/current/contributing/code/standards.html (the bridge is current; `lint:yaml`; the Symfony standards are PSR-12 based and meant for contributions)
- Symfony recipes: phpunit/phpunit 11.1 and symfony/security-bundle — https://github.com/symfony/recipes/tree/main/phpunit/phpunit/11.1, https://github.com/symfony/recipes/tree/main/symfony/security-bundle (the shipped `phpunit.dist.xml` and the test-environment hasher)
- Packagist, current releases and PHP requirements — https://packagist.org/packages/symfony/framework-bundle, https://packagist.org/packages/doctrine/orm, https://packagist.org/packages/doctrine/dbal, https://packagist.org/packages/doctrine/doctrine-bundle, https://packagist.org/packages/doctrine/doctrine-migrations-bundle, https://packagist.org/packages/symfony/test-pack, https://packagist.org/packages/symfony/maker-bundle, https://packagist.org/packages/symfony/flex, https://packagist.org/packages/dama/doctrine-test-bundle, https://packagist.org/packages/phpstan/phpstan-symfony, https://packagist.org/packages/phpstan/phpstan-doctrine (Symfony 8.1.11, ORM 3.7.6, DBAL 4.5.0, DoctrineBundle 3.3.4 and 2.19.3, MigrationsBundle 4.0.1 and 3.7.1, test-pack 1.2.0, MakerBundle 1.68.0, Flex 2.12.0, DAMA 8.7.0, phpstan-symfony 2.1.1, phpstan-doctrine 2.1.2)
- DoctrineBundle 3.0 upgrade notes and command registration — https://github.com/doctrine/DoctrineBundle/blob/3.3.x/UPGRADE-3.0.md, https://github.com/doctrine/DoctrineBundle/blob/3.3.x/config/orm.php (PHP 8.4 floor, ORM 2 / DBAL 3 / annotation and YAML drivers dropped; `doctrine:schema:validate`)
- Doctrine ORM 3.7: upgrade notes and reference — https://github.com/doctrine/orm/blob/3.7.x/UPGRADE.md, https://github.com/doctrine/orm/blob/3.7.x/docs/en/reference/transactions-and-concurrency.rst, https://github.com/doctrine/orm/blob/3.7.x/docs/en/reference/dql-doctrine-query-language.rst, https://github.com/doctrine/orm/blob/3.7.x/docs/en/reference/batch-processing.rst, https://github.com/doctrine/orm/blob/3.7.x/docs/en/reference/architecture.rst, https://github.com/doctrine/orm/blob/3.7.x/docs/en/reference/basic-mapping.rst (final entities, `enumType`, native lazy objects, the Paginator deprecation, `wrapInTransaction`, fetch joins, batch clearing)
- Twig and TwigBundle — https://packagist.org/packages/twig/twig, https://github.com/symfony/symfony/blob/8.1/src/Symfony/Bundle/TwigBundle/CHANGELOG.md (Twig 3.30.0; the `twig.safe_class` tag arrived in 8.1)
- Symfony 8.1 documentation, further pages: Console, Clock, Event Dispatcher, Security Voters and CSRF, AssetMapper, Error Pages, Cache, HttpClient, Mailer, Autowiring, Tags, Form reference — https://symfony.com/doc/8.1/console.html, https://symfony.com/doc/8.1/components/clock.html, https://symfony.com/doc/8.1/event_dispatcher.html, https://symfony.com/doc/8.1/security/voters.html, https://symfony.com/doc/8.1/security/csrf.html, https://symfony.com/doc/8.1/frontend/asset_mapper.html, https://symfony.com/doc/8.1/service_container/autowiring.html, https://symfony.com/doc/8.1/service_container/tags.html, https://symfony.com/doc/8.1/reference/forms/twig_reference.html, https://symfony.com/doc/8.1/validation/custom_constraint.html, https://symfony.com/doc/8.1/doctrine/events.html, https://symfony.com/doc/8.1/controller/error_pages.html, https://symfony.com/doc/8.1/cache.html, https://symfony.com/doc/8.1/http_client.html, https://symfony.com/doc/8.1/mailer.html, https://symfony.com/doc/8.1/form/unit_testing.html, https://symfony.com/doc/8.1/reference/constraints/UniqueEntity.html, https://symfony.com/doc/8.1/configuration/secrets.html (invokable commands and `runCommand()`, the clock and `ClockSensitiveTrait`, voters, CSRF attributes, AssetMapper commands, `form_end`, Doctrine listeners)
- Symfony 6.4 Controller and 7.0 / 7.3 upgrade notes — https://symfony.com/doc/6.4/controller.html, https://github.com/symfony/symfony/blob/7.4/UPGRADE-7.3.md, https://github.com/symfony/symfony/blob/7.4/UPGRADE-7.0.md (`#[MapQueryString]` since 6.3; `eraseCredentials()` deprecated in 7.3; Doctrine annotations integration removed in 7.0)
- Symfony sources: HttpKernel attributes and BrowserKit — https://github.com/symfony/symfony/blob/8.1/src/Symfony/Component/HttpKernel/Attribute/WithHttpStatus.php, https://github.com/symfony/symfony/blob/8.1/src/Symfony/Component/BrowserKit/AbstractBrowser.php (`#[WithHttpStatus]`, `jsonRequest()`)
- Symfony recipes: framework-bundle 8.1 and doctrine-bundle 3.1 — https://github.com/symfony/recipes/tree/main/symfony/framework-bundle/8.1, https://github.com/symfony/recipes/tree/main/doctrine/doctrine-bundle/3.1 (default `services.yaml`, `when@test` framework and Doctrine config)
- DoctrineMigrationsBundle documentation — https://symfony.com/bundles/DoctrineMigrationsBundle/current/index.html (commands, `transactional`, the server-version note)
- PHP supported versions and PHPUnit supported versions — https://www.php.net/supported-versions.php, https://phpunit.de/supported-versions.html (8.2 security fixes end 2026-12-31; PHPUnit 13 needs PHP 8.4, 12 needs 8.3, 11 needs 8.2)
- PHP-CS-Fixer rule sets, phpstan-symfony and phpstan-doctrine READMEs — https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/doc/ruleSets/Symfony.rst, https://github.com/phpstan/phpstan-symfony, https://github.com/phpstan/phpstan-doctrine (`@Symfony` and `@PER-CS` sets; `containerXmlPath`; `objectManagerLoader`)
