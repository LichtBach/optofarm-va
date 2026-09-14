# N8N Workflow Architecture: Optofarm - WIP
**Workflow ID:** `jLUnlrt9zM8VWZvp`  
**URL:** `https://n8n.splitagency.biz.id`  
**Status:** Active (production-ready read paths + working write path; manage update blocked on Imreh)

---

## Overview
Single workflow containing:
- One **manual trigger** for the API tester chain (run via "Execute Workflow" button; no live URL)
- Four **webhook triggers**, one per voice agent tool, each starting a branch
- Shared token caching mechanism (workflow static data holds the session token, reused across all branches)
- 83 total nodes with prefix-based namespacing to avoid conflicts

All branches execute the same auth-and-cache pattern before reaching their tool-specific logic.

---

## Shared Infrastructure

### Token Caching (Workflow Static Data)
**Purpose:** Minimize auth calls (evolvo tokens last 1 hour; we cache for 45 min then refresh).

**Implementation:**
- Every branch starts with an **"Auth Cache"** node (Code: JavaScript)
  - Checks if `sd.token` exists in workflow static data and is < 45 min old
  - If yes, returns the cached token (needs_auth = false)
  - If no, signals needs_auth = true, triggering a fresh call to get_auth.php
- **"Need Auth?" node** (If: conditional branch)
  - `true` → calls get_auth.php
  - `false` → skips to reuse cached token
- **"Store Token"** node (Code: after get_auth.php)
  - Parses the response, stores `token` + `tokenTs` into workflow static data
  - Returns the token for the rest of the branch
- **"Token OK?" node** (If: guards against auth failure)
  - Checks if token is valid; routes to Error Out if not
  - Otherwise chains to the branch's tool-specific logic

**All branches share this pattern with prefix-namespaced nodes:**
- CA (check_availability): CA Auth Cache, CA Need Auth?, CA get_auth.php, CA Store Token, CA Token, CA Token OK?
- BOOK (book_appointment): BOOK Auth Cache, BOOK Need Auth?, BOOK get_auth.php, BOOK Store Token, BOOK Token, BOOK Token OK?
- FIND (find_appointments): FIND Auth Cache, FIND Need Auth?, FIND get_auth.php, FIND Store Token, FIND Token, FIND Token OK?
- MAN (manage_appointment): MAN Auth Cache, MAN Need Auth?, MAN get_auth.php, MAN Store Token, MAN Token, MAN Token OK?

---

## Branch: check_availability (CA)

**Webhook trigger:** `POST /webhook/optofarm-check-availability`

### Node Flow
1. **CA Webhook** → receives JSON body: {doctor?, city?, location?, date_from?}
2. **CA Validate Input** (Code)
   - Parses date_from (defaults to tomorrow if missing or in past)
   - Fuzzy normalizes doctor/city/location (lowercase, diacritics off)
   - Returns validated params
3. **CA Input OK?** (If: checks for errors)
4. **[Auth chain: CA Auth Cache → CA Need Auth? → ... → CA Token OK?]**
5. **CA get_info.php** (HTTP POST with cached token)
   - Calls `/get_info.php` with `lng=1`
   - Returns 30+ calendars for Optofarm
6. **CA Match Calendars** (Code)
   - Fuzzy-matches calendars by doctor/city/location
   - Returns error if no match, too many matches, or ambiguous
   - Success returns ONE calendar entry per match (up to 4 recommended)
7. **CA Match OK?** (If: gates non-error matches)
8. **CA get_work_days.php** (HTTP POST, multi-branch for each calendar)
   - Calls `/get_work_days.php` per matched calendar with calendarid + date_from
   - Each calendar gets its own slotid list
9. **CA Format Slots** (Code)
   - Aggregates results from all calendars
   - Returns `success: true` + `results[]` with available_days per calendar
   - Limits to first 4 weeks and 8 slots per day (agent-readable)

**Response:**
```json
{
  "success": true,
  "date_searched_from": "2026-09-03",
  "results": [
    {
      "doctor": "Dr. Baricz Anna",
      "location": "Tg. Mures, Fortuna",
      "slot_duration_minutes": 15,
      "available_days": [
        {
          "date": "2026-09-08",
          "free_times": ["09:00", "09:15", ..., "10:45"],
          "total_free_slots": 8
        },
        ...
      ]
    }
  ]
}
```

---

## Branch: book_appointment (BOOK)

**Webhook trigger:** `POST /webhook/optofarm-book-appointment`

### Node Flow
1. **BOOK Webhook** → receives: {full_name, phone, date, time, doctor?, location?, city?, problem?, email?}
2. **BOOK Validate Input** (Code)
   - Validates required fields (name, phone, date YYYY-MM-DD, time HH:MM 24h, at least one of doctor/location/city)
   - Normalizes phone (strips spaces, dashes)
   - **Defaults email to `noemail@optofarm.ro` if empty or invalid** ← critical fix for 401s
   - Validates date is not in the past
   - Returns clean error list if missing fields
3. **BOOK Input OK?** (If)
4. **[Auth chain: BOOK Auth Cache → BOOK Need Auth? → ... → BOOK Token OK?]**
5. **BOOK get_info.php** (HTTP POST)
   - Gets current calendar list
6. **BOOK Match Calendars** (Code)
   - Fuzzy-matches doctor/location/city
   - **Must resolve to EXACTLY ONE calendar** (else returns `ambiguous_calendar` error with candidates)
7. **BOOK Match OK?** (If)
8. **BOOK get_work_days.php** (HTTP POST)
   - Fetches fresh availability for the matched calendar, starting from the requested date
9. **BOOK Find Slot** (Code)
   - Looks up the exact requested date and time
   - Returns errors if date not available or time not in the free list
   - Returns the slotid if found
10. **BOOK Slot OK?** (If)
11. **BOOK post_schedule.php** (HTTP POST)
    - Calls `/post_schedule.php` with:
      - lng=1
      - slotid (from BOOK Find Slot)
      - patientName, patientEmail (populated, never empty), patientPhone
      - problemDescription="" (empty, per Imreh note: use observations instead)
      - observations (patient's problem, from input)
    - **Response: `{"Result":"OK"}` on success, `{"Result":"ERROR","errorcode":N}` on failure**
12. **BOOK Format Booking** (Code)
    - Handles both success and 401 error cases
    - **401 with no API_ERROR_CUSTOM header** → returns `write_rejected_401` (was misleading as "slot taken"; now honest)
    - **Success** → returns booking confirmation with doctor, location, date, time, patient name/phone
    - Note to agent: "Tell the caller the clinic will confirm it"

**Response (success):**
```json
{
  "success": true,
  "booked": {
    "doctor": "Dr. Baricz Anna",
    "location": "Tg. Mures, Fortuna",
    "date": "2026-09-08",
    "time": "09:00",
    "patient": "TEST TEST N8N",
    "phone": "0770000000"
  },
  "note": "Booking registered. Tell the caller the clinic will confirm it."
}
```

**Response (slot unavailable at check time):**
```json
{
  "success": false,
  "error": "time_not_available",
  "requested": "2026-09-08 20:00",
  "free_times_that_day": ["09:00", "09:15", ..., "10:45"],
  "hint": "Offer the caller one of the free times."
}
```

---

## Branch: find_appointments (FIND)

**Webhook trigger:** `POST /webhook/optofarm-find-appointments`

### Node Flow
1. **FIND Webhook** → receives: {phone, full_name}
2. **FIND Validate Input** (Code)
   - Validates both phone and full_name present (2FA identity check)
   - Normalizes phone
   - Returns error if missing
3. **FIND Input OK?** (If)
4. **[Auth chain: FIND Auth Cache → FIND Need Auth? → ... → FIND Token OK?]**
5. **FIND get_schedule_patient.php** (HTTP POST)
   - Calls `/get_schedule_patient.php` with phone
   - Returns `{"Result":"NOTFOUND"}` or an array/object of appointment records
6. **FIND Format Results** (Code)
   - If NOTFOUND: `success: true, found: false, message: "No appointments found..."`
   - If records found:
     - Filters by full_name (case-insensitive, diacritics-off, word-based matching)
     - If name matches any records: returns `found: true, appointments: [{ref, date, doctor, location, type, state}, ...]`
     - If name matches none: returns `found: true, found: false` (records exist for this phone but not this name — suggests family member confusion)

**Response (not found):**
```json
{
  "success": true,
  "found": false,
  "message": "No appointments found for this phone number."
}
```

**Response (found, awaiting Imreh's scheduleid):**
```json
{
  "success": true,
  "found": true,
  "appointments": [
    {
      "ref": 1,
      "date": "2026-09-15 10:00:00",
      "doctor": "Dr. Baricz Anna",
      "location": "Tg. Mures, Fortuna",
      "type": "Consultație",
      "state": "Programat"
    }
  ]
}
```

---

## Branch: manage_appointment (MAN)

**Webhook trigger:** `POST /webhook/optofarm-manage-appointment`

### Node Flow
1. **MAN Webhook** → receives: {phone, full_name, date YYYY-MM-DD, action (confirm|cancel|reschedule), note?}
2. **MAN Validate Input** (Code)
   - Validates all required fields
   - Maps action to evolvo state: confirm→1, cancel→2, reschedule→3
   - Returns error if missing
3. **MAN Input OK?** (If)
4. **[Auth chain: MAN Auth Cache → MAN Need Auth? → ... → MAN Token OK?]**
5. **MAN get_schedule_patient.php** (HTTP POST)
   - Calls `/get_schedule_patient.php` with phone
6. **MAN Find Target** (Code)
   - Searches for an appointment matching full_name + date
   - Returns `not_found` if no appointment exists for this name+date
   - Returns `not_supported_yet` if an appointment is found but has no `scheduleid` field
     - (This happens until Imreh extends the API to return scheduleid)
     - Agent hint: "Tell the caller clinic staff will handle the change"
   - Success case: returns `scheduleid, state, obs, action, summary{date, doctor, location}`
7. **MAN Target OK?** (If)
8. **MAN update_schedule.php** (HTTP POST)
   - Calls `/update_schedule.php` with scheduleid, state, obs
   - (Not yet live-tested; gated on Imreh returning scheduleid)
9. **MAN Format Update** (Code)
   - Success: returns action confirmation (confirm/cancel/reschedule done)
   - Failure: returns error with API response

**Response (not supported yet, awaiting scheduleid):**
```json
{
  "success": false,
  "error": "not_supported_yet",
  "message": "The clinic API does not yet expose the id needed to modify this appointment. Tell the caller the clinic staff will handle the change and their request has been noted."
}
```

---

## Branch: Tester (Manual Trigger)

**Trigger:** "Execute Workflow" button in the n8n editor (no live webhook URL)

### Purpose
Chain the full API flow (auth → get_info → get_work_days → post_schedule/get_schedule/get_schedule_patient) and return a summary JSON showing each step's result and status code.

### Nodes
1. **Manual Trigger (tester)** — starts the chain
2. **get_auth.php, Extract Token** — fetch and cache token
3. **get_info.php, Extract Calendar** — get first calendar (Baricz Anna / Fortuna)
4. **get_work_days.php, Extract Slot** — fetch free slots, pick first (e.g., 2026-09-08 09:00)
5. **post_schedule.php (BAD desc)** — attempt booking with free-text problem description (demonstrates validation)
6. **post_schedule.php (GOOD desc)** — retry same slot with a calendar-provided problem option (would fail if slot is now taken — demonstrates slot consumption)
7. **get_schedule.php** — list appointments in the window (check if booking appears)
8. **get_schedule_patient.php** — lookup by phone (check if booking is findable)
9. **Build Summary** — aggregate all results into one JSON response

**Output:**
```json
{
  "step1_auth": {"status": 200, "got_token": true},
  "step2_calendar_used": {"name": "Dr. Baricz Anna", "workstation": "Tg. Mures, Fortuna"},
  "step3_slot_used": {"wday": "2026-09-08", "slot": "09:00"},
  "step4_post_schedule_bad_problemDescription": {"status": 200, "body": {"Result": "ERROR", "errorcode": 1}},
  "step5_post_schedule_valid_problemDescription": {"status": 200, "body": {"Result": "OK"}},
  "step6_get_schedule_lookup": {"status": 200, "total_records_in_window": 55, "found_our_test_booking": false},
  "step7_get_schedule_patient_lookup": {"status": 200, "body": {"Result": "NOTFOUND"}},
  "conclusion": "Booking created (Result:OK) but NOT retrievable via get_schedule.php or get_schedule_patient.php - confirms the gap reported to Imreh."
}
```

---

## Credentials & Environment

### N8N Credentials
- **Evolvo API Key** (id: `6RTMIBHJ3mUJZe7U`)
  - Type: httpHeaderAuth
  - Header: `Authorization: Bearer <institution API key>`
  - **Value (from admin):** Generated in droot/evolvo: Institutie → Setări instituție → Setări de comunicare cu sisteme AI → Generează cheia API

- **Optofarm Webhook Secret** (id: `DGDZdKhAqa5vEYBS`)
  - Type: httpHeaderAuth
  - Header: `X-Optofarm-Secret: <webhook secret>`
  - Value: Random secret; should be rotated monthly or when team members leave

### Workflow Static Data (Runtime)
Holds the cached session token:
```json
{
  "token": "<long opaque string>",
  "tokenTs": <epoch ms when token was fetched>
}
```

Updated by `Store Token` nodes; read by `Auth Cache` nodes. TTL enforced: if token is > 45 min old, a fresh call to `get_auth.php` replaces it.

---

## Error Handling Strategy

All branches follow a consistent error pattern:

1. **Input validation errors** → return before any API call
   - Structure: `{"success": false, "error": "<error_type>", ...hints and options...}`
   - Common types: `missing_fields`, `invalid_date`, `ambiguous_calendar`, `no_match`

2. **API errors** → pass through with agent-friendly hint
   - Structure: `{"success": false, "error": "<error_from_api>", "status": <http_code>, ...}`
   - Examples: `date_not_available`, `time_not_available`, `not_found`, `not_supported_yet`

3. **Success** → return `success: true` with confirmation or list

4. **Auth errors or malformed responses** → `Error Out` node (final fallback)
   - Returns: `{"_error": true, "success": false, "error": "...", "hint": "..."}`

All errors include a **hint** field written FOR THE AGENT to read to the caller ("Offer the caller...").

---

## Performance & Reliability

### Token Reuse
- Single call to `get_auth.php` per hour (or when token expires)
- All subsequent reads in that window reuse the cached token
- Reduces latency for availability checks (no auth overhead) and reduces load on evolvo's auth endpoint

### Graceful Degradation
- Validation happens before API calls (zero evolvo load for bad input)
- Each branch is independent (one failure doesn't cascade)
- No blocking retries; errors are terminal (agent decides next step)

### IP Whitelisting
- N8n outbound IP: `72.62.44.134`
- Whitelisted in droot/evolvo admin for both read and write endpoints
- No rate-limiting observed (tested with ~50 calls in one session)

---

## Known Limitations & Future Work

### Limitations (As of 2026-09-02)
1. **manage_appointment update path blocked**
   - Requires `scheduleid` from `get_schedule_patient.php`
   - Imreh is extending the API; once ready, re-enable this branch's write

2. **find_appointments only confirmed on "not found"**
   - Same blocker; need to verify what a found appointment looks like with scheduleid

3. **No volume load testing**
   - Single-call tests only; concurrent burst behavior unknown
   - Recommend testing under realistic voice-agent call load before production

### Future Enhancements
- [ ] Add a "get patient history" tool (medical notes, prior visits)
- [ ] Extend manage_appointment to support rescheduling without manual re-entry (offer next available times)
- [ ] Cache availability for a few minutes to speed up rapid checks (e.g., agent asking "any earlier slots?")
- [ ] Implement appointment-confirmation workflow (auto-SMS/email after agent books)

---

## Deployment Checklist

- [x] All four branches deployed and active
- [x] Token caching tested and working
- [x] Input validation tested (no API calls on bad input)
- [x] Read endpoints verified (check_availability, find_appointments)
- [x] Write endpoint verified (book_appointment succeeds and consumes slot)
- [x] Error handling tested (wrong secret, missing fields, slot unavailable)
- [x] Email default fallback implemented
- [x] Token `.first()` reference fix (paired-item chain corrected)
- [ ] ElevenLabs agent created and wired up (next phase)
- [ ] Imreh delivers scheduleid for manage_appointment (blockers can close)
- [ ] Production load testing (before going live with voice)

---

## Maintenance Notes

### Adding a new tool (example: analytics)
1. Create a new webhook node: `POST /webhook/optofarm-analytics`
2. Prefix all sub-nodes with `ANALYTICS` (e.g., `ANALYTICS Webhook`, `ANALYTICS Validate Input`, `ANALYTICS Auth Cache`, ...)
3. Follow the standard auth chain pattern
4. Connect to existing evolvo endpoints as needed
5. Return consistent error/success JSON format

### Monitoring
- **N8N UI:** Executions tab shows per-webhook call success rate and latency
- **Evolvo API:** No monitoring provided; rely on response codes
- **Voice agent logs:** ElevenLabs will capture tool call success/failure (once agent is built)

### Rotating credentials
- **Webhook secret:** Update in n8n credential, re-deploy workflow (no downtime)
- **Evolvo API key:** Request new key from droot/evolvo admin, update credential, re-deploy (old key stays valid for ~1 hour of cached tokens)

---

## Links & References
- **N8N Workflow URL:** https://n8n.splitagency.biz.id/home/workflows/jLUnlrt9zM8VWZvp
- **Evolvo Base URL:** https://secure.mydroot.eu/evolvo/api/thirdpartyai/
- **Tool Schemas:** `/api-docs/ELEVENLABS_TOOLS.md` (curl examples, response shapes)
- **Endpoint Specs:** `/api-docs/*.json` (per-endpoint details)
- **Integration Progress:** `/INTEGRATION_PROGRESS.md` (this session's findings and next steps)

## v4 additions (2026-09-07) — supersedes the node lists above where they differ

- **BOOK:** `… → BOOK Slot OK? → BOOK get_patient.php → BOOK Match Patient → BOOK Patient OK? → BOOK Has Patient? → [BOOK post_schedule.php (patient) | BOOK post_schedule.php] → BOOK Format Booking`. The two post_schedule nodes are identical except the `(patient)` one adds `patientid` — kept as two nodes so an empty `patientid` is never sent.
- **FIND:** `… → FIND get_schedule_patient.php (+schedule_form=0) → FIND Scan Windows → FIND get_schedule.php (runs 5× , schedule_form=0) → FIND Format Results` (merges both sources, dedupes by scheduleid, phone-matches on the last 9 digits, name-filters, drops `Anulat`).
- **MAN:** same scan chain, then `MAN Find Target → MAN Target OK? → MAN update_schedule.php → MAN Format Update`.
- **DIAG:** `DIAG Webhook (optofarm-diag-v4) → auth chain → get_schedule ×3 → get_schedule_patient → get_patient → DIAG Summary`. Temporary, read-only.
- Deploying via REST: `PUT /api/v1/workflows/{id}` with `{name,nodes,connections,settings,staticData}`; a **new webhook node needs an explicit `webhookId`** and the workflow must be deactivated/activated afterwards or n8n answers 404 "webhook not registered".
- Current export (API key redacted): `n8n/Optofarm-WIP.workflow.json`.

## Phone-only identification (2026-09-09) — FIND / MAN

- **FIND** no longer filters by name. `FIND Format Results` returns every non-cancelled record for the phone, each with `ref` (4-char base36 hash of the `scheduleid`, stable across calls), `person` (the name on the record), `date`, `time`, `doctor`, `location`, `state`, `kind`, `manageable`, plus `count`, `persons[]` and a `next_step` instruction for the agent.
- **MAN** takes `ref` (or `date` as a fallback) instead of a name. `MAN Find Target` resolves the target, refuses `ambiguous_appointment` if a bare date matches several records and `ref_date_mismatch` if ref and date disagree, and then enforces an **`appointment_confirmed` gate** — the same server-side read-back pattern as `phone_confirmed`, keyed on `conversation_id|ref|action` in workflow static data with a 5-second replay guard — before `MAN update_schedule.php` can run.
- Both gates live in workflow static data (`sd.phoneGate`, `sd.apptGate`), entries expire after 2 hours.
- Deploy note (re-confirmed 2026-09-09): `PUT /api/v1/workflows/{id}` with `{name,nodes,connections,settings}` works on the live workflow without deactivating it, as long as no new webhook node is added.
