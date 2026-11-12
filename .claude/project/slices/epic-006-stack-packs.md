# Epic 006 — Stack-Packs

> Completed: 2026-11-12 (started 2026-11-09)
> Slices: 10/10 landed · slice-083 and slice-092 sequentially on main; slice-084 to slice-091 by autopilot runs on epic-006-stack-packs, merged into main on the human's yes
> Merge: 903aac8 (Merge epic-006: Stack-Packs)

## Vision

CRAFT ships exactly one stack-pack (`stack-php-laravel`), so every project outside Laravel runs its code-near phases on
the Senior-Developer baseline alone, and `/craft:onboard` proposes pack names (`stack-php`, `stack-python`, `stack-ts`)
that do not exist. This epic adds eight packs built like `stack-php-laravel`: `stack-php` (plain PHP, no framework),
`stack-php-symfony`, `stack-php-api-platform`, `stack-php-shopware6`, `stack-php-shopware5`, `stack-python`, `stack-ts`
(plain TypeScript on Node, Vitest) and `stack-bash` (bash ≥ 5, ShellCheck, bats-core; POSIX sh only as a section).
When the epic is done, onboarding a Shopware, Symfony, API Platform, plain-PHP, Python, TypeScript or Bash project
detects the right pack, and `/craft:build`, `/craft:test`, `/craft:refactor` and `/craft:review` load that stack's
idioms. The content comes from research only — official documentation, with every version and tool claim verified
against current sources and dated — and the user reviews each pack before it lands. Out of scope: frontend-framework
packs (React, Vue, Next), packs composed from each other (D27 stays monolithic), and any change to how packs are
resolved or loaded.

## Slices (10/10)

- [slice-083 — pack-contract](./slice-083-pack-contract.md) — the stack-pack contract, checked by `scripts/test-stack-packs.sh`, and `/craft:onboard`'s detection table in precedence order
- [slice-092 — pack-existing-projects](./slice-092-pack-existing-projects.md) — the required `## Existing Projects` section; the baseline states once that a project's toolchain wins over a pack's default
- [slice-084 — stack-php](./slice-084-stack-php.md) — plain PHP 8.2–8.5 without a framework: Composer, PHPUnit 13, PHPStan, PER-CS
- [slice-085 — stack-php-symfony](./slice-085-stack-php-symfony.md) — Symfony 8.1 with the 7.4 LTS differences: DI, Doctrine, Twig + Forms, tests
- [slice-086 — stack-php-api-platform](./slice-086-stack-php-api-platform.md) — API Platform on Symfony: resources, state providers / processors, filters, formats, `ApiTestCase`
- [slice-087 — stack-php-shopware6](./slice-087-stack-php-shopware6.md) — Shopware 6.7: plugins, apps, DAL, Storefront, Administration, tests
- [slice-088 — stack-php-shopware5](./slice-088-stack-php-shopware5.md) — maintenance pack for legacy Shopware 5.7 (PHP 7.4–8.2), its end-of-life status stated
- [slice-089 — stack-python](./slice-089-stack-python.md) — plain Python with uv, Ruff, mypy strict and pytest
- [slice-090 — stack-ts](./slice-090-stack-ts.md) — plain TypeScript on Node (TypeScript 7, Vitest), library / CLI / service
- [slice-091 — stack-bash](./slice-091-stack-bash.md) — Bash 5.3 with ShellCheck, shfmt and bats-core; POSIX sh and macOS bash 3.2 portability

## Epic Decisions

- **Pack list and names** (2026-11-09) — eight packs: `stack-php`, `stack-php-symfony`, `stack-php-api-platform`,
  `stack-php-shopware6`, `stack-php-shopware5`, `stack-python`, `stack-ts`, `stack-bash`. Shell is `stack-bash` (bash ≥ 5,
  ShellCheck, bats-core), not a POSIX-first `stack-shell`; POSIX sh is a section of it. TypeScript is plain TS only —
  frontend packs (React, Vue, Next) are out of scope and would be their own packs later.
- **Content source: research only** (2026-11-09) — no extraction from the user's own projects (unlike
  `stack-php-laravel`). Every version, tool and API claim is verified against current primary sources and the pack
  records when it was verified, so a later reader can tell its age. The user reviews each pack's content before it lands.
- **Monolithic packs stay (D27)** (2026-11-09) — a project declares one pack, so Symfony knowledge is duplicated into
  `stack-php-api-platform` and `stack-php-shopware6` on purpose; no composition mechanism is added.
- **One epic with nine entries, above `/craft:epic`'s 2–7 guideline** (2026-11-09) — the guideline is prose-only; one
  entry per pack keeps each pack reviewable on its own. (A tenth entry, `pack-existing-projects`, was added later.)
- **Contract first, each pack wires itself, sequential execution** (2026-11-09) — a trailing wiring slice was rejected,
  since `scripts/test-docs-site.sh` compares the skills count with the docs badge. `pack-contract` lands first; each pack
  slice carries its docs count/text, README line and CHANGELOG line. Amended by slice-083: the whole detection table is
  written by `pack-contract`, because precedence is a property of the whole table. All pack slices touch the same lines,
  so the epic runs sequentially.
- **How to run it sequentially** (2026-11-09) — without a profile `Epic Mode` defaults to `parallel`;
  `.claude/project/craft-profile.md` was added as the `balanced` preset with only `Epic Mode → Default: sequential`
  changed (commit `90a92c5`).
- **Packs respect a project's existing toolchain** (2026-11-09) — raised for `stack-python` (pip / venv next to the uv
  default): a pack that only teaches its modern default would lead the agent to migrate tooling as a side effect. It
  became part of the contract through `pack-existing-projects` (slice-092).

## Open follow-ups

- none at epic level — each slice's own follow-ups stay in its archive (slice-091: bats-core and shfmt sections rest
  on documentation, not on a run).
