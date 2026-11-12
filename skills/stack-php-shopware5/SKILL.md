---
name: stack-php-shopware5
description: CRAFT stack-pack for maintaining legacy Shopware 5 shops and plugins (end-of-life since July 2024, last release 5.7.20) — safe change without upstream patches, the 5.2+ plugin system and the legacy Bootstrap.php system, Smarty templates and themes, the ExtJS backend and the REST API, pragmatic PHPUnit tests, and short rules for cutting new logic so a later move to Shopware 6 stays cheap. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — Shopware 5 (legacy maintenance)

The code-near personality layer for a Shopware 5 shop or plugin — written for the 5.7 line (5.7.20, PHP 7.4 to 8.2) and meant
for **maintenance**: Shopware 5 is end-of-life, so the pack favours small, conservative, well-tested change over modernisation.
It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`, `/craft:refactor` and `/craft:review`
when `rules.md` declares it in its `## Personality` block. Shopware 5 is no Symfony full-stack application (single Symfony
components, Doctrine and the Enlight layer), but a pack is monolithic (D27): the PHP idioms it needs are restated here, so a
Shopware 5 project declares this pack instead of `stack-php`. Project-specific conventions — the supported PHP and shop version,
exact commands, who patches security — live in the project's own `rules.md`. Versions below were verified on 2026-11-11 (see
`## Sources`); a newer release may have moved.

## Stack

- **End of life** — Shopware AG supported Shopware 5 with bug fixes until July 2023 and security fixes until the end of July 2024;
  the last release is 5.7.20 (2025-06-05) and the `shopware5/shopware` repository says it is no longer maintained. SafeFive
  (a commercial third party) offers security updates, a fork (`v5.7.20-safefive2`, 2026-08-02) and continues the documentation.
  There are no upstream patches: every fix is yours or the shop owner's decision to buy.
- **PHP** — 5.7.20 allows `~7.4 || ~8.0 || ~8.1 || ~8.2` (the unreleased branch head adds 8.3). On 2026-11-11 only 8.2 (security
  until 2026-12-31) and 8.3 are supported by PHP itself; 7.4, 8.0 and 8.1 get no fixes. Write to the shop's lowest PHP.
- **Framework** — the Enlight layer (Zend-derived events, hooks, controllers), Symfony 4.4 components (DI, Console, HttpKernel),
  Doctrine ORM 2.15 with annotation mapping and DBAL 2.13, Smarty 3, MySQL 5.7 or newer.
- **Plugins** — two systems side by side: the 5.2+ system (`custom/plugins/<Name>`, base class, `services.xml`, XML resources, migrations
  from 5.6.0) and the legacy `Bootstrap.php` system (`engine/Shopware/Plugins/…`). Extend by events, decoration and theme inheritance; never edit the core.
- **Frontend and backend** — Smarty block inheritance, `Theme.php`, LESS, jQuery 3.6 plugins on the `$.plugin` base class; ExtJS 4.1 backend
  modules; the REST API (Digest or Basic auth) with resources in `Shopware\Components\Api\Resource`.
- **Tests** — PHPUnit 9.6 (the only major the platform's test base supports): pure unit tests first, kernel tests on a development copy.
- **Quality** — PHPStan (the core pins 1.10.20 at level 8, `phpVersion: 70400`), PSR-1/PSR-2 via the project's php-cs-fixer, `composer audit`.

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.lock` (`shopware/shopware`), `plugin.xml`
(`<compatibility>`), the plugin's directory and its neighbours first and follow what they declare:

- **An older 5.x line** — last releases 5.6.10 (2021-05-04, PHP `^7.2`) and, all on `^5.6.4 || ^7.0`, 5.5.10 (2019), 5.4.6 and 5.3.7 (2018) and 5.2.27 (2017); 5.7.0 needs
  `^7.4`, with PHP 8.0 from 5.7.3, 8.1 from 5.7.7 and 8.2 from 5.7.17. Features carry a version: the 5.2+ plugin system 5.2.0,
  controller auto-registration 5.2.7, frontend resources auto-registration 5.2.13, API resources as services 5.2.17, HTTP Basic for
  the API 5.3.2, discarding an ancestor theme's LESS/JavaScript 5.4, hooks as `Enlight_Hook` and plugin migrations (`sw:generate:migration`)
  and the plugin-specific logger 5.6. Write to the declared line and never raise `minVersion` or the shop version unasked.
- **A legacy `Bootstrap.php` plugin** — maintain it in its own style (`legacy-plugin-patterns.md`); convert to the 5.2+ system only in a slice that says so.
- **A 5.2+ plugin and a legacy one in the same shop** — the same CLI installs both; migrations, `services.xml` and the context objects exist only in the new system.
- **A plugin without any tests** — extract the rule into a plain class and pin it with a characterization test before changing it (`references/test-patterns.md`).
- **A release-ZIP shop, a Git checkout or the SafeFive fork** — the ZIP ships `vendor/` and no `tests/` (export-ignored); a checkout has the core tests and
  a Makefile (older ones an `ant` build); the SafeFive fork keeps the layout with its own release tags. Use the commands the project already has.
- **Another code style or analyser** — a `phpcs.xml`, an older `.php_cs.dist`, a PHPStan baseline or none: the project's rules win; add no tool unasked.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP floors, the mandatory shape, security without upstream patches, static analysis.
- `references/plugin-patterns.md` — 5.2+ plugin layout, lifecycle, migrations, services, subscribers, config, cron, models, attributes, commands.
- `references/legacy-plugin-patterns.md` — the `Bootstrap.php` system: lifecycle, subscriptions, what to keep and what to leave.
- `references/frontend-patterns.md` — Smarty inheritance and blocks, `Theme.php`, LESS, jQuery plugins and the StateManager.
- `references/backend-api-patterns.md` — ExtJS modules and overrides, backend components, ACL, REST resources and controllers.
- `references/test-patterns.md` — PHPUnit 9.6 unit and kernel tests, characterization tests, what the platform does not carry.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Read the shop: Shopware, PHP and plugin versions, the plugin system, the existing tests. Reproduce the symptom on a development copy.
2. Schema and data — a migration (5.6.0+) or the install/update step, attribute columns through the CRUD service; never edit a core table.
3. Logic — plain classes by constructor; subscribers and controllers stay thin; configuration in `config.xml`.
4. Entry points — events, hooks as the last resort, controllers, REST resources with their privilege checks and CSRF handling.
5. Frontend and backend — Smarty blocks by `{extends}`, theme LESS and JavaScript, ExtJS overrides; clear the theme and shop caches.
6. Tests alongside each layer; the project's static analysis (if it has any) and its suites pass, and install, update and uninstall run clean on the copy before a layer counts as done.

## Toward Shopware 6

Not a migration guide — five rules for *new* logic so a later move stays cheap. (Shopware's Migration Assistant moves shop data such as
products and customers; nothing in it carries plugin code, so a plugin is rebuilt as a Shopware 6 extension.)

- Business rules live in plain classes with no `Shopware\…`/`Enlight_*` import; one thin adapter per hook point calls them.
- A plugin's own data goes in its own tables keyed by core ids; new attribute columns on core tables only when the backend must edit them.
- Integrations use the REST API or HTTP clients behind an interface, not in-process hooks into core classes.
- Smarty and ExtJS stay presentation: no pricing, validation or permission rules in templates or JavaScript.
- Write the data contract (tables, columns, config keys) in the plugin's `Readme`, and do not build a Shopware 6 compatibility layer unasked.

## Anti-Patterns

- Editing `engine/`, `vendor/` or a core theme, or copying a core template instead of extending its block.
- String-built SQL, an unescaped Smarty value, `allowHtml` on untrusted data, a widened Smarty security policy, debug settings in production.
- Raising the PHP or Shopware version, a core package or a plugin's `minVersion` as a side effect; converting a legacy plugin unasked.
- A migration changed after it ran; `install()` or `update()` that is not safe to run twice; an uninstall that drops data when `keepUserData()`.
- `Shopware()` or `container->get()` deep in business code, sensitive data assigned to the view in a global `PostDispatch` handler.
- A hook where an event fits; an ExtJS override of a whole file instead of one method with `callParent`.
- A second jQuery or library the theme already bundles; a `getSubscribedEvents()` change in a legacy plugin without an `update()` step.
- Tests that depend on demo data, order or a third-party HTTP call, or that assume a transaction undoes `CREATE`/`ALTER`; a mocked DBAL connection.

## Sources

> As of: 2026-11-11 · Basis: research

- Packagist, releases and constraints — https://packagist.org/packages/shopware/shopware, https://packagist.org/packages/phpunit/phpunit, https://packagist.org/packages/phpstan/phpstan, https://packagist.org/packages/phpstan/phpstan-doctrine, https://packagist.org/packages/friendsofphp/php-cs-fixer (5.2.27, 5.3.7, 5.4.6, 5.5.10, 5.6.10, 5.7.20 and the PHP constraint per release; PHPUnit 9.6.38 on PHP 7.3 and newer; PHPStan 2.3.5 on PHP 7.4 and newer)
- Shopware 5 platform, tag v5.7.20 — https://github.com/shopware5/shopware/blob/v5.7.20/composer.json, https://github.com/shopware5/shopware/releases/tag/v5.7.20, https://github.com/shopware5/shopware/blob/v5.7.20/UPGRADE-5.6.md, https://github.com/shopware5/shopware/blob/v5.7.20/UPGRADE-5.7.md, https://github.com/shopware5/shopware/blob/v5.7.20/.gitattributes, https://github.com/shopware5/shopware/blob/v5.7.20/.phpstan.neon (requirements and pins, release date, plugin migrations and `sw:generate:migration` from 5.6, `tests/` export-ignored, PHPStan level 8)
- Shopware 5 platform, branch 5.7 and the SafeFive fork — https://github.com/shopware5/shopware/blob/5.7/README.md, https://github.com/shopware5/shopware/blob/5.7/composer.json, https://github.com/safefive/shopware, https://safefive.de/, https://devdocs.safefive.de/ (repository no longer maintained, PHP 8.3 on the branch head only, SafeFive security service, fork tags and documentation)
- Shopware AG, end of life — https://www.shopware.com/en/news/shopware-5-how-it-continues/, https://www.shopware.com/en/migration/shopware-5-to-shopware-6/ (bug fixes until July 2023, security fixes until July 2024, no 5.8; SafeFive takes over support)
- Core sources, plugin system — https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/Plugin.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Bundle/PluginInstallerBundle/Service/PluginInstaller.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Bundle/PluginInstallerBundle/Service/LegacyPluginInstaller.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/Plugin/Bootstrap.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/Migrations/PluginMigrationManager.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Commands/GenerateMigrationCommand.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/DependencyInjection/commands.xml, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/Plugin/schema/config.xsd (install order, legacy result handling, migrations folder and table, command names, config element types)
- Core sources, rendering and security — https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/DependencyInjection/Bridge/Template.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Configs/Default.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Components/Theme/PathResolver.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Controllers/Backend/ExtJs.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Shopware/Controllers/Api/Articles.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Library/Smarty/Smarty.class.php (escape modifiers, Smarty security policy, plugin theme folder, backend ACL hooks, `useNumberAsId`, Smarty-3.1.12)
- Core sources, tests — https://github.com/shopware5/shopware/blob/v5.7.20/Makefile, https://github.com/shopware5/shopware/blob/v5.7.20/tests/phpunit.xml.dist, https://github.com/shopware5/shopware/blob/v5.7.20/tests/phpunit_unit.xml.dist, https://github.com/shopware5/shopware/blob/v5.7.20/tests/Functional/TestKernel.php, https://github.com/shopware5/shopware/blob/v5.7.20/tests/Functional/Components/Plugin/TestCase.php, https://github.com/shopware5/shopware/blob/v5.7.20/tests/Functional/Traits/DatabaseTransactionBehaviour.php, https://github.com/shopware5/shopware/blob/v5.7.20/tests/Unit/Plugin/Backend/Auth/BootstrapTest.php, https://github.com/shopware5/shopware/blob/v5.7.20/engine/Library/Enlight/Components/Test/Controller/TestCase.php (test layout, kernel on the shop database, plugin test base, transaction trait, Enlight mocks)
- Developer docs, plugins — https://github.com/shopware5/devdocs/blob/main/source/developers-guide/plugin-quick-start/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/legacy-plugin-system/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/shopware-5-plugin-update-guide/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/plugin-guidelines/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/attribute-system/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/models/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/event-guide/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/dic-tags/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/shopware-5-cli-commands/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/plugin-testing/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/csrf-protection/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/coding-standards/index.md (layout, lifecycle, services, hooks, attributes, versions per feature, logging, CSRF, testing)
- Developer docs, frontend, backend and API — https://github.com/shopware5/devdocs/blob/main/source/designers-guide/smarty/index.md, https://github.com/shopware5/devdocs/blob/main/source/designers-guide/theme-startup-guide/index.md, https://github.com/shopware5/devdocs/blob/main/source/designers-guide/configuration-using-theme-php/index.md, https://github.com/shopware5/devdocs/blob/main/source/designers-guide/javascript-statemanager-and-pluginbase/index.md, https://github.com/shopware5/devdocs/blob/main/source/designers-guide/modify-jquery-plugins/index.md, https://github.com/shopware5/devdocs/blob/main/source/designers-guide/custom-templates/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/backend-extension/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/backend-components/basics/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/backend-escaping/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/lightweight-backend-modules/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/rest-api/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/rest-api/plugin-api-extension/index.md, https://github.com/shopware5/devdocs/blob/main/source/developers-guide/rest-api/extend-api-resource/index.md, https://github.com/shopware5/devdocs/blob/main/source/sysadmins-guide/system-requirements/index.md (themes, inheritance, StateManager, ExtJS modules, backend components, REST authentication and resources)
- Composer installer types — https://github.com/composer/installers/blob/main/src/Composer/Installers/ShopwareInstaller.php (`shopware-plugin`, the legacy section types, `shopware-frontend-theme` and their target folders)
- PHP and PHPUnit — https://www.php.net/supported-versions.php, https://www.php.net/releases/index.php?json&version=8.1, https://www.php.net/manual/en/migration81.deprecated.php, https://www.php.net/manual/en/migration82.deprecated.php, https://phpunit.de/supported-versions.html (8.2 to 8.5 support dates, last 7.4 / 8.0 / 8.1 releases, the 8.1 and 8.2 deprecations, PHPUnit 9 support window)
- Doctrine — https://github.com/doctrine/dbal/blob/2.13.9/docs/en/reference/data-retrieval-and-manipulation.rst, https://github.com/doctrine/migrations/blob/3.9.x/docs/en/explanation/implicit-commits.rst (DBAL 2.13 fetch methods and parameter binding; MySQL does not run DDL inside a transaction)
- Shopware 6 migration — https://github.com/shopware/docs/blob/main/products/extensions/migration-assistant/index.md (the Migration Assistant migrates shop data from Shopware 5)
