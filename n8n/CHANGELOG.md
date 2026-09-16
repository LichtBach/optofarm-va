# n8n changelog

Newest first. Every entry is a change to the live workflow **Optofarm - WIP**
(`jLUnlrt9zM8VWZvp`) on `https://n8n.splitagency.biz.id`.

## 2026-09-16 — the psycho-orthoptics calendar: split its name, and hide it unless asked for

Two problems with the one calendar of 30 whose service lives in its **name**:
`Dr. Prof. Szekely Attila  - Consiliere / Terapie psiho-ortoptica` (Republicii, 30-min slots,
afternoons only; note the double space).

**1. The agent read the suffix out loud.** `doctor` was the whole calendar name, so a caller heard
*"Doctor Professor Szekely Attila minus Consiliere slash Terapie psiho-ortoptica"* — and that string
also went back into `book_appointment`. `splitName()` in `CA Match Calendars` and
`BOOK Match Calendars` now yields `doctor` (the speakable name) and `service` (the suffix), and
`service` is carried through `CA Format Slots`, `BOOK Find Slot` and `BOOK Format Booking` onto
results, `earliest`, `requested_date_slots` and `booked`. The same splitter runs over evolvo's
`medic` field in `FIND Format Results` and `MAN Find Target`, so a cancel read-back cannot say it
either. He is the **only** suffixed calendar, so for the other 29 the output is unchanged — there is
no `service` key at all when there is no suffix.

Checked against all 30 live names: every clean name still matches its own calendar, and the matcher
resolves `Szekely Attila`, `Székely Attila`, `Szekely`, `Prof. Szekely Attila`, ASR variants
(`Sekely Atila`, `Szekely Atila`) and the full suffixed string to the same single calendar — so
booking works with whichever form the agent sends.

**2. He was the default answer for Republicii.** `providerKind()` classified him `doctor` off the
`Dr.` prefix, and with 13:00 slots he was the `earliest` free slot at that branch — so
*"the soonest appointment in town centre"* offered a psycho-orthoptics counsellor to a caller who
wanted glasses. A name with a service suffix is now its own kind (`vision_therapy` when the service
matches `/ortopt/`, otherwise `specialty`), and a **specialty gate** in `CA Match Calendars` drops
such calendars from every search except when the caller named the person or sent that exact
`provider_type`. `CA Validate Input` whitelists `vision_therapy` and normalises separators, so
`vision therapy` and `vision-therapy` land on the same value.

He is also kept out of `available_doctors`, `doctors_at_requested_location`, `matching_doctors` and
`available_provider_types`, so the agent cannot offer him out of an error payload. A branch that had
*only* a specialty provider now answers with the new `only_specialty_providers_here` error (carrying
`other_locations`) rather than the misleading `no_match`. `provider_type: "vision_therapy"` also
works with **no** location, since there is exactly one such calendar — so the `missing_target` guard
no longer fires for that case.

Twelve cases were dry-run against the live calendar list before the push, then re-run against the
live webhook:

| request | before | after |
|---|---|---|
| `{location: "Republicii"}` | earliest = Szekely 13:00 | earliest = Dr. Tripon Robert 13:30, Szekely absent |
| `{location: "Republicii", provider_type: "doctor"}` | included Szekely | Tripon + Petrea only |
| `{location: "Republicii", provider_type: "vision_therapy"}` | — | Szekely only, with `service` |
| `{provider_type: "vision_therapy"}` (no location) | `missing_target` | Szekely only |
| `{doctor: "Szekely Attila"}` | full suffixed name | `"Dr. Prof. Szekely Attila"` + `service` |
| `{doctor: "Szekely", location: "Postei"}` | suffixed name in the error | clean name; specialty providers dropped from the branch list |
| `{location: "Postei"}`, `{doctor: "Baricz Anna"}` | — | unchanged |

His scope — and therefore when the agent should ask for `vision_therapy` — is written up in
[`../api-docs/ELEVENLABS_TOOLS.md`](../api-docs/ELEVENLABS_TOOLS.md) under "The specialty provider".
Rollback bodies for the eight nodes:
[`specialty-gate-nodes-rollback-2026-09-16.json`](specialty-gate-nodes-rollback-2026-09-16.json).

**Related, not done:** `problem_description` from `get_info.php` is a newline-separated service list
(`Prescriere ochelari`, `Tensiune oculara`, `Retinofotografie`, `Discromatie`, …) populated on **16 of
the 30 calendars** and not surfaced by any tool today. Exposing it as `services[]` would give the
prompt real clinic data for visit-reason routing instead of name-prefix heuristics. Szekely's is
empty, as are the eight `ai_*` fields on all 30 calendars — the clinic filling those in is the proper
fix, and `ai_public_names_hu/ro/en` would also solve spoken provider names generally.

## 2026-09-15 — `date_spoken` / `relative_day`: the agent was offering slots in the past

Reported from a live call: the agent offered a time 40 minutes in the **past**. n8n was not at fault
— and that is the point of this entry, because the next person to see it will suspect n8n too.

**What actually happened.** Execution 1409 (13:15 UTC) / conversation `conv_4701m2jk8460e2es63a4zbc5j21c`.
The webhook returned `earliest {date: "2026-09-16", time: "15:40", doctor: "Dr. Ilovan Anca"}` with
`date_searched_from: "2026-09-16"`. The agent said *"astăzi, marți 15 septembrie, la ora 15:40"*.
When the caller declined, it offered Dr. Popa Camelia's `2026-09-17 10:00` as
*"mâine, miercuri 16 septembrie, la ora 10:00"*. Both spoken dates are **exactly one day earlier
than the data, with the weekday name matching the wrong date** — the LLM (`qwen35-397b-a17b`) was
converting ISO dates to spoken dates itself and was consistently a day out. The October dates in the
same response, also reported as wrong, were real: Dr. Ardelean Adina has nothing free before 2 Oct.

Worth stating plainly: **nothing this workflow returns can ever be today.** `date_from` defaults to
tomorrow and evolvo's `get_work_days.php` rejects a non-future `date_from`, so a slot described as
"today" is always a misreading, never stale data.

**The fix — take the arithmetic away from the model.** Every date the workflow emits now carries:

- `date_spoken` — `"Wednesday 16 September"`: weekday + day + month in English, for the agent to
  *translate*, not compute.
- `relative_day` — `today` / `tomorrow` / `the day after tomorrow` / `in N days` /
  `IN THE PAST - do not offer this`.

and every `note` / `next_step` / `read_back` string ends with the rule: *never work out a date
yourself, say `date_spoken` translated, and say today or tomorrow only when `relative_day` says so.*
`check_availability` also gained a top-level `today`.

Seven Code nodes, no graph change (122 nodes, connections and positions untouched):

| node | change |
|---|---|
| `CA Format Slots` | labels on `earliest`, every `available_days[]` entry and `requested_date_slots`; top-level `today`; extended `note` |
| `FIND Format Results` | labels in `publicView`; rule appended to both `next_step` variants |
| `MAN Find Target` | labels in `publicView`; `read_back` now reads the spoken date; rule at the head of the `confirm_appointment_first` message |
| `MAN Format Update` | carries `date_spoken` into `sd.pendingResched` so the BOOK tail can speak it |
| `MAN Release Done` | the released-slot `note` says the spoken date, not the ISO one |
| `BOOK Format Booking` | labels on `booked`; rule appended to the `note` |
| `BOOK Resched Done` | `date_spoken` on `replaced_appointment` and in its `note` |

The helper is duplicated into each node (n8n Code nodes cannot share a module). It is independent of
the n8n host's timezone — today comes from `toLocaleDateString('en-CA', {timeZone: 'Europe/Bucharest'})`
and the weekday from a UTC-noon parse of the ISO date — and returns `{}` for a malformed date rather
than a plausible-looking wrong label.

Verified live against the failing query (`{provider_type: "doctor", location: "Postei"}`): `earliest`
came back `2026-09-16` / `Wednesday 16 September` / `tomorrow`, and the `2026-10-02` day as
`Friday 2 October` / `in 17 days`. The `requested_date` path and the FIND/MAN `publicView` labelling
were checked too. Rollback bodies for all seven nodes: [`date-label-nodes-rollback-2026-09-15.json`](date-label-nodes-rollback-2026-09-15.json).

**Still open, and prompt-side:** nothing in the agent prompt tells it how to speak a date or forbids
deriving one, so the inline instruction in each tool result is the only thing steering it. See the
handover note in the root `README.md`.

Also in this commit: the evolvo API key, still hardcoded in the tester chain's `get_auth.php` node,
is redacted in the committed export. It remains in this repository's git history — see the standing
credential-rotation item.

## 2026-09-14 (evening) — `slot_released`, and the cancel path from 7 evolvo calls to 3

Answers the round in [`REQUESTS_FROM_ELEVENLABS.md`](REQUESTS_FROM_ELEVENLABS.md). 115 → **122 nodes**.

- **`slot_released` on every successful cancel.** The agent was telling callers the time was bookable
  again on the strength of our ~8 s finding, not on anything the response said. It now re-queries the
  provider's calendar after the cancel and reports `slot_released` + `slot_release_status`
  (`released` / `still_blocked` / `unknown` / `not_checkable_same_day` / `check_failed`), with the
  `note` already phrased for the caller. New nodes `MAN Release Check?` → `MAN rel get_info.php` →
  `MAN rel Find Calendar` → `MAN rel get_work_days.php` → `MAN Release Done` (now the MAN responder).
  Only `cancel` is checked — `confirm` and `reschedule` do not free a slot.
- **`unknown` is deliberately distinct from `still_blocked`.** Absence from the free list does not
  prove a slot is blocked; the provider may simply not be working then. This came out of trying to
  verify a specific smoke-test record and discovering its calendar alternates morning and afternoon
  shifts by day — see the reply in `REQUESTS_FROM_ELEVENLABS.md`.
- **FIND's scan is now shared with MAN.** Within one conversation both branches scanned the same 31
  days for the same phone, seconds apart — 6 evolvo calls each. `FIND Format Results` parks the
  collected records in `sd.scanCache[conversation_id|phone]` (180 s TTL) and the new
  `MAN Scan Cache` → `MAN Scan Cached?` pair bypasses `get_schedule_patient.php` and all five
  `get_schedule.php` windows on a hit. Refs are `scheduleid` hashes, so a reused record keeps the ref
  the caller was read back. The entry is dropped as soon as MAN changes anything.
- **MAN narrows the scan to one window** when it has a `date`, instead of five. Falls back to all
  five if the date is outside the scanned range.
- **Parallel window fetch deliberately NOT done** — the unexplained Apache 403 in
  `QUESTIONS_FOR_IMREH.md` §3 makes five concurrent calls the wrong risk for a saving the cache has
  already delivered.
- `FIND Validate Input` now emits `conversation_id` (BOOK already did).
- Measured on a live cancel: **3 evolvo calls, 1.4 s** with the release check included; 5 on a
  cache miss. Was 7.
- Asked Imreh whether a phone lookup can cover agenda entries (question 12) — that would remove the
  scan altogether.

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
