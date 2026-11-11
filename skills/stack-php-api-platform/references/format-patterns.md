# API Platform — Format Patterns

The formats an API Platform API speaks and documents itself in: JSON-LD / Hydra, OpenAPI, JSON:API, HAL, JSON Merge
Patch, and the error formats. Written for API Platform 5.0; 4.4 differences are marked **4.4**.

## Content negotiation

The response format is picked from the request's `Accept` header or a URL extension (`/books.jsonld`). If the client
names none, the **first** format in `formats` wins. An `Accept` for a format that is not enabled answers **406**; a request
body in a `Content-Type` that is not enabled answers **415**. Only **JSON-LD** is enabled by default.

| Format | `formats` key | MIME type | Note |
|---|---|---|---|
| JSON-LD (Hydra) | `jsonld` | `application/ld+json` | default; hypermedia, linked data |
| JSON:API | `jsonapi` | `application/vnd.api+json` | needs `composer require api-platform/json-api`; backward-compatibility guaranteed |
| HAL | `jsonhal` | `application/hal+json` | needs `composer require api-platform/hal`; backward-compatibility guaranteed |
| JSON, XML, CSV, YAML, HTML | `json`, `xml`, `csv`, `yaml`, `html` | `application/json`, `application/xml`, `text/csv`, … | no compatibility promise; raw JSON and XML are discouraged — use JSON-LD |

```yaml
# config/packages/api_platform.yaml
api_platform:
    formats:
        jsonld: ['application/ld+json']
        jsonapi: ['application/vnd.api+json']
    patch_formats:
        json: ['application/merge-patch+json']
    docs_formats:
        jsonld: ['application/ld+json']
        jsonopenapi: ['application/vnd.openapi+json']
        html: ['text/html']
    error_formats:
        jsonld: ['application/ld+json']
        jsonproblem: ['application/problem+json']
```

- **JSON:API and HAL are separate packages** (`composer require api` does not install them): listing the format without
  its package fails the container build with a `LogicException` naming the package.
- **Offer as few formats as the clients need.** Each format is a contract that tests, docs and clients must keep.
- Per resource or operation: `formats: ['jsonld', 'csv' => ['text/csv']]`, or `inputFormats` / `outputFormats`; the
  attribute **replaces** the global list for that resource.
- `docs_formats` (the API description), `patch_formats` and `error_formats` are separate lists with their own defaults.
  Raw `json` is not on unless you list it.
- A custom format needs an encoder (and optionally a normalizer) registered with the Symfony Serializer.
- **`Content-Type` charset (4.4)** — a JSON-based response (`application/ld+json`, `application/json`,
  `application/hal+json`, `application/vnd.api+json`, `application/problem+json`) is sent **without** `; charset=utf-8`;
  only `text/*` and `application/xml` carry it. A test asserting the old header fails on 4.4 and 5.0 (the docs' test
  examples still show the charset).

## JSON-LD and Hydra

JSON-LD is the default: every resource carries `@context`, `@id` (its IRI) and `@type`; relations are IRIs; a collection
is a Hydra collection:

```json
{
    "@context": "/contexts/Book",
    "@id": "/books",
    "@type": "Collection",
    "member": [{"@id": "/books/1", "@type": "Book", "title": "Dune"}],
    "totalItems": 50,
    "view": {"@id": "/books?page=1", "@type": "PartialCollectionView", "first": "/books?page=1", "last": "/books?page=2", "next": "/books?page=2"}
}
```

- The keys have **no `hydra:` prefix** (`member`, `totalItems`, `view`) since 4.0; `api_platform.serializer.hydra_prefix:
  true` brings the prefix back for a client that still reads it.
- Hydra describes the API too (a `docs_formats` entry, the entrypoint at the route prefix, an `IriTemplate` for filter
  parameters). Semantic types: `types: ['https://schema.org/Book']` on the resource, `types:` on an `#[ApiProperty]` (the
  external-vocabularies page). Since 4.3 a Hydra class `@id` is always `#ShortName`; configured types appear as
  `rdfs:subClassOf`.
- Responses carry `Allow` and `Accept-Post` headers (4.3); `Accept-Patch` lists the patch formats on items.
- **Errors** are resources: `@type` `Error` for a thrown exception, `ConstraintViolation` entries for validation (**5.0**:
  the `/contexts/ConstraintViolationList` context route is gone; a test or client hardcoding it breaks).
- A client that only wants JSON documents a smaller surface than the Hydra one; do not hand-parse `@id` strings when a
  property would do — expose the identifier as a field.

## OpenAPI

API Platform generates an OpenAPI description from the resource metadata — the same metadata that builds Hydra and the
JSON Schemas — served at `/docs.jsonopenapi` under the route prefix with `Content-Type: application/vnd.openapi+json` (ask for it with that
`Accept` header or the extension; YAML too with `symfony/yaml`). The documents target
**OpenAPI 3.2.0**; `?spec_version=3.0.0` or `bin/console api:openapi:export --spec-version=3.0.0` gives 3.0.0 for a tool that
cannot read 3.2.

- **Export** — `php bin/console api:openapi:export --output=openapi.json` (`--yaml`). Commit it or diff it in CI: a
  contract change then shows in review. `api:json-schema:generate 'App\ApiResource\Book'` prints one resource's schema.
- **UIs** — Swagger UI (default), ReDoc (`?ui=re_doc`) and Scalar (`?ui=scalar`) are served when `symfony/twig-bundle` is
  installed, from the HTML docs format. Turn off what production should not serve: `enable_swagger_ui`, `enable_re_doc`,
  `enable_scalar`, `enable_docs`, or `enable_swagger: false`. A UI under a Content Security Policy needs the nonce setup of
  the docs.
- **Info and security** — `api_platform.title` / `description` / `version`; `swagger.api_keys.JWT: {name: Authorization,
  type: header}` adds the Authorize button for a bearer token.
- **Shape it from the resource, not the generated file** — `description` and `example` on `#[ApiProperty]`, PHPDoc
  summaries, `openapi: new Model\Operation(summary: ..., description: ..., responses: [...])` on an operation,
  `openapi: false` to hide one, `openapi_definition_name` in a context to rename a schema.
- **Whole-document changes** — decorate `api_platform.openapi.factory` with `#[AsDecorator(decorates:
  'api_platform.openapi.factory')]` and implement `OpenApiFactoryInterface::__invoke(array $context = []): OpenApi`.
- Parameters declared with `QueryParameter` appear with their schema; a `SortFilter` publishes an `asc` / `desc` enum.
- Several documents from one API: tag operations with `OpenApiFactory::API_PLATFORM_TAG` in `extensionProperties`, then
  `/docs?filter_tags[]=customer` or `api:openapi:export --filter-tags=customer`.

## JSON:API

Enabled by adding `jsonapi: ['application/vnd.api+json']` to `formats`; the client sends `Accept` (and, for a body,
`Content-Type`) `application/vnd.api+json`. Objects have `data.id`, `data.type`, `attributes`, `relationships` and `links`.

- **5.0 changes `id`**: `api_platform.jsonapi.use_iri_as_id` now defaults to `false`, so `data.id` is the entity identifier
  (`"10"`) and the IRI moves to `data.links.self`. A project that upgrades and wants the old payload sets the option to
  `true` explicitly (4.4 deprecates leaving it unset). Composite identifiers are `field1=val1;field2=val2`.
- A resource that is referenced in relationships but has no `Get` item endpoint needs `#[NotExposed(uriTemplate:
  '/tags/{id}')]` so its IRI can be built; direct access answers 404.
- A client-supplied `data.id` on `POST` is rejected with 400 unless `jsonapi.allow_client_generated_id: true` (global) or
  the `ALLOW_CLIENT_GENERATED_ID` denormalization context on the `Post` (one operation).
- Error objects use a string `status` since 5.0.
- Sparse fieldsets are a parameter: `new QueryParameter(key: 'fields', filter: SparseFieldset::class)` from
  `ApiPlatform\JsonApi\Filter` (the docs show it in the Laravel setup; sorting there is the Eloquent `SortFilter`).

## HAL

`jsonhal: ['application/hal+json']` in `formats` switches a resource to HAL (`_links`, `_embedded`). It shares the
serializer groups with JSON-LD; the same relation rules (IRI or embedded) apply. Keep it only when a client needs it.

## JSON Merge Patch

`PATCH` applies **JSON Merge Patch (RFC 7396)**: the body is a partial document and the request's `Content-Type` is
`application/merge-patch+json`; `null` removes a value. It is the default entry of `patch_formats`, so an item response
carries `Accept-Patch: application/merge-patch+json`. A `PATCH` sent with another `Content-Type` is a 415. With JSON:API
enabled, its own `PATCH` format is accepted as well.

- `PUT` replaces the whole item (and creates it with `allowCreate: true`); a client that sends partial data uses `PATCH`.
- Restrict formats on one operation when needed: `new Patch(inputFormats: ['json' => ['application/merge-patch+json']])`.
- Deserialization writes into the loaded object and validation sees the merged state, so a `PATCH` that touches one field
  still runs every constraint of the operation's validation groups.

## Choosing and testing formats

- Assert on the format a client really uses; one test per enabled format on a representative resource catches a group or
  normalizer mistake (`test-patterns.md`).
- A contract change is a changed `api:openapi:export` output, a changed JSON Schema (`assertMatchesResourceItemJsonSchema`),
  or a changed Hydra key — review all three when a resource's shape changes.
