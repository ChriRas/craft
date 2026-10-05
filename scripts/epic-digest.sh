#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# epic-digest.sh — the autopilot's epic-end digest, generated, never written from memory (slice-057, B22)
#
# WHY ------------------------------------------------------------------------
# At an autopilot run's end (/craft:execute → a5) the human reads one block and decides the merge.
# slice-056's probes 3 and 4 showed the master writing that block from context: the Phase-7 candidates
# paraphrased, the UX demo script retold instead of shown, a verification date invented (`2021-…`) —
# and a prescribed `grep` skipped, so prose does not bind it (rules.md → "What an agent must carry or
# read out verbatim is checked by command"). This helper prints the whole block; a5 only relays it.
#
# WHAT -----------------------------------------------------------------------
#   epic-digest.sh <epic-plan>
#
# Run from the project root (or set CLAUDE_PROJECT_DIR); <epic-plan> is relative to it. The epic's
# slices are its decomposition entries in their order, read through `epic-entry-link.sh resolve`;
# every one must be landed (no plan, exactly one archive under .claude/project/slices/). Example
# regions (fenced blocks, multi-line HTML comments) are content of no section: headings, follow-ups
# and candidates inside them are not read — scripts/example-regions.sh decides what is one. CRLF
# input is read as LF; the output has LF line ends.
#
# Output (stdout, exit 0) — this block, and nothing else:
#
#   ✓ Autopilot — <epic-id> complete: <M> slices on <epic-id>-<epic-slug>
#      <slice-id> — <first sentence of the archive's ## What>
#         follow-up: <a ## Follow-ups bullet>               one per bullet, in order
#         refactor candidate: <the line, prefix dropped>    one per candidate line, in order
#      …                                                    one entry per slice, in decomposition order
#      UX demo script — walk it before you answer (the epic plan's ## UX Demo Script):
#         <the section, from its first ### line to its end, each line as written>
#
# - <epic-slug>: the epic plan's `> Epic-Slug:` — the branch is `<epic-id>-<epic-slug>` (a0 item 3).
# - first sentence: the first paragraph of `## What`, its lines joined by one space, cut after the
#   first `.`, `!` or `?` that is followed by whitespace or the paragraph's end and does not sit inside
#   a `code span`; without one, the whole paragraph. Known limit: an abbreviation (`e.g. `) ends it.
# - follow-up: a `- ` bullet at column 0 of `## Follow-ups`; an indented line right below it continues
#   it (joined by one space); a bullet reading `(none)` is no follow-up.
# - refactor candidate: a line anywhere in the archive that starts with
#   `- **Refactor candidate (autopilot, not applied):**` — the form /craft:refactor → Subagent Mode
#   writes; a mere mention of the prefix elsewhere on a line is not one. The no-candidate line
#   (`- **Phase 7 (autopilot): no refactor candidate**`) lists nothing.
# - the UX demo script: lines are printed indented by six spaces, an empty line stays empty; the
#   template's note and placeholder above the first `### ` block are not printed, nor are trailing
#   empty lines. Removing the indent gives the section's lines byte-equal (CR dropped).
#
# Errors — `ERROR=<reason>` on stderr, a non-zero exit, and NOTHING on stdout (never a partial digest):
#   2  usage
#   3  project_dir_unreachable
#   4  epic_plan_unreadable · epic_frontmatter:Epic-ID · epic_frontmatter:Epic-Slug · helper_missing:<name>
#      · tmp_unwritable
#   5  resolve_failed · no_entries · not_landed:<slice-id or ->:<state> · unresolved
#   6  archive_missing:<slice-id> · archive_ambiguous:<slice-id> · what_missing:<slice-id>
#      (archive_missing is a race guard only: a slice whose archive is gone reads not_landed:<id>:missing
#      first, because epic-entry-link.sh decides "landed" by the same glob)
#   7  ux_demo_script_missing · ux_demo_script_empty
#
# Read-only: it writes nothing but its own temp files (removed on exit). The contract is
# scripts/test-epic-digest.sh, written before this file.

set -uo pipefail

die() { echo "ERROR=$2" >&2; exit "$1"; }

[[ $# -eq 1 && -n "$1" ]] || die 2 "usage"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$SCRIPT_DIR/epic-entry-link.sh"
REGIONS="$SCRIPT_DIR/example-regions.sh"
[[ -f "$LINK" ]] || die 4 "helper_missing:epic-entry-link.sh"
[[ -f "$REGIONS" ]] || die 4 "helper_missing:example-regions.sh"
command -v python3 >/dev/null 2>&1 || die 4 "helper_missing:python3"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" 2>/dev/null || die 3 "project_dir_unreachable"

EPIC="$1"
[[ -f "$EPIC" && -r "$EPIC" ]] || die 4 "epic_plan_unreadable"

resolved="$(CLAUDE_PROJECT_DIR="$PROJECT" bash "$LINK" resolve "$EPIC" 2>/dev/null)" || die 5 "resolve_failed"
grep -q '^ENTRY_COUNT=' <<<"$resolved" || die 5 "resolve_failed"
[[ "$(sed -n 's/^ENTRY_COUNT=//p' <<<"$resolved")" != "0" ]] || die 5 "no_entries"

TMP="$(mktemp -d)" || die 4 "tmp_unwritable"
trap 'rm -rf "$TMP"' EXIT

bash "$REGIONS" blank markdown "$EPIC" > "$TMP/epic.blank" 2>/dev/null || die 4 "epic_plan_unreadable"

# One "<slice-id> <archive> <blanked archive>" line per entry, in decomposition order.
args=()
while IFS= read -r line; do
  [[ "$line" == SLICE=* ]] || continue
  id="$(sed -n 's/^SLICE=\([^ ]*\) .*/\1/p' <<<"$line")"
  state="$(sed -n 's/.* STATE=\([^ ]*\) .*/\1/p' <<<"$line")"
  [[ "$state" == "landed" ]] || die 5 "not_landed:$id:$state"
  shopt -s nullglob
  archives=(".claude/project/slices/$id"-*.md)
  shopt -u nullglob
  [[ ${#archives[@]} -gt 0 ]] || die 6 "archive_missing:$id"
  [[ ${#archives[@]} -eq 1 ]] || die 6 "archive_ambiguous:$id"
  bash "$REGIONS" blank markdown "${archives[0]}" > "$TMP/$id.blank" 2>/dev/null || die 6 "archive_missing:$id"
  args+=("$id" "${archives[0]}" "$TMP/$id.blank")
done <<<"$resolved"
grep -q '^RESULT=ok$' <<<"$resolved" || die 5 "unresolved"

python3 - "$EPIC" "$TMP/epic.blank" "${args[@]}" <<'PY'
import re, sys

def fail(code, reason):
    sys.stderr.write("ERROR=%s\n" % reason)
    sys.exit(code)

def lines(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    if out and out[-1] == "":
        out.pop()
    return out

HEADING = re.compile(r"^#{1,2}\s")

def section(blank, name):
    """(start, end) line indices of a `## <name>` section's body, found in the blanked copy."""
    for i, l in enumerate(blank):
        if l.rstrip() == "## " + name:
            end = len(blank)
            for j in range(i + 1, len(blank)):
                if HEADING.match(blank[j]):
                    end = j
                    break
            return i + 1, end
    return None

def frontmatter(blank, key):
    for l in blank:
        if l.startswith("## "):
            break
        m = re.match(r"^>\s*" + re.escape(key) + r":\s*(\S+)", l)
        if m:
            return m.group(1)
    return None

def first_sentence(par):
    in_code = False
    for k, ch in enumerate(par):
        if ch == "`":
            in_code = not in_code
        elif ch in ".!?" and not in_code and (k + 1 == len(par) or par[k + 1].isspace()):
            return par[: k + 1]
    return par

epic, epic_blank_path = sys.argv[1], sys.argv[2]
rest = sys.argv[3:]
epic_lines, epic_blank = lines(epic), lines(epic_blank_path)

epic_id = frontmatter(epic_blank, "Epic-ID")
if not epic_id:
    fail(4, "epic_frontmatter:Epic-ID")
slug = frontmatter(epic_blank, "Epic-Slug")
if not slug:
    fail(4, "epic_frontmatter:Epic-Slug")

CAND = re.compile(r"^- \*\*Refactor candidate \(autopilot, not applied\):\*\*\s?(.*)$")
out = []
slices = [rest[i:i + 3] for i in range(0, len(rest), 3)]
out.append("✓ Autopilot — %s complete: %d slices on %s-%s" % (epic_id, len(slices), epic_id, slug))

for sid, _archive, blank_path in slices:
    blank = lines(blank_path)
    what = section(blank, "What")
    if what is None:
        fail(6, "what_missing:" + sid)
    par = []
    for l in blank[what[0]:what[1]]:
        if l.strip() == "":
            if par:
                break
            continue
        par.append(l.strip())
    if not par:
        fail(6, "what_missing:" + sid)
    out.append("   %s — %s" % (sid, first_sentence(" ".join(par))))

    fu = section(blank, "Follow-ups")
    if fu is not None:
        bullets, cur = [], None
        for l in blank[fu[0]:fu[1]]:
            if l.startswith("- "):
                if cur is not None:
                    bullets.append(cur)
                cur = l[2:].strip()
            elif cur is not None and l[:1] in (" ", "\t") and l.strip():
                cur += " " + l.strip()
            else:
                if cur is not None:
                    bullets.append(cur)
                cur = None
        if cur is not None:
            bullets.append(cur)
        for b in bullets:
            if b != "(none)":
                out.append("      follow-up: " + b)

    for l in blank:
        m = CAND.match(l)
        if m:
            out.append("      refactor candidate: " + m.group(1).rstrip())

ux = section(epic_blank, "UX Demo Script")
if ux is None:
    fail(7, "ux_demo_script_missing")
first = next((i for i in range(ux[0], ux[1]) if epic_blank[i].startswith("### ")), None)
if first is None:
    fail(7, "ux_demo_script_empty")
demo = epic_lines[first:ux[1]]
while demo and demo[-1].strip() == "":
    demo.pop()
out.append("   UX demo script — walk it before you answer (the epic plan's ## UX Demo Script):")
for l in demo:
    out.append("      " + l if l != "" else "")

sys.stdout.write("\n".join(out) + "\n")
PY
