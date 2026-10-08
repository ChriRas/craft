# Slice 071 — cache-guard-150k

> Completed: 2026-10-08
> Commits: 3e5d100..2bdd533 (branch only — epic-005-comfort-and-flow, no PR)

## What

The cache guard's recache threshold and Phase 4's context-discipline guideline both rise from 100k to 150k tokens: the
hook blocks a cold prompt only from 150000 tokens on (149999 passes, 150000 blocks), and Phase 4 now says "under ~150k
tokens".

## Why

- A cold prompt cache re-writes the whole context at full price; a restart is only cheaper once that re-write is large
  enough. The human chose to raise both 100k limits together.
- Existing project profiles are deliberately not rewritten: an explicit `Cache-guard-recache-tokens: 100000` is the
  human's durable state, so the CHANGELOG upgrade note tells them to raise or delete it.

## Decisions

- **Both 100k limits rise** (2026-10-08, human choice) — the request "Tokengrenze 100000 → 150000" matched two sites:
  the cache guard's `Cache-guard-recache-tokens` (a hard, harness-bound value) and Phase 4's "~100k tokens"
  context-discipline guideline (prose). The human chose both.
- **Existing project profiles are not rewritten** (2026-10-08, human confirmed) — a profile created from an older
  template carries an explicit `Cache-guard-recache-tokens: 100000` and keeps it; the profile is the human's durable
  state (rules.md: no silent mutation). The CHANGELOG's upgrade note tells them to raise or delete the line. A
  `/craft:prime` hint for an explicit 100000 was offered and declined.
- Phase 7 skipped (project rule)

## Commits

- `3e5d100` — feat(workflow): raise Phase 4's context guideline to ~150k tokens
- `f0a8f86` — feat(cache-guard): raise the recache threshold default to 150000
- `2bdd533` — docs(cache-guard): record the 150000 default in the docs page, design record and changelog
