---
name: docs-site
description: Regenerate or update the bilingual GitHub Pages documentation site (docs/index.html) after the plugin changes. Defines the design contract, the section/anchor structure, the four-perspective analysis procedure, delta-vs-full update, and the verification gate. Trigger phrases; "update the docs site", "regenerate the documentation page", after a version bump, or whenever commands/, skills/, agents/, hooks/, or templates/ changed and docs/ did not.
---

# Docs-Site Maintenance

`docs/index.html` is the public documentation site for CRAFT (GitHub Pages, served
from `main /docs`). It was generated from a full four-perspective analysis of the
plugin source. This skill is the contract that lets any future session extend or
regenerate it **at the same quality with the same parameters**.

Companion harness: `bash scripts/test-docs-site.sh` — mechanical checks, keep green.
Run it before every commit that touches `docs/` or the plugin surface.

---

## What the site is

- **One self-contained file**: `docs/index.html` + `docs/.nojekyll`. No CDN, no
  external fonts, no JS libraries, no build step. Everything inline (CSS, JS, SVG).
- **Bilingual, EN default**: every prose element exists twice (`class="en"` /
  `class="de"`); CSS shows one via `html[data-lang]`; the nav toggle (order **EN | DE**)
  persists in `localStorage` key `craft-lang`. The `<html>` tag hardcodes
  `lang="en" data-lang="en"` as the no-JS default.
- **Terminal aesthetic**: dark GitHub palette, monospace stack, each section is a
  terminal window (`.term` with traffic-light dots and a `~/craft — <topic>` title),
  `❯` prompt prefixes, `❯`-prefixed `h2` / `## `-prefixed `h3`.
- **Auto light/dark** via `@media (prefers-color-scheme: light)` — no manual toggle.
  **Shell rule:** `pre`, `.figwrap` (diagram containers) and `.hero .install` keep the
  dark palette in BOTH themes (CSS custom properties are re-scoped on those selectors).
  Terminal content looks like a terminal screenshot even on a light page.
- **Diagrams are inline SVG** inside `.figwrap` (scrollable, `min-width:640px`).
  Explanatory labels are bilingual via `<tspan class="de">…</tspan><tspan class="en">…</tspan>`.

## Language policy (the trap to not fall into)

**System terms stay English in BOTH languages** — phase names (`Planning`, `Recap`),
status tokens (`awaiting-release`, `blocked`, `review` vs `reviewing`), command names,
file paths, orchestrator messages (`epic ready for review`), lettered choices
(`[W]/[B]/[U]`). These literally appear on the user's screen; translating them would
misdocument the system. Only *explanations* are translated.

**Parity invariant:** the count of `class="de"` elements must equal `class="en"` —
the harness asserts it. Never add prose in one language only.

## Page structure (anchor contract)

| Anchor | Section | Content | Ground-truth sources (working tree!) |
|---|---|---|---|
| `#intro` | The problem & the idea | pitch, four disciplines, two-tier architecture | `README.md`, `intent.md` |
| `#loop` | The 9-phase loop | loop SVG + per-phase table (control levels, commands) | `skills/workflow/SKILL.md` |
| `#quickstart` | Quickstart | terminal transcript onboard→commit; **context hygiene** (~300k tokens → `/clear` + auto re-prime; context-mode as the token-saving enabler); prerequisites | `README.md`, `commands/prime.md` |
| `#turns` | Status graph & branch-offs | status-graph SVG + branch-off table (pause/handoff/block/unblock/abort/debug/release/approval) | `skills/workflow/SKILL.md` §Phase Transition Rules, `commands/{block,unblock,pause,handoff,abort,release,commit,continue}.md`, `skills/debug/SKILL.md` |
| `#autonomy` | Autonomy taxonomy | L0–L3 cards, action-type override table, bend/override/repeal | `skills/workflow/SKILL.md` |
| `#execution` | The three execution modes | 3-panel SVG (parallel worktrees / in-place / sequential epic) + orchestrator guarantees | `commands/execute.md`, `commands/release.md` |
| `#config` | Configuration reference | profile presets table, every block/field/enum/default, rules.md optional blocks, 3 personality tiers | `craft-profile-defaults.md`, `model-defaults.md`, `templates/`, `commands/onboard.md` |
| `#knowledge` | Knowledge model | State/Intent/Rules table, durable-capture routing, file-tree `<pre>` | `skills/workflow/SKILL.md`, `templates/` |
| `#commands` | Command reference | grouped table of all commands + slash-invocable skills | `commands/*.md` (count them!) |
| `#architecture` | Under the hood | anatomy cards (counts!), hooks, agents, self-test harnesses, companion tools, upgrade/cache caveat | `.claude-plugin/*.json`, `hooks/`, `agents/`, `scripts/` |

Nav links mirror the anchors; keep the GitHub link (`https://github.com/ChriRas/craft`)
in nav, hero install block, hero badge line, and footer.

**The badge line** (`v<version> · MIT · N commands · N skills · N agents · N hooks`)
must reflect reality: version from `.claude-plugin/plugin.json`, counts from
`commands/*.md`, `skills/*/`, `agents/*.md`, `hooks/*.sh`. The harness asserts this —
it is the staleness detector for the whole page.

## Regeneration procedure

### 0. Ground truth
Analyze the **working tree**, never `~/.claude/plugins/cache/` (the dogfooding trap:
the running session executes the cache, the repo may be newer). README marketing
counts can be stale — directory listings are authoritative.

### 1. Delta mode (default after small changes)
Map what changed since docs were last touched
(`git log --oneline $(git log -1 --format=%H -- docs/)..HEAD --stat`) to sections:

| Changed | Update |
|---|---|
| `commands/*.md` | `#commands` row + the section that explains that command's phase |
| `skills/workflow/SKILL.md` | `#loop`, `#turns`, `#autonomy`, `#knowledge` |
| `skills/debug/SKILL.md` | debug row in `#turns` |
| `templates/`, `craft-profile-defaults.md`, `model-defaults.md`, `commands/onboard.md` | `#config` |
| `hooks/`, `scripts/`, `agents/`, `.claude-plugin/` | `#architecture` + badge counts |
| `plugin.json` version bump | badge line + footer version |
| new status token / transition row | status-graph SVG + branch-off table |

### 2. Full mode (major changes / quality doubts)
Re-run the four-perspective analysis with parallel read-only agents, then rewrite
the affected sections. The four prompts (each must demand exact command names, exact
status tokens, precision over brevity, working tree only):

1. **Methodological core** — read `skills/workflow/SKILL.md` (fully),
   `senior-developer`, `debug`: the 9 phases with autonomy levels, the COMPLETE
   status/transition graph incl. both Phase-7 configurations, every branch-off
   (trigger / what's recorded where / way back), autonomy taxonomy + forced levels,
   durable-capture routing, bend/override/repeal, debug flow + thresholds.
2. **All commands** — read every `commands/*.md`: purpose, phase, trigger situation,
   inputs/outputs incl. `craft:writes`/`craft:reads` markers, dialogic forks with
   their lettered options, subagent-mode differences, the three execute modes.
3. **Configuration surface** — profile presets + every block/field/enum/default +
   constraints, rules.md optional blocks, agent model defaults/overrides, language
   settings, personality tiers, `.claude/project/` + `.claude/plans/` inventory.
4. **Architecture & runtime** — manifests, hook wiring + guard logic, both agents
   (role, model, must/must-nots), both test harnesses (what they assert and why
   markers-not-prose), worktree mechanics, companion tools, install/upgrade flow.

### 3. Writing
Edit `docs/index.html` in place with targeted `Edit` calls (for a rewrite: build in
chunks against a `<!--NEXT-->` placeholder, remove it at the end). Match the existing
CSS classes — do not invent new visual language. New SVG labels near the right
viewBox edge need `text-anchor="end"` (known overflow trap).

## Verification gate (all steps, before commit)

1. `bash scripts/test-docs-site.sh` → must be green (tag balance, anchors, ids,
   language parity, EN default, repo URL, `.nojekyll`, no `<!--NEXT-->` leftovers,
   badge/version vs. reality, light-mode + localStorage markers present).
2. **Visual check**: `python3 -m http.server 8642 --directory docs`, open in browser;
   check hero + all three SVGs, in **both languages** (toggle) — labels not clipped.
3. **Light theme**: copy the file to a scratch dir replacing
   `@media (prefers-color-scheme: light)` with `@media all`, serve, inspect — shells
   must stay dark, `.lvl` badges readable.
4. Prose numbers ("24 commands + 4 slash-invocable skills" in `#commands` and the
   anatomy card in `#architecture`) match the badge line — manual, the harness only
   covers the badge line.

## Publishing

`docs/` on `main` is the Pages source (repo: `https://github.com/ChriRas/craft`).
Commit style: `docs(pages): <what changed>`. Pages setup/visibility is a human
decision — never change repo visibility or Pages config without explicit confirmation.
