#!/usr/bin/env bash
# test-docs-site.sh — mechanical consistency checks for the documentation site.
#
# The published docs/index.html must stay in sync with the plugin surface and
# keep its structural invariants. This harness asserts what a grep/parser can:
#
#   1. docs/index.html and docs/.nojekyll exist
#   2. HTML tag balance — no mismatched/unclosed tags, no stray closers
#   3. every in-page anchor (#x) has a target id, no duplicate ids
#   4. bilingual parity — count(class="de") == count(class="en")
#   5. EN is the no-JS default: <html lang="en" data-lang="en">
#   6. repo URL present in >= 3 places (nav, hero, footer)
#   7. no <!--NEXT--> build placeholder left behind
#   8. badge line vs reality: version == plugin.json, command/skill/agent/hook
#      counts == directory listings  (the staleness detector)
#   9. every vX.Y.Z occurrence equals the plugin.json version
#  10. light-mode media query and the craft-lang localStorage key exist
#  11. release docs (slice-081): CONTRIBUTING.md and CONTRIBUTING.de.md exist and link
#      each other, README.md links CONTRIBUTING.md, and every list item in CHANGELOG's
#      [Unreleased] section is one line (a GitHub release body generated from it turns a
#      wrapped line into a hard break). A self-test runs check 11 on mutated copies and
#      must see each mutation go red.
#
# Prose content is deliberately NOT checked — prose is not mechanically checkable.
# The editorial contract lives in .claude/skills/docs-site/SKILL.md. Keep green.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HTML="$ROOT/docs/index.html"
FAIL=0

say()  { printf '%s\n' "$*"; }
pass() { say "  ok    $*"; }
fail() { say "  FAIL  $*"; FAIL=1; }

say "docs-site harness — $HTML"

# -- 1. files exist -----------------------------------------------------------
[ -f "$HTML" ]                && pass "docs/index.html exists" || { fail "docs/index.html missing"; echo "RESULT: RED"; exit 1; }
[ -f "$ROOT/docs/.nojekyll" ] && pass "docs/.nojekyll exists"  || fail "docs/.nojekyll missing"

# -- 2..7, 9, 10: parser + regex checks in one python pass --------------------
python3 - "$HTML" "$ROOT" <<'PY' || FAIL=1
import sys, re, json, os
from html.parser import HTMLParser

html_path, root = sys.argv[1], sys.argv[2]
src = open(html_path, encoding='utf-8').read()
rc = 0
def pass_(m): print(f"  ok    {m}")
def fail_(m):
    global rc; rc = 1; print(f"  FAIL  {m}")

VOID = {'meta','link','br','hr','img','input','wbr','source'}
class Checker(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack=[]; self.errors=[]; self.ids=[]; self.hrefs=[]
    def handle_starttag(self, tag, attrs):
        d=dict(attrs)
        if 'id' in d: self.ids.append(d['id'])
        if tag=='a' and d.get('href','').startswith('#'): self.hrefs.append(d['href'][1:])
        if tag not in VOID: self.stack.append((tag,self.getpos()))
    def handle_endtag(self, tag):
        if tag in VOID: return
        if not self.stack: self.errors.append(f"stray </{tag}> at {self.getpos()}"); return
        o,p=self.stack.pop()
        if o!=tag: self.errors.append(f"<{o}> opened {p} closed by </{tag}> at {self.getpos()}")

c=Checker(); c.feed(src); c.close()
if c.errors or c.stack:
    for e in c.errors: fail_(f"tag balance: {e}")
    for t,p in c.stack: fail_(f"unclosed <{t}> opened at {p}")
else:
    pass_("tag balance clean")

missing=[h for h in set(c.hrefs) if h not in c.ids]
dupes=[i for i in set(c.ids) if c.ids.count(i)>1]
fail_(f"anchor targets missing: {sorted(missing)}") if missing else pass_("all in-page anchors resolve")
fail_(f"duplicate ids: {sorted(dupes)}") if dupes else pass_("no duplicate ids")

de=len(re.findall(r'class="de[" ]', src)); en=len(re.findall(r'class="en[" ]', src))
pass_(f"language parity de={de} en={en}") if de==en and de>0 else fail_(f"language parity broken: de={de} en={en}")

m=re.search(r'<html\s+lang="en"\s+data-lang="en">', src)
pass_("EN is the no-JS default") if m else fail_('<html lang="en" data-lang="en"> not found — EN must be the default')

n=src.count('github.com/ChriRas/craft')
pass_(f"repo URL present ({n} occurrences)") if n>=3 else fail_(f"repo URL only {n}x — expected >=3 (nav, hero, footer)")

fail_("<!--NEXT--> build placeholder left in the page") if '<!--NEXT-->' in src else pass_("no build placeholders")

# badge line vs reality
plugin=json.load(open(os.path.join(root,'.claude-plugin','plugin.json')))
version=plugin['version']
counts={
 'commands': len([f for f in os.listdir(os.path.join(root,'commands')) if f.endswith('.md')]),
 # a skill is a directory holding SKILL.md — a stray empty directory (never in git) is no skill (slice-081)
 'skills':   len([d for d in os.listdir(os.path.join(root,'skills')) if os.path.isfile(os.path.join(root,'skills',d,'SKILL.md'))]),
 'agents':   len([f for f in os.listdir(os.path.join(root,'agents')) if f.endswith('.md')]),
 'hooks':    len([f for f in os.listdir(os.path.join(root,'hooks')) if f.endswith('.sh')]),
}
badge=re.search(r'v(\d+\.\d+\.\d+)\s*·\s*MIT\s*·\s*(\d+) commands\s*·\s*(\d+) skills\s*·\s*(\d+) agents\s*·\s*(\d+) hooks', src)
if not badge:
    fail_("badge line not found / format changed (v<ver> · MIT · N commands · N skills · N agents · N hooks)")
else:
    bver,bc,bs,ba,bh = badge.group(1), *(int(badge.group(i)) for i in range(2,6))
    pass_(f"badge version v{bver} == plugin.json") if bver==version else fail_(f"badge v{bver} != plugin.json v{version}")
    for name,got in (('commands',bc),('skills',bs),('agents',ba),('hooks',bh)):
        real=counts[name]
        pass_(f"badge {name}={got} matches tree") if got==real else fail_(f"badge says {got} {name}, tree has {real} — docs are stale")

# The harness table is a staleness surface like the badge, and nothing bound it: slice-047 added
# a harness and the table would have stayed at twelve rows in silence. Bound in BOTH directions —
# a row for a script that does not exist is as wrong as a script with no row.
rows=set(re.findall(r'<td><code>(test-[a-z0-9-]+\.sh)</code>', src))
files={f for f in os.listdir(os.path.join(root,'scripts')) if f.startswith('test-') and f.endswith('.sh')}
if rows==files:
    pass_(f"harness table lists exactly the {len(files)} harnesses in scripts/")
else:
    miss=sorted(files-rows); extra=sorted(rows-files)
    fail_("harness table is stale — "
          + (f"no row for: {miss}. " if miss else "")
          + (f"row for a script that does not exist: {extra}." if extra else ""))

wrong={v for v in re.findall(r'v(\d+\.\d+\.\d+)', src) if v!=version}
pass_(f"all version strings are v{version}") if not wrong else fail_(f"version strings != plugin.json: {sorted(wrong)}")

pass_("light-mode media query present") if 'prefers-color-scheme: light' in src else fail_("prefers-color-scheme light query missing")
pass_("language toggle persistence present") if "localStorage" in src and "craft-lang" in src else fail_("craft-lang localStorage persistence missing")

sys.exit(rc)
PY

# -- 11. release docs ---------------------------------------------------------
# release_docs <root> — prints one ok/FAIL line per check, exits non-zero on any FAIL.
release_docs() {
python3 - "$1" <<'PY'
import sys, os, re
root = sys.argv[1]
rc = 0
def pass_(m): print(f"  ok    {m}")
def fail_(m):
    global rc; rc = 1; print(f"  FAIL  {m}")
def read(name):
    p = os.path.join(root, name)
    return open(p, encoding='utf-8').read() if os.path.isfile(p) else None

en, de, readme, log = (read(n) for n in ('CONTRIBUTING.md', 'CONTRIBUTING.de.md', 'README.md', 'CHANGELOG.md'))
pass_("CONTRIBUTING.md exists") if en is not None else fail_("CONTRIBUTING.md missing")
pass_("CONTRIBUTING.de.md exists") if de is not None else fail_("CONTRIBUTING.de.md missing")
link = lambda text, target: text is not None and re.search(r'\]\(\.?/?' + re.escape(target) + r'(#[^)]*)?\)', text)
pass_("CONTRIBUTING.md links CONTRIBUTING.de.md") if link(en, 'CONTRIBUTING.de.md') else fail_("CONTRIBUTING.md does not link CONTRIBUTING.de.md")
pass_("CONTRIBUTING.de.md links CONTRIBUTING.md") if link(de, 'CONTRIBUTING.md') else fail_("CONTRIBUTING.de.md does not link CONTRIBUTING.md")
pass_("README.md links CONTRIBUTING.md") if link(readme, 'CONTRIBUTING.md') else fail_("README.md does not link CONTRIBUTING.md")

if log is None or '## [Unreleased]' not in log:
    fail_("CHANGELOG.md has no [Unreleased] section")
else:
    sect = log.split('## [Unreleased]', 1)[1]
    sect = re.split(r'^## \[', sect, maxsplit=1, flags=re.M)[0]
    item = lambda l: l.startswith('- ') or l.startswith('> - ')
    starts = ('- ', '> - ', '#', '> **')
    wrapped, prev = [], ''
    for line in sect.splitlines():
        if line.strip() and item(prev) and not line.startswith(starts):
            wrapped.append(line.strip()[:60])
        prev = line
    pass_("CHANGELOG [Unreleased]: every list item is one line") if not wrapped else \
        fail_(f"CHANGELOG [Unreleased]: {len(wrapped)} wrapped list line(s), first: '{wrapped[0]}'")
sys.exit(rc)
PY
}

release_docs "$ROOT" || FAIL=1

# The self-test: check 11 on mutated copies of the four files — every mutation must go red.
say "release-docs self-test (mutated copies must go red):"
ST="$(mktemp -d)"
selftest() { # <name> <python one-liner that mutates the copy in $ST>
  for f in README.md CHANGELOG.md CONTRIBUTING.md CONTRIBUTING.de.md; do
    [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$ST/$f"
  done
  python3 -c "$2" "$ST" || { fail "self-test '$1' could not mutate the copy"; return; }
  if release_docs "$ST" >/dev/null; then fail "self-test '$1' stayed GREEN"; else pass "self-test '$1' — correctly RED"; fi
}
selftest "CONTRIBUTING.de.md missing"    'import sys,os; os.remove(os.path.join(sys.argv[1],"CONTRIBUTING.de.md"))'
selftest "EN guide drops the DE link"    'import sys,os,re; p=os.path.join(sys.argv[1],"CONTRIBUTING.md"); t=open(p).read(); open(p,"w").write(re.sub(r"\]\(\.?/?CONTRIBUTING\.de\.md[^)]*\)", "](elsewhere.md)", t))'
selftest "README drops CONTRIBUTING link" 'import sys,os,re; p=os.path.join(sys.argv[1],"README.md"); t=open(p).read(); open(p,"w").write(re.sub(r"\]\(\.?/?CONTRIBUTING\.md[^)]*\)", "](elsewhere.md)", t))'
selftest "wrapped CHANGELOG item"        'import sys,os; p=os.path.join(sys.argv[1],"CHANGELOG.md"); t=open(p).read(); i=t.index("## [Unreleased]"); j=t.index("\n- ", i)+1; k=t.index("\n", j); open(p,"w").write(t[:k]+"\n  wrapped continuation of the item"+t[k:])'
selftest "wrapped upgrade-note item"     'import sys,os; p=os.path.join(sys.argv[1],"CHANGELOG.md"); t=open(p).read(); i=t.index("## [Unreleased]"); j=t.index("\n> - ", i)+1; k=t.index("\n", j); open(p,"w").write(t[:k]+"\n> wrapped continuation"+t[k:])'
selftest "no [Unreleased] section"       'import sys,os; p=os.path.join(sys.argv[1],"CHANGELOG.md"); t=open(p).read(); open(p,"w").write(t.replace("## [Unreleased]","## [9.9.9]"))'
rm -rf "$ST"

# -- result -------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then say "RESULT: GREEN"; exit 0; else say "RESULT: RED"; exit 1; fi
