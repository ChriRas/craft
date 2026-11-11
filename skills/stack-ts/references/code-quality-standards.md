# TypeScript 7 on Node — Code Quality Standards

## Mandatory shape

A module is typed, small and importable without side effects. Two-space indent and double quotes as Prettier writes them,
`node:` prefix on built-in imports, relative imports with their real extension (`./result.ts`), named exports. Everything
runnable lives in a function; the entry point only calls it.

```ts
import { readFile } from "node:fs/promises";

import type { Config } from "./config.ts";
import { parseConfig } from "./config.ts";

export async function loadConfig(path: string, signal?: AbortSignal): Promise<Config> {
  const text = await readFile(path, { encoding: "utf8", signal });
  return parseConfig(text);
}
```

## Strict mode and the flags worth adding

`strict: true` is the floor (TypeScript 6 and 7 turn it on by default; keep it written down). Add these on top, in a new
project from the start, in an old one flag by flag:

```jsonc
// tsconfig.json — the type-checking part (module settings: references/project-patterns.md)
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,   // array[i] and record[key] are T | undefined
    "exactOptionalPropertyTypes": true, // `a?: string` means absent, not `undefined`
    "noImplicitOverride": true,         // `override` is mandatory on a subclass method
    "noFallthroughCasesInSwitch": true,
    "verbatimModuleSyntax": true,       // `import type` is required for types, no import elision
    "erasableSyntaxOnly": true,         // no enum, namespace, parameter properties: Node can run the file as is
    "isolatedModules": true
  }
}
```

- `strict` covers `noImplicitAny`, `strictNullChecks`, `strictFunctionTypes`, `strictPropertyInitialization`,
  `useUnknownInCatchVariables` and more; a TypeScript upgrade can add checks under it. A project does not switch single
  members of the family off to make a slice pass.
- `erasableSyntaxOnly` is for a project that runs `.ts` files through Node's type stripping or may do so; use a union of string
  literals (`as const` object plus a derived type) instead of an `enum`, and assign class fields in the constructor body.
- `skipLibCheck: true` is acceptable for speed, but it skips **every** `.d.ts` file, your own included: keep hand-written declarations
  few and small, and run `tsc --noEmit --skipLibCheck false` when one changes (or leave the option off in a project that ships them).

## Type design

- **Unions over class hierarchies** — a closed set of cases is a discriminated union with a literal `kind` or `type` field;
  `switch` on it narrows each branch.
- **Immutable by default** — `readonly` properties, `ReadonlyArray<T>` (or `readonly T[]`) parameters, `as const` for literal
  tables. Take the widest useful input (`Iterable<T>`, `ReadonlyMap`), return a concrete type.
- **`interface` for an object shape that is extended or implemented, `type` for unions, mapped and conditional types** — one
  rule per project, kept by `@typescript-eslint/consistent-type-definitions` (stylistic config).
- **`satisfies`** (4.9) checks a value against a type without widening it: `const routes = { home: "/" } as const satisfies
  Record<string, string>;` keeps the literal types and still catches a wrong shape.
- **Generics earn their place** — a type parameter is used at least twice (input and output); `NoInfer<T>` (5.4) stops an
  argument from widening an inferred `T`; `const T` (5.0) keeps literal inference for tuples and tables.
- **Branded types** for values that must not be mixed up (`type UserId = string & { readonly __brand: "UserId" }`) with one
  constructor function that validates; no `as UserId` scattered through the code.
- **No `any`** — use `unknown` at a boundary and narrow it; a precise type, a generic or an overload where the shape varies.
  `@typescript-eslint/no-explicit-any` and the `no-unsafe-*` rules (recommended type-checked config) report the leaks.
- **Utility types** (`Pick`, `Omit`, `Partial`, `Required`, `Readonly`, `Record`, `ReturnType`, `Awaited`, `NonNullable`) derive
  a type from another one instead of copying it; keep the chain short enough to read in a hover.

## Narrowing and type guards

- **Built-in narrowing** — `typeof`, `instanceof`, `in`, equality, truthiness and the discriminant check all narrow; prefer
  them to casts. Optional chaining and `??` handle `null | undefined` without a branch.
- **User-defined guards** — `function isUser(value: unknown): value is User` for data that crosses a boundary. TypeScript 5.5
  infers a type predicate from a simple `filter` callback (`items.filter((x) => x !== undefined)`), so the cast is gone.
  Keep a guard honest: it checks every property it promises.
- **Assertion functions** — `function assertDefined<T>(x: T | undefined): asserts x is T` for a precondition that throws.
- **Exhaustiveness** — end a `switch` over a union with a `never` check so a new member is a compile error:

```ts
export type Shape = { kind: "circle"; radius: number } | { kind: "square"; side: number };

function assertNever(value: never): never {
  throw new Error(`unhandled case: ${JSON.stringify(value)}`);
}

export function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle":
      return Math.PI * shape.radius ** 2;
    case "square":
      return shape.side ** 2;
    default:
      return assertNever(shape);
  }
}
```

- **Casts** — `as` is a promise the compiler cannot check. Allowed after a real check or for a test fixture; never to silence an
  error. `!` is the same promise; replace it with a check that throws a useful message. `as unknown as T` is a bug report.

## Data at the boundary

`JSON.parse`, `response.json()`, `process.env`, `process.argv`, file contents and message payloads are untyped. Take them as
`unknown` (or `string | undefined` for `process.env`), validate once where they enter — a hand-written guard or the schema
library the project already uses — and pass typed values inward. Inner code trusts its types. `Object.keys` returns
`string[]` and `Object.entries` loses key types on purpose: iterate a typed tuple or map instead of casting.

## Error handling

- **`catch` gives `unknown`** (`useUnknownInCatchVariables`, part of `strict`): narrow before use —
  `if (error instanceof Error) …` — and rethrow what you cannot handle. Anything can be thrown, so never read `error.message`
  unchecked.
- **Throw `Error` subclasses with a `cause`**, never strings or plain objects (a stack trace is the point):

```ts
export class ConfigError extends Error {
  override readonly name = "ConfigError";
}

export function parseConfig(text: string): Config {
  try {
    return toConfig(JSON.parse(text) as unknown);
  } catch (error) {
    throw new ConfigError("invalid config file", { cause: error });
  }
}
```

- **Exceptions for the unexpected, values for the expected** — a parse that can reasonably fail returns a result
  (`{ ok: true; value } | { ok: false; error }`) or `undefined`; a violated precondition throws. Do not mix the two styles in
  one module.
- **No silent swallow** — an empty `catch` or `.catch(() => {})` needs a comment saying why; `@typescript-eslint/only-throw-error`
  and `prefer-promise-reject-errors` keep non-`Error` throws out.
- **Boundaries** — the CLI or service entry point turns an unexpected error into one readable message and a non-zero exit code
  (`process.exitCode = 1`; a bare `process.exit()` can cut off pending output). Stack traces belong in debug mode and logs.
- **Unhandled rejections** end the process on Node by default (the `throw` mode since Node 15); do not install a handler that
  hides them. Fix the missing `await` or `catch`.

## Async and resources

- **Return and await promises, do not float them** — every promise is `await`ed, returned or explicitly handled with `void` plus a
  catch; `@typescript-eslint/no-floating-promises` and `no-misused-promises` (type-checked configs) report the rest.
- **Run independent work together** — `await Promise.all([a(), b()])` fails fast; `Promise.allSettled` when every outcome
  matters; never `await` inside a loop over independent calls. Bound the concurrency of a large fan-out with a small pool.
- **Deadlines and cancellation** — pass an `AbortSignal` down: `AbortSignal.timeout(ms)` for a deadline, `AbortSignal.any([a, b])`
  to combine, `signal.throwIfAborted()` in long loops. `fetch`, `fs/promises`, `node:timers/promises` and `events.once` accept
  a `signal`. Handle the `AbortError` once, at the top.
- **Timers** — `import { setTimeout as sleep } from "node:timers/promises"` instead of a hand-made promise wrapper.
- **Resources** — close in `finally`, or with `using` / `await using` (TypeScript 5.2) for a type that implements
  `Symbol.dispose` / `Symbol.asyncDispose`. TypeScript rewrites `using` for a target below ESNext; a file that Node runs
  as it is must be parsed by that Node line, so check the floor before relying on it.
- **Entry** — top-level `await` is allowed in an ES module and in an entry file; keep it out of library modules (it blocks every
  importer and cannot be `require`d). One `main()` at the edge, awaited, with the error handler around it.
- **Callbacks** — an `async` function passed to `forEach`, an event emitter or `setTimeout` is not awaited; collect the promises
  or use a `for … of` loop.

## Modules, naming and logging

- **ES modules only** — `import` / `export`, never `require`, `module.exports` or `__dirname` in an ESM file
  (`import.meta.dirname` and `import.meta.filename`, Node 20.11 and later; `import.meta.main` is still early development).
- **Named exports**; a default export only where a tool requires it (a config file). A library lists its public API in one
  entry module; internals stay unexported.
- **`import type`** (enforced by `verbatimModuleSyntax`) for type-only imports; `export type { … }` for type re-exports.
- **Names** — `camelCase` values and functions, `PascalCase` types and classes, `UPPER_SNAKE_CASE` only for real constants,
  files `kebab-case.ts`. A boolean reads as a question (`isReady`, `hasAccess`).
- **Comments** say why, not what; a public API gets a TSDoc comment. `// @ts-expect-error reason` replaces `@ts-ignore` (it fails
  when the error disappears).
- **Output** — a CLI writes results to stdout and diagnostics to stderr; a library does not write to the console at all.
  A service logs through the logger the project already has, structured, with no secrets.

## Configuration: ESLint and Prettier

```js
// eslint.config.mjs — ESLint 10 reads flat config only
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import eslintConfigPrettier from "eslint-config-prettier/flat";
import tseslint from "typescript-eslint";

export default defineConfig(
  globalIgnores(["dist/", "coverage/"]),
  {
    files: ["**/*.{js,mjs,ts}"],
    extends: [
      js.configs.recommended,
      tseslint.configs.strictTypeChecked,
      tseslint.configs.stylisticTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        projectService: { allowDefaultProject: ["eslint.config.mjs"] },
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  eslintConfigPrettier, // last: switches off the rules Prettier owns
);
```

- **Presets** — `recommendedTypeChecked` is the stable baseline; `strictTypeChecked` and `stylisticTypeChecked` add more (the
  strict presets can gain rules in a minor release, so lock `typescript-eslint` with the lock file and upgrade on purpose).
  Typed linting needs the `projectService`; a file outside every tsconfig (`eslint.config.mjs`) goes in `allowDefaultProject`
  or into a tsconfig's `include`, not behind `// eslint-disable`.
- **Prettier** — pin it exactly (`npm install --save-dev --save-exact prettier`), keep `.prettierrc` small (`{}` is a valid
  start; set `printWidth` or `singleQuote` only when the team decides), list build output in `.prettierignore`. Run
  `prettier --check .` in CI and `prettier --write .` locally. Do not run Prettier inside ESLint (`eslint-plugin-prettier`).
- **Suppress narrowly** — `// eslint-disable-next-line @typescript-eslint/no-unsafe-assignment -- reason` on the line, with a reason;
  never a file-wide disable or a project-wide `off` to get a slice through. Test files may relax a rule in a `files:` block.
- **Scripts** — `"lint": "eslint ."`, `"format": "prettier --check ."`, `"typecheck": "tsc --noEmit"`, one `"check"` script
  that runs them and the tests.

## Code-quality checklist

- [ ] `tsc --noEmit` is clean without a new `@ts-expect-error`, `any`, `!` or `as`.
- [ ] `eslint .` and `prettier --check .` are clean; no rule switched off project-wide to make a slice pass.
- [ ] No module does work at import time except defining names; no mutable module-level state.
- [ ] Every `catch` narrows `error`; every wrapped error passes `{ cause }`; nothing throws a non-`Error`.
- [ ] Every promise is awaited, returned or handled; long operations take an `AbortSignal`.
- [ ] Untyped input (`JSON.parse`, `process.env`, `fetch`) is validated once at the boundary.
- [ ] Time, randomness, environment and the filesystem enter through arguments or small adapters.
- [ ] Public exports have TSDoc that says what, not how; internals are not exported.
- [ ] No `console.log`, `debugger`, commented-out code or TODO without an owner left behind.
