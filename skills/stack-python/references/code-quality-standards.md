# Python 3.11 to 3.15 — Code Quality Standards

## Mandatory shape

A module is typed, small and importable without side effects. Four-space indent, a line length from `[tool.ruff]` (88 is
Ruff's default), double quotes as `ruff format` writes them, imports sorted by Ruff. Everything runnable lives in a function;
the entry point only calls it.

```python
"""Invoice totals."""

from __future__ import annotations  # not needed on 3.14+; keep only for a lower floor

from collections.abc import Iterable
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True, slots=True)
class InvoiceLine:
    description: str
    amount: Decimal


def total(lines: Iterable[InvoiceLine]) -> Decimal:
    return sum((line.amount for line in lines), start=Decimal(0))
```

## Language idioms

Use what the project's `requires-python` allows (`## Existing Projects` in `SKILL.md`).

- **Types** — an annotation on every parameter and return value. Take the widest useful input (`Iterable`, `Mapping`,
  `Sequence` from `collections.abc`), return a concrete type. Built-in generics (`list[int]`, `dict[str, int]`) and
  `X | None` replace `typing.List` and `Optional`.
- **Data** — `@dataclass(frozen=True, slots=True)` for a value, `NamedTuple` for a small tuple, `TypedDict` for a dict that
  crosses a JSON boundary, `enum.StrEnum` (3.11) for a closed set of strings. A `__post_init__` validates; a frozen class
  is copied with `dataclasses.replace`. 3.15 adds a `frozendict` built-in and a `sentinel` type for "no value passed".
- **Generics (3.12)** — `def first[T](items: Sequence[T]) -> T:` and `type Pair[T] = tuple[T, T]` replace `TypeVar` and
  `TypeAlias`; 3.13 adds defaults for type parameters. On a lower floor use `TypeVar` and a plain alias.
- **Protocols** — a `typing.Protocol` names the few methods a consumer needs, so an adapter and a test double both satisfy
  it without inheriting. `@typing.override` (3.12) marks an intended override; mypy then reports a rename on the base.
- **Narrowing** — `isinstance`, `match` with class and mapping patterns, and `typing.TypeIs` (3.13) for a user-defined
  guard. `typing.assert_never(x)` closes an exhaustive `match` over an enum or union so mypy reports a missed case.
- **Paths and text** — `pathlib.Path` instead of `os.path`; `Path.read_text(encoding="utf-8")`. Python 3.15 makes UTF-8 the
  default encoding, but a project that still runs on 3.14 or lower, or another platform's default, needs it spelled out.
- **Iteration** — comprehensions and generator expressions for transformations, `enumerate`, `zip(..., strict=True)` (3.10)
  when lengths must match, `itertools.batched` (3.12) for chunks. 3.15 adds unpacking in comprehensions.
- **Resources** — `with` for every file, lock, connection and temporary directory; `contextlib.contextmanager` or
  `ExitStack` for your own. Never rely on garbage collection to close.
- **Startup cost (3.15)** — `lazy import heavy_module` defers an import to first use; worth it for a CLI that imports a large
  dependency only on one sub-command. Not usable on a lower floor.
- **Deprecation** — `warnings.deprecated("use new_name")` (3.13) marks a function or class; type checkers report callers.

## Error handling

- **Specific exceptions** — catch the narrowest class, around the narrowest block. A library defines one base exception
  (`class AcmeError(Exception)`) and subclasses; never raise a bare `Exception`, never use a string as an error signal.
- **Chain** — `raise DomainError("...") from exc` when translating; `from None` only to hide a truly irrelevant cause.
  Keep the traceback: `logger.exception(...)` inside `except`, never `print(e)`.
- **No silent swallow** — no `except:` or `except Exception: pass`. A deliberate ignore is `contextlib.suppress(FileNotFoundError)`
  with the narrowest class. Ruff's default set flags the bare forms (`E722`, `BLE001`, `S110`).
- **Exception groups (3.11)** — `except*` handles members of an `ExceptionGroup` raised by `asyncio.TaskGroup` or by your own
  code that collects several failures. 3.14 allows `except A, B:` without brackets (PEP 758), but only when there is no `as`
  clause — keep the bracketed form in code that still runs on a lower floor.
- **`finally`** — release resources there; do not `return`, `break` or `continue` out of it (3.14, PEP 765, warns).
- **Boundaries** — validate input once where it enters (CLI arguments, a file, an HTTP response) and convert to typed
  values; inner code trusts its types. An unexpected exception in `main()` becomes an error message and a non-zero exit
  code, not a traceback shown to a user — except in debug mode.
- **Resources and cancellation** — in `async` code let `asyncio.CancelledError` propagate after clean-up; it subclasses
  `BaseException`, and `TaskGroup` and `asyncio.timeout()` rely on it.

## Async basics

- **Entry** — one `asyncio.run(main())` at the program edge; library code exposes `async def` functions and never starts a loop.
- **Concurrency** — `async with asyncio.TaskGroup() as tg: tg.create_task(...)` (3.11) for work that runs together: a failure
  cancels its siblings and surfaces as an `ExceptionGroup`. `asyncio.gather` is for the case where partial results matter.
  A task started with `asyncio.create_task` needs a stored reference, or it can be collected mid-flight.
- **Deadlines** — `async with asyncio.timeout(seconds):` around a call that can hang; never an unbounded network await.
- **Blocking work** — `await asyncio.to_thread(func, *args)` for blocking I/O or CPU-light calls; a `ProcessPoolExecutor`
  for CPU-heavy work. A `time.sleep`, `requests.get` or plain file read inside `async def` stalls every task (Ruff's `ASYNC2xx`
  rules report these).
- **Shared state** — pass data through arguments, `asyncio.Queue` or a lock held for a short block; no module globals
  mutated by several tasks. An async context manager owns each connection or session.
- **Do not mix** — a sync function that must call async code gets a thin `asyncio.run` wrapper at the top, never one nested
  inside a running loop. Decide per module whether it is sync or async.

## Logging and output

- A library uses `logger = logging.getLogger(__name__)` and never configures handlers; the application configures logging
  once in its entry point. Messages use lazy formatting: `logger.info("loaded %s rows", count)`.
- A CLI writes results to stdout and diagnostics to stderr, and returns a meaningful exit code. `print` is for the CLI's output,
  not for diagnostics (`T20` in Ruff reports stray ones).

## Configuration: Ruff and mypy

```toml
# pyproject.toml
[tool.ruff]
line-length = 100                 # Ruff's default is 88

[tool.ruff.lint]
extend-select = ["ARG", "T20"]    # on top of the default set; add one group at a time

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["ARG"]
"src/acme_tool/cli.py" = ["T20"]

[tool.mypy]
python_version = "3.12"         # the same floor as requires-python
strict = true
warn_unreachable = true
files = ["src", "tests"]

[[tool.mypy.overrides]]
module = ["untyped_vendor_lib.*"]
ignore_missing_imports = true
```

- **Ruff** — `target-version` is inferred from `requires-python`. Since 0.16 the default rule set is broad (413 rules in 0.16, about 400 since 0.17; isort
  `I001`, pyupgrade `UP`, bugbear `B`, `PT`, `SIM`, `RUF` subsets), so add with `extend-select` instead of replacing it with
  `select`, and never `select = ["ALL"]`: every release adds rules. Ruff's minor versions can change defaults, so it is pinned
  by `uv.lock`. `ruff check --fix` applies safe fixes; unsafe fixes need `--unsafe-fixes`, read the diff first.
  `ruff format` also formats Python code blocks inside Markdown files.
- **Suppress narrowly** — `# ruff: ignore[CODE]` (or `# noqa: CODE`) on the line, with a reason, never a blanket
  `# noqa`. For mypy `# type: ignore[error-code]` with a code; `warn_unused_ignores` (part of `strict`) removes stale ones.
- **mypy** — `strict = true` for new code. Adopt in an old codebase per module: start with the default, then add
  `[[tool.mypy.overrides]]` blocks with `disallow_untyped_defs = true` for the modules already clean. mypy 2 enables
  `--local-partial-types` and `--strict-bytes` by default and supports parallel checking. A third-party package without
  types gets a stub package (`types-…`) first, `ignore_missing_imports` for its module only as a last resort.
- **Typed package** — a library that ships types has an empty `py.typed` file inside the package (`uv init --lib` creates it).

## Code-quality checklist

- [ ] Every function signature is annotated; `mypy` is clean without new `# type: ignore`.
- [ ] `ruff check` and `ruff format --check` are clean; no rule disabled project-wide to make a slice pass.
- [ ] No module does work at import time except defining names; no mutable module-level state.
- [ ] Every `except` names a class; every `raise` in an `except` block chains with `from`.
- [ ] Time, randomness, environment and the filesystem enter through arguments or small adapters.
- [ ] Public names have docstrings that say what, not how; internals start with `_`.
- [ ] No `print`, `pdb`, commented-out code or TODO without an owner left behind.
