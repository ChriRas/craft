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
#                  (The backwards edge /craft:review → implementing — the review loop-back,
#                  slice-034 — is bound this way like any other row.)
#   DELEGATION   — a Subagent-Mode section that hands a rule to its interactive twin
#                  (refactor.md → the Phase-7 gate, review.md → the Step-8 loop-back) must
#                  carry the craft:delegates token and no status write of its own, and the
#                  token's target heading must carry the rule's write marker. The delegation
#                  table itself is bound to the tokens in commands/ in both directions.
#   DETECTION    — the Phase-7-dropped rule is itself prose ("a ## Workflow Rules bullet
#                  declares Phase 7 dropped or skipped"). Assert this project's rules.md
#                  actually satisfies the canonical form, so the rule that gates the
#                  whole routing change is a checked contract, not an LLM judgment.
#   SECTIONS     — /craft:plan's P2 must derive its required sections from the slice-plan
#                  template (every `## ` header), or — if it lists them — each listed one must
#                  exist there. (P2 spent its life requiring `## Observable Effect`, which the
#                  template never emitted; a list also fell behind the template's later sections.)
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
#     Since slice-034 the token's TARGET is resolved (the named heading must carry the rule's
#     write marker), so a renamed or emptied target goes red — but that binds the marker's
#     *location*, not that the section's prose still implements the rule.
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

# This harness needs a current bash — under macOS's /bin/bash 3.2 its heredocs inside $( … )
# do not even parse. Bash reads a script command by command, so this guard runs before the
# first such construct and turns the parse error into an install hint. The minimum itself is
# defined once, in check-toolchain.sh, which runs here with the very bash executing this file.
if ! toolchain="$("$BASH" "$SCRIPT_DIR/check-toolchain.sh" 2>&1)"; then
  case "$toolchain" in
    *STATUS=missing-tools*)
      printf 'FATAL: %s needs a newer toolchain than this shell provides:\n%s\n' \
        "${BASH_SOURCE[0]##*/}" "$toolchain" >&2
      exit 2 ;;
  esac
fi

ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

SKILL="$ROOT/skills/workflow/SKILL.md"
COMMANDS="$ROOT/commands"
TEMPLATE="$ROOT/templates/slice-plan.md.template"
PLAN_CMD="$COMMANDS/plan.md"
RULES="$ROOT/.claude/project/rules.md"

# What counts as an EXAMPLE is decided once, in example-regions.sh (slice-047). This file used to
# carry THREE independent copies of the same naive parity toggle — in the marker scan, in
# unfence(), and in the delegation-coverage scan — each of which a nested or unclosed fence could
# fool. The python blocks below read blanked copies instead and no longer decide it at all.
# Invoked with "${BASH:-bash}", the interpreter running this script, never PATH's `bash`.
EXAMPLE_REGIONS="$SCRIPT_DIR/example-regions.sh"
[ -f "$EXAMPLE_REGIONS" ] || { echo "ERROR: example-regions.sh missing at $EXAMPLE_REGIONS" >&2; exit 4; }
BLANKED_COMMANDS="$(mktemp -d)"
trap 'rm -rf "$BLANKED_COMMANDS"' EXIT
UNCLOSED_IN=""
for _f in "$COMMANDS"/*.md; do
  [ -f "$_f" ] || continue
  "${BASH:-bash}" "$EXAMPLE_REGIONS" blank markdown "$_f" > "$BLANKED_COMMANDS/$(basename "$_f")" \
    || { echo "ERROR: example-regions.sh failed on $_f" >&2; exit 4; }
  # An unclosed fence hides every line after it, markers included, and a harness that only
  # BLANKS would go quietly green with fewer things to check. The old parity toggle had the same
  # hole and no way to know; the helper does, so ask it (slice-047).
  _rep="$("${BASH:-bash}" "$EXAMPLE_REGIONS" report markdown "$_f" 2>/dev/null)"
  [ -n "$_rep" ] && UNCLOSED_IN="$UNCLOSED_IN $(basename "$_f"):${_rep#UNCLOSED=}"
done

for f in "$SKILL" "$TEMPLATE" "$PLAN_CMD"; do
  [[ -f "$f" ]] || { echo "FATAL: expected file not found: $f" >&2; exit 2; }
done

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

# Collected while the blanked copies were built, above. An unclosed fence in a command file
# hides every marker after it, so this harness would check fewer things and say nothing —
# exactly the silent green it exists to prevent (slice-047).
if [[ -n "${UNCLOSED_IN// }" ]]; then
  bad "command file(s) with an unclosed fence — every marker after it is hidden from this run:${UNCLOSED_IN}"
else
  ok "no command file leaves a fence open (an unclosed one would hide markers from every check below)"
fi

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
markers="$(python3 - "$BLANKED_COMMANDS" <<'PY'
import os, re, sys
d = sys.argv[1]
pat = re.compile(r"<!--\s*craft:(writes|reads)\s+status=([a-z-]+)(?:\s+when=([a-z0-9-]+))?\s*-->")
ADJACENCY = 6   # lines after the marker within which the prescribed write must appear

for name in sorted(os.listdir(d)):
    if not name.endswith(".md"):
        continue
    cmd = "/craft:" + name[:-3]
    # Already blanked by example-regions.sh — a marker parked in an example is not an
    # instruction, and this block no longer decides what an example is. Line numbers survive
    # blanking, so the positions reported below are still the real ones.
    lines = open(os.path.join(d, name), encoding="utf-8").read().splitlines()

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
router_out="$(python3 - "$BLANKED_COMMANDS/continue.md" <<'PY'
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
# The same shape now binds /craft:review (slice-034, roadmap B3): its Subagent Mode must not
# restate the review loop-back — the one Step-8 definition writes `implementing` — and must
# point at it with a token. So is /craft:plan's (slice-054): the autopilot's slice-planner writes
# the plan file step 7 defines — status included — and its section only lists what differs.
# The token's TARGET is resolved too: a token pointing at a heading that no longer carries the
# rule's write marker is a pointer into nothing (a reviewer renamed Step 8, and separately moved
# its marker into Step 5 — both stayed green before this check). Each entry:
#   file | token rule | token target | target heading | marker attrs the target must carry |
#   what the token hands to | what is lost if the token goes
DELEGATIONS='refactor.md|phase7-dropped|preflight|Pre-flight|status=reviewing when=phase7-dropped|the Pre-flight Phase-7 gate|strips the Phase-7 drop from /craft:execute'"'"'s chain
review.md|loop-back|step-8|Step 8|status=implementing|the Step-8 review loop-back|leaves the autonomous handoff with no pointer to the one loop-back definition — behavior is unchanged, but nothing stops the next edit from restating Step 8 there
plan.md|plan-file|step-7|7. Generate the plan file|status=planning|step 7'"'"'s plan-file definition|leaves the autopilot'"'"'s slice-planner with no pointer to the one plan-file definition — nothing stops the next edit from restating the template substitution (and its Status) there
refactor.md|phase7-end|step-5|5. Advance to Phase 8|status=reviewing when=phase7-kept|Step 5'"'"'s Phase-7 end|leaves the autopilot'"'"'s Phase 7 (slice-056, B21) with no pointer to the one Phase-7 end — the slice-builder would pause at awaiting-refactor-decision again, or write reviewing itself'
echo "DELEGATION:"
while IFS='|' read -r dfile drule dto dhead dattrs dgate dloss; do
[[ -n "$dfile" ]] || continue
verdict="$(python3 - "$BLANKED_COMMANDS/$dfile" "$drule" "$dto" "$dhead" "$dattrs" <<'PY' 2>&1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
rule, target, heading, attrs = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

# No unfence() here any more: the file this reads has already been blanked by
# example-regions.sh, so every section taken out of it is example-free.

m = re.search(r"^##\s+Subagent Mode\b.*?$(.*?)(?=^##\s|\Z)", text, re.S | re.M)
if not m:
    print("NOSECTION"); sys.exit()
body = m.group(1)

token = re.search(r"<!--\s*craft:delegates\s+rule=" + re.escape(rule)
                  + r"\s+to=" + re.escape(target) + r"\s*-->", body)

# Resolve the target: the heading must exist, and its section (up to the next heading of the
# same or a higher level) must carry the rule's craft:writes marker.
h = re.search(r"^(#{2,4})\s+" + re.escape(heading) + r"\b.*$", text, re.M)
target_ok = False
if h:
    rest = text[h.end():]
    nxt = re.search(r"^#{1," + str(len(h.group(1))) + r"}\s", rest, re.M)
    section = rest[:nxt.start()] if nxt else rest
    want = r"<!--\s*craft:writes\s+" + r"\s+".join(map(re.escape, attrs.split())) + r"\s*-->"
    target_ok = re.search(want, section) is not None

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

print("NOTOKEN" if not token else
      "RESTATES" if marker_write or prose_write else
      "NOTARGET" if not target_ok else
      "OK")
PY
)"
case "$verdict" in
  OK)        ok "$dfile's Subagent Mode carries the craft:delegates token ($drule → $dto), declares no status write of its own, and its target '$dhead' carries the $dattrs write marker" ;;
  NOSECTION) bad "$dfile has no '## Subagent Mode' section — the autonomous path is undefined" ;;
  RESTATES)  bad "$dfile's Subagent Mode carries the craft:delegates token but ALSO declares a status write of its own (a craft:writes marker, or a 'Status: <x>' literal in its prose) — a restated rule. Two descriptions of one contract is how B1 survived; the subagent section must delegate to $dgate, not re-declare it" ;;
  NOTOKEN)   bad "$dfile's Subagent Mode carries no <!-- craft:delegates rule=$drule to=$dto --> token — the delegation was removed, relocated, or the section renamed, which $dloss (and no status-write check can see that, because a delegation writes nothing)" ;;
  NOTARGET)  bad "$dfile's craft:delegates token points at '$dhead', but no such heading carries the <!-- craft:writes $dattrs --> marker — the target was renamed, deleted, or the rule moved elsewhere; the token now points into nothing" ;;
  *)         last="${verdict##*$'\n'}"
             bad "DELEGATION could not check $dfile — unexpected verdict: ${last:-<empty>}" ;;
esac
done <<< "$DELEGATIONS"

# The table above is maintained by hand, so it can silently lose an entry — an emptied table once
# stayed 84/0 green, and a new craft:delegates token anywhere in commands/ would go unchecked. Bind
# the table to the tokens actually present, in both directions (fenced examples ignored).
coverage="$(DELEGATION_TABLE="$DELEGATIONS" python3 - "$BLANKED_COMMANDS" <<'PY' 2>&1
import os, re, sys, pathlib
table = set()
for line in os.environ.get("DELEGATION_TABLE", "").splitlines():
    cells = line.split("|")
    if len(cells) >= 3 and cells[0].strip():
        table.add((cells[0], cells[1], cells[2]))
found = set()
for f in sorted(pathlib.Path(sys.argv[1]).glob("*.md")):
    # already blanked by example-regions.sh
    for ln in f.read_text(encoding="utf-8").splitlines():
        for m in re.finditer(r"<!--\s*craft:delegates\s+rule=(\S+)\s+to=(\S+)\s*-->", ln):
            found.add((f.name, m.group(1), m.group(2)))
if not table:
    print("EMPTY\t-")
for e in sorted(found - table):
    print("UNLISTED\t" + "|".join(e))
for e in sorted(table - found):
    print("NOTOKEN\t" + "|".join(e))
PY
)"
if [[ -z "$coverage" ]]; then
  ok "every craft:delegates token in commands/ has a delegation-table entry, and every entry a token"
else
  while IFS=$'\t' read -r kind ref; do
    case "$kind" in
      EMPTY)    bad "the delegation table is empty — the DELEGATION checks above checked nothing" ;;
      UNLISTED) bad "craft:delegates token '$ref' has no delegation-table entry — its target, restatement and loss checks never run" ;;
      NOTOKEN)  bad "delegation-table entry '$ref' matches no craft:delegates token in commands/" ;;
      *)        bad "delegation coverage check failed: $kind $ref" ;;
    esac
  done <<< "$coverage"
fi

# --- AUTOPILOT PHASE 7: candidates, never a stop (slice-056, B21) -------------
# In an autopilot run a Phase-7-keeping project used to stop at awaiting-refactor-decision: the
# slice-builder had only the drop and the pause. The autopilot path surveys, applies nothing, writes
# each candidate as a decision line with ONE prefix, and ends Phase 7 through Step 5 (the token above).
# The a5 digest finds the candidates by that prefix — so writer and reader must name the same one.
echo "AUTOPILOT PHASE 7:"
CAND_PREFIX='Refactor candidate (autopilot, not applied):'
autopilot_p7="$(python3 - "$BLANKED_COMMANDS/refactor.md" "$BLANKED_COMMANDS/execute.md" "$ROOT/agents/slice-builder.md" "$CAND_PREFIX" <<'PY' 2>&1
import re, sys
refactor, execute, builder, prefix = (open(sys.argv[1], encoding="utf-8").read(),
    open(sys.argv[2], encoding="utf-8").read(), open(sys.argv[3], encoding="utf-8").read(), sys.argv[4])
def section(text, head_re):
    m = re.search(head_re + r".*?$(.*?)(?=^#{1,3}\s|\Z)", text, re.S | re.M)
    return m.group(1) if m else None
sub = section(refactor, r"^##\s+Subagent Mode\b")
# the bullet carrying the phase7-end token: from its "- " start to the next bullet or blank line
bullet = None
if sub:
    for b in re.split(r"\n(?=- )|\n\s*\n", sub):
        if re.search(r"craft:delegates\s+rule=phase7-end\b", b):
            bullet = b
print("BULLET " + ("missing" if bullet is None else "ok"))
if bullet is not None:
    # the gate itself, not the word: the prefix and the no-candidate line both contain "autopilot" (R1-2)
    print("AUTOPILOT " + ("ok" if re.match(r"-\s+\*\*In an autopilot run\*\*", bullet.lstrip()) else "missing"))
    # a later pass (review loop-back, re-run) replaces the earlier lines instead of adding to them (R1-5)
    print("REPLACES " + ("ok" if re.search(r"\*\*replaces\*\*\s+the\s+lines\s+an\s+earlier\s+pass\s+wrote", bullet) else "missing"))
    print("HANDOFF " + ("present" if "craft:handoff" in bullet else "none"))
    print("PREFIX_W " + ("ok" if prefix in bullet else "missing"))
a5 = section(execute, r"^###\s+a5\b")
print("PREFIX_R " + ("ok" if a5 and prefix in a5 else "missing"))
# probe 3: the digest paraphrased the candidates from context — a5 reads them by command
# anchored at the line start: an archive that merely mentions the prefix must list nothing (R1-1)
print("DIGEST_CMD " + ("ok" if a5 and ("grep -h '^- \\*\\*" + prefix + "\\*\\*'") in a5 else "missing"))
commit = open(sys.argv[1].replace("refactor.md", "commit.md"), encoding="utf-8").read()
cap = section(commit, r"^##\s+Autopilot Mode\b")
print("VERBATIM " + ("ok" if cap and re.search(r"carries each decision line into the archive's `## Decisions` as\s+written", cap) else "missing"))
# prose alone did not bind the commit master (probe run 1 rewrote the decisions from memory) — the carry is checked by command
# anchored, both forms (R1-1, R1-6), and the repair inserts only what the archive lacks (R1-4)
carry_re = "grep -cE '^- \\*\\*(Refactor candidate \\(autopilot, not applied\\):|Phase 7 \\(autopilot\\): no refactor candidate)\\*\\*'"
print("CARRY_CHECK " + ("ok" if cap and carry_re in cap and "grep -Fxv -f <archive>" in cap else "missing"))
if bullet is not None:
    print("PREFLIGHT " + ("ok" if re.search(r"run the \*\*Pre-flight above\*\* first", bullet) else "missing"))
step4 = section(builder, r"^###\s+4\.\s+Phase 7\b")
print("B_STEP4 " + ("missing" if step4 is None else "ok"))
if step4 is not None:
    print("B_AUTOPILOT " + ("ok" if re.search(r"autopilot", step4, re.I) else "missing"))
    print("B_RESTATES " + ("yes" if "awaiting-refactor-decision" in step4 else "no"))
PY
)"
ap7() { printf '%s\n' "$autopilot_p7" | awk -v k="$1" '$1 == k { print $2 }'; }
[[ "$(ap7 BULLET)" == ok ]] && ok "refactor.md's Subagent Mode has a bullet carrying the phase7-end delegation" \
  || bad "refactor.md's Subagent Mode has no bullet carrying <!-- craft:delegates rule=phase7-end to=step-5 --> — an autopilot slice-builder has no path past Phase 7 but the pause (B21)"
[[ "$(ap7 AUTOPILOT)" == ok ]] && ok "that bullet opens with the autopilot gate (**In an autopilot run**)" \
  || bad "the phase7-end bullet does not open with **In an autopilot run** — ungated, it would override the pause outside autopilot"
[[ "$(ap7 REPLACES)" == ok ]] && ok "a later Phase-7 pass replaces the earlier candidate lines instead of adding to them" \
  || bad "the autopilot bullet does not say a later pass replaces the earlier lines — a loop-back or re-run would duplicate candidates"
[[ "$(ap7 HANDOFF)" == none ]] && ok "the autopilot bullet writes no handoff marker (no stop)" \
  || bad "the autopilot bullet carries a craft:handoff marker — the autopilot run would stop at Phase 7 again (B21)"
[[ "$(ap7 PREFIX_W)" == ok ]] && ok "the autopilot bullet writes candidates with the prefix '$CAND_PREFIX'" \
  || bad "the autopilot bullet does not name the candidate prefix '$CAND_PREFIX' — the a5 digest could not find the candidates"
[[ "$(ap7 PREFIX_R)" == ok ]] && ok "execute.md's a5 digest reads the candidate prefix" \
  || bad "execute.md's a5 does not read '$CAND_PREFIX' — the candidates never reach the human (design record §3)"
[[ "$(ap7 DIGEST_CMD)" == ok ]] && ok "execute.md's a5 reads the candidate lines by command (grep -h, anchored at the line start)" \
  || bad "execute.md's a5 does not read the candidates by command — probe 3's digest paraphrased them from context"
[[ "$(ap7 VERBATIM)" == ok ]] && ok "commit.md's Autopilot Mode carries decision lines into the archive as written (the prefix survives)" \
  || bad "commit.md's Autopilot Mode does not keep decision lines as written — Step 5 may reword a refactor candidate and a5 would miss it"
[[ "$(ap7 CARRY_CHECK)" == ok ]] && ok "commit.md's Autopilot Mode checks the carried Phase-7 lines by command (grep -cE anchored, both forms, plan = archive; repair inserts only missing lines)" \
  || bad "commit.md's Autopilot Mode does not check the candidate lines by command — probe run 1 showed the archive rewritten from memory"
[[ "$(ap7 PREFLIGHT)" == ok ]] && ok "the autopilot bullet runs refactor.md's Pre-flight first (its refactoring status included)" \
  || bad "the autopilot bullet does not send the builder through Pre-flight — probe run 1 skipped the refactoring status"
[[ "$(ap7 B_STEP4)" == ok && "$(ap7 B_AUTOPILOT)" == ok ]] && ok "slice-builder step 4 names the autopilot path" \
  || bad "slice-builder step 4 does not name the autopilot path — the builder would follow the pause"
[[ "$(ap7 B_RESTATES)" == no ]] && ok "slice-builder step 4 does not restate the refactor pause — refactor.md's Subagent Mode defines it" \
  || bad "slice-builder step 4 restates the awaiting-refactor-decision pause — a second description beside refactor.md's Subagent Mode"

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
# $RULES and $TEMPLATE are read RAW, unlike every commands/*.md above. Disclosed, not
# overlooked (slice-047, R1-5): neither carries a marker region, so there is no bounded
# declaration a blanked copy would protect -- blanking them would only move the question of
# which region counts, not answer it. A fenced example in either file can therefore still
# reach these two checks. Related work: the raw $SKILL read ABOVE (the transition-table
# parse) -- but that one IS bounded by the craft:transitions markers, while these two have
# no marker boundary at all, so they are a different and wider question, not the same one.
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
missing="$(python3 - "$BLANKED_COMMANDS/plan.md" "$TEMPLATE" <<'PY'
import re, sys
plan = open(sys.argv[1], encoding="utf-8").read()
tpl  = open(sys.argv[2], encoding="utf-8").read()
heads = {re.sub(r"\s*\(optional\)\s*$", "", h).strip()
         for h in re.findall(r"^##\s+(.+?)\s*$", tpl, re.M)}
m = re.search(r"^###\s+P2\b.*?$(.*?)(?=^###\s|\Z)", plan, re.S | re.M)
asserted = re.findall(r"^-\s+`##\s+(.+?)`\s*$", m.group(1) if m else "", re.M)
derives = bool(m) and "templates/slice-plan.md.template" in m.group(1) and "every `## ` section header" in m.group(1)
if derives and not asserted:
    print("!DERIVED")
elif not asserted:
    print("!NONE")
for name in asserted:
    if name.strip() not in heads:
        print(name.strip())
PY
)"

if [[ "$missing" == "!DERIVED" ]]; then
  ok "/craft:plan P2 derives its required sections from slice-plan.md.template (every ## header)"
elif [[ "$missing" == "!NONE" ]]; then
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
