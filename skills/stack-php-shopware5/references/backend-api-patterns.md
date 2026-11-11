# Shopware 5 — Backend (ExtJS) and REST API Patterns

The administration is an ExtJS 4.1 application (the bundled library's header reads "Ext JS 4.1"; the docs link the 4.1.1
API) delivered through Smarty-rendered JavaScript. The REST API is a separate module with its own controllers and
resource classes. Both are extended by plugins; neither is rebuilt.

## How a backend module loads

A menu entry (`s_core_menu`, or `menu.xml`) names a **controller**; the controller's `index` action renders
`backend/<snake_name>/app.js`, a `Enlight.app.SubApplication` that lists its controllers, views, models and stores; the
`load` action then returns those dependencies concatenated. The ExtJS class name must match the PHP controller:
`Shopware_Controllers_Backend_SwagProduct` ⇒ `Shopware.apps.SwagProduct` ⇒ `Resources/views/backend/swag_product/`.

```
Resources/views/backend/swag_product/
├── app.js                       Ext.define('Shopware.apps.SwagProduct', { extend: 'Enlight.app.SubApplication', … })
├── controller/main.js           Ext.define('Shopware.apps.SwagProduct.controller.Main', { extend: 'Enlight.app.Controller' })
├── model/product.js  store/product.js
└── view/list/window.js  view/list/product.js  view/detail/window.js …
```

## A CRUD module in the backend components

The PHP side needs the model and an alias; list, detail, create, delete and search then come from the base controller:

```php
class Shopware_Controllers_Backend_SwagProduct extends Shopware_Controllers_Backend_Application
{
    protected $model = \SwagProduct\Models\Product::class;
    protected $alias = 'product';
}
```

```javascript
Ext.define('Shopware.apps.SwagProduct.view.list.Window', {
    extend: 'Shopware.window.Listing',
    alias: 'widget.swag-product-list-window',
    title: '{s name=window_title}Products{/s}',
    configure: function () {
        return {
            listingGrid: 'Shopware.apps.SwagProduct.view.list.Product',
            listingStore: 'Shopware.apps.SwagProduct.store.Product'
        };
    }
});
```

- The components (`Shopware.window.Listing`, `Shopware.grid.Panel`, `Shopware.data.Model`, `Shopware.store.Listing`,
  `Shopware.window.Detail`, `Shopware.model.Container`) are configured in a `configure()` method that returns an object;
  the model/store name the PHP controller (`controller: 'SwagProduct'`). The grid needs a `detailWindow`; every component
  needs an `alias` or ExtJS component queries and events fail.
- ExtJS files are Smarty templates: text is `{s name=window_title}Products{/s}` (optional `namespace`), and the
  core wraps its components in blocks (`backend/customer/application`, `backend/customer/view/detail/window`).
- Grids and fields strip HTML since 5.2.21; set `allowHtml: true` on a column or field only for content that is trusted.
- While developing, relax the caches in `config.php` (`front.throwExceptions`, `template.forceCompile`, `model.cacheProvider`
  `Array`, the `Black-Hole` cache backend) — never in production.
- **Simple modules without ExtJS** (5.1+): the "lightweight backend modules" are plain HTML/CSS/JS in an `iframe` that talk to the
  backend over `postMessage` with JSON-RPC 2.0. Use them for a read-only report or a small form.

## Extending an existing backend module

Never edit the core's ExtJS files. Subscribe to `Enlight_Controller_Action_PostDispatchSecure_Backend_<Module>` and inject a
template; **which action you hook decides what you can do**:

| Goal | Action to hook | Mechanism |
|---|---|---|
| Add a *new* component (tab, field set, view) | `index` (loads `app.js`) | `$view->extendsTemplate('backend/swag_x/app.js')`, appending to the module's `…/application` block |
| Change an *existing* component | `load` (loads the dependencies) | `$view->extendsTemplate('backend/swag_x/view/detail/window.js')` with an `override` |

```php
public function onCustomerPostDispatch(\Enlight_Event_EventArgs $args): void
{
    $view = $args->getSubject()->View();
    $view->addTemplateDir($this->pluginDir . '/Resources/views');

    if ($args->getRequest()->getActionName() === 'load') {
        $view->extendsTemplate('backend/swag_extend_customer/view/detail/window.js');
    }
}
```

```javascript
//{block name="backend/customer/view/detail/window"}
//{$smarty.block.parent}
Ext.define('Shopware.apps.SwagExtendCustomer.view.detail.Window', {
    override: 'Shopware.apps.Customer.view.detail.Window',

    createPersonalFieldSet: function () {
        var me = this,
            fieldSet = me.callParent(arguments);
        // change or add fields on fieldSet, then return it
        return fieldSet;
    }
});
//{/block}
```

- The block name is the core file's path under `themes/Backend/ExtJs/` (`backend/customer/view/detail/window`); the new
  class name comes from the template path. `me.callParent(arguments)` runs the original — start from it, so a core update
  that changes the method still works.
- Because the module's blocks are core-internal, a backend override is the most upgrade-fragile code a plugin has. In a
  frozen product that matters less, but keep each override small and tested by hand on every screen it touches.
- Attributes shown in a module come from the attribute system's backend configuration (`displayInBackend`,
  `Shopware.attribute.Form` with a `table`) — not from an override.
- ACL: a backend controller's actions are guarded by the user's role. Add a resource and its privileges for a new module
  and check them in the PHP controller (`initAcl()` with `addAclPermission()` in `Shopware_Controllers_Backend_ExtJs`
  subclasses); if one privilege needs another, add a `s_core_acl_privilege_requirements` row in a migration.
- CSRF: the backend validates every request and adds an `X-CSRF-Token` header to each Ajax request
  (`Ext.CSRFService.getToken()` returns it). An action reached by a plain browser GET (a download), or an external
  callback that authenticates itself, implements `CSRFWhitelistAware` and lists only that action.

## REST API

- Resources live in `engine/Shopware/Controllers/Api/` (controller) and `Shopware\Components\Api\Resource\` (logic):
  addresses, products (`/api/articles`), caches, categories, countries, customers, customer groups, manufacturers, media,
  orders, payment methods, property groups, shops, translations, users, variants, version. The developer docs' table
  lists the verbs each resource supports (not all of them support batch).
- Access: a backend user with "API access" enabled has an API key. Authentication is HTTP Digest, or HTTP Basic from
  5.3.2 — Basic gives no confidentiality, so HTTPS is mandatory. Request and response bodies are JSON in UTF-8, dates ISO 8601.
- Queries: `filter` (list of `property` / `value` / `expression` / `operator`), `sort`, `limit`, `start`; the product
  resource accepts `useNumberAsId=1` to address by order number. Treat `filter` as untrusted input in any resource you write.
- **Add a resource** (5.2.17+): a service `shopware.api.<name>` for the resource class, and a controller
  `Controllers/Api/<Name>.php`; the base `Shopware_Controllers_Api_Rest` maps the verbs to actions:

| Request | Action | Resource method |
|---|---|---|
| GET `/api/<name>` | `indexAction` | `getList($offset, $limit, $criteria, $orderBy)` |
| GET `/api/<name>/{id}` | `getAction` | `getOne($id)` |
| POST | `postAction` | `create($params)` |
| PUT `{id}` | `putAction` | `update($id, $params)` |
| PUT (batch) | `batchAction` | `batch($params)` |
| DELETE `{id}` | `deleteAction` | `delete($id)` |
| DELETE (batch) | `batchDeleteAction` | `batchDelete($params)` |

```php
public function indexAction(): void
{
    $result = $this->resource->getList(
        (int) $this->Request()->getParam('start', 0),
        (int) $this->Request()->getParam('limit', 1000),
        $this->Request()->getParam('filter', []),
        $this->Request()->getParam('sort', [])
    );
    $this->View()->assign(['success' => true, 'data' => $result['data'], 'total' => $result['total']]);
}
```

- Resource methods call `$this->checkPrivilege('read'|'create'|'update'|'delete')` first and throw the API exceptions
  (`NotFoundException`, `ParameterMissingException`, `ValidationException`) the controller turns into HTTP statuses. A Doctrine
  model with `fromArray()` writes the payload; validate it (`$this->getManager()->validate($model)`) before `flush()`.
- **Change an existing resource**: decorate its service (`decorates="shopware.api.article"`, `shared="false"`,
  `public="false"`) with a subclass whose methods call `parent::…` and adjust the result. Never copy the core resource.
- Clients: any HTTP client; for tests, the integration tests in `test-patterns.md` call the controller through the kernel.
