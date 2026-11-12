# Shopware 6 — Storefront and Theme Patterns

The Storefront is server-rendered Twig with Bootstrap 5, vanilla-JavaScript plugins bound to DOM elements, and SCSS compiled
per sales channel by the theme system. Written for 6.7 (Bootstrap 5.3, webpack 5, Twig 3.x); 6.8 raises Twig to 4.x. The
controllers and routes behind a page are in `plugin-patterns.md`.

## Where files go

```text
SwagExample/src/Resources/
├── views/storefront/…                 # Twig, same path as the core template it extends
├── views/components/<Name>/…          # Storefront components, since 6.7.11.0
├── app/storefront/src/main.js         # JS entry — loaded automatically
├── app/storefront/src/<name>/<name>.plugin.js
├── app/storefront/src/scss/{base.scss,overrides.scss}
├── app/storefront/dist/…              # build output; commit it for a Store plugin
├── snippet/<domain>.<locale>.json     # translations, e.g. swag-example.de.json (domain: the extension name, kebab case)
└── theme.json                         # only in a theme
```

Build and watch (from the Shopware source tree or the production template): `composer run build:js:storefront`,
`shopware-cli project storefront-build`; watcher `composer run storefront:dev-server` since 6.7.11.0, `composer run watch:storefront`
before. After a theme or SCSS change: `bin/console theme:compile`; after a `theme.json` change: `bin/console theme:refresh`;
assign a theme to a channel with `bin/console theme:change`. `bin/console cache:clear` after a template change.

## Twig: extend, never copy

An override lives at the **same path under `views/`** as the core template and extends it with Shopware's own tag:

```twig
{# views/storefront/layout/header/logo.html.twig #}
{% sw_extends '@Storefront/storefront/layout/header/logo.html.twig' %}

{% block layout_header_logo_link %}
    {{ parent() }}
    <span class="swag-example-claim">{{ 'swag-example.claim'|trans|sw_sanitize }}</span>
{% endblock %}
```

- Override a **block**, print `parent()` (inside the usual output braces) to keep the core markup; replacing a block wholesale ties you to its inner
  structure at every upgrade. Find the block by searching `src/Storefront/Resources/views` for the markup.
- `{% sw_include %}` instead of `{% include %}` so that plugin and theme overrides of the included file are honoured;
  `{% sw_extends %}` instead of `{% extends %}` for the same reason.
- Add a new page next to the core: a template extending `@Storefront/storefront/base.html.twig` overriding `base_content`
  (or `base_main_inner`).
- Texts go through snippets (the `trans` filter on a key such as `'swag-example.title'`), never literal strings; ship every language the shop uses.
  Escape output; `|raw` only on markup you built; run user HTML through `sw_sanitize`.
- Plugin configuration in Twig: the `config('SwagExample.config.label')` function. Data a template needs comes from the page
  object or a subscriber on the page-loaded event (`add-data-to-storefront-page`), not from a query in the template.
- Re-check every override after a minor or major upgrade: the `UPGRADE-6.x.md` files list removed blocks, templates and
  template variables (6.8 removes several document template variables, for example). A template copied from an older line
  carries blocks that may have moved.

### Storefront components (since 6.7.11.0)

Reusable atomic templates built on Symfony UX Twig Components: a file `views/components/Button/Primary.html.twig` is the
component `SwagExample:Button:Primary` (the extension name is the namespace); `index.html.twig` takes the directory name.
Properties are declared in the template with `{% props label = 'Click', size = 'md' %}`; use it as
`<twig:SwagExample:Button:Primary label="Buy" size="lg" />`. A PHP-class component (`#[AsTwigComponent]`, registered with
`autoconfigure`) is possible in plugins only, not in apps. A `Primary.scss` next to the template is compiled with the
component. The docs' directory examples spell the folder `commponents` — the text and the loader mean `components`.
6.8 moves to Twig 4 and UX Twig Component 3: check custom components against the Symfony UX 3 upgrade guide.

## JavaScript plugins

A plugin is an ES class extending `window.PluginBaseClass`, with `static options` (overridable from the template through
`data-<kebab-plugin-name>-options='{"text": "…"}'`), `this.el` (the bound element) and an `init()` run on `DOMContentLoaded`:

```js
// src/Resources/app/storefront/src/example-plugin/example-plugin.plugin.js
const { PluginBaseClass } = window;

export default class ExamplePlugin extends PluginBaseClass {
    static options = { text: 'Done' };

    init() {
        this._onClick = this.onClick.bind(this);
        this.el.addEventListener('click', this._onClick);
    }

    onClick() {
        window.alert(this.options.text);
    }
}
```

```js
// src/Resources/app/storefront/src/main.js
const PluginManager = window.PluginManager;
PluginManager.register('ExamplePlugin', ExamplePlugin, '[data-example-plugin]');
// lazy: only fetched on a page that contains the selector
PluginManager.register('ExamplePlugin', () => import('./example-plugin/example-plugin.plugin'), '[data-example-plugin]');
```

- The selector binds the plugin to the elements that have the attribute — `<template data-example-plugin>` in a Twig block
  on the page that needs it. Without a selector the plugin runs once on every page.
- Replace a core plugin by extending it and calling `PluginManager.override('CookiePermission', MyCookiePermission,
  '[data-cookie-permission]')`. **A plugin can be overridden only once**: with two extensions overriding the same core plugin,
  the last wins. Call `super.init()` and prefer adding behaviour over rewriting methods.
- Fetch with the platform's `fetch`/`HttpClient` against a Storefront route that returns a template or JSON; render
  responses through Twig, not by string concatenation of untrusted data (XSS).
- Remove listeners you add outside `this.el`; markup replaced by AJAX needs its plugins initialised again
  (`window.PluginManager.initializePlugins()`, `getPluginInstanceFromElement(el, name)` to reach an instance).
- Async registration keeps a rarely used plugin out of `storefront.js`; use it for anything not needed on every page.
- Do not edit `dist/`; it is generated. A Store plugin ships the built `dist` (and `shopware-cli extension validate` with
  `validation.store_compliance` checks source and compiled assets match).

## SCSS and assets

- `scss/base.scss` is loaded after Bootstrap and the Storefront styles; put selectors there. `scss/overrides.scss` is loaded
  **before** them (the first `style` entry of `theme.json`) and is where Bootstrap and Storefront SCSS **variables** are
  overridden, so they take effect in the compiled output. Import with the `@Storefront` alias-style paths the core uses.
- Values merchants edit are theme configuration fields in `theme.json` (`config` → `fields`; the key is the technical name
  used in the theme's SCSS and, in Twig, `theme_config('key')`).
- Static assets (images, fonts) go to `app/storefront/src/assets`; reference a plugin asset from Twig with the
  `asset('bundles/swagexample/image.png', 'asset')` function (the bundle name is the lower-cased plugin name).
- Icons: add SVGs under `Resources/app/storefront/dist/assets/icon/<pack-name>/` and render with `{% sw_icon 'name' style {…} %}`;
  icons and custom assets are not part of theme inheritance — a child theme needs its own copy.
- Never hard-code colours or breakpoints that Bootstrap variables already name.

## Themes (`theme.json`)

A theme is a plugin (or an app, see `app-patterns.md`) whose base class implements `Shopware\Storefront\Framework\ThemeInterface`
and ships `src/Resources/theme.json`. Create with `shopware-cli extension create --type theme` or `bin/console theme:create`.

```json
{
  "name": "SwagExampleTheme",
  "author": "Swag",
  "views": ["@Storefront", "@Plugins", "@SwagExampleTheme"],
  "style": ["app/storefront/src/scss/overrides.scss", "@Storefront", "app/storefront/src/scss/base.scss"],
  "script": ["@Storefront", "app/storefront/dist/storefront/js/swag-example-theme/swag-example-theme.js"],
  "asset": ["@Storefront", "app/storefront/src/assets"],
  "configInheritance": ["@Storefront"]
}
```

- `views` is applied in order: the Storefront template is the basis, the active plugins' extensions come on top (`@Plugins`),
  then the theme(s) listed after them. `style` / `script` order is compile and load order.
- **Inheritance**: a child theme lists the parent in `views` / `style` / `script` and in `configInheritance` instead of
  copying files; only the differences live in the child. Configuration inheritance exists since 6.4.8.0.
- Changing the compiled result needs `theme:compile` (or `theme:refresh` then compile) per sales channel; a theme not
  assigned to the sales channel is invisible there, and assigning is `theme:change` or the Administration.
- In 6.8 the theme configuration loader changed (`CachedResolvedConfigLoader` removed in favour of the `theme_runtime_config`
  table, `ThemeLifecycleService` final): do not extend either.

## Accessibility, performance, privacy

- Keep the core's semantics: landmarks, headings in order, `alt` on images (decorative ones empty), labelled form fields,
  focus-visible styles, keyboard reachable off-canvas and modals. Shopware publishes an accessibility checklist.
- Cookies that your JS or a third party sets must be registered with the cookie consent manager (the "add cookie to manager"
  guide; a plugin written for 6.7.2 or earlier used `CookieProviderInterface`, which the current form replaced; in an app the
  manifest `<cookies>` section) and loaded only after consent.
- Prefer async plugins, `loading="lazy"` on below-the-fold images and no blocking third-party scripts in `<head>`.
- Cacheable pages must not contain per-customer output; personal parts are loaded by a widget route or a JS plugin.

## Review checklist

- [ ] Overrides extend the core block with `sw_extends` and keep `parent()` unless replacing is the point.
- [ ] Every user-facing string is a snippet in both languages; output escaped; no `|raw` on input.
- [ ] A JS plugin has a selector or a stated reason for none, removes its listeners and survives being initialised twice.
- [ ] No core plugin overridden twice; no edited `dist/`; assets built with the project's own command.
- [ ] `theme:compile` / `cache:clear` run before a visual judgement.
