# Validation: Paper-Migration of `research/real_live_projekt`

> Simulates running `/onboard` (migration sub-path) against the Cocktail Management project. Goal: surface gaps in the plugin before live-installation.
>
> **Project context:** Laravel 12 app, PHP 8.4, Pest, Livewire, MariaDB, Docker. `.claude/` has 12 commands, 2 agents, 3 skills, a 281-line `CLAUDE.md`, allowed-commands doc, settings.local.json.

---

## 1. Pre-flight Walk-through

| Step | Result |
|---|---|
| Tool health (context-mode / agent-browser / git / gh) | Pass — all installed. |
| Git repo check (`git rev-parse --show-toplevel`) | Pass — would resolve. |
| `.claude/project/intent.md` exists? | **No** → not already onboarded; proceed. |
| `.claude/**/*` has prior content? | **Yes** → **migration mode** triggered. |

✓ Pre-flight passes; would proceed into migration sub-path.

---

## 2. Inventory & Classification

| Asset | Class | Action |
|---|---|---|
| `commands/plan-feature.md` | Universal conflict | → `.claude/commands/_legacy/plan-feature.md` |
| `commands/plan-backlog.md` | Universal conflict | → `_legacy/` |
| `commands/plan-parallel.md` | Universal conflict | → `_legacy/` |
| `commands/review-plan.md` | Universal conflict | → `_legacy/` |
| `commands/execute.md` | Universal conflict | → `_legacy/` |
| `commands/co-review.md` | Universal conflict | → `_legacy/` |
| `commands/commit.md` | Universal conflict | → `_legacy/` |
| `commands/prime.md` | Universal conflict | → `_legacy/` |
| `commands/create-prd.md` | Universal conflict | → `_legacy/` |
| `commands/create-rules.md` | Universal conflict | → `_legacy/` |
| `commands/init-project.md` | Project-local keep | stays — project tooling init (env, deps, DB) |
| `agents/developer.md` | Specialist keep | stays — Laravel/PHP specialist |
| `agents/code-reviewer.md` | Specialist keep | stays |
| `skills/developer/` | Specialist keep | stays — PHP/Laravel code quality + implementation workflow |
| `skills/code-review/` | Specialist keep | stays — Laravel best practices + testing strategy |
| `skills/agent-browser/` | **AMBIGUOUS** | (see Gap #1) |
| `CLAUDE.md` (281 lines) | Knowledge-split source | split into `intent.md` + `rules.md` + `roadmap.md` |
| `CLAUDE-template.md` | Universal conflict | → `_legacy/` (plugin ships its own template) |
| `settings.json` (5 lines) | Project-local keep | stays |
| `settings.local.json` (163 lines, allowlist) | Project-local keep | stays |
| `allowed-commands.md` (71 lines) | Project-local keep | stays — human-readable allowlist doc |

**Asset count:** 18 active. **Classified:** 17 unambiguous + 1 ambiguous.

---

## 3. CLAUDE.md → Knowledge-Split Simulation

The existing `CLAUDE.md` has 11 top-level sections. Mapping each into the new files:

| Source section | Target | Notes |
|---|---|---|
| Project Overview | `intent.md` → Product Vision | Strong fit — 1 paragraph, vision-shaped |
| Tech Stack (table) | `rules.md` → Stack & Tools | Direct port; "Explicit NOT in Stack" → Tabus |
| Commands (taskfile list) | `rules.md` → operational reference OR `intent.md`-pointer | Discussed in Gap #2 |
| Project Structure (tree) | **DROPPED** | This is State; lives in code. Templates should not capture this. |
| Architecture (paragraph) | `intent.md` → Architectural Decisions | Some text; partial fit |
| Code Patterns (PHP/Laravel/Livewire/Naming/Frontend) | `rules.md` → Code Conventions | Direct port; large content |
| Testing | `rules.md` → Workflow Rules / Code Conventions | Mix |
| Validation | `rules.md` → Workflow Rules | Direct |
| Key Files (table) | **DROPPED** | This is State |
| On-Demand Context (table) | **DROPPED OR pointer** | This is State references |
| Notes | `intent.md` → Architectural Decisions (selective) + `roadmap.md` | Mixed; some are still-true decisions, some are dated working-notes |

**Roadmap source:** the Phasen-Plaene line in Project Overview ("Foundation → Importer → … → Polish (9)") → `roadmap.md`.

**Splitting result preview:**

### Draft `intent.md` (~25 lines, would generate)

```markdown
# Intent

## Product Vision

Cocktail Management System — a Laravel 12 application to manage cocktail recipes
and serve digital cocktail menus for parties. Two interfaces: a custom admin panel
(Livewire + Alpine, iPad-optimized, neon-synthwave theme) for admins/bartenders,
and a smartphone PWA for guests with an integrated slot machine. Replaces the
file-based cdCocktails workflow with a database-backed solution.

## Active Goals

- Ship the guest PWA (Phase 7) — the most user-facing slice.
- Complete the slot-machine integration (Phase 8).
- Polish phase before production (Phase 9).

## Architectural Decisions

- **Service Pattern** — business logic in `app/Services/`, never in controllers or
  Livewire components. *Why not:* keeps Livewire components state-thin and testable.
- **Gates over Policies** — `Gate::define('manage-users', ...)`. *Why not Policies:*
  the project has a flat role model; Policies add ceremony without value here.
- **Server-rendered Blade + Livewire + Vanilla JS** — no SPA framework, no npm build.
  *Why not:* unnecessary tooling for a single-team admin tool.
- **Custom Livewire admin instead of Filament** — Filament was tried in Phase 3 and
  removed in Phase 4. *Why not Filament:* rigid component layout prevented the
  neon-synthwave theming that defines the product feel.

## Non-Goals

- Filament admin (removed in Phase 4 — do not re-add).
- npm / Vite build for own CSS/JS (assets are direct-copied to `public/assets/`).
- Tailwind / PhotoSwipe.

## Open Questions

- Live deployment strategy for shared webspace PDF export (parked in backlog).
- Whether backup ZIPs need encryption before first production deploy.
```

### Draft `rules.md` (~80 lines, would generate — at the upper limit)

```markdown
# Rules

## Stack & Tools

- **Language:** PHP 8.4
- **Web Framework:** Laravel 12+
- **UI:** Livewire 3.x (admin) + Alpine.js 3.x (micro-interactions)
- **DB:** MariaDB 11.8
- **Test Framework:** Pest
- **Static Analysis:** PHPStan / Larastan (Level 6+)
- **Lint / Format:** Laravel Pint
- **Image Processing:** Intervention Image 3.x
- **Container Runtime:** Docker + Nginx
- **All commands** run via Taskfile inside the app container (`task start`, `task artisan -- …`, etc.).

## Workflow Rules

- Tests must be green before commit.
- Static analysis (PHPStan/Larastan Level 6+) must pass.
- Laravel Pint must run cleanly before commit.
- Never commit without explicit user approval.
- Destructive git ops (`git branch -D`, `git reset --hard`, `git push --force`, `git rm`, `git clean -f`) always ask first.
- `main` is branch-protected: require PR + green CI.

## Code Conventions

- `declare(strict_types=1);` in every PHP file.
- Full type hints on parameters and return types.
- Constructor property promotion (`public function __construct(private readonly Foo $foo)`).
- PHPDoc shaped arrays for complex returns.
- Guard clauses and early returns preferred.
- `CarbonImmutable` for dates/times.
- `final` on Service and Value Object classes.
- Backed Enums for domain types (`PartyMode`, `UserRole`).
- Eloquent Scopes for recurring queries.
- Class-based Livewire components (not Volt for non-trivial).
- Livewire `#[Computed]`, `#[Locked]`, `#[Reactive]` attributes where appropriate.
- Alpine.js for purely client-side state without backend roundtrip.
- Plain CSS, no preprocessor (tokens from `resources/css/tokens.css`).
- Vanilla JS + Alpine, no framework for business logic.
- Neon-synthwave theme (Magenta `#ff3ec8`, Cyan `#4ff5ff`, Green `#39ff9a`).
- Fonts: Monoton (logo), Audiowide (headlines), Inter (body), JetBrains Mono (meta).

## Tabus (Anti-Patterns)

- No Filament (removed in Phase 4).
- No Tailwind.
- No npm / Vite build for own assets.
- No PhotoSwipe.
- No business logic in controllers or Livewire components — always in `app/Services/`.

## Deployment

- **Branch model:** trunk-based with PR + green CI; `main` protected.
- **Release tagging:** SemVer manual tags `vX.Y.Z`, only on `main` commits.
- **Build:** `image.yml` triggers on `push tag 'v*'`, builds + pushes `ghcr.io/<owner>/cocktails:vX.Y.Z + :latest`.
- **Deploy:** `deploy.yml` is `workflow_dispatch` with Tag-Input; validates SemVer regex.
- **Manual fallback:** SSH deploy via `docker/prod/README.md`.

## Self-Verification Settings

- Defaults — not overridden for this project.
```

### Draft `roadmap.md` (~20 lines)

```markdown
# Roadmap

## Phases

### Phase 1 — Foundation
Done.

### Phase 2 — Importer (2 / 2a / 2b)
Done.

### Phase 3 — Filament (rolled back in Phase 4)
Reverted. Reason: see Architectural Decisions in intent.md.

### Phase 4 — Filament Cleanup
Done.

### Phase 5 — Schema / Importer v2
Done.

### Phase 6 — Admin Panel (Livewire)
In progress.

### Phase 7 — Guest PWA
Planned next.

### Phase 8 — Slot Machine
Planned.

### Phase 9 — Polish
Planned final.
```

---

## 4. Drift Check Simulation

`/onboard` Step 6 runs the same check `/prime` uses. With the drafted `rules.md`:

| Rule | State source | Result |
|---|---|---|
| Test Framework: Pest | `composer.json` (`require-dev` would contain `pestphp/pest`) | **Cannot verify** — `composer.json` not present in `research/real_live_projekt`. See Gap #3. |
| Language: PHP 8.4 | `composer.json` `require.php` | Cannot verify (same gap). |
| Linter: Pint | `composer.json` `require-dev` | Cannot verify. |
| Static Analysis: PHPStan / Larastan | `composer.json` `require-dev` | Cannot verify. |

**In a real Laravel project, these checks would all pass against `composer.json`.** The fact that `research/real_live_projekt` is a metadata-only checkout (`.claude/` + `CLAUDE.md` only, no source code) is realistic for our scenario since we explicitly didn't ship the whole app — but it surfaces a real issue: **the drift check must degrade gracefully** when a manifest file is absent.

---

## 5. Gaps Found in `/onboard`

### Gap #1 — Ambiguous classification of `skills/agent-browser/`

**Symptom:** the asset list says "promote agent-browser to plugin universal skill OR keep project-local" — the migration command never resolves this. The user is left guessing.

**Fix:** In `/onboard` step 2 (Inventory and classify), when the skill `agent-browser` is detected project-local AND the plugin also ships `agent-browser`, surface this as a distinct decision:

> Project already has `skills/agent-browser/`. The plugin ships its own. Pick one:
>   [P] Keep project-local (plugin's version stays inactive)
>   [U] Use plugin version (move project-local to `_legacy/`)
>   [D] Diff them first — show me the differences

This needs a fifth implicit class: **plugin-already-provides** for skills that overlap with plugin-shipped skills. Currently `/onboard` only knows four classes.

### Gap #2 — Taskfile commands aren't captured anywhere

**Symptom:** The existing `CLAUDE.md` has a substantial "Commands" section enumerating Taskfile commands (`task start`, `task artisan -- …`, `task migrate`, `task backup`, etc.). After splitting, these end up nowhere obvious — `rules.md`'s Stack & Tools is for tooling, not project commands.

**Fix options:**

A. Add a `## Common Commands` section to `rules.md.template` — explicitly named and templated.
B. Keep them in `CLAUDE.md` (the repo-root index) instead of `rules.md` — `CLAUDE.md` is closer to the dev's daily reach and not loaded on every `/prime`.

Recommendation: **Option B**. `CLAUDE.md` should be allowed to carry a `## Common Commands` block. Update `templates/claude-md-index.template` accordingly.

### Gap #3 — Drift check needs graceful degradation when manifests are missing

**Symptom:** `/prime` and `/onboard` Step 6 both assume `composer.json` / `package.json` / etc. exist. If a project is e.g. a pure shell-script repo with no manifests, the drift check has nothing to verify against and may emit confusing errors.

**Fix:** In `/prime` Step 3 (Drift check), already documented behavior: *"Drift check sub-command itself errors out → report `⚠ drift check incomplete: <reason>`."* This is fine for `/prime`. But `/onboard` Step 6 currently says "report green" without handling the no-manifest case. The fix: when no manifest is found for a stack listed in the drafted `rules.md`, emit:

> Rules ↔ State drift check: incomplete — no `composer.json` to verify PHP rules against. This is expected if you haven't installed deps yet; re-run `/prime` after `task start` / `composer install`.

### Gap #4 — `intent.md` and `rules.md` size limits could be violated by greenfield migrations

**Symptom:** the drafted `rules.md` for this project hits ~80 lines (the soft limit) because Code Conventions are extensive. A more conservative project (Symfony with many conventions, a Python project with multiple linters) would exceed it.

**Fix:** `/onboard` step 6 should warn if the generated file exceeds 80 lines, and suggest splitting the longest section out as a separate file (e.g., `.claude/project/conventions.md`) referenced from `rules.md`. The current command silently writes whatever size.

### Gap #5 — No interactive trim during migration

**Symptom:** The CLAUDE.md "Notes" section in this project has dated working-notes (export strategies, backup encryption thoughts) mixed with still-true decisions. Bulk-moving this into `intent.md` would create noise.

**Fix:** During the knowledge-split, `/onboard` should ask the user to walk through each candidate entry:

> Notes section has 8 items. For each, pick:
>   [I] → intent.md
>   [R] → rules.md
>   [O] → roadmap.md (parked work)
>   [D] → discard
>   [K] → keep in CLAUDE.md as freeform notes

This adds dialog but is the only way to avoid auto-importing stale notes.

---

## 6. Gaps Found in Templates

### Gap #6 — `intent.md.template` lacks an Architectural Decisions example with multiple alternatives

**Symptom:** The template has one placeholder under Architectural Decisions:

```markdown
- **{{decision_name}}** — {{reason}}. *Why not {{alternative}}:* {{rationale_against_alternative}}
```

This handles a binary decision (A vs B). The real Cocktail-project example has decisions that ruled out several alternatives at once ("not Filament, not Tailwind, not PhotoSwipe"). The single-`Why not` slot doesn't fit.

**Fix:** Add a second line variant:

```markdown
- **{{decision_name}}** — {{reason}}.
  - *Why not {{alternative_1}}:* {{reason}}
  - *Why not {{alternative_2}}:* {{reason}}
```

### Gap #7 — `rules.md.template` lacks a "Common Commands" section

Per Gap #2, if we go with Option A, the template needs a section. Per Option B, the `claude-md-index.template` needs one. Pick one and update the corresponding template.

### Gap #8 — `slice-plan.md.template` has no placeholder for slice's slug — it's in the filename only

**Symptom:** A slice plan file is named `slice-007-pwa-reservation-button.md`. The slug is in the filename. But inside the file, only `Slice-ID: slice-NNN` is recorded. If two slices share the same number (after `/abort` + recreate) the file could be lost.

**Fix:** Add `Slice-Slug: {{slug}}` to the frontmatter. Belt-and-suspenders.

---

## 7. Gaps Found in Plugin Commands (beyond `/onboard`)

### Gap #9 — `/prime` doesn't know how to surface a handoff prominently

**Symptom:** `/handoff` writes a `## Handoff` section and sets `Handoff active: yes` in slice frontmatter. `/prime` reads slice frontmatter and lists active slices, but does not specifically surface a handoff as the "Recommended next action."

**Fix:** In `/prime` Step 7 (Recommended next action), add a check before the existing branches:

> If any active slice has `Handoff active: yes` in its frontmatter → recommend `/continue <slice-NNN>` with a note that a handoff is waiting to be read.

### Gap #10 — No way to view what would happen *before* committing migration changes

**Symptom:** `/onboard` migration mode has a confirm-by-class dialog (Step 3), but once the user types `Y` the changes execute. There is no `--dry-run` equivalent.

**Fix:** Optional. Add a step *between* confirm-by-class and execute that says:

> Final preview: <N> files will be moved, CLAUDE.md will be split, drift check will run. Type `apply` to proceed or anything else to abort.

Could be added later if needed. Low-priority unless real users hit a surprise.

---

## 8. Validation Summary

**Plugin readiness for this project:** ~80%.

The migration would mostly work but would surface visible friction at:
- agent-browser ambiguity (Gap #1) — user has to make an undocumented choice.
- Lost Taskfile commands (Gap #2) — user notices they can no longer find their `task start` reminder.
- Silent oversize `rules.md` (Gap #4) — file exceeds soft limit, loaded on every `/prime`, slow drift.
- Stale notes co-mingled with current decisions in `intent.md` (Gap #5).

**Recommended fixes before live-installation:**

| # | Gap | Fix location | Priority | Status |
|---|---|---|---|---|
| 1 | agent-browser ambiguity | `commands/onboard.md` — added 5th class `Plugin-already-provides` + step 2.5 resolution dialog | **High** | ✓ |
| 2 | Lost Taskfile commands | `templates/claude-md-index.template` — added `## Common Commands` section | **High** | ✓ |
| 3 | Drift check graceful degradation | `commands/prime.md` Step 3 + `commands/onboard.md` Steps 5/6 — emits incomplete-check note when manifests are absent | Medium | ✓ |
| 4 | Oversize warning | `commands/onboard.md` — post-write size check in both greenfield and migration paths | Medium | ✓ |
| 5 | Notes-section dialog | `commands/onboard.md` — per-entry triage `[I]/[R]/[O]/[K]/[D]` during knowledge-split | Medium | ✓ |
| 6 | Multiple-alternative decision format | `templates/intent.md.template` — added multi-alternative variant | Low | ✓ |
| 7 | Common Commands template section | `templates/claude-md-index.template` | High (tied to #2) | ✓ |
| 8 | Slice slug in frontmatter | `templates/slice-plan.md.template` — added `Slice-Slug:` and `Handoff active:` to frontmatter | Low | ✓ |
| 9 | Handoff surfacing in `/prime` | `commands/prime.md` Step 7 — priority-ordered recommendation list with handoff first | Medium | ✓ |
| 10 | Dry-run preview in `/onboard` | `commands/onboard.md` Step 3.5 — final preview requires `apply` confirmation | Low | ✓ |

**Status:** All 10 gaps fixed. Plugin is ready for live installation testing.
