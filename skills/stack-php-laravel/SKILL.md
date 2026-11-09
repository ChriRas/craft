---
name: stack-php-laravel
description: CRAFT stack-pack for PHP + Laravel projects — language idioms, framework patterns, and Pest test patterns. Loaded by /craft:build, /craft:test, and /craft:refactor when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — PHP / Laravel

The code-near personality layer for a PHP 8.4 / 8.5 + Laravel 12 project, using
Filament for admin UI and Pest for tests. It is loaded on top of the Senior-Developer baseline by
`/craft:build`, `/craft:test`, and `/craft:refactor` when `rules.md` declares it in
its `## Personality` block. Project-specific conventions — domain rules, exact tool
commands, the database in use — live in the project's own `rules.md`, not here.

## Stack

- **Language** — PHP 8.4 / 8.5: `declare(strict_types=1)`, readonly classes, backed
  enums, full type hints, constructor property promotion. PHP 8.5 idioms (pipe
  operator, clone-with, `#[\NoDiscard]`) are in `references/code-quality-standards.md`.
- **Framework** — Laravel 12; Filament for admin panels where the project uses it.
- **Tests** — Pest (a project on PHPUnit: see `## Existing Projects`).

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `composer.json` first and follow what it declares:

- **PHPUnit instead of Pest** — `phpunit/phpunit` in `require-dev` and no `pestphp/pest`; tests are PHPUnit classes
  (Feature tests extend `Tests\TestCase`, Unit tests usually `PHPUnit\Framework\TestCase` — follow the neighbouring
  test). Write new tests as PHPUnit test classes and run them with `php artisan test` or
  `vendor/bin/phpunit` — never add Pest alongside.
- **No Filament** — no `filament/filament` in `require`. The UI layer is whatever the project uses (controllers with
  Blade, Livewire, Inertia); never introduce a Filament panel to host new UI.
- **An older Laravel major** — the `laravel/framework` constraint in `composer.json` names it. Follow the structure the
  project already has (its middleware and exception handling stay where they are) instead of the current skeleton's,
  and use only APIs that major ships.
- **An older PHP** — the `require.php` constraint sets the floor. Use no language feature above it (the PHP 8.5 idioms
  in `references/code-quality-standards.md` only where the constraint's floor is 8.5 or higher, e.g. `^8.5`).

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — PHP 8.4 language idioms and the
  code-quality checklist.
- `references/framework-patterns.md` — Laravel and Filament structural patterns.
- `references/test-patterns.md` — Pest unit and feature test patterns.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Migrations — schema before code.
2. Models — relationships, casts, scopes.
3. Enums — backed enums for domain types.
4. Services — business logic.
5. Jobs — thin wrappers around services.
6. Filament resources / controllers — the UI layer.
7. Tests — alongside each layer or right after.

## Anti-Patterns

- Business logic in models, controllers, or Filament resources instead of services.
- Missing `declare(strict_types=1)`, or partial type hints.
- Multi-table writes outside a database transaction.
- N+1 queries — eager loading forgotten.
- Magic strings where a backed enum belongs.

## Sources

> As of: 2026-05-20 · Basis: extraction

- Extracted from a validated production project's developer skill (`research/real_live_projekt/.claude/skills/developer/`,
  D27) — not re-verified against current Laravel, Filament and Pest releases. Laravel 13 has been released since
  (`laravel/framework` v13.40.0 on Packagist, checked 2026-11-09); this pack still describes Laravel 12.
