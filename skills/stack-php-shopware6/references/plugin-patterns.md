# Shopware 6 — Plugin Patterns

The PHP side of a plugin: base class, services, subscribers, configuration, migrations, scheduled tasks, messages, routes.
The DAL (entities, repositories) is in `dal-patterns.md`, the Storefront in `storefront-patterns.md`, the Administration
in `administration-patterns.md`. Written for 6.7; 6.6 differences are marked.

## Layout and `composer.json`

Create a plugin with `shopware-cli extension create --type plugin --vendor Swag --name Example` (needs Shopware 6.7.13.0 or
newer) or `bin/console plugin:create SwagExample`; add single features with `shopware-cli extension add <generator>`
(`event-subscriber`, `scheduled-task`, `entity`, `store-api-route`, `storefront-controller`, `admin-module`, …). A generator
writes several files that belong together (class, `services.php`, `routes.php`) — never delete one of them alone.

```text
custom/static-plugins/SwagExample/        # project plugin, required through Composer; custom/plugins/ for Store plugins
├── composer.json
└── src/
    ├── SwagExample.php                   # extends Shopware\Core\Framework\Plugin
    ├── Resources/config/{services.php,routes.php,config.xml}
    ├── Resources/{views,app/storefront,app/administration,snippet}/
    ├── Migration/  Subscriber/  ScheduledTask/  Storefront/Controller/  Core/Content/<Entity>/  Service/
```

```json
{
    "name": "swag/example",
    "type": "shopware-platform-plugin",
    "version": "1.0.0",
    "require": { "shopware/core": "~6.7.0" },
    "extra": {
        "shopware-plugin-class": "Swag\\Example\\SwagExample",
        "label": { "en-GB": "Example", "de-DE": "Beispiel" }
    },
    "autoload": { "psr-4": { "Swag\\Example\\": "src/" } }
}
```

- `type` must be `shopware-platform-plugin` (an app is `shopware-app`, which is not a plugin); `extra.shopware-plugin-class`
  and `extra.label` are mandatory; the technical name never changes after release.
- The `shopware/core` constraint is the compatibility declaration: `~6.7.0` for the 6.7 line, `~6.6.0` for 6.6. A plugin
  with Administration code cannot serve 6.5 and 6.6 with one version (Vue 2 → Vue 3): ship a new major per line.
- Another plugin as a dependency goes into `require` with its Composer name; the required plugin must already be installed and active — Shopware refuses otherwise.

Commands: `bin/console plugin:refresh`, `plugin:install --activate SwagExample`, `plugin:update`, `plugin:deactivate`,
`plugin:uninstall`, then `cache:clear`. A static plugin must be `composer require`d before it can be installed.

## Lifecycle methods

Override only what is needed, on the `Plugin` base class: `install`, `postInstall`, `activate`, `deactivate`, `update`,
`postUpdate`, `uninstall` (each takes the matching context). Keep them small and idempotent.

- Do not create live business data in `install()`; create what can be switched off (a payment method) and activate it in
  `activate()`.
- `uninstall(UninstallContext $context)` removes the plugin's data — but check `$context->keepUserData()` first and do not
  delete rows that real orders reference (deactivate them).
- Migrations run automatically on install and update; do not put schema changes into a lifecycle method.

## Services (`src/Resources/config/services.php`)

PHP configuration is what the current docs show; it works on every line (the loader accepts XML, YAML and PHP). XML
(`services.xml`) is deprecated since 6.7.14.0 and not loaded in 6.8. `services_test.php` overrides services for the test
environment only.

```php
<?php declare(strict_types=1);

use Shopware\Core\System\SystemConfig\SystemConfigService;
use Swag\Example\Service\PriceLabelBuilder;
use Swag\Example\Subscriber\ProductSubscriber;
use Symfony\Component\DependencyInjection\Loader\Configurator\ContainerConfigurator;

use function Symfony\Component\DependencyInjection\Loader\Configurator\service;

return static function (ContainerConfigurator $configurator): void {
    $services = $configurator->services();

    $services->set(PriceLabelBuilder::class)
        ->args([service(SystemConfigService::class)]);

    $services->set(ProductSubscriber::class)
        ->tag('kernel.event_subscriber');
};
```

- Two styles: explicit `set()` with `->args([...])` (control, the generators' output) or `defaults()->autowire()->autoconfigure()`
  plus `load('Swag\\Example\\', '../../')->exclude('../../{Resources,Migration,*.php}')`. Pick one per plugin. Autoconfigure
  tags a class implementing `EventSubscriberInterface`; with explicit `set()` the tag is yours to add.
- Repositories are services named `<entity_name>.repository`: `service('product.repository')`, `service('swag_example.repository')`.
- Services are private; reach a public one only through injection. Decorate with `->decorate(Core::class)` and take
  `service('.inner')` — and only a service the core did not mark `@internal` or `@final`.

## Event subscribers

```php
final class ProductSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [ProductEvents::PRODUCT_WRITTEN_EVENT => 'onProductWritten'];
    }

    public function onProductWritten(EntityWrittenEvent $event): void
    {
        if ($event->getContext()->getVersionId() !== Defaults::LIVE_VERSION) {
            return;
        }
        // react to $event->getIds() / $event->getWriteResults()
    }
}
```

- A subscriber that is not registered and tagged `kernel.event_subscriber` is silently never called.
- DAL events follow `<entity>.loaded|written|deleted|search.result.loaded`, plus special classes such as `ProductEvents`.
  Versioned entities (products, orders) fire for every version: guard with `Defaults::LIVE_VERSION`.
- Subscribers observe and enrich; to change a control flow use an **extension point** (since 6.6.4.0; `Extension` events with `.pre`,
  `.post`, `.error` names; `$event->result = …; $event->stopPropagation();`) or decorate the service.
- Keep a listener fast: it runs in the request. Heavy work goes onto the queue (below).

## Configuration (`config.xml`)

`src/Resources/config/config.xml` is rendered in the Administration under the plugin; the schema is
`…/src/Core/System/SystemConfig/Schema/config.xsd` (set `xsi:noNamespaceSchemaLocation` for IDE completion).

```xml
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/shopware/shopware/trunk/src/Core/System/SystemConfig/Schema/config.xsd">
    <card>
        <title>General</title>
        <input-field type="text">
            <name>label</name>
            <label>Label</label>
            <label lang="de-DE">Bezeichnung</label>
        </input-field>
    </card>
</config>
```

Values are stored as `SwagExample.config.label`, per sales channel or globally; read them with
`SystemConfigService::getString('SwagExample.config.label', $salesChannelId)`. A value that changes cached Storefront
output may need `cache-relevant="true"` on its field — **since 6.7.12.0 only**: older config XSDs (6.6, 6.7.0 to 6.7.11) reject the
 attribute and the plugin fails to install; 6.8 makes it matter, because `SystemConfigService`'s `$silent` then defaults to `true`.
Grouping cards in `<tab>` elements exists since 6.7.16.0.

## Migrations (`src/Migration/`)

Name: `Migration<unix-timestamp><Description>.php`; create with
`bin/console database:create-migration -p SwagExample --name AddExampleTable`, or generate the SQL from definitions with
`bin/console dal:migration:create --bundle=SwagExample swag_example` (entities are a positional argument; the plugin must be active).

```php
<?php declare(strict_types=1);

namespace Swag\Example\Migration;

use Doctrine\DBAL\Connection;
use Shopware\Core\Framework\Migration\MigrationStep;

/** @internal */
class Migration1731000000AddExampleTable extends MigrationStep
{
    public function getCreationTimestamp(): int
    {
        return 1731000000;
    }

    public function update(Connection $connection): void
    {
        $connection->executeStatement(<<<'SQL'
CREATE TABLE IF NOT EXISTS `swag_example` (
    `id` BINARY(16) NOT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME(3) NOT NULL,
    `updated_at` DATETIME(3) NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL);
        // `name` is translated (dal-patterns.md), so it lives in the translation table
        $connection->executeStatement(<<<'SQL'
CREATE TABLE IF NOT EXISTS `swag_example_translation` (
    `swag_example_id` BINARY(16) NOT NULL,
    `language_id` BINARY(16) NOT NULL,
    `name` VARCHAR(255) COLLATE utf8mb4_unicode_ci NULL,
    `created_at` DATETIME(3) NOT NULL,
    `updated_at` DATETIME(3) NULL,
    PRIMARY KEY (`swag_example_id`, `language_id`),
    CONSTRAINT `fk.swag_example_translation.swag_example_id` FOREIGN KEY (`swag_example_id`)
        REFERENCES `swag_example` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk.swag_example_translation.language_id` FOREIGN KEY (`language_id`)
        REFERENCES `language` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL);
    }
}
```

- Put all schema and data changes in `update()`. **Plugin install and update never run `updateDestructive()`**; there is no
  rollback — cleanup belongs in `uninstall()`.
- Make a migration idempotent (`IF NOT EXISTS`, check the column first) and never edit one that has run: add a new one.
- UUID columns are `BINARY(16)`; every entity table has `created_at` and `updated_at`.
- One statement per `executeStatement()` outside the migration connection (6.8 rejects batches elsewhere); inside
  `update()` multiple statements still work.
- Test it: run `update()` twice on a database and compare `SHOW CREATE TABLE` (see `test-patterns.md`).

## Scheduled tasks

```php
class CleanupTask extends ScheduledTask
{
    public static function getTaskName(): string { return 'swag.example_cleanup'; }
    public static function getDefaultInterval(): int { return 3600; }   // seconds
}

#[AsMessageHandler(handles: CleanupTask::class)]
final class CleanupTaskHandler extends ScheduledTaskHandler
{
    public function run(): void { /* idempotent work */ }
}
```

```php
$services->set(CleanupTask::class)->tag('shopware.scheduled.task');
$services->set(CleanupTaskHandler::class)
    ->args([service('scheduled_task.repository'), service('logger')])
    ->tag('messenger.message_handler');
```

- Both halves need their tag; the task is stored in `scheduled_task` on plugin activation (or
  `bin/console scheduled-task:register`). Run `scheduled-task:run` to queue due tasks and `messenger:consume` to execute
  them (the Administration worker does it when enabled).
- Next run at a time you compute: implement `DynamicallyScheduledTaskHandler::getNextExecutionTime()` (since 6.7.13.0); in
  6.8 do not override the handler's reschedule hooks.

## Messages and the queue

A message is a serializable object; implementing `Shopware\Core\Framework\MessageQueue\AsyncMessageInterface` routes it to
the async queue (`LowPriorityMessageInterface` for the low-priority one, 6.5.7.0 and later); anything else is handled
synchronously. Dispatch through `MessageBusInterface` (service `messenger.default_bus`); handle with `#[AsMessageHandler]` on
a class with `__invoke`, tagged `messenger.message_handler`. Send ids, not entities.

## Routes and controllers

Every route needs a route scope in its defaults — `PlatformRequest::ATTRIBUTE_ROUTE_SCOPE`: `StorefrontRouteScope::ID`
(Storefront), `StoreApiRouteScope::ID` (Store API), `ApiRouteScope::ID` (Admin API). The attribute class is
`Symfony\Component\Routing\Attribute\Route` (6.5 still has `Symfony\Component\Routing\Annotation\Route`). Route names
start with `frontend.`, `widgets.`, `payment.` (Storefront), `store-api.` or `api.`. A controller is registered public with
`->call('setContainer', [service('service_container')])` and discovered through `routes.php`:

```php
return static function (RoutingConfigurator $routes): void {
    $routes->import('../../Storefront/Controller/*Controller.php', 'attribute');
};
```

- **Admin API** route: `#[Route(path: '/api/_action/swag-example/run', name: 'api.action.swag_example.run', defaults: [PlatformRequest::ATTRIBUTE_ROUTE_SCOPE => [ApiRouteScope::ID], PlatformRequest::ATTRIBUTE_ACL => ['swag_example:update']], methods: ['POST'])]`
  — the `_acl` default names the privilege(s) the route requires; add it to every Admin API route you write.
- **Store API** route: scope `store-api`, path `/store-api/…`, response extends `StoreApiResponse`; fields served through
  the API need the `ApiAware` flag in the definition. The docs' current example publishes the route body through
  `ExtensionDispatcher::publish()` with an `Extension` subclass (ADR 2026-09-24, "preferred" for new routes); the core's
  own routes on 6.7 still ship an `Abstract…Route` class with `getDecorated()` — decorate those by extending the abstract
  class, and check which form the project's neighbouring routes use.
- Storefront controller: `StorefrontController::renderStorefront('@SwagExample/storefront/page/x.html.twig', [...])`;
  an XHR route returns a `Response` rendered from a template without the layout. There is no CSRF token function any more
  (`sw_csrf` was removed): state-changing requests rest on the session cookie's `SameSite=lax` default (`framework.session.cookie_samesite`).
- Cache: a route is HTTP-cacheable only when its defaults carry `'_httpCache' => true`; the core then tags the response
  and invalidates it with the Store API cache tags of the data it loaded. Leave personal output uncached. Clear with
  `bin/console cache:clear:http`.

## Cart and checkout

Extend the cart with a `CartDataCollectorInterface` (tag `shopware.cart.collector`: loads data into the cart) and a
`CartProcessorInterface` (tag `shopware.cart.processor`: calculates prices); never write prices from a controller. Orders
change state through the state machine (`StateMachineRegistry`), not by writing a status column.

## Commands and long-running work

A console command is an ordinary Symfony `#[AsCommand]` class registered as a service (the `command` generator does the
wiring). In a long-running runtime services tagged `kernel.reset` are reset between requests from 6.8 (opt-in with the
`LONGRUNNING_ENVIRONMENT` feature flag in 6.7): keep no request state in a service property.
