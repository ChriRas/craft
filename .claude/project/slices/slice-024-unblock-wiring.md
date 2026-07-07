# Slice 024 — Unblock Wiring

> Completed: 2026-07-07
> Commits: 83bedf4..df46c3c (branch main, trunk-based; design-record docs in 6e70797)
> Epic: epic-002 (Blocked Slice Status), slice 2 of 4

## What

A blocked slice now comes back to life. Closing its prerequisite (via `/craft:commit`)
auto-resurfaces every slice blocked on it — restoring the exact execution status it was blocked
at; and a new `/craft:unblock` command is the manual surface (`resume | re-plan | abort` +
`(pending)` → real-ID back-fill). With slice-023's `/craft:block`, the block → unblock loop is
closed.

## Why

- The unblock mutations needed a home allowed to mutate, but `/craft:continue` is contractually
  a read-only router — so a dedicated `/craft:unblock` owns them (symmetric to `/craft:block`)
  and `continue` only routes to it.
- Auto-resurface lives in `/craft:commit` because a prerequisite becoming *done* is a commit
  event. The `(pending) → ID` back-fill is owned by `/craft:unblock` and must precede the
  prerequisite's commit, else auto-resurface has no ID to match. Full design spec:
  [`../design/d1-blocked-state.md`](../design/d1-blocked-state.md).

## Decisions

- **Dedicated `/craft:unblock` command** — `/craft:continue` is a read-only router (`Read`/`Glob`;
  "does not modify the plan / change Status"), so the unblock mutations (resume-fork, back-fill)
  live in a new `/craft:unblock`; `continue` only gains a `blocked` → `/craft:unblock` routing
  row. *Why not* fold into `continue`: it would break continue's clean router contract. Symmetric
  to `/craft:block`; resolved the design record's open question.
- **Back-fill owner = `/craft:unblock`** — the `(pending)` → real-ID link is written by
  `/craft:unblock`. *Why not* `/craft:commit` auto-scan or `/craft:plan` reverse-link: keeps
  linking inside the unblock domain, off commands that shouldn't know the blocked schema.
- **Unblock cleanup policy** — on auto-resurface (or resume), restore `Status: Blocked-status`,
  **remove** the four on-demand blocker fields, and leave the `## Blocker` section as a resolved
  historical note (`> Resolved: <date>`) for audit rather than deleting it.
- **Back-fill must precede the prerequisite's commit** (coherence note) — auto-resurface matches
  `Blocked-on:` against the closing slice's ID, so a still-`(pending)` dependent cannot be
  matched; the `/craft:unblock` back-fill has to run first.
- **Auto-resurface is `prerequisite-work`-only** (Phase-8 finding) — the match guards on
  `Blocker-type: prerequisite-work`; `external`/`decision`/`access` blockers carry free-text
  `Blocked-on` and must never be auto-cleared even on an ID collision. A restored `Blocked-status`
  is also validated as an execution token before use.

## Commits

- `83bedf4` — feat(unblock): add /craft:unblock + auto-resurface + continue routing
- `df46c3c` — fix(unblock): scope auto-resurface to prerequisite-work + validate resume token
- `6e70797` — docs(design): resolve D1 open question — dedicated /craft:unblock

## Follow-ups

> Light / needs-rethinking findings carried over from Phase 8 Review.

- (none — both Phase-8 findings were Local edits, fixed in-phase.)

## How (Diagram)

```mermaid
flowchart LR
  A[slice in flight] -->|/craft:block| B[Status: blocked]
  B -->|prerequisite closes: /craft:commit Step 7b| C[auto-resurface: Status = Blocked-status]
  B -->|/craft:continue routes| D[/craft:unblock]
  D -->|R resume| C
  D -->|P re-plan| E[/craft:plan]
  D -->|A abort| F[/craft:abort]
  B -.Blocked-on pending.-> G[/craft:unblock back-fill: pending = slice-NNN]
  G -.-> B
```
