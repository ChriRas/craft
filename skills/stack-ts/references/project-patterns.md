# TypeScript on Node — project patterns: tsconfig, ESM, package.json, builds, CLIs

## Project layout

```text
acme-tool/
├── package.json            # "type": "module", exports, engines, scripts
├── package-lock.json       # committed
├── tsconfig.json           # type check: src and tests, noEmit
├── tsconfig.build.json     # emit: src only, no tests
├── eslint.config.mjs
├── vitest.config.ts
├── .prettierrc  .prettierignore
├── src/
│   ├── index.ts            # the public entry of a library (or main.ts of a service)
│   ├── cli.ts              # exports main(argv): no top-level call, so tests can import it
│   ├── bin.ts              # shebang + `process.exitCode = main(...)`, the only entry
│   └── parse.ts  parse.test.ts   # a test sits next to its module
├── test/                   # integration and end-to-end tests, fixtures
└── dist/                   # emitted JavaScript and .d.ts, gitignored
```

Unit tests next to the module keep them in step; slow or cross-module tests live in `test/`. `dist/`, `coverage/` and
`node_modules/` are gitignored (and listed in `.prettierignore`); Vitest also writes to `.vitest/`.

## npm in daily use

```bash
npm ci                          # exact install from package-lock.json (CI, fresh clone)
npm install                     # resolve and update the lock file
npm install --save-dev vitest   # add a development dependency; --save-exact pins it
npm install-scripts ls          # npm 12: dependencies whose install scripts are still blocked
npm install-scripts approve esbuild   # record an approved one in "allowScripts" (review it first)
npm rebuild esbuild             # run the install script just approved
npm run build                   # scripts from package.json; `npm test` and `npm start` need no `run`
npm outdated                    # what could move; upgrade one tool at a time
npm audit                       # known vulnerabilities in the lock file
npm pack --dry-run              # exactly which files a published package would contain
```

- **npm 12 defaults** — a dependency's `preinstall` / `install` / `postinstall` runs only when the root `package.json` lists it
  in `allowScripts`; git and tarball-URL dependencies are blocked unless `allow-git` / `allow-remote` are raised; unknown CLI
  flags are errors. A native dependency whose binary does not appear after an install is usually a skipped script: approve it, then `npm rebuild <pkg>`.
- **Node ships its own npm** (Node 26.13 bundles npm 11.20): `npm install -g npm@12` moves a machine to 12, and the project's
  `engines` or `devEngines` field should say which it expects. Commands above work on npm 10 and 11 except `install-scripts`.
- **Lock file** — commit it, review its diff, never edit it by hand. `npm ci` fails when it and `package.json` disagree.
- **Dependencies** — `dependencies` are what shipped code imports at run time, `devDependencies` the tooling; a library lists
  what it needs of its consumers in `peerDependencies`. `@types/node` is a development dependency whose major matches the
  oldest Node line the project supports (`@types/node@^24` for Node 24).

## TypeScript 7 next to typescript-eslint

TypeScript 7.0 has no JavaScript API, and typescript-eslint 8.72 accepts `typescript >=4.8.4 <6.1.0`. Install the compiler under
a second name and give `typescript` itself to the 6.0 compatibility package; `tsc` is then 7's, `tsc6` the old one:

```jsonc
// package.json
{
  "devDependencies": {
    "@typescript/native": "npm:typescript@^7.0.2",          // provides the `tsc` binary
    "typescript": "npm:@typescript/typescript6@^6.0.2",     // the API typescript-eslint imports; provides `tsc6`
    "typescript-eslint": "^8.72.2"
  }
}
```

- Without the alias, `npm install -D typescript typescript-eslint` resolved `typescript` to 6.0.3 on npm 11.20, and adding
  typescript-eslint to a project that already had TypeScript 7 stopped with `ERESOLVE` — observed on 2026-11-11, so check
  `npx tsc -v` after any change to either.
- Drop the alias once typescript-eslint lists a TypeScript 7 range (TypeScript 7.1, in beta, ships the new API). Until then
  `onUnsupportedTypeScriptVersion: "error"` in `parserOptions` makes CI fail if the wrong compiler sneaks in.
- A project that stays on TypeScript 6.0 needs no alias. Whichever compiler, `tsc` in the scripts is the one that type-checks
  and emits.

## tsconfig for Node

```jsonc
// tsconfig.json — checks src and tests, emits nothing
{
  "compilerOptions": {
    "module": "nodenext",           // Node's ESM/CJS rules; implies moduleResolution nodenext and esModuleInterop
    "target": "es2024",             // runs on Node 22 and later; es2022 is the conservative Node 22 preset
    "lib": ["es2024"],
    "types": ["node"],              // the empty default since TypeScript 6 makes globals opt-in
    "rewriteRelativeImportExtensions": true,   // write `./x.ts`, emit `./x.js`
    "noEmit": true,
    "skipLibCheck": true
    // + the strict flags of references/code-quality-standards.md
  },
  "include": ["src", "test", "*.config.ts"]
}
```

```jsonc
// tsconfig.build.json — emits the library
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "noEmit": false,
    "rootDir": "src",               // 6 and 7 default to the tsconfig directory, so dist/ would nest `src/`
    "outDir": "dist",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["src/**/*.test.ts", "src/**/*.test-d.ts"]
}
```

- **`module`** — `nodenext` follows the newest Node behaviour (target `esnext`, `require(esm)` allowed). `node20` freezes it at
  Node 20's rules with target `es2023`; `node18` is the older freeze without `require(esm)`. Never `commonjs`, `esnext` or
  `bundler` for code Node runs itself; `bundler` resolution accepts imports Node refuses. TypeScript 7 rejects
  `moduleResolution: node` / `node10`, `baseUrl` and `target: es5`.
- **`target` and `lib`** — set them to what the lowest Node line runs (the `tsconfig/bases` presets use `es2022` for Node 22 and
  `es2024` for Node 24, with `lib` entries for newer built-ins; `es2024` syntax also runs on Node 22, so the sample's choice is a
  decision, not a requirement). TypeScript downlevels syntax only; a missing built-in is a
  runtime error, so check a new API against the Node floor.
- **`.ts` specifiers** — with `rewriteRelativeImportExtensions` (5.7) the source says `./parse.ts`, the emitted JavaScript
  `./parse.js`, and the same source runs under Node's type stripping and Vitest. Declaration files keep the `.ts` path (only
  non-declaration files are rewritten); TypeScript 6 and 7 consumers resolved them with `skipLibCheck` off in a hands-on
  check, older consumers were not tried. A library with such consumers, or a project that already writes `.js`, keeps `.js`
  specifiers and drops the option.
- **Type stripping** — `erasableSyntaxOnly` plus `verbatimModuleSyntax` keep the source inside what Node can strip; Node reads
  no tsconfig (no `paths`, no downlevelling). Path aliases are better replaced by `package.json` `imports` (`"#lib/*"`), which
  Node and TypeScript both resolve.
- **Several environments** — one tsconfig describes one environment. Browser code or a build script with other `types` gets a
  tsconfig of its own, linked with project references (`tsc -b`).

## ES modules on Node

- `"type": "module"` in `package.json` makes `.js` files ES modules; `.mts` / `.mjs` always are, `.cts` / `.cjs` never.
- Relative imports carry the file extension; directory and `index` imports are not resolved. Built-ins use the `node:` prefix.
- `__dirname` and `__filename` do not exist: `import.meta.dirname` and `import.meta.filename` (Node 20.11 and later) or
  `new URL("./x.json", import.meta.url)`. A JSON file is imported with `import data from "./x.json" with { type: "json" }`.
- A default import of a CommonJS package is its `module.exports`; named imports work when Node's static analysis finds them,
  and TypeScript assumes they do — a missing one fails at run time, not at compile time.
- Top-level `await` is allowed in an ES module; a module that uses it cannot be loaded with `require`.

## package.json for a library

```jsonc
{
  "name": "@acme/tool",
  "version": "1.0.0",
  "type": "module",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" },
    "./package.json": "./package.json"
  },
  "bin": { "acme": "./dist/bin.js" },
  "files": ["dist", "!dist/**/*.test.*", "!dist/**/*.test-d.*"],
  "engines": { "node": ">=22.12" },
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "format": "prettier --check .",
    "test": "vitest run",
    "check": "npm run typecheck && npm run lint && npm run format && npm test",
    "prepack": "npm run build"
  }
}
```

- **`exports`** is the only public surface: a consumer cannot import a path that is not listed. Put `"types"` first in each
  condition object, `"default"` last; conditions match in object order. Add subpath entries (`"./testing"`) deliberately and
  treat them as API. `main` and `types` at the top level are only for tools that predate `exports`.
- **ESM only is enough** for a new library: Node 22.12 and later load an ES module with `require` (no top-level `await` in its
  graph), so a CommonJS consumer on a supported line still works. A `"module-sync"` condition can steer a dual consumer. Publish
  a CommonJS build only for a stated consumer; two builds of one package risk two copies loaded side by side.
- **`engines`** states the supported Node range for consumers; `devEngines` (`runtime`, `packageManager`, `onFail`) says what
  contributors must use, and npm checks it before `install`, `ci` and `run`.
- **`files`** whitelists what is published; check with `npm pack --dry-run` that tests, configs and source maps you do not
  want are out. `"private": true` stops an application from being published by accident.
- **Verify the package** (optional) with `publint` and `@arethetypeswrong/cli` against the packed tarball; both read `exports`
  and the declaration files the way consumers' tools will.
- **Build** — plain `tsc` emits ESM plus `.d.ts` and needs no bundler for a Node library. Do not let a second tool emit the same
  files; if a bundler is already in the project, follow it (see `SKILL.md` → `## Existing Projects`).

## Entry points and CLIs

```ts
// src/cli.ts — exports the logic as a function tests can import; it has no top-level call
import { parseArgs } from "node:util";

import { parsePort } from "./result.ts";

export function main(argv: readonly string[]): number {
  const { values, positionals } = parseArgs({
    args: [...argv],
    options: { verbose: { type: "boolean", short: "v", default: false } },
    allowPositionals: true,
  });
  const [input] = positionals;
  if (input === undefined) {
    process.stderr.write("usage: acme [-v] <port>\n");
    return 2;
  }
  const result = parsePort(input);
  if (!result.ok) {
    process.stderr.write(`${result.error.message}\n`);
    return 1;
  }
  if (values.verbose) process.stderr.write("valid\n");
  process.stdout.write(`${String(result.value)}\n`);
  return 0;
}
```

```ts
#!/usr/bin/env node
// src/bin.ts — the only file that runs at import time
import { main } from "./cli.ts";

process.exitCode = main(process.argv.slice(2));
```

- `util.parseArgs` covers flags, options and positionals without a dependency; a larger CLI with sub-commands may justify a
  library, chosen once. `tsc` keeps the shebang; the `bin` entry points at the emitted `dist/bin.js`.
- Results to stdout, diagnostics to stderr; exit `0` on success, `1` on a runtime failure, `2` on a usage error. Set
  `process.exitCode` and let the event loop finish instead of calling `process.exit()`.
- A module that must run only as an entry can test `import.meta.main` (Node 24.2 and 22.18, still marked early development);
  the separate `bin.ts` above, which only calls the exported `main`, needs no such guard.
- **Configuration** — read the environment once in the entry point (`process.env`, `process.loadEnvFile()` or
  `node --env-file=.env`), validate it into a typed object, and pass that object in. `.env` files are gitignored.
- **A service** keeps the same split: `createApp(config)` builds and returns the server without listening, `main()` listens,
  handles `SIGTERM` by closing the server, and sets the exit code. Tests call `createApp`.

## Running TypeScript directly

- **Node's type stripping** runs a `.ts` file that uses only erasable syntax: `node src/bin.ts` (default since Node 22.18 and
  23.6, stable from 24.12 and 25.2). It does no type checking, reads no tsconfig, and refuses `enum`, runtime `namespace`,
  parameter properties and `.tsx`. Keep `tsc --noEmit` in the checks.
- **`tsx`** (4.23) runs TypeScript with full syntax support and tsconfig features: `npx tsx script.ts` or
  `node --import=tsx script.ts`; useful for scripts and development, not a reason to leave the erasable subset.
- **`node --watch src/main.ts`** restarts on change; Vitest has its own watch mode (`vitest`).
- Production runs the emitted JavaScript from `dist/` (`node dist/main.js`), not a loader.

## CommonJS interop

For code that must live beside CommonJS:

- **ESM imports CJS** — `import pkg from "legacy-pkg"` gives `module.exports`; `import { named } from "legacy-pkg"` works only if
  Node detects the export. For a CJS dependency without types, install its `@types/*` or write a small `.d.ts`.
- **CJS imports ESM** — `await import("esm-pkg")` always works; `require("esm-pkg")` works from Node 22.12 (20.19) when the
  module graph has no top-level `await` (otherwise `ERR_REQUIRE_ASYNC_MODULE`), and `module: nodenext` models this.
- **A CJS file in an ESM package** is a `.cjs` / `.cts` file; an ESM file in a CJS package is `.mjs` / `.mts`. TypeScript
  emits each in its own format under `nodenext`.
- **`require` inside ESM** — `import { createRequire } from "node:module"; const require = createRequire(import.meta.url);`
  for the rare CJS-only resource.
- **A CommonJS project** keeps `require` and `module.exports` in `.js`; new files may be `.ts` compiled as CommonJS by
  `module: nodenext` without a `"type"` field. Moving to ESM is a project decision (see `SKILL.md` → `## Existing Projects`).

## Node version policy

- Develop and test on the oldest supported LTS line and let CI also run the newest (a matrix of `22` and `24` or `26`).
- Pin the contributor runtime in `.nvmrc` or `.node-version` (or `devEngines.runtime`); state the consumer range in `engines`.
- When a Node line reaches end-of-life, raise `engines` and the CI matrix in one slice, then the `target`, `lib`, `@types/node`
  and any syntax the new floor allows in the next.
- A new Node major is adopted when it becomes LTS (production use is for Active and Maintenance LTS), not when it ships.
