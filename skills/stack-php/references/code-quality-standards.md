# PHP 8.4 / 8.5 — Code Quality Standards

## Mandatory shape

Every new PHP file follows this shape (PER Coding Style 3.1: `declare` directly after the opening tag, four-space indent,
soft line limit 120 (aim for 80), a trailing comma in every multi-line list):

```php
<?php

declare(strict_types=1);

namespace Acme\Billing;

final readonly class Invoice
{
    /** @param list<InvoiceLine> $lines */
    public function __construct(
        public InvoiceId $id,
        public array $lines,
        public Currency $currency,
    ) {}

    public function total(): Money
    {
        return Money::sum($this->currency, ...array_map(
            static fn(InvoiceLine $line): Money => $line->amount,
            $this->lines,
        ));
    }
}
```

An empty body (promotion-only constructor) is written `{}` on the closing-parenthesis line. One class per file; the file
name is the class name.

## Language idioms

Use what the project's `require.php` floor allows (`## Existing Projects` in `SKILL.md`).

- **Types** — a type on every parameter, return value and property; union, intersection and DNF types (8.2) where they
  say what the code means; `never` for a function that always throws; `static` / `self` return types for fluent code.
- **Value objects** — `final readonly class` (8.2) with promoted public properties; a "with-er" copies via
  `clone($this, ['x' => $x])` on 8.5, via `new self(...)` before.
- **Enums** — backed enums (8.1) for every closed set, `match` over the enum without a `default` arm so PHPStan reports a
  missing case; `Enum::from()` throws, `tryFrom()` returns `null`.
- **Property hooks and asymmetric visibility (8.4)** — `public private(set) string $name` instead of a getter plus a private
  property; a `get` / `set` hook for a computed or validated property. Hooks do not replace a service: no I/O in a hook.
- **Attributes** — `#[\Override]` (8.3) on every method that overrides or implements, `#[\Deprecated]` (8.4; functions, methods and class constants — never a class, which gets a `@deprecated` docblock) on API you are
  retiring, `#[\NoDiscard]` (8.5) on a function whose result must not be ignored.
- **Typed class constants (8.3)** — `public const string DEFAULT_LOCALE = 'en';`; `final` constants where a subclass must
  not change them.
- **No `new` in initializers of mutable state** — `new` in a parameter default or attribute argument (8.1) is fine for a
  stateless default; a shared mutable object is a hidden dependency.
- **Arrays** — `list<T>` / `array<string, T>` / array shapes in the docblock; `array_find`, `array_any`, `array_all`
  (8.4) and `array_first`, `array_last` (8.5) instead of hand-written loops; a bare `array` that crosses a layer boundary
  becomes a value object. Spread (`...`) accepts string keys since 8.1.
- **Pipe operator (8.5)** — `$value |> trim(...) |> strtolower(...)` for a linear chain of single-argument callables;
  a nested call that already reads well stays as it is.
- **First-class callables** — `strlen(...)`, `$this->handle(...)` instead of `Closure::fromCallable` or strings.
- **`new` without extra parentheses (8.4)** — `new Request()->withHeader(...)` chains on a fresh object; follow the
  neighbouring code if it still writes `(new Request())->withHeader(...)`.
- **Dynamic properties** — deprecated since 8.2: declare every property; `#[\AllowDynamicProperties]` only for legacy code.
- **Strings and dates** — `str_contains`, `str_starts_with`, `str_ends_with`; `DateTimeImmutable` and a clock
  (`Psr\Clock\ClockInterface`), never `new DateTime()` inside business logic.
- **URI extension (8.5)** — the built-in `Uri\Rfc3986\Uri` class (and a WHATWG variant) parses and modifies URLs; use it
  rather than `parse_url()` where the floor is 8.5.

## Checklist

- `declare(strict_types=1)` is the first statement; no `mixed` unless the value really is open.
- Public API has `@param` / `@return` generics where the native type is too wide (`list<Foo>`, `non-empty-string`,
  `positive-int`, `array{id: int, name: string}`).
- Classes are `final` unless they are designed for extension; properties are `readonly` unless they change.
- No logic in constructors beyond assigning and validating; side effects belong in named methods.
- Dependencies come in by constructor and are typed as interfaces at module boundaries.
- Output (`echo`, `print`, `var_dump`, `die`) only in entry points; everything else returns or throws.
- No `@` error suppression, no `eval`, no variable variables, no `extract()`, no `global`.
- Comparisons are strict (`===`); `empty()` and loose `==` do not appear on values of unknown type.
- Secrets and environment-specific values are read at the composition root, not in the domain.
- `phpstan analyse` and the fixer's check run clean (commands below) before the work is called done.

## Error handling

- Throw exceptions; do not return `false` / `null` for failure. A named exception per failure the caller can act on
  (`final class InvoiceNotFound extends \RuntimeException`), thrown through a named constructor
  (`InvoiceNotFound::withId($id)`).
- Wrap, do not swallow: `throw new ImportFailed('...', previous: $e)` keeps the cause. Catch the narrowest type, at the
  layer that can do something about it; a top-level handler in the entry point logs and exits.
- Validate at the boundary (input, config, file contents), then pass typed objects; do not re-validate in each layer.
- `\InvalidArgumentException` / `\LogicException` for programmer errors, `\RuntimeException` for environmental failures —
  do not catch the first kind to carry on.
- Convert PHP warnings into exceptions only at the entry point (`set_error_handler` throwing `\ErrorException`), not in
  library code.
- Log through a `Psr\Log\LoggerInterface` injected by the caller; a library never writes to `error_log` or stdout itself.

## Static analysis — PHPStan

```neon
# phpstan.neon.dist
parameters:
    level: max
    paths:
        - src
        - tests
```

- Install with `composer require --dev phpstan/phpstan`; run `vendor/bin/phpstan analyse` (the config supplies level and
  paths). Levels are cumulative from 0 to 10; `max` is an alias for the highest, so it rises with an upgrade.
- A new project starts at `max`. An existing codebase starts at the highest level it passes and raises it; findings it
  cannot fix yet go into a baseline (`vendor/bin/phpstan analyse --generate-baseline`), included from the config. The
  baseline only shrinks — a new finding is fixed, not added to it.
- Extensions are Composer packages: `phpstan/phpstan-phpunit` for test code, `phpstan/phpstan-strict-rules` for stricter
  checks; `phpstan/extension-installer` registers them. Add one only when the project asks for it.
- Prefer a specific `@phpstan-ignore <identifier>` on one line over a broad `ignoreErrors` pattern, with the reason next
  to it.

## Code style — PER Coding Style

- PER Coding Style 3.1 (PHP-FIG) extends and replaces PSR-12 and requires PSR-1. Do not hand-format; let the tool do it.
  As of 2026-11-09 the fixer's `@PER-CS` resolves to `@PER-CS3x0`, i.e. the 3.0 rules; it has no 3.1 set yet.
- Enforce with PHP-CS-Fixer: `composer require --dev friendsofphp/php-cs-fixer`, then `vendor/bin/php-cs-fixer init`
  writes a `.php-cs-fixer.dist.php`. The core of it:

```php
<?php

declare(strict_types=1);

$finder = (new PhpCsFixer\Finder())->in([__DIR__ . '/src', __DIR__ . '/tests']);

return (new PhpCsFixer\Config())
    ->setRules(['@PER-CS' => true])
    ->setFinder($finder);
```

- `vendor/bin/php-cs-fixer check --diff` reports, `vendor/bin/php-cs-fixer fix` rewrites. `@PER-CS` follows the latest
  PER-CS revision the installed fixer knows, so a fixer upgrade can change the output; pin a revision (`@PER-CS3x0`) when
  the project wants stable formatting. Rule sets that rewrite code semantics are `...Risky` — enable them knowingly.
- Wire the checks into Composer scripts (`project-patterns.md`) so one command runs analysis, style and tests.
