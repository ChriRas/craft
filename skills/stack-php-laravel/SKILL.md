---
name: stack-php-laravel
description: CRAFT stack-pack for PHP + Laravel projects — language idioms, framework patterns, and Pest test patterns. Loaded by /craft:execute, /craft:test, and /craft:refactor when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — PHP / Laravel

The code-near personality layer for a PHP 8.4 / 8.5 + Laravel 12 project, using
Filament for admin UI and Pest for tests. It is loaded on top of the Senior-Developer baseline by
`/craft:execute`, `/craft:test`, and `/craft:refactor` when `rules.md` declares it in
its `## Personality` block. Project-specific conventions — domain rules, exact tool
commands, the database in use — live in the project's own `rules.md`, not here.

## Stack

- **Language** — PHP 8.4 / 8.5: `declare(strict_types=1)`, readonly classes, backed
  enums, full type hints, constructor property promotion. PHP 8.5 idioms (pipe
  operator, clone-with, `#[\NoDiscard]`) are in `references/code-quality-standards.md`.
- **Framework** — Laravel 12; Filament for admin panels where the project uses it.
- **Tests** — Pest. A project on plain PHPUnit overrides this in its `rules.md`.

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
