# ElevenLabs voice-agent tools → n8n webhooks (Optofarm)

All five tools live as separate branches inside the single n8n workflow **"Optofarm - WIP"** (id `jLUnlrt9zM8VWZvp`) on `https://n8n.splitagency.biz.id` — one webhook trigger per tool (node prefixes: `CA`, `BOOK`, `FIND`, `MAN`, `LOG` — `log_request` is §5 below), plus the original API tester chain, whose trigger is now a **manual trigger** (run it with "Execute workflow" in the editor; it no longer has a live URL, since it creates a real booking each run). Each tool is a POST webhook returning JSON. All requests **must** carry the auth header, or n8n rejects them with 403 before the workflow even runs:

```
X-Optofarm-Secret: $OPTOFARM_WEBHOOK_SECRET
Content-Type: application/json
```

(The secret value is deliberately **not** in this repository — it lives in the n8n credential "Optofarm Webhook Secret", and on the ElevenLabs side as a workspace secret referenced by each tool. Export it as `OPTOFARM_WEBHOOK_SECRET` to use the curl examples below.

The evolvo API key likewise lives in the n8n credential "Evolvo API Key" — nothing is hardcoded in the workflow. Session tokens are cached 45 min in the workflow's shared static data (all four branches reuse one token), so `get_auth.php` is called rarely.)

All tools return HTTP 200 with a JSON body; failures are expressed as `{"success": false, "error": "...", ...}` with hints written *for the agent* — the error payloads tell the LLM what to ask the caller next.

---

## 1. check_availability
`POST https://n8n.splitagency.biz.id/webhook/optofarm-check-availability`
Branch `CA` in workflow "Optofarm - WIP"

Ask the caller for city / preferred location / preferred doctor / date **before** calling.

| Param | Type | Notes |
|---|---|---|
| `doctor` | string, optional | e.g. "Baricz Anna" — partial names fine, diacritics ignored; since 2026-09-07 also **fuzzy** (token prefix / edit distance ≤1 for 3–4-letter tokens, ≤2 for longer), so "Baricz Ana", "Bariț Anna", "Regin" all match |
| `city` | string, optional | e.g. "Targu Mures", "Reghin", "Sovata" |
| `location` | string, optional | e.g. "Fortuna", "Postei" |
| `date_from` | string, optional | YYYY-MM-DD, must be future; defaults to tomorrow. For "in 2 months" requests pass that future date — the API then scans the next ~15 working days of the doctor's schedule from there |
| `provider_type` | string, optional | `doctor` or `optometrist` — **added 2026-09-11, not previously documented here.** Filters the calendars searched. Anything other than those two values is ignored (treated as unfiltered) rather than rejected. **Ignored entirely when `doctor` is given**, since naming a provider is more specific than naming a kind |

Success: `results[]` per matching calendar (max 4) with `available_days[]` (`date`, `date_spoken`, `relative_day`, `free_times[]` 24h, `total_free_slots`) and `slot_duration_minutes`; days with no free slot are dropped. Plus (added 2026-09-07):
- `earliest` — `{date, date_spoken, relative_day, time, doctor, location}`: the single earliest free slot across all matched calendars (the agent offers exactly this to urgent / "as soon as possible" / no-preference callers).
- when `date_from` was sent: `requested_date`, `requested_date_status` (`available` | `not_available`) and, if available, `requested_date_slots` (`{date, date_spoken, relative_day, time, doctor, location, free_times[]}` for that exact day).
- `today` (added 2026-09-15) — today's date in Bucharest, so the agent never has to infer it. `date_searched_from` defaults to **tomorrow** and evolvo's `get_work_days.php` rejects a non-future `date_from`, so **no slot this tool returns is ever today**: a same-day appointment cannot be offered through it at all.

Every result, plus `earliest` and `requested_date_slots`, also carries `provider_type` (`doctor` | `optometrist`). A top-level `provider_type_filter` echoes the filter **only when it actually ran** — naming a `doctor` bypasses the filter, so a missing echo is normal and must not be read as the filter having failed.

Errors: `no_match` (includes `available_doctors`/`available_locations` to offer — the agent offers at most three), `too_many_matches` (ask caller to narrow down), `doctor_not_at_location` (the doctor exists but not at the requested branch; carries `doctor_locations[]` and `doctors_at_requested_location[]`), and `no_provider_of_type` (the branch has no provider of the requested kind — e.g. Fortuna has no optometrist).

**How provider type is decided:** off the calendar-name prefix. Verified live on 2026-09-14 across all 30 calendars — 21 `Dr. …`, 9 `Optometrist …`, none unmatched. Every non-doctor is *explicitly* prefixed `Optometrist`; nothing is identified by the absence of "Dr.". The list is not static (it was 16 calendars on 2026-09-11), so re-verify after clinic changes. The mapping from *reason for the visit* to provider type is a prompt-side decision and is not made here — n8n only filters on what it is asked for.

## Speaking dates — `date_spoken` / `relative_day` (added 2026-09-15)

**Every date any of these tools returns carries two extra fields, and the agent must speak those rather than convert the ISO date itself.**

| Field | Example | Meaning |
|---|---|---|
| `date` | `2026-09-16` | the machine date — pass it back to `book_appointment` / `manage_appointment`, never read it aloud |
| `date_spoken` | `Wednesday 16 September` | weekday + day + month, in English, for the agent to **translate** into the caller's language |
| `relative_day` | `tomorrow` | one of `today`, `tomorrow`, `the day after tomorrow`, `in N days`, or `IN THE PAST - do not offer this` |

Why it exists: on a live call (2026-09-15 16:16, `conv_4701m2jk8460e2es63a4zbc5j21c`, n8n execution 1409) the webhook returned `earliest 2026-09-16 15:40` and the agent told the caller *"astăzi, marți 15 septembrie, ora 15:40"* — a slot 40 minutes in the **past**. When the caller declined, the next offer, `2026-09-17 10:00`, came out as *"mâine, miercuri 16 septembrie"*. Both were exactly one day early, weekday name included: the LLM was doing ISO→spoken date arithmetic and getting it wrong. n8n's data was correct in both cases, and — because `date_searched_from` was tomorrow — could not have contained anything for today.

The fields above remove the arithmetic. Every `note` / `next_step` / `read_back` string in these responses now also ends with the rule itself:

> *Never work out a date yourself and never re-read the ISO date: say `date_spoken` translated into the caller's language, and say today or tomorrow only when `relative_day` says so.*

Present on: `check_availability` (`earliest`, every `available_days[]` entry, `requested_date_slots`), `find_appointments` and `manage_appointment` (every `appointments[]` / `appointment` entry, and the `read_back` string), `book_appointment` (`booked`, `replaced_appointment`).

**Open on the ElevenLabs side:** nothing in the prompt tells the agent how to speak a date or forbids deriving one — the inline instruction in each tool result is the only thing steering it. One sentence in the appointment flow would close it, e.g. *"When you name a day, say the tool's `date_spoken` in the caller's language; call it today or tomorrow only if `relative_day` says so."*

## 2. book_appointment
`POST https://n8n.splitagency.biz.id/webhook/optofarm-book-appointment`
Branch `BOOK` in workflow "Optofarm - WIP"

Call **only after** the caller has confirmed all details out loud (read back name, phone, doctor, date, time).

| Param | Type | Notes |
|---|---|---|
| `full_name` | string, required | |
| `phone` | string, required | spaces/dashes stripped automatically |
| `date` | string, required | YYYY-MM-DD |
| `time` | string, required | HH:MM 24h (9:00 auto-padded to 09:00) |
| `doctor` / `location` / `city` | at least one | must resolve to exactly ONE calendar, else `ambiguous_calendar` error with the candidates |
| `problem` | string, optional | what the patient wants — goes into the API's **observations** field (per Imreh; NOT problemDescription) |
| `email` | string, optional | |

The workflow re-fetches the live slot list and books only if the exact date+time is still free — errors `date_not_available` / `time_not_available` include alternatives to offer the caller.
Success: `booked{...}` (carrying `date`, `date_spoken`, `relative_day`, `time`) + note that clinic staff will confirm. In evolvo this creates an "agenda insertion" (lead); if name+phone match an existing patient it becomes a real appointment tied to CRM history.

## 3. find_appointments
`POST https://n8n.splitagency.biz.id/webhook/optofarm-find-appointments`
Branch `FIND` in workflow "Optofarm - WIP"

Identity check = **the phone number alone**, dictated digit by digit (changed 2026-09-09 — see "Phone-only identification" below). The caller's name is neither asked for nor used.

| Param | Type | Notes |
|---|---|---|
| `phone` | string, required | digits as dictated |
| `phone_confirmed` | boolean, required | true only after the digit-by-digit read-back got a yes |
| `conversation_id` | string, auto | `system__conversation_id`, used for the gate |
| `full_name` | string, ignored | still accepted for backwards compatibility; it filters nothing |

Success: `found: true`, `count`, `persons[]` and `appointments[]`, each entry `{ref, person, date "YYYY-MM-DD", date_spoken, relative_day, time "HH:MM", doctor, location, type, state, kind, manageable}` plus a `next_step` sentence telling the agent to read one back and get a yes. `ref` is a short stable handle derived from the record's `scheduleid` — it survives between the find call and the manage call and does not shift when another record appears or disappears. `found: false` means the phone has nothing in the next 31 days; the hint tells the agent to ask about another number and never to ask for a name.

## 4. manage_appointment
`POST https://n8n.splitagency.biz.id/webhook/optofarm-manage-appointment`
Branch `MAN` in workflow "Optofarm - WIP"

Identifies the appointment by the `ref` from find_appointments plus the caller's explicit spoken confirmation.

| Param | Type | Notes |
|---|---|---|
| `phone` | required | the same number as the lookup |
| `ref` | required | from the appointments list; `date` is a fallback when no ref is available |
| `date` | required | date of that same appointment, YYYY-MM-DD — cross-checked against the ref |
| `action` | required | `confirm` \| `cancel` \| `reschedule` (→ evolvo state 1/2/3). There is **no undo**: evolvo rejects state 0 ("unknown status", verified 2026-09-07), so a cancelled record can only be set back to Programat by staff in the admin panel. |
| `appointment_confirmed` | boolean, required | true only after the agent named that one appointment (person, weekday, date, time) and the caller said yes |
| `note` | optional | goes into `obs` |
| `conversation_id` | string, auto | gate key |

**On a successful `cancel` the response carries `slot_released` (2026-09-14).** evolvo is re-queried
after the cancel and the answer reports what was actually found, instead of the agent inferring that
the time is bookable again:

| `slot_release_status` | `slot_released` | Meaning |
|---|---|---|
| `released` | `true` | the exact time is free again and can be booked immediately |
| `still_blocked` | `false` | it has not reappeared — do not offer that time |
| `unknown` | `false` | the whole day is absent from the calendar (fully booked, or not a working day) |
| `not_checkable_same_day` | `false` | the appointment was today; evolvo needs a future date to re-check |
| `check_failed` | `false` | the re-check itself failed |

The `note` is already phrased for the caller in every case, so reading it is sufficient. `confirm`
and `reschedule` do not free a slot and so do not carry these fields. Note that **absence from the
free list does not prove a slot is blocked** — a provider may simply not work then, which is why
`unknown` exists as a separate value.

Error answers that mean **nothing was changed**: `confirm_appointment_first` (with `appointment` + `read_back` to say out loud), `ambiguous_appointment` (several on the given date — includes the list), `ref_date_mismatch` (ref and date point at different records), `appointment_not_found`, `not_found`, `not_supported_yet`.

After `reschedule`, the agent runs check_availability + book_appointment for the new slot, reusing the `person` name from the confirmed appointment rather than asking the caller for one.

**Slot release on reschedule (2026-09-14).** evolvo state 3 (`Trebuie reprogramat`) does **not** release the old slot — only state 2 (cancel) does. So `reschedule` marks the record *and remembers it*; the old record is cancelled automatically by `book_appointment` once the replacement booking succeeds, in the same conversation. The booking response then carries `replaced_appointment {ref, person, date, date_spoken, time, doctor, location, cancelled}` and the `note` says the earlier appointment was cancelled and its slot released. **The agent must not call manage_appointment again to cancel the old one** — it is already gone.

The hand-off is keyed on `conversation_id` (both tools already send `system__conversation_id`) and additionally requires the booking phone to match the marked appointment's phone — so booking for a *different* number later in the same call never cancels the first person's appointment. If the call ends before a replacement is booked, the record simply stays at `needs_reschedule` holding its slot, which is the safe failure: staff see it and call back. Order matters: **mark first, then book.** Booking before marking leaves the old slot blocked.

### Lookup cost and the shared scan (2026-09-14)

`find_appointments` costs 6 evolvo calls (one patient lookup + five 7-day `get_schedule` windows),
because `get_schedule_patient.php` still does not return Agenda/lead records by phone. Within one
conversation that scan is now **shared**: `find_appointments` parks its records against
`conversation_id` + phone for 180 s and `manage_appointment` reuses them, skipping the scan entirely.
`manage_appointment` also narrows to the single 7-day window containing `date` when it has to scan
itself. A cancel that follows a lookup in the same call now costs 3 evolvo calls instead of 7.

This is invisible from the agent's side — same requests, same answers, just faster — but it is the
reason `conversation_id` matters on both tools. Without it every call misses the cache and falls back
to the full scan, which still works, only slower.

### Phone-only identification (2026-09-09)
The old identity check was phone **+ full name**, with fuzzy name matching in n8n. It failed in practice: a caller saying "Csergo Zsofia" came through as "Cerches Zofia", which no fuzzy match can rescue. Names are now out of the identification path entirely:

1. the agent asks only for the phone number and reads it back (unchanged `phone_confirmed` gate);
2. `find_appointments` returns **every** non-cancelled appointment on that number, each carrying the name evolvo has on the record;
3. the agent names one back — person, weekday, date, time — and must get an explicit yes;
4. `manage_appointment` refuses to change anything unless `appointment_confirmed` is true, answering `confirm_appointment_first` with the exact wording to read back (same server-side pattern as `phone_confirmed`, including the 5-second replay guard, because the procedure engine skips "ask" steps in roughly one run in three).

Consequence to keep in mind: a caller who dictates a number hears the names of everyone with an appointment on it. That is deliberate (one phone covers a family) but it is the one privacy trade-off in this design.

---

## Slot release — verified live 2026-09-14

Imreh reported that cancelling frees the reserved slot. Confirmed end to end against Dr. Baricz Anna / Fortuna / 2026-09-22:

| Action | Effect on the slot |
|---|---|
| book (lead **or** CRM-linked appointment) | blocked immediately |
| `cancel` (state 2) | **free again ~8 s later**, and genuinely re-bookable |
| `reschedule` (state 3) | **still blocked** — state 3 never releases it |
| `confirm` (state 1) | stays blocked (correct), state → `confirmed`, `ref` stable |

This retires the older note that release lagged ~50 minutes, and also retires "leads don't block the slot" — leads block instantly, exactly like real appointments.

Two defects found by that test and fixed in n8n the same day:
1. state 3 left the old slot consumed forever on every reschedule → the automatic hand-off described under manage_appointment above;
2. `Trebuie reprogramat` was missing from the Romanian→English state map in `FIND Format Results` / `MAN Find Target`, so the raw Romanian leaked to the agent. The map now also carries `trebuie reprogramat` → `needs_reschedule` and `reprogramat` → `rescheduled`.

New nodes in the BOOK branch: `BOOK Resched Pending?` (if) → `BOOK resched update_schedule.php` (http) → `BOOK Resched Done` (code, now the webhook's last node and therefore the responder). `BOOK Validate Input` additionally emits `conversation_id`; `MAN Format Update` writes the pending entry into workflow static data (`sd.pendingResched`, 6 h TTL); `BOOK Format Booking` consumes it (read-and-delete, so it can fire at most once).

## Smoke-test results (2026-09-02, all live)

- wrong secret → n8n `403` before workflow runs ✓
- book with missing fields → `missing_fields` list, **zero** evolvo API calls made ✓
- check_availability `{doctor: "Baricz", location: "Fortuna"}` → real slots (Mondays 09:00–10:45, 15-min slots, 4 weeks ahead) ✓
- check_availability `{city: "Mures"}` → `too_many_matches` + full doctor/location lists for the agent to offer ✓
- find_appointments TEST identity → graceful `found:false` ✓
- manage_appointment TEST identity → graceful `not_found` ✓

### ✅ RESOLVED — book_appointment now works end-to-end (2026-09-02)

A deliberate real booking (TEST TEST N8N / 0770000000 / Dr. Baricz Anna Fortuna / **2026-09-08 09:00**) **succeeded** (`Result: OK`) and the slot then disappeared from availability — confirming the write took effect end-to-end.

**Root cause of the earlier 401s:** `post_schedule.php` rejects an **empty `patientEmail`** with a `401` (empty body, no `API_ERROR_CUSTOM` header — misleading, looks like an auth error but is really a missing-required-field rejection). This is NOT a WAF/IP block (my earlier conclusion was wrong): the 401 carries evolvo's own app headers, and populating the email made it work immediately. `patientEmail` is effectively **required** and must be non-empty.

**Fix in the tool:** `book_appointment` now defaults `email` to `noemail@optofarm.ro` when the caller doesn't provide one, so a voice call never has to collect an email and never 401s on this.

Also fixed along the way (real bugs, not the 401 cause): token header referenced via n8n's paired-item `.item` — broken by intermediate Code nodes — switched all token headers to `.first()`; and the misleading "slot taken" message replaced with honest error reporting.

**Confirmed behavior:** a successful booking **consumes/blocks the slot** (09:00 vanished from availability afterward). So the agent prompt should treat a confirmed booking as real, though staff still finalize it.

**Cleanup needed (manual, in droot/evolvo admin):** the 2026-09-08 09:00 booking (TEST TEST N8N / 0770000000) is a real consumed slot and should be cancelled. (Plus the two earlier leftover leads: 0700000000 on 2026-09-01, 0700000009 on 2026-09-08.)

Still not verified: manage_appointment's update path (blocked until get_schedule_patient returns scheduleid).

## Curl examples

```bash
curl -X POST https://n8n.splitagency.biz.id/webhook/optofarm-check-availability \
  -H "Content-Type: application/json" \
  -H "X-Optofarm-Secret: $OPTOFARM_WEBHOOK_SECRET" \
  -d '{"doctor":"Baricz","location":"Fortuna"}'

curl -X POST https://n8n.splitagency.biz.id/webhook/optofarm-book-appointment \
  -H "Content-Type: application/json" \
  -H "X-Optofarm-Secret: $OPTOFARM_WEBHOOK_SECRET" \
  -d '{"full_name":"TEST TEST","phone":"0700000010","date":"2026-09-15","time":"09:00","doctor":"Baricz","location":"Fortuna","problem":"TEST - please ignore"}'
```

---

## Postman v4 — APPLIED to the workflow (2026-09-07, all live-tested)

Source: `thirdpartyai-live.postman_collection_v4.json`; endpoint docs in `api-docs/` (new `get_patient.json`); redacted export of the live workflow in `n8n/Optofarm-WIP.workflow.json`.

### What changed per tool
- **book_appointment (BOOK):** after the slot check, `BOOK get_patient.php` looks the phone up. Exactly one name match → `BOOK post_schedule.php (patient)` sends `patientid` (evolvo then ignores name/email/phone and books a real appointment). No match / lookup failure / name mismatch → the original lead path. Several matches → `ambiguous_patient` error with `candidates[]`. Response gained `booking_mode` (`appointment_linked_to_existing_patient` | `lead_pending_staff_confirmation`) and `patient_match` (`existing_patient` | `new_patient` | `phone_known_name_mismatch` | `name_unverifiable` | `lookup_failed`); the `note` text differs per mode — read it to the caller.
- **find_appointments (FIND) / manage_appointment (MAN):** `get_schedule_patient.php` now sends `schedule_form=0`, BUT it still does not return leads by phone (verified). So both branches additionally scan `get_schedule.php` (`schedule_form=0`, 5 windows = today…+31 days) and match by phone client-side (name filtering was removed 2026-09-09). Cancelled records (`Anulat`) are hidden. Each appointment now carries `kind` (`appointment` | `request_pending_staff_confirmation`), `manageable` (has scheduleid) and an English `state` (`scheduled`, `confirmed`, `cancelled`, `completed`, `no_show`). Cost: 6 evolvo calls per lookup instead of 1.
- **manage_appointment:** the `not_supported_yet` path is effectively retired — leads have scheduleids and `update_schedule.php` accepts them.
- **DIAG branch (temporary):** `POST /webhook/optofarm-diag-v4` (same secret) body `{phone, atdate, interval}` → runs get_schedule ×3 (schedule_form 3/1/0), get_schedule_patient (3) and get_patient, and returns only TEST records + shape/state stats. Safe to delete once v4 is settled.

### Live test log (2026-09-07, all through the production webhooks)
1. find_appointments TEST TEST N8N / 0770000000 before booking → `found:false` (old test leads already removed by staff).
2. book_appointment Dr. Baricz Anna, "Doja", **2026-09-09 10:00** (first free slot that day) → `success`, `patient_match: new_patient` (get_patient → NOTFOUND), lead path, 10:00 vanished from check_availability.
3. find_appointments same identity → `found:true`, kind `request_pending_staff_confirmation`, `manageable:true`; wrong name → name-mismatch message.
4. manage_appointment cancel → `success`; DIAG shows the record state `Anulat`.
5. find_appointments again → `found:false` (cancelled hidden); manage on it → `not_found`.

### CRM test patient run (2026-09-07, later the same day) — patientid path VERIFIED
Test patient in evolvo: **Paciens Teszt**, #1867, phone `123123123`, with a manually created Consultație on 2026-09-10 09:05 (left untouched).
1. DIAG → `get_patient.php` returns `[{name, phone, patientid}]`; `get_schedule_patient.php` with `schedule_form=0` returns the 09-10 appointment (same record shape as get_schedule, `form: "Appointment"`); with `3` → NOTFOUND.
2. find_appointments → `found:true`, the 09-10 appointment, `kind: appointment`, `manageable: true`.
3. book_appointment Dr. Baricz Anna / Doja / **2026-09-09 10:20** → `success`, `booking_mode: appointment_linked_to_existing_patient`, `patient_match: existing_patient`. evolvo shows it as `form: Appointment`, `type: Consultație`, slot consumed.
4. find_appointments → both appointments listed, sorted by date.
5. manage_appointment cancel 2026-09-09 → `success`; evolvo state `Anulat`; find_appointments shows only the 09-10 one again.

### Still open
- **Slot release after cancel is not immediate.** Both cancelled records kept their slot blocked right after the cancel, but the first one's 10:00 slot was free again about 50 minutes later. Ask Imreh whether release is delayed or staff-driven.
- The old API-tester chain's `get_auth.php` node has the evolvo key hardcoded in its Authorization header (not via the credential). Harmless while the trigger is manual, but worth switching to the credential.


## 5. log_request (escalation / callback) — added 2026-09-07
`POST https://n8n.splitagency.biz.id/webhook/optofarm-log-request`
Branch `LOG` in workflow "Optofarm - WIP". ElevenLabs tool: `evolvo_log_request` (`tool_9101m1y2m48heyks8pbph93ssffj`).

| Param | Type | Notes |
|---|---|---|
| `request_type` | required | `order_status` \| `price_enquiry` \| `stock_enquiry` \| `complaint` \| `b2b_lead` \| `callback` \| `other` (unknown values → `other`) |
| `patient_name` | required | (alias `full_name`) |
| `phone` | required | digits as dictated |
| `summary` | required | 1–2 sentences for a colleague, in the call language |
| `language` | optional | `ro` default |
| `branch` | optional | keyword |
| `idempotency_key` | optional | ElevenLabs sends `system__conversation_id`; the same key is ignored for 6 h → `{success:true, duplicate:true}` |

Appends one row to Google Sheet **"Optofarm – Voice Agent Requests"**, tab **Requests** (columns: timestamp Europe/Bucharest, request_type, patient_name, phone, branch, summary, language, conversation_id, status=new, source=voice_agent):
https://docs.google.com/spreadsheets/d/1GServAn1IQuaMzLPgMB0faAt0rdN1Znk8U_1w3Ht7sc — owner **hunor@splitagency.eu** (the account behind n8n's "Google Sheets account" credential; there is no office@ Sheets credential in n8n), shared with **office@splitagency.eu** as editor.
Responses: `{success:true, logged:true, request_type, branch, routed_to:'callback_sheet', message}`; `missing_fields`; sheet failure → `{success:false, error:'log_failed', hint}` (HTTP 200, call is not dropped).

## 6. Phone read-back gate (`phone_confirmed`) — added 2026-09-08
`book_appointment`, `find_appointments` and `log_request` now take a required boolean **`phone_confirmed`** (plus `conversation_id` = `system__conversation_id` on book/find; log_request already sends it as `idempotency_key`). n8n refuses the call unless the agent has read the number back and the caller said yes:

| Call | n8n answer |
|---|---|
| `phone_confirmed` missing / false | `{success:false, error:'confirm_phone_first', phone, read_back:'1, 2, 3 — 1, 2, 3 — 1, 2, 3', message:'Nothing was done yet. First read this phone number back … call again with phone_confirmed true'}` — the refusal time is remembered per `conversation_id|phone` (workflow static data, 2 h) |
| `phone_confirmed: true` less than 5 s after a refusal | refused again (no real read-back + answer fits in 5 s) |
| `phone_confirmed: true` otherwise | processed normally |

Why: the ElevenLabs deterministic procedures fire the tool step in the same turn as the read-back question in roughly a third of runs, whatever the step text says (see ELEVENLABS_AGENT_STATUS.md round 6). The gate makes a booking on an unconfirmed number impossible on the server side; the agent recovers by reading the number back and retrying. Live-tested on all three webhooks (refuse → refuse within 5 s → accept after 5 s → `date_in_past`; fresh conversation with the flag passes straight through).

### `slot_accepted` on book_appointment (2026-09-08, later)
`book_appointment` also requires boolean **`slot_accepted`**: without it n8n answers `{success:false, error:'offer_slot_first', date, time, message}` and books nothing. Reason: in the reschedule procedure the engine chained availability → booking without ever offering the slot.

Both flags are LLM-provided booleans, so they are only as honest as the model — but an honest `false` costs nothing (the agent recovers in one turn) while a wrong `true` books on a wrong number, and in every observed run the model reported them truthfully. The gate is what makes a premature call harmless; it is not what makes the model careful.

Live-tested 2026-09-08 against the production webhooks:

```
book, no phone_confirmed                 -> confirm_phone_first (+ read_back string)
book, phone_confirmed within 5 s         -> confirm_phone_first (anti-flip guard)
book, phone_confirmed after 5 s          -> date_in_past        (gate passed, normal validation)
book, phone_confirmed, no slot_accepted  -> offer_slot_first
book, both flags                         -> date_in_past        (gate passed)
find / log_request, no flag              -> confirm_phone_first
find, flag, fresh conversation_id        -> normal result
```

Note on the reschedule flow: at the end of the session the live branch version had the reschedule branch ending right after `manage_appointment(reschedule)`, leaving the rebooking to the base agent — that turned out to skip the booking call while still telling the caller a time was registered. The prepared fix (procedure v7, not yet pushed) puts the booking step back inside the procedure, after an explicit offer step, with `slot_accepted` as the safety net.
