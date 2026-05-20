# Pest — Test Patterns

## Unit tests — services

```php
describe('TransferService', function () {
    beforeEach(function () {
        $this->service = app(TransferService::class);
    });

    it('moves funds between accounts', function () {
        $from = Account::factory()->withBalance(100_00)->create();
        $to = Account::factory()->withBalance(0)->create();

        $this->service->transfer($from, $to, Money::fromMinor(40_00));

        expect($to->fresh()->balance)->toEqual(Money::fromMinor(40_00));
    });

    it('rejects a transfer that exceeds the balance', function () {
        // failure path — see below
    })->throws(InsufficientFundsException::class);
});
```

## Feature tests — Filament

```php
use function Pest\Livewire\livewire;

it('creates a record through the resource', function () {
    $this->actingAs(User::factory()->create());

    livewire(CreateAccount::class)
        ->fillForm(['name' => 'Operating', 'currency' => 'EUR'])
        ->call('create')
        ->assertHasNoFormErrors();

    expect(Account::where('name', 'Operating')->exists())->toBeTrue();
});
```

## Systematic coverage

The Senior-Developer baseline's test-discipline matrix, expressed in Pest:

| Category | Pest expression |
|---|---|
| Boundaries | null, empty, zero, max as explicit cases. |
| Variants | a `dataset()` over every backed-enum value. |
| Conditions | each branch — the `true` and the `false` case. |
| Side effects | `Queue::fake()`, `Notification::fake()`, `Event::fake()`. |
| Errors | the failure path asserted with `->throws(...)`. |
| Isolation | an operation on one record leaves others untouched. |

## Datasets & factories

- `dataset()` runs one test across every enum value or input variant.
- Every model has a factory with realistic defaults and `state` helpers for common
  variants.
- DB-touching tests use `RefreshDatabase`.
