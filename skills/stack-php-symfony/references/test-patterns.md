# Symfony — Test Patterns

PHPUnit through `symfony/test-pack` (`composer require --dev symfony/test-pack` installs PHPUnit, BrowserKit and the CSS
selector). PHPUnit 13 needs PHP 8.4 (Symfony 8.x); PHPUnit 12 runs on 8.3 and 11 on 8.2 (the 7.4 LTS). Metadata is written as
PHP attributes — doc-comment annotations (`@dataProvider`) were removed in PHPUnit 12, so an older project follows the form
its neighbouring tests use (`SKILL.md` → `## Existing Projects`). Run with `php bin/phpunit` (the recipe's script).

## Layout and configuration

`tests/` mirrors `src/` for unit tests (`src/Invoice/Total.php` → `tests/Invoice/TotalTest.php`, namespace `App\Tests\…`); in a
larger suite use `tests/Unit/`, `tests/Integration/` and `tests/Application/`. Flex writes `phpunit.dist.xml` (not
`phpunit.xml.dist`), `tests/bootstrap.php`, `.env.test` and `bin/phpunit`; a developer's `phpunit.xml` is git-ignored.

```xml
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         colors="true" failOnDeprecation="true" failOnNotice="true" failOnWarning="true"
         bootstrap="tests/bootstrap.php" cacheDirectory=".phpunit.cache">
    <php>
        <ini name="display_errors" value="1" />
        <ini name="error_reporting" value="-1" />
        <server name="APP_ENV" value="test" force="true" />
        <server name="SHELL_VERBOSITY" value="-1" />
    </php>
    <testsuites><testsuite name="Project Test Suite"><directory>tests</directory></testsuite></testsuites>
    <source ignoreSuppressionOfDeprecations="true" ignoreIndirectDeprecations="true">
        <include><directory>src</directory></include>
    </source>
</phpunit>
```

- This is the recipe's configuration (abridged): deprecations, notices and warnings fail the run, so a deprecated Symfony
  or Doctrine API shows up in the test run before the upgrade. Keep the switches on; a project that turned one off records why.
- The kernel runs in the `test` environment: `.env.test` (committed) and `.env.test.local` override `.env`; `.env.local` is not
  read in tests. Put test-only service or package config under `when@test:` or `config/packages/test/`; the recipe sets
  `framework.test: true` there, which provides the test client.
- Run on CI with `debug` off (`bootKernel(['debug' => false])`) for speed, and clear `var/cache/test` in
  `tests/bootstrap.php` if the cache is not fresh.

## Unit tests — no kernel

A pure class (value object, domain service, validator, voter, form data) is tested with `PHPUnit\Framework\TestCase`: construct
it, call it, assert. Booting the kernel for a unit costs seconds and hides what the unit depends on.

```php
final class TotalTest extends TestCase
{
    #[DataProvider('lines')]
    public function testSumsLines(array $amounts, int $expected): void
    {
        self::assertSame($expected, Total::of(...$amounts)->minorUnits);
    }

    public static function lines(): iterable
    {
        yield 'empty' => [[], 0];
        yield 'mixed signs' => [[100, -30], 70];
    }
}
```

- Fakes first (an `InMemoryInvoiceRepository` implementing the repository interface), `createStub()` for answers,
  `createMock()` only when the interaction itself is the behaviour. Do not mock a value object or `EntityManagerInterface`
  to test a query — test that against the database.
- Time: `Symfony\Component\Clock\Test\ClockSensitiveTrait` and its `mockTime('2026-01-31')` freeze the clock and restore it
  after the test; or construct the service with a `MockClock`.
- HTTP calls: `MockHttpClient` with `MockResponse` instead of a real client.

## Integration tests — `KernelTestCase`

Use the container when the wiring is what you test: a service with its real collaborators, a repository against the test
database, a Messenger handler, a console command.

```php
final class InvoiceRepositoryTest extends KernelTestCase
{
    public function testFindsOpenInvoicesWithTheirLines(): void
    {
        self::bootKernel();
        $repository = static::getContainer()->get(InvoiceRepository::class);

        $open = $repository->findOpenWithLines();

        self::assertCount(2, $open);
    }
}
```

- `bootKernel()` boots `App\Kernel` (from `KERNEL_CLASS` in `.env.test`) and reboots it for every test. `static::getContainer()`
  is the test container: it reaches public services **and** private ones that something else uses; a private service nobody
  uses is removed — declare it public in `config/services_test.yaml` for the test or test through its user.
- **Replace a dependency** with `$container->set(NewsRepositoryInterface::class, $mock)` before fetching the service under
  test; no extra configuration is needed.
- **Console commands** — in 8.1, `static::runCommand('app:create-user', ['username' => 'Wouter'])` returns an
  `ExecutionResult` and `assertCommandIsSuccessful($result)` checks it (**7.4**: `CommandTester`, which
  dispatches no console events; `ApplicationTester` when they matter).
- **Mailer** — `assertEmailCount(1)`, `getMailerMessage()` after the code ran (`KernelTestCase` or `MailerAssertionsTrait`);
  `assertQueuedEmailCount()` when mail goes through Messenger.
- **Messenger** — in `when@test` point the transport at `in-memory://` and assert on it:

```yaml
# config/packages/messenger.yaml
when@test:
    framework:
        messenger:
            transports:
                async: 'in-memory://'
```

```php
/** @var InMemoryTransport $transport */
$transport = static::getContainer()->get('messenger.transport.async');
self::assertCount(1, $transport->getSent());
```

  A test of routing asserts on `getSent()`; a test of what the handler does constructs it with fakes (or fetches it from
  the container) and calls it with the message — it needs no transport.

## The test database

- Tests that touch the database use their own: the recipe appends `_test` (and ParaTest's `TEST_TOKEN`) to the database
  name in `when@test`. Create it once: `php bin/console --env=test doctrine:database:create` and
  `php bin/console --env=test doctrine:schema:create` (or `doctrine:migrations:migrate --env=test`).
- **Isolation** — install `dama/doctrine-test-bundle` and enable its PHPUnit extension in `phpunit.dist.xml`
  (`<extensions><bootstrap class="DAMA\DoctrineTestBundle\PHPUnit\PHPUnitExtension" /></extensions>` for PHPUnit 10 and
  newer): every test runs in a transaction that is rolled back. Without it, a test creates what it needs and cleans up, or
  reloads fixtures.
- **Data** — `doctrine/doctrine-fixtures-bundle` for a stable base set (users, reference data), loaded with
  `php bin/console --env=test doctrine:fixtures:load`; a test builds the rest it asserts on itself (a builder or a factory
  such as `zenstruck/foundry`), so the test shows what it depends on.
- After the entity manager is cleared or the kernel reboots, entities are detached: re-fetch by id instead of reusing an
  object across requests.

## Application tests — `WebTestCase`

`WebTestCase` adds a browser-like client on top of `KernelTestCase`: make a request, interact, assert the response.

```php
final class InvoiceControllerTest extends WebTestCase
{
    public function testAccountantCreatesAnInvoice(): void
    {
        $client = static::createClient();
        $user = static::getContainer()->get(UserRepository::class)->findOneByEmail('accountant@example.com');
        $client->loginUser($user);

        $client->request('GET', '/invoices/new');
        self::assertResponseIsSuccessful();

        $client->submitForm('Save', ['invoice[number]' => 'INV-1']);
        self::assertResponseRedirects();
        $client->followRedirect();
        self::assertSelectorTextContains('h1', 'INV-1');
    }
}
```

- **Hard-code URLs** (`'/invoices/new'`), not `generateUrl()`: a test that builds URLs from the router cannot notice that a
  public URL changed. A **smoke test** requests every public URL from a data provider and expects a 2xx or a redirect.
- **Login** — `$client->loginUser($user)` simulates authentication without the login form (create a test user through a
  fixture); test the real login form once, separately. The recipe lowers the password-hasher cost in `when@test`, keeping
  fixtures with hashed passwords fast.
- **Assertions** (`Symfony\Bundle\FrameworkBundle\Test`): `assertResponseIsSuccessful()`, `assertResponseStatusCodeSame(422)`,
  `assertResponseRedirects('/path')`, `assertSelectorExists()`, `assertSelectorTextContains()`, `assertPageTitleSame()`,
  `assertBrowserHasCookie()`; the crawler (`$crawler->filter('.comment')`) for counts. An invalid form submit answers
  **422**, an unauthorized request 401 / 403 / a redirect to the login — assert the status, not only the body.
- **Several requests in one test** reboot the kernel, which clears the security token and detaches entities; use
  `$client->disableReboot()` or keep each test to one scenario. `$client->followRedirect()` follows one redirect by hand;
  `$client->enableProfiler()` before a request makes `$client->getProfile()` available afterwards.
- **Forms and CSRF** — `submitForm('Button label', [...])` reads the CSRF token from the rendered page; do not turn CSRF off in
  `when@test` to make a test pass.
- **JSON APIs** — `$client->jsonRequest('POST', '/api/invoices', [...])` and decode with `json_decode($client->getResponse()->getContent(), true)`.
- JavaScript-dependent pages need the Panther component (a real browser); keep those few and out of the default run.

## Habits

- A test fails for one reason and its name says which behaviour broke; no logic in a test, expected values are literals.
- Test the failure path next to the happy path: a validation error (422), a forbidden user (403), a missing entity (404).
- Cover each of the baseline's categories with data providers: boundaries (empty, null, zero, negative), variants (every enum
  case), conditions (both branches), side effects (mail sent, message dispatched), errors, isolation.
- Fix a flaky test (time, order, shared state) instead of retrying it; `executionOrder="random"` exposes order dependence.
- Run PHPStan over `tests/` too; `lint:container` and `lint:twig` belong in the same CI job as the suite.
