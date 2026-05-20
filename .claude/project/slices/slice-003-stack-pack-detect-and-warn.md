# Slice 003 — Stack-Pack Detection & Missing-Pack Warning

> Completed: 2026-05-20
> Commits: cccfe12 (main, no PR)

## What

`/craft:onboard` now detects a project's stack from its manifests and proposes a
matching CRAFT stack-pack name for the `rules.md` `## Personality` block;
`/craft:prime` now warns at session start when a declared stack-pack's file is
missing. Closes the deferred remainder of D27 (Personality Autoload).

## Why

- Propose-and-confirm over silent detection — `/craft:onboard` never writes a detected
  pack name without user confirmation, consistent with the human-in-control rule.
- Fail-early visibility — a missing pack surfaces at `/craft:prime` (session start)
  rather than mid-slice at `/craft:execute`, so the user can fix it before code-near
  work begins. Detection deliberately yields candidate names even for packs that do
  not yet ship, since users can add their own under `~/.claude/craft-personalities/`.

## Decisions

- (none promoted — implementation followed the existing D27 design; no new
  architectural decisions surfaced)

## Commits

- `cccfe12` — feat(commands): detect stack-pack at onboard, warn on missing pack at prime
