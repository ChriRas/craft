#!/usr/bin/env bash
#
# craft (Coding with Rules, Autonomy, Feedback, Tests)
# flow-state.sh — the auto slice flow's one verdict: what, if anything, starts next? (slice-074, D42)
#
# WHY ------------------------------------------------------------------------
# Outside /craft:execute a slice moved only when the human typed the next phase command, although every phase
# already ends by naming it. With `## Slice Flow` -> `Mode: auto` (the default) the agent starts that next
# phase itself — but a "should I go on?" judged from memory is exactly the call that goes wrong silently
# (rules.md: what an agent must carry out is checked by command). So one helper reads the profile's mode and the
# plan's status and states the verdict; the agent acts on NEXT= / STOP= only (skills/workflow/SKILL.md ->
# Auto flow). DOUBT MEANS STOP: a wrong automatic phase start costs more than a halt, unlike the handoff marker
# (where doubt means live).
#
# WHAT -----------------------------------------------------------------------
#   flow-state.sh [--project <root>] [--profile <file>] [--from <status>] <plan-file>
#   flow-state.sh [--project <root>] [--profile <file>] --mode
#   flow-state.sh --map
#
#   <plan-file>  the slice plan (relative paths resolve against the project root).
#   --project    the project root; default CLAUDE_PROJECT_DIR, else the cwd.
#   --profile    default <root>/.claude/project/craft-profile.md (absent -> the defaults below).
#   --from       the plan's status when the phase command's OWN WORK began — after its Pre-flight status write, not the
#                status it found (skills/workflow/SKILL.md -> Auto flow lists one value per command). A phase that ends in
#                the status it began in has not advanced (a gated review, a [U] iteration, a pause) and does not chain:
#                STOP=no-progress.
#   --mode       the profile only (for /craft:prime, /craft:recap Step 4 and hooks/pause-watch.sh): MODE= and WARN= lines, no plan, no verdict.
#   --map        the status -> command map, one `<status><TAB>NEXT<TAB>/craft:<cmd>` or
#                `<status><TAB>STOP<TAB><reason>` line per status. test-workflow-status-graph.sh binds it to the
#                phase graph in skills/workflow/SKILL.md in both directions (rules.md tabu: an unbound copy of the
#                graph is the violation) — change a row here and the graph's table in the same edit.
#
# The mode, from the profile's `## Slice Flow` block (craft-profile.md):
#   - **Mode:** auto | manual     default auto (a missing file, block or key). Anything else is invalid.
#   Read only inside that block (`Execution -> Mode` is a different key); lines in a fenced or commented example
#   and `>` comment lines are no content. An invalid value, a second `Mode` line or an unreadable profile gives
#   MODE=invalid and STOP=invalid-mode; an unknown key or a stray line gives a WARN= line and nothing else.
#
# Output, in this order (key=value, one per line):
#   MODE=auto|manual|invalid
#   STATUS=<the plan's Status>       empty when there is none        (not with --mode)
#   WARN=<text>                      zero or more
#   NEXT=/craft:<phase>   OR   STOP=<reason>      exactly one         (not with --mode)
#
# STOP reasons, first match wins:
#   invalid-mode        the mode is not auto / manual
#   manual              Mode: manual — today's behavior, one command per phase
#   no-plan             the plan file is missing or not a file
#   unknown-status      no `> Status:` line in the plan's frontmatter (above its first `## `), or a value not in the map
#   committed, blocked, paused, awaiting-release, awaiting-approval
#                       the status stops the flow: a human holds the slice or the slice is done
#   pause-requested     the human sent the pause word (hooks/pause-watch.sh, or the agent's own
#                       `pause-request.sh request`) and the request is LIVE for this session — scripts/pause-request.sh
#                       state --plan is the one judge (slice-075). It wins over no-progress and over NEXT: the agent
#                       finishes the running step, writes the handoff and pauses the slice
#                       (skills/workflow/SKILL.md -> Auto flow). A marker nobody can read, a missing helper or an
#                       unattributable session is NO request (a phantom pause would halt a flow the human did not
#                       stop) — the verdict then goes on as if there were none.
#   no-progress         --from names the status the plan is still at
#
# Exit 0 for every verdict; 2 for a usage error, a --project that is not a directory included (nothing on stdout). Needs bash >= 5.0 (scripts/ baseline).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGIONS="$SCRIPT_DIR/example-regions.sh"

# The status -> command map — the one copy; --map prints it for the graph harness.
ALL_STATUSES=(planning implementing testing review refactoring reviewing committing committed blocked paused awaiting-release awaiting-approval)
status_map() {
  case "$1" in
    planning|implementing) printf 'NEXT\t/craft:build\n' ;;
    testing)               printf 'NEXT\t/craft:test\n' ;;
    review)                printf 'NEXT\t/craft:recap\n' ;;
    refactoring)           printf 'NEXT\t/craft:refactor\n' ;;
    reviewing)             printf 'NEXT\t/craft:review\n' ;;
    committing)            printf 'NEXT\t/craft:commit\n' ;;
    committed|blocked|paused|awaiting-release|awaiting-approval) printf 'STOP\t%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

usage() { echo "usage: flow-state.sh [--project <root>] [--profile <file>] [--from <status>] <plan-file> | --mode | --map" >&2; exit 2; }

project="" profile="" from="" plan="" want_mode=0 want_map=0 have_plan=0
while (( $# )); do
  case "$1" in
    --project) (( $# >= 2 )) || usage; project="$2"; shift 2 ;;
    --profile) (( $# >= 2 )) || usage; profile="$2"; shift 2 ;;
    --from)    (( $# >= 2 )) || usage; from="$2"; shift 2 ;;
    --mode)    want_mode=1; shift ;;
    --map)     want_map=1; shift ;;
    -*)        usage ;;
    *)         (( have_plan )) && usage; plan="$1"; have_plan=1; shift ;;
  esac
done
(( want_map && want_mode )) && usage
(( (want_map || want_mode) && have_plan )) && usage

if (( want_map )); then
  for s in "${ALL_STATUSES[@]}"; do
    printf '%s\t' "$s"; status_map "$s"
  done
  exit 0
fi
(( want_mode || have_plan )) || usage

root="${project:-${CLAUDE_PROJECT_DIR:-$PWD}}"
# A root that is not a directory is a usage error, never a silent "no profile -> auto" (doubt means stop).
if [[ ! -d "$root" ]] || ! cd "$root" 2>/dev/null; then echo "flow-state.sh: --project '$root' is not a directory" >&2; exit 2; fi
[[ -n "$profile" ]] || profile="$root/.claude/project/craft-profile.md"

# --- the mode ---------------------------------------------------------------
mode="auto"
warns=()
if [[ -f "$profile" ]]; then
  if ! content="$("${BASH:-bash}" "$REGIONS" blank markdown "$profile" 2>/dev/null)"; then
    mode="invalid"; warns+=("Slice Flow: the profile could not be read (example-regions.sh failed) — treated as invalid.")
  else
    in_block=0 seen_mode=0 value=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      if [[ "$line" =~ ^##[[:space:]]+(.*[^[:space:]])[[:space:]]*$ ]]; then
        [[ "${BASH_REMATCH[1]}" == "Slice Flow" ]] && in_block=1 || in_block=0
        continue
      fi
      (( in_block )) || continue
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*\> ]] && continue
      [[ "$line" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] && continue
      if [[ "$line" =~ ^-[[:space:]]+\*\*([^:*]+):\*\*[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        val="${val%"${val##*[![:space:]]}"}"
        if [[ "$key" == "Mode" ]]; then
          seen_mode=$((seen_mode + 1)); value="$val"
        else
          warns+=("Slice Flow: unknown key '$key' — ignored.")
        fi
      else
        warns+=("Slice Flow: unexpected line '${line:0:60}' — ignored.")
      fi
    done <<< "$content"
    if (( seen_mode > 1 )); then
      mode="invalid"; warns+=("Slice Flow → Mode is set more than once — treated as invalid.")
    elif (( seen_mode == 1 )); then
      case "$value" in
        auto|manual) mode="$value" ;;
        *) mode="invalid"; warns+=("Slice Flow → Mode: '$value' invalid — allowed: auto, manual.") ;;
      esac
    fi
  fi
elif [[ -e "$profile" ]]; then
  mode="invalid"; warns+=("Slice Flow: the profile is not a readable file — treated as invalid.")
fi

emit_warns() { local w; for w in "${warns[@]+"${warns[@]}"}"; do printf 'WARN=%s\n' "$w"; done; }

if (( want_mode )); then
  printf 'MODE=%s\n' "$mode"
  emit_warns
  exit 0
fi

# --- the plan's status -------------------------------------------------------
# The first `> Status:` line of the frontmatter: above the plan's first `## ` heading.
status=""
plan_ok=0
if [[ -f "$plan" ]]; then
  plan_ok=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^##[[:space:]] ]] && break
    if [[ "$line" =~ ^\>[[:space:]]*Status:[[:space:]]*(.*)$ ]]; then
      status="${BASH_REMATCH[1]}"
      status="${status//\`/}"
      status="${status#"${status%%[![:space:]]*}"}"
      status="${status%"${status##*[![:space:]]}"}"
      break
    fi
  done < "$plan"
fi

printf 'MODE=%s\n' "$mode"
printf 'STATUS=%s\n' "$status"
emit_warns

if [[ "$mode" == "invalid" ]]; then echo "STOP=invalid-mode"; exit 0; fi
if [[ "$mode" == "manual" ]]; then echo "STOP=manual"; exit 0; fi
if (( ! plan_ok )); then echo "STOP=no-plan"; exit 0; fi
if ! verdict="$(status_map "$status")"; then echo "STOP=unknown-status"; exit 0; fi
kind="${verdict%%$'\t'*}" detail="${verdict#*$'\t'}"
if [[ "$kind" == "STOP" ]]; then echo "STOP=$detail"; exit 0; fi
# The pause request (slice-075): asked of its one judge; anything but LIVE=yes is no request.
pause_live="$("${BASH:-bash}" "$SCRIPT_DIR/pause-request.sh" state --project "$root" --plan "$plan" 2>/dev/null | sed -n 's/^LIVE=//p' | head -1)"
if [[ "$pause_live" == "yes" ]]; then echo "STOP=pause-requested"; exit 0; fi
if [[ -n "$from" && "$from" == "$status" ]]; then echo "STOP=no-progress"; exit 0; fi
echo "NEXT=$detail"
exit 0
