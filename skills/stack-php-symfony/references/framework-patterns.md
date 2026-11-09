# Symfony — Framework Patterns

The patterns below are written for Symfony 8.1; where the 7.4 LTS differs it is marked **7.4**. Project layout follows the
framework's default and its Best Practices article.

## Layout

```
config/{packages/, routes/, services.yaml}   bin/console   migrations/   public/index.php
src/{Kernel.php, Controller/, Entity/, Repository/, Form/, Security/, Twig/, Message/, MessageHandler/, EventListener/}
templates/   tests/   translations/   var/   .env  .env.test  (.env.local is never committed)
```

Application code lives under `App\` in `src/` (no bundle for your own code); a feature folder
(`src/Invoice/{Controller,Entity,...}`) is fine once `src/` outgrows the layer folders — keep one style per project.

## Dependency injection

`config/services.yaml` ships with `_defaults: {autowire: true, autoconfigure: true}` and `App\: {resource: '../src/'}`, so
every class in `src/` is a service and most need no configuration. Autoconfiguration tags commands, listeners, voters, form
types, Twig extensions and message handlers from their interface or attribute.

```php
final readonly class Mailer
{
    public function __construct(
        private TransportInterface $transport,
        #[Autowire(param: 'app.sender')] private string $sender,
        #[Autowire(env: 'MAILER_DSN')] private string $dsn,
        #[Autowire(service: 'monolog.logger.mail')] private LoggerInterface $logger,
    ) {}
}
```

- **Type-hint the class or interface** — one implementation of an interface autowires on its own; with several, mark the
  default with `#[AsAlias]` on that class and pick another with `#[Target('name')]` on the argument.
- **`#[Autowire]`** injects what a type cannot name: a parameter, an env var, an expression or a specific service.
  `#[AutowireIterator('app.tag')]` / `#[AutowireLocator('app.tag')]` inject tagged services (**7.4**: `#[TaggedIterator]`
  and `#[TaggedLocator]` still work; 8.0 removed them).
- **Parameters or env vars** — infrastructure that differs per machine (DSNs, hosts) is an env var in `.env`, secrets go
  through `bin/console secrets:set`; application behaviour (a sender address, a feature toggle) is a `parameters:` entry
  prefixed `app.`, and a value that rarely changes is a class constant. `.env.local` never enters the repository.
- **Services are private**; do not add `public: true` to read one from a test (use the test container, `test-patterns.md`).
- **Per-environment config** — `when@test:` / `when@prod:` blocks inside a package file, or `config/packages/<env>/`.
- **Events** — `#[AsEventListener]` on a class or method; a listener does one small thing and delegates to a service.
- **Console commands** — `#[AsCommand(name: 'app:import', description: '...')]` on a class with `__invoke(): int` (the form
  both the 8.1 and the 7.4 docs show); extending `Command` with `execute()` is still valid. It delegates to a service.
- **Configuration format** — YAML is what recipes write; PHP config is the typed alternative (arrays returned from
  `App::config([...])`); XML is gone in 8.0. Pick the project's format and stay in it.

## Controllers and routing

Attribute routing is on by default with Flex (without Flex: `config/routes.yaml` with `resource: routing.controllers`).

```php
#[Route('/invoices')]
final class InvoiceController extends AbstractController
{
    #[Route('/{id}', name: 'invoice_show', requirements: ['id' => '\d+'], methods: ['GET'])]
    public function show(Invoice $invoice): Response
    {
        return $this->render('invoice/show.html.twig', ['invoice' => $invoice]);
    }

    #[Route('', name: 'invoice_create', methods: ['POST'])]
    #[IsGranted('ROLE_ACCOUNTANT')]
    public function create(
        #[MapRequestPayload] CreateInvoice $command,
        InvoiceService $invoices,
    ): JsonResponse {
        $invoice = $invoices->create($command);

        return $this->json(['id' => $invoice->getId()], Response::HTTP_CREATED);
    }
}
```

- A controller extends `AbstractController` (shortcuts for `render`, `redirectToRoute`, `json`, `createForm`,
  `denyAccessUnlessGranted`) and holds a few lines of glue. Services come in as action arguments or the constructor, not
  from `$this->container`.
- **Argument resolvers** map input to typed arguments: `#[MapRequestPayload]` (body to a validated DTO),
  `#[MapQueryString]` (query string to a DTO), `#[MapQueryParameter]` (one query parameter), `#[MapUploadedFile]`,
  `#[CurrentUser]`, and the entity value resolver for Doctrine entities. A failed validation answers 422 for
  `#[MapRequestPayload]` and 404 for `#[MapQueryString]` by default (`validationFailedStatusCode:` changes it), and an
  unaccepted payload format 415 — no code in the action. 8.1 adds uploaded files and dynamic validation groups to the payload mapper, a
  `#[Serialize]` attribute that serializes the returned object, and a `#[RateLimit]` attribute.
- **Entity arguments** — `{id}` finds by primary key; `{slug:product}` (since 7.1) maps another route parameter to the
  argument and queries by that property; `#[MapEntity(expr: 'repository.find(product_id)')]` for the rest. Map explicitly;
  `doctrine.orm.controller_resolver.auto_mapping` is documented as no longer recommended and 8.0 removed an auto-mapping
  mode. A nullable argument (`?Product`) skips the automatic 404.
- **Routes** — a name per route, an explicit `methods:`, requirements for typed parameters (`requirements: ['id' => '\d+']`),
  hard-coded URLs in tests. Generate URLs with `generateUrl()` / `path()`, never by string concatenation.
- **Responses** — render a template, return `$this->json()`, `RedirectResponse` after a POST (post/redirect/get). A form
  or API error is a response status, not an exception swallowed in the action.
- **Caching and rate limits** — `#[Cache]` for HTTP caching, the RateLimiter component for throttling; not hand-rolled.
- **Business logic** goes in a service (a use-case class); the controller maps in and out.

## Messenger

Use Messenger when work should happen after the response, off the web process, or behind a retry.

```php
#[AsMessage('async')]
final readonly class SendInvoice
{
    public function __construct(public int $invoiceId) {}
}

#[AsMessageHandler]
final readonly class SendInvoiceHandler
{
    public function __construct(private InvoiceRepository $invoices, private Mailer $mailer) {}

    public function __invoke(SendInvoice $message): void
    {
        $invoice = $this->invoices->find($message->invoiceId) ?? throw new UnrecoverableMessageHandlingException('gone');
        $this->mailer->send($invoice);
    }
}
```

- A message is a small immutable class carrying ids and scalars — never an entity (the handler loads a fresh one) and no
  service. A handler is a class with `#[AsMessageHandler]` and `__invoke()` (or the attribute on several methods).
- **Routing** — `#[AsMessage('async')]` on the message (since 7.2; **before 7.2** `framework.messenger.routing` in YAML).
  Without a route a message is handled synchronously. Transports come from env DSNs (`MESSENGER_TRANSPORT_DSN`: AMQP,
  `doctrine://default`, Redis); set `failure_transport` and a `retry_strategy`.
- **Workers** run `php bin/console messenger:consume async` under Supervisor or systemd with `--limit`, `--memory-limit`
  and `--time-limit` so the process restarts; restart workers on deploy (`messenger:stop-workers`).
- **Failures** — an exception retries the message (default `max_retries`: 3); `UnrecoverableMessageHandlingException` never
  retries, `RecoverableMessageHandlingException` always does. Inspect with `messenger:failed:show` and `messenger:failed:retry`.
- **Idempotent handlers** — delivery is at least once. A repeated message must not charge twice or mail twice: set absolute
  values rather than increments, and carry a stable idempotency key derived from the business event.
- **Transactions** — the `doctrine_transaction` middleware wraps a handler in a transaction; to dispatch a follow-up
  message only after the handler succeeded, add a `DispatchAfterCurrentBusStamp`.
- **Buses** — one `default.bus` is enough; add a command bus and an event bus (`framework.messenger.buses`) when the
  project separates them.
- **Tests** — in `when@test` swap the transport to `in-memory://` and assert on `getSent()` (`test-patterns.md`).

## Security

SecurityBundle is configured in `config/packages/security.yaml`. Generate the user with `make:user` and a login with
`make:security:form-login`; then:

```yaml
security:
    password_hashers:
        Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface: 'auto'
    providers:
        app_user_provider:
            entity: { class: App\Entity\User, property: email }
    firewalls:
        dev: { pattern: '^/(_profiler|_wdt|assets)/', security: false }
        main:
            lazy: true
            provider: app_user_provider
            form_login: { login_path: app_login, check_path: app_login, enable_csrf: true }
            login_throttling: ~
            logout: { path: app_logout }
    access_control:
        - { path: ^/login, roles: PUBLIC_ACCESS }
        - { path: ^/admin, roles: ROLE_ADMIN }
```

- **One firewall** unless there are two genuinely different authentication systems (a form login and a token API). Keep
  `lazy: true`. Enable `login_throttling` (default five attempts per minute) on every login.
- **Passwords** are hashed with `auto`; the user repository implements `PasswordUpgraderInterface` so hashes migrate. In
  `when@test` lower the hasher cost (the recipe does) so tests stay fast.
- **Authorization** — `access_control` for URL prefixes (the first match wins), `#[IsGranted]` or
  `denyAccessUnlessGranted()` for an action, and a **voter** (`extends Voter`: `supports()`, `voteOnAttribute()`) for any
  rule about a specific object ("only the author edits the post"). A voter beats a long expression in an attribute.
- **Current user** — `#[CurrentUser] ?User $user` in an action, `Security::getUser()` in a service; never trust a user id
  from the request. Hide only what the voter denies, and still check on the server.
- **User class** — implements `UserInterface` (`getUserIdentifier()`, `getRoles()`); `eraseCredentials()` is
  required up to 7.4 (deprecated since 7.3: keep an empty `#[\Deprecated]` one there) and removed from the interface in 8.0 — drop it on 8.x.
- **APIs** — `json_login` or `access_token` authenticators on a stateless firewall; the failure answers 401 JSON, not a redirect.
- **CSRF** — enable `enable_csrf` on form login, keep `csrf_protection` on forms, use `#[IsCsrfTokenValid]` or
  `isCsrfTokenValid()` for state-changing non-form requests (a logout link, a delete button).

## Assets and other defaults

- **AssetMapper** is the default asset pipeline (no bundler): `importmap:require`, `asset('...')` in Twig,
  `asset-map:compile` on deploy; Webpack Encore is the project's choice when it already uses it.
- **Logging** through `LoggerInterface` and Monolog channels; **mail** through the Mailer component; **time** through the
  Clock; **HTTP calls** through `HttpClientInterface` (never `curl_*` or `file_get_contents` on a URL).
- **Caching** through `CacheInterface` (`$cache->get($key, fn (ItemInterface $item) => ...)`), with an expiry on every item.
- **Translations** in `translations/` as XLIFF with keys that name the purpose, not the English text.
