# PHP 8.4 / 8.5 — Code Quality Standards

Language-level idioms for PHP 8.4 and 8.5. Framework patterns are in
`framework-patterns.md`; test patterns in `test-patterns.md`.

## Mandatory shape

```php
<?php

declare(strict_types=1);

namespace App\Services\Billing;

final readonly class InvoiceTotal
{
    public function __construct(
        private TaxRate $taxRate,
    ) {}

    public function net(Invoice $invoice): Money
    {
        // ...
    }
}
```

## Checklist

- [ ] `declare(strict_types=1)` in every file.
- [ ] Full type hints on every parameter and return type.
- [ ] No `mixed` unless genuinely unavoidable.
- [ ] `readonly` properties / classes for immutable data.
- [ ] Backed enums instead of magic strings.
- [ ] `#[\Override]` on overridden methods.
- [ ] Named arguments past three parameters, or for boolean flags.
- [ ] `final` on classes not designed for extension.
- [ ] Constructor property promotion for dependencies.
- [ ] Guard clauses and early returns over nested conditionals.

## PHP 8.5 idioms

When the project runs PHP 8.5 (check `rules.md` `## Stack & Tools`), prefer these:

- **Pipe operator `|>`** — chain transformations left-to-right instead of nesting
  calls; the left value becomes the first argument of the right-hand callable. Wrap
  arrow functions in parentheses.

  ```php
  $slug = $title
      |> trim(...)
      |> strtolower(...)
      |> (fn (string $s) => str_replace(' ', '-', $s));
  ```

- **Clone-with** — produce a modified copy of a `readonly` object by cloning with
  property overrides, instead of hand-written `with*()` methods.

  ```php
  $discounted = clone($price, ['amount' => $price->amount->minus($rebate)]);
  ```

- **`#[\NoDiscard]`** — mark a function whose return value must not be ignored, with
  a message explaining why.

  ```php
  #[\NoDiscard('the result carries a per-item error array')]
  public function bulkProcess(array $items): array
  {
      // ...
  }
  ```

## Error handling

Throw domain-specific exceptions that carry context, not a bare `\Exception`:

```php
final class InsufficientFundsException extends \DomainException
{
    public function __construct(
        public readonly Account $account,
        public readonly Money $requested,
        public readonly Money $available,
    ) {
        parent::__construct(
            "Insufficient funds on account {$account->id}: "
            . "requested {$requested}, available {$available}"
        );
    }
}
```

## Dates & money

- Use an immutable date type (`CarbonImmutable`) for date/time values.
- Never represent money as a float — use integer minor units or a money value object.
