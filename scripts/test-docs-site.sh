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
 'skills':   len([d for d in os.listdir(os.path.join(root,'skills')) if os.path.isdir(os.path.join(root,'skills',d))]),
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

wrong={v for v in re.findall(r'v(\d+\.\d+\.\d+)', src) if v!=version}
pass_(f"all version strings are v{version}") if not wrong else fail_(f"version strings != plugin.json: {sorted(wrong)}")

pass_("light-mode media query present") if 'prefers-color-scheme: light' in src else fail_("prefers-color-scheme light query missing")
pass_("language toggle persistence present") if "localStorage" in src and "craft-lang" in src else fail_("craft-lang localStorage persistence missing")

sys.exit(rc)
PY

# -- result -------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then say "RESULT: GREEN"; exit 0; else say "RESULT: RED"; exit 1; fi
