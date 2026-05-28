# Slice 012 — Onboarding language config

> Completed: 2026-05-28
> Commits: 866e7d3 (main, no PR)

## What

CRAFT projects can now set three independent language preferences at onboarding — chat, commits, and code comments — captured into an `## Operational Language` block in `rules.md`. Previously language was an implicit convention with no configuration surface. The downstream phases now consume the block. This was the last unshipped capability (A) from intent.md.

## Why

- Closes capability A (onboarding language config), the final item of the original seven.
- Store in `rules.md` rather than `intent.md`: pragmatic, since prime already loads rules.md and the consuming phases find the settings centrally. This deliberately bent rules.md's "verifiable rules only" doctrine, so the doctrine note was amended (Phase-9 [R] promotion) to admit operational settings as a sanctioned exception.
- Default policy keeps existing projects behaving as before: chat = system language (onboard asks), commits = English, comments = English; a missing block applies defaults and never aborts (report-never-abort, like the other prime checks).

## Decisions

- **Default language policy** — chat defaults to the system language (onboard asks whether to use it); commits and comments default to English. *Why not* force an explicit choice for all three: defaults keep onboarding short and make existing projects without the block behave exactly as today.

## Commits

- `866e7d3` — feat(onboard): configurable chat/commit/comment language

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review. Each is a candidate for a future slice.

- (none — all four Phase-8 findings, incl. one Heavy, were fixed in-phase)

## How (Diagram)

(declined in recap — flow is linear: onboard → rules.md `## Operational Language` → prime / commit / build / review)
