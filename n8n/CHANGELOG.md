# n8n changelog

Newest first. Every entry is a change to the live workflow **Optofarm - WIP**
(`jLUnlrt9zM8VWZvp`) on `https://n8n.splitagency.biz.id`.

## 2026-09-14 (later) — answered the QA follow-ups; no workflow change

Took up items 4 and 5 of [`../elevenlabs/qa-followups.md`](../elevenlabs/qa-followups.md), which
asked the n8n side to verify something before the prompt work could proceed. Full answers:
[`qa-followups-answers.md`](qa-followups-answers.md). Nothing in the workflow changed.

- **Item 4 (optometrist vs doctor) — already built, heuristic confirmed.** Live `get_info.php` now
  returns **30** calendars (it was 16 on 2026-09-11): 21 `Dr. …`, 9 `Optometrist …`, **0 unmatched**.
  Every non-doctor is explicitly prefixed `Optometrist` — the rule is not "absence of dr.".
  `check_availability`'s `provider_type` filter re-tested against the expanded set and correct,
  including the new Fortuna doctors. Fortuna remains the doctor-only branch for exercising
  `no_provider_of_type`.
- **Item 5 (read back a provider's schedule) — impossible with the current API.** Verified against
  raw live responses that `get_work_days.php` returns only free slots and `get_info.php` no hours,
  so a shift end cannot be derived. Handed to dRoot Solutions as question 10.
- **Found: eight `ai_*` fields on every calendar, all empty** (`ai_doctor_title`, `ai_description`,
  `ai_public_names_hu/ro/en`, `ai_supported_languages`, `ai_emergency_contacts`,
  `ai_default_language`). If the clinic can fill them they would replace the name-prefix heuristic,
  hold the visit-reason routing, and give per-language spoken forms of provider names. Question 11.
- Recorded in `QUESTIONS_FOR_IMREH.md` that question 9's premise is dead: cancel frees the slot in
  ~8 s, not ~50 min, so the hard-delete request is no longer blocking.

## 2026-09-14 — cancel/reschedule slot release

Imreh reported that cancelling frees the reserved slot; confirmed, and two defects found and fixed.
Full write-up: [`slot-release-and-reschedule.md`](slot-release-and-reschedule.md).

- **Verified:** `cancel` (state 2) releases the slot in **~8 s** and it is genuinely re-bookable, for
  leads and CRM-linked appointments alike. Retires two wrong beliefs: that release lagged ~50 min,
  and that leads do not block a slot (they block instantly).
- **Fixed — reschedule leaked a slot on every use.** State 3 never releases the slot, so the old
  record is now cancelled automatically once a replacement booking succeeds in the same conversation.
  New nodes `BOOK Resched Pending?` → `BOOK resched update_schedule.php` → `BOOK Resched Done` (the
  last is now the BOOK responder); `MAN Format Update` writes `sd.pendingResched[conversation_id]`
  (6 h TTL), `BOOK Format Booking` consumes it read-and-delete, guarded by a phone match.
  Response gains `replaced_appointment {…, cancelled}`.
- **Fixed — `Trebuie reprogramat` leaked untranslated** to the agent. The state map in
  `FIND Format Results` / `MAN Find Target` gained `trebuie reprogramat` → `needs_reschedule` and
  `reprogramat` → `rescheduled`.
- `BOOK Validate Input` now also emits `conversation_id`.
- 112 → **115 nodes**.

## 2026-09-11 — `provider_type` routing on check_availability

Route a caller to a **doctor** or an **optometrist** instead of whoever is free soonest. Runbook:
[`provider-type-runbook.md`](provider-type-runbook.md); rollback bodies in
[`CA-nodes-rollback-pre-provider_type.json`](CA-nodes-rollback-pre-provider_type.json).

- `CA Validate Input` whitelists `provider_type` (only `doctor`/`optometrist` survive; anything else
  becomes `''` = unfiltered).
- `CA Match Calendars` classifies off the calendar-name prefix and filters **after**
  `doctor_not_at_location`, **before** `no_match`/`too_many_matches`, skipping the filter entirely
  when the caller named a doctor. New error `no_provider_of_type` routes through the existing
  `CA Match OK?` → `CA Error Out` path, so no rewiring was needed.
- `CA Format Slots` surfaces `provider_type` on every result, on `earliest` and on
  `requested_date_slots`, plus a top-level `provider_type_filter` echo — emitted **only** when the
  filter actually ran.
- Verified live against `get_info.php`: all 16 calendars are `Dr. …` (12) or `Optometrist …` (4);
  there is no third naming pattern. **Fortuna** is the doctor-only branch to use when exercising
  `no_provider_of_type` — Reghin has optometrists, contrary to an earlier guess.

## 2026-09-09 — phone-only identification, and the callback flow

- Identification for find/manage dropped the caller's **name** entirely (ASR turned "Csergo Zsofia"
  into "Cerches Zofia"; no fuzzy match survives that). `find_appointments` takes phone +
  `phone_confirmed` and returns **every** appointment on the number with the name evolvo holds, each
  with a stable `ref` — a base36 hash of the `scheduleid`, never a positional index, which would
  shift onto someone else's record between calls.
- `manage_appointment` takes `ref` + `date` + `appointment_confirmed` and enforces a server-side
  `confirm_appointment_first` gate, mirroring `phone_confirmed`, with the same 5-second replay guard.
- `ref_date_mismatch` added: `ref` and `date` must point at the same record.
- BOOK/FIND remember the confirmed number against `conversation_id` (`sd.confirmedPhone`, 6 h) and
  LOG recovers it when absent, so a caller is never asked to dictate their number twice. New
  `phone_missing` answer when nothing is known.
- Accepted privacy trade-off: a caller who dictates a number hears the names of everyone with an
  appointment on it. Deliberate — one phone often covers a family.

## 2026-09-08 — server-side gates

The deterministic procedure engine skips "ask" steps in ~1 run in 3 regardless of wording, and
`reasoning_effort` cannot be set on the LLM in use. Fixed in n8n instead: BOOK/FIND/LOG refuse unless
`phone_confirmed: true` (answering `confirm_phone_first` + `read_back`), and BOOK additionally
requires `slot_accepted: true` (answering `offer_slot_first`). Both refuse a flag that flips less
than 5 s after a refusal.

## 2026-09-07 — Postman v4 applied

- `get_schedule.php` + `schedule_form` returns leads **with** a `scheduleid`, and
  `update_schedule.php` accepts it — this is what made cancel/confirm/reschedule possible at all.
  `get_schedule_patient.php` still does not return leads by phone, so FIND/MAN scan `get_schedule`
  in 5×7-day windows and match by phone client-side. Cost: 6 evolvo calls per lookup instead of 1.
- BOOK looks the phone up with the new `get_patient.php`: exactly one name match → book with
  `patientid` (a real appointment on the CRM record, evolvo then ignores name/email/phone);
  no match → the lead path; several → `ambiguous_patient`. Response gained `booking_mode` and
  `patient_match`.
- Records carry `kind`, `manageable` and an English `state`; cancelled records are hidden.
- City aliases (Târgu Mureș / Marosvásárhely → `tg. mures`) and multi-calendar booking.

## 2026-09-02 — the four tools go live, and the 401 mystery

- All four branches built inside the one workflow, header-authenticated, with a shared 45-minute
  token cache in static data.
- **`post_schedule.php` returns 401 with an empty body when `patientEmail` is empty** — a
  missing-required-field rejection wearing an auth error's clothes. It is not a WAF or IP block. BOOK
  now defaults the email to `noemail@optofarm.ro`, so a voice call never has to collect one.
- Fixed en route: token headers used n8n's paired-item `.item`, which Code nodes break — switched to
  `.first()`.
- First real end-to-end booking confirmed, and the slot then disappeared from availability.
