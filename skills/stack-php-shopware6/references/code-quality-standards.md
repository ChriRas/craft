# Shopware 6 — Code Quality Standards

PHP essentials for the code of a Shopware 6 extension (plugin, app server, shop project). Written for the 6.7 line (PHP 8.2
to 8.5, Symfony 7.4 components) with the older 6.6 line marked. Use what the project's `require.php` floor and its
`shopware/core` constraint allow (`SKILL.md` → `## Existing Projects`).

## Mandatory shape

Shopware's own code opens a file with `<?php declare(strict_types=1);` on one line; neighbouring files of the project win
if they differ. A class that only receives services is `final` with a constructor:

```php
<?php declare(strict_types=1);

namespace Swag\Example\Service;

use Shopware\Core\System\SystemConfig\SystemConfigService;

final class PriceLabelBuilder
{
    public function __construct(private readonly SystemConfigService $config)
    {
    }

    public function build(string $salesChannelId): string
    {
        return $this->config->getString('SwagExample.config.label', $salesChannelId);
    }
}
```

- **Entities and structs are not `readonly`.** The DAL sets properties after construction, so every property of an
  `Entity`, `Collection` or other `Struct` subclass is at least `protected` and none is `readonly`. Services, subscribers,
  handlers and value objects built by a constructor are `final` and may be `readonly`.
- Dependencies are injected by constructor. No `$container->get()`, no static service access. A service is private by
  default; a controller is the exception (public, with `setContainer`, see `plugin-patterns.md`).
- Constructor promotion, backed enums, `match`, first-class callable syntax (`$this->_load(...)`), typed class constants
  (PHP 8.3) where the project's PHP floor allows them. 6.7 supports PHP 8.2 to 8.5 — do not use 8.3+ syntax in a plugin
  that declares 8.2.
- Name classes after the domain folder Shopware uses (`Core/Content/Example`, `Storefront/Controller`, `Subscriber`,
  `ScheduledTask`, `Migration`, `Service`); the plugin base class and `composer.json` autoload define the root namespace.

## Use the public API, not the internals

- Extend or call only what Shopware leaves open. A class marked `@internal` may change or disappear without deprecation
  and a class marked `@final` may be used but not extended (core guideline `final-and-internal`). Both marks are
  doc annotations, so nothing stops you at runtime — a code review has to.
- Pick the extension mechanism by intent, narrowest first: an **event** (observe: `kernel.event_subscriber`), an
  **extension point** (`Shopware\Core\Framework\Extensions\Extension`, since 6.6.4.0, a listener that may replace a result and stop
  propagation), a **service decoration** (change a service's behaviour; for a Store API route see `plugin-patterns.md`), a
  Twig block or an Administration component override for markup. Copying a core class and replacing the service is the
  last resort.
- Do not add a column to a core table (`product`, `order`, …): add your own table with a one-to-one association through an
  `EntityExtension`, or a custom field (`dal-patterns.md`). Core migrations are not yours to edit either.
- Prefix everything that is global with a vendor prefix: tables (`swag_example`), entity names, scheduled task names
  (`swag.example_task`), config keys (`SwagExample.config.*`), CSS classes, snippet keys, route names.

## Reading the request and the context

- Pass `Context` / `SalesChannelContext` down from the controller, the event or the message; do not create one with
  `Context::createDefaultContext()` in request code — only for console commands, migrations and tests. The default context
  skips the sales channel, language chain and ACL of the caller.
- `Request::get()` is gone in Symfony 8 and with it from Shopware 6.8: read `$request->attributes->get()` for route
  placeholders, `->query->get()` for the query string and `->request->get()` for form data (`->query->all('ids')` for
  arrays). Write new code that way on 6.7 too.
- Read plugin configuration through `SystemConfigService`, with the typed getters (`getString`, `getInt`, `getBool`,
  `getFloat`) and a sales-channel id. In 6.8 its `$silent` parameter defaults to `true`; do not rely on the old default.

## Errors and logging

- Throw an exception that carries a unique error code: Shopware's convention is a domain exception class with static
  factory methods extending `Shopware\Core\Framework\HttpException` (private constructor, a constant such as
  `SWAG_EXAMPLE__NOT_FOUND`, an HTTP status and a message with named parameters). Do not throw a bare `\Exception`
  or `\RuntimeException` out of a service that serves an API.
- Catch only what you can handle. Never swallow a `\Throwable` in a subscriber: a broken listener must not break the
  request unnoticed, and it must not hide the cause either — log with context and rethrow or return a defined fallback.
- Log through the injected PSR logger (`service('logger')`, or a dedicated Monolog channel); the plugin's log lines carry the
  entity id and the sales channel, never customer data or secrets.
- A scheduled task or message handler is retried by the queue: make it idempotent.

## Typing for PHPStan

`EntityRepository` is generic over the **collection**, not the entity:

```php
/**
 * @param EntityRepository<ProductCollection> $productRepository
 */
public function __construct(private readonly EntityRepository $productRepository)
{
}
```

- `search()->first()` returns `?Entity` and a not-loaded association is `null`: add the association to the `Criteria`, check
  `=== null` and throw a domain exception, so PHPStan and the reader both see the failure path.
- Type a custom collection with `@extends EntityCollection<ExampleEntity>` and give the definition `getEntityClass()` and
  `getCollectionClass()`.

## Tooling

| Tool | Use |
|---|---|
| PHPStan 2.x | Level and baseline from the project. Shopware's rules: `shopwarelabs/phpstan-shopware` (0.2.5, PHP ^8.2, PHPStan ^2.1.7). `phpstan-symfony` needs `containerXmlPath` — core points it at the dumped container of a static-analysis kernel |
| PHP-CS-Fixer | Shopware core runs `friendsofphp/php-cs-fixer` (3.95 on trunk); a plugin follows its own `.php-cs-fixer.dist.php` or `ecs.php` |
| `shopware-cli extension validate <dir>` | Runs the built-in checks (metadata, icon, snippets, PHP lint, packaging) plus PHPStan, ESLint, Stylelint and the Storefront Twig linter; `--only builtin` for the cheap subset; `shopware-cli extension fix` converts deprecated `services.xml` / `routes.xml` to YAML (still loaded in 6.8) |
| `bin/console cache:clear` | After any change of service configuration, routes or Twig templates — a stale cache is the usual reason a new file "does nothing" |
| `bin/console dal:validate` | "Validates the DAL definitions" (the command's own description) — run it against the dev database after changing a definition |

## 6.8 readiness (write for it now)

Shopware 6.8 is announced for 2027-06-01 and raises PHP to 8.5, Symfony to 8.x, Twig to 4.x and PHPUnit to 13. What a
plugin should avoid today:

- XML service or route files (`services.xml`, `routes.xml`): deprecated from 6.7.14.0, not loaded in 6.8 — write
  `services.php` / `routes.php` by hand or with the generators (`shopware-cli extension fix` converts old files to YAML, not to PHP).
- `Request::get()`, `parent::__construct()` in an `EntityDefinition` subclass (the constructor is removed), overriding the
  `ScheduledTaskHandler` hooks `markTaskRunning()`, `markTaskFailed()`, `rescheduleTask()`, several SQL statements in one
  `executeStatement()` outside a migration, and state that must survive between requests in a long-running runtime.
- Every deprecation the shop logs: fix them as they appear, do not batch them for the major.

## Checklist

- [ ] `declare(strict_types=1)`, `final` services, constructor injection, nothing reads the container.
- [ ] No `@internal` class used, no core table altered, everything global has the vendor prefix.
- [ ] `Context` comes from the caller; `first()` and associations are null-checked.
- [ ] A handler, subscriber or migration is idempotent and survives a second run.
- [ ] PHPStan and `shopware-cli extension validate` are green; `cache:clear` was run before judging a result.
