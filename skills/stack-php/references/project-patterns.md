# Composer, PSR-4 and Dependency Injection — Project Patterns

## Project layout

```
composer.json          composer.lock (committed)
src/                   the code, PSR-4 root
tests/                 mirrors src/
public/index.php       web entry point (applications only)
bin/<tool>             CLI entry point (applications and tools)
config/                composition root and config files
phpunit.xml.dist       phpstan.neon.dist       .php-cs-fixer.dist.php
```

A library ships only `src/` and `composer.json`; keep `tests/` and the tool configs out of its dist archive with
`export-ignore` in `.gitattributes`. An application keeps `vendor/` out of git and out of PHPStan's `paths`.

## composer.json

```json
{
    "name": "acme/billing",
    "type": "library",
    "require": {
        "php": "^8.4"
    },
    "require-dev": {
        "friendsofphp/php-cs-fixer": "^3.95",
        "phpstan/phpstan": "^2.3",
        "phpunit/phpunit": "^13.4"
    },
    "autoload": {
        "psr-4": { "Acme\\Billing\\": "src/" }
    },
    "autoload-dev": {
        "psr-4": { "Acme\\Billing\\Tests\\": "tests/" }
    },
    "config": {
        "sort-packages": true
    },
    "scripts": {
        "test": "phpunit",
        "stan": "phpstan analyse",
        "cs": "php-cs-fixer check --diff",
        "qa": ["@cs", "@stan", "@test"]
    }
}
```

- `require.php` is the real floor of the code (a library: the lowest PHP its users still run, which the CI matrix covers;
  an application: the version in production). An application may also set `config.platform.php` to the production
  version so that `composer update` never resolves packages newer than production runs; run
  `composer check-platform-reqs` as part of the deploy.
- Add a package with `composer require vendor/name` (`--dev` for tooling); never edit `composer.json` and `composer.lock`
  apart. Constraints are caret ranges (`^2.3`); no `*`, no `dev-main`, and no `minimum-stability` change to reach one package.
- `composer.lock` is committed — for an application always, for a library recommended too (the CI then tests against the
  locked versions; run an extra job with `composer update` and `--prefer-lowest` to catch a too-low lower bound).
  `composer install` reads the lock file; only `composer update` changes it.
- `composer validate --strict` checks the manifest; `composer audit` reports known advisories in the locked packages — run
  both in CI. Composer blocks insecure versions during `update` / `require` by default.
- Scripts run with `vendor/bin` first on the `PATH`, so `"test": "phpunit"` finds the Composer-installed binary.
- Production: `composer install --no-dev --optimize-autoloader` (or `--classmap-authoritative` when nothing is generated at
  run time). Never `composer update` on a server.
- A plugin that Composer would run needs an entry under `config.allow-plugins`; allow the ones you know by name, never `true`.

## PSR-4 autoloading

- One prefix, one directory: namespace `Acme\Billing\Invoice\Line` lives in `src/Invoice/Line.php`. The class name is
  the file name; the namespace below the prefix is the directory path.
- After changing an `autoload` block run `composer dump-autoload`; `composer dump-autoload --optimize --strict-psr` fails when a file
  does not match its mapping — useful in CI.
- No `require` / `include` of class files; the only `require` is `vendor/autoload.php` in an entry point.
- Test classes live under `autoload-dev`, never in `src/`.
- Public API versus internals: mark internal classes `@internal` and keep them in an `Internal` namespace; the semver promise
  covers only the rest.

## Dependency injection without a framework

Business code asks for what it needs in its constructor and never looks anything up:

```php
final readonly class InvoiceMailer
{
    public function __construct(
        private InvoiceRepository $invoices,
        private Mailer $mailer,
        private \Psr\Clock\ClockInterface $clock,
    ) {}
}
```

- **Interfaces at the seams** — `InvoiceRepository`, `Mailer` are interfaces owned by the domain; the adapters (PDO,
  SMTP, filesystem) implement them. Inside one layer a concrete `final` class needs no interface.
- **One composition root** — a single place builds the object graph: a `config/container.php` or a small `Bootstrap` class
  called by `public/index.php` and `bin/<tool>`. Nothing else uses `new` on a service.

```php
// config/container.php — hand-wired; fine while the graph fits on a screen
$pdo = new \PDO($config->databaseDsn);
$invoices = new PdoInvoiceRepository($pdo);
$mailer = new SmtpMailer($config->smtpHost, $config->smtpPort);

// any PSR-20 implementation works; symfony/clock's NativeClock is one (it provides psr/clock-implementation)
return new InvoiceMailer($invoices, $mailer, new \Symfony\Component\Clock\NativeClock());
```

- **Grow into a PSR-11 container** when manual wiring becomes noise: any library that implements
  `Psr\Container\ContainerInterface` (`get()` / `has()`) works, and it is used only inside the composition root. Services
  receive their dependencies, never the container (that is a service locator).
- **Time, randomness, I/O are dependencies** — the current time comes from a `Psr\Clock\ClockInterface` (PSR-20); randomness,
  the filesystem and the network sit behind small interfaces, so a test can replace them.
- **Cross-cutting PSRs** — a logger is `Psr\Log\LoggerInterface` (PSR-3), HTTP messages follow PSR-7 / PSR-17 and an HTTP
  client PSR-18; depend on the interface and let the application choose the implementation.
- **No static access** — no `Service::getInstance()`, no static helpers that reach into state; a static method is fine only
  as a pure function or a named constructor (`Money::of(...)`).

## Configuration

- Read environment variables once, in the composition root, into a typed `final readonly` config object; pass that object
  (or its parts) on. The domain never calls `getenv()` or reads `$_ENV`.
- Validate configuration at start-up and fail with a message naming the missing key; do not discover it at the first request.
- Secrets are never committed; a committed `.env.example` lists the keys without values.

## Entry points

- `public/index.php` and `bin/<tool>` are thin: require the autoloader, build the graph, run one handler, translate
  exceptions to a response or an exit code. No business logic in them.
- A CLI tool returns a meaningful exit code (0 success, non-zero failure) and writes errors to stderr.
- A web entry point built from PSR-7 / PSR-15 parts has one place that turns an uncaught exception into a response; a
  production error never prints a stack trace to the client.

## Libraries versus applications

- A library keeps a broad `require.php` and few dependencies, declares what it needs by interface (PSR packages), and
  treats its public classes as API: changes follow semver, deprecated API gets `#[\Deprecated]` (or, for a class, a `@deprecated` docblock) before removal.
- An application pins its production platform and uses the lock file for reproducible builds; its classes are internal,
  so refactors need no deprecation period.
