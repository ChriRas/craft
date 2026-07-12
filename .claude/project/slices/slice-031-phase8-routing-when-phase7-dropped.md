# Slice 031 — phase8-routing-when-phase7-dropped

> Completed: 2026-07-12
> Commits: f07a802..536f707 (branch only — direct-to-main)
> Review rounds: **5** (four Phase-8 loop-backs)

## What

A project that drops Phase 7 — as CRAFT's own `rules.md` does — could never reach
`/craft:review`'s Phase-8 mode. `/craft:recap` only ever offered Phase 7 and wrote
`Status: refactoring`, a status only `/craft:refactor` consumes, and that command never runs;
`/craft:refactor`'s *interactive* path pulled a slice back to `refactoring` while its
*Subagent-Mode* path handled the drop correctly; and `/craft:continue` routed a Phase-5-passed
slice backwards to `/craft:test`. Whatever the human did, the slice stranded at `review` — which
`/craft:review` reads as pre-Phase-8 and answers with **advisory mode**: findings only, no in-phase
fixes, **Commit never gated** (roadmap B1, found while dogfooding slice-030, where the status had
to be repaired by hand).

Fixed at three sites, and — this is the part that took five review rounds — actually *guarded*: the
phase graph is now declared once as a machine-readable table in `skills/workflow/SKILL.md`, every
affirmative status write and read in `commands/` carries a marker, and
`scripts/test-workflow-status-graph.sh` binds the two.

## Why

- **A phase graph that exists only as prose cannot be checked, and was not.** The `Status:` token
  is what moves a slice between phases: one command writes it, another consumes it. Nothing
  verified the two halves ever met, so a hand-off could dangle for as long as nobody drove the loop
  by hand.
- **The duplication was not incidental — it *was* the bug.** B1 existed *because* `refactor.md`
  described the Phase-7 rule twice, interactively and for the subagent, and only one copy was
  maintained. The autonomous path was correct all along; only a human driving the loop hit the gap.
- **Prose is not checkable, so the checkable parts must be made explicit.** A grep for a status
  literal cannot tell the sentence that *prescribes* a write from the one that *forbids* it. Hence
  markers, and a graph the harness can reason over rather than pattern-match.

## Decisions

- **The answer to a duplicated contract is deletion, not checking.** Rounds 1–3 each stacked a
  layer of verification on top of the duplication — prose-grep → markers → ROUTER + `when=` — and
  each was green and looked finished until the next reviewer opened it. Round 4 removed the second
  copy: `refactor.md`'s Subagent-Mode section now *delegates* to the single gate. Only then did the
  failures stop. *Why not keep instrumenting it:* checking a duplication is a treatment; removing
  it is a cure. Promoted to `rules.md` (Tabus). The harness enforces it structurally — **exactly
  one** `craft:writes` marker per table row, plus a DELEGATION check.
- **Prose is not checkable; a marker binds presence, not meaning.** Promoted to `intent.md`. The
  markers exist because five rounds proved a grep green while checking nothing. What a marker does
  *not* do is bind the meaning of the prose beneath it — keep the marker, invert the sentence, and
  the check passes. Deliberate, disclosed, and preferable to a checker that must understand English.
- **The static state-machine check was chosen over a one-shot manual dogfood** (user decision,
  2026-07-12). *Why not dogfooding alone:* a single manual observation with no regression guard —
  and this defect survived precisely because nothing checked the graph.
- **`review.md` is authoritative; the rationale was wrong.** An early version of the methodology
  claimed `refactoring` degrades the review to advisory mode. It does not — `commands/review.md`
  lists it among the Phase-8-mode statuses, and rightly so: a slice mid-Phase-7 is review-ready.
  The damage is done by the dangling hand-off, not by that status value.
- **`/craft:continue` is deliberately config-independent.** It routes a `review` slice to
  `/craft:recap` in **both** Phase-7 configurations, because `review` is advisory for
  `/craft:review` and routing there directly would leave Commit ungated.
- **Non-goal: making Phase 7 configurable-in-general.** This slice fixes the routing for the
  already-supported "Phase 7 dropped" rule. A general phase-skip mechanism is a much larger design
  question and was not attempted — though the harness would notice such a gap.
- **The author is the last person able to see this.** Five reviewers with fresh context each found
  something the author had declared resolved — twice a bug *inside its own fix*: the `continue.md`
  routing row re-created the very advisory-mode failure the slice exists to kill, and the
  DELEGATION check was built as a grep over prose immediately after the methodology declared prose
  uncheckable. Recorded as evidence for why the fresh-context review exists, not as self-criticism.

## Commits

- `f07a802` — feat(workflow): declare the phase-transition graph and the marker contract
- `c44c627` — fix(commands): route Phase 6 to Phase 8 when rules.md drops Phase 7
- `5b2b0e8` — test(scripts): assert the phase graph, the markers and the router agree
- `1ae666d` — docs: document the status-graph harness in CLAUDE.md and rules.md
- `536f707` — chore(plans): bump slice counter to 32

## Follow-ups

> Optional — light / needs-rethinking findings carried over from Phase 8 Review.

- **`craft:routes` token for `/craft:continue`'s routing cells.** The ROUTER check reads the cell
  *positionally* (the first `/craft:<cmd>` named), so a cell reworded into a prohibition — "do
  **not** run `/craft:recap` yet" — passes while misrouting a human. A token in the cell would bind
  it the way `craft:writes` binds a status write.
- **Dogfooding is not self-verification** — promoted to the roadmap as **B2**. The runtime loads
  the plugin *cache*, not the working tree, so none of this slice's fixes were live in the session
  that wrote them.

## Known limits (disclosed, not closed)

Three residuals, stated identically in the script header, `skills/workflow/SKILL.md` and this
archive. All three require *deliberate* sabotage — an honest deletion takes the marker or token
with it and goes red:

1. **Marker/prose drift** — keep a `craft:writes` marker, invert the sentence beneath it → passes.
2. **ROUTER positional read** — reword a routing cell into a prohibition → passes (see Follow-ups).
3. **DELEGATION** binds the `craft:delegates` token's *presence* and the absence of a competing
   status write — not the meaning of the prose beneath it. Tokenizing that check fixed relocation
   and section-renaming, **not** negation: the negation never lived in a phrase's absence, it lives
   in the prose.

## Phase-8 Review Record

Five rounds, four loop-backs. Every intermediate version was green and looked finished; every one
was opened by the next fresh-context reviewer.

| Round | What the reviewer proved |
|---|---|
| 1 | The cross-check was a grep over prose: a deleted routing branch stayed green, because the status literal survived in a "Never write `Status: refactoring`" sentence — the slice's own words. |
| 2 | Markers bound the *file*, not the *fix*: the gate could be deleted **with its marker** because a second, unscoped marker covered for it. DETECTION had three `ok` calls and zero `bad`. `when=` was parsed and discarded. A **behavioral regression** was introduced while fixing a *Light* finding (a slice at `implementing` could be yanked to `reviewing`, skipping the constitutional Phase-5 demo). |
| 3 | The Subagent-Mode section was a *third*, unmarked route to `reviewing`. Markers were position-free (one hidden in a fenced code block → green). DETECTION's near-miss check was one-directional. And `continue.md`'s new routing row **contained the very bug the slice exists to kill**. |
| 4 | The new DELEGATION check was itself a prose grep and passed on the rule's **negation**. The `reads` half of the marker contract had neither exactly-one nor adjacency — a stray marker made the suite *greener* than the truth (82/0 → 83/0). |
| 5 | **Clear.** 2 Heavy · Local, 3 Light, no Rethink; all five fixed in-phase. 17 mutations run, 12 red — including the acid test: a full honest revert of B1 (prose + marker + table row) is caught by *reachability*, not by any string match. |

Final: **82/82** status-graph, **43/43** read-only-context, `claude plugin validate` ✔.
