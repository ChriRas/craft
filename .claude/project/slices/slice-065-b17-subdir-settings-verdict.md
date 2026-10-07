# Slice 065 — b17-subdir-settings-verdict

> Completed: 2026-10-07
> Commits: 2bf5d9e..c17d890 (branch only — epic-004-roadmap-fixes, no PR)

## What

In a project that sits in a subdirectory of its git repository, `ensure-readonly-context.sh` and `ensure-worktree-trust.sh` now print the `GITIGNORED=` verdict for the file they actually read and write, `<repo-root>/.claude/settings.local.json`, instead of the project-dir one. `/craft:execute`'s `GITIGNORED=no` warning names that file and a fix that covers it.

## Why

- Claude Code (>= 2.1.211) keeps `settings.local.json` at the repository root, so the helpers' write target was right and the project-dir verdict was the defect (B17).
- The verdict is asked from the `REPO_ROOT` each helper already computes, so the path written and the path judged come from one variable and `ensure-gitignore.sh` stays unchanged.
- The `GITIGNORED=no` line was reworded because `/craft:prime` 4f's project-anchored block cannot cover the repo-root file in a subdirectory project.

## Decisions

- **The write target stays at the repository root. Only the report moves** — the Claude Code settings docs (fetched 2026-10-07; CLI 2.1.292) say a session started in a subdirectory reads and writes `.claude/settings.local.json` at the repository root (since v2.1.211). *Why not* moving the write: it would break trust for current Claude Code.
- **Verdict asked from `REPO_ROOT`, not by a `../` path from the project dir** — one variable for the path written and the path judged; `ensure-gitignore.sh` unchanged. *Why not* `--verdict ../.claude/settings.local.json`: it needs the subdirectory's depth and a `..` path through `git check-ignore`.
- **The execute `⚠` line is reworded, without a new output key** — after the fix a subdirectory project usually reads `no`, and prime's old advice would change nothing there. *Why not* a `SETTINGS_SCOPE=` / `SETTINGS_FILE=` key: it widens both helpers' output contract and makes the master compare paths in prose.
- **Out of scope, observed while planning:** (1) `ensure-gitignore.sh`'s CRAFT path is anchored to the project dir, so in a subdirectory project `/craft:prime` 4f and `/craft:onboard` cover a file Claude Code ≥ 2.1.211 no longer uses; (2) `ensure-readonly-context.sh` reads `rules.md` from `<repo-root>`, the guard from `<project>`; (3) in a linked git worktree Claude Code uses the main checkout's root settings file, the helpers take the worktree root.
- **`Depends-On: []`** — no sibling touches the two helpers, their harness section or execute's worktree-trust step.
- **Plan gate `[R]` revision** — no `CHANGELOG.md` line (the 2.0.0 cut writes them), a roadmap sub-task closes B17, the builder leaves `rules.md` alone.
- **Optional `rules.md` wording, for the Epic-close walk (not applied):** change *"(read-only guard + sync helper, incl. the guard↔helper normalizer agreement)"* to *"(read-only guard + sync helper, incl. the guard↔helper normalizer agreement and the settings helpers' `GITIGNORED=` verdict for the repository-root `settings.local.json`, also in a subdirectory project)"*.
- Phase 7 skipped (project rule)
- **Durable Capture:** nothing cross-cutting enough for `.claude/project/design/`.

## Commits

- `2bf5d9e` — fix(settings): judge the repo-root settings.local.json in subdirectory projects
- `c17d890` — docs(roadmap): close B17 and extend the readonly-context harness note
