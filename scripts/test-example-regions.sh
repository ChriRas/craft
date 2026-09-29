#!/usr/bin/env bash
# test-example-regions.sh — the case table for scripts/example-regions.sh.
#
# THE TABLE IS THE CONTRACT. It was written before the helper existed (slice-047, sub-task 1),
# against scripts/epic-entry-link.sh's parser as the reference, so the helper is judged by this
# file rather than the other way round. Every case states what it pins and, where the answer
# deviates from the reference, why.
#
# WHAT THE HELPER DOES. One question — "is this line part of an EXAMPLE rather than content?" —
# answered the same way for every caller:
#
#   example-regions.sh blank  <markdown|html> <file>   the file, example lines replaced by ""
#   example-regions.sh report <markdown|html> <file>   UNCLOSED=<line> <fence>, or nothing
#
# `blank` preserves the line count, so a caller can keep using line numbers (epic-entry-link.sh
# reports entry positions, review-findings-state.sh reports MALFORMED lines).
#
# THREE CONSTRUCTS, TWO MODES (slice-047 decision, 2026-09-18):
#   markdown — fenced code blocks, and multi-line HTML comment blocks
#   html     — <pre> elements, and multi-line HTML comment blocks
# A SINGLE-LINE HTML comment is never an example region in either mode. CRAFT's binding markers
# ARE HTML comments (`<!-- demo:marker -->`), and R7-3a's decoy sits three lines below one,
# inside the template's own `<!-- Examples (uncomment to use): -->` block. Blanking "HTML
# comments" would blank the markers this whole mechanism binds. Cases 14–17 pin both directions.
#
# TOKENS ARE SYNTHETIC ON PURPOSE. The cases below use `<!-- demo:marker -->`, not CRAFT's real
# `craft:model-enum`: this table tests the STRUCTURE (is this line an example?), and a file
# carrying real marker tokens is picked up by test-model-enum.sh's tree scan, which rightly
# demands that any marked file be registered as a binding site. The real-token attacks — R7-3a's
# decoy in a template's Examples block and R7-3b's decoy in a <pre> — are fixtures in
# test-model-enum.sh, where the real scan runs and where they belong.
#
# RUNTIME. bash 3.2 (the helper is reached from the SessionStart hook through
# review-findings-state.sh, which uses no python3 today and must keep it that way). This harness
# itself is not hook-reachable, but it runs the helper under /bin/bash to prove the constraint.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/scripts/example-regions.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# ---------------------------------------------------------------------------------------------
# case <name> <mode> <blank-line-numbers, space separated or "-"> <<'EOF' … EOF
#
# Asserts that `blank` empties exactly the named lines and leaves every other line byte-identical.
# Naming the lines rather than the whole expected output keeps a case readable and makes a
# mismatch report the line, not a diff of the file.
# ---------------------------------------------------------------------------------------------
case_blank() {
  local name="$1" mode="$2" want="$3" src="$WORK/in.md"
  cat > "$src"
  case_blank_file "$name" "$mode" "$want" "$src"
}

case_blank_file() {
  local name="$1" mode="$2" want="$3" src="$4" got out i n
  if [ ! -x "$HELPER" ] && [ ! -f "$HELPER" ]; then
    fail "$name — helper not found at $HELPER (expected while the table is written first)"
    return
  fi
  out="$WORK/out"
  # HELPER_RUNNER pins WHICH bash runs the helper. Empty means the shebang's. The bash-3.2
  # leg at the bottom sets it, so that leg compares the ANSWER and not merely the absence of
  # shell error text -- a 3.2-specific wrong answer used to pass it (slice-047, R1-11).
  if [ -n "${HELPER_RUNNER:-}" ]; then
    "$HELPER_RUNNER" "$HELPER" blank "$mode" "$src" > "$out" 2>&1 \
      || { fail "$name — helper exited non-zero under $HELPER_RUNNER: $(cat "$out")"; return; }
  else
    "$HELPER" blank "$mode" "$src" > "$out" 2>&1 || { fail "$name — helper exited non-zero: $(cat "$out")"; return; }
  fi

  # Captured to a FILE, never "$(...)": command substitution strips trailing newlines, so every
  # case whose last lines are blanked — an unclosed fence, a comment block at EOF — lost exactly
  # the lines it was testing and reported a bogus line-count mismatch (slice-047, sub-task 3).
  n=$(wc -l < "$src" | tr -d ' ')
  got=$(wc -l < "$out" | tr -d ' ')
  if [ "$n" != "$got" ]; then
    fail "$name — line count changed: $n in, $got out"
    return
  fi

  local bad="" expect actual
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1))
    actual="$(sed -n "${i}p" "$out")"
    case " $want " in
      *" $i "*) expect="" ;;
      *)        expect="$(sed -n "${i}p" "$src")" ;;
    esac
    [ "$actual" = "$expect" ] || bad="$bad $i"
  done
  if [ -n "$bad" ]; then
    fail "$name — wrong lines:${bad} (wanted blank:${want:+ }$want)"
  else
    pass "$name"
  fi
}

# case_blank_raw <name> <mode> <blank-lines> <printf-format>
# Same contract as case_blank, but the input is built with printf. A heredoc cannot carry a CR,
# and trailing spaces do not survive an editor, so the two cases that are ABOUT exactly those
# bytes were written as heredocs and tested neither. Caught by auditing the table against its own
# case names (slice-047, sub-task 1) — the R8-9 defect shape slice-046 paid four rounds to learn.
case_blank_raw() {
  local name="$1" mode="$2" want="$3" fmt="$4" src="$WORK/in.md"
  # '%b' and not "$fmt": a format starting with '-' is read as an option, and %b is what
  # expands the \n and \r this variant exists for.
  printf '%b' "$fmt" > "$src"
  case_blank_file "$name" "$mode" "$want" "$src"
}

# case_report <name> <mode> <expected stdout of `report`> <<'EOF' … EOF
case_report() {
  local name="$1" mode="$2" want="$3" src="$WORK/in.md" out
  cat > "$src"
  if [ ! -f "$HELPER" ]; then fail "$name — helper not found at $HELPER"; return; fi
  # A variable is safe here: `report` prints at most one line and never a trailing blank.
  out="$("$HELPER" report "$mode" "$src" 2>&1)" || { fail "$name — helper exited non-zero: $out"; return; }
  if [ "$out" = "$want" ]; then pass "$name"; else fail "$name — report was '$out', wanted '$want'"; fi
}

printf 'example-regions case table — %s\n\n' "$(date +%F)"
printf 'Markdown fences (reference: scripts/epic-entry-link.sh)\n'

case_blank "a backtick fence hides its content, and the fence lines themselves" markdown "2 3 4" <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
```
- [ ] entry-b — kept
EOF

case_blank "a tilde fence does the same" markdown "2 3 4" <<'EOF'
- [ ] entry-a — kept
~~~
- [ ] decoy — hidden
~~~
- [ ] entry-b — kept
EOF

case_blank "an indented fence is still a fence" markdown "2 3 4" <<'EOF'
- [ ] entry-a — kept
   ```
   - [ ] decoy — hidden
   ```
- [ ] entry-b — kept
EOF

# CommonMark, and the reference: an inner run shorter than the opener does not close it, so the
# "nested" case is really "the inner fence is content". Round 4's R4-1 is that the current
# implementations COUNT fences instead of parsing them, so this case is the one that fails today.
case_blank "a shorter inner fence does not close the outer one" markdown "2 3 4 5 6" <<'EOF'
- [ ] entry-a — kept
````
```
- [ ] decoy — hidden
```
````
- [ ] entry-b — kept
EOF

case_blank "a closer of a different character does not close" markdown "2 3 4 5" <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
~~~
```
- [ ] entry-b — kept
EOF

# The reference's info-string rule: a ``` opener's info string may hold no backtick, so this line
# is not a fence at all and the entries around it stay visible.
case_blank "a backtick in a backtick fence's info string means it is not a fence" markdown "-" <<'EOF'
- [ ] entry-a — kept
``` see `x`
- [ ] entry-b — kept
EOF

case_blank "a tilde fence's info string may hold anything" markdown "2 3 4" <<'EOF'
- [ ] entry-a — kept
~~~ see `x`
- [ ] decoy — hidden
~~~
- [ ] entry-b — kept
EOF

case_blank "a closing run with trailing content is not a closer" markdown "2 3 4 5 6" <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
``` not a closer
- [ ] still hidden
```
- [ ] entry-b — kept
EOF

# Built with printf: the closer's trailing spaces ARE the case, and they do not survive an editor.
case_blank_raw "trailing whitespace does not stop a closer from closing" markdown "2 3 4" \
  '- [ ] entry-a\n```\n- [ ] decoy\n```   \n- [ ] entry-b\n'

case_blank "an unclosed fence hides the rest of the file" markdown "2 3 4" <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
- [ ] also hidden
EOF

case_report "an unclosed fence is reported, not swallowed" markdown 'UNCLOSED=2 ```' <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
EOF

case_report "a well-formed file reports nothing" markdown '' <<'EOF'
- [ ] entry-a — kept
```
- [ ] decoy — hidden
```
EOF

# DELIBERATE DEVIATION FROM THE REFERENCE (slice-047, 2026-09-18).
# epic-entry-link.sh anchors its fence regexes on ^[[:space:]]*, so a fence opened inside a
# blockquote is invisible to it; test-model-enum.sh's defenced() strips '> ' first and sees it.
# The table pins RECOGNISE — defenced()'s answer. Sub-task 4 measured what that changes: nothing
# observable. defenced() already blanked a decoy marker inside a blockquoted fence, and
# epic-entry-link.sh's ENTRY_RE is column-0 anchored, so a quoted entry was never an entry. The
# case stays because the helper needs ONE answer to give every caller, not because it fixes a
# live hole.
case_blank "a fence opened inside a blockquote is recognised" markdown "2 3 4" <<'EOF'
> - [ ] entry-a — kept
> ```
> - [ ] decoy — hidden
> ```
> - [ ] entry-b — kept
EOF

# Built with printf: a heredoc cannot carry the CR this case exists to test.
case_blank_raw "CRLF line endings do not hide a fence" markdown "2 3 4" \
  '- [ ] entry-a\r\n```\r\n- [ ] decoy\r\n```\r\n- [ ] entry-b\r\n'

printf '\nExample comment blocks (R7-3a) — the construct an HTML comment is, and is not\n'

# The closer is part of the region, exactly as a fence's closing line is. The rule is keyed on a
# line whose stripped content ENDS with `-->` and carries no `<!--` of its own, which is a
# deliberate narrowing of HTML: by HTML semantics the block would end at the first embedded `-->`,
# i.e. at the decoy's own comment, and the two template lines after it would leak back into
# content. A bare `-->` (CRAFT's templates) and a trailing closer on the last text line (an
# editor's block-comment toggle) both end it; the decoy line does not.
case_blank "a multi-line comment block is an example region" markdown "3 4 5 6" <<'EOF'
> <!-- demo:marker -->
> Allowed values: `opus`, `sonnet`
<!-- Examples (uncomment to use):
> <!-- demo:marker -->
> Allowed values: `opus`
-->
EOF

# R3-1 (slice-047 review round 3): the closer on the end of the last text line is the most common
# way to write a multi-line comment. The exact-`-->` rule never closed it, so the rest of the file
# was blanked in silence -- measured on a copy of this slice's plan: OPEN_COUNT=0 where HEAD's
# parser read 1. The line after the block must survive.
case_blank "a block whose last text line carries the closer ends on that line" markdown "2 3" <<'EOF'
x
<!-- Dropped from scope for now:
the old paragraph, kept for reference -->
- [ ] entry-b — kept
EOF

case_blank "a single-line marker comment is never an example region" markdown "-" <<'EOF'
<!-- demo:marker -->
Allowed values: `opus`, `sonnet`
EOF

case_blank "the decoy inside the block is blanked while the real marker above it survives" markdown "4 5 6 7" <<'EOF'
<!-- demo:marker -->
Allowed values: `opus`, `sonnet`

<!-- Examples (uncomment to use):
<!-- demo:marker -->
Allowed values: `haiku`
-->
EOF

case_blank "a comment that opens and closes on one line stays content" markdown "-" <<'EOF'
<!-- demo:marker canonical -->
Spawn-reachable values: `opus`, `sonnet`, `haiku`, `fable`
EOF

# R2-1 (slice-047 review round 2): the opener must BEGIN the stripped line. Accepting `<!--`
# anywhere on the line made a prose line that merely NAMES the token open a phantom block, which
# the exact-`-->` closer never closes -- so the rest of the file was blanked and `report` said
# nothing. Measured live on two slice plans, including this slice's own. A wrapper (indentation,
# a `>` quote) is not company, exactly as for a binding marker; other text on the line is.
case_blank "a prose line that merely NAMES the opener is content, not an opener" markdown "-" <<'EOF'
x
the token `<!--` opens a block only at the start of a line
## Review Findings
- a finding line that must stay visible
EOF

case_blank "a bare opener alone on its line still opens a block" markdown "2 3 4" <<'EOF'
x
<!--
hidden
-->
z
EOF

case_blank "an indented opener still opens a block" markdown "2 3 4" <<'EOF'
x
  <!--
  hidden
  -->
z
EOF

case_blank "a blockquoted opener still opens a block" markdown "2 3 4" <<'EOF'
x
> <!--
> hidden
> -->
z
EOF

printf '\nHTML mode (R7-3b) — docs/index.html is not Markdown at all\n'

case_blank "a pre element is an example region" html "3 4 5" <<'EOF'
<p>intro</p>
<!-- demo:marker -->
<pre>
  &lt;!-- demo:marker --&gt; decoy
</pre>
<p>outro</p>
EOF

case_blank "a marker comment in html mode survives" html "-" <<'EOF'
<tr><td><!-- demo:marker --></td></tr>
<tr><td>opus, sonnet, haiku, fable</td></tr>
EOF

case_blank "a multi-line comment in html mode is an example region" html "2 3 4" <<'EOF'
<p>intro</p>
<!-- Examples:
  <!-- demo:marker --> decoy
-->
<p>outro</p>
EOF

case_blank "in html mode a mid-line mention of the pre tag is content, not an opener" html "-" <<'EOF'
<tr><td>the opener <pre is only an opener at the start of a line</td></tr>
<tr><td>opus, sonnet, haiku, fable</td></tr>
EOF

case_blank "in html mode a pre element starting the line still opens a region" html "2 3 4" <<'EOF'
<p>intro</p>
<pre>
  decoy
</pre>
EOF

case_blank "a fence in html mode is not a construct there" html "-" <<'EOF'
<p>```</p>
<p>still content</p>
EOF

printf '\nbash 3.2 — the helper is reached from the SessionStart hook\n'
if [ -f "$HELPER" ]; then
  # Absence of shell error text is not evidence of a correct answer, so this leg runs a real case
  # of the table above under /bin/bash and compares the blanked output line by line.
  HELPER_RUNNER=/bin/bash
  case_blank "under /bin/bash 3.2, a fence hides its content — same answer, not merely no error" markdown "2 3 4" <<'EOF'
x
```
y
```
z
EOF
  case_blank "under /bin/bash 3.2, a nested fence is one region" markdown "2 3 4 5 6" <<'EOF'
x
````md
```
y
```
````
EOF
  HELPER_RUNNER=""
else
  fail "the helper runs under /bin/bash 3.2 — helper not found at $HELPER"
fi

printf '\nthe argument handling of the helper itself\n'
if [ -f "$HELPER" ]; then
  printf 'x\n' > "$WORK/args.md"

  "$HELPER" bogus markdown "$WORK/args.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown action exits 2 (got $rc)" || fail "an unknown action should exit 2, got $rc"

  "$HELPER" blank bogus "$WORK/args.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown mode exits 2 (got $rc)" || fail "an unknown mode should exit 2, got $rc"

  "$HELPER" blank markdown "$WORK/does-not-exist.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 3 ] && pass "a missing input file exits 3 (got $rc)" || fail "a missing input file should exit 3, got $rc"

  # A file whose last line carries no newline: the helper adds one. Pinned because a caller that
  # diffs line counts depends on it, and nothing else in the table covers it.
  printf 'x\n```\ny' > "$WORK/nonl.md"
  "$HELPER" blank markdown "$WORK/nonl.md" > "$WORK/nonl.out" 2>&1
  if [ "$(wc -l < "$WORK/nonl.out" | tr -d ' ')" = "3" ] && [ -z "$(sed -n '2p;3p' "$WORK/nonl.out")" ]; then
    pass "a file with no final newline comes back with one, and the unclosed fence is blanked"
  else
    fail "no-final-newline input: got $(wc -l < "$WORK/nonl.out" | tr -d ' ') line(s): $(cat "$WORK/nonl.out")"
  fi
else
  fail "the argument handling of the helper — helper not found at $HELPER"
fi

printf '\nRESULT: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
