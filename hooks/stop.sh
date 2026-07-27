#!/usr/bin/env bash
# Stop: catch judgment that landed mid-session.
#
# The gap this fills is narrow and real. A reviewer answers while the operator is
# doing unrelated work; the envelope badge never fires because nothing touched
# our API; SessionStart already ran an hour ago. Without this the answer waits
# for the owner-nudge email — which works, but means the loop closed by
# interrupting a human instead of informing the agent already sitting there.
#
# Throttled hard. Stop fires at the end of EVERY turn, and a review tool that
# makes a network call every time you finish a sentence is a review tool people
# rip out. One check per session per interval; anything unexpected exits silent.
set -uo pipefail

INTERVAL=${HGD_STOP_INTERVAL:-600}   # seconds

exec 3>&1
exec 1>&2

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "anon"')
STAMP="${TMPDIR:-/tmp}/hgd-stop-${SESSION//[^A-Za-z0-9_-]/}"
now=$(date -u +%s)
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$INTERVAL" ] && exit 0
fi
printf '%s' "$now" > "$STAMP" 2>/dev/null

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/humangated"
[ -f "$CFG/config" ] && . "$CFG/config" 2>/dev/null
[ -n "${HGD_TOKEN:-}" ] || exit 0
BASE="${HGD_BASE_URL:-https://humangated.ai}"

digest=$(curl -sS --max-time 5 "$BASE/api/inbox" \
  -H "Authorization: Bearer $HGD_TOKEN" \
  -H "X-HumanGated-Skills: 4.3.0" 2>/dev/null) || exit 0
waiting=$(printf '%s' "$digest" | jq -r '.counts.responses_waiting // 0' 2>/dev/null) || exit 0
[ "$waiting" -gt 0 ] 2>/dev/null || exit 0

lines=$(printf '%s' "$digest" | jq -r '.attention[]? |
  "  /hgd-pull \(.request_uuid)   \(.reviewer) on \(.artifact.name)" +
  (if .disposition then " — ruled \(.disposition)" else "" end)' 2>/dev/null)

jq -n --arg n "$waiting" --arg l "$lines" '{hookSpecificOutput:{
  hookEventName:"Stop",
  additionalContext:("HumanGated: \($n) response(s) came back while you were working. Say so before the user moves on.\n\($l)")
}}' >&3 2>/dev/null
exit 0
