# Laravel & Filament — Framework Patterns

## Service layer

Business logic lives in services — never in controllers, models, jobs, or Filament
resources.

```php
final readonly class TransferService
{
    public function __construct(
        private LedgerWriter $ledger,
    ) {}

    public function transfer(Account $from, Account $to, Money $amount): void
    {
        DB::transaction(function () use ($from, $to, $amount) {
            $this->ledger->debit($from, $amount);
            $this->ledger->credit($to, $amount);
        });
    }
}
```

- **Models** — relationships, casts, scopes. No business logic.
- **Jobs** — thin wrappers; `handle()` delegates to a service.
- **Controllers / Filament resources** — request and UI handling; delegate to services.

## Eloquent

- Casts declared via the `casts()` method; backed enums as cast targets.
- Recurring queries as query scopes, not ad-hoc `where()` chains in services.
- Foreign keys constrained on every relationship (`->constrained()`).

## Transactions

Every multi-table write runs inside `DB::transaction()`.

## N+1 prevention

Eager-load known relationships — `->with([...])` in the query, `->withCount()` for
aggregates. Never trigger a query inside a loop.

## Filament

- Form schema carries validation and conditional UI; mark a field `->live()` when
  other fields react to it.
- Table columns: `->searchable()` / `->sortable()` where the UX needs it; eager-load
  in the resource's query to avoid N+1.
- The resource delegates to services — no business logic in the resource.
- Enums shown in the UI implement Filament's label / colour contracts.
