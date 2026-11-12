# API Platform — Code Quality Standards

PHP and Symfony essentials for the code around an API Platform resource. Written for API Platform 5.0 on Symfony 8.1 (PHP
8.4) with the 7.4 LTS differences marked. Use what the project's `require.php` floor and Symfony line allow
(`SKILL.md` → `## Existing Projects`): API Platform 5.0 itself needs PHP 8.2 and Symfony 7.4 or 8.x; Symfony 8.x needs
PHP 8.4.

## Mandatory shape

Every new PHP file follows PER Coding Style (`declare` directly after the opening tag, four-space indent, a trailing comma
in every multi-line list). Providers, processors, voters, filters, extensions and Messenger handlers are `final`, take
their dependencies by constructor and do one job:

```php
<?php

declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;

/** @implements ProcessorInterface<Invoice, Invoice> */
final readonly class IssueInvoiceProcessor implements ProcessorInterface
{
    public function __construct(private InvoiceNumbers $numbers) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): Invoice
    {
        $data->number = $this->numbers->next();

        return $data;
    }
}
```

- A class that only receives services is `final readonly` (PHP 8.2). A **resource class is not readonly**: the serializer
  fills its properties after construction, and a `PATCH` or `PUT` writes into an existing instance, which a readonly
  property cannot take. `readonly` suits what is always built by a constructor: output DTOs, messages, value objects.
- A Doctrine entity may be `final` only with native lazy objects: on PHP 8.4 DoctrineBundle 3 always uses them (no
  generated proxy classes); before that (bundle 2.x, PHP below 8.4) keep entities non-final so Doctrine can generate
  proxies. An entity that is also a resource is never readonly (above).
- One class per file named after the class; `App\` maps to `src/`, `App\Tests\` to `tests/` (PSR-4).

## Language idioms

- **Types** — a type on every parameter, return value and property; union types where they say what the code means;
  `never` for a function that always throws. The metadata system reads the PHP types (through `symfony/type-info`) to
  build the JSON Schema, the OpenAPI document and the Hydra context, so an untyped property is an undocumented one.
- **Enums** — backed enums for every closed set; mapped in Doctrine with `enumType:`; an enum property needs an explicit
  validation constraint (`SKILL.md`, `resource-patterns.md` → Validation).
- **Attributes first** — `#[ApiResource]`, `#[ORM\...]`, `#[Assert\...]`, `#[Groups]`, `#[Autowire]`, `#[AsAlias]`,
  `#[AsEventListener]`, `#[AsCommand]`: one language for wiring, next to the code it configures. `#[\Override]` (PHP 8.3)
  on every method that overrides or implements.
- **Property hooks and asymmetric visibility (PHP 8.4)** — `public private(set) int $id` is what the API Platform docs use
  for a Doctrine entity id and keeps it read-only for the serializer's writes through the API. On a Doctrine entity only a
  backed hooked property maps (ORM 3.4+), so keep hooks off entities unless the project already uses them.
- **Serializer attributes** live in `Symfony\Component\Serializer\Attribute\` (`Groups`, `SerializedName`, `Ignore`,
  `MaxDepth`). The `Annotation\` namespace still appears in the API Platform docs; it exists on 7.4 (deprecated) and is
  gone from 8.x — write the `Attribute\` import.
- **Clock and time** — inject `Symfony\Component\Clock\ClockInterface`; never `new \DateTimeImmutable()` or `time()` in
  business logic. Resource date properties are `\DateTimeImmutable`.
- **Constructor promotion and named arguments** — attributes are written with named arguments
  (`new GetCollection(paginationItemsPerPage: 50)`); filters inside a `QueryParameter` always take named arguments, the
  docs warn that filter constructors change between versions.
- **First-class callables** — `$this->handle(...)` instead of `Closure::fromCallable`.

## Checklist

- `declare(strict_types=1)` is the first statement; no `mixed` unless the value really is open (the state interfaces' own
  `process(mixed $data, ...)` signature is the exception — narrow it with `@implements` and an `instanceof` check).
- The resource class declares the **public shape** of the API; business logic is in a service or a processor, never in the
  resource, a validator or a normalizer.
- Dependencies come in by constructor, typed as the class or an interface; `#[Autowire]` for a scalar, a parameter, an env
  var or a named service (the built-in Doctrine providers and processors). No `ContainerInterface`, no static access.
- Services are stateless (a long-running worker or FrankenPHP worker mode reuses them); no per-request data in a property.
- Config values are read where they are wired (`services.yaml`, `#[Autowire(env: '...')]`), never via `$_ENV` or
  `getenv()` in domain code.
- Output (`echo`, `dump`, `dd`, `var_dump`) does not stay in committed code; log through `Psr\Log\LoggerInterface`.
- No `@` error suppression, no `eval`, no `extract()`, no `global`. Comparisons are strict.
- `php bin/console lint:container`, `lint:yaml`, `doctrine:schema:validate`, PHPStan, the fixer's check and the test suite
  run clean before the work is called done.

## Error handling

- Throw exceptions; do not return `false` / `null` for failure — except a provider, where `null` means "not found" and
  API Platform answers 404 (`resource-patterns.md`).
- The status of a thrown exception is decided in this order (errors docs): `exception_to_status` in
  `config/packages/api_platform.yaml` (a global map, or `exceptionToStatus:` on a resource or operation), then Symfony's
  `HttpExceptionInterface` status (`NotFoundHttpException`, `AccessDeniedHttpException`), then a
  `ProblemExceptionInterface` status, then the validation / request defaults, then 500. Prefer a Symfony HTTP exception
  or a mapped domain exception; do not build an error response by hand.
- A status of 500 or above hides the exception message outside debug mode; any other status sends it to the client, so a
  message for a 4xx contains nothing internal.
- Wrap, do not swallow: `throw new ImportFailed('...', previous: $e)`. Catch the narrowest type at the layer that can act.
- Validate at the boundary (resource or input DTO constraints), then pass typed objects inward; do not re-validate per layer.

## Symfony essentials

- **Layout** — `config/{packages/, routes/, services.yaml}`, `src/{Entity/, ApiResource/, State/, Security/, Doctrine/,
  Filter/, Serializer/}`, `tests/`, `migrations/`, `.env` and `.env.test` (committed; `.env.local` never). The Flex recipe
  creates `src/ApiResource/` for resources that are not entities.
- **Dependency injection** — `config/services.yaml` ships with `autowire: true`, `autoconfigure: true` and
  `App\: {resource: '../src/'}`; every class in `src/` is a service. Autoconfiguration tags voters, Doctrine extensions,
  state providers and processors, normalizers and listeners from their interface or attribute. One implementation of an
  interface autowires on its own; with several, mark the default with `#[AsAlias]` and pick another with `#[Target]`.
- **Per-machine values** (DSNs, hosts) are env vars; secrets go through `bin/console secrets:set`; per-environment
  config lives in `when@test:` / `when@prod:` blocks or `config/packages/<env>/`. Services stay private — read one from a
  test through the test container.
- **Configuration format** — YAML is what the recipes write; PHP config is the typed alternative; XML configuration is gone
  in Symfony 8.0 (**7.4** still accepts it). Keep the project's format.
- **Doctrine** — attribute mapping, a migration per schema change (`make:migration`, read the SQL), never
  `doctrine:schema:update --force` against a shared database. ORM 3.7 with DBAL 4 through DoctrineBundle 3.3 (needs PHP
  8.4; 2.19 for PHP 8.1 to 8.3). API Platform's `api-platform/doctrine-orm` 5.0 accepts ORM `^2.17 || ^3.3`.
- **Security** — SecurityBundle: one firewall unless two authentication systems differ, `lazy: true` on a session firewall,
  `stateless: true` on a token API, password hashers on `auto` with the user repository as `PasswordUpgraderInterface`,
  `access_control` for URL prefixes, a voter for any rule about a specific object. `UserInterface::eraseCredentials()` is
  required up to 7.4 and removed in 8.0.
- **Messenger** for work after the response (`#[AsMessageHandler]`, a message carries ids and scalars never an entity,
  idempotent handlers, `failure_transport`); **Clock**, **HttpClient**, **Mailer** and **Cache** through their interfaces
  instead of `time()`, `curl_*`, `mail()` or static caches.
- Console commands are `#[AsCommand]` classes delegating to a service.

## Static analysis — PHPStan

```neon
# phpstan.neon.dist
parameters:
    level: max
    paths:
        - src
        - tests
    symfony:
        containerXmlPath: var/cache/dev/App_KernelDevDebugContainer.xml
```

- Install with `composer require --dev phpstan/phpstan phpstan/phpstan-symfony phpstan/phpstan-doctrine
  phpstan/phpstan-phpunit phpstan/extension-installer`; run `vendor/bin/phpstan analyse`. `phpstan-symfony` reads the
  compiled container, so `var/cache/dev` must be warmed (`php bin/console cache:warmup`).
- A new project starts at `max`. An existing codebase starts at the highest level it passes and raises it; what it cannot
  fix yet goes into a baseline (`--generate-baseline`) that only shrinks. Prefer `@phpstan-ignore <identifier>` on one
  line, with the reason, over a broad `ignoreErrors` pattern.
- Type state classes with `@implements ProviderInterface<Book|null>` / `ProcessorInterface<In, Out>` — the generics
  are what the docs show, and PHPStan then checks `$data`.

## Code style — PER Coding Style

Default for a new project: PHP-CS-Fixer's `@PER-CS` set (as of 2026-11-09 it resolves to the 3.0 rules; pin `@PER-CS3x0`
for stable output). The `@Symfony` set is the Symfony project's own, PSR-12 based; a project that runs it keeps it.
`vendor/bin/php-cs-fixer check --diff` reports, `fix` rewrites; wire lint, analysis, style and tests into one
`composer qa` script. Do not hand-format.

## Framework linters and API commands

- `php bin/console lint:container` — service definitions resolve; run it in CI.
- `php bin/console lint:yaml config/` — YAML syntax; `doctrine:schema:validate` — mapping valid, schema in sync.
- `php bin/console debug:router` lists the routes API Platform registered for each operation; `debug:container <id>` and
  `debug:autowiring <name>` answer "why is this not wired".
- `php bin/console api:openapi:export` dumps the OpenAPI document (add `--output=openapi.json`); commit it or diff it in CI
  to see a contract change in review (`format-patterns.md`).
