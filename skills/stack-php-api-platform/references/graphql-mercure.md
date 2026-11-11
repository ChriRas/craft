# API Platform — GraphQL and Mercure

Two optional layers on top of the REST resources: a GraphQL endpoint built from the same resource metadata, and real-time
pushes through the Mercure protocol. Written for API Platform 5.0.

## GraphQL

GraphQL is **not installed by default**. It reuses the resource classes, providers, processors, filters, pagination and
security; nothing is described twice.

```console
composer require api-platform/graphql
```

The package needs `webonyx/graphql-php` (^15.0, current 15.39). The endpoint is `/graphql` below the route prefix — with the
Flex recipe's `/api` prefix that is `/api/graphql`; GraphiQL (the default IDE) is at `graphql/graphiql`. Move the endpoint
by declaring the route with `controller: api_platform.graphql.action.entrypoint`.

- **Operations** — a resource gets `Query`, `QueryCollection`, `Mutation(name: 'create')`, `Mutation(name: 'update')` and
  `DeleteMutation(name: 'delete')`. Declare `graphQlOperations: [...]` (classes in `ApiPlatform\Metadata\GraphQl\`) to
  narrow them: once you declare one, the others are gone.
- **REST and GraphQL are configured separately.** `security`, `securityMessage`, filters and pagination on the REST
  operations do **not** carry over: repeat them on each GraphQL operation (`new Mutation(name: 'create', security:
  "is_granted('ROLE_ADMIN')")`). Forgetting this leaves a mutation open that the REST route guards — check the security
  of every GraphQL operation in a review.
- **Update and delete take the IRI** as `id`. `clientMutationId` is supported (Relay input objects).
- **Filters** become arguments of the collection query (`QueryCollection(filters: [...])` decouples them from REST).
- **Pagination** is cursor-based by default (Relay connections: `first` / `after`, `last` / `before`, `edges`, `node`,
  `pageInfo { endCursor hasNextPage }`, `totalCount`). `QueryCollection(paginationType: 'page')` switches an operation to
  page-based pagination. The usual `paginationEnabled`, `paginationItemsPerPage` and `paginationMaximumItemsPerPage` apply.
- **Custom queries and mutations** — implement a resolver (`QueryItemResolverInterface` / `QueryCollectionResolverInterface`,
  autoconfigured; otherwise tag `api_platform.graphql.query_resolver`) and name it on `new Query(name: 'retrievedBook',
  resolver: BookResolver::class)`. API Platform's own resolvers still run around yours. Keep business rules in a processor,
  shared with REST, rather than in a resolver.
- **Limits** — `api_platform.graphql.max_query_depth` (default 20) and `max_query_complexity` (default 500) bound a client's
  query; keep both set. Lower them if the schema has deep relations.
- **Introspection** — the docs advise turning it off outside development: `api_platform: {graphql: {introspection:
  false}}`. The GraphiQL IDE switches off with `graphql: {graphiql: {enabled: false}}`. The GraphQL Playground and its
  `graphql_playground` option are gone in 5.0 (the config key was removed; the GraphQL page still describes it).
- **Events and custom Symfony controllers are not supported** under GraphQL; use providers and processors (they run for
  both). The kernel-listener extension points do not.
- **N+1** — the Doctrine eager loading of `query-patterns.md` applies to the collection query too; nested connections add
  joins, so serialization groups and `max_joins` matter as much as in REST.
- **Subscriptions** use Mercure: a resource with `mercure: true`, the `update` mutation and a `Subscription` operation lets
  a client subscribe to updates of a resource.
- 5.0 replaced the legacy PropertyInfo type in a custom `TypeConverterInterface`: implement `convertPhpType()` with a
  `Symfony\Component\TypeInfo\Type`.

```php
#[ApiResource(
    mercure: true,
    graphQlOperations: [
        new Query(security: "is_granted('ROLE_USER')"),
        new QueryCollection(security: "is_granted('ROLE_USER')", paginationType: 'page'),
        new Mutation(name: 'update', security: "is_granted('BOOK_EDIT', object)"),
        new Subscription(),
    ],
)]
```

A GraphQL test posts `{"query": "{ books { edges { node { id } } totalCount } }"}` to `/api/graphql` with the test client
(`'json' => [...]` plus `'headers' => ['Content-Type' => 'application/json']`; a probe with that header answered 200) and
asserts on `data` and `errors` (`test-patterns.md`).

## Mercure

Mercure pushes a changed resource to every subscribed client over Server-Sent Events, through a hub. API Platform
detects changes to Doctrine entities and publishes the new representation; a deleted resource is published as its IRI
alone.

```console
composer require symfony/mercure-bundle
```

(`symfony/mercure-bundle` is 0.7, `symfony/mercure` 0.10, both for PHP 8.2 and up.) A hub (the Mercure.rocks binary, the
Caddy module of the Docker setup, or a managed hub) runs separately; the Flex recipe adds `MERCURE_URL` (where the app
publishes), `MERCURE_PUBLIC_URL` (where browsers subscribe), `MERCURE_JWT_SECRET` and `MERCURE_JWT_ISSUER` to `.env`; the
secret is a placeholder to replace and keep out of the repository. **Mercure 1.0** changed subscription: a subscriber uses `match=` / `match_urlpattern=`
instead of `topic=`, and a hub on 1.0 needs `protocol_version: '1.0'` on the **MercureBundle** side (API Platform speaks 0.x
by default). Ask who runs the hub which version it speaks.

```php
#[ApiResource(mercure: true)]                                    // publish on create, update, delete
#[ApiResource(mercure: ['private' => true])]                     // private updates: subscribers need a JWT
#[ApiResource(mercure: 'object.mercureOptions')]                 // options from an expression
```

- **Topics** — an update is published on the resource's absolute IRI (its JSON-LD `@id`), so a client subscribes to the `@id`
  it already has. The response of every Mercure-enabled resource carries a `Link: <hub>; rel="mercure"` header for hub
  discovery. `mercure.hub_url` sets the URL in that header.
- **Options** — `private`, `topics`, `data`, `id`, `type`, `retry` and `normalization_context` (the serialization of the
  pushed document). `include_type` always adds `@type`, even in delete updates.
- **Private updates** — `private: true` requires the subscriber's JWT to contain a matching target selector. To restrict
  *which* resources a subscriber sees, add an alternate topic with the `iri()` and `escape()` expression functions (for
  instance the owner's IRI) and put the matching topic selector in the subscriber's token. A subscriber must never get
  another user's data because the topic was guessable: use private updates for anything not public.
- **Payload** — push what the client needs: `normalization_context: {groups: ['book:read']}` keeps internal fields out.
- **Resources that are not Doctrine entities** publish through your own code: inject `Symfony\Component\Mercure\HubInterface`
  in a processor and publish an `Update` after the write.
- **Client** — fetch the resource, read the hub from the `Link` header, open an `EventSource` on the hub URL with the
  resource `@id` as topic (`match` on a 1.0 hub); the browser reconnects and resends `Last-Event-ID` itself.
- **Scale and cost** — a busy resource published on every write floods the hub; publish a small payload, or only the IRI,
  and let the client refetch.

### Testing Mercure

With the test client (`api-platform/test`) assertions exist for published updates: `getMercureMessages()`,
`getMercureMessage($index)` and `assertMercureUpdateMatchesJsonSchema($update, ['https://example.com/books/1'], $schema,
private: true)`. Assert that a write publishes one update, that it is private when it should be, and that the topic is the
IRI. The hub itself is not part of the test (`test-patterns.md`).
