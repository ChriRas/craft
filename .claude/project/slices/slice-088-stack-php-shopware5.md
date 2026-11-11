# Slice 088 — stack-php-shopware5

> Completed: 2026-11-11
> Commits: 1f82dbe..3f4a06a (on epic-006-stack-packs, no PR) · epic-006 entry `stack-php-shopware5`

## What

A project that declares `Stack-Pack: stack-php-shopware5` now gets a plugin-shipped maintenance pack for legacy Shopware 5 (the
5.7 line, last release 5.7.20, PHP 7.4 to 8.2). It states that Shopware 5 is end-of-life, how to change code safely without
upstream patches, the 5.2+ and the legacy `Bootstrap.php` plugin systems, Smarty templates and themes, the ExtJS backend and the
REST API, pragmatic PHPUnit 9.6 tests, and five rules ("Toward Shopware 6") so new logic stays cheap to move later.

## Why

- Shopware 5 shops and plugins are still maintained long after the vendor's end of life, and a generic PHP pack gives them neither
  the two plugin systems nor the security stance (no upstream patches) nor the test limits (no core test bootstrap in a release
  ZIP, a kernel that runs on the shop's own database).
- The pack is built from primary sources, dated and linked, as D43 requires.

## Walk-through

1. Research — the end-of-life dates, release history and PHP constraints per line (Packagist, the 5.7.20 `composer.json`, Shopware
   AG's posts), the plugin installer's real order of operations, the legacy bootstrap, the Smarty/ExtJS/REST mechanisms and the
   core test base were read from the 5.7.20 sources and the developer docs; stale docs (PHP 7.2, `.php_cs.dist`) were not followed.
2. `skills/stack-php-shopware5/SKILL.md` (112 lines) — Stack, Existing Projects (older lines, legacy vs 5.2+, no tests, ZIP shop /
   checkout / SafeFive fork, other tooling), Reference Files, Build Order, Toward Shopware 6, Anti-Patterns, Sources (13 source lines).
3. Six reference files under `skills/stack-php-shopware5/references/` (111 to 189 lines each): code quality and security,
   5.2+ plugin patterns, legacy plugin patterns, frontend, backend and REST API, tests.
4. Wiring — `docs/index.html` (skill count 11 to 12, Stack-Pack counts, the Tier-2 card and inventory line in DE and EN),
   `README.md` and `CHANGELOG.md`. No detection row: slice-083 wrote the whole table.
5. Evidence — `test-stack-packs.sh`, `test-docs-site.sh` and `claude plugin validate .` are green; `verify-run.sh` Run 1 passed 4 of 4.
   Phase 8: one round, six findings (two Heavy: 5.7-branch-head pins stated as 5.7.20 facts, and the CSRF rule), all fixed in-phase;
   the fix cap (5) was exceeded by one small fix.

## Decisions

- **Stance: maintenance + migration hints (user, 2026-11-09).** Shopware 5 reached its end of life at the end of July
  2024 (verified in slice-083; last release v5.7.20, 2025-06-05), so the pack favours safe, conservative change with no
  upstream patches to rely on, and adds short rules for cutting new logic so a later move to Shopware 6 stays cheap — not
  a full migration guide.
- **Scope: the 5.2+ plugin system, the legacy plugin system, the frontend and themes, the ExtJS backend and the REST API
  (user).** The legacy `Bootstrap.php` system is in because existing shops still carry such plugins. Six reference
  files hold the size budget.
- **Tests: pragmatic PHPUnit (user)** — isolated plugin logic, plus kernel integration tests as far as the Shopware 5
  test infrastructure carries them; what it carries is verified in the build.
- **Depends on slice-084 (user).** Shopware 5 is no Symfony full-stack application — it uses single Symfony components
  and Doctrine — so the plain-PHP research is its base, not the Symfony pack's. The migration hints stay general and do
  not wait for slice-087; the epic's sequential order still lands it after 087.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: older 5.x lines and their PHP versions, plugins without any tests, legacy and 5.2+ plugins side by side. The rule itself (the project's toolchain wins, never migrate unasked) is the baseline's, not repeated here.

- **Findings from the research (build, 2026-11-11).** (1) Shopware AG's own end-of-life statement is the 2022 post "Shopware 5 –
  how it continues" and the migration page (bug fixes to July 2023, security fixes to July 2024); the repository README now says it
  is no longer maintained and points to the SafeFive fork — the pack names SafeFive neutrally as a commercial option, not as a
  recommendation. (2) The 5.7.20 `composer.json` allows PHP 7.4 to 8.2; the unreleased branch head adds 8.3; the dev docs'
  system-requirements page still says PHP 7.2 and is stale, so the pack cites `composer.json`. (3) `tests/` is `export-ignore`d, so a
  release-ZIP shop has no core test bootstrap — functional plugin tests need a source checkout; the testing kernel runs against the
  shop's own database. (4) Plugin migrations exist from 5.6.0 (`sw:generate:migration`), not in the legacy system. (5) The pack states
  tests use PHPUnit 9.6 only, because the core's test base is written for it. The Phase-5 review should look hardest at these claims.
- Phase 7 skipped (project rule)


## Commits

- `1f82dbe` — feat(skills): add the stack-php-shopware5 pack
- `3f4a06a` — docs: wire stack-php-shopware5 into the docs site, README and changelog
