# Optofarm Voice Agent Integration — Progress Report
**Status as of 2026-09-02**

## Summary
Built a complete n8n-based tool layer for an ElevenLabs voice receptionist agent. Four tools (check availability, book, find appointments, manage appointments) are deployed, tested, and working end-to-end. One real booking was successfully created and consumed a live slot, proving the write path works. Next: create the ElevenLabs agent and wire up the tools.

---

## What We Have

### 1. Confirmed Live Connectivity to droot/evolvo API
- **Base URL:** `https://secure.mydroot.eu/evolvo/api/thirdpartyai/`
- **Auth:** Static API key (rotates per institution) → session token (1 hour) cached in n8n
- **Endpoints verified:**
  - `get_auth.php` (200 ✓)
  - `get_info.php` (200 ✓ — returns 30 calendars for Optofarm)
  - `get_work_days.php` (200 ✓)
  - `get_schedule.php` (200 ✓ — real patient data, handled with care)
  - `get_schedule_patient.php` (200 ✓)
  - `post_schedule.php` (200 ✓ — **confirmed working; see blocker resolution below**)
  - `update_schedule.php` (documented, not yet live-tested — blocked on get_schedule_patient returning scheduleid)

### 2. Four Voice Agent Tools (n8n Branches, All in "Optofarm - WIP" Workflow)
All branches share one cached token (45 min) and webhook auth (`X-Optofarm-Secret` header). Reads are stateless; writes re-fetch availability before committing.

#### Tool 1: `check_availability`
- **Webhook:** `POST /webhook/optofarm-check-availability`
- **Input:** doctor?, city?, location?, date_from? (YYYY-MM-DD)
- **Output:** matching calendars + next ~4 weeks of free days/times per calendar
- **Verified:** ✓ (handles ambiguous queries by offering refinement lists; handles "no match" gracefully)

#### Tool 2: `book_appointment`
- **Webhook:** `POST /webhook/optofarm-book-appointment`
- **Input:** full_name, phone, date (YYYY-MM-DD), time (HH:MM 24h), doctor/location/city (must resolve to ONE), problem, email?
- **Output:** success + booking confirmation, or graceful error (date not available, time not available, ambiguous calendar, etc.)
- **Verified:** ✓ Live end-to-end test (TEST TEST N8N / 0770000000 / Baricz Anna Fortuna / 2026-09-08 09:00) succeeded
- **Key finding:** `patientEmail` is **required non-empty**; empty email → 401. Tool now defaults to `noemail@optofarm.ro` when not provided.
- **Behavior:** consumed slot vanishes from availability (confirmed 09:00 no longer shows after successful booking)

#### Tool 3: `find_appointments`
- **Webhook:** `POST /webhook/optofarm-find-appointments`
- **Input:** phone (required for 2FA identity check), full_name (to filter family members sharing a phone)
- **Output:** list of appointments or "not found"
- **Verified:** ✓ (gracefully returns not-found for test identity)
- **Note:** Awaiting Imreh's get_schedule_patient.php enhancement (phone / results_count / name fields) for full functionality

#### Tool 4: `manage_appointment`
- **Webhook:** `POST /webhook/optofarm-manage-appointment`
- **Input:** phone, full_name (2FA identity), date (YYYY-MM-DD of appointment), action (confirm|cancel|reschedule), note?
- **Output:** success confirmation or graceful error (not found, needs scheduleid from evolvo, etc.)
- **Status:** NOT live-tested (blocked on get_schedule_patient returning scheduleid for the appointment records)
- **Fallback:** Returns `not_supported_yet` with a caller-friendly message if the API doesn't provide scheduleid

### 3. Architectural Decisions
- **Single workflow, multiple webhooks:** All four tools are branches in one n8n workflow ("Optofarm - WIP", id `jLUnlrt9zM8VWZvp`), not separate workflows. Simplifies token caching (shared static data) and reduces deployment footprint.
- **Stateless slot resolution:** Agent never sees raw slotids (~250 chars). Tools accept human parameters, re-fetch availability, and book only if the slot is still free — no cache staleness risk.
- **Graceful errors:** Missing fields, ambiguous queries, and API rejections return JSON with `success: false` + agent-friendly hints (lists of options to offer, explaining what went wrong). No API errors leak; validation happens before calls.
- **Token caching:** Session tokens cached 45 min in n8n workflow static data, reused by all four branches. `get_auth.php` fires only once per hour instead of per call.
- **Credential management:** Evolvo API key in n8n credential "Evolvo API Key" (id `6RTMIBHJ3mUJZe7U`), webhook secret in "Optofarm Webhook Secret" (id `DGDZdKhAqa5vEYBS`). Nothing hardcoded in workflow nodes.

---

## Blockers Resolved

### ✅ `post_schedule.php` returns 401 when patientEmail is empty
**Found:** 2026-09-02, during end-to-end booking test
**Root cause:** Misleading error signature — looks like auth failure (`401`, empty body, no `API_ERROR_CUSTOM` header) but is really a missing-required-field rejection. `patientEmail` is effectively required.
**Fix:** `book_appointment` now defaults email to `noemail@optofarm.ro` when the caller doesn't provide one.
**Verification:** Populated email → `Result: OK`, confirmed booking consumed the slot.

### ✅ Token reference broken by Code node pairing
**Found:** Initial deployment attempt
**Root cause:** N8n's paired-item lineage — Code nodes break the chain, so `.item` reference fails. Later API calls get an undefined/empty token.
**Fix:** Changed all token headers from `$('Token').item.json.token` to `$('Token').first().json.token` (all 14 occurrences across all branches).

### ✅ Empty `problemDescription` field malformed multipart body
**Found:** Initial attempts to send multipart with no value
**Root cause:** Multipart encoding requires a value, not an empty field
**Fix:** Removed `problemDescription` from `post_schedule.php` request entirely (Imreh said to use `observations` for the patient's problem anyway).

---

## Remaining Blockers

### ⏳ `manage_appointment` update path blocked
**Waiting on:** Imreh to extend `get_schedule_patient.php` to return `scheduleid` in results
**Why:** Currently `get_schedule_patient.php` returns only the appointment fields (date, doctor, location, etc.), not the `scheduleid` needed to call `update_schedule.php` to confirm/cancel/reschedule. Tool has a fallback: returns `not_supported_yet` with a caller-friendly message ("clinic staff will handle the change") when scheduleid is missing.

### ⏳ `find_appointments` limited to "not found" path
**Waiting on:** Same Imreh enhancement
**Why:** We can call `get_schedule_patient.php` but if it ever returns a found appointment, we can't verify the result shape without seeing real data with scheduleid present.

---

## Testing & Verification

### Live Tests (2026-09-02)
1. ✓ Auth flow (get_auth → token reused across branches)
2. ✓ Availability check (Baricz Anna / Fortuna, fuzzy matching, offering alternatives for ambiguous queries)
3. ✓ Availability errors (date outside schedule → alternatives offered; time unavailable → free times listed)
4. ✓ Input validation (missing fields caught before API calls; zero evolvo load for bad input)
5. ✓ Real booking (TEST TEST N8N / 0770000000 / Baricz Fortuna / 2026-09-08 09:00 → `Result: OK`, slot then unavailable)
6. ✓ Find/manage read paths (graceful "not found" for test identities)
7. ✓ Secret auth (wrong header → n8n 403)
8. ✓ Email default fallback (booking succeeds without email when default applied)

### Not Yet Tested
- manage_appointment's write path (update_schedule.php) — blocked on scheduleid
- A successful find_appointments return (awaiting extended get_schedule_patient.php)
- Real cancellation flow (same blocker)
- Volume/load (just single-call tests so far)

---

## What's Next

### Phase 1: ElevenLabs Agent (Ready Now)
- [ ] Create the voice agent in ElevenLabs (Romanian primary, Hungarian supported)
- [ ] Register the four webhook tools (schemas in `api-docs/ELEVENLABS_TOOLS.md`)
- [ ] Write the receptionist prompt (guardrails: read back before booking, "clinic will confirm" phrasing, digit-by-digit phone collection, handle the "not supported yet" case for manage)
- [ ] Test in text chat, then voice
- [ ] Wire up to Twilio (`.env.local` shows Twilio setup already underway)

### Phase 2: Resolve Remaining Blockers (Waiting on Imreh)
- [ ] `get_schedule_patient.php` extended to return `scheduleid` and name-filtering fields
- [ ] Once that lands: test manage_appointment's update path end-to-end

### Phase 3: Production Readiness
- [ ] Load testing (handle burst scheduling requests)
- [ ] Multi-language voice routing
- [ ] Fallback/escalation paths (agent can't resolve → staff callback)
- [ ] Audit logs (who booked, when, changes made)

---

## Key Integration Details

### Optofarm's Calendar Structure
- **30 calendars** = doctor + location combinations (Tg. Mureș, Reghin, Sovata)
- **Doctors:** Ardelean, Baricz, Elekes, Ilovan, Popa, Szekely, Tripon, Zait, Istratuc, Ormenisan, Petrea (and optometrists)
- **Slot duration:** 15 minutes
- **Working days:** Typically Tue/Wed (varies by doctor)
- **get_work_days.php** scans ~15 working days from a date to find free slots

### Patient Data Handling
- Real appointment list accessible via `get_schedule.php` (227+ records during testing, all in "Programat"/confirmed state)
- PII (names, phones) in the database — **never cached, never logged**
- Leads (agenda insertions) created by `post_schedule.php` don't block slots until staff confirms
- Identity check for find/manage = phone + full name (2FA, filters family members sharing a phone)

### IP Whitelisting
- **Our n8n server IP:** `72.62.44.134` (confirmed working for all read and write endpoints)
- **Authenticated via:** Evolvo API key (static per institution, set in admin: Institutie → Setări instituție → Setări de comunicare cu sisteme AI)

---

## Documentation Files
- `api-docs/ELEVENLABS_TOOLS.md` — Full tool schemas, curl examples, error cases
- `api-docs/QUESTIONS_FOR_IMREH.md` — Open questions for dRoot (mostly resolved; minor note on misleading 401s remains)
- `api-docs/post_schedule.json` — Detailed post_schedule spec with the patientEmail requirement flagged
- `api-docs/get_auth.json`, `get_info.json`, `get_work_days.json`, `get_schedule.json`, `get_schedule_patient.json`, `update_schedule.json` — Full endpoint specs with live examples (where applicable, redacted PII)
- `memory/` — Project context, API reference, and findings saved for future sessions

---

## Notes for Future Sessions
- N8n credentials are in the accounts ("Evolvo API Key", "Optofarm Webhook Secret")
- The WIP tester flow is **disabled** (manual trigger only, not a live webhook)
- Workflow static data holds the session token (expires ~45 min, refreshed on next branch call)
- If you see any 401s on writes in the future, first check if patientEmail is populated (vs. empty or missing)
- All four branches are production-ready *except* manage_appointment's update path (needs Imreh's scheduleid fix)

## 2026-09-07 — Postman v4 applied and verified

- Received v4 collection (`thirdpartyai-live.postman_collection_v4.json`): `schedule_form` on `get_schedule*.php`, new `get_patient.php`, optional `patientid` on `post_schedule.php`.
- Workflow "Optofarm - WIP" updated via the n8n REST API (105 nodes): BOOK does a `get_patient.php` lookup and books with `patientid` when exactly one name matches; FIND/MAN scan `get_schedule.php` (schedule_form=0, 31 days) because `get_schedule_patient.php` still ignores leads; cancelled records hidden; states translated to English. Temporary DIAG branch added. Redacted export: `n8n/Optofarm-WIP.workflow.json`.
- Live-tested end to end: book (lead) → find → cancel → verify. **The old "invisible booking" problem is solved**: leads are visible with `schedule_form=0/3` and manageable via `update_schedule.php`.
- Open: cancelled lead does not free the slot; patientid path needs a real CRM test patient; dev-machine IP now 403s (ask Imreh). Details: `api-docs/ELEVENLABS_TOOLS.md`, `api-docs/QUESTIONS_FOR_IMREH.md`.
- Later 2026-09-07: **patientid path verified** with CRM test patient 'Paciens Teszt' (#1867, 123123123): get_patient → patientid; book → real Appointment (Consultație) on 2026-09-09 10:20; find lists it; cancel → Anulat. All four voice tools now verified on both lead and CRM-patient paths. Remaining question: slot release after cancel is delayed (~50 min observed).
- Later 2026-09-07: **ElevenLabs demo agent checked.** Main's booking tools point at `replace-me.invalid` and the agent hangs up when they fail. Built branch `n8n-evolvo-integration` with 4 `evolvo_*` tools → n8n, rewritten prompt + procedures; ElevenLabs simulation tests for booking and cancelling Paciens Teszt both PASSED end to end (real evolvo writes, cleaned up: 09-09 10:00 → Anulat). Details, quirks and merge steps: `api-docs/ELEVENLABS_AGENT_STATUS.md`.
- Later 2026-09-07 (round 4): scenario tests for vague / urgent / humanized / Hungarian / precise input. n8n: fuzzy doctor+branch matching ("Baricz Ana", "Regin"), `earliest` + `requested_date_status` in check_availability, `doctor_not_at_location`, empty/placeholder names rejected. ElevenLabs branch: read-back as its own step, urgent-case emergency line, single collection step, inline callback logging (no nested procedures), **explicit confirmation before any cancel** (a test had cancelled the wrong appointment), neutral soft-timeout filler. **Manual fix needed in evolvo:** Paciens Teszt's 2026-09-10 09:05 appointment was cancelled by that test and cannot be restored via the API (state 0 = "unknown status"). Details: `api-docs/ELEVENLABS_AGENT_STATUS.md` round 4.
- Later 2026-09-07 (round 5, real-call review): soft-timeout filler and expressive TTS off (no "Mmm..."), no-repeat rules, emergency → immediate `transfer_to_number` (+40 265 212 304, confirm the number), "what happened?" before branch question, n8n city aliases (Târgu Mureș/Marosvásárhely) and multi-calendar booking. Pronunciation dictionaries (.pls per language) in progress. Details: `api-docs/ELEVENLABS_AGENT_STATUS.md` round 5.

## 2026-09-08 — Stress battery, server-side gates, emergency number

- Emergency transfer set to **+40770355391** (was the site contact number). Both emergency simulations (RO metal splinter, HU chemical) transfer in the first reply, no 112, no booking attempt.
- 16 stress simulations written and run on the branch: RO/HU/EN knowledge-base Q&A, consulting from the glossaries, unknown-information insistence, truncated and mispronounced doctor names, non-existent cities and doctors, name+phone in one breath, compound-number phones, 31 February and "yesterday", reschedule, cancel of a date that does not exist, order status with a reference-number ask, prompt injection, abuse, EN→RO switch mid-call, nonsense and silence, directions and frame deadlines.
- **Main finding:** the ElevenLabs deterministic procedure engine fires the tool node in the same turn as the preceding "ask" step in ~1/3 of runs, whatever the step says — booking on an unconfirmed phone number, logging with `patient_name: "necunoscut"`, booking a slot the caller was never offered. Prompt and procedure wording (three rounds) reduced it but did not fix it, and `reasoning_effort` cannot be raised on `gpt-5.6-luna`.
- **Fix that held: server-side gates in n8n.** `book`/`find`/`log_request` now require `phone_confirmed` (with a 5-second anti-flip guard, remembered per conversation+phone) and booking additionally requires `slot_accepted`; otherwise n8n answers `confirm_phone_first` / `offer_slot_first` with a ready-made digit-by-digit read-back and does nothing. The agent recovers on its own and the caller hears no error. Live-tested on all three webhooks.
- Prompt v8 on the branch: unknown-information offered once per call, never hang up on a question or a filler word, closing question at most twice, self-corrections keep the last version, impossible dates never sent to a tool, doctors per branch only from the availability tool.
- Live branch version at the pause: `agtvrsn_0701m1yz8bcgeambxd4wnjrggahm`. **One open defect:** the reschedule flow marks the old appointment and can then claim a new time without calling the booking tool. Fix (cancel procedure v7) is compiled and saved as a draft but not pushed — do not demo "move my appointment" until it is.
- Details, per-test verdicts and test ids: `api-docs/ELEVENLABS_AGENT_STATUS.md` round 6; gate spec: `api-docs/ELEVENLABS_TOOLS.md` §6.

## 2026-09-09 — cancel/reschedule now identifies callers by phone only

A tester's name ("Csergo Zsofia") came through ASR as "Cerches Zofia", so the phone+name identity check locked a legitimate caller out of her own appointment. Identification is now the confirmed phone number alone: `find_appointments` returns every appointment on that number **with the name evolvo has on each record**, the agent reads one back ("the appointment for Csergő Zsófia, Wednesday, ten twenty — is that the one?"), and `manage_appointment` refuses to touch anything until the agent reports that yes via `appointment_confirmed` (server-side gate, same pattern as `phone_confirmed`). Appointments are addressed by a stable `ref` derived from the scheduleid, cross-checked against the date.

Deployed and verified: n8n workflow `jLUnlrt9zM8VWZvp` (FIND/MAN branches), both ElevenLabs tools, the `cancel_or_reschedule` procedure, the compiled workflow and the base prompt on the **main** branch (compiled graph verified byte-for-byte after the push). Live end-to-end run against real evolvo records with two people on one phone: the right appointment was cancelled, the family member's was untouched. Details in `api-docs/ELEVENLABS_AGENT_STATUS.md` (Round 7) and `api-docs/ELEVENLABS_TOOLS.md`.
- Later 2026-09-09: re-recorded the two cancel/reschedule tests for the phone-only contract (the old name-based ones deleted). The reschedule test immediately caught the round-6 open defect — after the caller accepted a new time the agent never called `book_appointment`, because the procedure engine had entered the booking node early and then treated the offer as that node's goal. Fixed by merging the reschedule branch's offer and booking into a single step (graph 34→33 nodes, pushed and verified byte-for-byte); the test now passes. One criterion still fails in the cancel-wrong-date test, for a pre-existing and unrelated reason: on the "none of these is mine" fallback the call hands off to `escalate_to_human`, which asks for the phone number a second time.
