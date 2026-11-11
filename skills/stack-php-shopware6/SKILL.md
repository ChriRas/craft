---
name: stack-php-shopware6
description: CRAFT stack-pack for Shopware 6 extensions on the 6.7 line with the older 6.6 line's differences marked — plugins (services, subscribers, migrations, scheduled tasks, routes), the Data Abstraction Layer, apps (manifest, webhooks, app server, app scripts), the Storefront and themes, the Administration, and tests with PHPUnit, Jest and Playwright. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — Shopware 6

The code-near personality layer for a Shopware 6 extension or shop project — a plugin, an app, a theme, Administration or
Storefront code — written for the current 6.7 line (6.7.16, PHP 8.2 to 8.5, Symfony 7.4 components) with the older 6.6 line
marked. It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`, `/craft:refactor` and
`/craft:review` when `rules.md` declares it in its `## Personality` block. Shopware is a Symfony application, but a pack is
monolithic (D27): the PHP and Symfony idioms it needs are restated here, so a Shopware project declares this pack instead of
`stack-php-symfony`. Project-specific conventions — domain rules, exact commands, the supported Shopware range — live in the
project's own `rules.md`, not here. Versions below were verified on 2026-11-11 (see `## Sources`); a newer release may have moved.

## Stack

- **Shopware** — 6.7 is the current stable line (6.7.16.0, 2026-10-22; PHP `~8.2` to `~8.5`, Symfony `~7.4`). 6.6 (6.6.10.31,
  2026-11-02; same PHP and Symfony range) is the older line still patched; 6.5 (last 6.5.8.19, 2026-06-01; PHP 8.1 to 8.3,
  Symfony 6.4) is security-only. The repository's `releases.json` lists security end dates 2031-06-01 (6.7 from 6.7.15.0),
  2029-06-01 (6.6) and 2027-06-01 (6.5). 6.8 is listed for 2027-06-01, not released: PHP 8.5, Symfony 8, Twig 4, PHPUnit 13,
  Vite 8, no XML configuration.
- **Extension kinds** — a *plugin* (Composer type `shopware-platform-plugin`, a Symfony bundle in the shop's process, not
  usable on Shopware's cloud), an *app* (`manifest.xml` plus an app server over signed HTTP and sandboxed Twig scripts), a
  *theme* (plugin or app with `theme.json`). Prefer the app when the logic can sit behind HTTP.
- **Language and DI** — `declare(strict_types=1)`, constructor injection, services registered in `Resources/config/services.php`
  (PHP configuration; XML is deprecated since 6.7.14.0), attributes for routes and message handlers.
- **Data** — no ORM: the DAL (definitions or `#[Entity]` attribute entities since 6.6.3.0, `<entity>.repository`, `Criteria`),
  schema by `MigrationStep::update()`, Doctrine DBAL 4 (3 on 6.6) for raw SQL.
- **Frontend** — Storefront: Twig with `sw_extends`, Bootstrap 5.3, JS plugins on `PluginManager`, SCSS, webpack. Administration:
  Vue 3.5, Pinia, Vite, `Shopware.Component` + TwigJS blocks (stable), the Meteor Admin SDK for apps; Single File Components
  are experimental (6.7.16.0 and later).
- **Tests** — PHPUnit (11.5 in core on 6.7) with `IntegrationTestBehaviour`; Jest for Administration and Storefront JavaScript;
  Playwright via `@shopware-ag/acceptance-test-suite` for E2E (Cypress is deprecated).
- **Quality** — PHPStan 2.x with `shopwarelabs/phpstan-shopware`, PHP-CS-Fixer or ECS as the project has it,
  `shopware-cli extension validate`, `bin/console cache:clear` and `dal:validate`.

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.json` / `composer.lock` (`shopware/core`), the
plugin's `composer.json` constraint and the neighbouring files first and follow what they declare:

- **An older Shopware line** — the version of `shopware/core` in `composer.lock`. **6.6**: everything here works except what
  names a later version — `shopware-cli extension create` needs 6.7.13.0, Storefront components 6.7.11.0, `<crud>` in a
  manifest 6.7.3.0, config `cache-relevant` 6.7.12.0 (the config XSD rejects it before, which breaks plugin and app install), config `<tab>` and SFC
  6.7.16.0, dynamic task rescheduling 6.7.13.0, extension points (`ExtensionDispatcher`) 6.6.4.0; the shop runs Doctrine DBAL 3 where 6.7 has DBAL 4; the Administration is Webpack plus Vue 3 with the migration build and Vuex stores, Jest 29, PHPUnit 10.5. **6.5**: Vue 2.7, Vuex 3, vue-i18n 8, Webpack 4, `@vue/test-utils` 1,
  `Symfony\Component\Routing\Annotation\Route`; no attribute entities. Write to the declared line, never raise `~6.x.0`
  unasked, and do not share Administration code between 6.5 and 6.6 in one plugin version.
- **XML `services.xml` / `routes.xml`** — valid on 6.7 and earlier, a deprecation from 6.7.14.0, not loaded on 6.8. Keep the
  format in a file the slice does not otherwise change, write new files as PHP (`shopware-cli extension fix` converts old ones to YAML, which 6.8 still loads).
- **Definition classes instead of attribute entities** — the norm before 6.6.3.0 and still right for flags, computed fields and
  versioning; follow the project's existing entities.
- **Abstract route classes and decoration instead of extension events** — core Store API routes still ship `Abstract…Route`;
  the docs' newest example publishes through `ExtensionDispatcher`. Follow the project's neighbouring routes.
- **Webpack `webpack.config.js` or Vuex `Shopware.State` in an Administration plugin** — the pre-6.7 build and store; port to
  `vite.config.mts` and `Shopware.Store` only when moving the plugin to 6.7.
- **Cypress instead of Playwright** — Cypress specs are deprecated but run; keep them, write new E2E in Playwright only
  when the project agrees.
- **No Shopware CLI, a source checkout, or `custom/plugins` instead of `custom/static-plugins`** — use `bin/console plugin:create`,
  the checkout's `composer run build:js:*` / `watch:*` scripts (the production template has none: `shopware-cli project …`),
  and the plugin location the project already uses.
- **Another PHP code style or analyser** — ECS, a house `.php-cs-fixer.dist.php`, a PHPStan baseline: the project's rules win.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP shape, the public-API rule, context and request handling, errors, PHPStan, tooling, 6.8 readiness.
- `references/plugin-patterns.md` — composer.json, lifecycle, services, subscribers, config, migrations, scheduled tasks, queue, routes.
- `references/dal-patterns.md` — attribute and definition entities, flags, associations, extensions, Criteria, writes, indexers.
- `references/app-patterns.md` — manifest, registration and signing, app server, webhooks, app scripts, Admin SDK.
- `references/storefront-patterns.md` — Twig overrides, components, JS plugins, SCSS, themes and inheritance.
- `references/administration-patterns.md` — modules, components, data and state, ACL, Meteor Admin SDK, SFC status.
- `references/test-patterns.md` — PHPUnit unit and integration, Jest for Admin and Storefront, Playwright, CI order.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Extension kind and scaffold — plugin or app decision, `composer.json` / `manifest.xml`, base class, `services.php`, install, `cache:clear`.
2. Schema and data — migration, entity (attribute or definition), `EntityExtension` for core entities, `dal:validate`.
3. Services — use-case classes by constructor, subscribers, scheduled tasks, messages, configuration (`config.xml`).
4. Entry points — routes with their scope and `_acl`, controllers, Store API routes, app endpoints with signature checks.
5. Frontend — Storefront templates, JS plugin, SCSS; Administration module, components, snippets, privileges; build the assets.
6. Tests alongside each layer; PHPStan, `shopware-cli extension validate` and the suites pass before a layer counts as done.

## Anti-Patterns

- Adding a column to a core table, editing core or `vendor/` files, or using an `@internal` class; changing a migration that has run.
- Reading the container, keeping request state in a service, `Context::createDefaultContext()` in request code.
- A route without its `_routeScope`, an Admin API route without `_acl`, a field exposed without a decision about `ApiAware`.
- Associations read without being added to the `Criteria`, writes in a loop, an unbounded read instead of `RepositoryIterator`.
- A copied core template instead of a block override, literal strings instead of snippets, `|raw` on input, an edited `dist/`.
- A core JS plugin overridden twice, an Administration override where `extend` fits, Vue 2 idioms or Vuex on a 6.7 target.
- Relying on UI-only ACL, an SFC extension in production code, `updateDestructive()` expected to run for a plugin.
- An app that verifies only chosen query parameters, a secret in a Store app's manifest, a non-idempotent webhook handler.
- Tests that mock the DBAL `Connection`, depend on default shop data or `en_GB` / `EUR`, or share state through the database.

## Sources

> As of: 2026-11-11 · Basis: research

- Packagist, releases and constraints — https://packagist.org/packages/shopware/core, https://packagist.org/packages/shopware/app-php-sdk, https://packagist.org/packages/shopware/app-bundle, https://packagist.org/packages/shopwarelabs/phpstan-shopware, https://packagist.org/packages/shopware/dev-tools (6.7.16.0 2026-10-22, 6.6.10.31 2026-11-02, 6.5.8.19 2026-06-01; PHP and Symfony ranges; app-php-sdk 5.4.1, app-bundle 6.1.0, phpstan-shopware 0.2.5; dev-tools 1.6.0 accepts PHPUnit 9.6 to 13)
- Shopware platform sources, trunk and the 6.6.x / 6.5.x branches — https://github.com/shopware/shopware/blob/trunk/releases.json, https://github.com/shopware/shopware/blob/trunk/composer.json, https://github.com/shopware/shopware/blob/trunk/src/Administration/Resources/app/administration/package.json, https://github.com/shopware/shopware/blob/trunk/src/Storefront/Resources/app/storefront/package.json, https://github.com/shopware/shopware/blob/trunk/src/Core/Framework/Bundle.php (support dates; PHPUnit, Vue, Vite, Jest, Node versions; service loading and the XML deprecation, first present in v6.7.14.0)
- Shopware release and upgrade notes — https://github.com/shopware/shopware/blob/trunk/UPGRADE-6.8.md, https://github.com/shopware/shopware/blob/trunk/RELEASE_INFO-6.7.md (6.8 requirements; no XML configuration; `Request::get()`; scheduled-task executor; Vite 8; the 6.7.17.0 restrict-delete fix)
- Developer docs, plugins — https://github.com/shopware/docs/blob/main/guides/plugins/plugins/creating-plugins.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/plugin-base-guide.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/services/add-custom-service.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/event/listening-to-events.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/database/database-migrations.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/plugin-fundamentals/add-scheduled-task.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/plugin-fundamentals/plugin-lifecycle.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/plugin-fundamentals/add-plugin-configuration.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/store-api/add-store-api-route.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/message-queue/add-message-to-queue.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/storefront/controllers/add-custom-controller.md (layout, services.php, subscribers, migrations, tasks, routes, ADR-based route form)
- Developer docs, DAL — https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/entities-via-attributes.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/add-custom-complex-data.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/add-complex-data-to-existing-entities.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/reading-data.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/writing-data.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/add-data-translations.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/add-data-indexer.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/framework/data-handling/using-database-events.md (attribute entities since 6.6.3.0, extension instead of a core column, Criteria, iterator, indexer)
- Developer docs, apps — https://github.com/shopware/docs/blob/main/guides/plugins/apps/app-base-guide.md, https://github.com/shopware/docs/blob/main/guides/plugins/apps/lifecycle/app-registration-setup.md, https://github.com/shopware/docs/blob/main/guides/plugins/apps/lifecycle/app-signature-verification.md, https://github.com/shopware/docs/blob/main/guides/plugins/apps/lifecycle/webhook.md, https://github.com/shopware/docs/blob/main/guides/plugins/apps/app-scripts/custom-endpoints.md, https://github.com/shopware/docs/blob/main/resources/references/app-reference/manifest-reference.md, https://github.com/shopware/docs/blob/main/concepts/extensions/plugins-concept.md (manifest, setup handshake, signing, scripts; plugins are not compatible with cloud stores)
- Developer docs, Storefront and themes — https://github.com/shopware/docs/blob/main/guides/plugins/plugins/storefront/templates/customize-templates.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/storefront/javascript/add-custom-javascript.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/storefront/javascript/override-existing-javascript.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/storefront/styling/add-custom-styling.md, https://github.com/shopware/docs/blob/main/concepts/framework/storefront-components.md, https://github.com/shopware/docs/blob/main/guides/plugins/themes/create-a-theme.md, https://github.com/shopware/docs/blob/main/guides/plugins/themes/configuration/theme-configuration.md, https://github.com/shopware/docs/blob/main/guides/plugins/themes/inheritance/add-theme-inheritance.md (sw_extends, PluginManager, base.scss and overrides.scss, components since 6.7.11.0, theme.json)
- Developer docs, Administration — https://github.com/shopware/docs/blob/main/guides/plugins/plugins/administration/index.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/administration/single-file-components/roadmap.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/administration/module-component-management/customizing-components.md, https://github.com/shopware/docs/blob/main/guides/plugins/plugins/administration/permissions-error-handling/add-acl-rules.md, https://github.com/shopware/docs/blob/main/guides/upgrades-migrations/administration/pinia.md, https://github.com/shopware/docs/blob/main/guides/upgrades-migrations/administration/vite.md, https://github.com/shopware/docs/blob/main/guides/upgrades-migrations/administration/vue-migration-build.md, https://github.com/shopware/docs/blob/main/guides/plugins/apps/administration/meteor-admin-sdk.md (stable Options API route, SFC experimental from 6.7.16.0, Pinia and Vite in 6.7, ACL)
- Developer docs, testing and tooling — https://github.com/shopware/docs/blob/main/guides/development/testing/index.md, https://github.com/shopware/docs/blob/main/guides/development/testing/unit/php-unit.md, https://github.com/shopware/docs/blob/main/guides/development/testing/unit/jest-admin.md, https://github.com/shopware/docs/blob/main/guides/development/testing/unit/jest-storefront.md, https://github.com/shopware/docs/blob/main/guides/development/testing/e2e-playwright/install-configure.md, https://github.com/shopware/docs/blob/main/guides/development/testing/e2e-playwright/best-practices.md, https://github.com/shopware/docs/blob/main/guides/development/testing/legacy/index.md, https://github.com/shopware/docs/blob/main/guides/development/testing/ci.md, https://github.com/shopware/docs/blob/main/resources/guidelines/code/core/unit-tests.md, https://github.com/shopware/docs/blob/main/products/tools/cli/validation.md (test setup, Cypress deprecated, isolation rules, validation tools)
- npm and PHPUnit — https://www.npmjs.com/package/@shopware-ag/acceptance-test-suite, https://www.npmjs.com/package/@shopware-ag/jest-preset-sw6-admin, https://www.npmjs.com/package/@shopware-ag/meteor-admin-sdk, https://www.npmjs.com/package/@shopware-ag/meteor-component-library, https://phpunit.de/announcements/phpunit-12.html (12.26.0, 6.0.6, 6.17.0; annotations removed in PHPUnit 12)
