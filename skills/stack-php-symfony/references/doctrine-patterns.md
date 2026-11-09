# Symfony — Doctrine Patterns

Doctrine ORM 3.7 with DBAL 4 through DoctrineBundle 3.3 (PHP 8.4); DoctrineBundle 2.19 keeps PHP 8.1 to 8.3 running with
the same ORM 3 API. Install with `composer require symfony/orm-pack` (ORM, DoctrineBundle, DoctrineMigrationsBundle) and
`composer require --dev symfony/maker-bundle`. Where the 7.4 LTS or an older bundle differs it is marked.

## Versions that matter

- **Mapping is attributes** (`#[ORM\...]`) or XML. The annotation and YAML drivers are gone from ORM 3, and DoctrineBundle 3
  dropped ORM 2, DBAL 3 and Persistence 3. The recipe's `doctrine.yaml` maps `src/Entity` with `auto_mapping: true`.
- **Native lazy objects** — on PHP 8.4 DoctrineBundle 3 always uses them (`enable_native_lazy_objects` cannot be turned
  off), so there are no generated proxy classes and an entity class may be `final` (or `readonly`). Before that (bundle
  2.x, PHP below 8.4) keep entities non-final so Doctrine can generate proxies.
- **Property hooks** — since ORM 3.4 a hooked property maps if it is backed (not virtual; mapping a virtual one throws).
  Queries use the raw stored value, not the hooked one (`basic-mapping.rst` → Property Hooks).
- **`Paginator`** (`Doctrine\ORM\Tools\Pagination\Paginator`) is deprecated since ORM 3.7: use `OffsetPaginator` with a
  `Window` in new page queries; a project that already uses `Paginator` or a paginator bundle keeps its form.
- **Server version** — set `serverVersion` in `DATABASE_URL` (`?serverVersion=16&charset=utf8`; a
  `mariadb-` prefix for MariaDB). The recipe's own comment says you must configure it, and the migrations bundle
  fails on its metadata storage when the version is wrong.

## Entities

```php
#[ORM\Entity(repositoryClass: InvoiceRepository::class)]
#[ORM\Table(name: 'invoice')]
#[ORM\UniqueConstraint(name: 'uniq_invoice_number', columns: ['number'])]
class Invoice
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 32)]
    private string $number;

    #[ORM\Column(enumType: InvoiceStatus::class)]
    private InvoiceStatus $status = InvoiceStatus::Draft;

    #[ORM\Column]
    private \DateTimeImmutable $issuedAt;

    /** @var Collection<int, InvoiceLine> */
    #[ORM\OneToMany(targetEntity: InvoiceLine::class, mappedBy: 'invoice', cascade: ['persist'], orphanRemoval: true)]
    private Collection $lines;

    public function __construct(string $number, \DateTimeImmutable $issuedAt)
    {
        $this->number = $number;
        $this->issuedAt = $issuedAt;
        $this->lines = new ArrayCollection();
    }
    // behaviour as named methods: addLine(), markPaid() — no setter for every field
}
```

- An entity is a domain object: valid from its constructor, state changed by named methods (`markPaid()`), not a bag of
  public setters. Initialize every collection in the constructor.
- **Types** — `\DateTimeImmutable` (never mutable `DateTime`) for dates, backed enums with `enumType:`, `UuidType::NAME`
  or `UlidType` when the id must not be guessable, `Types::JSON` / `Types::DECIMAL` for the obvious cases. Money as integer
  minor units or `DECIMAL`, never `float`.
- **Associations** — the owning side is the one with the foreign key (`ManyToOne`, or `ManyToMany` with `JoinTable`); the
  inverse side has `mappedBy`. Keep both sides in sync inside the entity's `addLine()` / `removeLine()`. `cascade` and
  `orphanRemoval` only for a part-of relation the aggregate owns. Prefer a `ManyToOne` plus a repository query over a large
  bidirectional `OneToMany` collection nobody iterates; `fetch: 'EXTRA_LAZY'` lets `count()` and `contains()` skip the load.
- **Validation** on the entity with `#[Assert\...]` and `UniqueEntity` (`Symfony\Bridge\Doctrine\Validator\Constraints`);
  the database constraint is the real guarantee, the validator the friendly message.
- **Lifecycle** — keep `#[ORM\HasLifecycleCallbacks]` for trivial things (`updatedAt`); logic with services goes in a
  listener class marked `#[AsEntityListener]` or `#[AsDoctrineListener]`.
- Identity: let the database generate ids (`#[ORM\GeneratedValue]`) unless the domain supplies a UUID.

## Repositories

```php
/** @extends ServiceEntityRepository<Invoice> */
final class InvoiceRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, Invoice::class);
    }

    /** @return list<Invoice> */
    public function findOpenWithLines(): array
    {
        return $this->createQueryBuilder('i')
            ->addSelect('l')
            ->join('i.lines', 'l')
            ->where('i.status = :status')
            ->setParameter('status', InvoiceStatus::Open)
            ->getQuery()
            ->getResult();
    }
}
```

- One repository per aggregate root, extending `ServiceEntityRepository` (autowired; it is the class named in
  `repositoryClass`). Queries are named methods that return entities or a read-model DTO (`SELECT NEW ...`); a service
  never builds DQL itself. Use the QueryBuilder or DQL with bound parameters — never string-concatenate values.
- `find()`, `findOneBy()` and `findBy()` are fine for key lookups; a method with a name says what the query means.
- A user repository implements `PasswordUpgraderInterface` (`framework-patterns.md` → Security).
- Persist and flush belong to the service that owns the unit of work (or the repository's `save()` helper), never to a
  controller that also renders; `flush()` once at the end of the use case.

## The unit of work, transactions and N+1

- `persist()` schedules, `flush()` writes: one `flush()` per use case, not one per entity, and not inside a loop. A
  `flush()` is one transaction; for several flushes or other writes that must succeed together use
  `$em->wrapInTransaction(function (): void { ... })` (it flushes before the commit, and on an exception rolls back
  and closes the manager).
- **N+1** — reading `$invoice->getLines()` for every invoice in a loop runs one query per invoice. Fetch the association
  in the query: a join whose entity appears in the `SELECT` (`->addSelect('l')->join('i.lines', 'l')`) is a fetch join. Paginate
  a collection fetch join with care (the limit applies to joined rows); fetch the ids first, then the entities. Enable the
  profiler's Doctrine panel in dev and read the query count.
- **Batch work** — iterate with `$query->toIterable()` and `$em->clear()` every N rows so the identity map does not grow;
  a bulk update or delete is one DQL `UPDATE` / `DELETE`, not a loop of entities. A Messenger worker resets services that
  implement `ResetInterface` between two messages (the entity managers do); your own long-lived services must not keep
  per-message state.
- After `clear()` or a second request in a test, entities are detached — re-fetch before using them.
- **Locking** — optimistic with `#[ORM\Version]` on a column, pessimistic with `LockMode::PESSIMISTIC_WRITE` inside a
  transaction, when two writers can race.

## Migrations

Every schema change ships as a migration; `doctrine:schema:update --force` is for a throwaway local database only.

```bash
php bin/console make:migration --formatted      # diff of mapping vs database -> migrations/VersionYYYYMMDDHHMMSS.php
php bin/console doctrine:migrations:migrate     # apply (run on deploy, with --no-interaction)
php bin/console doctrine:migrations:status      # what is pending
php bin/console doctrine:schema:validate        # mapping valid and in sync with the database
```

- Read the generated SQL before committing it: check that a rename was not generated as drop plus add, which loses
  the data — write it by hand with `$this->addSql(...)`. A migration is never edited after it ran on a shared database;
  add a new one. Keep `down()` truthful or call `$this->throwIrreversibleMigrationException()` in it.
- Data changes go in their own migration (`postUp()` or SQL), and a destructive step follows the deploy that stopped using
  the column (expand, then contract).
- MigrationsBundle 4.x needs PHP 8.4 and DBAL 4; 3.7 supports older PHP and DBAL. Migrations are transactional by default
  (`transactional: true`); DDL that cannot run in a transaction on the platform needs `isTransactional(): false`.
- The test database is created per run: `doctrine:database:create --env=test` and `doctrine:schema:create --env=test` or
  `doctrine:migrations:migrate --env=test`. The recipe adds `dbname_suffix: '_test%env(default::TEST_TOKEN)%'` in
  `when@test`, so tests use `<db>_test` (and one database per ParaTest process).

## Configuration and wiring

- `doctrine.dbal.url: '%env(resolve:DATABASE_URL)%'` and the credentials in `.env.local` or secrets; a password with special
  characters goes in as separate parameters rather than a URL.
- Use `EntityManagerInterface` in a service that coordinates a unit of work and the repository for queries; inject
  `ManagerRegistry` only where several managers exist. Do not call `getRepository()` in application code — inject the
  repository class.
- Long-running workers: the connection can drop; the Messenger `doctrine_ping_connection` middleware reconnects, and
  `doctrine_close_connection` frees it after a message.
- Fixtures for dev and test data: `doctrine/doctrine-fixtures-bundle` (`make:fixtures`, `doctrine:fixtures:load`),
  `--env=test`; never load fixtures against a shared database.
