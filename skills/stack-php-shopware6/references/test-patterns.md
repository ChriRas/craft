# Shopware 6 — Test Patterns

Tests on three levels: **PHPUnit** for PHP (unit and integration), **Jest** for Administration and Storefront JavaScript,
**Playwright** (Shopware's acceptance test suite) for end-to-end. Written for 6.7; 6.6 and 6.8 differences are marked.
Run the fast checks first (static analysis, unit), the slow ones last (integration, E2E) — Shopware's own CI advice.

## Which level proves what

| Level | Boots | Proves | Example |
|---|---|---|---|
| PHPUnit unit | nothing | one class's logic against doubles | price label builder, a handler's branches, a subscriber's guard |
| PHPUnit integration | the kernel and a test database | wiring and persistence: DI container, DAL definition + migration, events, routes | repository round trip, migration `update()`, route response |
| Jest (Admin / Storefront) | jsdom | a component's or JS plugin's behaviour | list renders rows, a plugin reacts to a click |
| Playwright E2E | a running shop and a browser | a user journey end to end | the module saves an entity, the storefront shows it |

Most tests are the cheap ones. Keep one integration test per DAL entity (definition and migration agree) and per route, and
a handful of journeys at the top.

## PHPUnit setup in a plugin

`phpunit.xml` at the plugin root (the generated one points the suite at `tests/`); `tests/TestBootstrap.php`:

```php
<?php declare(strict_types=1);

use Shopware\Core\TestBootstrapper;

$loader = (new TestBootstrapper())
    ->addCallingPlugin()
    ->addActivePlugins('SwagExample')
    ->setForceInstallPlugins(true)      // plugin is installed and active even if the test database already existed
    ->bootstrap()
    ->getClassLoader();

$loader->addPsr4('Swag\\Example\\Tests\\', __DIR__);
```

```xml
<php>
    <ini name="error_reporting" value="-1"/>
    <server name="KERNEL_CLASS" value="Shopware\Core\Kernel"/>
    <env name="APP_ENV" value="test"/>
    <env name="APP_DEBUG" value="1"/>
    <env name="SYMFONY_DEPRECATIONS_HELPER" value="weak"/>
</php>
```

Run from the project root with the project's PHPUnit: `./vendor/bin/phpunit --configuration="custom/plugins/SwagExample"`,
`--testsuite "migration"`, `--filter testNoChanges`. Integration tests write to the database: run them with `APP_ENV=test` against a database
that holds no real data.

- **PHPUnit version**: the platform repository's own `require-dev` pins PHPUnit `^11.5.19` on 6.7 (6.7.16.0), `^10.5.38` on 6.6 and
  moves to **13 on 6.8**; `shopware/dev-tools` (1.6.0), the usual way a project gets PHPUnit, accepts 9.6 to 13. So the version in a
  project is whatever it resolved: read `composer.lock`. A plugin that supports several Shopware lines should require the PHPUnit
  it targets in its own `require-dev` and run that, as the 6.8 upgrade notes suggest. Use attributes (`#[CoversClass]`,
  `#[DataProvider]`, `#[Test]`), not annotations — doc-comment annotations were deprecated in PHPUnit 11 and removed in PHPUnit 12.
- Plugin test namespaces and folders (`tests/` or `src/Test`) follow the generated `phpunit.xml`; keep them out of the
  production autoload so test classes are not shipped.

### Unit tests

Instantiate the class with real collaborators where they are cheap and stubs where they are not; no kernel, no database.

```php
#[CoversClass(PriceLabelBuilder::class)]
final class PriceLabelBuilderTest extends TestCase
{
    public function testBuildsLabelForSalesChannel(): void
    {
        $config = $this->createStub(SystemConfigService::class);
        $config->method('getString')->willReturn('Sale');

        static::assertSame('Sale', (new PriceLabelBuilder($config))->build(Uuid::randomHex()));
    }
}
```

Shopware's own unit-test guideline (a good house style for a plugin):

- One `#[CoversClass]` per test class; no traits in a unit test class (fixture builders go into static fixture classes);
  `createStub()` for a double that never has `->expects()`, `createMock()` only with expectations.
- **Do not behaviour-mock the DBAL `Connection`** (asserting SQL text or parameters): put SQL behind a small adapter class
  and cover that adapter with an integration test. Test the logic around it against a narrow repository or gateway stub.
- `StaticEntityRepository` (`Shopware\Core\Test\Stub\DataAbstractionLayer`) is the stand-in for an `EntityRepository` that
  returns prepared results; `Symfony\Component\Clock\Test\ClockSensitiveTrait` freezes time.
- Data providers instead of near-duplicate tests, a named case per row; assert exceptions with `expectExceptionObject()`.
- No `exit()` / `die()` in code under test; no reflection into private methods of Shopware classes; no process isolation.
- Test the failure path as well as the happy path; clean up whatever the test registered (listeners, files).

### Integration tests

```php
final class ExampleRepositoryTest extends TestCase
{
    use IntegrationTestBehaviour;   // Shopware\Core\Framework\Test\TestCaseBase — wraps the test in a DB transaction, clears caches

    public function testCreatesAndReadsAnExample(): void
    {
        /** @var EntityRepository<ExampleCollection> $repository */
        $repository = $this->getContainer()->get('swag_example.repository');
        $id = Uuid::randomHex();
        $context = Context::createDefaultContext();

        $repository->create([['id' => $id, 'name' => 'A', 'active' => true]], $context);

        static::assertSame('A', $repository->search(new Criteria([$id]), $context)->first()?->name);
    }
}
```

- `IntegrationTestBehaviour` (kernel + database transaction + cache handling), `KernelTestBehaviour` (container access via
  `getContainer()` only), `DatabaseTransactionBehaviour`, `SalesChannelApiTestBehaviour` for Store API calls. In an integration
  test `Context::createDefaultContext()` is correct; in production code it is not (`code-quality-standards.md`).
- Override a service for the test run (an API client, a mailer, a file deleter) in `src/Resources/config/services_test.php`;
  it is loaded in the test environment only.
- **Migration test**: run `update()` on the current schema and compare `SHOW CREATE TABLE` before and after (idempotent); drop
  the table, run `update()` again and assert it exists. The guide's example uses `fetchAssoc()` / `fetchColumn()`, which DBAL 4
  (Shopware 6.7) no longer has — use `fetchAssociative()` / `fetchOne()`.
- Integration-test a route through the kernel (a Store API request with a sales channel context, or an Admin API call with
  an integration's token) and assert status, JSON shape and that a missing privilege is refused.
- Tests must not depend on data left by another test, and must leave none behind (the transaction does, unless the code
  commits itself).

## Jest — Administration

Spec files sit beside the code: `*.spec.js` / `*.spec.ts`. Components are registered on the global `Shopware` object, so import
the file (registering it), then build and mount the component:

```js
import { mount } from '@vue/test-utils';
import flushPromises from 'flush-promises';
import './index';   // the spec sits beside the component; registers it on the global Shopware object

async function createWrapper() {
    return mount(await Shopware.Component.build('swag-example-list'), {
        global: {
            stubs: { 'sw-page': true, 'sw-card': true, 'sw-data-grid': true },
            provide: {
                repositoryFactory: { create: () => ({ search: () => Promise.resolve([{ id: '1', name: 'A' }]) }) },
                acl: { can: () => true },
            },
        },
    });
}

describe('swag-example-list', () => {
    it('renders the loaded items', async () => {
        const wrapper = await createWrapper();
        await flushPromises();
        expect(wrapper.vm.items).toHaveLength(1);
    });
});
```

- `Shopware.Component.build(name)` returns the component with every extend/override and template block resolved; test the
  built component, and test an override by importing the base **and** the override.
- Stub the `sw-*` children, `provide` the injected services (`repositoryFactory`, `acl`, `httpClient`, notification mixin
  methods), prefer `shallowMount` or stubs over deep rendering. Assert input → output; flush promises after async work.
- 6.7 ships Vue 3.5 with `@vue/test-utils` 2.4: use `mount` and `wrapper.unmount()`. The guide's boilerplate still shows the
  Test Utils 1 API (`createLocalVue`, `wrapper.destroy()`) — that is for the Vue 2 line (6.5).
- The commands `composer run admin:unit` / `admin:unit:watch` / `admin:create:test` belong to the **platform** checkout. A plugin
  needs its own Jest setup: the `@shopware-ag/jest-preset-sw6-admin` preset (6.0.6, published 2026-03-10) sets the global
  `Shopware` object up and needs the path of the Administration source (its README says `globals.adminPath`, its code reads `process.env.ADMIN_PATH` — check both against
  the version you target) and maps `src/…` imports to the **core** Administration, so import your own files relatively. Core runs Jest 30 on 6.7 and 29 on 6.6.
- A test that logs to the console fails in core's setup (`jest-fail-on-console`); keep the plugin's tests quiet too.
- An SFC extension (experimental, 6.7.16.0+) cannot be tested yet.

## Jest — Storefront

Plain Jest on ES modules: a helper or JS plugin imports directly (`import Feature from 'src/helper/feature.helper'`), no
Shopware global to build. Put tests in the folder your `package.json` Jest config points at (the platform uses
`…/storefront/test/…` mirroring `src/`), name them after the unit (`*.test.js`).

```js
// window.PluginBaseClass and a window.PluginManager mock are set up before this import (see below)
import ExamplePlugin from 'src/example-plugin/example-plugin.plugin';

test('shows the configured text on click', () => {
    document.body.innerHTML = '<button data-example-plugin></button>';
    const alertSpy = jest.spyOn(window, 'alert').mockImplementation(() => {});
    new ExamplePlugin(document.querySelector('[data-example-plugin]'), { text: 'Hi' }, 'ExamplePlugin');
    document.querySelector('button').click();
    expect(alertSpy).toHaveBeenCalledWith('Hi');
});
```

The plugin file reads `window.PluginBaseClass` at import time and `PluginBaseClass`'s constructor reads `window.PluginManager`, so a test sets
up both first (`window.PluginBaseClass = <the core base class>`, a `window.PluginManager` mock) and only then imports the plugin. Reset the DOM and
mocks in `beforeEach`; test `fetch`-based code with a mocked `fetch` and an HTML fixture of the response.

## Playwright — end to end

Cypress is deprecated and no longer maintained (Shopware's legacy testing page); new E2E is **Playwright with the Shopware
Acceptance Test Suite**, `@shopware-ag/acceptance-test-suite` (12.26.0 on 2026-11-05). It is a drop-in
extension of Playwright with fixtures, page objects, API clients and test-data helpers, run against any shop over its APIs.

```bash
npm init playwright@latest && npm install @shopware-ag/acceptance-test-suite && npx playwright install && npx playwright install-deps
```

```dotenv
APP_URL="https://shop.test"
SHOPWARE_ACCESS_KEY_ID="…"          # integration (recommended); or SHOPWARE_ADMIN_USERNAME / SHOPWARE_ADMIN_PASSWORD
SHOPWARE_SECRET_ACCESS_KEY="…"
```

```ts
// BaseTestFile.ts — one base file; "type": "module" in package.json
import { test as base } from '@shopware-ag/acceptance-test-suite';
export * from '@shopware-ag/acceptance-test-suite';
export const test = base.extend({ /* your fixtures */ });

// tests/Example.spec.ts
import { test } from './../BaseTestFile';

test('product is added to the cart', async ({ ShopCustomer, StorefrontProductDetail, TestDataService, AddProductToCart }) => {
    const product = await TestDataService.createBasicProduct();
    await ShopCustomer.goesTo(StorefrontProductDetail.url(product));
    await ShopCustomer.attemptsTo(AddProductToCart(product));
    await ShopCustomer.expects(StorefrontProductDetail.offCanvasSummaryTotalPrice).toBeVisible(); // no literal price: locale/currency vary
});
```

- Fixtures: `DefaultSalesChannel` (a fresh sales channel and default customer per worker), `AdminApiContext`, `StoreApiContext`
  (log a customer in with `login()`), `TestDataService`, page objects (`StorefrontProductDetail`, `AdminManufacturerCreate`, …) and
  actors (`ShopCustomer`, `ShopAdmin`) following the actor pattern: *goes to* a page, *attempts* a task, *expects* a result.
- **Isolation is the rule**: create every record the test needs (through `TestDataService`, which also cleans up), find it by
  its ID or a unique name, never expect a list to contain exactly one item, never rely on default rules/flows/categories or on
  `en_GB`/`EUR`, never change global settings (settings of your own sales channel are fine).
- Credentials for a sandbox (a payment provider) go into a separate `*.init.ts` project with traces off.
- Check an E2E test against a shop on the version you ship for: the suite publishes daily images per Shopware version
  (`SHOPWARE_VERSION=trunk docker compose up --wait shopware` inside the suite's repo).
- An app's Administration iframe is tested like any web page; an app server is tested with the SDK's signing helpers plus a
  recorded Shopware request (`app-patterns.md`).

## CI order for an extension

1. `shopware-cli extension validate` (builtin checks, PHPStan, ESLint, Stylelint, Twig lint) and the project's code style.
2. PHPUnit unit, then integration (a Shopware test environment per supported Shopware × PHP combination).
3. Jest.
4. `shopware-cli extension build` to produce the ZIP once; run E2E against that artifact in a shop; promote the same artifact.

## Review checklist

- [ ] A new class has a unit test or a stated reason; a new entity, migration and route have an integration test.
- [ ] No test uses production data, shared state or the wall clock; doubles are stubs unless they carry expectations.
- [ ] The test fails when the behaviour is broken (flip the condition once to see it red).
- [ ] Admin tests mount the **built** component with stubs and provided services; E2E creates and cleans its own data.
- [ ] The CI matrix covers every `shopware/core` line the `composer.json` constraint allows.
