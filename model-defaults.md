# Per-Phase Model Defaults

CRAFT binds each role to a **capability tier** and lets the tier resolve to a model: Code
Review runs on the deep-reason tier (`code-reviewer`, today Opus), and Slice Execution — when
run through the `/craft:execute` orchestrator — on the execute tier (`slice-builder`, today
Sonnet). The other heavy-thinking phases — Plan, Debug autonomous
loop — stay on the active session model because they are dialogic, and a subagent
boundary would break their incremental streaming/pause UX. The orchestrating slash
command stays on the session model and delegates to the subagent at the
appropriate step. See the Default Mapping table for the full picture and the
rationale for each row.

This file documents the default mapping, the per-project override mechanism, and
the resolution rules.

> **Why this design**: a subagent is the only way to hold a workflow phase on a model.
> A slash command does take a `model:` frontmatter field, but it switches **only the turn
> that loads it**: that turn re-reads the whole context uncached, and the next prompt reverts
> to the session model. So a command cannot pin the phase it starts, let alone the turns that
> follow it — routing the work through a subagent (`agents/*.md`) is what makes the choice
> durable. See the slice-010 archive for the original verification trail, and design record §2
> for the current facts about command-level `model:`.

---

## Allowed Model Values

This is the **single declaration** of the model values CRAFT accepts in an agent's `model:`
frontmatter. Every other place that names these values is a copy bound to this line.

**An override reaches only some of them.** Which ones is declared in its own section below —
`## Spawn-Reachable Values` — because three commands read it at run time and a drift there silently
changes which overrides arrive. Do not restate the set here. The one value the Agent tool does
offer and CRAFT forbids itself is `fable` (below).

<!-- craft:model-enum canonical -->
Allowed values: `opus`, `sonnet`, `haiku`, `inherit`, `fable`, `<model-id>`

A value written in `<angle brackets>` is a **placeholder** for a full model ID; every other value on the line is an **alias** — a closed set. `inherit` means the agent runs on the
active session model. That is not the same as omitting `model:` altogether: an agent with no
`model:` falls through to `CLAUDE_CODE_SUBAGENT_MODEL` first, where one is set. `<model-id>` is not a sixth value but a
placeholder for a full model ID such as `claude-opus-5`, documented in Claude Code's
sub-agents reference. Prefer the aliases: they survive a model generation, and they are the
only part of this list anything can check.

**Nothing validates a full model ID.** `/craft:prime` reports any non-alias value as written and
says so; `claude plugin validate` accepts any string as a `model:` value. A wrong ID therefore
surfaces when the agent is **spawned**, not when it is configured.

**That last sentence is about an agent's own `model:` frontmatter, and only about that.** A full
model ID written into a *project override* never reaches a spawn at all: it is not spawn-reachable,
so the spawn sites drop it (`## Spawn-Reachable Values`) and the agent runs on its frontmatter
model. Saying an override "fails at spawn time" was true before the spawn sites became conditional
and is false now — the probe below pinned `model: gpt-4` into an **agent file**, which is the case
that still fails.

*Probed, 2026-09-16.* An agent pinned to `model: gpt-4` passed `claude plugin validate`, and the
spawn failed with `Agent terminated early due to an API error … (error type model_not_found,
HTTP 404, model sent to the API: gpt-4)`. So the failure is loud, immediate and names the value —
**with at least two documented exceptions this probe could not reach.** Where an organization
`availableModels` allowlist blocks the value, Claude Code substitutes another model instead of
failing; the documentation promises a warning naming both models *in interactive sessions*, and
says nothing about other sessions. And where a fallback model chain is configured, a failed
subagent request is continued on the next chain model instead of ending the run. Both are
documented, not observed here — see *Sources outside CRAFT's reach*. That is a deliberate choice over a pattern match: a regex would
have to settle Bedrock (`anthropic.claude-…`) and Vertex (`claude-opus-4@…`) spellings and
would age with every model generation, while guarding nothing the runtime does not already
reject.

**`fable` is human-chosen only.** CRAFT never selects it. A human may write it into
`## Agent Model Overrides` — and `/craft:prime` then reports it with a cost warning at every
session start. What the documentation says: *"Depending on your plan and seat tier, Fable usage can
bill to usage credits instead of drawing on your plan's included limits"* (`model-config.md`,
checked 2026-09-17); a spawn may stall on a consent prompt (5-minute `dialogExpiry`, then the turn
ends), and a headless `-p` run bills without asking. The further detail that Fable has **its own
allotment** and bills credits only beyond it is the user's report about this account
(design record §4), not documentation — it is why the warning exists here, but do not present it
as a documented rule.

That warning describes the **configuration**, not any single request. A request a safety
classifier flags is re-run on Opus and the session continues there — see *Sources outside CRAFT's
reach* → **content-based automatic fallback** — so a flagged request bills no Fable usage at all.
An agent overridden to `fable` is therefore not guaranteed to run on Fable.

That rule has a checked half and an unchecked half, and the difference is worth stating
plainly:

- **Checked** — no `agents/*.md` declares `model: fable`. `scripts/test-model-enum.sh`
  asserts it, and a self-test mutation proves the assertion bites.
- **Not checked** — that no command *chooses* `fable` at spawn time, and that nothing falls back
  to it. No harness can see a per-spawn value: it lives in a tool call, not in a file. These
  are rules for whoever writes the next command, not facts anything verifies.
- **Not what this forbids** — carrying a `fable` **project override** to the spawn. That value is
  spawn-reachable and the human wrote it into the profile; passing it on is obeying the profile,
  not CRAFT selecting a model. The prohibition binds the command's *own* choice — source 3 in
  `## Resolution Order` — and a spawn site that dropped a configured `fable` would disobey the
  profile silently, since no inert line is emitted for a reachable value. Stated here because two
  readings of the same sentence sent `/craft:execute` step 5 both ways (review round 7, R7-7).
- **Not settled** — what a `fable`-pinned subagent actually does when a command spawns it is
  documented but unprobed (design record §10 still gates it). Treat the consent-prompt
  behaviour above as documentation, not as evidence.

### How a copy is bound

A file that names these values carries the marker `craft:model-enum`, as an HTML comment
**alone on the line directly above them** — the canonical one adds the word `canonical`.
Leading whitespace and blockquote markers do not count as company: the marker may sit at a
list's indentation or inside a `>` quote, because both are wrappers rather than content.
A marker that shares its line with other text is prose about the mechanism, like this
paragraph, and is not a binding site; that is what keeps this section from counting as a
copy of itself.

**A marker inside a fenced code block is an example, not a binding site** — for the same
reason, and with the same history: slice-031 lost a gate because a marker parked in a fenced
example kept it green after the real one was deleted.

**How far that holds today.** Every check reads the file through one shared helper,
`scripts/example-regions.sh`, which *parses* the constructs rather than counting them: fenced
blocks (nested, indented, inside a blockquote, or left unclosed), multi-line HTML comment blocks,
and `<pre>` elements in the non-Markdown file among the binding sites. So an example neither stands
in for a missing marker nor raises a false alarm — at the marker comparisons **and** at the checks
that read this file's tables and rules — and the mechanism stays documentable in a code block.
A single-line HTML comment is never treated as an example, because CRAFT's markers *are* HTML
comments. The one definition is that helper; its contract is `scripts/test-example-regions.sh`.

#### Known limits of the binding mechanism

> This is the **single** description of what the binding mechanism does not yet catch. `CLAUDE.md`,
> `.claude/project/rules.md` and slice-046's Recap point here instead of restating it — the block
> was hand-maintained in four places and was wrong in three consecutive versions, each time
> differently, which is the same failure this whole mechanism exists to prevent.

The ten holes this block used to list as open were **closed by `slice-047
harness-fence-parser`** — recorded in slice-046's `## Review Findings` as R4-1, R4-2, R4-3, R4-6,
R4-7, R4-8, R4-9, R4-10 and, added by round 7, R7-3a and R7-3b. (R4-4 and R4-5 were never among
them: those were prose findings slice-046 fixed itself.) Each is a self-test fixture in
`scripts/test-model-enum.sh` now, and the three that had been reproduced GREEN were run **both**
ways before being believed — red against the shared helper, green against a restored copy of the
old parity toggle, because a fixture that is red under both reproduces nothing.

What that did and did not buy, stated precisely so the next reader does not have to re-derive it:

- **Closed structurally** — nested and unbalanced fences, tilde fences, a fence whose info string
  disqualifies it, a fence inside a blockquote, an HTML comment block (R7-3a) and a `<pre>` in
  `docs/index.html` (R7-3b). One helper parses all of them, so the four scripts that used to decide
  separately can no longer disagree. One limit: a comment block that is never closed blanks the rest
  of its file without a report, since `report` names only an unclosed fence (slice-047 R1-1).
- **Closed by asking the helper a second question** — an unclosed fence hides every line after it,
  which *both* the old toggle and the helper do. The difference is that the helper reports it, so
  the harnesses that ask it fail loudly instead of checking fewer things in silence.
- **Closed by removing a copy** — a self-test case must now declare which occurrence it mutates
  (R4-2), so a case can no longer quietly test something other than its label.
- **R4-10 is a copy removed, not a defect fixed, and it has no fixture on purpose.** The capability-
  tier set is read from the Capability Tiers table instead of being typed out three times inside the
  harness. With exactly two tiers, derived and hardcoded are **observationally identical** — a role
  retiered to a tier the table does not define fails the same way under both, via a check older than
  the change — so reverting it leaves the whole run green and **no test on this tree can show the
  difference**. The value is that the harness stops keeping its own unbound copy of a set, in a slice
  whose thesis is "declared once", and it is realised when the table grows. Said here rather than
  asserted by a case that would be caught by something else (B2, slice-047).

**Two holes remain, and neither is a fence problem.** They are stated below because nothing in this
repository can close them.

**The first remaining hole, and no parser can close it — which is why slice-047 did not (R1-3).**
A file that names the values **without carrying a marker** is invisible to every check here: the
tree scan finds markers, so a copy that declines to carry one is not a copy as far as the
mechanism is concerned. It is not hypothetical — this slice added such a copy to `CLAUDE.md` and a
human reviewer, not the harness, found it. Review round 7 reproduced it again from the other side:
an unmarked value list re-grown inside `commands/prime.md` leaves all thirteen harnesses green,
although that file's declared site count of **0** reads like an assertion that it names no values.
The count asserts that prime carries no *marker*; that it also names no *values* is a review
obligation, not a check. A marker-based mechanism cannot, in principle, find a copy that opts out
of the mechanism.

**And one residual belongs to `## Spawn-Reachable Values` specifically.** That declaration has a
single binding site, so comparing it against its copies compares it with itself and sees nothing;
a declared value **count** is what makes a narrowed or widened set loud. A **same-cardinality
swap** — four values, but `inherit` in place of `haiku` — passes both the count and the
subset check. Nothing in this repository can verify a third party's API: the harness can make an
edit conspicuous, never confirm it is correct. Re-probe the Agent tool when that set is changed;
do not treat a green run as evidence that the four values are the right four.

**What is still true about this declaration itself.** The guarantees above hold for the bound
**copies** by comparison; for a declaration with a single binding site they rest on the declared
value **count**, the subset relation and the presence checks, never on a copy comparison — that is
what the residual above is about. `scripts/example-regions.sh` changed what counts as an example;
it did not give a lone declaration a second opinion about its own contents.

On the marked line, everything after the **last** `:` is the value list, separated by
`,`, `|` or `·`; the values may be backticked, `<code>`-wrapped or HTML-escaped, and
nothing but values may follow that colon.

`scripts/test-model-enum.sh` compares every copy's value set against the declaration
above and fails naming the file and line that drifts — in both directions, so a copy that
keeps a value this declaration has dropped is caught too, and so is a stray word left
after the colon. The canonical line gets all three now (slice-047): value loss, exactly one
colon, and no stray tail between the colon and the first value. The last of those was *already*
caught before it was asserted here — every copy reported drift against the declaration — but the
message named the seven copies, which sends the reader to files that are all fine. Asserting it at
the declaration names the one line that is wrong.

The harness carries no copy of the value *list*; it reads the values from the canonical line.
That is what keeps it from becoming one more copy of the enum. (Two of its self-test fixtures do
name a single agent model — its own header says so.)

**A marker alone does not bind a file.** The harness compares only the files named in its
`BOUND_FILES` list, each with the number of binding sites that file must have — so a new file
that names the values belongs in that list.

That obligation is enforced, not merely stated: the harness also scans the tree for markers and
fails on any marked file the list does not name. The list is therefore bound the same way the
values are — a marked file cannot slip past it, and deleting an entry does not quietly shrink
coverage. The per-file count closes the same gap from the other side: delete a marker from a
listed file and the run fails instead of checking one copy fewer.

**In a project's own `craft-profile.md` the marker is inert.** The profile templates carry it,
so every onboarded project inherits one. Nothing binds a project's file — no CRAFT harness
runs there, and the values in it are the project's to edit. Ignore it, or delete it; neither
changes anything.

---

## Spawn-Reachable Values

This is the **single declaration** of the values that can travel from a configured override to a
running agent. It is a second declaration, not a copy of `## Allowed Model Values`: that section
says what an agent's `model:` frontmatter accepts, this one says what the *spawn parameter*
accepts, and the two are not the same set. Every other place that names these values is a copy
bound to the line below, the same way the enum above is bound.

<!-- craft:spawn-enum canonical -->
Spawn-reachable values: `opus`, `sonnet`, `haiku`, `fable`

*Probed 2026-09-17: the Agent tool's `model` parameter rejects a full model ID with
`InputValidationError`, naming exactly these four as the allowed values.*

**Why this set is load-bearing.** That parameter is the **only** route from
`## Agent Model Overrides` to a running agent, because CRAFT cannot rewrite the plugin's
`agents/*.md` at run time. So an override of `inherit` or a full `<model-id>` never arrives: the
spawn sites drop it (`/craft:execute` step 5, `/craft:review` Step 2, `skills/debug/SKILL.md` →
Autonomous Mode step 2) and the agent runs on its
frontmatter model, which `/craft:prime` resolves to and reports. Write one of the four, or change
the agent file.

The same limit applies to a **per-spawn** override, for the same reason — see `## Resolution Order`
→ *When a per-spawn override is legitimate*. It is the same parameter, so it is the same set; the
`fable` prohibition that applies there is about *who chooses the value*, not about what the
parameter can carry (below).

**Three commands read this section at run time** — `/craft:prime` step 4b (to resolve past an
unreachable override and to emit the inert line), `/craft:execute` step 5 and `/craft:review`
Step 2 (to decide whether to pass the override with the spawn) — and, since slice-053, one skill:
`skills/debug/SKILL.md` → Autonomous Mode step 2 (`code-reviewer`'s Protocol Freeze spawn). None of
them carries a copy of the set. That is why the harness binds this line in both directions and
asserts the rule sentence is still present: a silent edit here changes behaviour in four places at
once. *Known limit:* the harness's reader and spawn-site lists name only the three commands (it is
frozen, `rules.md`), so the skill's pointer and fallback sentence are not asserted there.

### What a spawn site must do

This is the **single** definition of the rule. A spawn site states the obligation in one sentence
and points here; it does not restate the reasoning, and it never names the values — two command
files each carrying the whole contract is the duplication this file exists to prevent, and the one
that goes un-updated is how the Phase-7 routing bug (B1, slice-031) survived five rounds.

1. Read the override for that agent from `.claude/project/craft-profile.md` →
   `## Agent Model Overrides`.
2. Resolve **this file**, first match wins: `${CLAUDE_PLUGIN_ROOT}/model-defaults.md` if the
   environment variable is set; else `<project-root>/model-defaults.md` if it exists. Take the set
   from `## Spawn-Reachable Values` — the declaration above, not the `## Allowed Model Values`
   line, which is a different and wider set.
3. Pass the override with the spawn **only if** it is in that set. Otherwise spawn with no `model`
   parameter and let the agent's frontmatter decide.
4. If neither path in (2) resolves, spawn with no `model` parameter — **and say so in the run's
   output**: `⚠ Could not read model-defaults.md — spawning <agent> without a model; a project
   override, if any, was dropped.` Without that line the whole chain is silent in the worst
   direction: `/craft:prime` reported a model at session start, every spawn quietly ignored the
   override, and nothing anywhere said either happened (review round 7, R7-19). A dropped override
   is defensible; a dropped override nobody can see is not.

**Step 4 is also written out at each spawn site, and that is deliberate — do not de-duplicate it.**
Every other part of this procedure lives here alone, and the spawn sites carry a pointer. Step 4
cannot: it is the handler for *this file being unreachable*, so an agent that needs it is by
definition an agent that cannot read this page. Phase-5 test T3 caught exactly that — the file was
renamed away, `/craft:review` ran to completion, and no line anywhere mentioned the dropped
override, because the instruction to mention it was behind the pointer that had just failed
(B-R7-1). The general rule: **a pointer's own unreachability handler cannot live behind that
pointer.** `scripts/test-model-enum.sh` asserts both sentences are present, so removing one goes
red rather than silently reinstating the bug.

*Why conditional rather than unconditional:* a value outside the set fails the spawn with
`InputValidationError` rather than being ignored, so passing it unconditionally would turn a typo in
a profile into a stopped autonomous run. Dropping it is the failure mode a human can recover from.

**`fable` in a project override is carried, not dropped.** It is spawn-reachable, and a human wrote
it into the profile — carrying it is not CRAFT selecting it. The prohibition below binds **source 3**,
the per-spawn override a command chooses on its own; it does not reach back to a value the human
configured. A spawn site that dropped `fable` would silently disobey the profile, and nothing would
say so, because no inert line is emitted for a reachable value.

**How this line is bound.** `scripts/test-model-enum.sh` asserts three things about it, and the
first two are what the enum above already gets:

1. every marked copy of this set equals this declaration, and this declaration equals every marked
   copy — the same two-directional comparison, with an expected binding-site count per file;
2. this set is a **subset** of `## Allowed Model Values` — a spawn cannot carry a value an agent's
   frontmatter would reject, so a value here that is not there is a contradiction between the two
   declarations rather than a drift within one;
3. the sentence stating the rule is present at all — deleting or inverting it is the failure
   `/craft:prime`'s inert line and both spawn sites depend on, and a comparison of copies cannot
   see the deletion of the last copy.

Check 3 is the one the enum above does **not** have an equivalent for, and it exists because
review round 7 reproduced its absence: replacing this section's rule with "every value reaches an
agent" left the harness green while prime would have stopped emitting the inert line and both spawn
sites would have started raising `InputValidationError`.

## Default Mapping

| Phase | Phase Command | Delegating Subagent | Model |
|---|---|---|---|
| 3 — Plan | `/craft:plan` | — (dialogic, runs in main session) | session |
| 4 — Execute | `/craft:execute` | `slice-builder` | `sonnet` |
| 5 — Test | `/craft:test` | — (user-driven, no delegation) | session |
| 6 — Recap | `/craft:recap` | — (user-driven dialog) | session |
| 7 — Refactor | `/craft:refactor` | — (small, in-session edits) | session |
| 8 — Review | `/craft:review` | `code-reviewer` | `opus` |
| 9 — Commit | `/craft:commit` | — (mechanical, no delegation) | session |
| Debug (escalated) | `/craft:debug` step 3 | — (interactive loop, session) | session |

Phase 3 and Debug stay on the session model because their value is interactive: the
three universal planning questions and the AUTONOMOUS LOOP's per-attempt
streaming + user-pause UX, respectively. A subagent reports back through a single
hand-back message — it cannot stream incremental bundles or honour a mid-loop user
pause, whether it runs in the foreground or (the default) in the background.
Delegating either phase would either break the interaction or require routing every
turn through a subagent boundary, which is fragile. Users who want a deep-reason model
for these phases switch the session model before invoking the command.

> **Note on delivery.** Subagents do not block their parent by default: a spawn is
> backgrounded, the parent's turn ends, and the **same** report can arrive repeatedly — three
> times in one slice-045 run, with no ceiling, because each wake or resume adds a delivery.
> Every delivery carries that one final report; none is incremental. So the reasoning above is
> untouched, and this is only why the older wording "subagents block their parent on a single
> return" was dropped.
>
> CRAFT does **not** de-duplicate. Epic-003 decided the other way (design record §9, Q8):
> builders are spawned in the foreground via `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, which
> delivers once, rather than accepting repeat deliveries and filtering them on `agent_id`.
> Verified by the slice-044 / slice-045 probes.

Phases marked **session** run on whatever model the user selected for the active
Claude Code session — CRAFT does not switch the model for them.

### Source of truth

Each agent's `model:` value is declared in its own frontmatter under
`agents/<name>.md`. This table is a human-readable index; the runtime resolution
reads the agent files directly.

---

## Capability Tiers

A role is bound to a **capability tier**, not to a model name. The tier says what the
work needs; the model column says how that tier resolves today, and a model generation
can move it without the role having to be re-argued.

| Tier | Resolves to | The work it describes |
|---|---|---|
| **deep-reason** | `opus` | Judgment with no ground truth to check against: planning, architecture, independent review, a round that has to be better rather than longer. |
| **execute** | `sonnet` | Carrying out something already decided: building an approved plan, running a committed Test Strategy, summarizing, orchestrating. |

Opus lists at 2.5× Sonnet on every token class — input, output, and cache hit — so the split is
where CRAFT's token spend is decided. How the models weigh against the 5h / 7d rate windows is not
documented; the ratio is list price, not window cost.

*Checked 2026-09-17 against the bundled `claude-api` skill's pricing table (itself cached
2026-06-24): Opus 5 $5 / $25 per MTok, Sonnet 5 $2 / $10 — 2.5× on input and output, and on cache
reads too, since a cache read is 0.1× of each model's own input price.* **The ratio is
generation-specific, not a law.** It holds for Opus 5 against Sonnet 5; against Sonnet 4.6
($3 / $15) the same Opus is 1.67×. Re-check it when either tier's model moves, rather than carrying
the number forward — a third party's price list is exactly the kind of fact an internal record
cannot notice going stale (R4-4's lesson, applied here by R7-14).

### Role → tier

`effort` is filled in where it was actually decided. **`—` is not a value**: not `medium`,
not `low`, not "no effort". It means the cell was never decided, so the documented default applies —
the session's own effort level.

One exception, worth knowing before reading the table: a role realised through a **per-spawn
override** — the ping-pong row — inherits the spawned agent's own frontmatter for everything but
the model. That spawn therefore runs at `slice-builder`'s `effort: high`, not at a runtime
default. See `## Resolution Order`. (The `—` in the Default Mapping table above means something else entirely — no
delegating subagent. Same glyph, different question.)

`effort` takes `low`, `medium`, `high`, `xhigh` or `max`; which levels a model offers varies.
Claude Code's sub-agents reference documents the field for plugin agents and gives its default as
**inherits from session** — that is what a `—` row leaves in place, so the cell is undecided, not
unknown. What *is* unknown here: **no CRAFT probe has shown the field taking effect**, and
`claude plugin validate` checks no frontmatter value (an `effort: xhigh` passes), so an
unsupported one would fail silently. The risk is bounded — an ignored key costs nothing — but
nothing here is evidence that the setting bites. `/tasks` shows a running subagent's model and
effort level, which is the cheapest way to check.

| Role | Tier | `effort` | Why |
|---|---|---|---|
| Master / orchestrator | execute | medium *(proposal)* | Reads helper output and digests against a long cached context, which is exactly where 2.5× hurts most. **Condition:** every decision needing real judgment goes to the human or to a short-lived deep-reason agent. Where that line cannot be drawn, the fallback is deep-reason. |
| `slice-planner` | deep-reason | — | Planning is the hard phase. |
| `plan-architect` | deep-reason | high | Overlaps, contracts, slice order. |
| `slice-builder` | execute | high | The bulk of the tokens; it executes an approved plan. |
| Builder after a ping-pong trip | deep-reason | — | One stronger round beats more rounds of the same. |
| E2E verification | execute | — | Runs a Test Strategy that was committed in Phase 3. |
| `code-reviewer` | deep-reason | — | Independent judgment — the point of the phase. |
| Digests / recap | execute | — | Haiku saves too little to be worth the risk here. |

Roles without an `agents/<name>.md` today are the later epic-003 slices' agents; they
inherit their row from this table rather than deciding a model of their own.

### Cache TTL — a rule, not a column

A subagent's prompt cache defaults to a 5-minute TTL, so every gap longer than that
re-writes the agent's whole prefix. `experimental: {cacheTtl: 1h}` in the agent file
switches it to an hour, and it works for plugin agents.

It is not free in either direction. With list multipliers — writes 1.25× at 5m and 2× at
1h, reads 0.1× — a gap costs the 5m agent 1.25× its context and the 1h agent a 0.1×
read. **1h pays off once the contexts re-written at gaps sum to more than ≈ 0.65 × the
final context**: one long wait after the context reached about two thirds of its size, or
two waits in the second half. Without such waits, 1h costs roughly 60% more on writes.

*Multipliers checked 2026-09-17 against the bundled `claude-api` skill (`shared/prompt-caching.md`
§ Economics): writes 1.25× at 5m and 2× at 1h, reads ≈ 0.1× of base input — confirmed.* **One
documented exception already exists:** Claude Fable 5.1 reads at 0.025×, not 0.1×, which moves every
break-even above it. The 0.65 figure is derived from the 0.1× read rate, so it does not hold for a
model priced that way — and since `fable` is a value a human may write into a project profile, that
is reachable here, not hypothetical. Re-derive rather than reuse when the read rate differs.

So the choice follows the agent's shape, not its tier:

- **1h** — an agent that waits: long test suites, external services, anything that idles
  inside a tool call. `slice-builder`, E2E verification.
- **5m (default, no `experimental` block)** — a short-burst agent that reads, reasons and
  reports without waiting. `code-reviewer`, planners, digests.

How cache writes count against the 5h / 7d rate windows is not documented, so the
break-even above is list price only; calibration decides the real figure. The setting
degrades safely either way: frontmatter `experimental` may change, and its `1h` is
ignored while the subscription spends usage credits — the documentation states that rule for
the frontmatter field and says nothing about the `subagentPromptCacheTtl` setting — an ignored TTL costs a cache write, never a wrong answer.

**Why the master has no row of its own to set.** The master is the main session, and a
command's `model:` frontmatter switches only the turn that loads it — it re-reads the
whole context uncached and reverts on the next prompt. CRAFT therefore cannot hold the
master on a tier; the human starts the session on it, and a command that depends on it
checks the session model rather than switching it.

---

## Per-Project Overrides

A project may override any agent's model by adding an `## Agent Model Overrides`
section to its `.claude/project/craft-profile.md`:

```markdown
## Agent Model Overrides

- slice-builder: opus
- code-reviewer: haiku
```

### Format

- Section heading must be exactly `## Agent Model Overrides`.
- One entry per line, format `<agent-name>: <model-value>`.
<!-- craft:model-enum -->
- Allowed model values: `opus`, `sonnet`, `haiku`, `inherit`, `fable`, `<model-id>`
- **Not all of them reach an agent.** This line is the values the *format* accepts; a project
  override is carried to a running agent by the Agent tool's `model` parameter, which takes a
  narrower set. An override outside it is reported by `/craft:prime` as inert and dropped at
  spawn time, so the agent runs on its frontmatter model. Which values reach a spawn is stated
  once, in **Spawn-Reachable Values** above — not in *Allowed Model Values*, which carries the
  wider set an agent's own frontmatter accepts and says in so many words that the spawn set is
  not restated there.
- What `<model-id>` means, why the aliases are preferred, and why nothing here validates a
  full model ID: **Allowed Model Values** above. It is stated once, there.
- `fable` is accepted as a profile value, and is also spawn-reachable; the human-chosen-only
  rule that governs it is in **Allowed Model Values** → *fable*.
- An empty section, or a missing section, means "use defaults".

### Why a project would override

- **Cost control**: pin everything to `haiku` for low-stakes spike work.
- **Speed**: drop `code-reviewer` to `sonnet` for trivial single-file slices.
- **Capability**: upgrade `slice-builder` to `opus` for a risky migration slice.

---

## Resolution Order

1. **Default** — `model:` from the agent's own frontmatter (`agents/<name>.md`).
2. **Project override** — matching entry in `craft-profile.md` → `## Agent Model Overrides`,
   if present.
3. **Per-spawn override** — a model passed by the command at the moment it spawns the
   agent, for that one spawn only.

**Source 2 only exists where a spawn site applies it.** A project override is read by
`/craft:prime` but *used* by the command that starts the agent, so each spawn site carries the
instruction: `commands/review.md` and `skills/debug/SKILL.md` → Autonomous Mode (the Protocol
Freeze spawn) for `code-reviewer`, `commands/execute.md` step 5 for `slice-builder`. A new agent whose spawn site omits it gets an override that prime reports and
nothing honours — which is exactly what happened to `slice-builder` until review round 5 found
it.

**Adding a third agent is therefore six edits, not one.** Each is load-bearing. Three of them are
now caught mechanically — `scripts/test-model-enum.sh` loops over `agents/*.md`, so a missing tier
row (3), a contradicting Default Mapping row (2) and a missing Cache TTL bullet (4) all fail the
run — and **three still fail quietly**:

1. **The spawn site's two sentences** — the pointer to *What a spawn site must do*, **and** the
   unreachable-declaration fallback of step 4. Without the pointer the agent's override is reported
   and ignored (the round-5 defect); without the fallback the override vanishes silently when this
   file cannot be read (B-R7-1). *Fails quietly*, and the new site is outside both harness checks
   until edit 6 registers it. That is the same shape as R7-13, and it is why this entry names both
   sentences instead of "the sentence".
2. **A `## Default Mapping` row** — otherwise nothing states the agent's intended model.
   *Caught: the tier cross-check reads this row.*
3. **A `### Role → tier` row** — otherwise the agent has no capability tier.
   *Caught: the harness reports an agent no Role → tier row assigns.*
4. **A bullet under `### Cache TTL — a rule, not a column`** — assigning the agent to 1h or the
   5m default. *Caught since review round 9:* `role_ttl()` reads the bullets and `role_effort()`
   the Role → tier row's `effort` cell, per agent in the same loop, so an agent named by neither
   bullet fails the run — and so does a table that disagrees with the frontmatter, in **both**
   directions. Until then both were literals in the harness naming two agents (F1).
5. **The published surface** — the `Agent Model Overrides` row in `docs/index.html` (both
   languages) and `README.md` both name today's agents inline, and `test-docs-site.sh` does not
   check that list. A third agent never appears to a human reading the docs. *Fails quietly.*

6. **The harness's reader lists** — add the new command file to `DECLARATION_READERS` **and**
   `SPAWN_SITES` in `scripts/test-model-enum.sh`. Both name their files literally, so until you do,
   edits 1's two sentences are checked by nothing for the new site. *Fails quietly.*

*No **tier** registration in the harness is needed any more.* It used to be obligation 4: the tier
assertions named two agents literally, so an unregistered third was invisible (review round 7,
R7-13, reproduced green). The loop replaced that one obligation — the better trade whenever a
documented duty can become a mechanical one. It did **not** generalise: edit 6 above is the reader
lists, which are still literal (review round 9, P5).

The later source wins: a per-spawn override beats a project override, which beats the
agent's own default. **These are the sources CRAFT controls — they are not the only ones.**

### Sources outside CRAFT's reach

Claude Code resolves a subagent's model in four steps: *"1. The per-invocation `model` parameter ·
2. The subagent definition's `model` frontmatter, where `inherit` selects the main conversation's
model · 3. The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable, when you set it to a model alias
or model ID · 4. The main conversation's model."* Step 4 is what an agent with no frontmatter
`model:` — or one whose value an allowlist substituted away — lands on. Each input below can decide which model a
subagent runs on, and none of them is visible to CRAFT. They do not all *override* CRAFT's sources
— the first applies only where CRAFT's own sources leave the choice open; each bullet says which it
is (sub-agents reference, checked 2026-09-16; `model-config.md`, checked 2026-09-17):

- **`CLAUDE_CODE_SUBAGENT_MODEL`** — a default beneath the first two, so it decides for any
  agent that names no model. CRAFT's agents all name one, so it reaches them only through the
  next entry.
- **`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`** (Claude Code v2.1.257+) — while it is on, *"Claude
  Code ignores the `model` field of every subagent definition"* and a command cannot pass a model
  at spawn. It overrides all three CRAFT sources at once. With `CLAUDE_CODE_SUBAGENT_MODEL` also
  set, every subagent runs on that model; with `FORCE=1` alone, every subagent runs on the main
  conversation's model.
- **A fallback model chain** (`--fallback-model`, or `fallbackModel` in settings) — when a
  subagent's request fails over, Claude Code continues it on the first chain model that accepts
  the request instead of ending the run. Whether a nonexistent model ID counts as a covered
  failure is not documented.
- **Content-based automatic fallback** — separate from the chain above, and the one input that
  targets exactly the two models this file is about. Fable models and Opus 5 run safety
  classifiers (most often cybersecurity and biology content); when one flags a request and the
  flagged category has a fallback model, Claude Code **re-runs the request on that model, shows a
  notice in the transcript, and continues on the fallback model**. Documented targets: Fable 5.1 /
  Fable 5 — biology → Opus 5, cybersecurity → Opus 4.8; Opus 5 — cybersecurity → Opus 4.8, while a
  biology flag ends in a refusal with no fallback. A user can turn the automatic switch off
  (`switchModelsOnFlag: false`), which makes a flagged request pause for a choice instead. Requires
  Claude Code v2.1.219+. Note what this does to the `fable` cost warning: a flagged Fable request
  does not bill Fable at all — it runs on Opus. The warning is about the configuration, not a
  prediction about any single request.
- **An organization `availableModels` allowlist** — checked against the per-invocation
  parameter, the frontmatter *and* the environment variable. A blocked value is substituted:
  a family alias resolves to the newest permitted version, anything else falls back to the
  inherited model. The documentation promises a warning naming both models in interactive
  sessions and says nothing about other sessions.

**What this means for what you read.** `/craft:prime` reports what CRAFT *asked for*, not what
ran; it has no way to see any of them. Where one is in play, the model a subagent actually
runs on is shown by `/tasks` while it is running. Treat prime's line as a statement about this
project's configuration, not as an observation of the runtime.

*Why this is written down here:* the section previously ended "No further sources", which four
review rounds did not catch, because each round checked this slice against CRAFT's own design
record — and a record cannot notice that a third-party tool moved underneath it.

### When a per-spawn override is legitimate

A per-spawn override exists so a command can react to something it only learns at
runtime — the agent file and the project profile are both written before the run. It wins over
both, and it is the only one of CRAFT's three sources that leaves no trace in a file, so it is
deliberately bounded.

**It reaches the agent through the same narrow parameter a project override does**, so it carries
the same set — declared once in `## Spawn-Reachable Values`, and deliberately not restated here.
That limit is not special to the per-spawn case; it applies to anything that travels the `model`
parameter. A command that needs a value outside it cannot express that at spawn time, and neither
can a project override, since it travels the same parameter; only the agent file can.

**And it carries a model only**, one of the spawn-reachable values. `effort` and `experimental`
stay as the spawned agent's own frontmatter declares them. So realising a role through a per-spawn override — the ping-pong
breaker raising the builder to deep-reason — changes the model and nothing else: that spawn
keeps `slice-builder`'s `effort: high` and its 1h cache TTL. The `effort` cell of the role's
row is not reachable this way.

The bounds on when it may be used:

- A command may raise a role to **deep-reason** for a single spawn when the run has
  produced evidence that the execute tier is not converging — the ping-pong breaker's
  re-spawn of the builder after a trip is the designed case.
- A command may pass a model the **human chose for that run** and that CRAFT would not
  select on its own.
- A command may **not** use it to lower a role's tier to save tokens, to set `fable` **of its own
  accord**, or to encode a preference that belongs in `agents/<name>.md` or the project profile. A
  standing choice is written down where the next reader will find it. *Carrying* a `fable` the human
  put in the project profile is not this case — that is source 2 arriving through the same parameter,
  and it is required, not forbidden (`## Spawn-Reachable Values` → *What a spawn site must do*).

A command that passes a per-spawn override **must** name it in the run's output, so the human can see which model
actually ran and why.

---

## Validation

`/craft:prime` reads the overrides during its pre-flight check and reports, per agent, the
model **CRAFT will ask for at spawn time** — never an observation of what runs (see *Sources
outside CRAFT's reach*).

**Prime does not validate model values.** It checks the agent name; a value it does not
recognise is reported **as written**, not rejected. Whether that value ever reaches the agent
is decided by **Spawn-Reachable Values** — an unreachable one is **dropped** at the spawn
rather than passed to the runtime, which is why prime reports it as inert. For where a value
written into an *agent file* actually fails, see **Allowed Model Values** above.

What prime emits, and on which condition, is defined once in `commands/prime.md` → step 4b.
It is not restated here: this file owns the *values and the policy*, that step owns the
*output*, and two descriptions of one contract are how the Phase-7 routing bug survived five
reviews (`rules.md` → Tabus).

This is a plain pointer, deliberately not a `craft:delegates` token. That token is bound by
`scripts/test-workflow-status-graph.sh`, which scans `commands/` against a delegation table; a
token here would sit outside both and only *look* checked. Binding it would mean widening that
harness's scope, its hand-maintained table and its target syntax — a change to another
harness's contract, and its own piece of work.



---

## Verification — does `model:` actually take effect?

[GitHub issue #173](https://github.com/affaan-m/everything-claude-code/issues/173)
reported that the `model:` field in agent frontmatter was non-functional in
earlier Claude Code versions: all agents defaulted to Opus regardless of their
declared model. Before relying on this feature in production, verify the runtime
respects the pin in your installed Claude Code version.

### Procedure

1. Install the latest CRAFT release (`/craft:upgrade`).
2. From any Claude Code session, ask Claude to invoke the `code-reviewer` agent
   via the `Task` tool with `subagent_type: "code-reviewer"` and a trivial
   prompt. You can ask Claude directly:

   > Spawn the `code-reviewer` subagent with the prompt:
   > "Report your model identity in one line — for example,
   > 'I am running on Claude Opus 4.7'. Do not do any other work."
   > Show me its reply.

3. Inspect the agent's reply. If it names the model declared in
   `agents/code-reviewer.md` frontmatter (`opus` / Claude Opus), the pin is
   honoured.
4. If it names a different model (e.g. defaulted to the session model), the
   issue is still present in your version — file an upstream bug and fall back
   to switching the session model manually for review work.

This is a one-shot check per Claude Code version upgrade.
