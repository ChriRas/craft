#!/usr/bin/env bash
# test-model-enum.sh — the model enum is declared once, and every copy agrees with it.
#
# CRAFT names its allowed model values in several files: the normative document, the profile
# templates a project starts from, and the published docs page. They cannot be collapsed into
# one — a template exists precisely so a human reads the values where they are. So the values are
# DECLARED once and every other site is BOUND to that declaration by a marker.
#
# commands/prime.md is listed with an expected count of ZERO. That zero asserts exactly one thing:
# prime carries no binding MARKER. It does not assert that prime names no values — the count counts
# markers, so an unmarked value list re-grown in that file leaves this check, and every other
# harness, green (review round 7, R7-17, reproduced). That prime reads the declaration at run time
# and validates agent NAMES only is a review obligation, not a check; it is the unmarked-copy
# residual described in model-defaults.md -> Known limits of the binding mechanism. What the zero
# does catch is a marker APPEARING here, which would mean prime had started declaring values.
#
# The contract (defined in model-defaults.md -> Allowed Model Values):
#
#   * A binding site carries  <!-- craft:model-enum -->  alone on the line directly
#     above the values; leading whitespace and blockquote '>' markers do not count as
#     company. The canonical declaration adds the word 'canonical'.
#   * A marker sharing its line with other text is prose ABOUT the mechanism and is not
#     a binding site — that is what stops the documentation of this contract from being
#     counted as a copy of it.
#   * On a marked line, everything after the LAST ':' is the value list, separated by
#     ',', '|' or '·'. Values may be backticked, <code>-wrapped or HTML-escaped, and
#     nothing but values may follow that colon.
#
# This harness carries no copy of the value LIST — not in its checks and not in its self-test
# fixtures, which are built from the canonical line at run time. That is the whole point: a
# hardcoded list here would be one more copy to drift, and for two rounds it was exactly that.
# Adding a value is an edit to the marked lines a human reads, and nothing else; the run picks it
# up. Two fixtures do still name a single agent MODEL (`model: opus`, `model: haiku`); those fail
# loudly through subst's exit 3 if they go stale, but the claim above is about the list.
#
# It also holds the two rules that keep 'fable' human-chosen (no agents/*.md selects it)
# and the agent frontmatter honest against model-defaults.md -> Cache TTL.
#
# Exit 0 = green. Any drift = non-zero, naming the file and line.

set -uo pipefail

# CRAFT_ENUM_ROOT is a test-only override: the self-test at the bottom re-invokes this
# script against a mutated copy of the tree to prove the checks actually bite. Nothing
# else sets it.
if [ -n "${CRAFT_ENUM_ROOT:-}" ]; then
  cd "$CRAFT_ENUM_ROOT" || exit 2
else
  cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
fi
ROOT="$PWD"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAILED=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); printf '  ok    %s\n' "$1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILED=$((FAILED + 1)); printf '  FAIL  %s\n' "$1"; }

# --- the contract, in one place -------------------------------------------------------

MARKER_RE='^[[:space:]>]*<!--[[:space:]]*craft:model-enum([[:space:]]+canonical)?[[:space:]]*-->[[:space:]]*$'

# The second declaration's marker. Declared HERE, beside the first, because the near-miss scan
# (2c) runs before the spawn checks (2d) and has to know both tokens — round 8 reproduced
# `<!-- craft:spawn-enum2 -->` above a value list being compared by nothing and flagged by
# nothing, which is R3-4 verbatim, one declaration out (R8-4).
SPAWN_MARKER_RE='^[[:space:]>]*<!--[[:space:]]*craft:spawn-enum([[:space:]]+canonical)?[[:space:]]*-->[[:space:]]*$'
SPAWN_HEADING='## Spawn-Reachable Values'

# A marker inside a fenced code block is an EXAMPLE, not a binding site — the same rule the
# status-graph harness has carried since slice-031, where a marker parked in an example kept a
# deleted gate green. Without it a fenced example can stand in for a deleted real marker and
# satisfy the per-file count while the list a human reads has drifted (review round 3, R3-1).
#
# defenced <file> prints the path of a copy with every fenced line blanked, line numbering
# intact, so every check below can keep addressing lines by number.
# The one definition of "this line is an example, not content", shared with
# epic-entry-link.sh, review-findings-state.sh and test-workflow-status-graph.sh (slice-047).
EXAMPLE_REGIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/example-regions.sh"
[ -f "$EXAMPLE_REGIONS" ] || { printf 'ERROR: example-regions.sh missing at %s\n' "$EXAMPLE_REGIONS" >&2; exit 4; }

# R4-3 (slice-047): the checks that read THIS file's tables and rules — tier definitions, the
# Role → tier rows, the Default Mapping rows, the fable rule — all read it raw, so a row or a rule
# parked in a fenced example was read as content. They read the defenced copy now, like every
# marker-level check. That entry of the known-limits block is closed.
#
# section_bounds <file> <heading-line-regex> <terminator-regex> -> "<start>,<end>", blank when
# the heading is absent. A heading check binds a NAME and nothing else; this is what lets a check
# also assert that the section the name opens still carries what readers are sent there for.
section_bounds() {
  awk -v h="$2" -v t="$3" '
    !start && $0 ~ h { start = NR; next }
    start && $0 ~ t  { print start "," NR - 1; found = 1; exit }
    END { if (start && !found) print start "," NR }
  ' "$1"
}

# mode_for <file> -> the example-regions.sh mode for it. The helper does NOT infer this: it
# takes the mode as an argument and exits 2 without one, so the decision is the caller's.
# Declared once here because this file asks for a mode twice -- blank() below and the report
# gate -- and two independent copies of the rule can diverge silently, which is exactly what
# this harness exists to prevent (slice-047, N2 round 2).
mode_for() {
  case "$1" in *.html|*.htm) printf html ;; *) printf markdown ;; esac
}

defenced() {
  local f="$1" out mode
  out="$WORK_DIR/defenced/$(printf '%s' "$f" | tr '/' '_')"
  if [ ! -f "$out" ]; then
    mkdir -p "$WORK_DIR/defenced"
    # What counts as an EXAMPLE is decided once, in example-regions.sh (slice-047). This used to
    # be a naive parity toggle here: it flipped on any line starting with ``` or ~~~, so a nested
    # fence toggled twice and a decoy inside it read as content (R4-1), and it ran the MARKDOWN
    # rules over docs/index.html, which is not Markdown at all and hides its examples in <pre>
    # (R7-3b). The CALLER picks the mode -- the helper takes it as an argument and exits 2
    # without one -- so mode_for() above is the single place this file decides it;
    # "${BASH:-bash}" is the interpreter already running this script, never PATH's.
    "${BASH:-bash}" "$EXAMPLE_REGIONS" blank "$(mode_for "$f")" "$f" > "$out" \
      || { printf 'ERROR: example-regions.sh failed on %s\n' "$f" >&2; exit 4; }
  fi
  printf '%s\n' "$out"
}

# Files that carry a binding site, each with the number of sites it must have — the
# canonical declaration counts as one of model-defaults.md's.
#
# The count is not bookkeeping. Without it, deleting a marker line silently UNBINDS that
# copy: the file stops being compared and nothing says so, which is exactly the drift this
# harness exists to catch. It was found that way in review round 1 — a template lost its
# marker and its values and the run stayed green. A file whose count changes is a decision;
# a file missing from this list is invisible, so a new one is added here in the same commit.
BOUND_FILES=(
  "model-defaults.md:2"
  "commands/prime.md:0"
  "templates/craft-profile.md.template:1"
  "templates/profiles/balanced.md:1"
  "templates/profiles/careful.md:1"
  "templates/profiles/autonomous.md:1"
  "docs/index.html:1"
)

# Split once, so the rest of the harness can address paths and counts separately.
BOUND_PATHS=()
BOUND_COUNTS=()
for entry in "${BOUND_FILES[@]}"; do
  BOUND_PATHS+=("${entry%:*}")
  BOUND_COUNTS+=("${entry##*:}")
done

# Extract the value set from a marked line: everything after the last ':', split on
# ',' '|' '·'. Strips HTML tags BEFORE decoding entities, so an escaped placeholder
# such as &lt;model-id&gt; survives tag-stripping and still arrives as <model-id>.
# Prints one normalized value per line.
# parse_marked_line <line> values   -> one normalized value per line
# parse_marked_line <line> rawcount -> how many separator-delimited pieces the raw tail had
#
# The rawcount mode exists to close a failure CLASS, not one bug. Normalization once ate the
# `<model-id>` placeholder, so the canonical line yielded five values instead of six — and
# every Markdown copy lost the same one, so set comparison found them in perfect agreement
# and stayed green. Comparing the raw piece count against the extracted count sees what set
# comparison structurally cannot: that parsing itself dropped something.
parse_marked_line() {
  printf '%s\n' "$1" | MODE="$2" python3 -c '
import html, os, re, sys

mode = os.environ["MODE"]
line = sys.stdin.read().rstrip("\n")
if ":" not in line:
    sys.exit(0)
tail = line.rsplit(":", 1)[1]

if mode == "rawcount":
    # Count before any normalization: a piece is anything between separators that carries
    # at least one alphanumeric character. Trailing markup like "</code></td>" attaches to
    # the last piece rather than forming its own, so this counts VALUES as written.
    pieces = [p for p in re.split(r"[,|·]", tail) if re.search(r"[A-Za-z0-9]", p)]
    print(len(pieces))
    sys.exit(0)

# Only KNOWN html tags — not any <word>, or the placeholder <model-id> would be
# stripped as if it were markup. That bug made the canonical line silently one value
# short while every Markdown copy lost the same value, so they agreed with each other
# and only the HTML-escaped copy stood out as "drift".
tail = re.sub(r"</?(?:code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>", "", tail)
tail = html.unescape(tail)                       # now &lt;model-id&gt; -> <model-id>
for piece in re.split(r"[,|·]", tail):
    v = piece.strip().strip("`").strip()
    v = v.rstrip(".").rstrip(")").strip()
    v = v.strip("`").strip()
    if v:
        print(v)
'
}

# --- 1. find the canonical declaration ------------------------------------------------

CANON_FILE=""
CANON_LINE=""
CANON_VALUES=""

while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  if [ -n "$CANON_FILE" ]; then
    fail "more than one canonical declaration (also $f:$n) — there must be exactly one"
    break
  fi
  CANON_FILE="$f"
  CANON_LINE="$n"
done < <(for bp in "${BOUND_PATHS[@]}"; do
  [ -f "$bp" ] || continue
  grep -nE '^[[:space:]>]*<!--[[:space:]]*craft:model-enum[[:space:]]+canonical[[:space:]]*-->[[:space:]]*$' "$(defenced "$bp")" \
    | while IFS=: read -r ln _; do printf '%s:%s:\n' "$bp" "$ln"; done
done)

if [ -z "$CANON_FILE" ]; then
  fail "no canonical declaration found — expected '<!-- craft:model-enum canonical -->' in model-defaults.md"
  printf '\nRESULT: RED (%d/%d checks failed)\n' "$FAILED" "$CHECKS"
  exit 1
fi

CANON_VALUE_LINE="$(sed -n "$((CANON_LINE + 1))p" "$(defenced "$CANON_FILE")")"
CANON_VALUES="$(parse_marked_line "$CANON_VALUE_LINE" values | sort -u)"

if [ -z "$CANON_VALUES" ]; then
  fail "$CANON_FILE:$((CANON_LINE + 1)) — canonical marker is not followed by a value list"
  printf '\nRESULT: RED (%d/%d checks failed)\n' "$FAILED" "$CHECKS"
  exit 1
fi

# Document order, not the sorted set — the self-test fixtures below are built from this, so
# that changing the enum stays the one-file edit this mechanism advertises. Hardcoding the
# values in the fixtures would make the harness one more copy of them (review round 3, R3-2).
CANON_ORDERED="$(parse_marked_line "$CANON_VALUE_LINE" values)"

# vlist <n> -> the first n canonical values, backticked and comma-joined as the copies write them
vlist() {
  printf '%s\n' "$CANON_ORDERED" | head -"$1" | sed 's/^/`/; s/$/`/' | paste -sd, - | sed 's/,/, /g'
}

CANON_COUNT="$(printf '%s\n' "$CANON_VALUES" | wc -l | tr -d ' ')"

# R4-6 (slice-047): the exactly-one-colon rule ran on copies only. With copies present that felt
# safe, but only the text after the LAST colon is compared, so a second colon on the CANONICAL
# line hides whatever precedes it from every comparison — and the declaration is the one line no
# copy can catch drifting, because every copy is compared against it.
canon_colons="$(printf '%s' "$CANON_VALUE_LINE" | sed -E 's:</?(code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>::g' | tr -cd ':' | wc -c | tr -d ' ')"
if [ "$canon_colons" -ne 1 ]; then
  fail "$CANON_FILE:$((CANON_LINE + 1)) — a marked value line must contain exactly one ':' (found $canon_colons); only the text after it is checked, so a second colon hides whatever precedes it from every comparison."
else
  pass "$CANON_FILE:$((CANON_LINE + 1)) — exactly one ':' on the canonical value line"
fi

# A stray word between the colon and the first value IS caught today — every copy reports drift
# against the declaration — but the message names the COPIES, sending the maintainer to seven
# files that are all fine. Asserting it here names the one line that is wrong (slice-047).
canon_tail="${CANON_VALUE_LINE#*:}"
canon_tail="${canon_tail#"${canon_tail%%[![:space:]]*}"}"
case "$canon_tail" in
  '`'*) pass "$CANON_FILE:$((CANON_LINE + 1)) — the canonical value list starts at the first value, no stray tail" ;;
  *)    fail "$CANON_FILE:$((CANON_LINE + 1)) — a stray word sits between the ':' and the first value ('$(printf '%s' "$canon_tail" | cut -c1-24)…'); every copy will report drift against this line, which sends the reader to the copies instead of here." ;;
esac

# R4-10 (slice-047): the tier set was typed out three times inside this file — a second,
# unbound copy of a set, in the harness of a slice whose thesis is "declared once". It is read
# from the Capability Tiers table now. Why that change has no fixture, and why derived and
# hardcoded are observationally identical while there are exactly two tiers: see the R4-10
# comment at the self-test cases below, and model-defaults.md -> Known limits. Not restated
# here -- an earlier version of this comment claimed a behavioural difference that does not
# exist, which is the defect class B1/B2 were opened for (slice-047, R1-3).
TIER_SET="$(grep -oE '^\|[[:space:]]*\*\*`?[a-z][a-z-]*`?\*\*[[:space:]]*\|' "$(defenced "$CANON_FILE")" \
  | sed -E 's/^\|[[:space:]]*\*\*`?//; s/`?\*\*[[:space:]]*\|$//' | sort -u | paste -sd'|' -)"
if [ -z "$TIER_SET" ]; then
  fail "$CANON_FILE — no capability tier definition rows found; the tier set cannot be read"
  # Degraded mode on an ALREADY-RED run: the fail() above has fired, so this run reports a
  # failure whatever follows. The value only keeps the checks below from producing noise on
  # top of the real message. It is deliberately NOT a maintained copy of the tier set --
  # grow the table and this line does not need to follow (slice-047, R1-10).
  TIER_SET='deep-reason|execute'
else
  pass "capability tier set read from the table, not hardcoded ($TIER_SET)"
fi

# An unclosed fence hides every line after it, so a bound file with one goes quiet from that point
# and every check below simply has less to look at — the harness gets greener, not louder. `blank`
# cannot tell; `report` can, so ask it. The same gap was closed in test-workflow-status-graph.sh in
# sub-task 6 and not carried here, and it cost a whole debug round: a self-test case of this file's
# own left a fence open, half of model-defaults.md went dark, and the run failed with a pile of
# unrelated messages instead of naming the fence (B1, slice-047).
UNCLOSED_BOUND=""
for entry in "${BOUND_FILES[@]}" "${SPAWN_BOUND_FILES[@]}"; do
  bf="${entry%:*}"
  [ -f "$bf" ] || continue
  brep="$("${BASH:-bash}" "$EXAMPLE_REGIONS" report "$(mode_for "$bf")" "$bf" 2>/dev/null)"
  [ -n "$brep" ] && UNCLOSED_BOUND="$UNCLOSED_BOUND $bf:${brep#UNCLOSED=}"
done
if [ -n "${UNCLOSED_BOUND// }" ]; then
  fail "bound file(s) with an unclosed fence — every check below reads a file that goes quiet from there:${UNCLOSED_BOUND}"
else
  pass "no bound file leaves a fence open (an unclosed one would hide the rest of it from every check below)"
fi

# R4-8 (slice-047): nothing checked that this file still has a section headed
# `## Allowed Model Values`. /craft:prime step 4b resolves the alias set BY THAT HEADING NAME, so
# renaming it breaks prime with every check green. Same shape as the spawn heading check below,
# and like it the heading must also still CONTAIN the declaration it opens.
ENUM_HEADING='## Allowed Model Values'
if ! grep -qE "^${ENUM_HEADING}[[:space:]]*$" "$(defenced "$CANON_FILE")"; then
  fail "$CANON_FILE — the '$ENUM_HEADING' heading is gone; /craft:prime step 4b resolves the alias set by that heading name."
else
  pass "$CANON_FILE still carries the '$ENUM_HEADING' heading (the name /craft:prime resolves by)"
  ENUM_SECT="$(section_bounds "$(defenced "$CANON_FILE")" "^${ENUM_HEADING}[[:space:]]*$" '^## ')"
  if [ -z "$ENUM_SECT" ]; then
    fail "$CANON_FILE — could not delimit the '$ENUM_HEADING' section"
  elif [ "$CANON_LINE" -lt "${ENUM_SECT%,*}" ] || [ "$CANON_LINE" -gt "${ENUM_SECT#*,}" ]; then
    fail "$CANON_FILE:$CANON_LINE — the canonical declaration sits OUTSIDE the '$ENUM_HEADING' section (lines $ENUM_SECT); prime would find a section that carries no set."
  else
    pass "$CANON_FILE: the canonical declaration sits inside the section its heading opens (lines $ENUM_SECT)"
  fi
fi
pass "canonical declaration: $CANON_FILE:$((CANON_LINE + 1)) — $CANON_COUNT values ($(printf '%s' "$CANON_VALUES" | tr '\n' ' '))"

# Parsing must not lose a value. Set comparison cannot see this: a normalization bug hits
# every site alike, so the copies still agree — with each other, about the wrong set.
assert_nothing_lost() {
  local where="$1" line="$2" raw got
  raw="$(parse_marked_line "$line" rawcount)"
  # Count BEFORE de-duplication. Comparing against the sorted-unique set made a repeated
  # value read as a normalizer bug ("7 written, 6 extracted"), pointing the next maintainer
  # at code that is fine — an invariant whose whole worth is naming a cause nobody else can
  # see must not misname it.
  got="$(parse_marked_line "$line" values | wc -l | tr -d ' ')"
  if [ -n "$raw" ] && [ "$raw" -ne "$got" ]; then
    fail "$where — $raw values written, $got extracted. Either the normalizer dropped one (a drift check cannot see that, because it hits every site equally) or the line repeats a value — read the line first."
    return 1
  fi
  return 0
}

assert_nothing_lost "$CANON_FILE:$((CANON_LINE + 1))" "$CANON_VALUE_LINE" \
  && pass "canonical line parses without loss ($CANON_COUNT written, $CANON_COUNT extracted)"

# --- 2. every bound copy agrees, in both directions -----------------------------------

COPIES=0
for i in "${!BOUND_PATHS[@]}"; do
  f="${BOUND_PATHS[$i]}"
  expected="${BOUND_COUNTS[$i]}"
  [ -f "$f" ] || { fail "$f — listed as a bound file but does not exist"; continue; }

  # The count check is what makes a DELETED marker loud. Without it the file simply stops
  # being compared, and the run stays green while the copy drifts (review round 1, R1-4).
  actual="$(grep -cE "$MARKER_RE" "$(defenced "$f")")"
  if [ "$actual" -ne "$expected" ]; then
    fail "$f — $actual binding site(s), expected $expected. A marker was added or removed; if that is intended, change this file's count in BOUND_FILES so the change is a decision, not a silent unbinding."
  else
    pass "$f — $expected binding site(s), as declared"
  fi

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    # the canonical line is the declaration, not a copy of it
    if [ "$f" = "$CANON_FILE" ] && [ "$n" = "$CANON_LINE" ]; then
      continue
    fi
    COPIES=$((COPIES + 1))
    vline="$(sed -n "$((n + 1))p" "$(defenced "$f")")"
    vals="$(parse_marked_line "$vline" values | sort -u)"

    if [ -z "$vals" ]; then
      fail "$f:$((n + 1)) — marked, but no value list after the last ':'"
      continue
    fi

    # "Everything after the LAST colon" lets a drifted, human-visible list hide behind a
    # later one: `Allowed values: <old four> — full list in model-defaults.md: <all six>`
    # passed while the list a reader sees was the old one (review round 2). One colon per
    # marked line keeps what is checked and what is read the same text.
    colons="$(printf '%s' "$vline" | sed -E 's:</?(code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>::g' | tr -cd ':' | wc -c | tr -d ' ')"
    if [ "$colons" -ne 1 ]; then
      fail "$f:$((n + 1)) — a marked value line must contain exactly one ':' (found $colons); only the text after it is checked, so a second colon hides whatever precedes it from the comparison."
      continue
    fi

    assert_nothing_lost "$f:$((n + 1))" "$vline" || continue

    missing="$(comm -23 <(printf '%s\n' "$CANON_VALUES") <(printf '%s\n' "$vals") | tr '\n' ' ')"
    extra="$(comm -13 <(printf '%s\n' "$CANON_VALUES") <(printf '%s\n' "$vals") | tr '\n' ' ')"
    missing="${missing% }"
    extra="${extra% }"

    if [ -n "$missing" ] || [ -n "$extra" ]; then
      detail=""
      [ -n "$missing" ] && detail="missing: $missing"
      [ -n "$extra" ] && detail="${detail:+$detail; }not in the declaration: $extra"
      fail "$f:$((n + 1)) — drifted from $CANON_FILE:$((CANON_LINE + 1)) ($detail)"
    else
      pass "$f:$((n + 1)) — agrees with the declaration"
    fi
  done < <(grep -nE "$MARKER_RE" "$(defenced "$f")" | cut -d: -f1)
done

if [ "$COPIES" -eq 0 ]; then
  fail "no bound copies found — the marker mechanism is not reaching any file"
else
  pass "$COPIES bound copies checked across ${#BOUND_PATHS[@]} files"
fi

# --- 2b. no marked file escapes the list ----------------------------------------------
# Everything above only ever looks at files BOUND_FILES already names, which makes the list
# itself an unbound declaration: add a marked file and forget the entry, or delete an entry,
# and the copy is invisible while the run stays green. Review round 2 reproduced both. This
# is the same failure as a deleted marker (R1-4), one level out — so the tree decides which
# files claim to be bound, and the list must account for every one of them.
#
# The harness is excluded unconditionally: its self-test fixtures contain marker text, and some
# of those strings DO sit alone on a line. The exclusion is the rule, not a convenience justified
# by current formatting — a fixture may be reformatted at any time.
UNLISTED=0
while IFS= read -r found; do
  found="${found#./}"
  [ -n "$found" ] || continue
  [ "$found" = "scripts/test-model-enum.sh" ] && continue
  listed=0
  for p in "${BOUND_PATHS[@]}"; do
    [ "$p" = "$found" ] && { listed=1; break; }
  done
  if [ "$listed" -eq 0 ]; then
    UNLISTED=$((UNLISTED + 1))
    fail "$found carries a binding marker but is not in BOUND_FILES — it looks bound and is not checked. Add it with its expected site count, or remove the marker."
  fi
done < <(
  # The raw grep is only a cheap candidate filter; each hit is confirmed against the file's
  # defenced copy, so a marker that exists only inside a fenced example is not reported —
  # otherwise the mechanism could not be documented anywhere in the tree with a code block.
  grep -rlE "$MARKER_RE" . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor 2>/dev/null | while IFS= read -r cand; do
    grep -qE "$MARKER_RE" "$(defenced "${cand#./}")" && printf '%s\n' "$cand"
  done
)

[ "$UNLISTED" -eq 0 ] && pass "every marked file in the tree is accounted for in BOUND_FILES"

# --- 2c. a near-miss marker is not a marker, and must not look like one ------------------
# `craft:Model-Enum` or `craft:model-enum2` above a value list is compared by nothing (the file
# is not listed) and flagged by nothing (it does not match MARKER_RE) — while a human reading it
# sees a marker and assumes the list is checked. The realistic trigger is not a typo but a future
# rename of the token: sites updated and sites missed would part company in silence.
#
# This is checkable without false positives because a near-miss is marker-SHAPED — inside an HTML
# comment, alone on its line — and a prose mention never is.
# R4-7 (slice-047): two spellings used to match neither this nor MARKER_RE and were therefore
# compared by nothing and reported by nothing — a separator variant (`craft:model_enum`) and a
# real marker followed by a second comment on the same line. `[-_]` catches the first; ending
# in `.*$` instead of `[^>]*-->[[:space:]]*$` catches the second. Still anchored to a line that
# STARTS with the comment, so a prose mention in backticks is untouched.
NEARMISS_RE='^[[:space:]>]*<!--[^>]*([Mm][Oo][Dd][Ee][Ll]|[Ss][Pp][Aa][Ww][Nn])[-_][Ee][Nn][Uu][Mm].*$'
NEARMISS=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; n="${rest%%:*}"
  f="${f#./}"
  [ "$f" = "scripts/test-model-enum.sh" ] && continue
  # a real marker is fine; only the near-misses remain
  line="$(sed -n "${n}p" "$(defenced "$f")")"
  [ -z "$line" ] && continue
  printf '%s\n' "$line" | grep -qE "$MARKER_RE" && continue
  printf '%s\n' "$line" | grep -qE "$SPAWN_MARKER_RE" && continue
  NEARMISS=$((NEARMISS + 1))
  fail "$f:$n — looks like a binding marker but is not one: '$(printf '%s' "$line" | sed 's/^[[:space:]>]*//')'. Check spelling and case, or remove it — nothing compares the values beneath it."
done < <(grep -rnE "$NEARMISS_RE" . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor 2>/dev/null)

[ "$NEARMISS" -eq 0 ] && pass "no marker-shaped comment that is not the marker"

# --- 2d. the spawn-reachable declaration ------------------------------------------------
# A SECOND declaration, not a copy of the first: `## Allowed Model Values` says what an agent's
# `model:` frontmatter accepts, `## Spawn-Reachable Values` says what the spawn parameter accepts,
# and the two sets differ. It is bound here for a reason the enum above does not have — THREE
# COMMANDS PARSE IT AT RUN TIME (/craft:prime step 4b, /craft:execute step 5, /craft:review Step 2),
# so an edit here changes command behaviour in three places at once, silently.
#
# Review round 7 reproduced exactly that, twice, with the harness GREEN: rewriting the set to two
# values, and replacing the rule with "every value reaches an agent". Hence checks (c) and (d)
# below, which the enum above has no equivalent for.

# Same contract as BOUND_FILES, for the spawn set. One site today; the tree scan below is what
# makes adding a second one a decision rather than an accident.
SPAWN_BOUND_FILES=(
  "model-defaults.md:1"
)

# How many values the declaration must hold. This is NOT bookkeeping, and it is not a copy of the
# value list — it is the same device BOUND_FILES uses for site counts, for the same reason.
#
# With ONE binding site, the declaration is compared against itself, so the both-directions check
# below is structurally vacuous: narrowing the set to three values leaves every copy in perfect
# agreement. Round 7 reproduced exactly that against the real tree. The count is what makes that
# edit loud, and changing it is a decision a human makes when the Agent tool's API changes.
#
# KNOWN RESIDUAL, deliberate: a same-cardinality swap (haiku -> inherit) still passes both this
# count and the subset check. Nothing in the repo can verify a third party's API; the harness can
# only make an edit conspicuous, never confirm it is right. Disclosed in model-defaults.md ->
# Known limits of the binding mechanism.
SPAWN_EXPECTED_VALUES=4

SPAWN_CANON_FILE=""
SPAWN_CANON_LINE=""
while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  if [ -n "$SPAWN_CANON_FILE" ]; then
    fail "more than one canonical spawn declaration (also $f:$n) — there must be exactly one"
    break
  fi
  SPAWN_CANON_FILE="$f"
  SPAWN_CANON_LINE="$n"
done < <(for entry in "${SPAWN_BOUND_FILES[@]}"; do
  bp="${entry%:*}"
  [ -f "$bp" ] || continue
  grep -nE '^[[:space:]>]*<!--[[:space:]]*craft:spawn-enum[[:space:]]+canonical[[:space:]]*-->[[:space:]]*$' "$(defenced "$bp")" \
    | while IFS=: read -r ln _; do printf '%s:%s:\n' "$bp" "$ln"; done
done)

if [ -z "$SPAWN_CANON_FILE" ]; then
  fail "no canonical spawn declaration found — expected '<!-- craft:spawn-enum canonical -->' in model-defaults.md. /craft:prime, /craft:execute and /craft:review all read that set at run time."
else
  SPAWN_VALUE_LINE="$(sed -n "$((SPAWN_CANON_LINE + 1))p" "$(defenced "$SPAWN_CANON_FILE")")"
  SPAWN_VALUES="$(parse_marked_line "$SPAWN_VALUE_LINE" values | sort -u)"

  if [ -z "$SPAWN_VALUES" ]; then
    fail "$SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1)) — canonical spawn marker is not followed by a value list"
  else
    SPAWN_COUNT="$(printf '%s\n' "$SPAWN_VALUES" | wc -l | tr -d ' ')"
    pass "spawn declaration: $SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1)) — $SPAWN_COUNT values ($(printf '%s' "$SPAWN_VALUES" | tr '\n' ' '))"

    assert_nothing_lost "$SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1))" "$SPAWN_VALUE_LINE" \
      && pass "spawn line parses without loss ($SPAWN_COUNT written, $SPAWN_COUNT extracted)"

    # Exactly one colon, on the CANONICAL line too. For the enum this rule runs on copies only,
    # which is safe there because the enum has six of them; the spawn declaration has none, so the
    # rule ran nowhere at all. Round 8 reproduced the consequence: only the text after the LAST
    # colon is compared, so `Spawn-reachable values: opus, sonnet — full set in model-defaults.md:
    # opus, sonnet, haiku, fable` passes the count and the subset check while the list a reader
    # meets first has drifted to two values (R8-4). The widening direction is worse — a five-value
    # visible list with a four-value tail also passes, and a maintainer copies `inherit` into a
    # spawn site.
    spawn_colons="$(printf '%s' "$SPAWN_VALUE_LINE" | sed -E 's:</?(code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>::g' | tr -cd ':' | wc -c | tr -d ' ')"
    if [ "$spawn_colons" -ne 1 ]; then
      fail "$SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1)) — a marked value line must contain exactly one ':' (found $spawn_colons); only the text after it is checked, so a second colon hides whatever precedes it from every comparison."
    else
      pass "$SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1)) — exactly one ':' on the spawn value line"
    fi

    # With one binding site the copy comparison compares the declaration to itself. The count is
    # the only thing that makes a narrowed or widened set loud — see SPAWN_EXPECTED_VALUES.
    if [ "$SPAWN_COUNT" -ne "$SPAWN_EXPECTED_VALUES" ]; then
      fail "$SPAWN_CANON_FILE:$((SPAWN_CANON_LINE + 1)) — $SPAWN_COUNT spawn-reachable value(s), expected $SPAWN_EXPECTED_VALUES. Three commands read this set at run time, so changing it changes their behaviour: update SPAWN_EXPECTED_VALUES in the same commit, deliberately."
    else
      pass "spawn declaration holds its declared $SPAWN_EXPECTED_VALUES values"
    fi

    # (a) every bound copy agrees, in both directions — and carries the site count it declares.
    SPAWN_COPIES=0
    for entry in "${SPAWN_BOUND_FILES[@]}"; do
      f="${entry%:*}"
      expected="${entry##*:}"
      [ -f "$f" ] || { fail "$f — listed as a spawn-bound file but does not exist"; continue; }
      actual="$(grep -cE "$SPAWN_MARKER_RE" "$(defenced "$f")")"
      if [ "$actual" -ne "$expected" ]; then
        fail "$f — $actual spawn binding site(s), expected $expected. A deleted marker unbinds its copy silently; a new one must be declared here."
        continue
      fi
      [ "$expected" -eq 0 ] && continue
      while IFS=: read -r ln _; do
        [ -n "$ln" ] || continue
        vline="$(sed -n "$((ln + 1))p" "$(defenced "$f")")"
        got="$(parse_marked_line "$vline" values | sort -u)"
        assert_nothing_lost "$f:$((ln + 1))" "$vline" || continue
        # The same one-colon rule the canonical line gets. R8-4 added it there and not here,
        # because there was only one site; a legitimately registered second site then got no
        # check at all and its visible list could drift behind a second colon while the run
        # printed "every spawn binding site agrees" (review round 9, F4).
        copy_colons="$(printf '%s' "$vline" | sed -E 's:</?(code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>::g' | tr -cd ':' | wc -c | tr -d ' ')"
        if [ "$copy_colons" -ne 1 ]; then
          fail "$f:$((ln + 1)) — a marked value line must contain exactly one ':' (found $copy_colons); only the text after it is compared, so a second colon hides whatever precedes it."
          continue
        fi
        if [ "$got" != "$SPAWN_VALUES" ]; then
          fail "$f:$((ln + 1)) — spawn values differ from the declaration: '$(printf '%s' "$got" | tr '\n' ' ')' vs '$(printf '%s' "$SPAWN_VALUES" | tr '\n' ' ')'"
        else
          SPAWN_COPIES=$((SPAWN_COPIES + 1))
        fi
      done < <(grep -nE "$SPAWN_MARKER_RE" "$(defenced "$f")" | cut -d: -f1 | while read -r l; do printf '%s:\n' "$l"; done)
    done
    # Guarded: this pass used to sit outside the loop unconditionally, so a site-count mismatch
    # (which `continue`s) or a value mismatch printed a FAIL and "agrees … (0 site(s))" in the same
    # run. In a harness whose thesis is that a green line means something, that is the wrong
    # artefact to ship (R8-10).
    spawn_sites_declared=0
    for entry in "${SPAWN_BOUND_FILES[@]}"; do
      spawn_sites_declared=$((spawn_sites_declared + ${entry##*:}))
    done
    if [ "$SPAWN_COPIES" -eq "$spawn_sites_declared" ]; then
      pass "every spawn binding site agrees with the declaration ($SPAWN_COPIES site(s))"
    else
      fail "spawn binding sites checked: $SPAWN_COPIES of $spawn_sites_declared declared — the rest failed above, so this is not an agreement."
    fi

    # (b) no marked file escapes the list — the same one-level-out rule as 2b.
    SPAWN_UNLISTED=0
    while IFS= read -r found; do
      found="${found#./}"
      [ -n "$found" ] || continue
      [ "$found" = "scripts/test-model-enum.sh" ] && continue
      listed=0
      for entry in "${SPAWN_BOUND_FILES[@]}"; do
        [ "${entry%:*}" = "$found" ] && { listed=1; break; }
      done
      if [ "$listed" -eq 0 ]; then
        SPAWN_UNLISTED=$((SPAWN_UNLISTED + 1))
        fail "$found carries a spawn binding marker but is not in SPAWN_BOUND_FILES — it looks bound and is not checked."
      fi
    done < <(
      grep -rlE "$SPAWN_MARKER_RE" . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor 2>/dev/null | while IFS= read -r cand; do
        grep -qE "$SPAWN_MARKER_RE" "$(defenced "${cand#./}")" && printf '%s\n' "$cand"
      done
    )
    [ "$SPAWN_UNLISTED" -eq 0 ] && pass "every spawn-marked file in the tree is accounted for in SPAWN_BOUND_FILES"

    # (c) the spawn set is a SUBSET of the enum. A spawn cannot carry a value an agent's
    # frontmatter would reject, so a value here that is not there is a contradiction BETWEEN the
    # two declarations — which comparing each against its own copies can never see.
    EXTRA="$(comm -23 <(printf '%s\n' "$SPAWN_VALUES") <(printf '%s\n' "$CANON_VALUES") | tr '\n' ' ')"
    if [ -n "${EXTRA// /}" ]; then
      fail "spawn-reachable values not present in the enum: ${EXTRA% } — a spawn cannot carry a value an agent's model: frontmatter would reject. The two declarations contradict each other."
    else
      pass "spawn-reachable values are a subset of the enum ($SPAWN_COUNT of $CANON_COUNT)"
    fi
  fi

  # (d) the rule and its heading are still there at all. Comparing copies cannot see the deletion
  # of the LAST copy, and /craft:prime resolves the set BY HEADING NAME — a rename breaks three
  # commands with nothing else noticing. Presence only: no check can read the sentence's meaning.
  # Anchored to a heading LINE, not to the string: the file mentions this heading in prose three
  # times (the pointer from Allowed Model Values, and twice inside the section itself), so a plain
  # -F grep finds it after the heading has been renamed away. That is the same prose-vs-binding
  # confusion section 3 exists for, one check further out — and the fixture below caught it.
  #
  # Read through defenced(), because anchoring to a line is NOT enough on its own: round 8
  # reproduced the rename with the old heading parked inside a fenced block, and this check stayed
  # green (R8-7). The same applies to the only-route grep below.
  # section_bounds <file> <heading-line-regex> <terminator-regex> -> "<start>,<end>", blank when
  # the heading is absent. Needed because a heading check binds a NAME and nothing else: review
  # round 9 moved the declaration out of this section and gutted the procedure below it, heading
  # kept in both cases, and the run stayed green (F2). A pointer that resolves to a section which
  # no longer answers is R8-6's failure mode one layer out.
  # section_bounds() is defined at the top of this file (R4-3).

  if ! grep -qE "^${SPAWN_HEADING}[[:space:]]*$" "$(defenced "$SPAWN_CANON_FILE")"; then
    fail "$SPAWN_CANON_FILE — the '$SPAWN_HEADING' heading is gone; /craft:prime, /craft:execute and /craft:review resolve the set by that heading name."
  else
    pass "$SPAWN_CANON_FILE still carries the '$SPAWN_HEADING' heading (the name three commands resolve by)"

    # …and the declaration it is supposed to open actually sits inside it.
    SPAWN_SECT="$(section_bounds "$(defenced "$SPAWN_CANON_FILE")" "^${SPAWN_HEADING}[[:space:]]*$" '^## ')"
    if [ -z "$SPAWN_SECT" ]; then
      fail "$SPAWN_CANON_FILE — could not delimit the '$SPAWN_HEADING' section"
    elif [ "$SPAWN_CANON_LINE" -lt "${SPAWN_SECT%,*}" ] || [ "$SPAWN_CANON_LINE" -gt "${SPAWN_SECT#*,}" ]; then
      fail "$SPAWN_CANON_FILE:$SPAWN_CANON_LINE — the spawn declaration sits OUTSIDE the '$SPAWN_HEADING' section (lines $SPAWN_SECT). Three commands resolve the set by that heading name and would find a section that carries no set."
    else
      pass "$SPAWN_CANON_FILE: the spawn declaration sits inside the section its heading opens (lines $SPAWN_SECT)"
    fi
  fi

  # (e) each READER of this declaration states its own fallback for THIS FILE being unreachable. It
  # is the one part of the procedure that cannot live here — an agent that needs it cannot read this
  # page — so it is written at each reader on purpose, and this check keeps a future de-duplication
  # pass from deleting it. Phase-5 test T3 found the version without it: the declaration was renamed
  # away, /craft:review ran to completion, and the dropped override was never mentioned (B-R7-1).
  #
  # The list is DECLARATION_READERS, not "spawn sites": model-defaults.md names three readers, and
  # round 8 reproduced the version that covered only two — deleting commands/prime.md's handler left
  # the run green and reinstated exactly the silence B-R7-1 was fixed to prevent (R8-3).
  # Read through defenced(): round 8 hardened the two presence checks that read THIS file and
  # left the two that read the command files reading them raw, so a fenced example could stand in
  # for the real sentence. Review round 9 reproduced both (F3) — B-R7-1 and R5-1 reinstated with
  # the run green.
  DECLARATION_READERS="commands/review.md commands/execute.md commands/prime.md"
  MISSING_FALLBACK=""
  for site in $DECLARATION_READERS; do
    if [ ! -f "$site" ]; then
      MISSING_FALLBACK="$MISSING_FALLBACK $site(absent)"
    elif ! grep -q 'Could not read model-defaults.md' "$(defenced "$site")"; then
      MISSING_FALLBACK="$MISSING_FALLBACK $site"
    fi
  done
  if [ -n "$MISSING_FALLBACK" ]; then
    fail "declaration reader(s) without the unreachable-declaration fallback:${MISSING_FALLBACK}. That sentence is not a duplicate of the procedure — it is the case the pointer cannot deliver, because the file it points into is the one that is missing (B-R7-1). See model-defaults.md -> What a spawn site must do."
  else
    pass "every reader of the declaration states its own unreachable fallback (the deliberate copies)"
  fi

  # (f) the POINTER itself, at both ends. The fallback above was bound while the thing it is an
  # exception TO was not: deleting a spawn site's pointer paragraph, or renaming the sub-heading both
  # sites resolve by, left the run green — and a spawn site without its pointer silently ignores
  # every project override, which is R5-1 reinstated (R8-2, reproduced three ways).
  SPAWN_SITES="commands/review.md commands/execute.md"
  SPAWN_HEADING_SUB='### What a spawn site must do'
  MISSING_POINTER=""
  for site in $SPAWN_SITES; do
    if [ ! -f "$site" ]; then
      MISSING_POINTER="$MISSING_POINTER $site(absent)"
    elif ! grep -q 'What a spawn site must do' "$(defenced "$site")"; then
      MISSING_POINTER="$MISSING_POINTER $site"
    fi
  done
  if [ -n "$MISSING_POINTER" ]; then
    fail "spawn site(s) that no longer point at the procedure:${MISSING_POINTER}. Without the pointer the site applies no project override at all, and nothing else says so (R5-1's failure, R8-2)."
  else
    pass "every spawn site points at the procedure"
  fi

  # Anchored to a heading LINE, and read through defenced() — the sub-heading is mentioned in prose
  # in this file and in both commands, and a fenced example must not stand in for it either (R8-7).
  if ! grep -qE "^${SPAWN_HEADING_SUB}[[:space:]]*$" "$(defenced "$SPAWN_CANON_FILE")"; then
    fail "$SPAWN_CANON_FILE — the '$SPAWN_HEADING_SUB' sub-heading is gone; both spawn-site pointers resolve by that name and now dangle."
  else
    pass "$SPAWN_CANON_FILE still carries the '$SPAWN_HEADING_SUB' sub-heading (the pointers' target)"

    # …and the procedure it names still says the things its readers were sent here for. Presence
    # only — no check reads meaning — but an empty section is not a procedure (F2).
    PROC_SECT="$(section_bounds "$(defenced "$SPAWN_CANON_FILE")" "^${SPAWN_HEADING_SUB}[[:space:]]*$" '^#{2,3} ')"
    if [ -z "$PROC_SECT" ]; then
      fail "$SPAWN_CANON_FILE — could not delimit the '$SPAWN_HEADING_SUB' section"
    else
      PROC_BODY="$(sed -n "${PROC_SECT%,*},${PROC_SECT#*,}p" "$(defenced "$SPAWN_CANON_FILE")")"
      MISSING_STEP=""
      for needle in 'Take the set' 'Could not read model-defaults.md' 'do not de-duplicate it'; do
        printf '%s' "$PROC_BODY" | grep -qF -- "$needle" || MISSING_STEP="$MISSING_STEP '$needle'"
      done
      if [ -n "$MISSING_STEP" ]; then
        fail "$SPAWN_CANON_FILE — the '$SPAWN_HEADING_SUB' section no longer states:${MISSING_STEP}. Both spawn-site pointers resolve to this section by name; an emptied one leaves them pointing at nothing while every other check stays green (F2)."
      else
        pass "$SPAWN_CANON_FILE: the '$SPAWN_HEADING_SUB' section still states the steps its pointers send readers for"
      fi
    fi
  fi

  if ! grep -q 'only.*route from' "$(defenced "$SPAWN_CANON_FILE")"; then
    fail "$SPAWN_CANON_FILE — the rule stating that the spawn parameter is the only route from a profile to a running agent is gone. Round 7 reproduced its deletion GREEN while /craft:prime would stop reporting inert overrides and both spawn sites would start raising InputValidationError."
  else
    pass "$SPAWN_CANON_FILE still states the only-route rule (presence only — no check can read its meaning)"
  fi
fi

# --- 3. a marker in prose is not a binding site ---------------------------------------
# model-defaults.md documents the mechanism and therefore writes the marker inside a
# sentence. If that ever started counting, the contract's own description would be
# checked as a copy and this harness would report drift about itself.

# R4-9 (slice-047): both counts used to read the raw file, so a marker parked in a fenced
# example inflated the prose count and this check reported the distinction as tested when it was
# not. Read through defenced(), like every other marker-level check.
PROSE_MARKERS="$(grep -cE 'craft:model-enum' "$(defenced "$CANON_FILE")")"
BINDING_MARKERS="$(grep -cE "$MARKER_RE" "$(defenced "$CANON_FILE")")"
if [ "$PROSE_MARKERS" -le "$BINDING_MARKERS" ]; then
  fail "$CANON_FILE — expected the contract to also mention the marker in prose; the prose/binding distinction is untested"
else
  pass "marker in prose is ignored ($((PROSE_MARKERS - BINDING_MARKERS)) prose mention(s), $BINDING_MARKERS binding site(s) in $CANON_FILE)"
fi

# --- 4. fable is never selected by CRAFT ----------------------------------------------
# It is a legitimate value a human may write into a project profile. What must not
# happen is CRAFT choosing it on its own — so no shipped agent may declare it.

# The quotes are not cosmetic: `model: "fable"` and `model: 'fable'` are valid YAML and mean
# exactly the same thing, and the bare-token regex matched neither. A new agent could declare the
# quoted form and pass the one half of the fable rule this file promises is mechanically enforced
# (review round 7, R7-9 — reproduced GREEN).
FABLE_RE='^[[:space:]]*model:[[:space:]]*["'"'"']?fable["'"'"']?[[:space:]]*$'
if grep -lE "$FABLE_RE" agents/*.md >/dev/null 2>&1; then
  offenders="$(grep -lE "$FABLE_RE" agents/*.md | tr '\n' ' ')"
  fail "fable is declared by a shipped agent (${offenders% }) — it is human-chosen only"
else
  pass "no shipped agent declares model: fable"
fi

# This check greps the RULE's distinctive wording, not the bare token `fable` — the token
# appears in the canonical enum line itself, so the old version could never fail while fable
# was an allowed value. Deleting the entire rule left it green (review round 1, R1-2).
#
# What it can honestly claim: the sentence is present. Not that it says what it should, and
# not that anything obeys it. The enforceable half is the agents/*.md check above; this one
# only stops the rule from vanishing unnoticed.
if ! grep -q 'human-chosen only' "$(defenced "$CANON_FILE")"; then
  fail "$CANON_FILE — the 'human-chosen only' rule for fable is gone; fable is an allowed value with nothing stating that CRAFT never selects it"
else
  pass "$CANON_FILE still states the 'human-chosen only' rule (presence only — no check can read its meaning)"
fi

# --- 5. agent frontmatter follows the Cache TTL rule ----------------------------------
# model-defaults.md -> Cache TTL: 1h for an agent that waits, the 5m default for a
# short-burst agent. The absence on code-reviewer is as deliberate as the presence on
# slice-builder, and is asserted here so it reads as a decision, not an oversight.

frontmatter() { sed -n '2,/^---$/p' "$1"; }

# Both assertions used to be literals here — 'effort: high', 'cacheTtl: 1h', and a bare
# code-reviewer — naming two agents and reading NOTHING from the tables whose authority the
# failure messages cited. That made them this harness's own unbound copy of model-defaults.md,
# the exact duplication the slice exists to abolish: review round 9 reproduced three green runs
# (the effort cell set to '—', the TTL bullet moved, an effort added to the undecided row) with
# the agent files untouched (F1). They are now DERIVED per agent in check_agent_effort_ttl below,
# from role_effort() and role_ttl(), and run inside the agents/*.md loop — so a third agent is
# covered the moment it exists, the same trade R7-13 made for the model.

# The one role -> model mapping that can be bound mechanically. model-defaults.md states it
# twice (Default Mapping, and the tier table's "Resolves to" column); an agent's frontmatter is
# the third place. Binding the frontmatter to the tier keeps the slice's own thesis honest —
# a second description of a rule must at minimum be checked against the first.
tier_model() {  # tier_model <tier> -> the model that tier resolves to, read from the table
  grep -E "^\|[[:space:]]*\*\*\`?$1\`?\*\*[[:space:]]*\|" "$(defenced "$CANON_FILE")" \
    | sed -E 's/^[^|]*\|[^|]*\|[[:space:]]*//; s/[[:space:]]*\|.*$//' \
    | tr -d '`' | tr -d ' '
}

# role_tier <agent-name> -> the tier its Role → tier row assigns it. Derived, not passed in:
# passing the tier as an argument left the row itself unbound, so retiering slice-builder in the
# table (or changing the Default Mapping row) stayed green while the agent kept its old model.
# Review round 2 reproduced three such green runs.
role_tier() {
  grep -E "^\|[[:space:]]*\`?$1\`?[[:space:]]*\|" "$(defenced "$CANON_FILE")" \
    | grep -oE "\|[[:space:]]*($TIER_SET)[[:space:]]*\|" \
    | head -1 | tr -d '| '
}

# role_effort <agent-name> -> the `effort` cell of its Role → tier row, '' when the cell is '—'.
# Restricted to rows that also carry a tier, so the Default Mapping table's rows cannot match.
# model-defaults.md defines '—' as "not a value … the cell was never decided", so an empty
# result means "the agent must declare no effort key", not "any effort is fine".
role_effort() {
  grep -E "^\|[[:space:]]*\`?$1\`?[[:space:]]*\|[[:space:]]*($TIER_SET)[[:space:]]*\|" "$(defenced "$CANON_FILE")" \
    | head -1 | awk -F'|' '{print $4}' \
    | sed -E 's/\*\(proposal\)\*//g; s/[[:space:]]//g' | tr -d '`'
}

# ttl_bullet <1h|5m> -> the text of that bullet under '### Cache TTL', blank line ends it.
ttl_bullet() {
  awk -v want="$1" '
    /^### Cache TTL/ { inblk = 1; next }
    !inblk { next }
    /^#{2,3} / { exit }
    /^- \*\*/ { cur = ($0 ~ /^- \*\*1h\*\*/) ? "1h" : (($0 ~ /^- \*\*5m/) ? "5m" : "other") }
    /^[[:space:]]*$/ { cur = "" }
    cur == want { print }
  ' "$(defenced "$CANON_FILE")"
}

# role_ttl <agent-name> -> 1h | 5m | '' (named by neither bullet).
role_ttl() {
  if ttl_bullet 1h | grep -q -- "\`$1\`"; then printf '1h\n'; return; fi
  if ttl_bullet 5m | grep -q -- "\`$1\`"; then printf '5m\n'; return; fi
  printf ''
}

# default_mapping_model <agent-name> -> the Model cell of its Default Mapping row.
default_mapping_model() {
  grep -E "^\|.*\`$1\`" "$(defenced "$CANON_FILE")" \
    | grep -E '\| *[0-9]+ —' \
    | sed -E 's/.*\|[[:space:]]*\`?([a-z0-9-]+)\`?[[:space:]]*\|[[:space:]]*$/\1/' \
    | head -1 | tr -d '` '
}

check_agent_tier() {  # check_agent_tier <agent-file> <agent-name>
  local f="$1" name="$2" tier want got mapped
  tier="$(role_tier "$name")"
  got="$(frontmatter "$f" | sed -nE 's/^model:[[:space:]]*//p' | tr -d ' ')"

  if [ -z "$tier" ]; then
    fail "$CANON_FILE — no Role → tier row assigns a tier to \`$name\`"
    return
  fi
  want="$(tier_model "$tier")"
  if [ -z "$want" ]; then
    fail "$CANON_FILE — cannot read the model for tier '$tier' from the Capability Tiers table"
    return
  fi
  if [ "$want" != "$got" ]; then
    fail "$f declares model: $got, but its Role → tier row says $tier, which resolves to $want in $CANON_FILE — the agent and the tables disagree"
    return
  fi
  pass "$f: model $got matches its role row ($tier → $want) in $CANON_FILE"

  # The third description of the same mapping. All three must agree, or one of them is a copy
  # nobody maintains — which is the duplication this slice exists to abolish.
  mapped="$(default_mapping_model "$name")"
  if [ -z "$mapped" ]; then
    fail "$CANON_FILE — no Default Mapping row names \`$name\` with a model"
  elif [ "$mapped" != "$got" ]; then
    fail "$CANON_FILE — the Default Mapping row for \`$name\` says $mapped, the agent declares $got"
  else
    pass "$CANON_FILE: Default Mapping row for $name agrees ($mapped)"
  fi
}

check_agent_effort_ttl() {  # check_agent_effort_ttl <agent-file> <agent-name>
  local f="$1" name="$2" want_effort got_effort want_ttl
  want_effort="$(role_effort "$name")"
  got_effort="$(frontmatter "$f" | sed -nE 's/^effort:[[:space:]]*//p' | tr -d ' ')"
  case "$want_effort" in
    ''|'—'|'-')
      if [ -n "$got_effort" ]; then
        fail "$f declares effort: $got_effort, but its Role → tier row in $CANON_FILE leaves the effort cell undecided ('—', which that table defines as 'the cell was never decided') — decide it in the table first"
      else
        pass "$f: no effort key, matching the undecided effort cell in its Role → tier row"
      fi ;;
    *)
      if [ "$want_effort" != "$got_effort" ]; then
        fail "$f declares effort: ${got_effort:-<none>}, but its Role → tier row in $CANON_FILE says $want_effort — the agent and the table disagree"
      else
        pass "$f: effort $got_effort matches its Role → tier row ($want_effort)"
      fi ;;
  esac

  want_ttl="$(role_ttl "$name")"
  case "$want_ttl" in
    1h)
      if frontmatter "$f" | grep -qE '^experimental:[[:space:]]*\{[[:space:]]*cacheTtl:[[:space:]]*1h[[:space:]]*\}[[:space:]]*$'; then
        pass "$f: experimental {cacheTtl: 1h}, matching the 1h bullet under Cache TTL"
      else
        fail "$f — the 1h bullet under '### Cache TTL' in $CANON_FILE names \`$name\` (an agent that waits), so it must declare 'experimental: {cacheTtl: 1h}'"
      fi ;;
    5m)
      if frontmatter "$f" | grep -qE '^experimental:'; then
        fail "$f declares an experimental block, but the 5m bullet under '### Cache TTL' in $CANON_FILE names \`$name\` — move it to the 1h bullet there first if this is intended"
      else
        pass "$f: no experimental block, matching the 5m default bullet under Cache TTL"
      fi ;;
    *)
      fail "$CANON_FILE — no bullet under '### Cache TTL' names \`$name\`; the agent has no recorded TTL decision" ;;
  esac
}

# Every agent in the tree, not two by name. The named form left a third agent invisible to this
# whole cross-check: adding one with a model contradicting its tier row stayed green (review round
# 7, R7-13). Because check_agent_tier fails when no Role → tier row assigns the agent a tier, the
# loop also turns "register the new agent in the tables" from a documented obligation into a
# mechanical one — which is why model-defaults.md's new-agent checklist no longer carries it.
AGENTS_CHECKED=0
for af in agents/*.md; do
  [ -f "$af" ] || continue
  check_agent_tier "$af" "$(basename "$af" .md)"
  check_agent_effort_ttl "$af" "$(basename "$af" .md)"
  AGENTS_CHECKED=$((AGENTS_CHECKED + 1))
done
if [ "$AGENTS_CHECKED" -eq 0 ]; then
  fail "agents/ holds no agent definitions — the tier cross-check ran against nothing"
else
  pass "tier cross-check covered every agent in agents/ ($AGENTS_CHECKED)"
fi


# --- 6. the tier table covers the roles -----------------------------------------------

# A role counts as covered only by a real table ROW that also names a tier — not by the
# role's name appearing somewhere in the file, which 'slice-builder' does a dozen times.
# The role list below mirrors the design record; it is a coverage assertion, not a second
# copy of the enum.

row_names_role_and_tier() {
  grep -E '^\|' "$(defenced "$CANON_FILE")" \
    | grep -F -- "$1" \
    | grep -qE "\|[[:space:]]*($TIER_SET)[[:space:]]*\|"
}

TIER_ROWS_OK=1
for role in 'Master / orchestrator' 'slice-planner' 'plan-architect' 'slice-builder' \
            'ping-pong trip' 'E2E verification' 'code-reviewer' 'Digests / recap'; do
  if ! row_names_role_and_tier "$role"; then
    fail "$CANON_FILE — Role → tier table has no row pairing '$role' with a tier"
    TIER_ROWS_OK=0
  fi
done
[ "$TIER_ROWS_OK" -eq 1 ] && pass "Role → tier table pairs all eight roles with a tier"

TIERS_OK=1
for tier in $(printf '%s' "$TIER_SET" | tr '|' ' '); do
  if ! grep -qE "^\|[[:space:]]*\*\*\`?$tier\`?\*\*" "$(defenced "$CANON_FILE")"; then
    fail "$CANON_FILE — capability tier '$tier' has no definition row"
    TIERS_OK=0
  fi
done
[ "$TIERS_OK" -eq 1 ] && pass "every capability tier read from the table has a definition row"

# --- 7. self-test: prove the checks bite ----------------------------------------------
# A harness that only ever runs against a correct tree reports GREEN whether or not it
# checks anything — slice-031 paid for that lesson. So each rule above is fed a tree
# mutated to break exactly it, and must come back RED.

if [ -z "${CRAFT_ENUM_SELFTEST_CHILD:-}" ]; then
  SELFTEST_DIR="$(mktemp -d)"
  trap 'rm -rf "$SELFTEST_DIR"' EXIT

  seed_fixture() {
    local dst="$1"
    rm -rf "$dst"
    mkdir -p "$dst/scripts" "$dst/agents" "$dst/commands" "$dst/templates/profiles" "$dst/docs"
    cp "$ROOT/scripts/test-model-enum.sh" "$dst/scripts/"
    # defenced() calls it; without it every fixture dies at startup and the control goes red
    # (slice-047).
    cp "$ROOT/scripts/example-regions.sh" "$dst/scripts/"
    cp "$ROOT/model-defaults.md" "$dst/"
    # prime.md is the declared-zero binding site; review.md and execute.md are the two spawn
    # sites whose unreachable-declaration fallback check (2d/e) reads them. A check that reads a
    # file the fixture does not carry turns the positive control red and makes every mutation
    # result below meaningless — which is how this line was found.
    cp "$ROOT/commands/prime.md" "$ROOT/commands/review.md" "$ROOT/commands/execute.md" "$dst/commands/"
    cp "$ROOT/templates/craft-profile.md.template" "$dst/templates/"
    cp "$ROOT"/templates/profiles/*.md "$dst/templates/profiles/"
    cp "$ROOT/docs/index.html" "$dst/docs/"
    cp "$ROOT"/agents/*.md "$dst/agents/"
  }

  run_fixture() {
    CRAFT_ENUM_ROOT="$1" CRAFT_ENUM_SELFTEST_CHILD=1 bash "$1/scripts/test-model-enum.sh" >/dev/null 2>&1
  }

  # positive control — an untouched copy must still be green, or every RED below
  # would prove nothing but a broken fixture
  seed_fixture "$SELFTEST_DIR/control"
  if run_fixture "$SELFTEST_DIR/control"; then
    pass "self-test control: an unmutated copy is GREEN"
  else
    fail "self-test control: an unmutated copy came back RED — the fixture is broken, every mutation result below is meaningless"
  fi

  # A mutation is applied by `subst`, which does a LITERAL replacement and exits 3 when its
  # pattern is not present. That exit status matters: a mutation that silently stops matching
  # after an unrelated edit would otherwise surface as "the harness stayed GREEN on a tree
  # that should fail it" — blaming the harness for a broken fixture. python3, not perl:
  # every other script under scripts/ uses it, and check-toolchain.sh guarantees only bash
  # and python3.
  # R4-2 (slice-047): this used to `replace(old, new, 1)` after only checking that the pattern
  # EXISTS. With several occurrences the mutation silently hit the first one — which may be a
  # documentation example rather than the binding site the case names — and the case then reported
  # a result about something else while still looking green. A fixture that cannot say which
  # occurrence it changed is not evidence, so an ambiguous pattern is now a fixture error (exit 4)
  # and the case must be given a longer, unique pattern instead.
  #
  # A fourth argument, "<n>/<total>", lets a case DECLARE which occurrence it means and how many
  # there are; absent, it means 1/1 and several occurrences are an error. The declaration exists
  # for the unavoidable case: a fixture that mutates THIS file writes its pattern literally in its
  # own source, so the pattern is always there twice — once at the real site, once in the fixture.
  # Picking the first silently worked only because the code happens to sit above the fixtures; the
  # declaration says so out loud and fails if the count ever changes.
  #
  # Exit codes: 3 = pattern absent, 4 = count is not the declared total, 0 = the n-th replaced.
  subst() {
    python3 - "$1" "$2" "$3" "${4:-1/1}" <<'PY'
import pathlib, sys
path, old, new, which = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
nth, total = (int(x) for x in which.split("/"))
p = pathlib.Path(path)
t = p.read_text()
n = t.count(old)
if n == 0:
    sys.exit(3)
if n != total:
    sys.stderr.write("COUNT=%d DECLARED=%d\n" % (n, total))
    sys.exit(4)
i = -1
for _ in range(nth):
    i = t.index(old, i + 1)
p.write_text(t[:i] + new + t[i + len(old):])
PY
  }

  # Reports an ambiguous pattern as what it is — a broken fixture — separately from an absent one,
  # because the two need different repairs: absent means the tree moved, ambiguous means the case
  # was never specific enough.
  subst_report() {   # subst_report <label> <file> <exit-code>
    case "$3" in
      3) fail "self-test '$1' — the mutation did not apply (its pattern is gone from $2); the fixture, not the harness, is broken" ;;
      4) fail "self-test '$1' — the mutation's pattern does not occur as often as the case declares in $2, so the case cannot say which occurrence it tests (R4-2); give it a unique pattern, or declare '<n>/<total>'" ;;
      *) fail "self-test '$1' — subst failed on $2 (exit $3)" ;;
    esac
  }

  # subst is the fixture machinery, so it gets its own checks: every other case below is only
  # as trustworthy as it is. R4-2 was that it verified the pattern EXISTS and then replaced the
  # first occurrence, so a case could silently mutate a documentation example instead of the
  # binding site it names and still report a result.
  _sp="$SELFTEST_DIR/subst-probe"
  mkdir -p "$_sp"
  printf 'alpha\nbeta\nalpha\n' > "$_sp/f"
  ( cd "$_sp" && subst f zeta x 2>/dev/null ); [ $? -eq 3 ] \
    && pass "subst: an absent pattern is exit 3 (the tree moved)" \
    || fail "subst: an absent pattern should exit 3"
  ( cd "$_sp" && subst f alpha x 2>/dev/null ); [ $? -eq 4 ] \
    && pass "subst: two occurrences with no declaration is exit 4 (R4-2 — the case cannot say which it means)" \
    || fail "subst: an undeclared ambiguous pattern should exit 4"
  ( cd "$_sp" && subst f alpha x 1/3 2>/dev/null ); [ $? -eq 4 ] \
    && pass "subst: a declared total that does not match the file is exit 4" \
    || fail "subst: a wrong declared total should exit 4"
  printf 'alpha\nbeta\nalpha\n' > "$_sp/f"
  if ( cd "$_sp" && subst f alpha REPLACED 2/2 2>/dev/null ) \
     && [ "$(sed -n '1p' "$_sp/f")" = "alpha" ] && [ "$(sed -n '3p' "$_sp/f")" = "REPLACED" ]; then
    pass "subst: '2/2' replaces the SECOND occurrence and leaves the first alone"
  else
    fail "subst: '2/2' did not replace the second occurrence (got: $(tr '\n' ' ' < "$_sp/f"))"
  fi

  # selftest_case <label> <file> <old> <new>  — mutate one file, expect RED.
  selftest_case() {   # … [<n>/<total>]
    local label="$1" file="$2" old="$3" new="$4" which="${5:-1/1}"
    local dir="$SELFTEST_DIR/case"
    seed_fixture "$dir"
    ( cd "$dir" && subst "$file" "$old" "$new" "$which" 2>/dev/null ); rc=$?
    if [ "$rc" -ne 0 ]; then subst_report "$label" "$file" "$rc"; return; fi
    if run_fixture "$dir"; then
      fail "self-test '$label' — the harness stayed GREEN on a tree that should fail it"
    else
      pass "self-test '$label' — correctly RED"
    fi
  }

  # selftest_case_newfile <label> <src> <dst> <old> <new> — copy src to a NEW file with one
  # literal substitution, expect RED. The other variants can only mutate files the fixture
  # already has, and the case that matters here is a file the harness has never seen.
  selftest_case_newfile() {
    local label="$1" src="$2" dst="$3" old="$4" new="$5"
    local dir="$SELFTEST_DIR/case"
    seed_fixture "$dir"
    cp "$dir/$src" "$dir/$dst"
    ( cd "$dir" && subst "$dst" "$old" "$new" 2>/dev/null ); rc=$?
    if [ "$rc" -ne 0 ]; then subst_report "$label" "$dst" "$rc"; return; fi
    if run_fixture "$dir"; then
      fail "self-test '$label' — the harness stayed GREEN on a tree that should fail it"
    else
      pass "self-test '$label' — correctly RED"
    fi
  }

  # selftest_case_green <label> <file> <old> <new> — mutate one file, expect it to stay GREEN.
  # The RED-only machinery cannot express "this edit is legitimate and must NOT trip anything",
  # which is the whole claim of the prose-marker rule.
  selftest_case_green() {
    local label="$1" file="$2" old="$3" new="$4"
    local dir="$SELFTEST_DIR/case"
    seed_fixture "$dir"
    ( cd "$dir" && subst "$file" "$old" "$new" 2>/dev/null ); rc=$?
    if [ "$rc" -ne 0 ]; then subst_report "$label" "$file" "$rc"; return; fi
    if run_fixture "$dir"; then
      pass "self-test '$label' — correctly stayed GREEN"
    else
      fail "self-test '$label' — the harness went RED on an edit that is legitimate"
    fi
  }

  # selftest_case2 <label> <f1> <o1> <n1> <f2> <o2> <n2> — TWO substitutions, expect RED.
  # Needed for a mutation that is only reachable when a maintainer does two things at once, e.g.
  # adding a second spawn binding site AND registering it in SPAWN_BOUND_FILES. With one
  # substitution the site would be unregistered and the tree scan would fire instead — red for a
  # reason other than the one the label names, the R8-9 defect this harness now guards against.
  selftest_case2() {   # … [<n>/<total> for the SECOND substitution]
    local label="$1" f1="$2" o1="$3" n1="$4" f2="$5" o2="$6" n2="$7" w2="${8:-1/1}"
    local dir="$SELFTEST_DIR/case"
    seed_fixture "$dir"
    ( cd "$dir" && subst "$f1" "$o1" "$n1" 2>/dev/null ); rc=$?
    if [ "$rc" -ne 0 ]; then subst_report "$label" "$f1" "$rc"; return; fi
    ( cd "$dir" && subst "$f2" "$o2" "$n2" "$w2" 2>/dev/null ); rc=$?
    if [ "$rc" -ne 0 ]; then subst_report "$label" "$f2" "$rc"; return; fi
    if run_fixture "$dir"; then
      fail "self-test '$label' — the harness stayed GREEN on a tree that should fail it"
    else
      pass "self-test '$label' — correctly RED"
    fi
  }

  selftest_case "a copy loses a value" \
    templates/profiles/balanced.md "$(vlist "$CANON_COUNT")" "$(vlist $((CANON_COUNT - 2)))"

  selftest_case "a copy gains a value the declaration does not have" \
    templates/profiles/careful.md "$(vlist "$CANON_COUNT")" "$(vlist "$CANON_COUNT"), \`nonesuch\`"

  selftest_case "a stray word is left after the colon" \
    templates/craft-profile.md.template "Allowed values: $(vlist 1)" "Allowed values: probably $(vlist 1)"

  selftest_case "the canonical declaration is removed" \
    model-defaults.md '<!-- craft:model-enum canonical -->' '<!-- nothing -->'

  selftest_case "code-reviewer picks up an undecided effort" \
    agents/code-reviewer.md 'model: opus' 'model: opus
effort: high'

  # R7-9: the same declaration in quotes. Identical YAML, and the old regex saw nothing.
  selftest_case "an agent declares model: \"fable\" (quoted)" \
    agents/slice-builder.md 'model: sonnet' 'model: "fable"'

  selftest_case "an agent declares model: fable" \
    agents/slice-builder.md "model: $(tier_model execute)" "model: fable"

  selftest_case "slice-builder loses its 1h cache TTL" \
    agents/slice-builder.md 'experimental: {cacheTtl: 1h}' ''

  # The hole review round 1 reproduced: removing a marker used to unbind the copy silently.
  selftest_case "a copy loses its marker" \
    templates/profiles/careful.md '> <!-- craft:model-enum -->
' ''

  # The reviewer's exact edit: marker gone AND values drifted. Before the per-file binding
  # count this run was GREEN while careful.md shipped the old four-value list.
  selftest_case "a copy loses its marker and drifts its values" \
    templates/profiles/careful.md "> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")" "> Allowed values: $(vlist $((CANON_COUNT - 2)))"

  # The value line is deliberately absent. It used to carry a SINGLE-quoted "$(vlist 1)", which
  # inserted that text literally, so the second failure read "missing: <all six values>" — a
  # diagnosis pointing at drift in commands/prime.md, which is not what happened (review round 7,
  # R7-15).
  #
  # What this fixes and what it does not: the case still produces TWO failures, because the loop
  # above deliberately does not `continue` after a count mismatch — that is what lets "marker
  # deleted AND values drifted" report both halves. Reducing this case to one failure would mean
  # weakening that loop, which is worth more than a tidy fixture. What changed is that the second
  # failure is now TRUE of the mutation ("marked, but no value list") instead of misdescribing it.
  # The slice's round-1 lesson is "a mutation must not go red for a reason that misleads", not
  # "exactly one check may fire".
  selftest_case "a marker is added to a file declared to have none" \
    commands/prime.md '## Pre-flight' '<!-- craft:model-enum -->

## Pre-flight'

  # Deletes ONLY the rule sentence, leaving the enum line intact, so this fixture can fail for
  # exactly one reason. The round-1 version (s/fable/redacted/g) rewrote the canonical line too
  # and went red through six unrelated enum failures, never reaching the check it was named
  # for: red for the wrong reason proves nothing.
  selftest_case "the human-chosen-only rule is deleted (enum left intact)" \
    model-defaults.md 'human-chosen only' 'redacted'

  # --- the spawn declaration (2d) -------------------------------------------------------
  # These five reproduce review round 7's findings. The first two were reproduced GREEN against
  # the real tree before this section existed; the harness must now go RED on both.

  # Round 7, P5/F3: drift the value list while leaving the sentence around it intact. A presence
  # grep on the rule would NOT catch this — only the declaration-vs-copies comparison does.
  selftest_case "the spawn set drifts to a narrower set" \
    model-defaults.md "Spawn-reachable values: $(vlist 3)" "Spawn-reachable values: $(vlist 2)"

  # Round 7, F4: replace the rule itself. Comparing copies cannot see the deletion of the LAST
  # copy, so this is what check (d) exists for.
  selftest_case "the only-route rule is deleted (declaration left intact)" \
    model-defaults.md 'only** route from' 'redacted from'

  # /craft:prime, /craft:execute and /craft:review all resolve the set BY HEADING NAME. A rename
  # breaks three commands and changes no value anywhere.
  #
  # The pattern carries its leading newline on purpose: `subst` replaces the FIRST literal hit, and
  # the first mention of this string in the file is the pointer in prose, not the heading. Without
  # the newline the fixture renamed the pointer, the heading survived, and the case came back green
  # — a fixture that fails to mutate proves nothing about the check it is named for.
  selftest_case "the spawn section heading is renamed" \
    model-defaults.md "$(printf '\n## Spawn-Reachable Values\n')" "$(printf '\n## Reachable Values\n')"

  # The same unbinding failure as R1-4, on the new declaration: remove the marker and the copy
  # stops being compared.
  selftest_case "the spawn declaration loses its marker" \
    model-defaults.md '<!-- craft:spawn-enum canonical -->' ''

  # The two declarations must not contradict each other. Neither one's own copy comparison can
  # see this, because each is internally consistent.
  selftest_case "a spawn value is not in the enum" \
    model-defaults.md 'Spawn-reachable values: `opus`' 'Spawn-reachable values: `gpt-4`, `opus`'

  # Re-introduces the exact normalizer bug round 1 exposed: a greedy tag regex that also eats
  # <model-id>. Every site loses the same value, so set comparison still sees perfect
  # agreement — only the written-vs-extracted invariant catches it.
  selftest_case "the normalizer silently drops a value everywhere" \
    scripts/test-model-enum.sh 'r"</?(?:code|td|tr|th|strong|em|span|p|li|ul|ol|br)\b[^>]*>"' 'r"</?[A-Za-z][^>]*>"' 1/2

  selftest_case "a role loses its tier-table row" \
    model-defaults.md '| `plan-architect` | deep-reason |' '| |'

  selftest_case "a capability tier loses its definition row" \
    model-defaults.md '| **deep-reason** |' '| |'

  selftest_case "an agent's model contradicts its tier row" \
    agents/code-reviewer.md 'model: opus' 'model: haiku'

  selftest_case "a tier row's resolved model changes without the agents" \
    model-defaults.md "| **execute** | \`$(tier_model execute)\` |" "| **execute** | \`haiku-probe\` |"

  # Round 2 reproduced these three GREEN: the tier was a constant in the script, so the
  # tables could be edited to contradict the agents without anything noticing.
  selftest_case "a role row is retiered away from its agent" \
    model-defaults.md '| `slice-builder` | execute |' '| `slice-builder` | deep-reason |'

  selftest_case "the reviewer's role row is retiered" \
    model-defaults.md '| `code-reviewer` | deep-reason |' '| `code-reviewer` | execute |'

  selftest_case "the Default Mapping row contradicts the agent" \
    model-defaults.md "| \`slice-builder\` | \`$(tier_model execute)\` |" "| \`slice-builder\` | \`$(tier_model deep-reason)\` |"

  # Review round 2 reproduced both of these GREEN.
  selftest_case_newfile "a marked file the list does not name" \
    templates/profiles/balanced.md templates/profiles/aggressive.md \
    "$(vlist "$CANON_COUNT")" "$(vlist $((CANON_COUNT - 2)))"

  selftest_case "a file is dropped from BOUND_FILES" \
    scripts/test-model-enum.sh '  "templates/profiles/careful.md:1"
' '' 1/2

  # Round 2 reproduced this GREEN: the checked text and the text a human reads were different.
  selftest_case "drift hides behind a second colon" \
    templates/profiles/balanced.md \
    "> Allowed values: $(vlist "$CANON_COUNT")" \
    "> Allowed values: $(vlist $((CANON_COUNT - 2))) — full list in model-defaults.md: $(vlist "$CANON_COUNT")"

  # Round 3 reproduced this GREEN: a fenced EXAMPLE satisfied the per-file count in place of
  # the deleted real marker, while the list a human reads had drifted back to four values.
  selftest_case "a fenced example stands in for a deleted marker" \
    templates/profiles/careful.md \
    "> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")" \
    "> Allowed values: $(vlist $((CANON_COUNT - 2)))

\`\`\`markdown
<!-- craft:model-enum -->
Allowed values: $(vlist "$CANON_COUNT")
\`\`\`"

  # Round 3 reproduced this GREEN twice (wrong case, and a suffixed token): the file is not
  # listed so nothing compares it, and it does not match MARKER_RE so nothing flagged it.
  # B-R7-1: a de-duplication pass deletes the fallback sentence from one spawn site. This is the
  # exact edit a reader applying R7-10 ("the rule is never described twice") would make, which is
  # why the check exists at all.
  selftest_case "a spawn site loses the unreachable-declaration fallback" \
    commands/review.md 'Could not read model-defaults.md' 'REDACTED'

  # R8-3: the same edit on the THIRD reader. The round-8 version of the check named only the two
  # spawn sites, so this mutation was green and prime went back to reporting an override as
  # effective with no signal — the R7-19 silence, reinstated by the fix against reinstating it.
  selftest_case "prime loses its own unreachable-declaration fallback" \
    commands/prime.md 'Could not read model-defaults.md' 'REDACTED'

  # R8-2: the pointer, deleted while the fallback stays. A spawn site without its pointer applies
  # no project override at all and nothing says so — R5-1's failure, and green until round 8.
  selftest_case "a spawn site loses its pointer to the procedure" \
    commands/review.md 'What a spawn site must do' 'REDACTED'

  # R8-2: the target both pointers resolve by, renamed. Changes no value anywhere.
  selftest_case "the procedure sub-heading is renamed" \
    model-defaults.md "$(printf '\n### What a spawn site must do\n')" "$(printf '\n### Spawn notes\n')"

  # R8-7: the heading check is anchored to a LINE, which is not enough on its own — the old heading
  # parked in a fenced block satisfied a raw grep. Reading the defenced copy is what closes it.
  selftest_case "the spawn heading is renamed with a fenced decoy" \
    model-defaults.md "$(printf '\n## Spawn-Reachable Values\n')" \
    "$(printf '\n## Reachable Values\n\n```markdown\n## Spawn-Reachable Values\n```\n')"

  # R8-4: a near-miss on the SECOND declaration's token. Compared by nothing (the file is in no
  # bound list) and, before round 8's widening, flagged by nothing either.
  selftest_case_newfile "a near-miss spawn marker looks bound and is not" \
    templates/profiles/careful.md templates/profiles/decoy.md \
    '> <!-- craft:model-enum -->' '> <!-- craft:spawn-enum2 -->'

  # R8-4: the spawn declaration drifts behind a second colon. Count and subset both still pass,
  # because both read only the tail.
  selftest_case "the spawn declaration drifts behind a second colon" \
    model-defaults.md "Spawn-reachable values: $(vlist 3)" \
    "Spawn-reachable values: $(vlist 2) — full set in model-defaults.md: $(vlist 3)"

  # R7-13: a THIRD agent, which the two named check_agent_tier calls could never see. It has no
  # Role → tier row, so the loop must report it — that is what turns registering a new agent from
  # a documented obligation into a mechanical one.
  #
  # The name matters. The first version copied to `plan-architect`, which HAS a Role → tier row,
  # so the run went red on a model/tier mismatch instead of the missing-registration branch the
  # label names — red for a reason the label does not claim, and the branch itself untested
  # (R8-9, the R4-2 class). `digest-writer` appears in no table.
  selftest_case_newfile "a third agent nothing registers" \
    agents/slice-builder.md agents/digest-writer.md 'name: slice-builder' 'name: digest-writer'

  selftest_case_newfile "a near-miss marker looks bound and is not" \
    templates/profiles/balanced.md templates/profiles/legacy.md \
    '<!-- craft:model-enum -->' '<!-- craft:model-enum2 -->'

  # Legitimate edits that must NOT trip the harness.
  # A repeated value does not change the SET, so it is legitimate. The round-2 version of
  # assert_nothing_lost compared against the de-duplicated count and blamed the normalizer.
  # --- review round 9: the tables' own columns, the sections behind the headings, the command
  # --- files read raw, and the one-colon rule on a registered second spawn site (F1-F4).

  # F1: effort and cacheTtl were literals in this file, so the TABLE side was unbound in both
  # directions. These three mutate only model-defaults.md; the agent files stay as shipped.
  selftest_case "the effort cell is undecided while the agent declares one" \
    model-defaults.md '| `slice-builder` | execute | high |' '| `slice-builder` | execute | — |'

  selftest_case "an effort is decided in the table and not in the agent" \
    model-defaults.md '| `code-reviewer` | deep-reason | — |' '| `code-reviewer` | deep-reason | xhigh |'

  selftest_case "the Cache TTL rule moves an agent to the other bullet" \
    model-defaults.md 'inside a tool call. `slice-builder`, E2E verification.' \
                      'inside a tool call. `code-reviewer`, E2E verification.'

  # F2: a heading check binds a NAME. Both of these keep the heading and break what it opens.
  selftest_case "the spawn declaration is moved out of the section its heading opens" \
    model-defaults.md 'bound to the line below, the same way the enum above is bound.

<!-- craft:spawn-enum canonical -->' 'bound to the line below, the same way the enum above is bound.

## Interlude

<!-- craft:spawn-enum canonical -->'

  selftest_case "the spawn procedure no longer states a step its pointers send readers for" \
    model-defaults.md 'Take the set' 'Take the values'

  # F3: the two checks that read the COMMAND files used to read them raw, so a fenced example
  # could stand in for the real sentence — B-R7-1 and R5-1 reinstated with the run green.
  selftest_case "the unreachable-declaration fallback survives only inside a fence" \
    commands/review.md 'Could not read model-defaults.md' 'REDACTED

```text
Could not read model-defaults.md
```
'

  selftest_case "a spawn site pointer survives only inside a fence" \
    commands/review.md 'What a spawn site must do' 'the reviewer default

```text
What a spawn site must do
```
'

  # F4: the one-colon rule reached the spawn declaration in round 8 and not the copy loop. With
  # one binding site that was invisible; this registers a second one, exactly as a maintainer
  # would, and drifts its visible list behind a second colon.
  # Appended at the END of the template on purpose: inserting it above the existing enum marker
  # split that marker from its value line, so the case went red on the ENUM copy before the colon
  # rule was ever reached — red for a reason other than its label, which is the R8-9 defect this
  # harness exists to catch. Caught while writing the fixture (review round 9).
  selftest_case2 "a registered second spawn site drifts behind a second colon" \
    templates/profiles/balanced.md '- code-reviewer: sonnet   # faster review for low-stakes slices' \
'- code-reviewer: sonnet   # faster review for low-stakes slices
-->

<!-- craft:spawn-enum -->
Spawn-reachable values: `opus`, `sonnet` — full set in model-defaults.md: `opus`, `sonnet`, `haiku`, `fable`

<!-- keep the trailing comment closed:' \
    scripts/test-model-enum.sh 'SPAWN_BOUND_FILES=(' 'SPAWN_BOUND_FILES=(
  "templates/profiles/balanced.md:1"' 1/3

  # --- slice-047 sub-task 8: the five holes slice-046 disclosed and routed here ---------------
  # Each was reproduced GREEN in slice-046 and is a fixture now. Labels name the MUTATION, not a
  # single check: several checks may fire, and the run compares exit status.

  # R4-6 — the one-colon rule ran on copies only. The declaration is the one line no copy can
  # catch drifting, because every copy is compared against IT.
  selftest_case "a second colon on the canonical value line hides what precedes it (R4-6)" \
    model-defaults.md "Allowed values: $(vlist "$CANON_COUNT")" \
                      "Allowed values: $(vlist $((CANON_COUNT - 2))) — full set: $(vlist "$CANON_COUNT")"

  # R4-7a — a separator variant. `craft:model_enum` matched neither MARKER_RE nor the old
  # NEARMISS_RE, so it was compared by nothing and reported by nothing.
  selftest_case_newfile "a separator-variant marker looks bound and is not (R4-7)" \
    templates/profiles/balanced.md templates/profiles/decoy-sep.md \
    '<!-- craft:model-enum -->' '<!-- craft:model_enum -->'

  # R4-7b — a real marker followed by a second comment on the same line. MARKER_RE requires the
  # line to END at the first `-->`, and the old near-miss regex could not span the second one.
  selftest_case_newfile "a marker trailed by a second comment looks bound and is not (R4-7)" \
    templates/profiles/balanced.md templates/profiles/decoy-trail.md \
    '<!-- craft:model-enum -->' '<!-- craft:model-enum --> <!-- keep -->'

  # R4-8 — /craft:prime step 4b resolves the alias set BY THIS HEADING NAME.
  # Anchored with its surrounding newlines: the bare string occurs five times in this file (the
  # heading plus four prose references), and a fixture that depends on the heading happening to
  # come first is one insertion away from silently renaming prose instead (R4-2).
  selftest_case "the heading prime resolves the alias set by is renamed (R4-8)" \
    model-defaults.md "$(printf '\n## Allowed Model Values\n')" "$(printf '\n## Model Values (allowed)\n')"

  # R4-9 — check 3 read the raw file, so a marker parked in a fenced example counted as a prose
  # mention and the prose/binding distinction reported itself as tested when it was not.
  # The mutation must remove the file's ONE real prose mention and put a prose-style mention
  # inside a fence. Attempt 1 changed a sentence that does not contain the marker at all, so the
  # counts never moved and the case was a silent pass with the fix applied too.
  #   raw      → prose 3 > binding 2  → passes (the distinction reads as tested, and is not)
  #   defenced → prose 2 = binding 2  → fails  (correctly caught)
  selftest_case "the only prose mention of the marker is one parked in a fence (R4-9)" \
    model-defaults.md 'A file that names these values carries the marker `craft:model-enum`, as an HTML comment' \
'A file that names these values carries the marker, as an HTML comment

```
A file that names these values carries the marker `craft:model-enum`, as an HTML comment
```
'

  # The stray-tail diagnosis: caught before, but reported at the copies. This pins that the
  # canonical line itself is named. (I first declared 1/2 here by assuming the Format-section copy
  # matched the same prefix; it does not, and subst said so — which is R4-2's machinery earning
  # its place on its first day.)
  selftest_case "a stray word between the colon and the first value on the canonical line" \
    model-defaults.md "Allowed values: $(vlist 1)" "Allowed values: probably $(vlist 1)"

  # R4-3 — the checks that read this file's tables and rules read it raw, so a tier row parked in
  # a fenced example was read as a real row. Here the real row is deleted and a correct-looking one
  # is parked in a fence: the old readers found it and reported the table as complete.
  selftest_case "a tier row deleted and a decoy parked in a fence (R4-3)" \
    model-defaults.md '| `code-reviewer` | deep-reason | — |' \
'
```
| `code-reviewer` | deep-reason | — |
```
'

  # R4-3, second half — the `fable` rule is one of the "rules" that check read raw. Real rule
  # deleted, a correct-looking one parked in a fence: the old reader found it and reported the rule
  # as present. (Test Strategy leg 3, fourth replay.)
  selftest_case "the fable rule deleted and a decoy parked in a fence (R4-3)" \
    model-defaults.md 'human-chosen only' \
'REDACTED

```
human-chosen only
```
'

  # R4-10 has NO fixture, deliberately (B2, slice-047). The fix reads the tier set from the
  # Capability Tiers table instead of typing it out three times. With exactly two tiers that is
  # **observationally identical** to the hardcoded alternation: a role retiered to a tier the table
  # does not define fails as "no Role → tier row assigns a tier" either way, via a check older than
  # the fix. Reverting the fix leaves the whole run green, which is what a fixture here would have
  # to contradict and cannot. The fix removes an unbound copy — this harness's own copy of a set,
  # in a slice whose thesis is "declared once" — and pays off when the table grows. Stated in
  # model-defaults.md rather than asserted by a case that would test something else.

  # --- slice-047: the reproductions slice-046 disclosed and could not close ------------------
  # Each of these stayed GREEN while the tree was wrong, which is the definition of a silent
  # pass. They are fixtures now because example-regions.sh decides what an example is, and it
  # parses the constructs instead of counting them.

  # R4-1 — a NESTED fence. The old parity toggle flipped on the outer ```` and back on the inner
  # ```, so the decoy inside read as content and stood in for the marker that had been deleted,
  # while the visible list drifted to a shorter set. The plan's Effect section names the exact
  # before/after: "1 binding site(s), as declared" → "0 binding site(s), expected 1".
  selftest_case "a nested fence hides the real marker while a decoy stands in for it (R4-1)" \
    templates/profiles/careful.md \
"> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")" \
"> Allowed values: $(vlist $((CANON_COUNT - 2)))
>
> \`\`\`\`
> \`\`\`
> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")
> \`\`\`
> \`\`\`\`"

  # R7-3a — an HTML comment is not a Markdown fence, so a decoy parked in a template's own
  # "Examples (uncomment to use)" block was a binding site to every fence-based check. All four
  # profile templates carry such a block a few lines below their marker.
  selftest_case "a decoy in the template's own Examples comment block stands in (R7-3a)" \
    templates/profiles/careful.md \
"> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")" \
"> Allowed values: $(vlist $((CANON_COUNT - 2)))

<!-- Examples (uncomment to use):
> <!-- craft:model-enum -->
> Allowed values: $(vlist "$CANON_COUNT")
-->"

  # R7-3b — docs/index.html is not Markdown at all, so a Markdown fence parser can never cover
  # it however good it is. Its examples live in <pre>. defenced() used to run the markdown rules
  # over it; the caller passes html mode for it (mode_for()).
  # The real marker is DELETED and a complete decoy — marker plus an identical value line — is
  # parked inside a <pre>, mirroring R7-3a's shape. A first attempt merely wrapped the real
  # marker in <pre> with no value line after it: that went red under the old toggle too, on
  # "no value list after the marker" rather than on the decoy standing in — red for a reason
  # other than its label, which is the one thing a fixture here must never be (slice-047).
  selftest_case "a decoy inside a <pre> on the docs page stands in (R7-3b)" \
    docs/index.html \
"      <!-- craft:model-enum -->
$(sed -n '1023p' "$ROOT/docs/index.html")" \
"      <pre>
      <!-- craft:model-enum -->
$(sed -n '1023p' "$ROOT/docs/index.html")
      </pre>
$(sed -n '1023p' "$ROOT/docs/index.html")"

  selftest_case_green "a repeated value is not a normalizer bug" \
    model-defaults.md "Allowed values: $(vlist 2)" "Allowed values: $(vlist 1), $(vlist 2)"

  # The other side of the same rule: the mechanism must remain documentable in a code block.
  selftest_case_green "a fenced example is not a binding site" \
    model-defaults.md '### How a copy is bound' '### How a copy is bound

```markdown
<!-- craft:model-enum -->
Allowed values: `nonesuch`, `bogus`
```'

  selftest_case_green "an inline marker in prose is ignored" \
    model-defaults.md '### How a copy is bound' '### How a copy is bound

Example of the mechanism, written inline <!-- craft:model-enum --> in a sentence:
Allowed values: `nonesuch`, `bogus`'
fi

# --- result ---------------------------------------------------------------------------

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'RESULT: GREEN (%d checks)\n' "$CHECKS"
  exit 0
fi
printf 'RESULT: RED (%d/%d checks failed)\n' "$FAILED" "$CHECKS"
exit 1
