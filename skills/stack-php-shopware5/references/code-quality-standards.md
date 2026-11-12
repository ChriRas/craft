# Shopware 5.7 — Code Quality Standards

Shopware 5 is end-of-life: nothing below can lean on an upstream fix. Quality here means small, conservative change plus the
checks that catch regressions early. Versions were verified on 2026-11-11 (see `SKILL.md` → `## Sources`).

## Which PHP the code must run on

- The 5.7.20 `composer.json` allows `~7.4.0 || ~8.0.0 || ~8.1.0 || ~8.2.0`; the unreleased head of the `5.7` branch adds
  `~8.3.0`. The floor was PHP 7.4 from 5.7.0, 8.0 came with 5.7.3, 8.1 with 5.7.7, 8.2 with 5.7.17.
- Support on 2026-11-11: 8.2 gets security fixes until 2026-12-31, 8.3 until 2027-12-31; 7.4 (last release 7.4.33), 8.0
  (8.0.30) and 8.1 (8.1.34, 2025-12-18) have none. A shop on 7.4 to 8.1 therefore runs PHP without fixes — say so in a
  slice that touches the server, and never raise the PHP version as a side effect.
- **The floor of new code is the oldest PHP the shop or the plugin declares** (read `composer.json`, `plugin.xml`,
  the server). Default to 7.4 syntax when nothing says otherwise:

| Syntax | Needs at least |
|---|---|
| typed properties, arrow functions, `??=`, array spread | 7.4 (the core's floor) |
| constructor promotion, `match`, named arguments, union types, nullsafe `?->`, attributes | 8.0 |
| enums, `readonly` properties, `never`, `new` in initializers, first-class callables | 8.1 |
| `readonly` classes, DNF types, `null` / `false` / `true` as standalone types | 8.2 |

- 5.7.20 ships `symfony/polyfill-php80`, `-php81` and `-php82` (not `-php83`), so *functions* up to PHP 8.2 such as
  `str_contains()` exist on 7.4 — newer ones (`json_validate()`, `mb_str_pad()`) and all syntax do not.
- PHP 8.1 deprecates passing `null` to a non-nullable parameter of a built-in function; 8.2 deprecates dynamic properties,
  `${var}` interpolation and `utf8_encode()`. Declare every property, cast at the boundary, run the suite with
  `error_reporting(-1)` as the core does.
- Doctrine models are mapped with annotations (`@ORM\Entity`, `@ORM\Table`, `@ORM\Column`): ORM 2.15 and
  `doctrine/annotations` 1.14 are pinned and the core registers an `AnnotationDriver`. Write new models the same way.

## Mandatory shape

```php
<?php

declare(strict_types=1);

namespace SwagOrderNote\Components;

use Doctrine\DBAL\Connection;

final class OrderNoteLoader
{
    private Connection $connection;

    public function __construct(Connection $connection)
    {
        $this->connection = $connection;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function loadByOrder(int $orderId): array
    {
        return $this->connection->fetchAllAssociative(
            'SELECT id, note FROM swag_order_note WHERE order_id = :orderId ORDER BY id',
            ['orderId' => $orderId]
        );
    }
}
```

- Full parameter, return and property types; `@return` generics where the native type is too wide.
- `strict_types` only in the plugin's own classes. Values handed to Shopware's untyped APIs (`Enlight_*`, `sBasket`,
  `sArticles`) are often strings: cast at that boundary instead of relying on a loose call.
- Constructor injection from `Resources/services.xml`; no `Shopware()` helper, no `$this->container->get()` deep inside
  business code. The container is read in the plugin base class, a controller or a subscriber's factory — nowhere else.
- Classes are `final` unless built for extension; an Enlight or core class you extend (`Shopware\Components\Plugin`,
  `Enlight_Controller_Action`, a REST resource) is the exception, and the file says why.
- One logic path per method; a subscriber or controller action delegates to a service, as the pack's
  `plugin-patterns.md` shows.
- The DBAL connection is the service `dbal_connection` (alias `Doctrine\DBAL\Connection`), DBAL 2.13: use
  `fetchAllAssociative()`, `fetchAssociative()`, `fetchOne()` as the 2.13 documentation does.

## Security without upstream patches

No vendor ships a fix for a core flaw any more (a commercial third party, SafeFive, offers security updates and a fork; that
is the shop owner's decision, not a slice's). What a slice must do on its own side:

- **Never edit the core** (`engine/Shopware`, `engine/Library`, `vendor/`, `themes/Frontend/Bare|Responsive`). The core
  docs say changes there are never required; a patched file is lost at the next update and invisible to review. Extend by
  events, decoration, hooks and theme inheritance.
- **SQL** — bind every value (`:name` or `?` with the parameters array); build a `LIKE` pattern in PHP and bind it; table
  and column names from a fixed whitelist, never from a request. The model layer (DQL, `QueryBuilder`) binds too.
- **Output** — the core sets no automatic Smarty escaping (no `escape_html`): use `|escapeHtml`, `|escapeHtmlAttr`, `|escapeJs`, `|escapeCss`,
  `|escapeUrl` (registered by the core) on every value that is not trusted HTML. Backend ExtJS grids and fields strip HTML
  by default since 5.2.21; `allowHtml: true` is a decision, not a convenience.
- **Requests** — validate at the controller boundary (type, range, length, whitelist), then pass typed values on.
  CSRF: the backend validates **every** request, the frontend only POST (a GET only when its controller opts in with
  `CSRFGetProtectionAware::getCSRFProtectedActions()`), so a state change goes through POST. Implement
  `CSRFWhitelistAware` only for an action that must be reachable without a token — a backend download by GET, an external
  callback such as a payment provider's POST that authenticates itself — and list just that action. The core's test
  config sets `csrfprotection.frontend` and `.backend` to `false`, so a test never shows a missing whitelist entry.
- **Smarty security** — templates run under a security policy with a PHP-function allow list
  (`template_security` in `engine/Shopware/Configs/Default.php`); do not widen it, and never put user input into
  `{eval}`, `{include file=$var}` or a template resource string.
- **Secrets and debug** — credentials only in `config.php` or the environment, out of Git. The development switches
  (`throwExceptions`, `forceCompile`, `Black-Hole` cache) never go to production.
- **REST API** — enabled per backend user (an API key), over HTTPS only: the docs warn that Basic authentication gives no
  confidentiality protection; Digest is the other supported mechanism.
- **Dependencies** — a plugin adds no Composer package that duplicates a pinned core one at another major
  (`symfony/*` 4.4, `doctrine/*`, `guzzlehttp/guzzle` ~7.7): the shop's autoloader holds one copy.
- **Advisories** — run `composer audit` in the shop project and report what it finds to the shop owner; the core pins
  Symfony 4.4 and other packages, and a slice does not bump a pinned core package.
- File permissions, PHP and MySQL versions, the web server and `var/` outside the web root are part of the same picture;
  name them in the slice if the work touches them, and leave them alone if it does not.

## Static analysis

The core (5.7.20) pins PHPStan 1.10.20 and runs it at level 8 with `phpVersion: 70400`, the Doctrine, Symfony and PHPUnit extensions and a baseline.
A plugin can use the same shape: PHPStan 2.x itself runs on PHP 7.4 and above and analyses for a lower target.

```neon
parameters:
    level: 6
    phpVersion: 70400
    paths:
        - .
    excludePaths:
        - Tests/*
includes:
    - phpstan-baseline.neon
```

- Start at the highest level the plugin passes; the baseline only shrinks. The shop's classes (`Shopware\…`, `Enlight_*`)
  need the shop's autoloader: point `bootstrapFiles` at the shop's `autoload.php`, and expect `Shopware()`-style calls
  and the dynamic Smarty and container access to need a documented ignore.
- `phpstan/phpstan-doctrine` (needs an `objectManagerLoader` that boots the shop), `phpstan/phpstan-phpunit`.
- Style: PSR-1/PSR-2 is the core's stated standard (`vendor/bin/php-cs-fixer fix -v` with the repository's `.php-cs-fixer.php`).
  A plugin keeps the style of its neighbours; a fixer run never rewrites files the slice does not touch.

## Checklist

- The code runs on the plugin's lowest declared PHP and raises no deprecation on the shop's PHP.
- No core file edited; no `@`, `eval`, `extract`, `global`, no `die`/`var_dump` left.
- Every value that reaches SQL is bound, every value that reaches a template is escaped.
- A log line goes through the plugin logger (`pluginlogger`, or `<plugin_name_snake_case>.logger` from 5.6.0) — not
  `error_log`, not a file you open.
- The plugin installs, updates and uninstalls on a copy of the shop (`sw:plugin:install`, `…:update`, `…:uninstall`) and
  `sw:cache:clear` ends clean.
