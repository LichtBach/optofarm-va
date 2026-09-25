# n8n changelog

Newest first. Every entry is a change to the live workflow **Optofarm - WIP**
(`jLUnlrt9zM8VWZvp`) on `https://n8n.splitagency.biz.id`.

## 2026-09-25 — no "Optometrist" in returned names, no "clinic" anywhere in the workflow

Answers both open items in [`REQUESTS_FROM_ELEVENLABS.md`](REQUESTS_FROM_ELEVENLABS.md). Live as
`versionId 33ffcf07-8727-4859-ac64-37d3a168db6d` (was `e247f42b-…`), active version confirmed. 17 nodes
changed; rollback bodies in [`optometrist-clinic-rollback-2026-09-25.json`](optometrist-clinic-rollback-2026-09-25.json).

- **`Optometrist ` is stripped on the way out.** In all four `* Display Names` nodes the DISPLAY values
  lose the prefix (`Bódi Ildikó`, `Ifj. Jeremiás László`, `Jeremiás Zoltán`, and `Dan Laura` added), and
  any other name still starting `Optometrist ` (a calendar added later) is stripped as a fallback.
  `Dr.` is kept. `provider_type` still says `optometrist`. Only the name keys are touched, as before, so
  a patient name is never rewritten. Matching on the way **in** is unchanged: `Optometrist Bodi Ildiko`
  and a bare `Jeremiás Zoltán` both still resolve to their calendar (tested live).
- **One leak the request did not list:** the `NO FREE SLOTS:` / `PARTLY FREE:` sentence in
  `CA Format Slots` is built from the raw evolvo name, and `Display Names` only rewrites name keys, never
  `note`, so it would still have said *"Optometrist Jeremias Zoltan … was found"*. `who()` now strips
  the prefix too.
- **All 11 spoken "clinic" strings replaced** with the suggested wording (`Optofarm`, `a colleague`,
  `the booking system`), plus the JS comments in `CA Match Calendars`, `CA Format Slots`,
  `BOOK Validate Input`, `BOOK Find Slot` and the four `Display Names` nodes. A scan of every node
  parameter now finds the word zero times.
- Verified against the live webhook: three `check_availability` calls (Reghin + `provider_type:
  optometrist`, `Jeremiás Zoltán` @ Reghin, `Optometrist Bodi Ildiko`) and none of the responses
  contains `Optometrist` or `clinic`.
- No credentials touched. The webhook secret and evolvo key rotation stays a coordinated two-sided change.

## 2026-09-21 (last) — the evolvo API key is out of the workflow, and the export is current again

The manual tester's `get_auth.php` node carried the evolvo API key as a literal
`Authorization: Bearer 94f0a111…` header — the reason the export in this repo had been left stale
through four rounds of changes rather than refreshed into a public repository.

- **Fixed at the source, not redacted.** That node now authenticates exactly like the other eleven:
  `genericCredentialType` / `httpHeaderAuth` against the existing `Evolvo API Key` credential
  (`6RTMIBHJ3mUJZe7U`). 12 nodes now use it. The key is gone from the live workflow entirely,
  including n8n's own `activeVersion` snapshot — so exports are clean by construction from here on
  and there is nothing left to remember to strip.
- **One hardcoded secret in 126 nodes**, confirmed by scanning every node parameter. Every other
  `Authorization` header is a runtime expression referencing a session token; the six webhooks
  authenticate through a credential, not a literal.
- **The export is refreshed and current** — 126 nodes, including `splitName`, the four
  `Display Names` nodes and the `PHRASES`/`NOISE` matcher work. It had been stuck at 115.
- **Export only `name`/`nodes`/`connections`/`settings`.** A raw `GET` also returns `staticData`
  (which holds a **live evolvo session token**), `activeVersion` (a mirror of `nodes`, where a
  secret redacted from `nodes` alone would survive) and `shared` (owner account details). Written
  down in the README so the next person does not have to rediscover it.
- Smoke-tested after the deploy: CA, the Hungarian branch match, and FIND all still correct.

## 2026-09-21 (later still) — a Hungarian caller can name a branch in Hungarian

`CA Match Calendars` and `BOOK Match Calendars` only rewrote a branch alias when it was the
**entire** query. So `Marosvasarhely` alone matched, and `Rozsak tere` alone matched, but
`"Marosvasarhely, Rozsak tere"` — city and square together, the natural way to say it — matched
nothing at all. The same gap hit Romanian: `"Targu Mures, Piata Trandafirilor"` also failed.

- **Phrase rewriting inside a longer string**, applied only after the existing whole-string ALIAS
  table declines, so every path that worked before is untouched by construction. Longest phrase
  first, so `dozsa gyorgy` wins over `dozsa`. Targets are spelled as the tokens evolvo actually
  holds in `workstation`.
- **Generic street nouns dropped from the query** — `utca`, `ut`, `tere`, `ter`, `str`, `piata`,
  `nr` and friends carry no branch information, so `"Dozsa Gyorgy utca"` has to reach the same
  place as `"Dozsa"`. Query side only, never the workstation, and only when a real token survives:
  a bare `"utca"` still matches nothing rather than everything.
- New Hungarian branch names now reaching the right place: `Rózsák tere`, `Szentgyörgy tér`,
  `Köztársaság tere`, `Posta utca`, `Dózsa György utca`, `Iskola utca`, `Fő út` (→ Str. Principală).
- **Verified differentially, not by spot check.** A 67-query corpus — every literal workstation,
  every existing alias, Hungarian and Romanian full addresses, the corrected diacritic forms, and
  junk like `"utca"`, `"Cluj"`, `""` — run through the old and new matcher side by side:
  **15 fixed, 0 broken, nothing else changed.** Re-run against the code extracted back out of the
  deployed payload, not just the draft.

## 2026-09-21 (later) — branch addresses corrected too

Extends the `Display Names` map with a `LOCATIONS` table: all 8 branch addresses get their Romanian
diacritics back (`Tg. Mureș, Str. Poștei Nr. 3`). This is the Romanian voice mispronouncing its own
language — `Mures` is in 6 of the 8 addresses, so it was wrong on nearly every call.

- **Diacritics only. Abbreviations are deliberately NOT expanded.** `Tg.` → `Târgu` is three edits
  against the matcher's Levenshtein budget of two, and `placeMatch` has no alias for it in that
  position: measured against the live matcher, expanding it sent **all six Târgu branches to
  NO MATCH** when a corrected address was echoed back into a tool. Diacritics-only round-trips
  cleanly — 12/12 against the live `placeMatch`, including partial queries like `Poștei` alone.
  Abbreviation expansion moved to `ro-voice.pls`, where it is output-only and cannot reach a matcher.
- Six new `LOC_KEYS` (`location`, `available_locations`, `doctor_locations`, `matching_locations`,
  `other_locations`, `requested_location`), kept separate from `NAME_KEYS` so the two maps cannot
  cross-fire. Free text is still untouched — verified an `observations` field mentioning a branch.
- `elevenlabs/pronunciation/*.pls` re-keyed in the same pass: five now-dead entries dropped from
  `ro-voice.pls`, three location graphemes re-keyed in `hu-voice.pls`, and two new Hungarian entries
  added — `Poștei`/`Școlii` map back to plain `s`, because the Hungarian voice had been reading the
  *stripped* spellings correctly by accident and now receives a `ș` it has no letter for.

## 2026-09-21 — corrected provider names returned to ElevenLabs, 122 → **126 nodes**

Evolvo stores all 16 provider names with diacritics stripped. Rather than have the clinic retype
them (and risk evolvo normalising them straight back on save), the correction is applied on the way
out, in n8n. Evolvo is never written to.

- **Four new Code nodes** — `CA / BOOK / FIND / MAN Display Names` — each wired downstream of both
  that branch's happy path and its `Error Out`, so all four are now the webhook responders. Source
  in [`display-names.node.js`](display-names.node.js); the four copies are identical.
- **Five names change**, per the clinic's decision: `Dr. Ilovan Anca` → `Anica` (a wrong given name,
  not a diacritic), and Hungarian diacritics restored on `Székely Attila`, `Ildikó`,
  `Ifj. Jeremiás László` (also the missing period) and `Jeremiás Zoltán`. The other eleven are
  returned untouched — Romanian names keep their stripped spellings, deliberately.
- **Applied at the last node and nowhere else.** The obvious place is `splitName`, and it would have
  been a silent bug: `MAN rel Find Calendar` matches a cancelled appointment back to its calendar
  with `norm(c.name) === norm(a.doctor)`, an *exact* equality after diacritic stripping. Diacritics
  survive it; `Anica` vs `Anca` does not. Rewriting upstream would have turned every
  `slot_release_status` into `unknown` with nothing visibly breaking.
- **Scoped to name-bearing keys** (`doctor`, `available_doctors`, `doctors_at_requested_location`,
  `matching_doctors`, `specialty_providers`, `calendar_name`), not a blind walk over every string —
  a patient legitimately called `Jeremias Zoltan` must not be rewritten. Verified.
- **Round-trip is safe.** The agent may echo a corrected name straight back into a tool:
  `CA/BOOK Match Calendars` NFD-normalise and strip combining marks on both sides, and `Anca`→`Anica`
  is one edit against a Levenshtein budget of 2. All 16 names plus `Kilován` and
  `Ilovan Anica doktornőhöz` tested against the live matcher — 14/14 pass.
- **Fails open.** Any exception passes the item through untouched; an unrecognised provider name is
  logged, never raised. A cosmetic rewrite must never drop a call.

Confirmed by the clinic the same day: it is **`Bódi`**. `Optometrist Bodi Ildiko` returns as
`Optometrist Bódi Ildikó`. No open questions remain on the name list.

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
