# Slice 005 — README Refresh

> Completed: 2026-05-21
> Commits: 0ce9677 (main, no PR)

## What

`README.md` and the two plugin manifests now accurately describe the plugin: the
nine-phase loop (Review visible in the phase list and the Quickstart), correct counts
(20 entry points, 6 universal skills, 28 decisions), the D27 personality system
(Senior-Developer baseline + stack-packs), and an Installation section for the
single-repo-marketplace distribution model.

## Why

- The README is the first-contact document; stale phase / command / decision counts
  undermine trust immediately.
- `plugin.json` and `marketplace.json` carried the same stale `8-phase` strings —
  folded into this slice (with user approval) rather than spun off, so the `8 → 9`
  cleanup is repo-wide, not half-done.
- The old `git clone … ~/.claude/plugins/craft` install no longer matches reality;
  the Installation section was rewritten for the marketplace distribution model.

## Decisions

- **Scope expansion (Phase 4)** — `plugin.json` and `marketplace.json` carried the
  same stale `8-phase` strings; with user approval (Level 1) the manifest fix was
  folded into slice-005 rather than spun off — the same `8 → 9` cleanup as the README
  work, kept repo-wide-consistent.

## Commits

- `0ce9677` — docs: refresh README and manifests for the 9-phase model

## Follow-ups

(none)
