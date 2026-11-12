# Shopware 6 — Administration Patterns

The Administration is a Vue 3 single-page application built with Vite, with a Shopware layer on top for modules, component
registration, TwigJS template blocks, a dependency-injection container and the DAL client. A plugin extends it through
`Shopware.*`; an app extends it from an iframe through the Meteor Admin SDK. Written for 6.7 (Vue 3.5, Pinia, Vite 6, Jest 30);
the 6.6 and 6.5 differences are marked, 6.8 changes are listed at the end.

## Three ways to extend

| Way | For | Stability |
|---|---|---|
| **Options API + TwigJS** (`Shopware.Component.register/extend/override`, `Shopware.Module.register`) | a plugin's modules and component changes | the stable way today, and the way most of the Administration is written |
| **Meteor Admin SDK** (`@shopware-ag/meteor-admin-sdk`, 6.17.0 on 2026-11-03) | an app's iframe module, an action button, a CMS element; usable from a plugin too | Shopware names it the stable cross-version extension point |
| **Single File Components** (`.vue` with `<script setup>`, `<sw-block extends>`, `swDefineOverride()`) | experiments | **experimental since 6.7.16.0**; the API can change at any time without deprecation; planned stable in 6.9; testing an SFC extension is not supported yet |

Default to the first. Choose the second for an app, or for a feature that must survive Administration upgrades unchanged. Use the
third only for a throw-away or with a stated readiness to rewrite it each update.

## Layout

```text
SwagExample/src/Resources/app/administration/
├── package.json  (only if the plugin has its own npm dependencies)  vite.config.mts  (only for a custom Vite config)
└── src/
    ├── main.js                          # entry — imports each module / override once
    ├── module/swag-example/{index.js,page/swag-example-list/{index.js,*.html.twig,*.scss},snippet/{en-GB,de-DE}.json}
    ├── component/…   service/…   state/…
```

Build: `composer run build:js:admin` (source tree) or `shopware-cli project admin-build` (production template); watcher
`composer run watch:admin`. Node `^20 || ^21 || … || ^25` for the 6.7 Administration. The build must run before a Store plugin
is packaged, and again after every pulled change to `main.js` or a template. **6.7** replaced Webpack with Vite: a plugin's
`webpack.config.js` becomes `vite.config.mts` in `…/administration/src/`, without webpack dependencies in its `package.json`. On **6.6**
and **6.5** it is still Webpack; 6.6 runs Vue 3 with a *migration build* (`@vue/compat`), 6.5 runs **Vue 2.7**, Vuex 3 and
vue-i18n 8 — a plugin's Administration code cannot be one version for 6.5 and 6.6.

## Modules, routes, menu

```js
// src/module/swag-example/index.js
import './page/swag-example-list';
import deDE from './snippet/de-DE.json';
import enGB from './snippet/en-GB.json';

Shopware.Module.register('swag-example', {
    type: 'plugin',
    name: 'Example',
    title: 'swag-example.general.title',          // a snippet key, not a literal string
    description: 'swag-example.general.description',
    color: '#ff3d58',
    icon: 'regular-shopping-bag',
    routes: {
        list: { component: 'swag-example-list', path: 'list', meta: { privilege: 'swag_example.viewer' } },
        detail: { component: 'swag-example-detail', path: 'detail/:id', meta: { parentPath: 'swag.example.list', privilege: 'swag_example.viewer' } },
    },
    navigation: [{ id: 'swag-example', label: 'swag-example.general.title', color: '#ff3d58', path: 'swag.example.list', parent: 'sw-catalogue', position: 100, privilege: 'swag_example.viewer' }],
    snippets: { 'de-DE': deDE, 'en-GB': enGB },   // imported JSON, keys prefixed with the extension name
});
```

- The route name is `<module-name with dots>.<route key>` (`swag.example.list`). `meta.parentPath` makes the back button and
  the breadcrumb work. Always set a unique `name`, `type: 'plugin'`, `title` and a snippet-key label.
- A plugin module cannot add a first-level menu entry (the Store rejects it): set `parent` to an existing entry (`sw-catalogue`,
  `sw-marketing`, …; the id is in that module's `navigation`). `position`: the higher, the lower in the menu.
- Snippet keys are prefixed with the extension name (`swag-example.…`) so they cannot collide; an app's snippets may not
  override existing keys.

## Components: register, extend, override

```js
import template from './swag-example-list.html.twig';
const { Criteria } = Shopware.Data;

Shopware.Component.register('swag-example-list', {
    template,
    inject: ['repositoryFactory', 'acl'],
    mixins: [Shopware.Mixin.getByName('notification')],
    data() { return { items: null, isLoading: false }; },
    computed: {
        repository() { return this.repositoryFactory.create('swag_example'); },
        criteria() {
            const criteria = new Criteria();
            criteria.setPage(1);
            criteria.setLimit(25);
            return criteria.addSorting(Criteria.sort('createdAt', 'DESC'));
        },
    },
    created() { this.load(); },
    methods: {
        async load() {
            this.isLoading = true;
            try { this.items = await this.repository.search(this.criteria); }
            catch { this.createNotificationError({ message: this.$tc('global.notification.unspecifiedSaveErrorMessage') }); }
            finally { this.isLoading = false; }
        },
    },
});
```

- `register(name, config)` (or `register(name, () => import('…'))` for a lazily loaded one); `extend(newName, parentName, config)`
  makes a **new** component from an existing one; `override(name, config)` changes the component **in place** for everyone.
  Prefer `extend` for your own variants; an override is global, and several overrides of one component chain in
  registration (plugin load) order — keep yours small and call `$super`.
- Template blocks (TwigJS): `{% block name %}…{% endblock %}`, `{% parent %}` to keep the original. Override the block, never
  copy the whole template; names are the contract and can change between minors (read the target version's template).
- To change logic, extend `methods` / `computed` and call `this.$super('method', …)` for the original. Write Vue 3: no
  `$listeners` (use `$attrs`), no `$parent.$on` / `$off` (the parent provides the handler through `inject`), `beforeUnmount`
  instead of `beforeDestroy` (the Administration's own components use `beforeUnmount`, although the migration guide's
  snippet still shows the old hook name). Vue's own Vue 3 migration list covers the rest when porting a 6.5 plugin.
- Use the Administration's base components (`sw-card`, `sw-entity-single-select`, `sw-data-grid`, …) and the Meteor Component Library
  components that replace some of them from 6.7 (`@shopware-ag/meteor-component-library`, npm latest 5.10.0, 6.7.16.0 ships 5.8.0; codemods:
  `composer run admin:code-mods`) rather than raw markup.
- Share logic with a **mixin** (`Shopware.Mixin.getByName('notification')`, `listing`, …) — the stable way today. A composable
  replaces a mixin only inside an SFC, and some mixins have no composable yet (see the SFC roadmap).

## Data, services, state

- **Repositories**: `inject: ['repositoryFactory']`, `this.repositoryFactory.create('product')`; `search(criteria)`, `get(id)`,
  `save(entity)`, `create()`, `delete(id)` — each takes the API context (`Shopware.Context.api`; the SDK-style methods
  default to it). `Criteria` is `Shopware.Data.Criteria` with `addFilter(Criteria.equals('active', true))`, `addAssociation('manufacturer')`,
  `setPage / setLimit / setTerm / setIds / setTotalCountMode`. Fields the Administration reads must be `ApiAware` (`dal-patterns.md`).
- **Services**: register with `Shopware.Service().register('swagExampleService', (container) => new …)` and add the name to
  `inject: [...]`; `Shopware.Application.addServiceProviderMiddleware(name, (service, next) => …)` decorates an existing one.
  Call the API through the Administration's HTTP client and API services (the login token and base URL are handled), not a bare `fetch`.
- **State**: **Pinia since 6.7.** `const store = Shopware.Store.register('swagExample', { state: () => ({ … }), getters: {…}, actions: {…} })`;
  read with `Shopware.Store.get('swagExample')`. A Pinia state is a function, there are no mutations, a getter may not share a
  name with a state property. On 6.6 and 6.5 the store is Vuex: `Shopware.State.registerModule('swagExample', {…})`.
  Keep component-local state in the component; a store is for state that several components share.
- **Global objects**: `Shopware.Context`, `Shopware.Service`, `Shopware.Data`, `Shopware.Utils`, `Shopware.Filter`, `Shopware.Mixin`
  — the public interface for third parties. Importing from the Administration's internal paths binds you to its structure.

## Permissions (ACL)

Register privileges once, protect every entry point, check in code:

```js
Shopware.Service('privileges').addPrivilegeMappingEntry({
    category: 'permissions',
    parent: 'catalogues',
    key: 'swag_example',
    roles: {
        viewer: { privileges: ['swag_example:read'], dependencies: [] },
        editor: { privileges: ['swag_example:update'], dependencies: ['swag_example.viewer'] },
        creator: { privileges: ['swag_example:create'], dependencies: ['swag_example.viewer', 'swag_example.editor'] },
        deleter: { privileges: ['swag_example:delete'], dependencies: ['swag_example.viewer'] },
    },
});
```

- Roles for `permissions` are `viewer`, `editor`, `creator`, `deleter`; non-CRUD actions use `additional_permissions` with a
  custom role key. `privileges` lists the API permissions (`entity:operation`) the role needs; `dependencies` auto-selects
  other roles. Add a privilege snippet so the role shows a readable label.
- Guard a route with `meta.privilege`, a menu entry with `privilege`, and a control with `v-if="acl.can('swag_example.editor')"`
  (`inject: ['acl']`). **These checks only hide UI**: the Admin API still answers a direct call, so the server route needs
  its own `_acl` default (`plugin-patterns.md`).

## Apps and the Meteor Admin SDK

An app's Administration code is not part of the Administration's bundle: it is a page served by the app server inside an iframe,
registered in the manifest (`<admin><module …>`, `<action-button action entity view url>` for smart-bar buttons on a detail or
list view) and talking to the Administration through `postMessage`, wrapped by the SDK (`sw.notification.dispatch({…})`,
context access, UI extension points such as `ui.mainModule`, data subscriptions). The SDK works the same from a plugin. Because
the app is an ordinary web page it does not depend on the Administration's Vue, Pinia or Vite versions (the migration guides
state no consequences for apps); build it as a normal Vite project with the SDK. Declare the permissions in the manifest and
verify the signature of every request the shop sends (`app-patterns.md`).

## Review checklist

- [ ] Snippet keys instead of literal strings, in every shipped language; keys prefixed with the extension name.
- [ ] A module, route, menu entry and API route each carry the privilege; `acl.can` guards the buttons.
- [ ] Overrides are `extend` where a variant suffices; blocks are overridden, not whole templates.
- [ ] No Vue 2 idiom (`$listeners`, `beforeDestroy`, `$on`, `Vue.set`) and no Vuex on a 6.7 target.
- [ ] `admin-build` ran; a Store plugin ships the compiled assets next to the source.

## 6.8 and later

- Vite 8 (Rolldown, Oxc) replaces Vite 6 in 6.8 and needs Node `^20.19.0 || >=22.12.0`; in 6.7 `ADMIN_VITE_8=1` builds with it.
  `import.meta.glob` with extglob patterns like `!(*.spec)` stops matching: use an array with a negated pattern
  (`['./**/*.{j,t}s', '!./**/*.spec.{j,t}s']`); `bin/console administration:upgrade-extensions -- --only=YourPlugin --target=6.8 --write`
  rewrites supported cases.
- The Composition API extension system is no longer a public entry point in 6.8; the SFC system stays experimental until 6.9.
- Plan the plugin's `vite.config.*` and CommonJS default imports against the Vite 7 and 8 migration guides.
