# Python project patterns — uv, pyproject.toml, packaging, CLIs

## Project layout

`uv init` writes a `src` layout and a build system, for an application and for a library (`--lib`, which also adds the
`py.typed` marker). The package sits under `src/`, the tests beside it, never inside the package:

```text
acme-tool/
├── .python-version          # the interpreter uv uses, e.g. 3.14
├── pyproject.toml           # metadata, dependencies, tool configuration
├── uv.lock                  # exact versions, committed
├── README.md
├── src/
│   └── acme_tool/
│       ├── __init__.py
│       ├── __main__.py      # python -m acme_tool
│       ├── cli.py           # argument parsing, exit codes
│       ├── core.py          # pure logic
│       └── py.typed         # libraries only
└── tests/
    ├── conftest.py
    └── test_core.py
```

The `src` layout keeps an uninstalled copy of the package out of the import path, so a test imports what an installed
user would get, and a missing file in the wheel shows up in the tests. Use `--no-package` (`uv init --no-package`) only for
a loose script collection that is never installed; its modules then sit in the project root.

## uv in daily use

| Task | Command |
|---|---|
| New application / library | `uv init acme-tool` · `uv init --lib acme-lib` |
| Pin or install an interpreter | `uv python pin 3.14` · `uv python install 3.14` |
| Add / remove a dependency | `uv add httpx` · `uv remove httpx` |
| Development tools | `uv add --dev pytest` · `uv add --group lint ruff` |
| Optional extra of a library | `uv add pyyaml --optional yaml` |
| Lock / upgrade one package | `uv lock` · `uv lock --upgrade-package httpx` |
| Create or refresh `.venv` | `uv sync` (`--no-dev` drops the dev group) |
| Run in the project | `uv run pytest` · `uv run acme-tool --help` |
| CI: fail when the lock is stale | `uv lock --check` · `uv run --locked pytest` |
| Build distributions | `uv build` (into `dist/`) · `uv publish` |
| One-off tool, no install | `uvx ruff check` (same as `uv tool run`) |

- `uv run` locks and syncs first, so the environment always matches `pyproject.toml`; `--locked` turns a stale lock into
  an error and `--frozen` uses the lock as it is. A fresh clone is `uv sync`, then `uv run …`.
- `uv.lock` is committed for an application and for a library's own development; it is not what consumers of a library
  install, so a library's `dependencies` carry ranges (`httpx>=0.28`), an application's exact needs come from the lock.
- Never edit `uv.lock` by hand. Tools that only read a `requirements.txt` get one from `uv export --format requirements.txt`.
- uv installs and manages interpreters itself (`uv python install`); a project that wants a system Python says so in its
  own docs, it is not this pack's default.
- Ruff, mypy and pytest are development dependencies of the project (`uv add --dev ruff mypy pytest`), so a clone and CI
  use the locked versions; `uvx` is for a tool the project does not depend on.

## pyproject.toml

```toml
[project]
name = "acme-tool"
version = "0.1.0"
description = "Converts invoices to ledger entries."
readme = "README.md"
license = "MIT"                      # an SPDX expression (PEP 639), not a table
requires-python = ">=3.12"
dependencies = [
    "httpx>=0.28",
]

[project.optional-dependencies]
yaml = ["pyyaml"]

[project.scripts]
acme-tool = "acme_tool.cli:main"

[dependency-groups]
dev = ["pytest>=9", "pytest-cov", "mypy", "ruff"]

[build-system]
requires = ["uv_build>=0.13.7,<0.14"]
build-backend = "uv_build"
```

- **`[project]`** is the standard metadata table; `name`, `version` and `requires-python` are the ones tools rely on. The
  license is an SPDX expression in `license` plus `license-files` globs; the old `license = { text = … }` table is the
  superseded form.
- **`requires-python`** is the floor the code is written for; Ruff infers its `target-version` from it and `uv lock` resolves
  for every Python it admits. Raise it deliberately, in a slice of its own.
- **`[dependency-groups]`** (PEP 735) holds development-only requirements that never reach the built package; the `dev`
  group is installed by default. `[project.optional-dependencies]` are extras a consumer can ask for.
- **Build backend** — `uv_build` for pure-Python code in the default layout (the `uv init` default; it supports pure Python
  only). `hatchling` (or `setuptools`) when the build needs more, a Rust or C extension needs `maturin` or
  `scikit-build-core` (`uv init --build-backend …`). Pin the backend's range as above.
- **Tool tables** — `[tool.ruff]`, `[tool.mypy]` and `[tool.pytest]` live in the same file (see the other references), so
  one file configures the whole project.

## Entry points and CLIs

`[project.scripts]` creates a console command from a function. The function parses, calls the logic and returns an exit
code; the thin wrapper turns it into the process status, so tests call `main([...])` directly.

```python
# src/acme_tool/cli.py
import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from acme_tool.core import convert


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="acme-tool", description="Convert invoices.")
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", "-o", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        convert(args.source, args.output)
    except FileNotFoundError as exc:
        print(f"acme-tool: {exc}", file=sys.stderr)
        return 2
    return 0
```

```python
# src/acme_tool/__main__.py
from acme_tool.cli import main

raise SystemExit(main())
```

- **argparse** is in the standard library and enough for most tools. **Click** (8.5) and **Typer** (0.29, type-hint driven)
  give sub-commands, prompts and completion with less code; add one when the CLI has several sub-commands, not for one flag.
- The CLI layer parses, validates and prints; domain code never reads `sys.argv`, calls `print` or `sys.exit`.
- Exit codes: `0` success, `1` a runtime failure, `2` a usage error (argparse's own); document any others.
- Environment variables and config files are read once in `main()` (`os.environ`, `tomllib.load` for a TOML file, 3.11) and
  passed on as a frozen dataclass of typed values.

## Scripts with inline metadata

A single-file script that needs packages declares them in a comment block (PEP 723); `uv run script.py` builds a throwaway
environment for it, outside any project:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx"]
# ///
import httpx

print(httpx.get("https://example.org").status_code)
```

`uv init --script example.py` creates the block, `uv add --script example.py httpx` edits it. Once a script grows a second
module or a test, it becomes a project (`uv init`).

## Dependencies and releases

- Add a dependency only with a reason; prefer the standard library (`pathlib`, `argparse`, `tomllib`, `logging`,
  `dataclasses`, `zoneinfo`, `urllib`) for small jobs. A new third-party dependency is named in the slice and its licence
  and maintenance state are looked at.
- Constraints: a library gives lower bounds (`>=`) and an upper bound only where a breaking release is known; an application
  leaves ranges loose and lets `uv.lock` pin. No `*`, no unpinned VCS URL in a release.
- Upgrade on purpose: `uv lock --upgrade-package <name>` in its own commit, with the tests run; a bulk `uv lock --upgrade`
  is a separate slice.
- `uv version` shows the project version; the version lives in `[project]` and is changed there or with `uv version`
  (`uv version --short` prints just the number). Tag the release commit; `uv build` then `uv publish` ship it.
- CI: install uv (`astral-sh/setup-uv`), then `uv sync --locked` (or `uv run --locked …`), `uv run ruff check`,
  `uv run ruff format --check`, `uv run mypy`, `uv run pytest`. Pin the action to a commit.

## Python version policy

- A new application pins the newest stable interpreter in `.python-version` (3.14 or 3.15 on 2026-11-11); a library's
  `requires-python` floor is the oldest branch still in security support (3.11 until October 2027) unless its users need
  less.
- Test a library on every Python it admits (a CI matrix of `uv run --python 3.11 pytest`, one per version); an application
  runs on the one version it ships on.
- A branch that reached end-of-life (3.10 on 2026-10-01) is not a target for new code; an existing project that still
  declares it is told so, and the move is a decision, not a side effect.
