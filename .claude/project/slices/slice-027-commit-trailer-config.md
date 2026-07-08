# Slice 027 — Commit trailer config (Co-Authored-By)

> Completed: 2026-07-08
> Commits: 0b957af..ec498ff (branch main, trunk-based)

## What

Consumer projects can now opt into a `Co-Authored-By` commit trailer via their CRAFT profile — a
per-project setting that didn't exist before. The profile's `## Commit Policy` block carries
`Co-Authored-By: on | off` (default `off`), `/craft:onboard` asks about it during setup, and
`/craft:commit` appends the fixed literal trailer `Co-Authored-By: Claude <noreply@anthropic.com>`
to every commit only when it's `on`. Previously `/craft:commit` had no notion of the trailer at
all — "no trailer" was an unwritten convention each project followed by hand. Roadmap item B2.

## Why

- **Fixed trailer, not a configurable string** — a simple on/off toggle appending one literal,
  model-agnostic trailer, chosen over arbitrary per-project co-author identities (which would have
  ballooned the slice: onboard prompting for free-form text, commit/validate handling multi-line
  trailers). The identity string is a captured, changeable decision.
- **Default off, recommend off** — a consumer-project opt-in; off-by-default means CRAFT's own repo
  (no profile) behaves exactly as its `rules.md` demands — no trailer — with zero special-casing.
- **Field home in `## Commit Policy`** — next to `Auto-commit`, the block `/craft:commit` already
  consumes and `/craft:prime` already reports.

## Decisions

- **Fixed default trailer, not a configurable string** — the field is a `Co-Authored-By: on | off`
  toggle; when `on`, `/craft:commit` appends the single literal
  `Co-Authored-By: Claude <noreply@anthropic.com>`. *Why not configurable*: keeps the slice
  minimal; the identity string is a captured decision changeable later; free-form / multi-author
  trailers are YAGNI for now.
- **Default off, recommend off** — consumer-project opt-in; CRAFT's own repo keeps no profile, so
  the default `off` applies and stays consistent with its `rules.md` "No Co-Authored-By trailer"
  (this slice does not touch this repo's `rules.md`).
- **Field lives in `## Commit Policy`** — alongside `Auto-commit`, consumed by `/craft:commit`,
  reported by `/craft:prime` step 4d (which enum-validates it and appends a `+coauthored-by` suffix
  to its profile line when enabled).
- **Phase 7 skipped** — per the project rule dropping Refactor for this Markdown-authoring repo.

## Commits

- `0b957af` — feat(commit): profile-configurable Co-Authored-By trailer
- `ec498ff` — chore(plans): bump slice counter to 28

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review. Each is a candidate for a future slice.

- (none — the single Phase-8 finding was a Local cosmetic edit, fixed in-phase)
