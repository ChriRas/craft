# PHPUnit 13 — Test Patterns

PHPUnit 13 needs PHP 8.4 or newer. Metadata is written as PHP attributes — doc-comment annotations (`@dataProvider`,
`@covers`) were removed in PHPUnit 12. A project on an older PHPUnit follows the form its neighbouring tests use
(`SKILL.md` → `## Existing Projects`).

## Layout and configuration

`tests/` mirrors `src/`: `src/Invoice/Line.php` is tested by `tests/Invoice/LineTest.php`, class `LineTest`, namespace
under `autoload-dev`. A test class is `final` and extends `PHPUnit\Framework\TestCase`; a test method is public, returns
`void` and is named `test…` (or carries `#[Test]`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- phpunit.xml.dist -->
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         bootstrap="vendor/autoload.php"
         cacheDirectory=".phpunit.cache"
         executionOrder="random"
         failOnWarning="true"
         failOnRisky="true"
         failOnDeprecation="true"
         colors="true">
    <testsuites>
        <testsuite name="default">
            <directory>tests</directory>
        </testsuite>
    </testsuites>
    <source>
        <include>
            <directory>src</directory>
        </include>
    </source>
</phpunit>
```

- `vendor/bin/phpunit --generate-configuration` writes a starting file; keep the project's own if one exists.
- Random execution order and the `failOn…` switches surface order dependencies and ignored warnings early; a project
  that has to turn one off records why in its `rules.md`.
- Run: `vendor/bin/phpunit`, one file `vendor/bin/phpunit tests/Invoice/LineTest.php`, by name `--filter testRejects`,
  one suite `--testsuite default`.

## Unit tests — values and services

Arrange, act, assert; one behaviour per test; the failure path next to the happy path.

```php
<?php

declare(strict_types=1);

namespace Acme\Billing\Tests;

use Acme\Billing\Money;
use PHPUnit\Framework\Attributes\CoversClass;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

#[CoversClass(Money::class)]
final class MoneyTest extends TestCase
{
    public function testAddsAmountsOfTheSameCurrency(): void
    {
        $sum = Money::of(1_000, 'EUR')->plus(Money::of(250, 'EUR'));

        self::assertSame(1_250, $sum->minorUnits);
    }

    public function testRejectsAmountsOfDifferentCurrencies(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        Money::of(1_000, 'EUR')->plus(Money::of(1, 'USD'));
    }

    /** @return iterable<string, array{int, int, int}> */
    public static function additions(): iterable
    {
        yield 'zero plus zero' => [0, 0, 0];
        yield 'negative result' => [100, -250, -150];
    }

    #[DataProvider('additions')]
    public function testAddsAcrossBoundaries(int $left, int $right, int $expected): void
    {
        self::assertSame($expected, Money::of($left, 'EUR')->plus(Money::of($right, 'EUR'))->minorUnits);
    }
}
```

- `assertSame` (strict) over `assertEquals`; for several values that belong together, assert the whole structure once.
- A data provider is a `public static` method referenced by `#[DataProvider('name')]`; give each set a string key so a
  failure names the case. `#[TestWith([...])]` suits two or three short sets.
- `#[CoversClass]` states what a test is about; it matters once the project turns on `requireCoverageMetadata`.
- Static `self::assert…()` or `$this->assert…()` — follow the project's choice, do not mix inside one file.

## Test doubles — prefer fakes and stubs

- **Fake first** — a small in-memory class implementing the domain interface (`InMemoryInvoiceRepository`) tests behaviour
  without any mocking syntax and is reusable across tests. Keep fakes in `tests/Support/`.
- **Stub** — `$this->createStub(Mailer::class)` supplies answers; it asserts nothing. Configure with
  `$stub->method('send')->willReturn(...)`; an unconfigured method returns a value of its return type.
- **Mock** — `$this->createMock(Mailer::class)` plus `->expects($this->once())->method('send')->with(...)` only when the
  interaction itself is the behaviour under test (a notification was sent). A mock with no expectation raises a PHPUnit
  notice: use `createStub()` instead. Since PHPUnit 13, `->seal()` ends a configuration and makes calls to unconfigured
  methods of a mock fail.
- Double interfaces and public contracts, not concrete internals, and never a value object — construct a real one.
- Time comes from a fixed clock (a `ClockInterface` fake), randomness from a seeded or injected source; a test does not
  `sleep()`.

```php
public function testSendsTheInvoiceMailOnce(): void
{
    $mailer = $this->createMock(Mailer::class);
    $mailer->expects($this->once())->method('send')->with($this->isInstanceOf(InvoiceMail::class));

    $service = new InvoiceMailer(new InMemoryInvoiceRepository([$this->invoice()]), $mailer, new FixedClock('2026-01-31'));
    $service->sendOverdue();
}
```

## Integration tests

- Cross the real boundary on purpose: an adapter against SQLite `:memory:` or a throwaway database, a filesystem adapter
  against a temp directory (`sys_get_temp_dir()` plus a unique name, removed in `tearDown()`), an HTTP client against a
  recorded response or a local test server. The domain's unit tests do not touch these.
- Build the schema in `setUp()` (fresh per test) or `setUpBeforeClass()` (once per class, then truncate); keep the
  database seed minimal and local to the test.
- Mark tests that need an optional extension or a PHP version with `#[RequiresPhpExtension('pgsql')]` or
  `#[RequiresPhp('>= 8.4')]` so they skip instead of fail.
- Keep a thin end-to-end test of the entry point (`bin/<tool>` run as a process with its exit code and output asserted)
  for an application or CLI tool.

## Systematic coverage

The Senior-Developer baseline's test-discipline matrix, expressed in PHPUnit:

| Category | PHPUnit expression |
|---|---|
| Boundaries | `null`, empty string, `[]`, zero, negative, maximum as explicit data-provider sets. |
| Variants | a provider over every backed-enum case (`yield $case->name => [$case]` for `Status::cases()`). |
| Conditions | each branch — the `true` and the `false` case — in its own test. |
| Side effects | a mock with `expects()` on the collaborator, or a fake asserted afterwards. |
| Errors | `expectException()` plus `expectExceptionMessage()` for the failure path. |
| Isolation | an operation on one object leaves another untouched; no shared mutable state between tests. |

## Habits

- A test fails for one reason and its name says which behaviour broke (`testRejectsAmountsOfDifferentCurrencies`).
- No logic in a test (no `if`, no loop that recomputes the expected value); the expected value is a literal.
- A test that passes without an assertion is risky — with `failOnRisky` it fails; add the assertion or delete the test.
- Run PHPStan over `tests/` too (`phpstan/phpstan-phpunit` teaches it the PHPUnit API when the project uses it).
