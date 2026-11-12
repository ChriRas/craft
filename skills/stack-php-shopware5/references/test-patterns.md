# Shopware 5 — Test Patterns (pragmatic PHPUnit 9.6)

Most Shopware 5 plugins have no tests, and the platform carries only part of what a plugin test would want. The pack's
rule: **test the logic in isolation, and use the kernel only where the behaviour is the database or the container.**
What the infrastructure provides was read from the 5.7.20 sources on 2026-11-11 (see `SKILL.md` → `## Sources`).

## What exists and what it costs

- **Runner**: PHPUnit **9.6** (`"phpunit/phpunit": "^9.6"` in the core's `require-dev`, `>= PHP 7.3`). PHPUnit 9's active
  support ended on 2024-02-02, and 10 and later need PHP 8.1 and a changed API, which the core's test base classes are not
  written for — do not mix versions. Annotations such as `@dataProvider` are the supported form in 9.6.
- **Core test layout** (a Git checkout, not a release archive): `tests/Unit/` (no kernel), `tests/Functional/`
  (boots the real application), `tests/Mink/` (Behat browser tests), `tests/phpunit.xml.dist`, `tests/phpunit_unit.xml.dist`;
  `make test-phpunit` runs both PHPUnit configs; `npm run test --prefix ./themes/Frontend/Responsive` runs the theme's Jest tests.
- **`tests/` is `export-ignore`d** in the repository's `.gitattributes`, so a shop installed from the release ZIP or a Composer
  dist archive has *no* core test bootstrap. Plugin functional tests need a source checkout (`composer install --prefer-source`
  or a Git clone) with the dev dependencies; check `tests/Functional/bootstrap.php` exists before planning one.
- **CSRF protection is off in the functional config** (`csrfprotection.frontend` / `.backend` = `false` in
  `tests/Functional/config.php`): a missing `CSRFWhitelistAware` entry or token is invisible to the tests; check it by hand.
- **The functional kernel uses the shop's own database.** `TestKernel('testing', true)` boots with `tests/Functional/config.php`
  merged over the shop's configuration, so it reads and writes the configured database. Run it on a development copy, never
  against production data, and never assume an empty database.

## 1. Isolated logic — no kernel (the default)

Put the plugin's logic in plain classes behind constructors (`Components/`, see `code-quality-standards.md`) and test those with
plain `PHPUnit\Framework\TestCase`. Autoload the plugin and the shop's classes with the shop's `autoload.php`.

```php
final class PriceRoundingTest extends \PHPUnit\Framework\TestCase
{
    /**
     * @dataProvider provideAmounts
     */
    public function testRoundsToFiveCents(float $in, float $expected): void
    {
        static::assertSame($expected, (new PriceRounding())->roundToFiveCents($in));
    }

    public function provideAmounts(): array
    {
        return [[1.02, 1.00], [1.03, 1.05], [0.0, 0.0]];
    }
}
```

- Inject a clock, a configuration array and small interfaces instead of calling `Shopware()` or `new DateTime()` in the
  class under test. A class whose only dependency is `Doctrine\DBAL\Connection` is tested in layer 3, not with a mocked connection.
- The core's own unit tests show the Enlight-level seams: a subscriber or controller handler is called with an
  `Enlight_Controller_ActionEventArgs` carrying a mocked `Enlight_Controller_Action` and an
  `Enlight_Controller_Request_RequestTestCase`; assert what was assigned to the view or returned (the core's `Auth` plugin test is the pattern).

```php
$request = new Enlight_Controller_Request_RequestTestCase();
$request->setModuleName('frontend');
$request->setControllerName('detail');

$view = $this->createMock(Enlight_View_Default::class);
$view->expects(static::once())->method('assign')->with('swagNote', 'note');

$action = $this->createMock(Enlight_Controller_Action::class);
$action->method('Request')->willReturn($request);
$action->method('View')->willReturn($view);

$args = new Enlight_Controller_ActionEventArgs();
$args->set('subject', $action);
$subscriber->onPostDispatch($args);
```

## 2. Characterization tests for a plugin with none

1. Pick the smallest unit that holds a rule (a price calculation, a mapping, a validation) — often a private method of a
   subscriber or the `Bootstrap.php`. Extract it into a class *without changing its behaviour*, in one commit.
2. Write tests that pin today's output for representative inputs, including the odd ones, before changing anything.
3. Only then change the behaviour, in a second commit. The legacy `Bootstrap.php` itself stays untested glue.

## 3. Functional tests with the kernel

A plugin's `phpunit.xml.dist` and `Tests/Functional/Bootstrap.php` (the path in the `require` depends on where the plugin
sits — `custom/plugins/<Name>/Tests/Functional` is five levels below the shop root):

```xml
<phpunit bootstrap="./Tests/Functional/Bootstrap.php" colors="true" backupGlobals="false">
    <testsuites><testsuite name="SwagOrderNote"><directory>./Tests</directory></testsuite></testsuites>
</phpunit>
```

```php
<?php
require __DIR__ . '/../../../../../tests/Functional/bootstrap.php';
```

```php
use Shopware\Tests\Functional\Traits\ContainerTrait;
use Shopware\Tests\Functional\Traits\DatabaseTransactionBehaviour;

final class OrderNoteLoaderTest extends \Shopware\Tests\Functional\Components\Plugin\TestCase
{
    use ContainerTrait;
    use DatabaseTransactionBehaviour;       // BEGIN before each test, ROLLBACK + Models()->clear() after

    protected static $ensureLoadedPlugins = ['SwagOrderNote' => ['maxLength' => 200]];

    public function testLoadsNotesOfOneOrder(): void
    {
        $connection = $this->getContainer()->get(\Doctrine\DBAL\Connection::class);
        $connection->insert('swag_order_note', ['order_id' => 15, 'note' => 'gift']);

        $loader = $this->getContainer()->get('swag_order_note.order_note_loader');

        static::assertSame([['note' => 'gift']], array_map(
            static fn (array $row): array => ['note' => $row['note']],
            $loader->loadByOrder(15)
        ));
    }
}
```

- `Plugin\TestCase` installs and activates the plugins named in `$ensureLoadedPlugins` (with config values) before the class
  and restores their previous state afterwards; the less a test needs the shop stack, the better it is written.
- `DatabaseTransactionBehaviour` isolates **DML**. MySQL does not run DDL inside a transaction: a test that runs `CREATE TABLE`,
  `ALTER TABLE` or a plugin migration is not rolled back by it, and PDO on PHP 8 raises "There is no active transaction" when
  the code then ends a transaction the DDL already committed. Test migrations and attribute creation on a throwaway
  database, or assert them through the installer in `setUpBeforeClass` / `tearDownAfterClass` pairs that undo them.
- `FixtureBehaviour::executeFixture($file)` runs an SQL fixture; create the rows a test needs instead of relying on the
  demo shop (product numbers, customer ids and `en_GB` / `EUR` differ between installations).
- For a controller or routing test extend `Enlight_Components_Test_Controller_TestCase` and call `$this->dispatch('/swag_note')`;
  then read `$this->Response()`, `$this->View()`, `$this->Request()`. It runs the real front controller with the real
  database: keep such tests few, on the plugin's own routes.
- Reset what you changed: `Shopware()->Models()->clear()`, cache state, config values saved with `saveConfigElement`.
- A test that depends on test order, the wall clock, an HTTP call to a third party, or a leftover row is broken; mock the
  external client behind an interface (layer 1) and keep the rest in the transaction.

## 4. The browser, the backend, the REST API

- Backend ExtJS code has no unit-test setup in the platform: test its PHP controller in layer 3 and verify the screens by
  hand in a development shop (the Phase-5 content). Do not add Jest or Karma to a plugin unless the project has it.
- Storefront JavaScript: the Responsive theme has Jest; a plugin's jQuery plugin is tested there only if the project already
  wires it. Smoke-test a template change by rendering the page in the development shop and reading the HTML.
- REST: call the resource class directly in a functional test (`\Shopware\Components\Api\Manager::getResource('Article')`, or your own resource)
  for create, update, delete and the validation errors, and the HTTP path once by hand with an API user.
- Mink/Behat (`tests/Mink`) is the core's browser suite and needs Selenium and a prepared database; it is out of reach for a
  plugin slice and is not a quality gate here.

## Running

```bash
php vendor/bin/phpunit -c custom/plugins/SwagOrderNote/phpunit.xml.dist
php vendor/bin/phpunit --config tests/phpunit_unit.xml.dist --filter OrderNote     # the core's own unit config
php bin/console sw:cache:clear                                                      # after a failing install in a test
```

Order of the gates for a change: the project's static analysis (if it has any), then the plugin's unit tests, then its functional tests on the development copy,
then a manual install / update / uninstall round on that copy.
