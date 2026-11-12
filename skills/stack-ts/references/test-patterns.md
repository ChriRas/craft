# Vitest 5 — Test Patterns

Vitest 5 runs on Node 22.12 or later with Vite 6.4 or later (`vite` is a peer dependency: npm and pnpm install it, Yarn needs it
listed). A test is a function passed to `test` inside an optional `describe`; assertions use `expect`. Vitest reads
`vitest.config.ts` (or `vite.config.ts`) from the project root only — it no longer searches parent directories. The config below
works as is; follow `SKILL.md` → `## Existing Projects` for a project on Jest or Mocha.

## Configuration

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/*.test.ts", "test/**/*.test.ts"],
    environment: "node",          // the default; a DOM environment (jsdom, happy-dom) is for frontend code
    restoreMocks: true,           // vi.restoreAllMocks() before each test: spies go back to the original
    unstubEnvs: true,             // vi.unstubAllEnvs() before each test: vi.stubEnv() values are undone
    unstubGlobals: true,          // vi.unstubAllGlobals() before each test
    coverage: {
      provider: "v8",
      include: ["src"],
      exclude: ["src/**/*.test.ts", "src/**/*.test-d.ts", "src/bin.ts"],
      reporter: ["text", "lcov"],
      thresholds: { lines: 90, branches: 85 },
    },
  },
});
```

- **Imports are explicit** — `import { describe, expect, test, vi } from "vitest"`. `globals: true` would add `describe` and
  `expect` globally, but then `types: ["vitest/globals"]` is needed and the habit leaks into every file; leave it off.
- **Defaults to know in 5.0** — `clearMocks` is `true` (mock call history is cleared before each test, implementations stay);
  `restoreMocks`, `mockReset`, `unstubEnvs` and `unstubGlobals` are `false`. Name the test files `*.test.ts` or `*.spec.ts`
  (the default `include` is `**/*.{test,spec}.?(c|m)[jt]s?(x)`).
- **Type-check separately** — Vitest transpiles each file and does not check types; `tsc --noEmit` stays in the checks (the
  `check` script of `references/project-patterns.md`).
- **Scripts** — `"test": "vitest run"` runs once (CI); `vitest` alone watches; `vitest run --coverage` adds the report;
  `vitest run src/parse.test.ts -t "rejects"` selects a file and a name (`-t` matches the `describe > test` path joined by ` > `).
- **Projects** — `test.projects` splits unit and integration suites with their own `include`, `environment` and setup; since
  5.0 an inline project inherits the root config by default (`extends: false` to opt out).

## Layout

A unit test sits next to its module (`src/parse.ts`, `src/parse.test.ts`); integration tests and fixtures live in `test/`.
One `describe` per unit under test, nested only for a real sub-grouping. Test names state the behaviour:
`test("rejects a port above 65535")`, not `test("test1")`. Shared helpers and builders live in `test/helpers/`, not in the
source tree.

## Writing a test

```ts
import { describe, expect, test } from "vitest";

import { parsePort } from "./result.ts";

describe("parsePort", () => {
  test("accepts a valid port", () => {
    expect(parsePort("8080")).toEqual({ ok: true, value: 8080 });
  });

  test("reports why a port is invalid", () => {
    const result = parsePort("70000");

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.message).toContain("70000");
  });
});
```

- **Arrange, act, assert**, one behaviour per test; a blank line between the parts when the test is longer than a few lines.
- **Matchers** — `toBe` for primitives and identity, `toEqual` for structure, `toStrictEqual` when `undefined` properties and
  class types matter, `toMatchObject` for a subset, `toContain`, `toHaveLength`, `toBeCloseTo` for floats. A thrown error is
  `expect(() => fn()).toThrow("message")` or `toThrow(ErrorClass)`; inspect `cause` by catching the error in the test.
- **Narrowing in a test** — an `if` that narrows a union for the assertion is fine; a test with several branches is two tests.
- **Snapshots** only for output that is large, stable and reviewed (`toMatchInlineSnapshot` keeps it in the test file). A
  snapshot nobody reads is not a test; never snapshot a timestamp, an id or an object with a class instance.
- **`test.skip` and `test.todo`** carry a reason; `test.fails` documents a known bug until it is fixed; `test.only` is never
  committed (the `vitest/no-focused-tests` rule of `@vitest/eslint-plugin` catches it).

## Parametrisation

```ts
test.each([
  { input: "1", ok: true },
  { input: "65535", ok: true },
  { input: "0", ok: false },
  { input: "abc", ok: false },
])("parsePort($input) -> ok=$ok", ({ input, ok }) => {
  expect(parsePort(input).ok).toBe(ok);
});
```

An array of objects reads better than an array of tuples and gives `$name` placeholders in the title. `describe.each` repeats a
whole group. A table with many columns or branching logic in the test body is a sign to split the test.

## Fixtures and setup

- **`beforeEach` / `afterEach`** for setup and tear-down shared by a `describe`; keep the shared state in a `let` declared in
  the `describe` and assigned in `beforeEach`, never at module level, so tests stay independent.
- **`test.extend`** builds typed fixtures that are created only for the tests that ask for them, with clean-up after `use`:

```ts
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test as base } from "vitest";

export const test = base.extend<{ dir: string }>({
  // eslint-disable-next-line no-empty-pattern -- Vitest reads the fixtures from the destructuring
  dir: async ({}, use) => {
    const dir = await mkdtemp(join(tmpdir(), "acme-"));
    await use(dir);
    // remove `dir` here: close handles, and delete the directory with the project's own helper
  },
});
```

  Tests import `test` from this module instead of `vitest`; a test that lists `{ dir }` in its context gets a fresh directory.
- **`onTestFinished(fn)`** registers a clean-up next to the code that needs it, inside the test.
- **Temporary files** go under `os.tmpdir()` via `mkdtemp`, never into the source tree; a test that writes to a fixed path breaks
  parallel runs. Vitest runs test files in parallel and the tests of one file in order.
- **A global setup** (`setupFiles`) is for registering matchers or a polyfill, not for shared mutable state.

## Test doubles

Prefer a small hand-written fake passed in as an argument (`{ now: () => new Date("2026-01-01T09:00:00") }`) to patching a module.
When the code under test imports a dependency directly, use the mock API:

```ts
import { expect, test, vi } from "vitest";

import { notify } from "./mailer.ts";
import { sendMail } from "./transport.ts";

vi.mock("./transport.ts"); // hoisted above the imports; the module's exports become mocks

test("passes the recipient on", async () => {
  vi.mocked(sendMail).mockResolvedValue("sent");

  await expect(notify("ann")).resolves.toBe("sent");
  expect(sendMail).toHaveBeenCalledWith("ann", "hello");
});
```

- **`vi.fn()`** makes a standalone mock (`vi.fn<() => Promise<string>>()` types it); `mockResolvedValue`, `mockRejectedValueOnce`
  and `mockReturnValue` script it. `vi.spyOn(object, "method")` wraps a real method and keeps the original until you replace it.
- **`vi.mock(path)` must be at the top level of the file** — Vitest 5 throws for a call inside a function, `describe` or
  `test`, because it is hoisted and would not run where written. `vi.doMock` is the non-hoisted variant. A factory
  (`vi.mock(path, () => ({ … }))`) replaces the module; `vi.mock(path, { spy: true })` keeps the implementation but records calls;
  `vi.importActual` / `importOriginal` keep part of the real module. It works for `import`, not for `require`.
- **`vi.mocked(fn)`** gives the mock its type; `vi.hoisted(() => …)` creates values a `vi.mock` factory may use.
- **Mock at the edge** — a database client, an HTTP call, the clock, the filesystem. Never mock the module under test or a pure
  function; assert on results first and on calls only where the call is the behaviour.
- **Environment and globals** — `vi.stubEnv("NAME", "value")` and `vi.stubGlobal("fetch", mock)` are undone by `unstubEnvs` /
  `unstubGlobals` above; assign to `process.env` directly and the change leaks into the next test.
- **Asymmetric matchers type as `any`** — `expect.any(Error)` and `expect.objectContaining({ … })` inside a typed argument trip
  `@typescript-eslint/no-unsafe-assignment`; use `toMatchObject`, `toThrow` or narrow in the test instead of a disable comment.

## Time

```ts
import { afterEach, beforeEach, expect, test, vi } from "vitest";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("debounces", () => {
  const fn = vi.fn();
  const run = debounce(fn, 100);

  run();
  run();
  vi.advanceTimersByTime(100);

  expect(fn).toHaveBeenCalledOnce();
});
```

`vi.setSystemTime(date)` fixes `Date.now()`; since 5.0 fake timers and `setSystemTime` also mock `Temporal`. For promise-based
timers use `await vi.advanceTimersByTimeAsync(ms)`. A real `sleep` in a test is a flaky test.

## Async tests

- Return or `await` every promise; **Vitest 5 fails a test that leaves `expect(…).resolves` / `.rejects` un-awaited**.
  `await expect(promise).rejects.toThrow("message")` is the pattern for an expected failure.
- **Wait for a condition** with `await expect.poll(() => readStatus(), { timeout: 1000 }).toBe("ready")`; since 5.0 it fails when
  the timeout passes and hands the callback an `AbortSignal`. `vi.waitFor` retries a callback until it stops throwing.
- **Cancellation** — pass `AbortSignal.timeout(1000)` to the code under test and assert it rejects with an `AbortError`;
  never rely on the test timeout (default 5 s, `testTimeout`) as the assertion.
- **Concurrency** — `test.concurrent` runs tests of one file together; only for tests with no shared state, and take `expect`
  from the test context (`({ expect }) => …`) inside them, as snapshots need it.
- **Unhandled errors** — a promise rejection nobody awaited fails the run; fix the missing `await`, do not silence it.

## Type tests

`*.test-d.ts` files are checked, not run (`vitest --typecheck`, or `typecheck.enabled` in the config); use them for a library's public
types:

```ts
// src/result.test-d.ts
import { expectTypeOf, test } from "vitest";

import { parsePort } from "./result.ts";

test("parsePort returns a discriminated result", () => {
  expectTypeOf(parsePort).returns.toHaveProperty("ok");
});
```

`expectTypeOf` inside an ordinary runtime test does nothing at run time; `tsc --noEmit` is what evaluates it.

## Coverage

`@vitest/coverage-v8` is the default provider: it needs no instrumentation step and reports as accurately as Istanbul since
Vitest 3.2. Install it as a development dependency with the same version as `vitest`.

- **Thresholds** in `coverage.thresholds` fail the run below the number; set them at the current level and raise them, never to
  an aspirational figure. A glob-pattern threshold needs its own `perFile` (5.0).
- **`include` / `exclude`** match paths relative to the project root; a bare `src` means `src/**` (5.0). Check the file list in
  the report after changing them.
- Coverage shows which lines ran, not whether they were asserted; read the uncovered lines of changed code rather than chasing
  a percentage. `/* v8 ignore next -- @preserve */` hints (the `@preserve` keeps the comment through esbuild's TypeScript transform) are for code that cannot run in a test, with a reason.

## Rules for a good test suite

- Tests are independent and order-free; a test that needs another test to run first is one test.
- No real network, wall clock, random values or shared files without a fake or a fixed seed; no `sleep` to wait for work.
- Assert behaviour and outputs, not implementation details; refactoring the inside should not break a test.
- A bug fix starts with a failing test that reproduces it.
- Failure messages explain themselves: a descriptive name, `toEqual` on the whole value instead of five `toBe` on fields.
- The whole suite stays fast enough to run before every commit; slow tests move to `test/` and their own project.
