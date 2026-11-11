# API Platform — Test Patterns

PHPUnit with `ApiTestCase`, API Platform's test client and its API assertions. Written for API Platform 5.0 (tests extend
`ApiPlatform\Test\ApiTestCase` from the `api-platform/test` package); on 4.x the class is
`ApiPlatform\Symfony\Bundle\Test\ApiTestCase` (`SKILL.md` → `## Existing Projects`). PHPUnit 13 needs PHP 8.4 (Symfony
8.x); PHPUnit 12 runs on 8.3 and 11 on 8.2; `api-platform/test` accepts PHPUnit `^11.5 || ^12.2 || ^13.0`. Metadata is
written as PHP attributes (`#[DataProvider]`) — doc-comment annotations are gone from PHPUnit 12. Run with
`php bin/phpunit`.

## Setup

```console
composer require --dev symfony/test-pack api-platform/test symfony/browser-kit symfony/http-client
composer require --dev dama/doctrine-test-bundle zenstruck/foundry justinrainbow/json-schema
```

- The Flex recipes provide `phpunit.dist.xml`, `tests/bootstrap.php`, `.env.test` and `framework.test: true` in the test
  environment, which the client needs. Keep deprecations, notices and warnings failing the run (`failOnDeprecation`,
  `failOnNotice`, `failOnWarning`) so a deprecated API Platform or Symfony call shows up before an upgrade.
- `justinrainbow/json-schema` is needed only for the JSON Schema assertions below.
- **Database per test** — either DAMA (`dama/doctrine-test-bundle`: enable its PHPUnit extension in `phpunit.dist.xml`;
  every test runs in a transaction that is rolled back) or Foundry's `ResetDatabase` and `Factories` traits (a factory per
  entity, `BookFactory::createMany(100)`). The test database is its own (`_test` suffix): `php bin/console --env=test
  doctrine:database:create` and `doctrine:schema:create` (or `doctrine:migrations:migrate`).
- Fixtures give a stable base (users, reference data); a test builds the rest it asserts on itself, so it shows what it
  depends on.

## A functional test

```php
<?php

declare(strict_types=1);

namespace App\Tests\Api;

use ApiPlatform\Test\ApiTestCase;
use App\Entity\Book;
use App\Factory\BookFactory;
use Zenstruck\Foundry\Test\Factories;
use Zenstruck\Foundry\Test\ResetDatabase;

final class BookTest extends ApiTestCase
{
    use ResetDatabase, Factories;

    public function testCollectionIsPaginated(): void
    {
        BookFactory::createMany(100);

        $response = static::createClient()->request('GET', '/api/books');

        self::assertResponseIsSuccessful();
        self::assertJsonContains(['@type' => 'Collection', 'totalItems' => 100]);
        self::assertCount(30, $response->toArray()['member']);
        self::assertMatchesResourceCollectionJsonSchema(Book::class);
    }

    public function testPatchChangesOneField(): void
    {
        BookFactory::createOne(['isbn' => '9781344037075']);
        $client = static::createClient();
        $iri = $this->findIriBy(Book::class, ['isbn' => '9781344037075']);

        $client->request('PATCH', $iri, [
            'json' => ['title' => 'updated'],
            'headers' => ['Content-Type' => 'application/merge-patch+json'],
        ]);

        self::assertResponseIsSuccessful();
        self::assertJsonContains(['@id' => $iri, 'title' => 'updated']);
    }

    public function testInvalidBodyIsRejected(): void
    {
        static::createClient()->request('POST', '/api/books', ['json' => ['isbn' => 'invalid']]);

        self::assertResponseStatusCodeSame(422);
        self::assertJsonContains(['violations' => [['propertyPath' => 'isbn']]]);
    }
}
```

- `createClient()` is `protected static`; the client **implements Symfony's HttpClient** interfaces and drives the
  HttpKernel directly (no network). `request($method, $url, $options)` takes the HttpClient options — `json`, `headers`,
  `query`, `body`, `auth_bearer`, `auth_basic` — and returns a response with `toArray()` and `getContent(false)` (the
  `false` keeps a 4xx from throwing).
- **URLs are literal strings** with the route prefix the project uses (`/api/books` with the recipe's `/api`); do not
  build them from the router, so a changed public URL fails a test.
- The client's default `Accept` is `application/ld+json`, and a body sent through `json` carries `Content-Type:
  application/ld+json`; a `PATCH` must set `application/merge-patch+json` (otherwise 415), and a request for another format
  sets `Accept` (otherwise 406).
- **API assertions** (static, from `ApiTestAssertionsTrait`): `assertJsonContains($subset)` (a superset check),
  `assertJsonEquals($json)`, `assertMatchesJsonSchema($schema)`, `assertMatchesResourceItemJsonSchema(Book::class)` and
  `assertMatchesResourceCollectionJsonSchema(Book::class)` (the schema API Platform generated for the resource, in the format
  given as an argument, `jsonld` by default). The Symfony assertions (`assertResponseStatusCodeSame`,
  `assertResponseHeaderSame`, `assertResponseIsSuccessful`) work as is.
- The schema assertions read the **last response**: call them straight after the request they check (a 204 has no body).
- `findIriBy(Book::class, [...])` and `getIriFromResource($object)` give an IRI without hard-coding an id; assert on the
  IRI shape (`~^/api/books/\d+$~`), not a literal id.
- **`Content-Type`** — assert `application/ld+json` for 4.4 and 5.0; a JSON response carries no `; charset=utf-8` since
  4.4 (the docs' examples still show it). A test that must run on both asserts the media type with
  `assertStringStartsWith`.
- **Several requests in one test** reboot the kernel and with it the transaction: call `$client->disableReboot()`. 5.0
  makes `$alwaysBootKernel` default to `false` (the kernel is not rebooted between `createClient()` calls once booted); set
  `protected static ?bool $alwaysBootKernel = true;` in a class that relied on the old implicit reboot.
- The container is reachable (`static::getContainer()->get('doctrine')`) to assert on the database after a write.

## What to test, per resource

- **Every operation that exists**, and that the ones you removed answer 404 or 405: collection (filters, order, page 1 and
  the `view` links), item, create (201 with an `@id`), update, delete (204), a missing item (404).
- **The error shapes**: a validation failure (422 with `violations`), a type error in the body (400 or 422 — depends on
  whether the property has a constraint, `resource-patterns.md`), a malformed JSON body (400), an unsupported
  `Content-Type` (415), a duplicate key (422 on 5.0).
- **Security per operation and role**: anonymous 401, a user without the role 403, the owner 200, another user's item 403 or
  404. The voter is also unit-tested with a stub token. `$client->loginUser($user)` logs a user in without the login form
  (named firewall as the second argument); for token APIs use `['auth_bearer' => $token]`.
- **Filters and sorting**: seed rows that differ on the filtered field, request with the parameter, assert members; an
  invalid `order` value is a 422.
- **The collection a user must not see**: a test that another user's row is absent proves the Doctrine extension; a second,
  anonymous request proves it fails closed (401, or an empty collection — never the other users' rows).
- **Contract**: `assertMatchesResourceItemJsonSchema` per resource, and a test that `api:openapi:export` still equals the
  committed file when the project commits one.
- **Each enabled format** once on a representative resource: `Accept: application/vnd.api+json` and the others; the
  JSON:API `data.id` default changed in 5.0.
- **Mercure**: with the test client `getMercureMessages()` and `assertMercureUpdateMatchesJsonSchema(...)` check that a write
  published one update, privately, on the IRI.
- **GraphQL**: `POST` `{"query": "..."}` to the endpoint, assert on `data` and `errors`; the security of each GraphQL
  operation separately from REST.

## Unit tests — no kernel

State providers, processors, voters, filters and extensions are plain classes: construct them with fakes and call them with
`PHPUnit\Framework\TestCase`; booting the kernel for a unit costs seconds and hides what it depends on. A processor test
passes a fake persist processor (`ProcessorInterface`) and asserts it was called with the changed object and that its
result is returned. Test a voter with `createStub(TokenInterface::class)`. Use `MockClock` from Symfony Clock for time.
Test a filter against a real `QueryBuilder` on the test database, not a mocked `EntityManager`.

## Habits

- A test fails for one reason and its name says which behaviour broke; expected values are literals.
- The failure path sits next to the happy path in the same class.
- Cover boundaries (empty collection, last page, page past the end, maximum page size), variants (every enum case), both
  branches of a condition, side effects (mail sent, message dispatched, Mercure update) and isolation.
- Fix a flaky test (time, order, shared state, a generated id) instead of retrying it; `executionOrder="random"` exposes
  order dependence.
- Run PHPStan over `tests/` too, and `lint:container` in the same CI job as the suite.
- Other tools the docs list — Behat, Hoppscotch, Blackfire Player, PHP Matcher — do not replace the `ApiTestCase` suite in a
  project that has one; Playwright or Symfony Panther cover end-to-end checks of the whole stack.
