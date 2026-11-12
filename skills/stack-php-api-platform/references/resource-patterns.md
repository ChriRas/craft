# API Platform — Resource Patterns

How to model a resource, where its data comes from and goes to, which operations it exposes, and how it is validated,
secured and serialized. Written for API Platform 5.0; what 4.4 does differently is marked **4.4**.

## Entity or DTO — the criterion

API Platform builds the API from the **public shape** of a class marked `#[ApiResource]` and fills it through a state
provider (reads) and a state processor (writes). That class is either a Doctrine entity or a separate class.

| Use | When |
|---|---|
| **Entity as the resource** | The API is plain CRUD over the table: same fields, same validity rules, same access for every operation, no business action. Built-in Doctrine provider and processor, filters, pagination and eager loading work with no code. |
| **DTO resource** (a class that is not the entity) linked by `stateOptions` | CRUD, but the API shape differs: renamed, hidden or computed fields, a lighter collection, different write rules. The Object Mapper copies between entity and resource. |
| **DTO resource with a custom provider / processor** | The data does not come from one Doctrine entity (several tables, an external API, a search index, an event store), or the operation is a business action (`/orders/{id}/cancel`), or you want to keep the domain model out of the API contract. |

Decide per resource, not per project, and switch when the two models start to diverge: the first field that must be
renamed, hidden or computed, the first write rule that differs from an entity invariant, the first endpoint that is a verb
and not a row. The docs call sharing the model "super-convenient and efficient" but "probably **not** a good idea for
non-CRUD and/or large systems", and recommend a DTO as the resource for a layered design. An entity with groups on every
property to fake a second shape is the sign to switch.

## Entity as the resource

```php
<?php

declare(strict_types=1);

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Serializer\Attribute\Groups;
use Symfony\Component\Validator\Constraints as Assert;

#[ORM\Entity]
#[ApiResource(
    operations: [
        new GetCollection(),
        new Get(),
        new Post(security: "is_granted('ROLE_EDITOR')"),
        new Patch(security: "is_granted('BOOK_EDIT', object)"),
        new Delete(security: "is_granted('ROLE_ADMIN')"),
    ],
    normalizationContext: ['groups' => ['book:read']],
    denormalizationContext: ['groups' => ['book:write']],
)]
class Book
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    #[Groups('book:read')]
    public private(set) ?int $id = null;

    #[ORM\Column(length: 255)]
    #[Assert\NotBlank, Assert\Length(max: 255)]
    #[Groups(['book:read', 'book:write'])]
    public string $title = '';

    #[ORM\ManyToOne]
    #[Groups('book:read')]
    public ?User $owner = null;
}
```

- **Defaults** — `#[ApiResource]` alone registers `Get`, `GetCollection`, `Post`, `Patch` and `Delete`. `Put` is not
  registered. The moment one operation is declared, the defaults are gone: declare all that you need. An enum resource
  gets `Get` and `GetCollection`.
- **Write the operations out** for anything that leaves a prototype: the list is the API's contract, and each operation
  carries its own `security`, `status`, groups and validation.
- `PATCH` takes `Content-Type: application/merge-patch+json` (JSON Merge Patch, RFC 7396). `PUT` replaces the item; with
  `new Put(allowCreate: true)` it creates a missing one (upsert) and answers 201.
- A resource that is **not** a Doctrine entity needs `#[ApiProperty(identifier: true)]` on its id property, and a provider.
- Identifiers may be UUID v7, ULID, ints or composite; `symfony/uid` and Ramsey UUIDs are supported (identifiers doc).
- Resources that are not entities live in `src/ApiResource/` (the recipe creates it); the bundle finds every class carrying
  `#[ApiResource]` — 5.0 removed the `resource_class_directories` option.

## DTO resource over an entity — `stateOptions` and the Object Mapper

Install `symfony/object-mapper` (^7.4 or ^8.0). The resource class carries `#[Map]`, and `stateOptions` names the entity;
the built-in Doctrine provider reads the entity, the Object Mapper builds the resource from it, and on writes the mapped
input goes back through the Doctrine processor.

```php
use ApiPlatform\Doctrine\Orm\State\Options;
use Symfony\Component\ObjectMapper\Attribute\Map;

#[ApiResource(
    shortName: 'Book',
    stateOptions: new Options(entityClass: BookEntity::class),
    operations: [
        new Get(),
        new GetCollection(output: BookSummary::class),
        new Post(input: CreateBook::class),
        new Patch(input: UpdateBook::class),
    ],
)]
#[Map(source: BookEntity::class)]
final class Book
{
    public int $id;

    #[Map(source: 'title')]
    public string $name;
}

#[Map(target: BookEntity::class)]
final class CreateBook
{
    #[Assert\NotBlank, Assert\Length(max: 255)]
    #[Map(target: 'title')]
    public string $name;
}
```

- `#[Map]` is required on the resource class, and an input class names its entity with `#[Map(target: ...)]`; without the
  attribute the mapper is not used.
- `input:` classes carry the **write** constraints, so the entity can keep its own invariants; `output:` classes shrink a
  collection. `input: false` accepts no body, `output: false` returns none (use it with `status: 202` or `204`).
- `stateOptions` also takes `repositoryMethod:` to start the query from a custom repository method (public, returns a
  `QueryBuilder`; the provider still applies filters, pagination and the identifier). On a `Get`, the method's `WHERE`
  also hides excluded items behind a 404.
- 5.0 splits the old mapping processor into `ObjectMapperInputProcessor` and `ObjectMapperOutputProcessor`; the DTO page of
  the docs still names the old one. Do not reference these classes from application code.

## Providers and processors

A **provider** returns the data for a read: `provide(Operation $operation, array $uriVariables = [], array $context = [])`.
A **processor** handles a write: `process(mixed $data, Operation $operation, array $uriVariables = [], array $context = [])`
and returns the stored object (or nothing for a `Delete`). Both are services set on the resource or per operation:

```php
#[Get(provider: BookRepresentationProvider::class)]
#[Post(processor: PublishBookProcessor::class, output: false, status: 202)]
```

```php
final readonly class BookRepresentationProvider implements ProviderInterface
{
    public function __construct(
        #[Autowire(service: 'api_platform.doctrine.orm.state.item_provider')]
        private ProviderInterface $itemProvider,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): ?BookView
    {
        $book = $this->itemProvider->provide($operation, $uriVariables, $context);

        return $book instanceof Book ? BookView::from($book) : null;
    }
}
```

- **Compose, do not copy** — the built-in services to inject are `api_platform.doctrine.orm.state.item_provider`,
  `…collection_provider`, `…persist_processor` and `…remove_processor` (use `odm` for MongoDB). A processor that adds
  behaviour calls the persist processor and returns its result; a `Delete` goes to the remove processor
  (`$operation instanceof DeleteOperationInterface`).
- **`null` from a provider is a 404** for `Get`, `GetCollection`, `Patch`, `Delete` and a `Put` without `allowCreate`;
  `Post` and an upsert `Put` never throw. `throwOnNotFound: false` lets an operation take `null` as data ("current cart")
  and `true` forces the 404 (**4.4**).
- A collection provider returns an iterable; to paginate it returns a `PaginatorInterface` (`ArrayPaginator`,
  `TraversablePaginator`) — `query-patterns.md`.
- A processor runs on `POST`, `PUT`, `PATCH`, `DELETE`. On a read it runs only with `write: true` on the operation.
- The status can depend on the request: set the request attribute `_api_response_status` in a processor (**4.4**); a fixed
  status is `status:` on the operation, which is also what the generated docs show.
- A service-level business rule belongs in a processor or in the service it calls — one use case per operation. Do not put
  it in an entity listener or a normalizer.
- A provider injects `SerializerInterface` by constructor if it needs it (the setter injection interface is gone in 5.0).
- A write that must not block the request: `messenger: true` on the operation dispatches the resource as a message
  (`symfony/messenger`), usually with `output: false, status: 202`.

## Operations

- **Custom URI** — `uriTemplate: '/books/{id}/publish'` with `uriVariables: ['id']`, `requirements: ['id' => '\d+']`, a
  `status`, `name:`. A static route that also matches `/books/{id}` needs `routePriority: 1` on it (5.0; higher is tried first).
- **Business actions** are a `Post` on a verb path with an `input:` DTO and a processor (the `dto.md` discount example).
  Custom Symfony controllers (`controller:`) and the kernel event listeners are discouraged by the docs and work only
  with `use_symfony_listeners: true`; GraphQL ignores them. Use a provider or a processor.
- **Subresources** are another `#[ApiResource]` on the class with a `uriTemplate` and `uriVariables` links:
  `'id' => new Link(fromClass: Question::class, fromProperty: 'answer')` for `/questions/{id}/answer`.
- **`NotExposed`** registers a URI template for IRI generation without a public endpoint (a resource only referenced by
  others).
- **Hide an operation from the docs** with `openapi: false`; document it with `openapi: new Model\Operation(...)`.
- **`QUERY`** (RFC 10008, **4.4**) carries filter criteria in the body: `new Query(parameters: [...])` — `query-patterns.md`.

## Validation

API Platform validates the deserialized object with Symfony Validator on `POST`, `PUT` and `PATCH` and answers **422** with
a `violations` list (`propertyPath`, `message`, `code`) in the negotiated error format. Not validated by default:
`DELETE`, and `GET`.

- Constraints go on the resource or on the input DTO (`#[Assert\...]`, custom constraints as usual).
- **Groups per operation** — `validationContext: ['groups' => ['Default', 'postValidation']]` on the operation; a `Default`
  constraint applies to every operation unless its group is named otherwise.
- **A rule on delete** — put the constraint in a group (`deleteValidation`) and validate in a processor that wraps the remove
  processor, with `ApiPlatform\Validator\ValidatorInterface::validate($data, ['groups' => ['deleteValidation']])`.
- **Type errors in the body** (a string for an int, `null` for a non-nullable property) become **422 only if the property
  has a constraint** (a matching `Type` / `NotBlank` / `NotNull`, or any constraint); with none the serializer's error
  stays **400** (**4.4**; a probe of an unconstrained `string` property sent an int and got 400). The upgrade notes say the same
  for a backed enum without a constraint: add `#[Assert\Type(Status::class)]` or enable Symfony's validator auto-mapping,
  and assert the status in a test (a probe with a nullable enum property answered 422 for a bad case and for an int).
  `collectDenormalizationErrors: true` reports every field at once.
- A `UniqueConstraintViolationException` is mapped to **422** by default in 5.0 (409 for `OptimisticLockException`).
  Prefer `#[UniqueEntity]` so the client gets a violation, not a database error.
- Parameters (query and header) validate through `constraints:` and `required:` on the `QueryParameter` — `query-patterns.md`.
- Validate the DTO, not the entity, when the entity is the persistence model of a DTO resource: input classes carry the
  constraints.

## Security

```php
#[ApiResource]
#[GetCollection(security: "is_granted('ROLE_USER')")]
#[Get(security: "is_granted('BOOK_VIEW', object)")]
#[Post(securityPostDenormalize: "is_granted('BOOK_CREATE', object)", securityMessage: 'Not allowed.')]
```

- **`security`** runs before denormalization, so `object` is the stored state; **`securityPostDenormalize`** runs after, with
  `previous_object` (the state before the change, `null` on create). Use `securityPostDenormalize` for a voter on a
  `Post` — before denormalization the object does not exist. Variables: `user`, `object`, `previous_object`, `request`
  (resource level only). Do not combine both on one operation — and a `security` on `#[ApiResource]` is inherited by every
  operation, so a resource-level `security` plus a `securityPostDenormalize` on the `Post` is that combination: put
  `security` on the operations instead, as above.
- An expression that does not use `object` is checked before the provider runs (since 4.3), saving the query for an
  anonymous caller. Expressions with `object` wait for the provider.
- **Voters** carry rules about a specific object; they apply through `is_granted('ATTR', object)`:

```php
final class BookVoter extends Voter
{
    protected function supports(string $attribute, mixed $subject): bool
    {
        return \in_array($attribute, ['BOOK_VIEW', 'BOOK_EDIT'], true) && $subject instanceof Book;
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token): bool
    {
        $user = $token->getUser();

        return $user instanceof User && $subject->owner?->id === $user->id;
    }
}
```

  (The docs' voter example imports `Security\Core\Security` and a `Role` class; neither exists any more — write it as above.)
- **A voter cannot filter a collection.** Restrict what a user sees in the provider's query with a Doctrine **extension**
  (`QueryCollectionExtensionInterface` and `QueryItemExtensionInterface`, `Security` injected) — `query-patterns.md`.
- **Property level** — `#[ApiProperty(security: "is_granted('ROLE_ADMIN')", securityPostDenormalize: "...")]` hides and
  guards a single field.
- A processor or voter can throw `ApiPlatform\Metadata\Exception\AccessDeniedException` with a `detail` (always sent to the
  client — keep roles and ownership out of it); the `Symfony\Security\Exception` one is deprecated (**4.4**). A voter's
  reasons appear in the error through `access_decision` (**4.4**).
- **Authentication** — a stateless firewall with `json_login` or `access_token`; the docs recommend OIDC over a hand-made JWT
  flow; `lexik/jwt-authentication-bundle` (3.2) is the documented JWT option. Hash a user's password in a processor
  (`PasswordHasher` + a non-persisted `plainPassword`), never in the entity setter.
- Mark every endpoint explicitly: a resource with no `security` is public.

## Serialization

- `normalizationContext` / `denormalizationContext` with groups choose the fields of a read and of a write; the
  operation-level value replaces the resource-level one, it does not merge. Name groups `<resource>:<read|write>`.
- Relations are IRIs by default. A relation is embedded as soon as one of its properties is in the read group; avoid
  circular embedding (a group scheme or `MaxDepth`), and prefer links with Vulcain over compound documents.
- `#[ApiProperty(readable: false, writable: false, description: '...', example: '...')]` shapes one property; `readableLink`
  and `writableLink` choose IRI or embedded.
- `framework.serializer: { enable_attributes: true }` is already on in a Symfony app; the bundle does the rest.
- Return the DTO, not the entity, when a field must not leak; groups are the lighter option for small differences.

## Errors

- `exception_to_status` maps a domain exception to a status (global, or per resource / operation — operation wins).
- An `#[ErrorResource]` class implementing `ProblemExceptionInterface` gives full control of the error body (type, title,
  detail, status); its `trace`, `file` and `line` are ignored by default.
- The error format follows the negotiated format: Hydra for JSON-LD, `application/problem+json` (RFC 7807) for
  `error_formats`, JSON:API errors for JSON:API. 5.0 casts the JSON:API error `status` to a string.
