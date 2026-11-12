# Shopware 6 — App Patterns

An app extends a shop without PHP running inside it: a `manifest.xml` declares what the app adds, an optional **app server**
(a service of your own, in any language) talks to the shop over signed HTTP, and **app scripts** (sandboxed Twig) run in the
shop. Plugins are not compatible with Shopware's cloud stores; an app is how those are extended. Choose an app when the
logic can live behind an HTTP boundary; choose a plugin when it must run in the shop's process (own DAL entities, Store API
routes, cart processors, service decoration).

## Layout and manifest

```text
custom/apps/MyExampleApp/               # the folder name must equal <meta><name>
├── manifest.xml
├── Resources/{config/config.xml,config/plugin.png,scripts/<hook>/*.twig,views/,theme.json,app/storefront/}
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/shopware/shopware/trunk/src/Core/Framework/App/Manifest/Schema/manifest-3.0.xsd">
    <meta>
        <name>MyExampleApp</name>
        <label>Example</label>
        <description>What the app does</description>
        <author>Your Company Ltd.</author>
        <copyright>(c) Your Company Ltd.</copyright>
        <version>1.0.0</version>
        <icon>Resources/config/plugin.png</icon>
        <license>MIT</license>
    </meta>
    <setup>
        <registrationUrl>https://app.example.com/app/register</registrationUrl>
    </setup>
    <permissions>
        <read>product</read>
        <crud>swag_example</crud>
    </permissions>
    <webhooks>
        <webhook name="product-changed" url="https://app.example.com/hook/product" event="product.written"/>
    </webhooks>
</manifest>
```

- `<author>` and `<copyright>` are required — `app:refresh` fails without them. Every section (`setup`, `permissions`,
  `webhooks`, `admin`, `storefront`, `custom-fields`, `cookies`, `payments`, `shipping-methods`, `tax`, `rule-conditions`,
  `allowed-hosts`, `requirements`) is optional; declare only what the app uses.
- `<crud>` is shorthand for read + create + update + delete of an entity and exists since 6.7.3.0; for older shops list
  `<read>`, `<create>`, `<update>`, `<delete>` separately. Ask for the least permission; the app gets exactly these on the
  Admin API.
- `<allowed-hosts>` lists every external host the app's scripts or shop-side calls may reach (since 6.4.12.0).
- `<requirements>` (since 6.7.10.0) declares preconditions such as `public-access` (the shop is reachable over HTTPS from the
  internet, which webhooks and server-to-server calls need).
- Webhook names are unique per app; a webhook posts JSON `{data: {payload: [...], event}, source: {url, appVersion, shopId, eventId}, timestamp}`.
  Payload and event data depend on the event; `product.written` carries ids and `updatedFields`, not the product.
- Install and manage: `bin/console app:refresh` (reads `custom/apps`, validates), `app:install --activate MyExampleApp`
  (by technical name, not by path), `app:list`, `app:validate`, `app:activate`, `app:uninstall`; then `cache:clear`.
  `--no-validate` only while debugging.

## Registration and signing

A shop with an app server runs a handshake on install (the **setup**), all within a 5-second timeout:

1. Shopware sends `GET <registrationUrl>?shop-id=…&shop-url=…&timestamp=…` with the header `shopware-app-signature`
   (HMAC-SHA256 of the query string with the **app secret**; the Shopware Account holds the secret for Store apps, a private
   app sets `<secret>` in the manifest for local development only — a hard-coded secret cannot be uploaded to the Store).
2. The app verifies the signature, answers with `proof` = HMAC-SHA256 of `shop-id + shop-url + app name` with the app secret,
   a per-shop `secret` (64 to 255 characters, random) and a `confirmation_url`. On refusal it answers `{"error": "…"}`.
3. Shopware posts `apiKey`, `secretKey`, `shopUrl`, `shopId` to the confirmation URL; the app stores them per shop and uses
   them for the Admin API.

**Re-registration** of a known shop-id (secret rotation, a changed shop URL) also carries `shopware-shop-signature`, signed with the
shop secret you stored. Verify **both** signatures and switch to the new secret only after the confirmation — otherwise anyone with
the app secret and a shop-id could overwrite that shop's record. The SDK and the bundle do this check.

Every later request from the shop carries a signature made with the per-shop secret: verify it on **all** query parameters
(GET) or the **whole body** (POST) — never pick parameters, Shopware may add some without that being a breaking change —
using `hash_equals`. Sign your responses with the same secret. Do not re-parse and re-encode the query string before
hashing. Never log or commit either secret.

Use `shopware/app-php-sdk` (5.4.1 on 2026-09-21; `AppConfiguration`, `RegistrationService`, `ShopRepositoryInterface`,
`ContextResolver`, `ResponseSigner`) or, in a Symfony app server, `shopware/app-bundle` (6.1.0) which verifies and signs
for you and injects `WebhookAction` / action contexts into `#[AsController]` actions.

## App server design

- One record per shop (`shopId`, `shopUrl`, `shopSecret`, Admin API credentials); every handler resolves the shop first and
  rejects an unknown or mis-signed request before reading its payload.
- A webhook handler acknowledges fast and works asynchronously. `source.eventId` stays the same when a delivery is retried,
  so key idempotency on it.
- Tolerate unknown fields and new events in payloads.
- Lifecycle events reach the app server too (`app.installed`, `app.updated`, `app.deleted`, `app.activated`,
  `app.deactivated`): clean up a deleted shop's records on your side.
- Test the server with the SDK's signing helpers and a recorded request; the manifest and its handshake with a real shop
  through a tunnel (the shop must reach the app server).

## App scripts

Twig files in `Resources/scripts/<hook-name>/`, executed in a sandbox when the hook fires; they get the hook's data and
services (`services.repository`, `services.store`, `services.response`, …) and may `return` values. Several scripts per hook
run in file-name order; `hook.stopPropagation()` stops the rest. Shared code goes into Twig macros under
`Resources/scripts/include/`.

- **Interface hooks** (such as `store-api-*`) are implemented as Twig blocks (`cache_key`, `response`).
- **Custom endpoints**: a folder `api-<name>` serves `POST /api/script/<name>`, `store-api-<name>` serves
  `/store-api/script/<name>` (GET and POST), `storefront-<name>` the Storefront. Prefix the name with the app name to avoid
  collisions; the default response is `204`, a custom one is `{% set response = services.response.json({...}) %}{% do hook.setResponse(response) %}`.
- **Data loading** and **cart manipulation** hooks add data to Storefront pages or change the cart without a server.
- Scripts run sandboxed with only the services the hook provides; heavier work goes to the app server.

## Administration, Storefront, configuration

- **Admin UI**: modules are iframes. Declare them under `<admin><module name="…" source="https://…" parent="sw-marketing" position="50">`
  (with `<label>`); give `parent`, the "My apps" fallback is going away. Use the **Meteor Admin SDK**
  (`@shopware-ag/meteor-admin-sdk`, 6.17.0 on 2026-11-03) in the iframe to talk to the Administration (notifications, modals,
  action buttons, CMS elements, data); `@shopware-ag/meteor-component-library` (npm latest 5.10.0; 6.7.16.0 itself ships 5.8.0) gives the matching Vue components.
  The SDK is the cross-version extension point — it also works from plugins. An app's own build is decoupled from the
  Administration's Vue and Vite versions.
- **Storefront**: templates under `Resources/views/storefront/…` extend core blocks with `{% sw_extends %}`; there is no PHP.
  A `Resources/theme.json` turns the app into a **theme** (assigned per sales channel), without it the app's changes apply to
  every sales channel while active. A plugin theme's `Resources` folder can be copied to an app theme unchanged.
- **Configuration**: `Resources/config/config.xml` with the same schema as a plugin's; values are stored as
  `{AppName}.config.{field}` and read over `GET /api/_action/system-config?domain=AppName.config` or in Twig with
  `config('AppName.config.field')`. Mark a field `cache-relevant="true"` if it changes cached Storefront output — **since
  6.7.12.0 only**: older shops' config XSD rejects the attribute and the app fails to install.
- **Custom data**: custom fields and custom entities in the manifest or `Resources/` instead of migrations.
- **Checkout extensions** — payment, shipping methods, tax providers, document types and gateways — are manifest sections
  with a server-side endpoint each; read the manifest reference for the exact signatures before building one.

## Review checklist

- [ ] Folder name equals `<meta><name>`; `app:validate` is green; `author` and `copyright` are set.
- [ ] Minimal permissions; no secret in the manifest of a Store app.
- [ ] Every inbound request is verified over the full query or body; responses are signed.
- [ ] Webhook handlers are idempotent and tolerate new fields.
- [ ] Anything needing the shop's process (own DAL entity, Store API route, cart processor) is a plugin, not an app.
