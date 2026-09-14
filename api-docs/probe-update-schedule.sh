#!/usr/bin/env bash
# Probe evolvo update_schedule.php for hard-delete support.
#
# SAFETY CONTRACT (from the authorising instruction, 2026-09-14):
#   - max ONE request per 15s, enforced across invocations via a timestamp file
#   - NO retries, NO parallel calls, NO loops
#   - a plain-HTML 403 => write STOP sentinel, refuse all further calls, report to the human
#   - only ever touch a scheduleid created by this script (recorded in state/created_scheduleid)
#
# Credentials come from the ENVIRONMENT so they never enter a chat transcript:
#   EVOLVO_API_KEY  - institution API key, the Bearer for get_auth.php
# Optional:
#   PROBE_DIR       - where state/logs go (default: ./.probe)
#
# Usage (one step per invocation, inspect between each):
#   ./probe-update-schedule.sh auth
#   ./probe-update-schedule.sh calendars
#   ./probe-update-schedule.sh workdays <calendarid> <YYYY-MM-DD>
#   ./probe-update-schedule.sh book <slotid>
#   ./probe-update-schedule.sh schedule <YYYY-MM-DD>
#   ./probe-update-schedule.sh try-state <scheduleid> <state>
#   ./probe-update-schedule.sh try-param <scheduleid> <key> <value>
#   ./probe-update-schedule.sh finalise <scheduleid>      # sets state=2 (ANULAT)

set -euo pipefail

BASE="https://secure.mydroot.eu/evolvo/api/thirdpartyai"
DIR="${PROBE_DIR:-$(cd "$(dirname "$0")" && pwd)/.probe}"
mkdir -p "$DIR"
STAMP="$DIR/last_request_epoch"
STOP="$DIR/STOP"
TOKEN_F="$DIR/session_token"
LOG="$DIR/probe.log"
MIN_GAP=15

TEST_NAME="TEST TEST N8N"
TEST_PHONE="0700000009"
TEST_EMAIL="test@test.com"
TEST_OBS="TEST hard-delete probe (authorised 2026-09-14) - delete me"

die() { echo "ERROR: $*" >&2; exit 1; }

guard() {
  [ -f "$STOP" ] && die "STOP sentinel present ($STOP). A previous call was blocked by the API. Refusing to continue. Human must inspect and remove it."
  local now last wait
  now=$(date +%s)
  if [ -f "$STAMP" ]; then
    last=$(cat "$STAMP")
    wait=$(( MIN_GAP - (now - last) ))
    if [ "$wait" -gt 0 ]; then
      echo "[rate-limit] waiting ${wait}s (min gap ${MIN_GAP}s)" >&2
      sleep "$wait"
    fi
  fi
  date +%s > "$STAMP"
}

# One request. No retries, ever. Body/status logged. Detects the Apache-403 lockout.
req() {
  local label="$1"; shift
  guard
  local out status body
  out=$(curl -sS -m 30 -w $'\n__STATUS__%{http_code}' "$@" 2>&1) || true
  status="${out##*__STATUS__}"
  body="${out%$'\n'__STATUS__*}"
  {
    echo "=== $(date -Iseconds) | $label | HTTP $status"
    echo "--- args: $* "
    echo "--- body:"; echo "$body"; echo
  } >> "$LOG"
  echo "HTTP $status"
  echo "$body"
  # plain-HTML 403 = whitelist lockout. Hard stop.
  if [ "$status" = "403" ] && printf '%s' "$body" | grep -qi '<html\|<!doctype'; then
    echo "LOCKOUT" > "$STOP"
    die "Plain-HTML 403 — IP appears blocked at the web-server layer. STOP sentinel written. Do NOT retry. Tell the human."
  fi
  printf '%s' "$body" > "$DIR/last_body.json"
  printf '%s' "$status" > "$DIR/last_status"
}

need_token() { [ -s "$TOKEN_F" ] || die "no session token — run: $0 auth"; cat "$TOKEN_F"; }
auth_hdr()   { echo "Authorization: Bearer $(need_token)"; }

# STOP is checked before anything else: command substitution in the case arms
# (e.g. $(auth_hdr)) is expanded before req/guard ever runs.
[ -f "$STOP" ] && die "STOP sentinel present ($STOP). A previous call was blocked by the API. Refusing to continue. Human must inspect and remove it."

cmd="${1:-}"; shift || true
case "$cmd" in
  auth)
    [ -n "${EVOLVO_API_KEY:-}" ] || die "EVOLVO_API_KEY not set in the environment."
    req "get_auth" -X POST "$BASE/get_auth.php" -H "Authorization: Bearer ${EVOLVO_API_KEY}"
    tok=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("token") or d.get("Token") or "")' "$DIR/last_body.json" 2>/dev/null || true)
    [ -n "$tok" ] || die "could not parse a token from the response — inspect $DIR/last_body.json"
    printf '%s' "$tok" > "$TOKEN_F"
    echo "[ok] session token stored in $TOKEN_F"
    ;;
  calendars)
    req "get_info" -X POST "$BASE/get_info.php" -H "$(auth_hdr)"
    ;;
  workdays)
    [ $# -ge 2 ] || die "usage: $0 workdays <calendarid> <YYYY-MM-DD>"
    req "get_work_days cal=$1 from=$2" -X POST "$BASE/get_work_days.php" -H "$(auth_hdr)" \
        -F "calendarid=$1" -F "date_from=$2"
    ;;
  book)
    [ $# -ge 1 ] || die "usage: $0 book <slotid>"
    req "post_schedule slot=$1" -X POST "$BASE/post_schedule.php" -H "$(auth_hdr)" \
        -F "lng=1" -F "slotid=$1" \
        -F "patientName=$TEST_NAME" -F "patientEmail=$TEST_EMAIL" -F "patientPhone=$TEST_PHONE" \
        -F "observations=$TEST_OBS"
    ;;
  schedule)
    [ $# -ge 1 ] || die "usage: $0 schedule <YYYY-MM-DD>"
    req "get_schedule at=$1" -X POST "$BASE/get_schedule.php" -H "$(auth_hdr)" \
        -F "atdate=$1" -F "interval=1" -F "schedule_form=0"
    ;;
  try-state)
    [ $# -ge 2 ] || die "usage: $0 try-state <scheduleid> <state>"
    grep -qx "$1" "$DIR/created_scheduleid" 2>/dev/null || die "refusing: $1 is not a scheduleid this script created (see $DIR/created_scheduleid)"
    req "update_schedule state=$2 sid=$1" -X POST "$BASE/update_schedule.php" -H "$(auth_hdr)" \
        -F "scheduleid=$1" -F "state=$2" -F "obs=$TEST_OBS"
    ;;
  try-param)
    [ $# -ge 3 ] || die "usage: $0 try-param <scheduleid> <key> <value>"
    grep -qx "$1" "$DIR/created_scheduleid" 2>/dev/null || die "refusing: $1 is not a scheduleid this script created"
    req "update_schedule $2=$3 sid=$1" -X POST "$BASE/update_schedule.php" -H "$(auth_hdr)" \
        -F "scheduleid=$1" -F "$2=$3" -F "obs=$TEST_OBS"
    ;;
  finalise)
    [ $# -ge 1 ] || die "usage: $0 finalise <scheduleid>"
    grep -qx "$1" "$DIR/created_scheduleid" 2>/dev/null || die "refusing: $1 is not a scheduleid this script created"
    req "update_schedule FINAL state=2 sid=$1" -X POST "$BASE/update_schedule.php" -H "$(auth_hdr)" \
        -F "scheduleid=$1" -F "state=2" -F "obs=$TEST_OBS (probe finished, left in ANULAT)"
    ;;
  record-sid)
    [ $# -ge 1 ] || die "usage: $0 record-sid <scheduleid>"
    echo "$1" >> "$DIR/created_scheduleid"; echo "[ok] $1 recorded as ours"
    ;;
  *)
    sed -n '1,30p' "$0"; exit 1;;
esac
