#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# test-stack-packs.sh — the stack-pack contract (D43, slice-083) and its self-test.
#
# THE CONTRACT — defined here, once. templates/stack-pack/ is a bound copy: it is checked against
# these same rules (placeholders `{{…}}` stand in for values), so it cannot drift from them.
#
# A stack-pack is a directory skills/stack-<…>/ holding SKILL.md (a directory without SKILL.md is no
# skill — test-docs-site.sh counts the same way). Every pack must satisfy:
#
#   C1  frontmatter    `name:` equals the directory name; `description:` is not empty;
#                      `disable-model-invocation: true` (D27: a pack is loaded by declaration, never
#                      by Claude's description matching).
#   C2  sections       SKILL.md carries these `## ` sections, in this order (others may sit between):
#                      Stack · Reference Files · Build Order · Anti-Patterns · Sources.
#                      An optional `## Provisioning` is read by /craft:checkout.
#   C3  references     `## Reference Files` names its files as `references/<file>.md`; at least one;
#                      each named file exists, and every file in references/ is named (both directions).
#                      Each reference file opens with a `# ` heading. Hidden files (`.DS_Store`) are not
#                      reference files; a subdirectory in references/ is a breach.
#   C4  size budget    SKILL.md ≤ 120 lines; each reference file ≤ 300 lines. A pack is loaded into the
#                      context of every code-near phase — it must stay a pack, not a manual.
#   C5  sources        `## Sources` opens with `> As of: <YYYY-MM-DD> · Basis: research|extraction`;
#                      the date is a real date and not in the future; at least one `- ` source line;
#                      with Basis research, every source line carries an https:// URL. (D43: training
#                      knowledge is never ground truth — a reader must see what a pack rests on and
#                      how old it is.)
#   C6  no placeholder a pack (not the template) keeps no `{{…}}` placeholder in SKILL.md or a reference
#                      file — the template's placeholders are filled in, never shipped.
#
# The /craft:onboard detection table (commands/onboard.md → ### Detection table):
#
#   D1  coverage       every shipped pack has a row naming it as the candidate.
#   D2  precedence     a more specific signal is checked before the one it builds on — the pairs in
#                      PRECEDENCE below; both rows of a pair must exist.
#   D3  fallback       the last row names `none`, and the `stack-bash` row sits directly above it — its
#                      signal ("no manifest above") only holds below every manifest row.
#
# Lines inside an example (fenced block, multi-line HTML comment) are not content: the one answer to
# that is scripts/example-regions.sh, never a parity toggle here.
#
# Run it directly — the contract on this tree, then the self-test (mutated copies that must go red,
# legitimate edits that must stay green, a positive control):
#
#   bash scripts/test-stack-packs.sh
#   bash scripts/test-stack-packs.sh --check <root>    # the contract only, on <root>; exit 0 | 1
#
# It writes nothing outside its own mktemp directory (removed on exit). Needs bash and python3.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
REGIONS="$SCRIPT_DIR/example-regions.sh"
[[ -f "$REGIONS" ]] || { echo "FATAL: not found: $REGIONS" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 not found" >&2; exit 2; }

# check <root> — the contract on <root>; prints PASS / FAIL lines, exit 0 when all pass.
check() {
  python3 - "$1" "$REGIONS" <<'PY'
import datetime, os, re, subprocess, sys

root, regions = sys.argv[1], sys.argv[2]
REQUIRED = ["Stack", "Reference Files", "Build Order", "Anti-Patterns", "Sources"]
SKILL_MAX, REF_MAX = 120, 300
PRECEDENCE = [
    ("stack-php-shopware6", "stack-php-symfony"),
    ("stack-php-api-platform", "stack-php-symfony"),
    ("stack-php-laravel", "stack-php-api-platform"),
    ("stack-php-symfony", "stack-php"),
    ("stack-php-shopware5", "stack-php"),
    ("stack-php-laravel", "stack-php"),
    ("stack-bash", "none"),
]
PH = re.compile(r"\{\{[^}]*\}\}")
fails = 0

def ok(m): print(f"  PASS  {m}")
def bad(m):
    global fails
    fails += 1
    print(f"  FAIL  {m}")

def content(path):
    """The file with example lines blanked (line count kept) — example-regions.sh decides."""
    r = subprocess.run(["bash", regions, "blank", "markdown", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"example-regions.sh failed on {path}: {r.stderr.strip()}")
    return r.stdout.split("\n")

def nlines(path):
    with open(path, encoding="utf-8") as f:
        return len(f.read().rstrip("\n").split("\n"))

def check_pack(label, d, skill, template):
    sfx = ".template" if template else ""
    path = os.path.join(d, skill)
    lines = content(path)
    # C6 — no placeholder left (the template is the one place placeholders belong)
    def no_placeholder(p, ls):
        if template:
            return
        hits = [(k + 1, m.group(0)) for k, l in enumerate(ls) for m in [PH.search(l)] if m]
        if hits:
            bad(f"{label}: C6 placeholder left in {os.path.relpath(p, d)}:{hits[0][0]}: {hits[0][1]}" + (f" (+{len(hits) - 1} more)" if len(hits) > 1 else ""))
    no_placeholder(path, lines)
    # C1 — frontmatter
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        bad(f"{label}: C1 no frontmatter block"); return
    end = lines.index("---", 1)
    fm = {}
    for l in lines[1:end]:
        k, _, v = l.partition(":")
        fm[k.strip()] = v.strip()
    name, want = fm.get("name", ""), os.path.basename(d)
    if (PH.fullmatch(name) if template else name == want):
        ok(f"{label}: C1 name")
    else:
        bad(f"{label}: C1 name '{name}' does not match the directory '{want}'")
    (ok if fm.get("description") else bad)(f"{label}: C1 description" + ("" if fm.get("description") else " is empty"))
    dmi = fm.get("disable-model-invocation")
    (ok if dmi == "true" else bad)(f"{label}: C1 disable-model-invocation" + ("" if dmi == "true" else f" is '{dmi}', must be true"))
    # C2 — sections in order
    heads = [(i, l[3:].strip()) for i, l in enumerate(lines) if l.startswith("## ")]
    names = [h for _, h in heads]
    missing = [s for s in REQUIRED if s not in names]
    if missing:
        bad(f"{label}: C2 missing section(s): {', '.join(missing)}")
    else:
        order = [names.index(s) for s in REQUIRED]
        (ok if order == sorted(order) else bad)(f"{label}: C2 sections" + ("" if order == sorted(order) else " out of order — required: " + " · ".join(REQUIRED)))
    def section(title):
        for k, (i, h) in enumerate(heads):
            if h == title:
                stop = heads[k + 1][0] if k + 1 < len(heads) else len(lines)
                return lines[i + 1:stop]
        return None
    # C3 — reference files, both directions
    refsec = section("Reference Files")
    if refsec is not None:
        named = sorted(set(re.findall(r"`references/([^`/]+\.md)`", "\n".join(refsec))))
        rdir = os.path.join(d, "references")
        entries = [f for f in (os.listdir(rdir) if os.path.isdir(rdir) else []) if not f.startswith(".")]
        for f in entries:
            if os.path.isdir(os.path.join(rdir, f)):
                bad(f"{label}: C3 references/{f} is a directory — a reference is a file")
        present = sorted(f[: -len(sfx)] if sfx and f.endswith(sfx) else f
                         for f in entries if os.path.isfile(os.path.join(rdir, f)))
        if not named:
            bad(f"{label}: C3 ## Reference Files names no references/<file>.md")
        for f in named:
            if f not in present:
                bad(f"{label}: C3 references/{f} is listed but missing")
        for f in present:
            if f not in named:
                bad(f"{label}: C3 references/{f} exists but is not listed")
        if named and named == present:
            ok(f"{label}: C3 references ({len(named)}) listed and present")
        for f in present:
            p = os.path.join(rdir, f + sfx)
            rl = content(p)
            no_placeholder(p, rl)
            first = next((l for l in rl if l.strip()), "")
            (ok if first.startswith("# ") else bad)(f"{label}: C3 references/{f} " + ("opens with a heading" if first.startswith("# ") else "does not open with a '# ' heading"))
            n = nlines(p)
            (ok if n <= REF_MAX else bad)(f"{label}: C4 references/{f} {n} lines" + ("" if n <= REF_MAX else f" — over the budget of {REF_MAX}"))
    # C4 — SKILL.md budget
    n = nlines(path)
    (ok if n <= SKILL_MAX else bad)(f"{label}: C4 {skill} {n} lines" + ("" if n <= SKILL_MAX else f" — over the budget of {SKILL_MAX}"))
    # C5 — sources
    src = section("Sources")
    if src is not None:
        body = [l for l in src if l.strip()]
        head = body[0] if body else ""
        m = re.fullmatch(r"> As of: (\S+) · Basis: (\S+)", head.strip())
        if not m:
            bad(f"{label}: C5 ## Sources does not open with '> As of: <YYYY-MM-DD> · Basis: research|extraction'")
        else:
            date, basis = m.group(1), m.group(2)
            if template and PH.fullmatch(date):
                ok(f"{label}: C5 As of (placeholder)")
            else:
                try:
                    dd = datetime.date.fromisoformat(date)
                    (ok if dd <= datetime.date.today() else bad)(f"{label}: C5 As of {date}" + ("" if dd <= datetime.date.today() else " is in the future"))
                except ValueError:
                    bad(f"{label}: C5 As of '{date}' is not a YYYY-MM-DD date")
            if not (template and PH.fullmatch(basis)) and basis not in ("research", "extraction"):
                bad(f"{label}: C5 Basis '{basis}' — allowed: research, extraction")
            srcs = [l for l in body[1:] if l.startswith("- ")]
            if not srcs:
                bad(f"{label}: C5 no '- ' source line")
            else:
                ok(f"{label}: C5 {len(srcs)} source line(s)")
                if basis == "research":
                    for l in srcs:
                        if "https://" not in l:
                            bad(f"{label}: C5 research source without an https:// URL: {l[:70]}")

# packs
sk = os.path.join(root, "skills")
packs = sorted(d for d in os.listdir(sk) if d.startswith("stack-") and os.path.isfile(os.path.join(sk, d, "SKILL.md")))
if not packs:
    bad("no skills/stack-*/SKILL.md found")
for p in packs:
    check_pack(p, os.path.join(sk, p), "SKILL.md", False)
# the template — the bound copy
tpl = os.path.join(root, "templates", "stack-pack")
if os.path.isfile(os.path.join(tpl, "SKILL.md.template")):
    check_pack("templates/stack-pack", tpl, "SKILL.md.template", True)
else:
    bad("templates/stack-pack/SKILL.md.template missing")

# detection table
ob = content(os.path.join(root, "commands", "onboard.md"))
try:
    start = next(i for i, l in enumerate(ob) if l.strip() == "### Detection table")
except StopIteration:
    bad("D0 commands/onboard.md has no '### Detection table'"); start = None
rows = []
if start is not None:
    for l in ob[start + 1:]:
        if l.startswith("#"):
            break
        if l.startswith("|") and not re.fullmatch(r"\|[\s|:-]+\|", l.strip()):
            m = re.search(r"`([^`]+)`\s*\|\s*$", l)
            if m:
                rows.append(m.group(1))
    if not rows:
        bad("D0 the detection table has no rows")
    for p in packs:
        (ok if p in rows else bad)(f"D1 {p} " + ("has a detection row" if p in rows else "has no detection row"))
    for a, b in PRECEDENCE:
        if a not in rows or b not in rows:
            bad(f"D2 precedence {a} before {b}: row missing ({a if a not in rows else b})")
        elif rows.index(a) < rows.index(b):
            ok(f"D2 {a} before {b}")
        else:
            bad(f"D2 precedence broken: {a} must be checked before {b}")
    if "stack-bash" in rows:
        sb = rows.index("stack-bash") == len(rows) - 2
        (ok if sb else bad)("D3 stack-bash sits directly above none" + ("" if sb else " — it does not; its 'no manifest above' signal must come after every manifest row"))
    (ok if rows and rows[-1] == "none" else bad)("D3 the last row is none" + ("" if rows and rows[-1] == "none" else f" — it is '{rows[-1] if rows else '-'}'"))

sys.exit(1 if fails else 0)
PY
}

if [[ "${1:-}" == "--check" ]]; then
  [[ $# -eq 2 && -d "$2" ]] || { echo "usage: ${0##*/} [--check <root>]" >&2; exit 2; }
  check "$2"
  exit $?
fi
[[ $# -eq 0 ]] || { echo "usage: ${0##*/} [--check <root>]" >&2; exit 2; }

PASS=0
FAIL=0
pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "== the contract on this tree"
if check "$REPO"; then pass "this tree satisfies the stack-pack contract"; else fail "this tree breaks the stack-pack contract (lines above)"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fixture — a fresh copy of everything the contract reads, in a directory of its own. It runs in a
# command substitution (a subshell), so a counter would never advance there: mktemp names it instead.
fixture() {
  local f
  f="$(mktemp -d "$TMP/f.XXXXXX")"
  mkdir -p "$f/skills" "$f/templates" "$f/commands"
  cp -R "$REPO"/skills/stack-* "$f/skills/"
  cp -R "$REPO/templates/stack-pack" "$f/templates/"
  cp "$REPO/commands/onboard.md" "$f/commands/"
  printf '%s' "$f"
}

# edit <file> <python expression over s> — rewrite a file in place (s = its text)
edit() {
  python3 - "$1" "$2" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
t = eval(expr, {"s": s})
if t == s:
    sys.exit("edit changed nothing — the fixture is wrong: " + expr)
open(p, "w", encoding="utf-8").write(t)
PY
}

L=skills/stack-php-laravel
# red <name> <expected FAIL text> <file> <python expr> — the mutated copy must fail, naming the breach
red() {
  local name="$1" want="$2" file="$3" expr="$4" f out
  f="$(fixture)"
  if ! edit "$f/$file" "$expr"; then fail "fixture '$name' could not be built"; return; fi
  out="$(check "$f")" && { fail "mutation '$name' stayed green"; return; }
  if grep -q -- "FAIL.*$want" <<<"$out"; then pass "mutation '$name' correctly RED"; else
    fail "mutation '$name' went red, but not with '$want':"; grep FAIL <<<"$out" | head -3; fi
}
# green <name> <setup command> — a legitimate edit that must stay green
green() {
  local name="$1" f
  f="$(fixture)"
  if ! ( cd "$f" && eval "$2" ); then fail "legitimate edit '$name' could not be built"; return; fi
  if check "$f" >/dev/null; then pass "legitimate edit '$name' stays green"; else
    fail "legitimate edit '$name' went red:"; check "$f" | grep FAIL | head -3; fi
}

echo "== positive control"
f="$(fixture)"
if check "$f" >/dev/null; then pass "an unchanged copy is green"; else fail "an unchanged copy is red — the fixture is wrong"; fi

# red_fs <name> <expected FAIL text> <setup command> — a filesystem mutation, run inside the copy
red_fs() {
  local name="$1" want="$2" f out
  f="$(fixture)"
  if ! ( cd "$f" && eval "$3" ); then fail "fixture '$name' could not be built"; return; fi
  out="$(check "$f")" && { fail "mutation '$name' stayed green"; return; }
  if grep -q -- "FAIL.*$want" <<<"$out"; then pass "mutation '$name' correctly RED"; else
    fail "mutation '$name' went red, but not with '$want':"; grep FAIL <<<"$out" | head -3; fi
}

echo "== mutations that must go red"
red "dmi removed"          "disable-model-invocation"   "$L/SKILL.md" 's.replace("disable-model-invocation: true\n", "", 1)'
red "dmi false"            "disable-model-invocation"   "$L/SKILL.md" 's.replace("disable-model-invocation: true", "disable-model-invocation: false", 1)'
red "name mismatch"        "C1 name"                    "$L/SKILL.md" 's.replace("name: stack-php-laravel", "name: stack-php-laravel2", 1)'
red "empty description"    "description is empty"       "$L/SKILL.md" '__import__("re").sub(r"(?m)^description: .*$", "description:", s, count=1)'
red "no Sources section"   "missing section"            "$L/SKILL.md" 's.replace("## Sources", "## Quellen", 1)'
red "Sources only in a fence" "missing section"         "$L/SKILL.md" 's.replace("## Sources", "```\n## Sources\n```", 1)'
red "sections out of order" "out of order"              "$L/SKILL.md" 's.replace("## Build Order", "## Build Order TMP", 1).replace("## Anti-Patterns", "## Build Order", 1).replace("## Build Order TMP", "## Anti-Patterns", 1)'
red "listed file missing"  "listed but missing"         "$L/SKILL.md" 's.replace("`references/test-patterns.md`", "`references/test-patterns.md` and `references/gone.md`", 1)'
red "file not listed"      "not listed"                 "$L/SKILL.md" 's.replace("- `references/test-patterns.md`", "- test patterns", 1)'
red "reference no heading" "does not open with"         "$L/references/test-patterns.md" '"intro line\n\n" + s'
red "SKILL.md over budget" "over the budget of 120"     "$L/SKILL.md" 's + "\n".join("x" for _ in range(130)) + "\n"'
red "reference over budget" "over the budget of 300"    "$L/references/test-patterns.md" 's + "\n".join("x" for _ in range(310)) + "\n"'
red "As of missing"        "does not open with '> As of" "$L/SKILL.md" '__import__("re").sub(r"(?m)^> As of: .*$", "", s, count=1)'
red "As of in the future"  "in the future"              "$L/SKILL.md" '__import__("re").sub(r"(?m)^> As of: \S+", "> As of: 2999-01-01", s, count=1)'
red "As of not a date"     "not a YYYY-MM-DD"           "$L/SKILL.md" '__import__("re").sub(r"(?m)^> As of: \S+", "> As of: 2026-13-45", s, count=1)'
red "Basis unknown"        "allowed: research"          "$L/SKILL.md" '__import__("re").sub(r"Basis: \S+", "Basis: memory", s, count=1)'
red "research without URL" "without an https"           "$L/SKILL.md" '__import__("re").sub(r"Basis: \S+", "Basis: research", s, count=1)'
red "no source line"       "no '- ' source line"        "$L/SKILL.md" 's[: s.index("## Sources")] + "## Sources\n\n" + __import__("re").search(r"(?m)^> As of: .*$", s).group(0) + "\n"'
red "pack without row"     "has no detection row"       "commands/onboard.md" '__import__("re").sub(r"(?m)^\|[^\n]*`stack-php-laravel` \|\n", "", s, count=1)'
# swap(s, a, b) for the detection table: the row naming `a` and the row naming `b` trade places
SWAP='(lambda ls: (lambda i, j: "\n".join(ls[:i] + [ls[j]] + ls[i+1:j] + [ls[i]] + ls[j+1:])))(s.split("\n"))(*sorted(next(k for k, l in enumerate(s.split("\n")) if l.startswith("|") and x in l) for x in ("`stack-php-shopware6`", "`stack-php-symfony`")))'
red "precedence broken"    "precedence broken"          "commands/onboard.md" "$SWAP"
red "none not last"        "D3 the last row is none"    "commands/onboard.md" '__import__("re").sub(r"(?m)^\|[^\n]*`none` \|\n", "", s, count=1)'
red "no detection table"   "no '### Detection table'"   "commands/onboard.md" 's.replace("### Detection table", "### Detection", 1)'
red "placeholder left"     "C6 placeholder left in references/test-patterns.md" "$L/references/test-patterns.md" 's + "\n- {{anti_pattern}}\n"'
red "placeholder in SKILL" "C6 placeholder left in SKILL.md" "$L/SKILL.md" 's.replace("## Anti-Patterns\n", "## Anti-Patterns\n\n- {{anti_pattern}}\n", 1)'
red_fs "references subdir" "is a directory" "mkdir $L/references/extra"
BASH_SWAP="${SWAP//stack-php-shopware6/stack-bash}"
red "bash above go"        "stack-bash sits directly above none" "commands/onboard.md" "${BASH_SWAP//stack-php-symfony/stack-go}"
red "template dmi removed" "templates/stack-pack: C1 disable" "templates/stack-pack/SKILL.md.template" 's.replace("disable-model-invocation: true\n", "", 1)'
red "template no Sources"  "templates/stack-pack: C2 missing" "templates/stack-pack/SKILL.md.template" 's.replace("## Sources", "## Quellen", 1)'
red "template ref missing" "references/absent.md is listed but missing" "templates/stack-pack/SKILL.md.template" 's.replace("`references/test-patterns.md` —", "`references/test-patterns.md`, `references/absent.md` —", 1)'

echo "== legitimate edits that must stay green"
# a second pack: a copy of the Laravel pack renamed stack-zz-demo, with its own row above `stack-bash`
add_demo_pack() {
  cp -R "$L" skills/stack-zz-demo
  python3 - <<'PY'
import re
p = "skills/stack-zz-demo/SKILL.md"
s = open(p).read()
open(p, "w").write(s.replace("name: stack-php-laravel", "name: stack-zz-demo", 1))
p = "commands/onboard.md"
s = open(p).read()
open(p, "w").write(re.sub(r"(?m)^(\|[^\n]*`stack-bash` \|)$", "| a demo signal | `stack-zz-demo` |\n\\1", s, count=1))
PY
}
green "an optional ## Provisioning section" "printf '\n## Provisioning\n\n- composer install\n' >> $L/SKILL.md"
green "a second pack with its own row" "add_demo_pack"
green "a Finder .DS_Store in references/" "printf 'x' > $L/references/.DS_Store"

echo
echo "  $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
