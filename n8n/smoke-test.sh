#!/usr/bin/env bash
# Read-only smoke test for the Optofarm n8n webhooks.
#
#   export OPTOFARM_WEBHOOK_SECRET=...   # n8n credential "Optofarm Webhook Secret"
#   ./n8n/smoke-test.sh
#
# Everything here is READ-ONLY or a guard path that changes nothing. It deliberately does NOT book:
# a booking writes a real record into the live clinic system. If you do test a booking, use an
# obviously fake phone (07000000xx) and a "TEST ..." name, then cancel it and check availability is
# back to its baseline.
set -euo pipefail

BASE="https://n8n.splitagency.biz.id/webhook"
: "${OPTOFARM_WEBHOOK_SECRET:?set OPTOFARM_WEBHOOK_SECRET (n8n credential 'Optofarm Webhook Secret')}"

call() { # call <path> <json>
  curl -s -X POST "$BASE/optofarm-$1" \
    -H "Content-Type: application/json" \
    -H "X-Optofarm-Secret: $OPTOFARM_WEBHOOK_SECRET" \
    -d "$2"
}
show() { python3 -m json.tool 2>/dev/null || cat; }

echo "== 1. auth: wrong secret must be rejected by n8n before the workflow runs =="
curl -s -o /dev/null -w "   HTTP %{http_code} (expect 403)\n" -X POST "$BASE/optofarm-check-availability" \
  -H "Content-Type: application/json" -H "X-Optofarm-Secret: wrong" -d '{}'

echo "== 2. check_availability (read-only) =="
call check-availability '{"doctor":"Baricz","location":"Fortuna"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   success:",d.get("success"),"| calendars:",len(d.get("results",[])),"| earliest:",d.get("earliest"))'

echo "== 3. check_availability, too vague -> too_many_matches =="
call check-availability '{"city":"Mures"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   error:",d.get("error"))'

echo "== 4. book with missing fields -> missing_fields, zero evolvo calls =="
call book-appointment '{"phone":"0700000099"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   error:",d.get("error"),"| missing:",len(d.get("missing",[])))'

echo "== 5. book without the read-back -> confirm_phone_first, nothing booked =="
call book-appointment '{"full_name":"TEST SMOKE","phone":"0700000099","date":"2030-01-01","time":"09:00","doctor":"Baricz","location":"Fortuna"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   error:",d.get("error"))'

echo "== 6. find_appointments on an unused number -> graceful found:false =="
call find-appointments '{"phone":"0700000099","phone_confirmed":true,"conversation_id":"smoke"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   found:",d.get("found"))'

echo "== 7. manage_appointment on an unused number -> refused, nothing changed =="
call manage-appointment '{"phone":"0700000099","date":"2030-01-01","action":"cancel","conversation_id":"smoke"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("   error:",d.get("error"),"(not_found here because the number has no records at all; a real one would hit confirm_appointment_first)")'

echo
echo "Done. Every call above either read data or was refused by a guard; nothing was written."
