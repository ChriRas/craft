# pytest 9 — Test Patterns

pytest 9 reads its configuration from a `[tool.pytest]` table in `pyproject.toml` with native TOML types (new in 9.0; the
older `[tool.pytest.ini_options]` table with string values still works and is what a project on pytest 8 or lower uses —
follow `SKILL.md` → `## Existing Projects`). A test is a plain function whose name starts with `test_` and that uses
bare `assert`; pytest rewrites the assertion to show both sides.

## Layout and configuration

`tests/` mirrors `src/<package>/`: `src/acme_tool/core.py` is tested by `tests/test_core.py`, deeper trees by
`tests/<subpackage>/test_<module>.py`. Shared fixtures live in the nearest `conftest.py`. pytest's guidance for new projects
with a `src` layout is the `importlib` import mode, which needs no `__init__.py` files in `tests/`:

```toml
# pyproject.toml
[tool.pytest]
minversion = "9.0"
strict = true                       # config, markers, parametrize ids and xfail are checked strictly
testpaths = ["tests"]
addopts = ["-ra", "--import-mode=importlib"]
filterwarnings = ["error"]          # a warning in the code under test fails the run
markers = [
    "slow: tests that take more than a second",
    "integration: tests that touch a real database or network",
]
```

- `strict = true` enables `strict_config`, `strict_markers`, `strict_parametrization_ids` and `strict_xfail`, and pytest may add
  further strict options in later releases — it is safe with a locked pytest (`uv.lock`), which a uv project has.
- The package is installed into the environment by `uv sync` (the build system is declared), so tests import
  `acme_tool` as a user would. Without an installed package use `pythonpath = ["src"]` in the same table.
- Run `uv run pytest`; narrow with `-k "name"`, `-x` (stop at first failure), `--lf` (last failed), `-m "not slow"`.
  `python -m pytest` also puts the current directory on `sys.path`, which matters only for a flat layout.

## Writing a test

```python
from decimal import Decimal

import pytest

from acme_tool.core import InvoiceLine, parse_line, total


def test_total_sums_line_amounts() -> None:
    lines = [InvoiceLine("a", Decimal("1.50")), InvoiceLine("b", Decimal("2.25"))]

    assert total(lines) == Decimal("3.75")


def test_total_of_nothing_is_zero() -> None:
    assert total([]) == Decimal(0)


def test_parse_rejects_negative_amount() -> None:
    with pytest.raises(ValueError, match="negative"):
        parse_line("a;-1")
```

- One behaviour per test, named for it; arrange, act, assert in that order.
- `pytest.raises(Type, match=regex)` for expected exceptions — always `match`, so another error of the same class does
  not pass; use `excinfo.value` for attributes. `pytest.warns` and `pytest.approx(…)` (floats) are the siblings.
- Annotate tests with `-> None` so `mypy --strict` accepts the test code too; fixtures are annotated with their yielded type.

## Fixtures

```python
# tests/conftest.py
from collections.abc import Iterator
from pathlib import Path

import pytest

from acme_tool.store import Store


@pytest.fixture
def store(tmp_path: Path) -> Iterator[Store]:
    s = Store(tmp_path / "data.db")
    yield s  # the test runs here
    s.close()  # teardown runs even when the test failed
```

- A fixture is requested by naming it as a parameter. Its **scope** defaults to `function`; widen it (`scope="module"` or
  `"session"`) only for something expensive and read-only, never for state a test changes.
- `yield` fixtures put teardown after the `yield`; prefer them over `request.addfinalizer`.
- Built-ins to use before inventing anything: `tmp_path` (a `pathlib.Path` per test), `monkeypatch`, `capsys` and `capfd`
  (captured output), `caplog` (log records), `request`. `monkeypatch.setenv("NAME", "value")` and `monkeypatch.setattr(obj, "name", value)`
  are undone after the test.
- `autouse=True` is for a cross-cutting guard (for example blocking the network), not for setup a test depends on.
- A factory fixture returns a function (`def make_invoice(**overrides): …`) when a test needs several slightly different objects.

## Parametrisation

```python
@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("1", Decimal(1)),
        ("1.50", Decimal("1.50")),
        pytest.param("", None, id="empty"),
        pytest.param("x", None, marks=pytest.mark.xfail(reason="parser rewrite"), id="garbage"),
    ],
)
def test_parse_amount(raw: str, expected: Decimal | None) -> None:
    assert parse_amount(raw) == expected
```

- Table-driven cases replace copy-pasted tests; `pytest.param(..., id=…)` names the unreadable ones, and a case-specific
  `marks=` skips or expects a failure for that case only. With `strict`, duplicate generated ids are an error.
- Stack `parametrize` decorators for a cross product. Parametrise a fixture (`@pytest.fixture(params=[...])`) when a whole
  set of tests must run against several implementations of one interface.
- A property that holds for all inputs is a better test than twenty examples — Hypothesis (`@given(...)`, 6.170 on 2026-11-11)
  generates them; add it to the `dev` group when a parser, serializer or algorithm warrants it.

## Test doubles

- **Prefer a fake over a mock** — a small in-memory class that satisfies the `Protocol` the code depends on. It survives
  refactoring; a mock that asserts call details breaks with every internal change.
- **`unittest.mock`** (or the `mocker` fixture of pytest-mock) for the boundary you cannot fake. Use `autospec=True` or
  `create_autospec(Class, instance=True)` so a call with the wrong signature, or a method the real class lacks, fails the test.
- **Patch where the name is looked up**, not where it is defined: `mocker.patch("acme_tool.cli.convert")`, not
  `mocker.patch("acme_tool.core.convert")`, when `cli` did `from acme_tool.core import convert`.
- Replace the clock, randomness and the environment through arguments or fixtures (`monkeypatch.setenv`), not by patching
  `datetime` itself. A function that takes `now: Callable[[], datetime]` needs no patching at all.
- Never mock a value object or a dataclass; construct it. Never mock the thing under test.

## Async tests

pytest-asyncio runs `async def` tests in an event loop. The default mode is `strict`: mark each test with
`@pytest.mark.asyncio` and declare async fixtures with `@pytest_asyncio.fixture`. `asyncio_mode = "auto"` in the pytest
table marks every `async def` test automatically — pick it for a project that is async throughout.

```python
import pytest

from acme_tool.client import Transport, fetch_all


@pytest.mark.asyncio
async def test_fetch_all_collects_results(fake_transport: Transport) -> None:
    results = await fetch_all(["a", "b"], transport=fake_transport)

    assert [r.key for r in results] == ["a", "b"]
```

- Add `asyncio_default_fixture_loop_scope = "function"` to the `[tool.pytest]` table together with pytest-asyncio: without it
  the plugin warns at startup, and `filterwarnings = ["error"]` turns that warning into an internal error that stops the whole
  run (checked with pytest 9.2 and pytest-asyncio 1.4.1). Add it only once the plugin is installed — the key is unknown to
  pytest before that, and `strict` rejects unknown keys.
- Fake the transport, not the event loop. Bound every await in a test with `asyncio.timeout(...)` so a hang fails fast.
- Tests that share a loop declare it with `@pytest.mark.asyncio(loop_scope="module")`; the default is one loop per test.

## Coverage

```bash
uv run pytest --cov=acme_tool --cov-branch --cov-report=term-missing
uv run pytest --cov=acme_tool --cov-fail-under=90      # in CI, with the threshold the project agreed on
```

pytest-cov wraps coverage.py; `term-missing` lists the uncovered lines, `--cov-branch` measures branches. Read coverage as a
map of untested code, not as a target: a test that exists only to execute lines proves nothing.

## Rules for a good test suite

- Tests are independent and order-free: no shared mutable state, no reliance on another test having run.
- No network, no wall clock, no `sleep`, no real home directory: `tmp_path`, fakes and injected clocks instead. A test that
  needs a real service carries `@pytest.mark.integration` and runs in its own CI job.
- A bug fix starts with a failing regression test that names the bug; fix; keep the test.
- Test through the public interface. Testing a private function is a sign it wants to be a public function of a small module.
- The suite is fast enough to run before every commit; a slow test gets `@pytest.mark.slow` and a reason.
