# API Platform — Query Patterns

Filters, sorting, pagination and the query of a collection on Doctrine ORM. Written for API Platform 5.0 (the parameter
system arrived in 4.2 and settled in 4.3 / 4.4); the Doctrine ODM filters share the names under
`ApiPlatform\Doctrine\Odm\Filter`.

## Parameters and filters — the way to declare them

A client-facing query or header value is a **parameter**; a **filter** is the class that applies it to the query. Declare
parameters with `QueryParameter` on an operation (or on the resource, for all operations). They appear in the Hydra,
OpenAPI and GraphQL documentation by themselves. The old `#[ApiFilter]` attribute, `Operation::$filters` and the
`AbstractFilter` base class still work in 5.0 but are deprecated and go in 6.0: a new resource does not use them.

```php
use ApiPlatform\Doctrine\Orm\Filter\ComparisonFilter;
use ApiPlatform\Doctrine\Orm\Filter\ExactFilter;
use ApiPlatform\Doctrine\Orm\Filter\PartialSearchFilter;
use ApiPlatform\Doctrine\Orm\Filter\SortFilter;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\QueryParameter;

#[GetCollection(parameters: [
    'status' => new QueryParameter(filter: new ExactFilter(), property: 'status'),
    'title' => new QueryParameter(filter: new PartialSearchFilter(), property: 'title'),
    'price' => new QueryParameter(filter: new ComparisonFilter(new ExactFilter()), property: 'price'),
    'order' => new QueryParameter(filter: new SortFilter(), property: 'title'),
])]
```

`GET /books?status=new&title=ring&price[gte]=10&order=asc`. A `#[GetCollection]` attribute written next to a bare
`#[ApiResource]` is a declared operation: the default `Post`, `Patch` and `Delete` disappear (a probe answered 405 to a
`POST`). List every operation the resource needs. The key is the URL name; `property` is the entity property
(dot notation reaches a relation: `author.name`; the joins are resolved once, at cache warm-up).

| Need | Filter |
|---|---|
| Exact value, boolean, numeric equality, enum | `ExactFilter` (replaces `BooleanFilter`, `NumericFilter`, `BackedEnumFilter`) |
| Contains / starts with / ends with / word start | `PartialSearchFilter`, `StartSearchFilter`, `EndSearchFilter`, `WordStartSearchFilter` |
| A relation by IRI | `IriFilter` |
| Greater / less / not equal / between | `new ComparisonFilter(new ExactFilter())`: `[gt]`, `[gte]`, `[lt]`, `[lte]`, `[ne]` and `[between]=10..100` (numeric bounds) |
| A date interval | `DateFilter`: `[after]`, `[before]` (inclusive), `[strictly_after]`, `[strictly_before]` — kept, declare it in a `QueryParameter` |
| A nullable value exists | `ExistsFilter` (kept) |
| Sorting | `SortFilter` — one parameter per sorted property, value `asc` / `desc`, `nullsComparison:` for nulls (replaces `OrderFilter`) |
| One input over several properties | `new FreeTextQueryFilter(new PartialSearchFilter())` with `properties: ['title', 'isbn']`; `OrFilter` joins with OR |
| One key, several kinds of value | `ChainFilter` |

- **`RangeFilter` is deprecated in 5.0** for `ComparisonFilter` (removed in 6.0); `SearchFilter` is a multi-type filter the
  docs advise against — pick the type-specific filter.
- **One parameter per property** with a placeholder: `'search[:property]' => new QueryParameter(filter: new
  PartialSearchFilter(), properties: ['title', 'author'])` creates `search[title]` and `search[author]`; without
  `properties` it covers every property.
- **Migrating legacy filters** — `php bin/console api:upgrade-filter` rewrites `#[ApiFilter]` declarations into
  `QueryParameter`s; review the diff. A filter inside a `QueryParameter` is created with named arguments
  (`new DateFilter(nullManagement: ...)`) — constructors change between versions.
- An inline `new DateFilter()` logs a harmless `ManagerRegistry must be initialized` alert at cache warm-up
  (issue 7361); a service id string or a `ChainFilter` avoids it.
- Always give a Doctrine parameter filter its `property` (or the `:property` placeholder): since 4.3 it throws without.
- **Validation of parameters** — `required: true`, `constraints: [new Assert\Country()]` with a `nativeType:`, and the
  JSON Schema the filter publishes (a `SortFilter` rejects a value other than asc / desc with 422).
  `strictQueryParameterValidation: true` on the operation answers 400 to an undeclared query parameter.
- A header is a `HeaderParameter`; `defaults.parameters` in `api_platform.yaml` declares one for every resource.

## A custom filter

Implement `ApiPlatform\Doctrine\Orm\Filter\FilterInterface` (`apply(QueryBuilder $queryBuilder,
QueryNameGeneratorInterface $queryNameGenerator, string $resourceClass, ?Operation $operation = null, array $context = [])`);
`make:filter orm` generates the skeleton, and `$context['parameter']` carries the key and value. Use the query name
generator for every alias and parameter name (`$queryNameGenerator->generateParameterName('month')`) so two filters never
collide, and bind values — never concatenate them into DQL. A filter that documents itself implements
`OpenApiParameterFilterInterface` or `JsonSchemaFilterInterface`.

## Restricting a collection to what the caller may see

A voter cannot filter a collection. Restrict the query itself with a Doctrine extension — a service implementing
`QueryCollectionExtensionInterface` and `QueryItemExtensionInterface` (autoconfigured):

```php
final readonly class OwnedByCurrentUserExtension implements QueryCollectionExtensionInterface, QueryItemExtensionInterface
{
    public function __construct(private Security $security) {}

    public function applyToCollection(QueryBuilder $qb, QueryNameGeneratorInterface $names, string $resourceClass, ?Operation $operation = null, array $context = []): void
    {
        $this->restrict($qb, $resourceClass);
    }

    public function applyToItem(QueryBuilder $qb, QueryNameGeneratorInterface $names, string $resourceClass, array $identifiers, ?Operation $operation = null, array $context = []): void
    {
        $this->restrict($qb, $resourceClass);
    }

    private function restrict(QueryBuilder $qb, string $resourceClass): void
    {
        if (Book::class !== $resourceClass || $this->security->isGranted('ROLE_ADMIN')) {
            return;
        }
        $alias = $qb->getRootAliases()[0];
        if (null === $user = $this->security->getUser()) {
            $qb->andWhere('1 = 0'); // fail closed: an anonymous caller sees nothing
            return;
        }
        $qb->andWhere(sprintf('%s.owner = :current_user', $alias))->setParameter('current_user', $user);
    }
}
```

- **Fail closed.** An extension that returns early for an anonymous caller leaves the query unrestricted — every user's rows
  go to an unauthenticated request whenever the operation carries no `security`. Restrict to nothing instead, and still
  guard the operations (`security: "is_granted('ROLE_USER')"`) so an anonymous call answers 401, not an empty list.

- The built-in providers use the root alias `o`; give your own joins another alias. A custom provider does not run
  extensions unless it calls them — the extension system is the Doctrine provider's.
- For a different base query on a resource: `stateOptions: new Options(repositoryMethod: 'findAvailable')` (the repository
  method is public and returns a `QueryBuilder`).
- Default order: `#[ApiResource(order: ['createdAt' => 'DESC'])]`; without it the collection is ordered by identifier,
  ascending. A paginated collection needs a stable order, or pages repeat and skip rows.

## Pagination

On by default for every collection: 30 items per page, a Hydra collection with `member`, `totalItems` and a `view` of
`first` / `last` / `next` / `previous` links (a JSON-LD key set without the `hydra:` prefix since 4.0).

| Setting | Resource / operation attribute | Global `api_platform.defaults` |
|---|---|---|
| On or off | `paginationEnabled: false` | `pagination_enabled` |
| Items per page | `paginationItemsPerPage: 30` | `pagination_items_per_page` |
| Cap on a client's choice | `paginationMaximumItemsPerPage: 50` | `pagination_maximum_items_per_page` |
| Client turns pagination on / off (`?pagination=false`) | `paginationClientEnabled: true` | `pagination_client_enabled` (default false) |
| Client sets the page size (`?itemsPerPage=20`) | `paginationClientItemsPerPage: true` | `pagination_client_items_per_page` |
| Skip the `COUNT` query, lose `last` | `paginationPartial: true` | `pagination_partial` (default false) |

- The parameter names live under `api_platform.collection.pagination` (`page_parameter_name`, `enabled_parameter_name`,
  `items_per_page_parameter_name`, `partial_parameter_name`).
- **Never let a client turn pagination off on a large collection**; set `paginationMaximumItemsPerPage` whenever
  `paginationClientItemsPerPage` is on.
- **Partial pagination** removes the `COUNT` on a huge table; the price is the `last` page link.
- **Cursor pagination** (`paginationViaCursor: [['field' => 'id', 'direction' => 'DESC']]` with `paginationPartial: true`)
  needs a range filter and an order filter on the cursor field. The docs' example still declares the legacy `RangeFilter` /
  `OrderFilter` (deprecated) — keep it for a collection that needs a cursor, and keep the cursor field unique and indexed.
- **A custom provider** that wants pagination returns a `PaginatorInterface` or `PartialPaginatorInterface`:
  `ArrayPaginator` or `TraversablePaginator` wrap an array or iterable with the page, size and total.
- **Doctrine paginator** — a join to a collection-valued association needs `paginationFetchJoinCollection: true` and
  sometimes `paginationUseOutputWalkers: true`; API Platform guesses both, override only when counts are wrong.

## Eager loading and N+1

API Platform joins every readable association into the collection query (`eager_loading.force_eager` is true), but only
for relations that are in a **serialization group** of the operation — so groups on relation properties are also the
performance setting. Up to 30 joins per query (`eager_loading.max_joins`), after which a `RuntimeException` is thrown —
usually a circular embedding. `#[ApiProperty(fetchEager: true)]` joins a relation that is not serialized;
`eager_loading.fetch_partial` selects only the grouped columns (off by default; entities then arrive partial). Check the
query count of the busiest collection in a test or the profiler before calling a list endpoint done.

## The HTTP `QUERY` operation (RFC 10008)

For criteria too large for a URL, add `new Query(parameters: [...])` to the resource (not registered by default): the same
parameters and filters read the request **body** (`application/json` or `application/x-www-form-urlencoded`, with a
`Content-Type` even for an empty body). Or set `input: BookCriteria::class` and put `QueryParameter` on its properties.
Documented since 4.4; a proxy or client in front of the API must pass the `QUERY` method.
