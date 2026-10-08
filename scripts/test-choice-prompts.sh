#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-choice-prompts.sh — binds the human-choice sites of CRAFT's command prose to the click rule (slice-076, D40 amended)
#
# WHY: human test T2 (2026-10-08) ran a whole phase loop with ZERO AskUserQuestion calls. Every site only POINTED at
# the convention in skills/workflow/SKILL.md -> Choice prompts, and no session ever read the target. So each
# human-choice site now names the tool itself, in one sentence on a line marked `<!-- craft:choice -->`, and this
# harness binds those sentences (rules.md: a copy that cannot go is bound, an unbound one is the violation).
#
# THE CONTRACT (this header is it; the case table below was written before the sites were marked):
#   Scope   commands/*.md and skills/debug/SKILL.md (the surface /craft:test [B] enters). Markers are read through
#           scripts/example-regions.sh `blank markdown`, so a marker inside a fence or a multi-line comment is no marker.
#   (a)     Every `<!-- craft:choice -->` line names `AskUserQuestion` on that same line.
#   (b)     Every `<!-- craft:choice typed -->` sits in commands/execute.md, in the same BLOCK as a
#           `<!-- craft:cache-guard arm -->` marker, and its own line does not contain `AskUserQuestion`. A block is a
#           run of non-blank lines, cut where a line opens a list item (`N.`, `-`, `*`) at an indent no deeper than the
#           block's first line. Only the marker's own line is read for the tool name: a negated mention elsewhere
#           ("never as an `AskUserQuestion` click") is allowed. The guard section's Arm bullet is the RULE, not a
#           question; it carries no choice marker and this harness neither checks nor edits it.
#   (c)     The number of sites per file, all three kinds (choice / typed / none), is DECLARED below and compared in both
#           directions: a file with markers that the table lacks fails, and so does a count that drifted. The numbers are
#           read off a run (the INFO lines), never derived.
#   (d)     Legend scan — a staleness detector for the commonest unmarked site. Any line, fenced or not, carrying two or
#           more bracketed single capitals (`[W]`, `[Y]` ...), the `(Y / ...)` form, or starting with one while another line
#           within two lines also does (a vertical menu, one letter per line) must lie within WINDOW lines below
#           a choice marker of any kind. A legend that is not asked (an Output Format copy, a mention in prose, a
#           Subagent-Mode note) carries `<!-- craft:choice none -->` above it, and those are counted too. The window
#           lies BELOW the marker: a site's marker sits above its legend.
#   (e)     Convention pins: skills/workflow/SKILL.md -> Choice prompts keeps the cache-guard exception paragraph and
#           names this harness.
#   (f)     Mutation self-tests on temporary copies, each must go red: the tool name removed from a site; a marker
#           removed; an unmarked `[A]/[B]` legend added; a typed marker moved into the next ap step (out of its arm's
#           block, though still in the same run of non-blank lines); `AskUserQuestion` added to a typed marker's line; a
#           count changed. A positive control (the unchanged tree) and one legitimate edit (a typed block that also says
#           "never as an `AskUserQuestion` click" on a line other than the marker's) must stay green.
#
# KNOWN LIMITS (staleness detector, not a security boundary — rules.md): an open question with no legend and no marker is
# caught by nothing but the declared count; prose is not checked, so a marker above a sentence that no longer asks anything
# stays green; the window is a distance, not a proof that the legend belongs to the marker above it.
#
# Run it directly:   bash scripts/test-choice-prompts.sh
# It writes nothing outside its own mktemp directory (removed on exit). Needs awk; no python3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REGIONS="$SCRIPT_DIR/example-regions.sh"

[[ -f "$REGIONS" ]] || { echo "FATAL: not found: $REGIONS" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# --- the declaration: how many sites each file carries, "<file> <choice> <typed> <none>" ---------------------------
WINDOW=30
COUNTS='
commands/abort.md 4 0 0
commands/block.md 6 0 0
commands/build.md 3 0 0
commands/checkout.md 1 0 0
commands/commit.md 12 0 3
commands/continue.md 3 0 0
commands/epic.md 1 0 0
commands/execute.md 2 3 5
commands/handoff.md 2 0 0
commands/intent-update.md 2 0 0
commands/onboard.md 13 0 1
commands/pause.md 2 0 0
commands/plan.md 7 0 0
commands/prime.md 4 0 0
commands/recap.md 3 0 0
commands/refactor.md 3 0 0
commands/release.md 2 0 1
commands/review.md 7 0 0
commands/test.md 3 0 1
commands/unblock.md 4 0 2
commands/upgrade.md 2 0 0
commands/worktree-clean.md 2 0 0
skills/debug/SKILL.md 6 0 0
'

# --- the scan -----------------------------------------------------------------------------------------------------
# scan_file <repo-root> <relative-path>: prints "ERR <text>" lines and one "COUNT <choice> <typed> <none>" line.
scan_file() {
  local root="$1" rel="$2" blank key
  # example-regions.sh takes about a second per file: the blank view is cached by content, so a mutation scan
  # re-reads only the file it changed.
  key="$(cksum < "$root/$rel" | tr ' ' '_')"
  blank="$ROOT/cache.$key"
  if [[ ! -f "$blank" ]]; then
    "${BASH:-bash}" "$REGIONS" blank markdown "$root/$rel" > "$blank.tmp" 2>/dev/null || { echo "ERR $rel: example-regions.sh failed"; echo "COUNT 0 0 0"; return; }
    mv "$blank.tmp" "$blank"
  fi
  awk -v WINDOW="$WINDOW" -v REL="$rel" '
    { sub(/\r$/, "") }
    NR == FNR { blank[FNR] = $0; n = FNR; next }
    { raw[FNR] = $0 }
    END {
      c = 0; t = 0; z = 0
      for (i = 1; i <= n; i++) {
        line = blank[i]
        if (line ~ /(^|[^`])<!-- craft:choice typed -->/) {
          t++; mark[i] = 1; typed[i] = 1
          if (index(line, "AskUserQuestion")) print "ERR " REL ":" i ": a typed marker line names AskUserQuestion (rule b)"
          if (REL != "commands/execute.md") print "ERR " REL ":" i ": a typed marker outside commands/execute.md (rule b)"
        } else if (line ~ /(^|[^`])<!-- craft:choice none -->/) {
          z++; mark[i] = 1
        } else if (line ~ /(^|[^`])<!-- craft:choice -->/) {
          c++; mark[i] = 1
          if (!index(line, "AskUserQuestion")) print "ERR " REL ":" i ": a choice marker line does not name AskUserQuestion (rule a)"
        }
        if (line ~ /(^|[^`])<!-- craft:cache-guard arm -->/) arm[i] = 1
      }
      # blocks over the raw lines (rule b): runs of non-blank lines, cut at a list item no deeper than the first line
      cur = 0; first = 0
      for (i = 1; i <= n; i++) {
        l = raw[i]
        if (l ~ /^[ \t]*$/) { cur = 0; continue }
        match(l, /^[ ]*/); ind = RLENGTH
        item = (l ~ /^[ ]*([0-9]+[.]|[-*])[ ]/)
        if (cur == 0) { nb++; cur = nb; first = ind }
        else if (item && ind <= first) { nb++; cur = nb; first = ind }
        bid[i] = cur
        if (arm[i]) armblock[cur] = 1
      }
      for (i = 1; i <= n; i++) if (typed[i] && !armblock[bid[i]]) print "ERR " REL ":" i ": a typed marker is not in the block of a cache-guard arm marker (rule b)"
      # legends (rule d)
      # a vertical menu: a line that starts with a bracketed capital and has another such line within two lines
      for (i = 1; i <= n; i++) if (raw[i] ~ /^[ >]*\[[A-Z]\]( |$)/) vstart[i] = 1
      last = 0
      for (i = 1; i <= n; i++) {
        if (mark[i]) last = i
        tmp = raw[i]; k = gsub(/\[[A-Z]\]/, "&", tmp)
        vert = vstart[i] && (vstart[i-1] || vstart[i+1] || vstart[i-2] || vstart[i+2])
        if (k >= 2 || vert || raw[i] ~ /\([Yy] ?\/ ?[A-Za-z]/) {
          if (last == 0 || i - last > WINDOW) print "ERR " REL ":" i ": a legend line is not within " WINDOW " lines below a choice marker (rule d)"
        }
      }
      print "COUNT " c " " t " " z
    }
  ' "$blank" "$root/$rel"
}

# scan_repo <repo-root>: ERR lines on stdout, then INFO lines "INFO <file> <c> <t> <z>".
scan_repo() {
  local root="$1" rel out line declared c t z dc dt dz counted
  local -a files=()
  if [[ $# -gt 1 ]]; then
    shift; files=("$@")
  else
    for rel in "$root"/commands/*.md; do files+=("commands/${rel##*/}"); done
    files+=("skills/debug/SKILL.md")
  fi
  for rel in "${files[@]}"; do
    [[ -f "$root/$rel" ]] || { echo "ERR $rel: not found"; continue; }
    out="$(scan_file "$root" "$rel")"
    counted=""
    while IFS= read -r line; do
      case "$line" in
        ERR*) echo "$line" ;;
        COUNT*) read -r _ c t z <<< "$line"; counted="$c $t $z"; echo "INFO $rel $c $t $z" ;;
      esac
    done <<< "$out"
    # (c) both directions
    declared="$(printf '%s\n' "$COUNTS" | awk -v f="$rel" '$1 == f { print $2 " " $3 " " $4 }')"
    [[ -n "$declared" ]] || declared="0 0 0"
    [[ "$counted" == "$declared" ]] || echo "ERR $rel: markers (choice typed none) are '$counted', declared '$declared' (rule c)"
  done
  local f
  while read -r f dc dt dz; do
    [[ -n "$f" ]] || continue
    [[ -f "$root/$f" ]] || echo "ERR declared count for a file that does not exist: $f"
  done <<< "$COUNTS"
  # (e) the convention pins
  local skill="$root/skills/workflow/SKILL.md" sec
  if [[ -f "$skill" ]]; then
    sec="$(awk '/^#### Choice prompts/ {p=1; print; next} /^####? / {p=0} p {print}' "$skill")"
    case "$sec" in *"A stop that arms the autopilot cache guard stays text"*) ;; *) echo "ERR skills/workflow/SKILL.md: Choice prompts lost the cache-guard exception paragraph (rule e)" ;; esac
    case "$sec" in *"test-choice-prompts.sh"*) ;; *) echo "ERR skills/workflow/SKILL.md: Choice prompts does not name scripts/test-choice-prompts.sh (rule e)" ;; esac
  else
    echo "ERR skills/workflow/SKILL.md: not found"
  fi
}

errs_of() { scan_repo "$@" | grep '^ERR' || true; }

# --- 1. the tree ----------------------------------------------------------------------------------------------------
echo "TREE:"
scan_out="$(scan_repo "$REPO")"
errs="$(printf '%s\n' "$scan_out" | grep '^ERR' || true)"
if [[ -z "$errs" ]]; then
  ok "every site is marked, bound to the tool name and counted as declared"
else
  while IFS= read -r line; do bad "${line#ERR }"; done <<< "$errs"
fi
echo "  counts read off this run (file choice typed none):"
printf '%s\n' "$scan_out" | awk '/^INFO/ && ($3 + $4 + $5 > 0) { printf "    %s %s %s %s\n", $2, $3, $4, $5 }'
printf '%s\n' "$scan_out" | awk '/^INFO/ { c += $3; t += $4; z += $5 } END { printf "    total: choice=%d typed=%d none=%d\n", c, t, z }'

# --- 2. mutation self-tests (each on a temporary copy of the scoped files) -----------------------------------------------
echo "MUTATIONS:"
make_copy() {
  local dst="$1" rel
  rm -rf "$dst"; mkdir -p "$dst/commands" "$dst/skills/debug" "$dst/skills/workflow"
  cp "$REPO"/commands/*.md "$dst/commands/"
  cp "$REPO/skills/debug/SKILL.md" "$dst/skills/debug/SKILL.md"
  cp "$REPO/skills/workflow/SKILL.md" "$dst/skills/workflow/SKILL.md"
}
# expect_red <name> <copy-dir>: the scan of the mutated copy must report at least one error
# The third argument is the rule tag the error must carry, e.g. "(rule b)": a mutation proves the rule it is named for.
expect_red() {
  local name="$1" dir="$2" tag="$3" e hit
  e="$(errs_of "$dir")"
  hit="$(printf '%s\n' "$e" | grep -F -- "$tag" | head -n 1)"
  if [[ -n "$hit" ]]; then ok "RED as it must: $name  [${hit#ERR }]"; else bad "did not go red for $tag: $name ($(printf '%s' "$e" | head -n 1))"; fi
}
expect_green() {
  local name="$1" dir="$2" e
  e="$(errs_of "$dir")"
  if [[ -z "$e" ]]; then ok "green as it must: $name"; else bad "went red but must stay green: $name ($(printf '%s' "$e" | head -n 1))"; fi
}

# a site file with a plain choice marker, and the typed ap block, found in the real tree so the mutations follow the sites
site_file="$(grep -l '<!-- craft:choice -->' "$REPO"/commands/*.md 2>/dev/null | head -n 1)"
site_rel="commands/${site_file##*/}"

if [[ -z "$site_file" ]]; then
  bad "no choice site exists yet — the mutation self-tests have nothing to mutate"
else
  M="$ROOT/m"

  make_copy "$M"
  expect_green "positive control: the unchanged tree" "$M"

  make_copy "$M"
  awk '!d && /<!-- craft:choice -->/ && /AskUserQuestion/ { sub(/AskUserQuestion/, "the question tool"); d = 1 } { print }' "$M/$site_rel" > "$M/x" && mv "$M/x" "$M/$site_rel"
  expect_red "the tool name removed from a site ($site_rel)" "$M" "(rule a)"

  make_copy "$M"
  awk '!d && /<!-- craft:choice -->/ { d = 1; next } { print }' "$M/$site_rel" > "$M/x" && mv "$M/x" "$M/$site_rel"
  expect_red "a marker removed ($site_rel)" "$M" "(rule c)"

  make_copy "$M"
  printf '\nPick one: [A] first   [B] second\n' >> "$M/commands/status.md"
  expect_red "an unmarked [A]/[B] legend added (commands/status.md)" "$M" "(rule d)"

  make_copy "$M"
  printf '\n```\nPick one:\n  [A] first - do this\n  [B] second - do that\n```\n' >> "$M/commands/status.md"
  expect_red "an unmarked vertical [A]/[B] menu added (commands/status.md)" "$M" "(rule d)"

  make_copy "$M"
  awk '
    /<!-- craft:choice typed -->/ && !moved { sub(/ ?<!-- craft:choice typed -->/, ""); print; held = 1; moved = 1; next }
    held && /^1\. / { print; print "   <!-- craft:choice typed -->"; held = 0; next }
    { print }
  ' "$M/commands/execute.md" > "$M/x" && mv "$M/x" "$M/commands/execute.md"
  expect_red "a typed marker moved into the next ap step (out of its arm block)" "$M" "(rule b)"

  make_copy "$M"
  awk '!d && /<!-- craft:choice typed -->/ { sub(/<!-- craft:choice typed -->/, "<!-- craft:choice typed --> AskUserQuestion"); d = 1 } { print }' "$M/commands/execute.md" > "$M/x" && mv "$M/x" "$M/commands/execute.md"
  expect_red "AskUserQuestion added to a typed marker line" "$M" "(rule b)"

  make_copy "$M"
  saved="$COUNTS"
  COUNTS="$(printf '%s\n' "$COUNTS" | awk -v f="$site_rel" '$1 == f { $2 = $2 + 1 } { print }')"
  expect_red "a declared count changed ($site_rel)" "$M" "(rule c)"
  COUNTS="$saved"

  make_copy "$M"
  awk '
    /<!-- craft:choice typed -->/ && !d { print; print "   Never as an `AskUserQuestion` click: the guard sees a prompt, not a click."; d = 1; next }
    { print }
  ' "$M/commands/execute.md" > "$M/x" && mv "$M/x" "$M/commands/execute.md"
  expect_green "a typed block that says \"never as an AskUserQuestion click\" on another line" "$M"
fi

echo
if (( FAIL == 0 )); then
  echo "RESULT: $PASS passed, 0 failed"
else
  echo "RESULT: $PASS passed, $FAIL failed"
fi
[[ $FAIL -eq 0 ]]
