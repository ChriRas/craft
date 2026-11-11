# Shopware 6 — Data Abstraction Layer (DAL) Patterns

Shopware has no ORM. The DAL is a thin layer of **definitions** (fields, flags, associations), **entities** (structs),
**collections** and **repositories**, with indexers and events around it. Written for 6.7; 6.6 differences are marked.
Migrations (the tables themselves) are in `plugin-patterns.md`.

## Two ways to declare an entity

**Attribute entity** (since 6.6.3.0; a collection class since 6.6.9.0) — the least code, the default for a new plugin entity.
Public typed properties, no getters or setters, no definition; `collectionClass:` is optional (6.6.9.0+) — when set, it names
a class extending `EntityCollection` (`ExampleCollection` below, shown with the classic entity):

```php
use Shopware\Core\Framework\DataAbstractionLayer\Attribute\{Field, FieldType, PrimaryKey, Required, Translations, ManyToOne};
use Shopware\Core\Framework\DataAbstractionLayer\Attribute\Entity as EntityAttribute;
use Shopware\Core\Framework\DataAbstractionLayer\Entity;

#[EntityAttribute('swag_example', collectionClass: ExampleCollection::class)]
class ExampleEntity extends Entity
{
    #[PrimaryKey]
    #[Field(type: FieldType::UUID, api: true)]
    public string $id;

    #[Field(type: FieldType::STRING, translated: true, api: true)]
    public ?string $name = null;          // a translated property must be nullable

    #[Field(type: FieldType::BOOL, api: true)]
    public bool $active = true;

    /** @var array<string, ArrayEntity>|null */
    #[Translations]
    public ?array $translations = null;   // nullable: loaded only when the association is added to the Criteria
}
```

Register it with a tag in `services.php`: `$services->set(ExampleEntity::class)->tag('shopware.entity');` — Shopware then
creates `swag_example.definition` and `swag_example.repository` (and the translation definition). A property that is not
nullable is required. **A field is not exposed in the API unless `api: true` (or a list of API source classes) is set.**
Other attributes: `#[AutoIncrement]`, `#[ForeignKey(entity: 'currency')]`, `#[ManyToOne|OneToOne|OneToMany|ManyToMany(entity: …, onDelete: OnDelete::CASCADE)]`,
`#[CustomFields]`, `#[Serialized(serializer: …)]`. The docs do not cover the table: write the migration (`dal:migration:create`
reads the registered definition). On 6.6.0 to 6.6.2 there is no attribute entity: use a definition.

**Definition class** — when you need flags, computed fields, a custom entity class hydration, versioning or inheritance, or the
project is on 6.6.2 or older. Tag: `->tag('shopware.entity.definition', ['entity' => 'swag_example'])`.

```php
class ExampleDefinition extends EntityDefinition
{
    public const ENTITY_NAME = 'swag_example';

    public function getEntityName(): string { return self::ENTITY_NAME; }
    public function getEntityClass(): string { return ExampleEntity::class; }
    public function getCollectionClass(): string { return ExampleCollection::class; }

    protected function defineFields(): FieldCollection
    {
        return new FieldCollection([
            (new IdField('id', 'id'))->addFlags(new PrimaryKey(), new Required(), new ApiAware()),
            (new TranslatedField('name'))->addFlags(new ApiAware()),
            (new BoolField('active', 'active'))->addFlags(new ApiAware()),
            new TranslationsAssociationField(ExampleTranslationDefinition::class, 'swag_example_id'),
        ]);
    }
}
```

Fields take `(storageName snake_case, propertyName lowerCamelCase)`. `created_at` / `updated_at` are added by default. In 6.8
the `EntityDefinition` constructor is removed (do not call `parent::__construct()`) and your defined fields are applied
after the defaults. The entity class extends `Entity` with `EntityIdTrait`; its properties are at least `protected` and
never `readonly`; the collection `@extends EntityCollection<ExampleEntity>` and returns the class from `getExpectedClass()`.

## Flags and field types

- Flags worth knowing: `PrimaryKey`, `Required`, `ApiAware` (exposes the field in the Store API / Admin API — nothing is
  served without it), `CascadeDelete`, `RestrictDelete`, `SetNullOnDelete`, `Inherited` (variants), `AllowHtml` (sanitised
  rich text), `SearchRanking` (full-text weight), `WriteProtected`, `Computed`, `Runtime`, `Extension`.
- Types: `IdField`, `FkField`, `StringField`, `LongTextField`, `IntField`, `FloatField`, `BoolField`, `DateTimeField`,
  `DateField`, `JsonField`, `ListField`, `PriceField`, `EmailField`, `PasswordField`, `EnumField`, `CustomFields`,
  `TranslatedField`, `VersionField`, `ParentFkField`, association fields. Pick the narrowest type; a `JsonField` is stored as one JSON
  value, not as columns you can index.
- Associations: `ManyToOneAssociationField('manufacturer', 'manufacturer_id', ManufacturerDefinition::class)` with its
  `FkField`; `OneToManyAssociationField('items', ItemDefinition::class, 'example_id')`; `ManyToManyAssociationField` through a
  mapping definition extending `MappingEntityDefinition` (both foreign keys are primary keys) and
  `ManyToManyIdField` for id lists. Decide `CascadeDelete` / `RestrictDelete` on purpose for each.
- **Translations**: a `<entity>_translation` table with the parent id, `language_id`, the translated columns and a composite
  primary key; the parent definition has `TranslatedField`s and a `TranslationsAssociationField`. In the Storefront read
  `entity.translated.name` (the fallback chain applied), in the Administration `entity.name` (the stored value).

## Extend a core entity — never alter its table

Add data to `product`, `order` etc. with an `EntityExtension` and your own table, or with custom fields:

```php
class ProductExtension extends EntityExtension
{
    public function getEntityName(): string { return ProductDefinition::ENTITY_NAME; }

    public function extendFields(FieldCollection $collection): void
    {
        $collection->add(
            (new OneToOneAssociationField('swagExample', 'id', 'product_id', ExampleExtensionDefinition::class, true))
                ->addFlags(new CascadeDelete())
        );
    }
}
```

Register it `->tag('shopware.entity.extension')`. The extension appears under `$product->getExtension('swagExample')`.
Custom fields (`custom-fields.xml` set, or the `CustomFields` field of your own entity) suit a few scalar values merchants edit;
they are JSON, not indexable columns. Variants: an `Inherited` flag on the field and `inheritanceAware` on the entity.

## Reading

```php
$criteria = new Criteria();
$criteria->setTitle('swag-example::overdue');                          // labels the SQL in logs
$criteria->addFilter(new EqualsFilter('active', true), new RangeFilter('stock', [RangeFilter::GTE => 1]));
$criteria->addAssociation('manufacturer');                             // 'productReviews.customer' for nested
$criteria->getAssociation('productReviews')->addFilter(new RangeFilter('points', [RangeFilter::GTE => 4]));
$criteria->addSorting(new FieldSorting('createdAt', FieldSorting::DESCENDING), new FieldSorting('id'));
$criteria->setLimit(25)->setOffset(0);
$criteria->setTotalCountMode(Criteria::TOTAL_COUNT_MODE_NEXT_PAGES);   // default NONE; EXACT is the expensive one

$result = $this->repository->search($criteria, $context);   // EntitySearchResult: getEntities(), first(), getTotal()
$ids    = $this->repository->searchIds($criteria, $context); // ids only — for mapping or "exists" checks
```

- Filters: `EqualsFilter`, `EqualsAnyFilter`, `ContainsFilter`, `RangeFilter`, `NotFilter`, `AndFilter`, `OrFilter`,
  `MultiFilter`. Only `addFilter` narrows the aggregations; `addPostFilter` does not.
- **Load only the associations you read.** An association not added to the Criteria is `null` on the entity — and loading
  every one is the DAL's N+1. A filter on `productReviews.points` filters the products; a filter on the association
  (`getAssociation(...)->addFilter`) filters the loaded reviews.
- Aggregations: `addAggregation(new AvgAggregation('avg', 'productReviews.points'))`, read from `$result->getAggregations()`.
- Big sets: `RepositoryIterator($repository, $context, $criteria->setLimit(500))` with `fetch()` / `fetchIds()`. A custom sort
  must be deterministic (add `id` as the last sort) or batches overlap and skip rows.
- A Storefront or Store API read of a core entity that has a sales-channel definition goes through `SalesChannelRepository`
  (service `sales_channel.product.repository` for products) with a `SalesChannelContext`, which applies the sales channel's
  visibility and price rules; the plain `EntityRepository` ignores them. Your own entity has only the plain repository.
- Raw SQL with the injected `Doctrine\DBAL\Connection` is for reports and bulk reads the DAL cannot express. It bypasses
  events, ACL and inheritance; IDs are `BINARY(16)` (`Uuid::fromHexToBytes()`), and it never writes core tables.

## Writing

```php
$id = Uuid::randomHex();                                  // Shopware\Core\Framework\Uuid\Uuid
$this->repository->create([['id' => $id, 'name' => 'A', 'active' => true]], $context);
$this->repository->update([['id' => $id, 'active' => false]], $context);
$this->repository->upsert([['id' => $id, 'name' => 'B']], $context);   // needs an id, else it always creates
$this->repository->delete([['id' => $id]], $context);
```

- Every call takes a **list** of records and one `Context`; write many at once, never in a loop of single calls.
- Associations are written nested: a to-one by its foreign key or nested record, a to-many as a list of records or id maps
  (`'categories' => [['id' => $categoryId]]`), translations as `'translations' => ['en-GB' => ['name' => 'A']]` or by language id.
- The result is an `EntityWrittenContainerEvent`; `getPrimaryKeys('swag_example')` returns the ids written. A validation
  failure throws `WriteException` with the field paths — catch it where you can report it.
- Do not use `Context::createDefaultContext()` to write on behalf of a user: it carries no `AdminApiSource` and skips ACL;
  use the caller's context. `$context->scope(Context::SYSTEM_SCOPE, fn (Context $c) => …)` lifts write protection for one
  closure — for protected core fields only, and the closure stays minimal.
- A delete blocked by `RestrictDelete` is refused with `409 FRAMEWORK__DELETE_RESTRICTED`. Since 6.7.12.0 that did not hold for
  many-to-many associations; the release notes list the fix under 6.7.17.0 (upcoming on 2026-11-11) — test your delete path.

## Events and indexers

- DAL events per entity: `<entity>.loaded`, `.written`, `.deleted`, `.search.result.loaded`, `.id.search.result.loaded`.
  `EntityWriteEvent` / `EntityDeleteEvent` fire *before* the write and take `addSuccess()` / `addError()` callbacks — use them
  when you need the old state. Versioned entities fire per version: filter on `Defaults::LIVE_VERSION`.
- An **indexer** keeps derived data (`extends EntityIndexer`: `getName`, `getTotal`, `iterate`, `update` on written events,
  `handle` from the queue, `getDecorated()` throwing `DecorationPatternException`); register it with the `shopware.entity_indexer`
  tag and run it with `bin/console dal:refresh:index`. Do the work in `handle()`, not in `update()`.
- Cascade and inheritance rules live in the definition; a subscriber that re-implements them drifts.

## Review checklist

- [ ] Own table, prefixed names, an `EntityExtension` or custom field instead of a core column.
- [ ] `ApiAware` / `api: true` only on fields that are meant to be public.
- [ ] Associations are added to the Criteria before they are read; `first()` is null-checked.
- [ ] Writes are batched with the caller's context; a deterministic sort for iterators.
- [ ] The migration, the definition and `bin/console dal:validate` agree.
