---
name: stack-php-api-platform
description: CRAFT stack-pack for API Platform on Symfony — the current line (5.0) with the 4.4 differences marked: resources (entity or DTO), state providers and processors, operations, validation and security, filters and pagination, formats (JSON-LD/Hydra, OpenAPI, JSON:API, HAL, JSON Merge Patch), GraphQL, Mercure, and ApiTestCase tests with PHPUnit. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — API Platform

The code-near personality layer for an API Platform API on Symfony — a PHP class becomes a REST (and optionally GraphQL)
API with Hydra and OpenAPI documentation — written for the current line (API Platform 5.0 on Symfony 8.1) with the 4.4
and 7.4 LTS differences marked. It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`,
`/craft:refactor` and `/craft:review` when `rules.md` declares it in its `## Personality` block. A Laravel app declares
`stack-php-laravel`, a Symfony app without API Platform resources `stack-php-symfony` (a pack is monolithic: the Symfony
and PHP idioms are restated here). Project-specific conventions — domain rules, exact commands, the supported API Platform
range — live in the project's own `rules.md`, not here. Versions below were verified on 2026-11-09 (see `## Sources`).

## Stack

- **API Platform** — 5.0 is the current stable line (5.0 since 2026-09-16, current 5.0.6 of 2026-11-06; requires PHP 8.2 and Symfony 7.4 or 8.x).
  4.4 is the last 4.x minor (4.4.7 of 2026-11-06, same Symfony and PHP floors): same features as 5.0 plus the deprecations 5.0 removes, so
  it is the upgrade path. 4.3 still allows Symfony 6.4. The published policy (a minor every six months, a major every two
  years, a stable and a security-only old-stable branch) still named 4.3 and 4.2 on 2026-11-09: read 5.0 as stable and 4.4
  as the previous branch, and check the releases page before promising support to a client.
- **Framework** — Symfony 8.1 (8.1.11, needs PHP 8.4) or the 7.4 LTS (7.4.23, PHP 8.2), Doctrine ORM 3.7 with DoctrineBundle
  3.3; `api-platform/doctrine-orm` accepts ORM `^2.17 || ^3.3`. Attribute mapping only; `make:migration` generates migrations.
- **Install** — `composer require api` brings `api-platform/symfony`, `api-platform/doctrine-orm`, Security, Validator,
  Serializer, Twig and Nelmio CORS, and a Flex recipe that mounts the routes at `/api` and creates `src/ApiResource/`. Add on
  demand: `api-platform/json-api`, `api-platform/hal`, `api-platform/graphql`, `symfony/mercure-bundle`,
  `symfony/object-mapper` (DTO resources) and `api-platform/test` (dev).
- **Language** — PHP 8.4 or newer on Symfony 8.x, 8.2 or newer on 7.4: `declare(strict_types=1)`, typed public properties
  on resources, backed enums, attributes for resources, mapping, validation, security and wiring.
- **Tests** — `ApiPlatform\Test\ApiTestCase` from `api-platform/test` with PHPUnit (13 on PHP 8.4), its HttpClient-style
  test client and JSON assertions, run as `php bin/phpunit`. A project on Behat: see `## Existing Projects`.
- **Quality** — PHPStan 2.x with `phpstan-symfony` and `phpstan-doctrine`, PHP-CS-Fixer (`@PER-CS`), `lint:container`,
  `doctrine:schema:validate`, and `api:openapi:export` as the contract diff.

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.json`, `composer.lock` (the
`api-platform/core` or `api-platform/symfony` version), `config/packages/api_platform.yaml` and an existing resource first
and follow what they declare:

- **An older API Platform major or minor** — write to that line's API and plan an upgrade one minor at a time, deprecations
  first (`api:upgrade-resource` from 2.7, `api:upgrade-filter` from 4.4); never raise the line unasked.
  **2.x**: `ApiPlatform\Core\` classes, `itemOperations` / `collectionOperations`, data providers and data persisters
  (`ProviderInterface` / `ProcessorInterface` replaced them in 3.0, and data transformers gave way to `input` / `output`).
  **3.x** (PHP 8.1, Symfony 6.4 or 7.1): state providers and processors, but `hydra:`-prefixed keys, `keep_legacy_inflector`,
  `event_listeners_backward_compatibility_layer` and `use_symfony_listeners` flags to read before touching events or errors.
  **4.0 to 4.3**: no `throwOnNotFound`, runtime status or `QUERY` before 4.4, no `routePriority` before 5.0, no parameter
  filters before 4.2.
  **4.4**: the 5.0 removals are still deprecations. **5.0**: tests moved to `api-platform/test`, `use_iri_as_id` is false.
- **Legacy filters** — `#[ApiFilter]`, `SearchFilter`, `OrderFilter`, `RangeFilter` in the project's resources: keep them
  and write a neighbouring filter in the same style; use `QueryParameter` filters only on 4.2 or newer, and migrate a
  resource only when the slice touches it.
- **Entity as resource or DTO resource** — keep each resource's existing shape; do not split an entity from its resource or
  merge them unasked (`references/resource-patterns.md` has the criterion for new resources).
- **YAML or XML resources, event listeners, custom controllers** — `config/api_platform/*.yaml` and `*.xml` are valid on every
  line; `use_symfony_listeners: true`, `controller:` operations and kernel-event subscribers stay as they are, and new
  behaviour goes into a provider or processor.
- **Behat or plain HTTP-client tests instead of `ApiTestCase`** — `behat/behat` in `require-dev`, a `behat.yml.dist` and
  `features/`, or `WebTestCase` classes using `jsonRequest()`: use the project's runner and style, add no second one. On 4.x
  the test class lives at `ApiPlatform\Symfony\Bundle\Test\ApiTestCase`.
- **Symfony below 7.4, annotations, no Flex, Pest, another code style** — the Symfony floors above apply; for the rest
  follow the project's files and never reformat what the slice does not touch.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP 8.2 to 8.5 idioms, Symfony essentials (DI, config, Doctrine, security,
  Messenger), error handling, PHPStan, PHP-CS-Fixer and the linters.
- `references/resource-patterns.md` — entity or DTO (the criterion), providers and processors, operations, validation,
  security, serialization, errors.
- `references/query-patterns.md` — parameters and filters, extensions, pagination, eager loading, the `QUERY` operation.
- `references/format-patterns.md` — content negotiation, JSON-LD / Hydra, OpenAPI, JSON:API, HAL, JSON Merge Patch.
- `references/graphql-mercure.md` — the GraphQL endpoint and its separate security, Mercure updates and their tests.
- `references/test-patterns.md` — `ApiTestCase`, the client, API assertions, database isolation, what to test per resource.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Dependencies and configuration — `composer require`, `api_platform.yaml` (formats, defaults), env vars.
2. Model — Doctrine entities and enums, then `make:migration` and review the SQL; a DTO resource and its `stateOptions` if it
   diverges from the entity.
3. Resource declaration — explicit operations, serialization groups, validation constraints, `security` on every operation.
4. Behaviour — providers, processors, Doctrine extensions, parameters and filters, pagination limits.
5. Security — firewall, voters; formats and the OpenAPI export; GraphQL and Mercure only if the slice needs them.
6. Tests — alongside each layer; PHPStan, the linters, the fixer and `php bin/phpunit` pass before a layer counts as done.

## Anti-Patterns

- An entity exposed with groups on every property to fake a second API shape, or an API that mirrors a table that has
  non-CRUD behaviour; business logic in the resource class, a validator, a normalizer or a kernel listener.
- Declaring one operation (a lone `#[GetCollection]` next to `#[ApiResource]` counts) and losing the defaults unseen; a write
  operation without `security`; a voter used to filter a collection (use a Doctrine extension).
- Copying the docs' older snippets: `Serializer\Annotation\Groups` (gone in Symfony 8), `ApiPlatform\Symfony\Bundle\Test\ApiTestCase`
  in 5.0 code, a voter on `Security\Core\Security`, `; charset=utf-8` in a JSON content-type assertion.
- `#[ApiFilter]`, `SearchFilter`, `RangeFilter` in new code; a `QueryParameter` filter without `property`; a client-set page
  size with no maximum; GraphQL operations with no `security` of their own (REST rules do not carry over); public Mercure
  updates carrying private data; more formats than clients use (an unsupported Accept is 406, a Content-Type 415).
- Entities returned in a Messenger message or an event; a processor that persists with its own `flush()` instead of the
  persist processor; `flush()` in a loop; lazy associations read in a loop; schema changes without a reviewed migration.
- Tests that boot a client for a pure unit, share state through the database, hard-code generated ids, or assert only the
  status and not the error body.

## Sources

> As of: 2026-11-09 · Basis: research

- API Platform releases, maintenance and security policy, upgrade guide, configuration — https://api-platform.com/docs/extra/releases/, https://api-platform.com/docs/extra/security/, https://github.com/api-platform/core/releases, https://api-platform.com/docs/core/upgrade-guide/, https://api-platform.com/docs/core/configuration/, https://api-platform.com/docs/llms.txt (5.0.0 and 4.4.0 on 2026-09-16; the policy page names 4.3 as stable; 4.4 to 5.0 removals and renames, 3.0 providers / processors, the current docs are 5.0)
- API Platform core docs: operations, state providers, state processors, DTOs, design, extensions, identifiers, subresources — https://api-platform.com/docs/core/operations/, https://api-platform.com/docs/core/state-providers/, https://api-platform.com/docs/core/state-processors/, https://api-platform.com/docs/core/dto/, https://api-platform.com/docs/core/design/, https://api-platform.com/docs/core/extensions/, https://api-platform.com/docs/core/identifiers/, https://api-platform.com/docs/core/subresources/ (default operations, entity or DTO, stateOptions, Object Mapper, composition with the Doctrine services)
- API Platform core docs: filters, Doctrine filters, pagination, default order, performance — https://api-platform.com/docs/core/filters/, https://api-platform.com/docs/core/doctrine-filters/, https://api-platform.com/docs/core/pagination/, https://api-platform.com/docs/core/default-order/, https://api-platform.com/docs/core/performance/ (QueryParameter filters, ComparisonFilter, SortFilter, RangeFilter deprecation, paging settings, eager loading, QUERY)
- API Platform core docs: content negotiation, serialization, errors, OpenAPI, JSON:API, JSON Schema, GraphQL, Mercure, events — https://api-platform.com/docs/core/content-negotiation/, https://api-platform.com/docs/core/serialization/, https://api-platform.com/docs/core/errors/, https://api-platform.com/docs/core/openapi/, https://api-platform.com/docs/core/jsonapi/, https://api-platform.com/docs/core/json-schema/, https://api-platform.com/docs/core/graphql/, https://api-platform.com/docs/core/mercure/, https://api-platform.com/docs/core/events/ (formats, charset note, error mapping, OpenAPI 3.2.0, the 5.0 JSON:API id)
- API Platform Symfony docs: getting started, security, validation, testing, messenger, controllers, user, JWT — https://api-platform.com/docs/symfony/, https://api-platform.com/docs/symfony/security/, https://api-platform.com/docs/symfony/validation/, https://api-platform.com/docs/symfony/testing/, https://api-platform.com/docs/symfony/messenger/, https://api-platform.com/docs/symfony/controllers/, https://api-platform.com/docs/symfony/user/, https://api-platform.com/docs/symfony/jwt/ (security expressions, validation groups, 422 versus 400, ApiTestCase, assertions)
- API Platform source, 5.0 branch — https://github.com/api-platform/core/blob/5.0/src/Symfony/Bundle/DependencyInjection/Configuration.php, https://github.com/api-platform/core/blob/5.0/src/Metadata/Resource/Factory/OperationDefaultsTrait.php, https://github.com/api-platform/core/blob/5.0/src/State/Util/HttpResponseHeadersTrait.php, https://github.com/api-platform/core/blob/5.0/src/State/Provider/ContentNegotiationProvider.php, https://github.com/api-platform/core/blob/5.0/src/Test/ApiTestCase.php, https://github.com/api-platform/core/blob/5.0/src/Test/Client.php, https://github.com/api-platform/core/blob/5.0/src/Test/ApiTestAssertionsTrait.php, https://github.com/api-platform/core/blob/5.0/src/Symfony/Bundle/Resources/config/doctrine_orm.php (config defaults, default operations, no charset on JSON, 406 and 415, test client, Doctrine service ids)
- API Platform Flex recipe and the Mercure recipe — https://github.com/symfony/recipes/tree/main/api-platform/symfony/4.0, https://github.com/symfony/recipes/tree/main/symfony/mercure-bundle/0.6, https://raw.githubusercontent.com/symfony/recipes/flex/main/index.json (the `api` alias, `/api` prefix, `src/ApiResource`, the Mercure env vars)
- Packagist, API Platform and companion releases and requirements — https://packagist.org/packages/api-platform/core, https://packagist.org/packages/api-platform/symfony, https://packagist.org/packages/api-platform/doctrine-orm, https://packagist.org/packages/api-platform/test, https://packagist.org/packages/api-platform/json-api, https://packagist.org/packages/api-platform/hal, https://packagist.org/packages/api-platform/graphql, https://packagist.org/packages/symfony/object-mapper, https://packagist.org/packages/symfony/mercure-bundle, https://packagist.org/packages/webonyx/graphql-php, https://packagist.org/packages/dama/doctrine-test-bundle, https://packagist.org/packages/zenstruck/foundry, https://packagist.org/packages/justinrainbow/json-schema, https://packagist.org/packages/lexik/jwt-authentication-bundle, https://packagist.org/packages/behat/behat (core 5.0.6 and 4.4.7, PHP and Symfony floors, 4.3 with Symfony 6.4, separate JSON:API and HAL packages; behaviour marked as probed was run on a project from `composer require api` on Symfony 8.1.11, API Platform 5.0.6, 2026-11-09)
- Symfony releases, 8.0 upgrade notes and 8.1 documentation (Service Container, Configuration, Security, Voters, Validation, Doctrine, Messenger, Testing, Best Practices) — https://symfony.com/releases, https://symfony.com/releases.json, https://github.com/symfony/symfony/blob/8.1/UPGRADE-8.0.md, https://github.com/symfony/symfony/blob/8.1/src/Symfony/Component/Serializer/Attribute/Groups.php, https://symfony.com/doc/8.1/service_container.html, https://symfony.com/doc/8.1/configuration.html, https://symfony.com/doc/8.1/security.html, https://symfony.com/doc/8.1/security/voters.html, https://symfony.com/doc/8.1/validation.html, https://symfony.com/doc/8.1/doctrine.html, https://symfony.com/doc/8.1/messenger.html, https://symfony.com/doc/8.1/testing.html, https://symfony.com/doc/8.1/best_practices.html (8.1.11 stable, 7.4.23 LTS, PHP floors, the Attribute namespace; DI, env vars and secrets, firewalls, voters, constraints, migrations)
- PHP, PHPUnit, PHP-CS-Fixer, PHPStan extensions and the RFCs — https://github.com/doctrine/orm/blob/3.7.x/UPGRADE.md, https://github.com/doctrine/DoctrineBundle/blob/3.3.x/UPGRADE-3.0.md, https://packagist.org/packages/doctrine/orm, https://packagist.org/packages/doctrine/doctrine-bundle, https://www.php.net/supported-versions.php, https://phpunit.de/supported-versions.html, https://packagist.org/packages/phpunit/phpunit, https://packagist.org/packages/symfony/test-pack, https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/doc/ruleSets/PER-CS.rst, https://github.com/phpstan/phpstan-symfony, https://github.com/phpstan/phpstan-doctrine, https://www.rfc-editor.org/rfc/rfc10008.html, https://www.rfc-editor.org/rfc/rfc7396.html (8.2 security fixes end 2026-12-31; PHPUnit 13 needs PHP 8.4, 12 needs 8.3, 11 needs 8.2; `@PER-CS`; `containerXmlPath`; the QUERY method of June 2026; the merge-patch media type; ORM 3.7.6, DoctrineBundle 3.3.4, PHP 8.4 floor, property hooks on entities)

