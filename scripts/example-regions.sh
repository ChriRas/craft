#!/usr/bin/env bash
# example-regions.sh — the one answer to "is this line an EXAMPLE rather than content?"
#
# CRAFT's harnesses read their own repository: markers, epic entries, findings lines. A line that
# sits inside an example must not be read as content, or a decoy parked in one stands in for the
# real thing and every check stays green. Four scripts used to decide this independently and
# demonstrably disagreed; this helper is the single definition they all call.
#
#   example-regions.sh blank  <markdown|html> <file>   the file, example lines replaced by ""
#   example-regions.sh report <markdown|html> <file>   UNCLOSED=<line> <fence>, or nothing
#
# `blank` preserves the line count and every kept line byte-for-byte (trailing CR included), so a
# caller keeps using line numbers. The CONTRACT is scripts/test-example-regions.sh, not this
# header: the case table was written first, against scripts/epic-entry-link.sh's parser as the
# reference, and this file is judged by it.
#
# THREE CONSTRUCTS, TWO MODES
#   markdown — fenced code blocks; multi-line HTML comment blocks
#   html     — <pre> elements;     multi-line HTML comment blocks
#
# A SINGLE-LINE HTML comment is never an example region. CRAFT's binding markers ARE HTML
# comments (`<!-- craft:model-enum -->`), so blanking "HTML comments" would blank the very things
# the mechanism binds. A multi-line block is the example; a one-liner is content.
#
# TWO DELIBERATE DIVERGENCES, both pinned by cases:
#   1. A fence opened inside a `>` blockquote IS recognised — defenced()'s answer, not
#      epic-entry-link.sh's, which anchors on ^[[:space:]]* and misses it. Measured: no outcome
#      changes either way today (defenced() already blanked a decoy in one, and epic-entry-link's
#      ENTRY_RE is column-0 anchored so a quoted entry is never an entry). This is unification,
#      not a fix — one answer where there were two.
#   2. A comment block ends at the first line whose stripped content ENDS with `-->` and opens no
#      comment of its own — a bare `-->`, or a last text line followed by `-->`, the shape an
#      editor's block-comment toggle writes. By HTML semantics it would end at the first embedded
#      `-->` — i.e. inside a decoy marker line — letting the rest of the block leak back into
#      content, so a line carrying `<!--` never closes it. A `-->` with more text after it on its
#      line does not close it either; no CRAFT file writes that. (Until slice-047 R3-1 only an
#      exact `-->` closed a block, and a trailing closer silently blanked the rest of the file.)
#
# RUNTIME: bash 3.2. review-findings-state.sh reaches this from the SessionStart hook and uses no
# python3 today; a python helper would put a new hard dependency on a path that must fail open.

set -u

usage() {
  printf 'usage: %s <blank|report> <markdown|html> <file>\n' "${0##*/}" >&2
  exit 2
}

[ $# -eq 3 ] || usage
ACTION="$1"; MODE="$2"; FILE="$3"

case "$ACTION" in blank|report) ;; *) usage ;; esac
case "$MODE"   in markdown|html) ;; *) usage ;; esac
[ -f "$FILE" ] || { printf 'ERROR=file_not_found:%s\n' "$FILE" >&2; exit 3; }

# CommonMark-shaped, and the reference's rules: a ``` opener's info string holds no backtick, a
# ~~~ opener's may hold anything, and a closer is a bare run of the SAME character at least as
# long as the opener. Applied to the stripped line, so indent and blockquote markers do not hide
# a fence.
FENCE_OPEN_BT_RE='^(`{3,})[^`]*$'
FENCE_OPEN_TL_RE='^(~{3,})'
FENCE_CLOSE_RE='^(`{3,}|~{3,})$'

# strip_lead <text> -> the text with leading whitespace and '>' blockquote markers removed.
# A loop rather than a parameter-expansion trick: the obvious `${t#"${t%%[![:space:]>]*}"}` eats
# the last word of an ordinary line, because %% removes the longest matching SUFFIX.
strip_lead() {
  local s="$1"
  while [ -n "$s" ]; do
    case "$s" in
      [[:space:]]*) s="${s#?}" ;;
      '>'*)         s="${s#?}" ;;
      *)            break ;;
    esac
  done
  printf '%s' "$s"
}

# is_comment_opener <text> -> 0 when the line opens a comment it does not also close.
# Keyed on the LAST `<!--`: `<!-- craft:model-enum -->` closes itself and is content, while
# `<!-- Examples (uncomment to use):` does not and opens a block.
is_comment_opener() {
  local t="$1" s rest
  # The token must BEGIN the line, wrappers aside. Accepting it ANYWHERE let a prose line that
  # merely NAMES it open a phantom block, which the exact-`-->` closer never closes -- so the rest
  # of the file was blanked and `report`, which only watches fences, said nothing (slice-047 R2-1,
  # reproduced live on two slice plans). Indentation and a `>` quote are wrappers, not company --
  # the same rule a binding marker follows; any other text on the line makes it prose.
  s="$(strip_lead "$t")"
  case "$s" in '<!--'*) ;; *) return 1 ;; esac
  rest="${s##*<!--}"
  case "$rest" in *'-->'*) return 1 ;; *) return 0 ;; esac
}

fence=""          # the opening run while a fence is open, else empty
fence_line=0
comment=0
pre=0
n=0
out=""

emit() {  # emit <text> — collected, so `report` prints nothing but its own findings
  [ "$ACTION" = "blank" ] || return 0
  printf '%s\n' "$1"
}

while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  t="${line%$'\r'}"                          # drop a trailing CR …
  t="${t%"${t##*[![:space:]]}"}"             # … and trailing whitespace, for testing only
  s="$(strip_lead "$t")"

  # ---- inside a comment block: everything up to and including its closing line ---------------
  if [ "$comment" -eq 1 ]; then
    emit ""
    case "$s" in *'<!--'*) ;; *'-->') comment=0 ;; esac
    continue
  fi

  # ---- inside a <pre> (html mode only) -------------------------------------------------------
  if [ "$pre" -eq 1 ]; then
    emit ""
    case "$t" in *'</pre>'*) pre=0 ;; esac
    continue
  fi

  # ---- inside a fence (markdown mode only) ---------------------------------------------------
  if [ -n "$fence" ]; then
    emit ""
    if [[ "$s" =~ $FENCE_CLOSE_RE ]]; then
      run="${BASH_REMATCH[1]}"
      if [ "${run%"${run#?}"}" = "${fence%"${fence#?}"}" ] && [ ${#run} -ge ${#fence} ]; then
        fence=""
      fi
    fi
    continue
  fi

  # ---- openers -------------------------------------------------------------------------------
  if [ "$MODE" = "markdown" ]; then
    if [[ "$s" =~ $FENCE_OPEN_BT_RE ]] || [[ "$s" =~ $FENCE_OPEN_TL_RE ]]; then
      fence="${BASH_REMATCH[1]}"; fence_line=$n; emit ""; continue
    fi
  else
    # Same rule as the comment opener: the tag must BEGIN the stripped line. A mid-line mention
    # used to open a phantom region that `</pre>` never closed (slice-047 R2-1).
    case "$s" in
      '<pre'*)
        # a <pre> that also closes on the same line is still one example line
        case "$t" in *'</pre>'*) ;; *) pre=1 ;; esac
        emit ""; continue ;;
    esac
  fi

  if is_comment_opener "$t"; then
    comment=1; emit ""; continue
  fi

  emit "$line"
done < "$FILE"

if [ "$ACTION" = "report" ] && [ -n "$fence" ]; then
  printf 'UNCLOSED=%s %s\n' "$fence_line" "$fence"
fi

exit 0
