# Slice 090 — stack-ts

> Completed: 2026-11-11
> Commits: 0b0c639..328cd9d (on epic-006-stack-packs, no PR) · epic-006 entry `stack-ts`

## What

CRAFT now ships `stack-ts`, a researched stack-pack for plain TypeScript on Node (a library, CLI or service, no frontend
framework): `skills/stack-ts/SKILL.md` plus three references (code quality, project patterns, test patterns), satisfying
the stack-pack contract. It covers strict-mode typing, narrowing, error handling and async idioms; an ESM-only npm project
setup (tsconfig for Node, `package.json` `exports`, a plain-`tsc` build, CLIs, CommonJS interop); ESLint 10 +
typescript-eslint + Prettier; and Vitest 5 test patterns. The docs badge and inventory (14 skills, 8 stack-packs), the
Tier-2 card (DE/EN), the README lines and the CHANGELOG name it.

## Why

- A project that declares `Stack-Pack: stack-ts` (or that `/craft:onboard` proposes it for) otherwise gets the
  `⚠ … declared but not found` line and only the baseline. D43 wants every pack researched, dated and sourced.
- The research changed one premise: TypeScript 7.0.2 is the current release but ships no JavaScript API, so
  typescript-eslint (peer range `<6.1.0`) needs the 6.0 compatibility package behind an npm alias. The pack documents that
  setup, and it was run by hand in a scratch project.

## Walk-through

1. Research against primary sources (TypeScript 7.0 / 6.0 / 7.1 announcements and docs, the nodejs.org schedule and API
   docs, typescript-eslint, ESLint 10, Prettier, the npm 12 changelog, Vitest 5 docs, the npm registry). Then a scratch
   project ran the described toolchain: tsc 7.0.2 + tsc6, typed linting, Vitest 5.1 with coverage and type tests, and
   `node src/bin.ts`.
2. `skills/stack-ts/SKILL.md` (109 lines): Stack, six Existing Projects entries (pnpm/Yarn, CommonJS, Jest/Mocha, Biome,
   older Node, older TypeScript or tsconfig), Reference Files, Build Order, Anti-Patterns, and 14 dated source lines
   (`Basis: research`).
3. `skills/stack-ts/references/`: `code-quality-standards.md` (222 lines), `project-patterns.md` (260),
   `test-patterns.md` (233).
4. Wiring: `docs/index.html` (badge, counts, the Tier-2 card, DE/EN), `README.md`, `CHANGELOG.md`.
5. Evidence: `verify-run.sh` passed 4 of 4 in run 1 and again in run 2 after the review fixes. Phase 8 ran one round with
   one Heavy finding and five Light ones, all fixed in-phase; the fix cap (5) was exceeded by one small fix.
   - The Heavy finding: the pack claimed `skipLibCheck` skips only `node_modules` declarations. It skips every `.d.ts`,
     including the project's own.
   - The Light findings:
     - `*.test-d.ts` was left out of the build exclude, the `files` list and the coverage exclude.
     - The CLI sample ran `main` at import, so it is now split into `cli.ts` and `bin.ts`.
     - The tsconfig `target` sample disagreed with its prose.
     - `npm rebuild` was missing after `npm install-scripts approve`.
     - A plan decision contradicted `Depends-On`.

## Decisions

- **Scope from epic-006 (user):** plain TypeScript on Node, strict mode, Vitest; no frontend framework — React, Vue and
  Next would be packs of their own (the detection table already places `stack-ts-nextjs` / `stack-ts-react` above it).
- **Modules: ESM-only (user, 2026-11-09).** `"type": "module"` with Node's module resolution; CJS interop only as a
  section for existing code. What the Node LTS lines can do with `require(esm)` today is verified in the build.
- **Lint and format: ESLint + Prettier (user)** — typescript-eslint with flat config; not Biome as the default.
- **Runtime and package manager: Node LTS + npm (user).** The supported LTS lines are verified against nodejs.org; pnpm or
  yarn projects override it in their own `rules.md`; Bun and Deno stay out.
- **Depends on slice-083 only (user).** The epic's sequential order (shared docs lines) still lands it after the earlier
  packs. Amended: the frontmatter says `Depends-On: [slice-092]`, the contract amendment, which itself builds on slice-083.
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: pnpm or yarn instead of npm, a CommonJS project instead of ESM, Jest or Mocha instead of Vitest, Biome instead of ESLint + Prettier, an older Node line. The rule itself (the project's toolchain wins, never migrate unasked) is the baseline's, not repeated here.
- **TypeScript 7 + typescript-eslint via npm alias (build finding, 2026-11-11).** Research showed TypeScript 7.0.2 is `latest` and ships no
  JavaScript API, while typescript-eslint 8.72.2 accepts `typescript >=4.8.4 <6.1.0`. The pack therefore documents the Microsoft-recommended
  alias setup (`typescript: npm:@typescript/typescript6`, `@typescript/native: npm:typescript@^7`) and was run by hand in a scratch project
  (tsc 7.0.2 + tsc6, typed linting, Vitest 5.1 incl. coverage and type tests, `node src/index.ts`); drop it once typescript-eslint supports 7. For the content
  review: this is the one place where "what is the TypeScript version" is not a single number.
- **`.ts` specifiers + `rewriteRelativeImportExtensions` as the default for new code (build finding).** Declaration files keep the `.ts` path (TypeScript 5.7
  release notes: only non-declaration files are rewritten); TypeScript 6 and 7 consumers resolved them, older consumers were not tried, so a library with such
  consumers keeps `.js` specifiers (stated in the pack).
- **Content review for Phase 5 (what to read):** `skills/stack-ts/SKILL.md` (`## Stack`, `## Existing Projects`, `## Sources` with 14 source lines) and
  the three references; the Node LTS statement (26 Active, 24 and 22 Maintenance, 22 ends 2027-04-30), the npm 12 `allowScripts` default, and the TS 7 / typescript-eslint alias are the claims most likely to move.
- Phase 7 skipped (project rule)

## Commits

- `0b0c639` — feat(skills): add the stack-ts pack
- `328cd9d` — docs: wire stack-ts into the docs site, README and changelog
