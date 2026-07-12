#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-workflow-status-graph.sh — asserts the phase-transition graph is closed and
# that the commands agree with it.
#
# WHY ------------------------------------------------------------------------
# A slice moves between phases by its plan's `Status:` token: one command writes it,
# another consumes it. Nothing checked that the two ever met. Slice-031 (roadmap B1)
# found the consequence: in a project whose rules.md drops Phase 7, /craft:recap's only
# route out of Phase 6 led to /craft:refactor — a command that project never runs — so
# the slice stranded at `review`, which /craft:review reads as pre-Phase-8 and answers
# with advisory mode (findings only, Commit never gated). No test could have caught it:
# the graph existed only as prose scattered across a dozen command files.
#
# WHAT -----------------------------------------------------------------------
# skills/workflow/SKILL.md (## Phase Transition Rules) carries the graph as a
# machine-readable table between <!-- craft:transitions --> markers, and each command
# carries markers on the affirmative writes and reads:
#
#   <!-- craft:writes status=<x> [when=<config>] -->
#   <!-- craft:reads  status=<x> -->
#
# The markers exist because PROSE IS NOT CHECKABLE. This harness's first version
# grepped the command text for `Status: <x>`, and a grep cannot tell the sentence that
# prescribes a write from the one that forbids it: deleting an entire routing branch
# left it green, because the literal survived in a "never write this" sentence. Only
# markers count now, and a prohibition carries none.
#
#   GRAPH        — for each Phase-7 configuration, the live rows must form a closed
#                  graph: /craft:commit reachable from /craft:plan, the Phase-8 entry
#                  (`reviewing`) producible, and no live row handing to a command the
#                  configuration disables (an orphan status).
#   COMPLETENESS — both directions. Every craft:writes/craft:reads marker in commands/
#                  must have a matching table row, AND every row must have its
#                  producer's write-marker and its consumer's read-marker. A status a
#                  command writes but the table forgets is a failure, not a blind spot.
#   DETECTION    — the Phase-7-dropped rule is itself prose ("a ## Workflow Rules bullet
#                  declares Phase 7 dropped or skipped"). Assert this project's rules.md
#                  actually satisfies the canonical form, so the rule that gates the
#                  whole routing change is a checked contract, not an LLM judgment.
#   SECTIONS     — the plan sections /craft:plan's P2 asserts on must exist in the
#                  slice-plan template. (P2 spent its life requiring `## Observable
#                  Effect`, which the template never emitted.)
#
# LIMITS, stated plainly — an earlier version of this header overstated them, and a
# reviewer proved it:
#   * A **craft:writes** marker must sit ON or within 6 lines ABOVE the `Status: <x>`
#     instruction it describes; markers inside fenced code blocks are ignored (both enforced).
#     **craft:reads markers are NOT adjacency-checked** — a consumer accepts a status in prose
#     that often does not spell `Status: <x>` (a routing-table cell, a pre-flight sentence), so
#     the literal cannot be required. What is NOT enforced for either kind is that the
#     surrounding sentence *means* what the marker says: prose within the window can still
#     drift from it. An honest deletion takes the marker with it and goes red; only deliberate
#     sabotage (keeping the marker, inverting the sentence) survives.
#   * Exactly one marker per row — for writes AND reads. Two markers on one row cover for each
#     other, so the row binds neither; that duplication let a deleted gate stay green twice,
#     and a stray reads marker once made the suite *greener* than the truth.
#   * The ROUTER check reads /craft:continue's routing cell POSITIONALLY (the first command
#     named). A cell reworded into a prohibition ("do NOT run /craft:recap yet") would pass
#     while misrouting a human. A `craft:routes` token would close this; it is a recorded
#     follow-up, not a claim.
#   * DELEGATION binds the craft:delegates TOKEN'S PRESENCE and the absence of a competing
#     status write — it does NOT bind the meaning of the prose beneath the token. A section
#     that keeps the token and negates the rule in words ("the subagent does NOT apply the
#     Pre-flight gate…") still passes. Tokenizing this check fixed relocation and renaming,
#     not negation: the negation never lived in the phrase's absence, it lives in the prose,
#     and a token is exactly as blind to prose as a grep was. Same residual as marker drift,
#     stated here because an earlier version of this file claimed the token had closed it.
# What the harness does guarantee: the declared graph is coherent, and no command silently
# loses, gains, or duplicates a *marked* status write.
#
# Run it directly (optionally against another checkout, e.g. to prove it goes red
# against a pre-fix HEAD):
#
#   bash scripts/test-workflow-status-graph.sh [ROOT]
#
# It writes nothing, anywhere.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

SKILL="$ROOT/skills/workflow/SKILL.md"
COMMANDS="$ROOT/commands"
TEMPLATE="$ROOT/templates/slice-plan.md.template"
PLAN_CMD="$COMMANDS/plan.md"
RULES="$ROOT/.claude/project/rules.md"

for f in "$SKILL" "$TEMPLATE" "$PLAN_CMD"; do
  [[ -f "$f" ]] || { echo "FATAL: expected file not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

# --- parse the canonical transition table ------------------------------------
# One "producer<TAB>status<TAB>consumer<TAB>config" line per row. The heredoc is
# quoted and the file path is passed as argv: no shell data lands in Python source.
rows="$(python3 - "$SKILL" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<!-- craft:transitions -->(.*?)<!-- /craft:transitions -->", text, re.S)
if not m:
    sys.exit(0)                     # no table → zero rows → GRAPH fails loudly below
for line in m.group(1).splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip().strip("`").strip() for c in line.strip("|").split("|")]
    if len(cells) != 4:
        continue
    if cells[0].lower() in ("producer", "") or set(cells[0]) <= set("-: "):
        continue                    # header / separator
    print("\t".join(cells))
PY
)"

if [[ -z "$rows" ]]; then
  echo "FATAL: no transition table found in $SKILL (expected between <!-- craft:transitions --> markers)" >&2
  exit 2
fi

# --- parse the markers out of every command ----------------------------------
# One "kind<TAB>command<TAB>status<TAB>when" line per marker (when="" if unscoped).
markers="$(python3 - "$COMMANDS" <<'PY'
import os, re, sys
d = sys.argv[1]
pat = re.compile(r"<!--\s*craft:(writes|reads)\s+status=([a-z-]+)(?:\s+when=([a-z0-9-]+))?\s*-->")
ADJACENCY = 6   # lines after the marker within which the prescribed write must appear

for name in sorted(os.listdir(d)):
    if not name.endswith(".md"):
        continue
    cmd = "/craft:" + name[:-3]
    raw = open(os.path.join(d, name), encoding="utf-8").read().splitlines()

    # Blank out fenced code blocks: a marker parked in an example is not an instruction.
    # (A reviewer disarmed an earlier version by hiding a marker in a fenced block under
    # "What This Command Does NOT Do" — the harness stayed green.)
    lines, fenced = [], False
    for ln in raw:
        if ln.lstrip().startswith("```"):
            fenced = not fenced
            lines.append("")
            continue
        lines.append("" if fenced else ln)

    for i, ln in enumerate(lines):
        for kind, status, when in pat.findall(ln):
            adjacent = ""
            if kind == "writes":
                # The marker must sit ON or ABOVE the instruction that writes the status:
                # a `Status: <x>` literal has to appear within the next few lines. A marker
                # floating anywhere in the file proves nothing about what the command does.
                window = "\n".join(lines[i:i + 1 + ADJACENCY])
                adjacent = "yes" if re.search(r"Status:\s*`?" + re.escape(status) + r"`?\b", window) else "no"
            # "-" for an absent `when=`, never "": bash's `read` with IFS=$'\t' collapses
            # runs of IFS *whitespace*, so an empty field would silently vanish and shift
            # every later field left. (It did, and produced when='yes'.)
            print("\t".join((kind, cmd, status, when or "-", adjacent or "-")))
PY
)"

# --- GRAPH: closure under each Phase-7 configuration -------------------------
echo "GRAPH:"
for cfg in phase7-kept phase7-dropped; do
  live="$(awk -F'\t' -v c="$cfg" '$4 == "any" || $4 == c' <<< "$rows")"

  # A Phase-7-dropped project never runs /craft:refactor; a live row handing a status
  # to it would strand the slice in a phase that never executes.
  if [[ "$cfg" == "phase7-dropped" ]]; then
    orphan="$(awk -F'\t' '$3 == "/craft:refactor" { print $2 }' <<< "$live" | sort -u | tr '\n' ' ')"
    [[ -z "${orphan// /}" ]] \
      && ok "[$cfg] no live row hands to /craft:refactor (no orphan status)" \
      || bad "[$cfg] orphan status(es) '${orphan% }' → consumed only by /craft:refactor, which this config never runs"
  fi

  awk -F'\t' '$2 == "reviewing"' <<< "$live" | grep -q . \
    && ok "[$cfg] Phase-8 entry status 'reviewing' is producible" \
    || bad "[$cfg] nothing produces 'reviewing' → /craft:review can never enter Phase-8 mode"

  # /craft:commit must stay reachable from /craft:plan across the live edges.
  reach="$(printf '%s\n' "$live" | python3 -c '
import collections, sys
edges = collections.defaultdict(list)
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line.strip():
        continue
    p, s, c, _cfg = line.split("\t")
    edges[p].append(c)
seen, stack = set(), ["/craft:plan"]
while stack:
    n = stack.pop()
    if n in seen:
        continue
    seen.add(n)
    stack.extend(edges.get(n, []))
print("yes" if "/craft:commit" in seen else "no")
')"
  [[ "$reach" == "yes" ]] \
    && ok "[$cfg] /craft:commit is reachable from /craft:plan" \
    || bad "[$cfg] /craft:commit is NOT reachable from /craft:plan — the phase chain is broken"
done

# --- COMPLETENESS: markers ↔ table, in both directions ------------------------
echo "COMPLETENESS:"

# (0a) a `when=` must name a real configuration, or the scoping is silently meaningless.
# (0b) a craft:writes marker must actually SIT on the instruction it describes.
while IFS=$'\t' read -r kind cmd status when adjacent; do
  [[ -n "${kind:-}" ]] || continue
  if [[ "$when" != "-" ]]; then
    case "$when" in
      phase7-kept|phase7-dropped)
        # `when=` scopes a WRITE to a configuration. A read is config-independent — no table row
        # distinguishes a consumer by config — so a `when=` on a reads marker means nothing and
        # would invite a future author to believe it does. Hard error, not a silent no-op.
        [[ "$kind" == "reads" ]] && bad "${cmd#/craft:}.md has a craft:reads marker with when='$when' — reads are config-independent (no row distinguishes a consumer by config), so the scope is meaningless. Drop the when=."
        ;;
      *) bad "${cmd#/craft:}.md has a marker with when='$when' — not a known configuration (phase7-kept | phase7-dropped)" ;;
    esac
  fi
  if [[ "$kind" == "writes" && "$adjacent" != "yes" ]]; then
    bad "${cmd#/craft:}.md has a craft:writes marker for '$status' with no 'Status: $status' instruction within 6 lines below it — a marker floating away from its instruction proves nothing"
  fi
done <<< "$markers"

# (1) every row must have its producer's write-marker and its consumer's read-marker.
#     The write-marker's `when=` must MATCH the row's Config — an `any` row pairs with an
#     unscoped marker, a config-scoped row with a marker carrying that exact `when=`. This
#     is what keeps two routes to the same status distinguishable: /craft:refactor writes
#     `reviewing` both at its phase end (phase7-kept) and via the skip gate (phase7-dropped),
#     and with a single `any` row either marker alone satisfied it — so the skip gate could
#     be deleted together with its marker and the harness stayed green.
while IFS=$'\t' read -r producer status consumer config; do
  [[ -n "${producer:-}" ]] || continue
  want_when="-"                       # "-" is the marker table's encoding of "unscoped"
  [[ "$config" != "any" ]] && want_when="$config"

  # EXACTLY one marker per row — not "at least one". Duplicate coverage is how the disarm
  # keeps coming back: with two markers satisfying one row, either can be deleted and the
  # other covers for it, so the row binds neither. One route, one marker, one row.
  nmark="$(awk -F'\t' -v c="$producer" -v s="$status" -v w="$want_when" \
       '$1 == "writes" && $2 == c && $3 == s && $4 == w' <<< "$markers" | grep -c .)"
  scope=""; [[ "$want_when" != "-" ]] && scope=" (when=$want_when)"
  if (( nmark == 1 )); then
    ok "$producer carries exactly one craft:writes marker for '$status'$scope"
  elif (( nmark == 0 )); then
    bad "table row '$producer → $status' [$config] has NO matching craft:writes marker in ${producer#/craft:}.md${scope/ (when=/ (expected when=} — the write was removed, renamed, or mis-scoped"
  else
    bad "table row '$producer → $status' [$config] has $nmark craft:writes markers in ${producer#/craft:}.md — exactly one expected; duplicate coverage means either can be deleted while the other hides it"
  fi

  # Same exactly-one rule as the writes half. A stray second reads marker (parked anywhere in
  # the file, since reads are not adjacency-checked) would otherwise cover for a deleted read
  # gate — and a consumer that no longer accepts the status it is named for is B1's own shape.
  nread="$(awk -F'\t' -v c="$consumer" -v s="$status" \
       '$1 == "reads" && $2 == c && $3 == s' <<< "$markers" | grep -c .)"
  if (( nread == 1 )); then
    ok "$consumer carries exactly one craft:reads marker for '$status'"
  elif (( nread == 0 )); then
    bad "table row '$status → $consumer' has NO craft:reads marker in ${consumer#/craft:}.md — the consumer does not accept the status it is named for"
  else
    bad "table row '$status → $consumer' has $nread craft:reads markers in ${consumer#/craft:}.md — exactly one expected; a stray marker would cover for a deleted read gate"
  fi
done <<< "$rows"

# (2) every marker must have a matching row — a status a command writes but the table
#     forgets would otherwise be invisible to every check above.
while IFS=$'\t' read -r kind cmd status when adjacent; do
  [[ -n "${kind:-}" ]] || continue
  if [[ "$kind" == "writes" ]]; then
    # the marker's scope must land on a row with the matching Config (unscoped "-" ↔ `any`)
    wcfg="$when"; [[ "$wcfg" == "-" ]] && wcfg="any"
    scope=""; [[ "$when" != "-" ]] && scope=" (when=$when)"
    awk -F'\t' -v c="$cmd" -v s="$status" -v w="$wcfg" '$1 == c && $2 == s && $4 == w' <<< "$rows" | grep -q . \
      && ok "craft:writes '$status'$scope in ${cmd#/craft:}.md has a table row" \
      || bad "${cmd#/craft:}.md writes '$status'$scope but the transition table has NO row with that Config — invisible to the graph"
  else
    awk -F'\t' -v c="$cmd" -v s="$status" '$3 == c && $2 == s' <<< "$rows" | grep -q . \
      && ok "craft:reads '$status' in ${cmd#/craft:}.md has a table row" \
      || bad "${cmd#/craft:}.md reads '$status' but the transition table has NO row naming it as consumer"
  fi
done <<< "$markers"

# --- ROUTER: /craft:continue's recommendations must match the graph -----------
# /craft:continue IS the router: on resume it decides which command a slice at a given
# Status goes to. Its routing table must therefore recommend the graph's consumer for
# that status — and recommend it *first*, since the first command named is the one the
# user follows. This is what binds the routing text itself, not merely the file: the
# marker checks above would stay green if someone rewrote a routing row while leaving
# the markers intact. (Before slice-031, `review` routed backwards to /craft:test.)
#
# Exempt: rows consumed by /craft:continue itself (`paused` — it routes by the Phase:
# field, naming no command), and `planning` (legitimately offers /craft:plan first, to
# finish planning, before /craft:build).
echo "ROUTER:"
router_out="$(python3 - "$COMMANDS/continue.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for line in text.splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) != 2:
        continue
    m = re.match(r"`([a-z-]+)`", cells[0])          # status is the leading `code` span
    if not m:
        continue
    first = re.search(r"/craft:[a-z-]+", cells[1])  # the first command it names
    print("\t".join((m.group(1), first.group(0) if first else "")))
PY
)"

while IFS=$'\t' read -r producer status consumer config; do
  [[ -n "${producer:-}" ]] || continue
  [[ "$consumer" == "/craft:continue" ]] && continue     # routes by Phase:, names no command
  [[ "$status" == "planning" ]] && continue              # /craft:plan-first is intended
  routed="$(awk -F'\t' -v s="$status" '$1 == s { print $2; exit }' <<< "$router_out")"
  if [[ -z "$routed" ]]; then
    bad "/craft:continue has no routing row for '$status' — a resumed slice at that status is stranded"
  elif [[ "$routed" == "$consumer" ]]; then
    ok "/craft:continue routes '$status' → $consumer (matches the graph)"
  else
    bad "/craft:continue routes '$status' → $routed, but the graph's consumer is $consumer — the router sends the slice the wrong way"
  fi
done <<< "$(awk -F'\t' '!seen[$2 FS $3]++' <<< "$rows")"   # dedup by (status, consumer), not status:
                                                          # the Config column exists precisely so a
                                                          # status MAY get config-dependent consumers.

# --- DELEGATION: the subagent path must not restate the Phase-7 rule ----------
# /craft:refactor describes its behavior twice — interactively, and for the slice-builder
# subagent. Restating the Phase-7-dropped rule in both is how B1 survived in the first place
# (the subagent path handled the drop; the interactive one did not), and a second copy also
# re-opens the duplicate-marker disarm the exactly-one-marker rule above just closed. So the
# subagent section must DELEGATE to the one gate rather than carry its own rule. This asserts
# the delegation is there — deleting it would silently strip the drop from /craft:execute's
# chain, and no status-write check could see that, because delegation writes nothing.
# The delegation carries a MACHINE-READABLE TOKEN, not a phrase — the first version of this
# check was a grep for "pre-flight gate", and a reviewer passed it by writing the rule's
# *negation* ("the subagent does NOT apply the pre-flight gate…"): green, while re-introducing
# both the Phase-5-skip regression and the duplicate-contract defect. A grep cannot tell a
# prescription from a prohibition — the same lesson the markers exist for, applied one level up.
echo "DELEGATION:"
verdict="$(python3 - "$COMMANDS/refactor.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^##\s+Subagent Mode\b.*?$(.*?)(?=^##\s|\Z)", text, re.S | re.M)
if not m:
    print("NOSECTION"); sys.exit()
body = m.group(1)
# ignore fenced examples, as everywhere else
lines, fenced = [], False
for ln in body.splitlines():
    if ln.lstrip().startswith("```"):
        fenced = not fenced; lines.append(""); continue
    lines.append("" if fenced else ln)
body = "\n".join(lines)

token = re.search(r"<!--\s*craft:delegates\s+rule=phase7-dropped\s+to=preflight\s*-->", body)

# A delegating section must not carry its own status write — that would be a restated rule,
# and two descriptions of one contract is the defect B1 came from. Check BOTH a marker and a
# plain-prose `Status: <x>` literal: an earlier version looked only for the marker, and a
# reviewer restated the whole rule in prose ("set `Status: reviewing` … at ANY status") while
# the harness cheerfully reported "restates no status write".
GRAPH_STATUSES = ("planning", "implementing", "testing", "review", "refactoring",
                  "reviewing", "committing", "blocked", "paused", "awaiting-release",
                  "awaiting-approval")
# The .craft/handoff.md namespace is a different artifact and may legitimately appear here.
prose_write = any(re.search(r"Status:\s*`?" + s + r"`?\b", body) for s in GRAPH_STATUSES)
marker_write = re.search(r"<!--\s*craft:writes\s", body)

print("OK" if token and not marker_write and not prose_write else
      "RESTATES" if token else
      "NOTOKEN")
PY
)"
case "$verdict" in
  OK)        ok "refactor.md's Subagent Mode carries the craft:delegates token and declares no status write of its own" ;;
  NOSECTION) bad "refactor.md has no '## Subagent Mode' section — the autonomous path is undefined" ;;
  RESTATES)  bad "refactor.md's Subagent Mode carries the craft:delegates token but ALSO declares a status write of its own (a craft:writes marker, or a 'Status: <x>' literal in its prose) — a restated rule. Two descriptions of one contract is how B1 survived; the subagent section must delegate to the Pre-flight gate, not re-declare it" ;;
  NOTOKEN)   bad "refactor.md's Subagent Mode carries no <!-- craft:delegates rule=phase7-dropped to=preflight --> token — the delegation was removed, relocated, or the section renamed, which strips the Phase-7 drop from /craft:execute's chain (and no status-write check can see that, because a delegation writes nothing)" ;;
esac

# --- DETECTION: the Phase-7-dropped rule is a checked contract ----------------
# The rule is prose four commands must agree on. Assert this project's rules.md
# actually matches the canonical form, so the gate is verified, not assumed.
# Four commands resolve the Phase-7 drop by matching prose. The failure mode is NOT a
# missing bullet — a project with no Phase-7 bullet simply keeps Phase 7, which is a valid
# state. The failure mode is a **near miss**: a bullet that talks about Phase 7 in wording
# the commands do not match ("Phase 7 is not part of this project's workflow"), which reads
# to a human as "dropped" and to the commands as "kept" — silently flipping the whole
# routing. That ambiguity is what this asserts, and it is the only outcome that can fail.
echo "DETECTION:"
if [[ -f "$RULES" ]]; then
  verdict="$(python3 - "$RULES" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^##\s+Workflow Rules\s*$(.*?)(?=^##\s|\Z)", text, re.S | re.M)
body = m.group(1) if m else ""
bullets = [ln for ln in body.splitlines() if ln.lstrip().startswith("-")]
drops = lambda ln: re.search(r"\b(dropped|skipped)\b", ln, re.I)

# Canonical: names Phase 7 AND declares it dropped/skipped. That is what the commands match.
canonical = [ln for ln in bullets if re.search(r"phase\s*7\b", ln, re.I) and drops(ln)]

# Near miss, in BOTH directions — each reads to a human as "dropped" and to the commands as "kept":
#   - names Phase 7 but not in the canonical wording ("Phase 7 is not part of this workflow")
#   - declares a refactor phase dropped without naming Phase 7 ("The Refactor phase is dropped")
ambiguous = [ln for ln in bullets if ln not in canonical and (
    re.search(r"phase\s*7\b", ln, re.I) or (re.search(r"\brefactor\w*\b", ln, re.I) and drops(ln))
)]

if canonical:
    print("DROPPED")
elif ambiguous:
    print("AMBIGUOUS\t" + ambiguous[0].strip()[:90])
else:
    print("KEPT")
PY
)"
  case "$verdict" in
    DROPPED)
      ok "rules.md declares Phase 7 dropped in the canonical form the commands match on" ;;
    KEPT)
      ok "rules.md has no Phase-7 bullet — this project keeps Phase 7 (a valid state)" ;;
    AMBIGUOUS*)
      bad "rules.md mentions Phase 7 but NOT in the canonical form ('dropped' / 'skipped'): \"${verdict#AMBIGUOUS	}\" — /craft:recap, /craft:refactor, /craft:continue and /craft:execute all match on that wording, so as written they will treat Phase 7 as KEPT. Reword the bullet, or the drop silently stops applying." ;;
    *)
      bad "DETECTION could not classify rules.md — unexpected parser output '$verdict'" ;;
  esac
else
  ok "no .claude/project/rules.md at ROOT — detection check not applicable"
fi

# --- SECTIONS: the plan sections /craft:plan asserts on must exist ------------
echo "SECTIONS:"
missing="$(python3 - "$PLAN_CMD" "$TEMPLATE" <<'PY'
import re, sys
plan = open(sys.argv[1], encoding="utf-8").read()
tpl  = open(sys.argv[2], encoding="utf-8").read()
heads = {re.sub(r"\s*\(optional\)\s*$", "", h).strip()
         for h in re.findall(r"^##\s+(.+?)\s*$", tpl, re.M)}
m = re.search(r"^###\s+P2\b.*?$(.*?)(?=^###\s|\Z)", plan, re.S | re.M)
asserted = re.findall(r"^-\s+`##\s+(.+?)`\s*$", m.group(1) if m else "", re.M)
if not asserted:
    print("!NONE")
for name in asserted:
    if name.strip() not in heads:
        print(name.strip())
PY
)"

if [[ "$missing" == "!NONE" ]]; then
  bad "/craft:plan P2 enumerates no plan sections — the section assertion is vacuous"
elif [[ -z "$missing" ]]; then
  ok "every plan section /craft:plan asserts on exists in slice-plan.md.template"
else
  while read -r name; do
    [[ -n "$name" ]] || continue
    bad "/craft:plan P2 requires section '## $name', which slice-plan.md.template never emits"
  done <<< "$missing"
fi

echo
if (( FAIL == 0 )); then
  echo "RESULT: $PASS passed, 0 failed — closed transition graph, markers and table agree"
else
  echo "RESULT: $PASS passed, $FAIL failed"
fi
[[ $FAIL -eq 0 ]]
