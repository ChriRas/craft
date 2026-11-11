---
name: stack-ts
description: CRAFT stack-pack for plain TypeScript projects on Node without a frontend framework (libraries, CLIs, services) — strict typing, narrowing, error handling and async idioms, an ESM-only npm project setup (tsconfig, package.json exports, build), ESLint + Prettier, and Vitest test patterns. Loaded by /craft:build, /craft:test, /craft:refactor and /craft:review when a project declares it. Not auto-activated.
disable-model-invocation: true
---

# Stack-Pack — TypeScript (plain, on Node)

The code-near personality layer for a TypeScript 7 project on a Node.js LTS line without a frontend framework — a library, a
command-line tool or a service wired by hand — written as ES modules, managed with npm, kept clean with ESLint and Prettier,
and tested with Vitest. It is loaded on top of the Senior-Developer baseline by `/craft:build`, `/craft:test`,
`/craft:refactor` and `/craft:review` when `rules.md` declares it in its `## Personality` block. A project on React, Vue,
Next.js or another frontend framework wants a pack of its own; Bun and Deno are out of scope. Project-specific
conventions — domain rules, exact tool commands, the supported Node range — live in the project's own `rules.md`, not here.
Versions and tool behaviour below were verified on 2026-11-11 (see `## Sources`); a newer release may have moved since.

## Stack

- **Language** — TypeScript 7.0 (7.0.2): the native compiler, same `tsc` command line, about ten times faster than 6.0, with
  6.0's defaults (`strict` on, `types` empty, `rootDir` the tsconfig directory). 7.0 ships **no JavaScript API** (7.1 adds a new
  one, in beta): typescript-eslint needs the 6.0 API, so a project runs both through npm aliases (see
  `references/project-patterns.md`). Idioms: strict mode, discriminated unions, `unknown` plus narrowing, `satisfies`.
- **Runtime** — Node.js on an LTS line, ES modules (`"type": "module"`). On 2026-11-11 Node 26 is Active LTS, Node 24 and 22
  Maintenance LTS (22 ends on 2027-04-30); Node 20 ended on 2026-04-30. New code targets 22.12 or later: `require(esm)` works
  there without a flag, and Vitest 5 needs 22.12, ESLint 10 22.13 and npm 12 22.22 on the 22 line.
- **Packages** — npm (12.2). Since npm 12 a dependency's install script runs only when the root `package.json` lists it in
  `allowScripts`, and git or tarball-URL dependencies are blocked by default. Commit `package-lock.json`, install with `npm ci`.
- **Quality** — ESLint 10 in flat config with typescript-eslint 8 (typed linting), Prettier 3.10 pinned exactly,
  `eslint-config-prettier` to switch off the style rules Prettier owns. `tsc --noEmit` is the type check.
- **Tests** — Vitest 5 with `@vitest/coverage-v8` (see `references/test-patterns.md`).

## Existing Projects

The Senior-Developer baseline's existing-toolchain rule applies. Read `package.json` (`type`, `engines`, `packageManager`,
scripts), the lock file, `tsconfig*.json` and the config files at the root first, and follow what they declare:

- **pnpm or Yarn instead of npm** — `pnpm-lock.yaml` or `yarn.lock` (Yarn 2+ also `.yarnrc.yml`), a `packageManager` field. Use
  `pnpm add -D <pkg>`, `pnpm install --frozen-lockfile` and `pnpm exec`, or `yarn add -D <pkg>`, `yarn install --immutable`
  and `yarn <bin>`. pnpm asks for build approval with `pnpm approve-builds`; Yarn needs `vite` listed explicitly for Vitest 5.
  Corepack ships with Node only up to 24 (`npm install -g corepack` on 25 and later). Write no `package-lock.json` beside them.
- **A CommonJS project instead of ESM** — no `"type"` field (or `"commonjs"`), `.js` files that `require`, a `module: commonjs`
  tsconfig. Keep it: `module: nodenext` checks both formats, `.mts` and `.cts` pin a file's format, and from Node 22.12 `require`
  loads an ES module that has no top-level `await`. Reach an ESM-only dependency with `import()`. Switching the project to
  ESM is a slice of its own.
- **Jest or Mocha instead of Vitest** — `jest.config.*` or `.mocharc.*` and `jest` / `mocha` in the dependencies. Jest 30 runs
  TypeScript through `ts-jest` or Babel (`babel-jest` with `@babel/preset-typescript`, no type check); ES modules need
  `node --experimental-vm-modules` and `extensionsToTreatAsEsm`. Mocha 12 needs `--extension ts` and Node's type stripping
  (22.18 and later) or `tsx`. Run the project's runner (`npx jest`, `npx mocha`), follow its neighbours' style, add no second runner.
- **Biome instead of ESLint + Prettier** — `biome.json` and `@biomejs/biome` (2.6). Run `npx biome check` (`--write` to fix,
  `biome ci` in CI); it lints, formats and sorts imports in one tool, so add neither ESLint nor Prettier next to it.
- **An older Node line** — `engines`, `.nvmrc` / `.node-version`, a CI matrix. Use no feature above the floor: `require(esm)` and
  `import.meta.dirname` need 22.12 / 20.11, type stripping runs by default from 22.18. Node 20 and 18 are end-of-life — say so,
  do not upgrade silently. The tool majors follow the floor: Vitest 5 wants 22.12, ESLint 10 wants 20.19 / 22.13 / 24, npm 12 22.22.
- **An older TypeScript or a legacy tsconfig** — 5.x, 6.0, `moduleResolution: node`, `baseUrl`, `esModuleInterop: false`, a
  `target: es5`, extensionless relative imports, `.js` specifiers instead of `.ts`. TS 7 reports the removed options as hard errors; fix
  them only when the slice upgrades the compiler. In a `.js`-specifier project keep writing `.js` specifiers.

## Reference Files

Consult these for depth — read the one relevant to the work at hand:

- `references/code-quality-standards.md` — strict-mode flags, type design, narrowing, error handling, async and resources,
  ESLint and Prettier configuration, the code-quality checklist.
- `references/project-patterns.md` — tsconfig for Node, the TypeScript 7 + typescript-eslint alias setup, ESM module rules,
  `package.json` (`exports`, `engines`, scripts), building a library, CLIs, running `.ts` files, CommonJS interop.
- `references/test-patterns.md` — Vitest layout and configuration, tests, parametrisation, mocks and fake timers, async tests,
  coverage, type tests.

## Build Order

When a slice spans several layers, implement in dependency order:

1. Project and tooling — `package.json` (`type`, `engines`, scripts), `tsconfig.json`, ESLint, Prettier and Vitest configuration.
2. Domain types — unions, branded or readonly types, error classes, schemas for data that crosses a boundary.
3. Pure logic — functions that take their dependencies as arguments.
4. Adapters — filesystem, network, database, clock and process behind small interfaces.
5. Entry points — the CLI or service `main()` that parses input, wires everything and maps errors to exit codes.
6. Tests — alongside each layer or right after; `tsc --noEmit`, `eslint .`, `prettier --check .` and `vitest run` pass before a layer counts as done.

## Anti-Patterns

- `any`, a non-null `!` or an `as` cast where narrowing, `unknown` or a type guard fits; `// @ts-ignore` instead of `@ts-expect-error` with a reason.
- Disabling a `strict` flag to make a slice compile, or trusting `JSON.parse`, `fetch().json()` or `process.env` as typed values.
- `enum`, `namespace` and constructor parameter properties in a project that runs `.ts` through Node's type stripping (`erasableSyntaxOnly`).
- A floating promise, an `async` callback passed where a `void` return is expected, `await` in a loop over independent calls, or a `catch` that swallows the error.
- `throw` of a string or plain object, a rethrow that drops `cause`, `catch (e)` read as an `Error` without a check.
- Mixing `require` and `import` in one module, an extensionless relative import, a default export from a library module, a `package.json` without `exports`.
- Importing a package's internals through a deep path, or a `devDependency` imported by shipped code.
- `skipLibCheck` hiding your own declaration errors, or `tsc` and a bundler both emitting the same output.
- Tests that sleep, hit the network or the wall clock, share state between tests, or mock the module under test; `vi.mock` inside a function.

## Sources

> As of: 2026-11-11 · Basis: research

- Announcing TypeScript 7.0, 6.0 and 7.1 Beta — https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/, https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/, https://devblogs.microsoft.com/typescript/announcing-typescript-7-1-beta/ (the native compiler, no API in 7.0, the `@typescript/typescript6` alias, new defaults and removed options, the 7.1 API)
- npm registry, current releases and engines — https://www.npmjs.com/package/typescript, https://www.npmjs.com/package/@typescript/typescript6, https://www.npmjs.com/package/typescript-eslint, https://www.npmjs.com/package/eslint, https://www.npmjs.com/package/prettier, https://www.npmjs.com/package/eslint-config-prettier, https://www.npmjs.com/package/vitest, https://www.npmjs.com/package/@vitest/coverage-v8, https://www.npmjs.com/package/@types/node, https://www.npmjs.com/package/npm, https://www.npmjs.com/package/pnpm, https://www.npmjs.com/package/jest, https://www.npmjs.com/package/mocha, https://www.npmjs.com/package/@biomejs/biome, https://www.npmjs.com/package/tsx (TypeScript 7.0.2, typescript-eslint 8.72.2, ESLint 10.14.0, Prettier 3.10.0, eslint-config-prettier 10.1.8, Vitest 5.1.0, @types/node 26.6.6, npm 12.2.2, pnpm 12.18.0, Jest 30.5.2, Mocha 12.0.3, Biome 2.6.6, tsx 4.23.15)
- Node.js releases and release schedule — https://nodejs.org/en/about/previous-releases, https://github.com/nodejs/Release/blob/main/schedule.json (Node 26 Active LTS since 2026-10-28, 24 Maintenance since 2026-10-20, 22 ends 2027-04-30, 20 ended 2026-04-30)
- Node.js API: modules, ECMAScript modules, packages, TypeScript, CLI, util, process, timers, globals, corepack — https://nodejs.org/api/modules.html, https://nodejs.org/api/esm.html, https://nodejs.org/api/packages.html, https://nodejs.org/api/typescript.html, https://nodejs.org/api/cli.html, https://nodejs.org/api/util.html, https://nodejs.org/api/process.html, https://nodejs.org/api/timers.html, https://nodejs.org/api/globals.html, https://nodejs.org/api/corepack.html (`require(esm)` history, `import.meta`, `exports` conditions, type stripping, unhandled rejections, `parseArgs`, `AbortSignal`, Corepack distribution)
- TypeScript documentation: tsconfig reference, modules reference, choosing compiler options, narrowing, utility types — https://www.typescriptlang.org/tsconfig/, https://www.typescriptlang.org/docs/handbook/modules/reference.html, https://www.typescriptlang.org/docs/handbook/modules/guides/choosing-compiler-options.html, https://www.typescriptlang.org/docs/handbook/2/narrowing.html, https://www.typescriptlang.org/docs/handbook/utility-types.html (`module` values `nodenext` / `node20`, `strict` family, `erasableSyntaxOnly`, `verbatimModuleSyntax`, `rewriteRelativeImportExtensions`, exhaustiveness)
- TypeScript release notes 4.9, 5.0, 5.2, 5.4, 5.5, 5.7 and 5.8 — https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-0.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-2.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-4.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-5.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-7.html, https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-8.html (`satisfies`, `const` type parameters, `using`, `NoInfer`, inferred type predicates, rewritten import extensions, erasable syntax)
- Community tsconfig bases — https://github.com/tsconfig/bases/tree/main/bases (Node 22, 24 and 26 and strictest bases: `lib`, `target`, `module`, strict options)
- typescript-eslint: getting started, typed linting, shared configs, dependency versions, parser — https://typescript-eslint.io/getting-started/, https://typescript-eslint.io/getting-started/typed-linting, https://typescript-eslint.io/users/configs, https://typescript-eslint.io/users/dependency-versions/, https://typescript-eslint.io/packages/parser (flat config, `projectService`, `tsconfigRootDir`, supported ESLint `^8.57 || ^9 || ^10` and TypeScript `>=4.8.4 <6.1.0`)
- ESLint: configuration files and migrating to v10 — https://eslint.org/docs/latest/use/configure/configuration-files, https://eslint.org/docs/latest/use/migrate-to-10.0.0 (`eslint.config.*`, `defineConfig`, `globalIgnores`, flat config only, supported Node lines)
- Prettier: install, configuration, integrating with linters — https://prettier.io/docs/install, https://prettier.io/docs/configuration, https://prettier.io/docs/integrating-with-linters (exact pin, `.prettierrc` and `.prettierignore`, `eslint-config-prettier` over `eslint-plugin-prettier`)
- npm CLI: changelog 12.0.0, package.json, `npm install-scripts` — https://github.com/npm/cli/blob/latest/CHANGELOG.md, https://docs.npmjs.com/cli/v12/configuring-npm/package-json, https://docs.npmjs.com/cli/v12/commands/npm-install-scripts (npm 12 breaking changes, `allowScripts`, `engines`, `devEngines`, `exports`)
- Vitest: guide, migration to 5.0, coverage, mocking, configuration, `vi` API, test context — https://vitest.dev/guide/, https://vitest.dev/guide/migration.html, https://vitest.dev/guide/coverage.html, https://vitest.dev/guide/mocking.html, https://vitest.dev/config/, https://vitest.dev/api/vi.html, https://vitest.dev/guide/test-context.html (Node >= 22.12 and Vite >= 6.4, `clearMocks` default, hoisted `vi.mock`, unawaited assertions fail, v8 coverage, `test.extend`)
- Jest, Mocha, Biome, pnpm and Yarn documentation — https://jestjs.io/docs/ecmascript-modules, https://jestjs.io/docs/getting-started, https://mochajs.org/explainers/typescript/, https://biomejs.dev/guides/getting-started/, https://biomejs.dev/reference/cli/, https://pnpm.io/cli/install, https://pnpm.io/cli/approve-builds, https://yarnpkg.com/cli/install, https://yarnpkg.com/cli/add (the commands named in `## Existing Projects`)
- Hands-on check on 2026-11-11 (Node 26.13.0, npm 11.20.0, a scratch project; observed, not documented) — https://typescript-eslint.io/users/dependency-versions/ (the setup in `references/project-patterns.md` was run: `tsc` 7.0.2 and `tsc6` 6.0.3 side by side, typed linting on the 6.0 alias, `vitest run --coverage`, `node src/index.ts`; adding typescript-eslint next to TypeScript 7 failed with `ERESOLVE`, the peer range being `<6.1.0`)
