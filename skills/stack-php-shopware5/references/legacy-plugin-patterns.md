# Shopware 5 — Legacy Plugin Patterns (`Bootstrap.php`)

Plugins written for Shopware 4 and the early 5.x releases still run in 5.7.20: `Shopware_Components_Plugin_Bootstrap` and
its installer are in the core, and the plugin manager lists both kinds. New plugins use the 5.2+ system
(`plugin-patterns.md`); this file is for **maintaining** an existing `Bootstrap.php` plugin without converting it.

## Recognise it

```
engine/Shopware/Plugins/{Local|Community|Default}/{Frontend|Backend|Core}/SwagSloganOfTheDay/Bootstrap.php
```

- No namespace in the file; the class is `Shopware_Plugins_<Section>_<PluginName>_Bootstrap` and extends
  `Shopware_Components_Plugin_Bootstrap`. `Default` holds the core's own plugins; a plugin of the shop or the Store sits in `Local` or `Community`.
- A Composer-installed one comes from `shopware-frontend-plugin`, `shopware-backend-plugin` or `shopware-core-plugin`.
- Metadata comes from the class (`getVersion()`, `getLabel()`, `getInfo()`, `getCapabilities()`), not a `plugin.xml`;
  there is no `Resources/services.xml`, no DI registration by the plugin, and **no plugin migrations** (those belong to the
  5.2+ installer). Version and label are the minimum `getInfo()` returns.

## Lifecycle

```php
class Shopware_Plugins_Frontend_SwagSloganOfTheDay_Bootstrap extends Shopware_Components_Plugin_Bootstrap
{
    public function getVersion() { return '1.2.0'; }
    public function getLabel()   { return 'Slogan of the day'; }

    public function getCapabilities()
    {
        return ['install' => true, 'update' => true, 'enable' => true, 'secureUninstall' => true];
    }

    public function afterInit()          // runs on every request the plugin is loaded
    {
        $this->get('loader')->registerNamespace('SwagSloganOfTheDay', $this->Path());
    }

    public function install()
    {
        $this->subscribeEvent('Enlight_Controller_Action_PostDispatchSecure_Frontend', 'onPostDispatch');
        $this->createConfiguration();
        return ['success' => true, 'invalidateCache' => ['frontend', 'theme']];
    }

    public function update($oldVersion)
    {
        if (version_compare($oldVersion, '1.2.0', '<')) {
            $this->subscribeEvent('Shopware_CronJob_SloganRefresh', 'onCron');
        }
        return true;
    }

    public function secureUninstall() { return true; }   // keep user data
    public function uninstall()       { /* drop what install created */ return true; }
    public function enable()          { return ['success' => true, 'invalidateCache' => ['proxy', 'frontend', 'theme']]; }
    public function disable()         { return true; }
}
```

- Every lifecycle method returns `true`, `false` or an array `['success' => bool, 'message' => …, 'invalidateCache' => […]]`.
  `false`, or an array without `success`, aborts the operation with an error; an exception aborts it with its message.
  The base-class defaults depend on `getCapabilities()`; a method that is not declared as a capability does nothing.
- `subscribeEvent($event, $method)` is stored **in the database** at install/update time. A new or changed subscription
  therefore needs an `update()` branch (or a reinstall) — editing `afterInit()` alone changes nothing.
- `assertMinimumVersion('5.2.0')` tests the shop version in `update()`; throw to refuse.
- Use `$this->get('<service-id>')` for the container, `$this->Path()` for the plugin directory, `$this->Config()->get('name')`
  for configuration.

## What the Bootstrap offers

| Need | Legacy call (in `install()`) |
|---|---|
| Event / hook | `$this->subscribeEvent('Enlight_Controller_Action_PostDispatchSecure_Frontend_Detail', 'onDetail')` |
| Subscriber class | in a handler: `$this->get('events')->addSubscriber(new Subscriber($this->Path(), $this->get('dbal_connection')))` |
| Controller | `$this->registerController('Frontend', 'MyController')`, or the `…_ControllerPath_` event returning the file path |
| Configuration | `$this->Form()->setElement('text', 'name', ['label' => …, 'value' => …, 'scope' => Element::SCOPE_SHOP])`, translations with `addFormTranslations()` |
| Backend menu | `$this->createMenuItem(['label' => …, 'controller' => …, 'action' => 'Index', 'class' => …, 'active' => 1, 'parent' => $this->Menu()->findOneBy(['controller' => 'Marketing'])])` |
| Cron job | `$this->createCronJob('Name', 'action', 86400, true)` plus `subscribeEvent('Shopware_CronJob_Action', …)` (the action camel-cased and prefixed) |
| CLI command | `subscribeEvent('Shopware_Console_Add_Command', …)` returning an `ArrayCollection` of `ShopwareCommand`s |
| Payment, template, widget, emotion element | `createPayment()`, `createTemplate()`, `createWidget()`, `createEmotionComponent()` |
| Assets | `Theme_Compiler_Collect_Plugin_Less` / `…_Javascript` events returning a `LessDefinition` / file list |
| Decorate a service | `Enlight_Bootstrap_AfterInitResource_<service>` event, then `$this->container->set($id, new Decorator($original))` |

- Views live in `Views/` (not `Resources/views`): add the dir with `$view->addTemplateDir($this->Path() . 'Views/')`
  in a PostDispatch handler. `extendsTemplate()` and `extendsBlock()` are the old injection calls; for the Responsive theme
  the docs say to rely on the automatic template loading instead, i.e. `{extends file="parent:…"}` templates in the
  plugin's view directory.
- Backend ExtJS extensions work as in `backend-api-patterns.md`; the template dir is `Views/backend/…`.
- `registerController()` with the default listener also registers, when the directories exist, the plugin's `Models`
  (`registerCustomModels()`), `Views/`, `Snippets/` and `Components/` (namespace `Shopware_Components`) — a plugin without a
  controller registers them itself in `afterInit()` or a handler. Call `removeSnippets()` in `uninstall()`.
- Installing and updating use the same commands as the new system: `sw:plugin:refresh`, `sw:plugin:install --activate`,
  `sw:plugin:update`, `sw:plugin:uninstall [--secure]`.

## Working on one

- **Keep the style.** A bug fix in a `Bootstrap.php` plugin stays a bug fix in a `Bootstrap.php` plugin. Do not add
  `services.xml`, namespaces everywhere or a second base class unasked; the two systems are separate installers.
- **Do not break the shop on update.** `update($oldVersion)` must be safe for every version that shipped; guard each step with
  `version_compare($oldVersion, …)`, and make schema changes idempotent (`IF NOT EXISTS`, an information-schema check),
  because there is no migration table to remember what ran.
- **Bump `getVersion()`** in the same change that needs an update step; the plugin manager only runs `update()` when the
  version it finds is higher than the installed one.
- **Testing**: the legacy test base is the same (`Shopware\Tests\Functional\Components\Plugin\TestCase`) but the bootstrap
  path is different: `engine/Shopware/Plugins/Local/Frontend/<Name>/Tests/Functional/Bootstrap.php` needs a longer
  `../` chain than a `custom/plugins` plugin. Count it from the real directory.
- **Converting to 5.2+** is a slice of its own, planned from the developer docs' plugin update guide: new base class named
  after the plugin, `services.xml` for subscribers, `Resources/views` for templates, the plugin's database state kept
  and `uninstall()` written so it does not delete the old data. Never as a drive-by change.
- **Moving toward Shopware 6** — a legacy plugin has no structure to reuse. Put its business logic in plain classes
  (`Components/`, constructor-injected) as soon as it is touched, so that only the thin Bootstrap stays Shopware 5.
