# Shopware 5 — Frontend Patterns (Smarty, themes, LESS, jQuery plugins)

The storefront is server-rendered Smarty 3 (bundled in `engine/Library/Smarty`, whose class file reports Smarty-3.1.12),
styled with LESS compiled in PHP (`wikimedia/less.php` 4.1.0 in 5.7.20) and enlivened by jQuery 3.6.0 plugins in the
Responsive theme. Everything is extended by **inheritance and blocks** — a copied core template is the anti-pattern.

## Where templates live and how they resolve

- Core themes: `themes/Frontend/Bare` (bare HTML structure) and `themes/Frontend/Responsive` (extends Bare). Your own theme
  is `themes/Frontend/<Name>/` or, shipped with a plugin, `Resources/Themes/Frontend/<Name>/` (5.2+). Plugin templates
  sit in `Resources/views/` (5.2+) or `Views/` (legacy).
- Plugin templates are processed after the core themes. With `$injectBeforePlugins = true` the theme is processed before
  the plugins, so every plugin can still extend it (the setting for a theme meant to be sold); with `false` the theme
  comes after them, so a local theme can override a plugin's templates.
- A file with the same path in a child theme **replaces** the parent file. To change part of it, extend:

```smarty
{extends file="parent:frontend/detail/index.tpl"}

{block name="frontend_detail_index_buy_container"}
    {$smarty.block.parent}
    <p class="swag--note">{s name="NoteText" namespace="frontend/swag_note/detail"}Note{/s}</p>
{/block}
```

- `parent:` resolves in the parent theme; `{$smarty.block.parent}` includes the parent block (call it before or after your
  markup; leave it out to replace the block). `{block name="…" append|prepend}` is the short form.
- Blocks are named by path: frontend blocks `frontend_detail_index_buy_container` (underscores), backend ExtJS blocks
  `backend/customer/view/detail/window` (slashes). The Responsive theme has well over 1,800 blocks (1,831 counted in the
  5.0 docs). Find one by searching the parent file for the markup; do not guess a name — a name the parent does
  not define makes the extension do nothing.
- Directory sections: `frontend/{index,home,listing,detail,checkout,account,register,search,…}`, `widgets/`, `documents/`,
  `newsletter/`. A custom category or detail template is a new file in `frontend/listing/` or `frontend/detail/`,
  registered in the basic settings ("Available template categories" / "templates for detail page", format
  `file.tpl:Label`).
- Template data comes from the controller (`$view->assign()`); the template reads `{$sArticle.articleName}`. Do not
  query the database from a template; assign what it needs in a PostDispatch handler.
- **Escape** every value that is not trusted HTML: `{$value|escapeHtml}`, `|escapeHtmlAttr`, `|escapeJs`, `|escapeCss`,
  `|escapeUrl`. Snippets (`{s name=… namespace=…}Text{/s}`) make text translatable; the namespace maps to a
  snippet INI file loaded into the database on install.

## Theme.php

```php
namespace Shopware\Themes\SwagBrand;

use Shopware\Components\Form as Form;

class Theme extends \Shopware\Components\Theme
{
    protected $extend = 'Responsive';
    protected $name = 'Swag Brand';
    protected $description = 'Brand theme';
    protected $author = 'Swag';
    protected $license = 'MIT';

    protected $injectBeforePlugins = true;
    protected $javascript = ['src/js/jquery.swag-teaser.js'];    // relative to frontend/_public
    protected $css = [];                                          // plain CSS, if no LESS
    protected $discardedLessThemes = [];                          // 5.4+: drop an ancestor's LESS
    protected $discardedJavascriptThemes = [];                    // 5.4+: drop an ancestor's JavaScript

    public function createConfig(Form\Container\TabContainer $container)
    {
        // $container->addTab($this->createTab('brand', 'Brand')) with fields, see the docs
    }
}
```

- LESS: the compiler reads `frontend/_public/src/less/all.less` (imports resolved); it compiles on the fly and writes to
  `web/cache`. Components follow the `src/less/_components/*.less` and `_mixins/` layout of the Responsive theme; the
  `unitize` mixin produces `rem` with a `px` fallback.
- Theme options created in `createConfig()` are edited in the Theme Manager, read in templates as `{$theme.<field_name>}`
  and available in LESS as a variable of the field's name; configuration sets (`createConfigSets()`) ship presets.
- After any change to a theme, template, LESS or JavaScript: `bin/console sw:theme:cache:generate` (and
  `sw:cache:clear`); `sw:theme:synchronize` registers a newly added theme directory, `sw:theme:create` scaffolds one.
  During development the backend's "force compile" setting skips the cache — it is a development switch.
- A plugin's own assets (`Resources/frontend/css|js/**`, `Resources/frontend/less/all.less`) are compiled into the same
  bundle from 5.2.13; there is nothing to register.
- Supported browsers in the Responsive theme per the 5.x docs: current Chrome, Firefox, Safari, Opera, and Internet
  Explorer 11 from 5.3. The built-in compressor concatenates and strips whitespace and comments (per the 5.x docs), so write browser-ready ES5 in theme and plugin files.

## jQuery plugins and the StateManager

The Responsive theme's JavaScript is built on `$.plugin(name, definition)` (a base class that merges `defaults` into
`this.opts`, reads `data-` attributes with `applyDataAttributes()` and removes listeners registered with `this._on()` on
`destroy`) and the global `StateManager` (breakpoints `xs` 0–479, `s` 480–767, `m` 768–1023, `l` 1024–1259, `xl` 1260 and up).

```javascript
;(function ($, window) {
    'use strict';

    $.plugin('swagTeaser', {
        defaults: { activeCls: 'js--is-active' },

        init: function () {
            var me = this;
            me.applyDataAttributes();
            me._on(me.$el, 'click', $.proxy(me.onClick, me));
        },

        onClick: function (event) {
            event.preventDefault();
            this.$el.toggleClass(this.opts.activeCls);
        },

        destroy: function () {
            this._destroy();
        }
    });

    // bind it to a selector, active only for the listed viewport states
    StateManager.addPlugin('.swag--teaser', 'swagTeaser', ['m', 'l', 'xl']);
})(jQuery, window);
```

- **Change a core plugin's behaviour**, do not copy it: `$.overridePlugin('swSearch', { showResult: function () {
  this.superclass.showResult.apply(this, arguments); … } })` (5.0.2+); `this.superclass` is the original method.
- **React to a core plugin** with the global events the plugins publish (`$.subscribe('plugin/<name>/onInit.my-ns', fn)`,
  removed with `$.unsubscribe('…onInit.my-ns')`) — always with an event namespace, or `unsubscribe` removes everyone's
  listeners.
- **Re-initialise after Ajax**: `StateManager.addPlugin()` binds on page load; after replacing markup call the plugin's
  jQuery function on the new element (`$('.swag--teaser').swagTeaser()`), and `CSRF.updateForms()` when the new markup
  contains a form (the CSRF token is injected into forms and Ajax headers by the core's `swCsrfProtection` plugin).
- Do not load a second jQuery or a library the theme already bundles; check `frontend/_public/vendors/js/` of the
  Responsive theme first.
- The core ships Jest tests for the Responsive theme (`npm run test --prefix ./themes/Frontend/Responsive`); a theme or
  plugin adds JavaScript tests only if the project already has the tooling (`test-patterns.md`).

## Emotion worlds and the checkout

- The shopping worlds ("emotions") are driven by `s_emotion*` data and components installed with
  `shopware.emotion_component_installer` (5.2.10+); a plugin adds a component with fields, a Smarty template under
  `widgets/emotion/components/` and, when it needs data, a `shopware_emotion.component_handler`-tagged service.
- Checkout, registration and the account are the most-extended and most-legislated pages: change them by block, keep the
  core's form field names and `__csrf_token` fields, and re-test the whole path (cart, shipping, payment, confirm) after.
