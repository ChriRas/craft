# Slice 086 — stack-php-api-platform

> Completed: 2026-11-11
> Commits: 15e6192..bc81bbc (on epic-006-stack-packs, no PR) · epic-006 entry `stack-php-api-platform`

## What

`skills/stack-php-api-platform/` is a new plugin-shipped stack-pack for API Platform on Symfony: a `SKILL.md` (Stack, six
`## Existing Projects` entries, Reference Files, Build Order, Anti-Patterns, dated Sources) and six references —
`code-quality-standards.md` (161 lines), `resource-patterns.md` (280; entity or DTO with the criterion, state providers
and processors, operations, validation, security), `query-patterns.md` (159; filters, collection restriction,
pagination), `format-patterns.md` (140; JSON-LD / Hydra, OpenAPI, JSON:API, HAL, JSON Merge Patch), `graphql-mercure.md`
(110) and `test-patterns.md` (150; `ApiTestCase` with PHPUnit). The docs badge and inventory (9 -> 10 skills, 6 universal
+ 4 stack-packs), the Tier-2 card (DE/EN), the README lines and the CHANGELOG name the pack. A project declaring
`Stack-Pack: stack-php-api-platform` now gets `✓ Stack-pack loaded` instead of the "declared but not found" warning.

## Why

- epic-006 ships researched stack-packs (D43); API Platform needs its own because its idioms (state providers and
  processors, `QueryParameter` filters, DTO resources, `ApiTestCase`) sit on top of Symfony and change between lines.
  Every version claim was checked on 2026-11-09 against Packagist (5.0.6 / 4.4.7, PHP 8.2, Symfony 7.4 or 8.x), the docs
  repository's 5.0 branch and the 5.0 source, and carries an https source in `## Sources`.
- The user chose entity and DTO both with a stated criterion, a scope of core + filters / pagination / more formats /
  GraphQL / Mercure, tests with `ApiTestCase`, monolithic (D27), the Symfony variant only.

## Walk-through

Research against the 5.0 and 4.4 sources first, then a probe project (`composer require api` on Symfony 8.1.11, API
Platform 5.0.6) that ran the behaviours the pack states: default operations, a lone `#[GetCollection]` removing the
defaults, 422 versus 400, 406 versus 415, JSON without `charset`, the test client's content types, DTO resources through
the Object Mapper, OpenAPI 3.2.0, JSON:API and HAL as separate packages, GraphQL at `/api/graphql`. The pack was written
from that, trimmed to the contract, and verified by command (`verify-run.sh` run 1, 4/4 checks). The first Phase-8 attempt
could not spawn the reviewer (auto mode refused the Agent call twice because a hook rewrote its input); round 1 ran on
2026-11-11 and found 1 Heavy and 3 Light findings, all local edits, all fixed in-phase: the Doctrine extension example
failed open for an anonymous caller (it now restricts to nothing, says why, and the test patterns add an anonymous case);
the Security example combined a resource-level `security` with `securityPostDenormalize`; a pointer to a nonexistent
"Doctrine pack" (the native-lazy-objects rule is restated now); and 5.0.6 carried 5.0.0's release date.
`test-stack-packs.sh` (44 passed) and `test-docs-site.sh` stayed green after the fixes.

## Decisions

- **Resource model: both, with a criterion (user, 2026-11-09).** An entity may be the resource for plain CRUD; a
  separate resource class (DTO) with a state provider / processor once the API model and the data model diverge. The pack
  states the rule for choosing. What the API Platform docs recommend today was verified in the build, not recalled.
- **Scope: core + filters and pagination, more formats, GraphQL, Mercure (user).** JSON-LD / Hydra, OpenAPI, validation,
  security and tests are always in. To hold the contract's size budget the references are split by topic into six files.
- **Targets the Symfony variant of API Platform** (from slice-083's detection decision): a Laravel app with
  `api-platform/laravel` gets `stack-php-laravel`, so this pack never has to cover Laravel.
- **Tests: `ApiTestCase` with PHPUnit (user)** — consistent with `stack-php` and `stack-php-symfony`.
- **Depends on slice-085 (user).** Built after the Symfony pack: it reuses that slice's verified Symfony / Doctrine
  research and touches the same docs lines. Monolithic (D27): the Symfony core is restated in this pack, not referenced.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: an
  older API Platform major and its extension model (data providers / persisters before state providers / processors),
  Behat or HTTP-client tests instead of `ApiTestCase`. The rule itself (the project's toolchain wins, never migrate
  unasked) is the baseline's, not repeated here.
- **Docs-versus-source conflicts resolved in the build (2026-11-09).** The pack follows the 5.0 source and the probe
  project where the 5.0 docs lag: JSON responses carry no `charset`; tests extend `ApiPlatform\Test\ApiTestCase`
  (`api-platform/test`, the docs show the deprecated shim); `Serializer\Annotation\Groups` is gone in Symfony 8; the
  GraphQL Playground is gone; `patch_formats` defaults to merge patch; an unsupported `Accept` is 406, not 415; JSON:API
  and HAL need their own packages; the policy page still names 4.3 as stable (the pack says so and derives 5.0 / 4.4 from
  the releases).
- **Content review for the user.** Read `SKILL.md` (Stack, the six `## Existing Projects` entries, Anti-Patterns), then
  `references/resource-patterns.md` (the entity-or-DTO criterion table is the decision the user asked for), and the
  `## Sources` list. Not covered on purpose: MongoDB ODM, Elasticsearch, file upload, subresource depth, the MCP package,
  the admin and PWA clients, FOSUser, Nelmio API Doc, deployment.
- **Phase 7 skipped (project rule).**

## Commits

- `15e6192` — feat(skills): add the stack-php-api-platform pack
- `bc81bbc` — docs: wire stack-php-api-platform into the docs site, README and changelog
