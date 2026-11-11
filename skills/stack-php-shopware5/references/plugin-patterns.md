# Shopware 5 — Plugin Patterns (the 5.2+ plugin system)

The 5.2+ system is the one for new plugins: a Symfony-style bundle with a base class, `Resources/*.xml` and a DI container.
The older `Bootstrap.php` system is in `legacy-plugin-patterns.md`; both are installed side by side by the same
plugin manager. Facts below hold for 5.7.20 unless a version is named.

## Layout

```
custom/plugins/SwagOrderNote/
├── SwagOrderNote.php          # class SwagOrderNote extends Shopware\Components\Plugin
├── plugin.xml                 # label, version, compatibility, changelog, requiredPlugins
├── composer.json              # optional; "type": "shopware-plugin"
├── Resources/
│   ├── services.xml           # the container configuration (XML only in 5.x)
│   ├── config.xml  menu.xml  cronjob.xml
│   ├── snippets/  views/  frontend/{css,js,less}/  migrations/
├── Components/  Subscriber/  Models/  Commands/  Controllers/{Frontend,Widgets,Backend,Api}/
└── Tests/
```

- `custom/plugins/` holds shared plugins; `custom/project/` project-specific ones. The namespace and the class name equal
  the directory name, with no extra path parts. Names carry a developer prefix (`Swag…`, your own).
- `plugin.xml`: `<version>` must be accepted by PHP's `version_compare()` (`1.0.0`, not `v1.0`), `<compatibility
  minVersion="5.6.0"/>` (never below 5.2.0), one `<changelog version>` per release with `lang` texts, and
  `<requiredPlugins>` for plugin dependencies. The element order must match `plugin.xsd`, or the install throws; install
  with `-v` to see the message.
- A Composer-installed plugin uses `"type": "shopware-plugin"` (target `custom/plugins/{$name}/`, composer/installers);
  a legacy one `shopware-frontend-plugin`, `shopware-backend-plugin` or `shopware-core-plugin` (target
  `engine/Shopware/Plugins/Local/<Section>/{$name}/`); a theme `shopware-frontend-theme` (`themes/Frontend/{$name}/`).

## Base class and lifecycle

```php
class SwagOrderNote extends Plugin
{
    public function install(InstallContext $context): void
    {
        $this->container->get('shopware_attribute.crud_service')
            ->update('s_order_attributes', 'swag_note', TypeMapping::TYPE_STRING);
    }

    public function update(UpdateContext $context): void
    {
        if (version_compare($context->getCurrentVersion(), '1.1.0', '<')) {
            // changes introduced in 1.1.0
        }
    }

    public function uninstall(UninstallContext $context): void
    {
        if ($context->keepUserData()) {
            return;
        }
        $this->container->get('shopware_attribute.crud_service')->delete('s_order_attributes', 'swag_note');
        $context->scheduleClearCache(UninstallContext::CACHE_LIST_ALL);
    }

    public function activate(ActivateContext $context): void
    {
        $context->scheduleClearCache(ActivateContext::CACHE_LIST_ALL);
    }
}
```

- Order on install: `plugin.xml` requirements checked, `config.xml`, `menu.xml`, `cronjob.xml` and `Resources/snippets`
  synchronised, then **migrations**, then `install()`. Update runs the same sequence with `update()`. Uninstall removes the
  plugin's menu entries, cron jobs and event registrations itself, and its form too unless `--secure` keeps the data.
- `keepUserData()` is true for `sw:plugin:uninstall --secure`: leave data tables and attributes alone then.
- `scheduleClearCache()` takes `CACHE_LIST_DEFAULT`, `CACHE_LIST_ALL`, `CACHE_LIST_FRONTEND` or single tags
  (`CACHE_TAG_CONFIG`, `_HTTP`, `_PROXY`, `_ROUTER`, `_TEMPLATE`, `_THEME`); the argument is an array:
  `scheduleClearCache([InstallContext::CACHE_TAG_CONFIG])`. Clear what the change touches.
- An install or update that cannot proceed throws an exception; its message is shown to the shop owner.
- Compare versions with `version_compare()` against the version *being left*; every branch must be safe to run on a
  shop that skipped releases.

## Migrations (5.6.0 and later)

`Resources/migrations/<n>-<name>.php`, created by `bin/console sw:generate:migration <name-in-camelCase> -p SwagOrderNote`
(it numbers the next file and dashes the name). Run on install and on update, in order, before `install()` / `update()`;
the applied numbers sit in `s_plugin_schema_version`.

```php
namespace SwagOrderNote\Migrations;

use Shopware\Components\Migrations\AbstractPluginMigration;

class Migration1 extends AbstractPluginMigration
{
    public function up($modus): void
    {
        $this->addSql('CREATE TABLE IF NOT EXISTS swag_order_note (
            id INT AUTO_INCREMENT PRIMARY KEY, order_id INT NOT NULL, note TEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    }

    public function down(bool $keepUserData): void
    {
        if (!$keepUserData) {
            $this->addSql('DROP TABLE IF EXISTS swag_order_note');
        }
    }
}
```

- Never edit a migration that has run; add the next number. `up()` must be re-runnable (`IF NOT EXISTS`, guarded `ALTER`).
- Below 5.6.0, or for a plugin that targets older shops, create tables in `install()` — with Doctrine's `SchemaTool`
  (`updateSchema($classes, true)`, the *safe* mode, and `dropSchema` on a non-`keepUserData` uninstall) — or with DBAL.

## Container: services, subscribers, decoration

`Resources/services.xml` is loaded for you; the plugin's parameters `swag_order_note.plugin_dir` and `.plugin_name` exist
(the prefix is the snake-cased name).

```xml
<service id="swag_order_note.order_note_loader" class="SwagOrderNote\Components\OrderNoteLoader">
    <argument type="service" id="dbal_connection"/>
</service>
<service id="swag_order_note.subscriber.checkout" class="SwagOrderNote\Subscriber\CheckoutSubscriber">
    <argument type="service" id="swag_order_note.order_note_loader"/>
    <argument>%swag_order_note.plugin_dir%</argument>
    <tag name="shopware.event_subscriber"/>
</service>
```

- A subscriber implements `Enlight\Event\SubscriberInterface::getSubscribedEvents()` and is tagged
  `shopware.event_subscriber`. It stays thin: read the event, call a service, assign to the view.
- Event kinds: `notify`, `notifyUntil`, `filter` (return the changed value), `collect` (return a `ArrayCollection` to add).
  Global events such as `Enlight_Controller_Action_PostDispatchSecure_Frontend_Checkout` are the usual seam; the full
  list is the developer docs' event list. Prefer an event; a **hook** (`Class::method::before|replace|after`,
  controllers, core classes and repositories only, `Enlight_Hook` since 5.6) is the last resort and ties the plugin to
  internals.
- Never assign sensitive data to the view in a global `PostDispatch` handler: view variables are shared across renders and
  a JSON render sends them all.
- **Decorate** a core service instead of replacing it: `decorates="shopware_storefront.list_product_service"`,
  `public="false"`, the inner service as `<argument type="service" id="….inner"/>`; implement the same interface and
  delegate. Compiler passes and parameters go in `build(ContainerBuilder $container)` of the base class — call
  `parent::build($container)`, which sets the plugin parameters and loads `Resources/services.xml`.
- Other services: `shopware.plugin.cached_config_reader` (plugin configuration), `pluginlogger` and
  `<plugin_snake_case>.logger` (5.6.0+), `models` (`ModelManager`), `shopware_attribute.crud_service`,
  `template`, `snippets`. Tags worth knowing: `console.command`, `shopware.event_listener`, `shopware_media.optimizer`,
  `shopware_media.adapter`, the search/facet/condition handler tags (see the developer docs' DI tags page).
- Another plugin's path: `$this->container->get('kernel')->getPlugins()['SwagExample']->getPath()`.

## Configuration, menu, cron jobs

- `Resources/config.xml` — `<element type="…" scope="locale|shop" required="true">` with `<name>`, `<label lang>`,
  `<value>`, `<description>`; types `text`, `password`, `textarea`, `boolean`, `color`, `date`, `datetime`, `time`,
  `interval`, `html`, `mediaselection`, `number`, `select`, `selecttree`, `combo`, `combotree`, `button`; a `<store>` of
  `<option>`s or an ExtJS store for selects. Read it with
  `shopware.plugin.cached_config_reader->getByPluginName($name, $shop)`; pass the shop for shop-scoped values.
- `Resources/menu.xml` — `<entry>` with `<name>`, `<label lang>`, `<controller>`, `<action>`, `<class>` (icon sprite),
  `<parent identifiedBy="controller">Marketing</parent>` and nested `<children>`; the parent list is the `controller`
  column of `s_core_menu`. An entry without controller and action is not shown.
- `Resources/cronjob.xml` — `<cronjob>` with `<name>`, `<action>`, `<active>`, `<interval>` (seconds),
  `<disableOnError>`; synchronised on every install and update (new added, changed updated, missing removed, matched by
  action). Subscribe to the event named by the action: an action that already starts with `Shopware_` is the event name (the docs'
  form, `Shopware_CronJob_SendBirthdayMail`); any other is camel-cased and prefixed (`send_mail` fires `Shopware_CronJob_SendMail`). The handler takes a `\Shopware_Components_Cron_CronJob`.
  Cron jobs run when `sw:cron:run` runs (a system cron job or the backend's cron mode), not on their own.
- Snippets: `Resources/snippets/**.ini` per namespace, loaded to the database on install; load them for a controller with
  `$this->get('snippets')->addConfigDir()`.

## Models and attributes

- **Own table** — a Doctrine model in `Models/` (`@ORM\Entity`, `@ORM\Table`, extends `ModelEntity`), the table created in a
  migration or by `SchemaTool`, a repository (`@ORM\Entity(repositoryClass=…)`) that extends `ModelRepository` for
  queries. Model events (`Shopware\Models\…::postUpdate`, as subscriber events) let the plugin react to core entities.
- **Extend a core entity** — the attribute system: one row per core row in `s_<entity>_attributes`. Create the column with
  `shopware_attribute.crud_service->update($table, $column, $type, $viewConfig, $newName, $updateDependingTables, $default)`
  in `install()`, remove it in a non-`keepUserData` `uninstall()`, then rebuild the attribute models
  (`models->generateAttributeModels([$table])` after clearing the metadata cache; the CLI is `sw:generate:attributes`).
  View config (`label`, `displayInBackend`, `translatable`, `position`, `entity`, `arrayStore`, `custom`) puts the field
  into the backend. Attributes are loaded with their entity; where they sit in the template data
  depends on the entity (the docs read a customer attribute as `$sUserData.additional.user.swag_shoesize`) — check
  what the controller assigns. Never `ALTER` a core table by hand.

## Commands, controllers, assets

- **CLI** — a class extending `Shopware\Commands\ShopwareCommand` (Symfony Console 4.4) registered as a service with
  `<tag name="console.command" command="swagorder:import"/>` (5.2.2+); or return commands from `registerCommands()`.
  A command touching the database or models boots the shop container, so it is a unit-testable service plus a thin shell.
- **Controllers** — `Controllers/<Frontend|Widgets|Backend|Api>/<Name>.php`, class
  `Shopware_Controllers_<Module>_<Name>` extending `Enlight_Controller_Action` (backend: `Shopware_Controllers_Backend_ExtJs`
  or `…_Application`); auto-registered from 5.2.7. Add the template dir in `preDispatch()`. An action ends in `Action`.
  A controller that needs a CSRF exemption implements `CSRFWhitelistAware`.
- **Assets** — files under `Resources/frontend/css|js/**` and `Resources/frontend/less/all.less` are picked up
  automatically from 5.2.13; the theme compiler concatenates and minifies them. Frontend JavaScript is jQuery-plugin
  style (see `frontend-patterns.md`).
- **Emotion components, payment methods** — installer services (`shopware.emotion_component_installer`, `PaymentInstaller`)
  called in `install()`; remove them again in `uninstall()` unless the user data is kept.
- **ACL** — a backend resource's privileges and their requirements are rows in `s_core_acl_*`; add a
  `s_core_acl_privilege_requirements` row in a migration when one privilege needs another.
