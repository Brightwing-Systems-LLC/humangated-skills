#!/usr/bin/env bash
# PreToolUse: refuse work inside the scope of an open gate.
#
# This is the only mechanism in any harness that actually STOPS an agent. Skill
# text is a request a model may decline; a hook is shell, it runs outside the
# model, and its verdict is not up for negotiation.
#
# Two rules govern everything below.
#
# 1. FAIL OPEN. Every unexpected condition — no jq, no ledger, a malformed line,
#    a network hiccup — exits 0 and blocks nothing. A guard that wrongly blocks
#    is uninstalled within the hour, and then it protects nothing at all. The
#    model still has BLOCKED in context via CLAUDE.md, so failing open degrades
#    to the advisory tier rather than to nothing.
#
# 2. NEVER BLOCK ON A NETWORK CALL. A hook that hangs is a hook people disable.
#    The single liveness call is capped at two seconds and its failure is
#    indistinguishable from success (see `still_open`).
#
# What gets blocked depends on what was declared, mirroring ask-lifecycle §4:
#
#   awaited            → may prepare changes inside scope, may not LAND them
#                        (Write/Edit allowed; commit/push/deploy denied)
#   required, blocking → may not touch scope at all
#   courtesy           → never in BLOCKED; nothing to enforce
set -uo pipefail

exec 3>&1        # real stdout, for the verdict
exec 1>&2        # anything else we print is diagnostics, never protocol

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
[ -n "$CWD" ] || exit 0

# The ledger is committed at the repo root; the agent may be anywhere under it.
root="$CWD"
while [ "$root" != "/" ] && [ ! -f "$root/.humangated/BLOCKED" ]; do
  root=$(dirname "$root")
done
BLOCKED="$root/.humangated/BLOCKED"
[ -f "$BLOCKED" ] || exit 0

# What is this tool about to touch?
case "$TOOL" in
  Write|Edit|NotebookEdit)
    TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
    ACTION="edit"
    ;;
  Bash)
    TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
    ACTION="run"
    ;;
  *) exit 0 ;;
esac
[ -n "$TARGET" ] || exit 0

# Paths arrive absolute; scopes are repo-relative.
REL="${TARGET#"$root"/}"

# Landing verbs: the irreversible, outward half of §4's table. Deliberately not
# a shell parser — this is a short list of things that make work real, and
# anything subtler is the operator's judgment, not a regex's.
is_landing() {
  printf '%s' "$1" | grep -Eq \
    '(^|[;&|[:space:]])(git[[:space:]]+(commit|push|merge|tag)|npm[[:space:]]+publish|yarn[[:space:]]+publish|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|docker[[:space:]]+push|just[[:space:]]+prod-|make[[:space:]]+deploy|gh[[:space:]]+(pr[[:space:]]+merge|release))'
}

# What would a landing command actually put into the world?
#
# `git push origin main` names no path but ships every gated file that happens
# to be committed, so matching the command TEXT against the scope misses the
# most common way work escapes a gate. Ask git instead: staged files for a
# commit, unpushed commits for a push.
#
# Deliberately conservative in one direction only — if git cannot answer, we
# print nothing and the caller blocks. Being wrong about an irreversible,
# outward-facing action is the expensive kind of wrong.
landing_paths() {
  local cmd="$1" out=""
  if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit'; then
    out=$(git -C "$root" diff --cached --name-only 2>/dev/null)
    # `commit -a` sweeps in every tracked modification too.
    if printf '%s' "$cmd" | grep -Eq 'commit[[:space:]]+(-[a-zA-Z]*a|--all)'; then
      out="$out
$(git -C "$root" diff --name-only 2>/dev/null)"
    fi
  elif printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(push|merge)'; then
    out=$(git -C "$root" diff --name-only '@{u}..HEAD' 2>/dev/null) \
      || out=$(git -C "$root" diff --name-only 'origin/HEAD..HEAD' 2>/dev/null)
  else
    # A deploy or publish ships the tree. Nothing to narrow it down to.
    return 1
  fi
  [ -n "${out// /}" ] || return 1
  printf '%s\n' "$out"
}

matches_scope() {   # $1 = candidate text, $2 = glob
  local pat="${2%/}"
  # `**` collapses to `*` because a shell glob in `case` already crosses `/`.
  # The replacement must NOT be escaped — `\*` inserts a literal backslash and
  # then nothing ever matches, which is a guard that silently permits
  # everything. That is the single worst bug this file can have, so it has a
  # test: hooks/tests/test_guard.sh.
  pat="${pat//\*\*/*}"
  case "$1" in
    $pat) return 0 ;;
    $pat/*) return 0 ;;
  esac
  # For a shell command we cannot know the paths, so fall back to the scope's
  # literal directory prefix appearing anywhere in the command text.
  if [ "$ACTION" = "run" ]; then
    local literal="${pat%%\**}"
    literal="${literal%/}"
    [ -n "$literal" ] && printf '%s' "$1" | grep -qF "$literal" && return 0
  fi
  return 1
}

now=$(date -u +%s)
iso_to_epoch() {  # GNU and BSD date disagree; try both, give up quietly
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "${1/Z/+0000}" +%s 2>/dev/null
}

still_open() {  # $1 = uuid. Any doubt answers "yes" — see rule 2.
  local base="${HGD_BASE_URL:-https://humangated.ai}"
  local body
  body=$(curl -sS --max-time 2 "$base/api/asks/$1/live" 2>/dev/null) || return 0
  printf '%s' "$body" | jq -e '.status == "queued" and .expired == false' >/dev/null 2>&1
}

deny() {  # $1 = reason
  jq -n --arg r "$1" '{hookSpecificOutput:{
    hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r
  }}' >&3
  exit 0
}

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  # uuid  preset/on_expiry  deadline|-  checked_at  scope…
  set -- $line
  [ $# -ge 4 ] || continue
  uuid=$1 decl=$2 deadline=$3 checked=$4
  shift 4
  scopes="$*"
  [ -n "$scopes" ] && [ "$scopes" != "-" ] || continue

  preset="${decl%%/*}"
  [ "$preset" = "courtesy" ] && continue
  # An `awaited` ask permits editing inside scope; only landing is held.
  if [ "$preset" = "awaited" ] && [ "$ACTION" = "edit" ]; then continue; fi
  if [ "$ACTION" = "run" ] && ! is_landing "$TARGET"; then continue; fi

  hit=""
  if [ "$ACTION" = "run" ]; then
    # Prefer what git says this command would actually ship; fall back to the
    # command text, and if git cannot answer at all, hold — a landing verb with
    # an unknown blast radius is exactly what a gate is for.
    if paths=$(landing_paths "$TARGET"); then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        for glob in $scopes; do
          matches_scope "$p" "$glob" && { hit="$glob"; break 2; }
        done
      done <<< "$paths"
    else
      for glob in $scopes; do
        matches_scope "$TARGET" "$glob" && { hit="$glob"; break; }
      done
      [ -n "$hit" ] || hit="$scopes (this command's reach could not be determined)"
    fi
  else
    for glob in $scopes; do
      matches_scope "$REL" "$glob" && { hit="$glob"; break; }
    done
  fi
  [ -n "$hit" ] || continue

  # A deadline that has passed releases the gate locally, whatever the file
  # still says. The engine has either acted already or is about to.
  if [ "$deadline" != "-" ]; then
    dl=$(iso_to_epoch "$deadline")
    if [ -n "$dl" ] && [ "$now" -ge "$dl" ]; then continue; fi
  fi

  still_open "$uuid" || continue

  stale=""
  ck=$(iso_to_epoch "$checked")
  if [ -n "$ck" ] && [ $((now - ck)) -gt 1800 ]; then
    stale=" (this local record is over 30 minutes old — run /hgd-status to refresh)"
  fi

  case "$preset" in
    blocking) when="There is no deadline; it waits for the reviewer." ;;
    required) when="Unanswered by $deadline, the work is dropped." ;;
    *)        when="Holding until $deadline." ;;
  esac

  deny "Blocked on an open HumanGated gate.

Ask $uuid ($preset) covers \`$hit\`, and this would ${ACTION} \`${REL:-$TARGET}\`.
$when$stale

You told a named human this work was held. Do something outside that scope, or
run /hgd-status to see whether they have answered. If the operator wants to
proceed anyway, /hgd-unblock $uuid records the override with their reason —
don't just work around this."
done < "$BLOCKED"

exit 0
