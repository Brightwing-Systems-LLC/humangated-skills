#!/usr/bin/env bash
# SessionStart: put pending human judgment in front of the model before it works.
#
# This closes the coverage hole that the envelope badge cannot. The badge rides
# on HumanGated API responses, so it only fires when the agent already touched
# our API — which during ordinary coding work is never. A review that came back
# overnight would otherwise sit unseen until somebody thought to ask.
#
# Fails open and silent: no token, no network, no jq, anything at all — exit 0
# with nothing to say. A session that will not start because a review tool had
# an opinion is a review tool nobody keeps.
set -uo pipefail

exec 3>&1
exec 1>&2

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/humangated"
[ -f "$CFG/config" ] && . "$CFG/config" 2>/dev/null
[ -n "${HGD_TOKEN:-}" ] || exit 0
BASE="${HGD_BASE_URL:-https://humangated.ai}"

digest=$(curl -sS --max-time 6 "$BASE/api/inbox" \
  -H "Authorization: Bearer $HGD_TOKEN" \
  -H "X-HumanGated-Skills: 4.2.0" 2>/dev/null) || exit 0
printf '%s' "$digest" | jq -e . >/dev/null 2>&1 || exit 0

waiting=$(printf '%s' "$digest" | jq -r '.counts.responses_waiting // 0')
overdue=$(printf '%s' "$digest" | jq -r '.counts.overdue // 0')
open_asks=$(printf '%s' "$digest" | jq -r '.counts.open_asks // 0')

# Local gates matter even when the server has nothing new: a fresh clone may
# carry a block this machine has never seen.
root="${CWD:-$PWD}"
while [ "$root" != "/" ] && [ ! -f "$root/.humangated/BLOCKED" ]; do
  root=$(dirname "$root")
done
gates=0
[ -f "$root/.humangated/BLOCKED" ] && gates=$(grep -cve '^\s*$' -e '^#' "$root/.humangated/BLOCKED" 2>/dev/null || echo 0)

[ "$waiting" -eq 0 ] && [ "$overdue" -eq 0 ] && [ "$gates" -eq 0 ] && exit 0

{
  echo "HumanGated — human judgment is pending in this project."
  echo
  if [ "$waiting" -gt 0 ]; then
    echo "$waiting response(s) answered and never pulled. Tell the user before you"
    echo "start something else, and offer to pull:"
    printf '%s' "$digest" | jq -r '
      .attention[]? |
      "  /hgd-pull \(.request_uuid)   \(.reviewer) on \(.artifact.name)" +
      (if .disposition then " — ruled \(.disposition)" else "" end) +
      (if (.resume_note // "") != "" then "\n      resume note: \(.resume_note)" else "" end)'
  fi
  if [ "$overdue" -gt 0 ]; then
    echo
    echo "$overdue ask(s) past their declared deadline. What happens next was"
    echo "declared when the ask was opened — an expired ask is unopposed or"
    echo "abandoned, NEVER approved. Do not report silence as agreement."
    printf '%s' "$digest" | jq -r '.overdue[]? | "  \(.request_uuid)  \(.reviewer) — \(.declared)"'
  fi
  if [ "$gates" -gt 0 ]; then
    echo
    echo "$gates open gate(s) recorded in .humangated/BLOCKED. Work inside their"
    echo "declared scope is refused by a hook — that is expected, not a bug."
  fi
  [ "$open_asks" -gt 0 ] && { echo; echo "$open_asks ask(s) still out with humans."; }
} > /tmp/hgd-session-$$ 2>/dev/null

jq -n --rawfile ctx /tmp/hgd-session-$$ '{hookSpecificOutput:{
  hookEventName:"SessionStart", additionalContext:$ctx
}}' >&3 2>/dev/null
rm -f /tmp/hgd-session-$$
exit 0
