# Symfony — Code Quality Standards

PHP and Symfony conventions for new code. Use what the project's `require.php` floor and Symfony line allow
(`SKILL.md` → `## Existing Projects`): Symfony 8.x needs PHP 8.4, 7.4 needs PHP 8.2.

## Mandatory shape

Every new PHP file follows PER Coding Style (`declare` directly after the opening tag, four-space indent, a trailing comma
in every multi-line list). A service in `src/` is `final`, takes its dependencies by constructor and does one job:

```php
<?php

declare(strict_types=1);

namespace App\Invoice;

use Symfony\Component\Clock\ClockInterface;

final readonly class InvoiceNumberGenerator
{
    public function __construct(
        private InvoiceRepository $invoices,
        private ClockInterface $clock,
    ) {}

    public function next(): InvoiceNumber
    {
        $year = (int) $this->clock->now()->format('Y');

        return InvoiceNumber::forYear($year, $this->invoices->countForYear($year));
    }
}
```

A class with a constructor that only assigns is `final readonly` (8.2); a Doctrine entity is neither `final` nor
`readonly` unless native lazy objects are enabled (see `doctrine-patterns.md`). One class per file, the file
named after the class, `App\` mapped to `src/` and `App\Tests\` to `tests/` (PSR-4).

## Language idioms

- **Types** — a type on every parameter, return value and property; union and DNF types where they say what the code means;
  `never` for a function that always throws. A bare `array` that crosses a layer boundary becomes a value object or a
  docblock shape (`list<Foo>`, `array{id: int, name: string}`).
- **Enums** — backed enums for every closed set (status, role, type), mapped in Doctrine with `enumType:`; `match` without a
  `default` arm so PHPStan reports a missing case.
- **Attributes first** — `#[Route]`, `#[ORM\...]`, `#[Assert\...]`, `#[IsGranted]`, `#[AsMessageHandler]`, `#[Autowire]`,
  `#[AsEventListener]`, `#[AsCommand]` — one language for wiring, next to the code it configures. `#[\Override]` (8.3) on
  every method that overrides or implements.
- **Property hooks and asymmetric visibility (8.4)** — `public private(set) string $name` instead of a getter plus a
  private property on a value object or DTO. On a Doctrine entity (ORM 3.4+) only a backed hooked property maps, and
  DQL queries use its raw value; keep hooks off entities unless the project already uses them there.
- **Clock and time** — inject `Symfony\Component\Clock\ClockInterface` (`symfony/clock`; it has `MockClock` for tests); never
  `new \DateTimeImmutable()` or `time()` inside business logic.
- **Constructor promotion and named arguments** — `new Money(amount: 100, currency: Currency::EUR)`; named arguments are
  also how attributes are written (`#[Route('/blog', name: 'blog_list', methods: ['GET'])]`).
- **First-class callables** — `$this->handle(...)`, `strlen(...)` instead of `Closure::fromCallable` or strings.
- **Dynamic properties** are deprecated since 8.2; declare every property.

## Checklist

- `declare(strict_types=1)` is the first statement; no `mixed` unless the value really is open.
- Controllers are thin: map the request, call one service, return a response (`framework-patterns.md`).
- Dependencies come in by constructor, typed as the class or an interface; `#[Autowire]` for a scalar, a parameter or an
  env var. No `ContainerInterface`, no `$this->container->get()`, no static access to services.
- Services are stateless (a long-running Messenger worker reuses them); no per-request data in a property.
- Config values are read where they are wired (`services.yaml`, `#[Autowire(env: '...')]`), never via `$_ENV` or
  `getenv()` in domain code.
- Output (`echo`, `dump`, `dd`, `var_dump`) does not stay in committed code; log through `Psr\Log\LoggerInterface`.
- No `@` error suppression, no `eval`, no `extract()`, no `global`.
- Comparisons are strict (`===`); `empty()` and loose `==` do not appear on values of unknown type.
- `php bin/console lint:container`, `lint:twig`, `lint:yaml`, PHPStan, the fixer's check and `php bin/phpunit` run clean
  before the work is called done.

## Error handling

- Throw exceptions; do not return `false` / `null` for failure. A named exception per failure the caller can act on,
  built through a named constructor (`OrderNotFound::withId($id)`).
- An HTTP status comes from the exception: `Symfony\Component\HttpKernel\Exception\NotFoundHttpException` /
  `AccessDeniedHttpException` thrown from a controller (`$this->createNotFoundException()`), or a domain exception mapped
  to a status with `#[WithHttpStatus(404)]` on its class. The controller does not build error responses by hand.
- Wrap, do not swallow: `throw new ImportFailed('...', previous: $e)`. Catch the narrowest type at the layer that can act on
  it; the kernel's error handler logs and renders everything else.
- Validate at the boundary (request DTO, form, console input), then pass typed objects inward; do not re-validate per layer.
- A Messenger handler lets an exception escape to trigger the retry; a message that can never succeed throws
  `UnrecoverableMessageHandlingException` (`framework-patterns.md`).

## Static analysis — PHPStan

```neon
# phpstan.neon.dist
parameters:
    level: max
    paths:
        - src
        - tests
    symfony:
        containerXmlPath: var/cache/dev/App_KernelDevDebugContainer.xml
```

- Install with `composer require --dev phpstan/phpstan phpstan/phpstan-symfony phpstan/phpstan-doctrine
  phpstan/phpstan-phpunit phpstan/extension-installer`; run `vendor/bin/phpstan analyse`. With the extension installer the
  extensions register themselves; without it, include each package's `extension.neon` in the config.
- `phpstan-symfony` reads the compiled container: it needs `var/cache/dev` warmed (`php bin/console cache:warmup`) and
  `containerXmlPath` pointing at `App_KernelDevDebugContainer.xml` (the kernel is `App\Kernel`). It then types
  `$container->get()`, console arguments and `getParameter()`. `phpstan-doctrine` types repositories and the
  QueryBuilder; for DQL / QueryBuilder validation it needs an `objectManagerLoader` (its README).
- A new project starts at `max`. An existing codebase starts at the highest level it passes and raises it; findings it
  cannot fix yet go into a baseline (`--generate-baseline`) that only shrinks. Prefer `@phpstan-ignore <identifier>` on one
  line, with the reason, over a broad `ignoreErrors` pattern.

## Code style — PER Coding Style or the Symfony set

- Default for a new project: PER Coding Style via PHP-CS-Fixer's `@PER-CS` set (as of 2026-11-09 it resolves to the 3.0
  rules; pin `@PER-CS3x0` for stable output). The `@Symfony` rule set is the alternative the Symfony project uses for its
  own code (PSR-12 based, meant for contributions); a project that already runs `@Symfony` keeps it.

```php
<?php

declare(strict_types=1);

$finder = (new PhpCsFixer\Finder())->in([__DIR__ . '/src', __DIR__ . '/tests'])->exclude('var');

return (new PhpCsFixer\Config())
    ->setRules(['@PER-CS' => true])
    ->setFinder($finder);
```

- `vendor/bin/php-cs-fixer check --diff` reports, `fix` rewrites. Do not hand-format.
- Wire the checks into `composer.json` scripts so one command (`composer qa`) runs lint, analysis, style and tests.

## Framework linters

- `php bin/console lint:container` — service definitions resolve (autowiring, parameter types); run it in CI.
- `php bin/console lint:twig templates/` and `lint:yaml config/` — syntax of templates and YAML.
- `php bin/console doctrine:schema:validate` — mapping is valid and the schema matches it (a pending migration shows here).
- `php bin/console debug:container <id>`, `debug:router`, `debug:autowiring <name>` answer "why is this not wired".
