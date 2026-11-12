# Slice 089 — stack-python

> Completed: 2026-11-11
> Commits: 5d3349b..8d7d115 (on epic-006-stack-packs, no PR) · epic-006 entry `stack-python`

## What

A project that declares `Stack-Pack: stack-python` now gets a plugin-shipped pack for plain Python (no web framework):
`skills/stack-python/SKILL.md` plus three references (code quality, project patterns, test patterns), satisfying the
stack-pack contract. The code-near phases load it instead of printing the "declared but not found" line, and the docs site,
README and CHANGELOG name the new pack (13 skills, 7 stack-packs).

## Why

- D43 wants every stack in `/craft:onboard`'s detection table backed by a researched, dated and sourced pack; the table
  already proposed `stack-python` for `pyproject.toml` / `requirements.txt`.
- uv + Ruff + `pyproject.toml` as the modern default and pytest for tests (user), plain Python only (Django / FastAPI would be
  packs of their own), and the slice-092 rule that an existing project's toolchain wins — hence nine `## Existing Projects`
  entries. The type checker was left to research: mypy 2.4 with `strict = true` is the default because ty is still beta
  (0.0.x) and Pyrefly / Pyright are a project's own choice. Ruff 0.16 expanded its default rule set from 59 to 413 rules, so
  the pack says to extend the defaults rather than replace them.

## Walk-through

1. Research (2026-11-11, primary sources): Python support window and release notes, PyPI versions, uv, Ruff (changelogs and
   default rules), mypy, ty, Pyrefly, pytest 9 (native `[tool.pytest]`, `strict`), pytest-cov / -asyncio, the packaging
   specs, and the commands of pip-tools, Poetry, Pipenv, Black, Flake8, isort and unittest named in `## Existing Projects`.
2. `SKILL.md` from the template (120 lines): Stack, nine Existing Projects entries, Reference Files, Build Order,
   Anti-Patterns, and 16 https source lines (`Basis: research`).
3. References: `code-quality-standards.md` (141 lines), `project-patterns.md` (183), `test-patterns.md` (171).
4. Wiring: docs badge and counts, the two architecture paragraphs and the Tier-2 card (DE/EN), the README inventory lines,
   and the CHANGELOG entry.
5. Evidence: `verify-run.sh` passed 4 of 4 in run 1 and again in run 2 after the review fixes. Phase 8: one round, one Heavy
   (`filterwarnings = ["error"]` crashed pytest with pytest-asyncio's startup warning — the pack now pairs it with
   `asyncio_default_fixture_loop_scope = "function"`) and eight Light findings, all fixed in-phase; the fix cap (5) was
   exceeded by four small one-file fixes.

## Decisions

- **Tooling: modern — uv + Ruff (user, 2026-11-09).** uv for projects, dependencies and Python versions; Ruff for lint
  and format; `pyproject.toml` as the one configuration. Which type checker the pack recommends (mypy or a successor) is
  decided by the build's verified research, not recalled — the Python tooling landscape has moved fast.
- **Scope: plain Python (user)** — libraries, CLIs, scripts and services without a web framework. Django and FastAPI would
  be packs of their own (D27, as `stack-ts` leaves frontend frameworks out).
- **Tests: pytest (user).**
- **Depends on slice-092 (and through it slice-083) (user).** Python needs nothing from the PHP chain; the epic's sequential order (shared docs
  lines) still lands it after the PHP packs.
- **Content review brief for Phase 5 (build, 2026-11-11).** What the pack says, to read against its `## Sources` (16 source lines, every claim dated 2026-11-11 from primary docs): (1) **Type checker = mypy 2.4 with `strict = true`** as the default, decided by research: mypy is the stable reference checker; ty is still beta (0.0.x versioning, breaking changes may occur between any two versions), Pyrefly 1.4 and Pyright are named in `## Existing Projects` as a project's own choice, not as the pack's default. (2) **Ruff 0.17**: since 0.16 (2026-07-23) the default rule set is 413 rules (up from 59) and already includes isort (`I001`), so the pack says "extend, do not `select = ALL`". (3) **Python window**: 3.15 and 3.14 bugfix, 3.13/3.12/3.11 security, 3.10 end-of-life since 2026-10-01; new code on 3.14+. (4) **uv 0.13**: `uv init` gives a src layout with `uv_build` (pure Python only) for applications and libraries alike; dependency groups (PEP 735). (5) **pytest 9**: native `[tool.pytest]` TOML with `strict = true` (9.0), `importlib` import mode for new projects. (6) `## Existing Projects` has 9 entries (pip+venv, pip-tools, Poetry, Pipenv, setup.py/setup.cfg, Black/Flake8/isort, other type checkers, unittest, older Python). Not verified by a run: no command in the pack was executed against a real project (command facts are read from each tool's current docs); the `pyright` version is the PyPI wrapper's, and `coverage.py`'s own version was not read (pytest-cov only).
- **Existing projects (slice-092, user, 2026-11-09).** The pack carries the contract's `## Existing Projects` section: pip + venv with `requirements*.txt`, pip-tools (`requirements.in` / compiled `requirements.txt`), Poetry, Pipenv, `setup.py` / `setup.cfg`; Black / Flake8 / isort instead of Ruff; unittest instead of pytest — how to recognise each, and its commands for adding a dependency, locking, creating the environment and running the tests. The rule itself (the project's toolchain wins, never migrate unasked) is the baseline's, not repeated here.
- Phase 7 skipped (project rule)


## Commits

- `5d3349b` — feat(skills): add the stack-python pack
- `8d7d115` — docs: wire stack-python into the docs site, README and changelog
