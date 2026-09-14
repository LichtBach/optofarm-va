# Questions for Imreh R. (dRoot Solutions) — thirdpartyai API

Context: integrating this API with an ElevenLabs voice agent via n8n. We built a real n8n workflow (using a Webhook trigger, exactly how the production integration will call the API) at `https://n8n.splitagency.biz.id`, workflow "Droot Evolvo - IP Diag Test", and ran it against the live API URL you gave us: `https://secure.mydroot.eu/evolvo/api/thirdpartyai/`. Below is the real webhook response and the raw HTTP exchanges behind it. Two issues need clarifying before we build the booking flow for real.

## Live n8n webhook run — full result

Triggered via `GET https://n8n.splitagency.biz.id/webhook/droot-diag-test`, which runs: get_auth → get_info → get_work_days → post_schedule (attempt A, fresh slot) → post_schedule (attempt B, same slot again) → get_schedule → get_schedule_patient, and returns this summary:

```json
{
  "step1_auth": { "status": 200, "got_token": true },
  "step2_calendar_used": { "name": "Dr. Baricz Anna", "workstation": "Tg. Mures, Fortuna" },
  "step3_slot_used": { "wday": "2026-09-08", "slot": "09:00" },
  "step4_post_schedule_bad_problemDescription": { "status": 200, "body": { "Result": "OK" } },
  "step5_post_schedule_valid_problemDescription": { "status": 200, "body": { "Result": "ERROR", "errorcode": 1 } },
  "step6_get_schedule_lookup": { "status": 200, "total_records_in_window": 55, "found_our_test_booking": false },
  "step7_get_schedule_patient_lookup": { "status": 200, "body": { "Result": "NOTFOUND" } },
  "conclusion": "Booking created (Result:OK) but NOT retrievable via get_schedule.php or get_schedule_patient.php"
}
```

Booking made in step4: patient "TEST TEST N8N", phone `0700000009`, email `test@test.com`, Dr. Baricz Anna / Fortuna, 2026-09-08 09:00. **Please delete this manually** — same as the earlier one below, we have no scheduleid to cancel it via the API.

## 0. RESOLVED on our side (2026-09-02) — but a heads-up: empty patientEmail → 401

We hit repeated `401`s on `post_schedule.php` (empty body, no `API_ERROR_CUSTOM` header) while reads worked fine with the same token. **Root cause turned out to be an empty `patientEmail` field** — sending a non-empty email makes the booking succeed (`Result: OK`) immediately. We now default the email on our side, so this no longer blocks us.

**Minor question (not urgent):** is `patientEmail` intended to be required? The `401` (which looks like an auth failure and has no `API_ERROR_CUSTOM` header) is misleading for what is really a missing/empty required field — an `errorcode` in a `200` body (like other validation errors) would be clearer. Not blocking us; just flagging in case it's an easy fix or affects other integrators.

## 1. `errorcode: 1` — what does it actually mean?

Earlier (separate, manual test) we got `errorcode:1` and assumed it meant `problemDescription` must match one of the calendar's predefined options from `get_info.php`. **That assumption turned out to be wrong** — see the n8n run above: step4 used a completely made-up free-text `problemDescription` on a fresh slot and it succeeded fine (`Result:OK`). Step5 then reused the *same slotid* (already booked by step4) with the calendar's exact predefined description text, and got `errorcode:1` — most likely just because the slot was already taken, not because of the description.

**Question:** what does `errorcode:1` (and other errorcodes) on `post_schedule.php` actually mean? Is there a list of possible error codes and their causes (e.g. slot already taken, invalid patientPhone format, missing required field, etc.)? We don't want to guess and build incorrect validation into the voice agent.

## 2. How do we retrieve/manage a booking right after creating it?

Confirmed twice now (once manually, once via the real n8n webhook above): `post_schedule.php` returns `{"Result":"OK"}` with **no scheduleid or any identifier**. The resulting booking does not show up afterward in:
- `get_schedule.php` for the relevant date window (55 real records returned in the n8n run, ours wasn't among them)
- `get_schedule_patient.php` by phone (tried several formats: with/without leading 0, with +40 prefix — always `NOTFOUND`)

This was true minutes after booking, in both tests. Every appointment we *do* see via `get_schedule.php` has `"state": "Programat"` (confirmed) — we've never seen any other state.

**Question:** does a booking made via `post_schedule.php` need staff confirmation in the admin UI before it becomes visible via `get_schedule.php` / `get_schedule_patient.php`? If so, is there any way to get the `scheduleid` of a booking immediately after creating it, so a voice agent could confirm/reschedule/cancel its own booking via `update_schedule.php` without waiting on staff?

## Manual cleanup needed (2 leftover TEST bookings)

We couldn't cancel either via the API (no scheduleid available) — please remove them:
- Dr. Baricz Anna, Tg. Mureș - Fortuna, **2026-09-01 09:00**, patient "TEST TEST", phone `0700000000`, email `test@test.com`
- Dr. Baricz Anna, Tg. Mureș - Fortuna, **2026-09-08 09:00**, patient "TEST TEST N8N", phone `0700000009`, email `test@test.com`

## 3. Sensitivity to request rate / 403 IP blocks

Separately, during earlier manual testing (not the n8n run above), after ~6-7 requests within about a minute (including one malformed request on our side), our whitelisted IP got a plain Apache `403 Forbidden` on every endpoint, including `get_auth.php` itself — not the API's own JSON error format, a generic Apache "you don't have permission" page. It did **not** clear after 5 minutes of polling every 20s.

**Question:** is there a rate limit / fail2ban-style block on this server? What's a safe request rate for an automated integration (voice agent + n8n), and what's the actual cooldown duration after a burst or a 401?

```
09:01:43 UTC  first 403 Forbidden (plain Apache page, on get_info.php)
09:01:43 UTC  → 403 (retry, on get_auth.php itself)
09:02:29 - 09:07:10 UTC  polled get_auth.php every ~20s, 15 attempts, every single one still 403
```

---

## Other raw exchanges (from the earlier manual test, for reference)

**get_auth.php → 200**
```
POST https://secure.mydroot.eu/evolvo/api/thirdpartyai/get_auth.php
Authorization: Bearer <institution API key>
→ 200 {"token":"<session token>"}
```

**get_schedule_patient.php, several phone formats tried → all not found**
```
POST .../get_schedule_patient.php
lng=1, phone=0700000000  (also tried 700000000, +40700000000)
→ 200 {"Result":"NOTFOUND"}
```

Full endpoint documentation (schema + examples for all 7 endpoints) is in `api-docs/*.json` alongside this file.

---

## Status update 2026-09-07 — Postman v4 received

Imreh's v4 collection adds `schedule_form` (none/0=All, 1=Appointment, 3=Agenda) on `get_schedule.php` and `get_schedule_patient.php`, a new `get_patient.php` (phone → `patientid`), and an optional `patientid` on `post_schedule.php` (ties the booking to an existing patient; name/email/phone are then ignored). This most likely answers **question 2**: the invisible bookings were agenda insertions, which the read endpoints only return with `schedule_form=0` or `3`. Still to confirm live (from n8n's IP): whether agenda records carry a `scheduleid` usable by `update_schedule.php`, the full `get_patient.php` response shape, and what `schedule_form=2` would be. Questions 1 (errorcode meanings) and 3 (403 blocks — this dev machine got a plain Apache 403 again on 2026-09-07 on its first request) remain open.

## v4 live results (2026-09-07) and new questions

Tested through our n8n workflow (IP 72.62.44.134): `get_schedule.php` with `schedule_form=3` returns our test lead (`form: "Agenda"`, `state: "Programat"`, with a `scheduleid`), and `update_schedule.php state=2` on that id works (state → `Anulat`). Thank you — that closes the old question 2.

4. **`get_schedule_patient.php` does not return Agenda records by phone**, even with `schedule_form=0` or `3` (phone `0770000000`, which had a fresh lead, → `NOTFOUND`). Is that intended? We now scan `get_schedule.php` in 7-day windows and filter by phone ourselves — 6 calls per lookup instead of 1. A phone lookup that also covers agenda entries would be much better for us.
5. **Slot release after cancel is delayed.** Right after `update_schedule.php state=2` (tested on an Agenda entry and on a real Appointment) `get_work_days.php` still did not offer the slot; the first one reappeared roughly 50 minutes later. Is there a cache / cron, or did someone delete it manually? We need to know what to tell a caller who cancels and wants to rebook the same slot.
6. **`get_patient.php` for a phone that only has leads → `NOTFOUND`**, so the `patientid` flow only helps returning CRM patients — confirmed and fine. (patientid booking verified with test patient 'Paciens Teszt' #1867 — works as described, thanks.)
7. Our dev machine IP `188.27.55.208` now gets a plain Apache `403` on the very first `get_auth.php` call — was it removed from the whitelist?

Test records left in the system (both cancelled via API, state **Anulat**): TEST TEST N8N / 0770000000 / Dr. Baricz Anna, Gheorghe Doja / 2026-09-09 10:00 (agenda), and Paciens Teszt / 123123123 / same doctor+location / 2026-09-09 10:20 (appointment). Paciens Teszt's own 2026-09-10 09:05 appointment was not touched.

8. **Can a cancelled record be set back to Programat?** `update_schedule.php` with `state=0` returns `{"Result":"ERROR","errorcode":3,"message":"unknown status"}`; only 1/2/3 are accepted. During our tests the voice agent cancelled Paciens Teszt's 2026-09-10 09:05 appointment by mistake and we could not undo it — could you (or the clinic) restore it, and is there an API way to undo a cancellation? Related: the cancelled record still blocks the slot, and slots are on the calendar's 20-minute grid, so 09:05 cannot be re-booked through `post_schedule.php` either.

9. **Can an appointment be hard-deleted through the API, not just set to `Anulat`?**
Optofarm has told us deletion is now possible "through the current API". We can find no trace of it:
your v4 Postman collection still documents `update_schedule.php` as `scheduleid` + `state` + `obs`
(unchanged from v3, while `get_schedule`, `get_schedule_patient` and `post_schedule` all gained new
fields in v4), and question 8 above establishes that only states 1/2/3 are accepted — `state=0`
returns `errorcode 3, unknown status`.

So, concretely:
- Is there a delete — a `state` value beyond 1/2/3, an extra parameter on `update_schedule.php`, or a
  separate endpoint? If so: exact URL/parameter, success response, error response.
- What happens on a second delete of the same `scheduleid`, and on deleting a record already `Anulat`?
- Is it recoverable in the admin panel afterwards, or gone for good?
- **Does a delete free the slot immediately?** This is the one that matters most to us — see
  question 5. If `Anulat` leaves the slot blocked for ~50 minutes but a delete frees it at once,
  that alone would change how we handle a caller who cancels and wants to rebook the same time.

If what was meant is simply that **staff** can delete a record in the evolvo admin panel, please say
so plainly — that is what we have been asking for under "manual cleanup" all along, and it would mean
there is nothing for us to build.

---

## Status update 2026-09-14 — question 9's premise is resolved

We re-tested slot release end to end through our own integration and can close the part of question 9
that mattered most: **cancelling (`state 2`) frees the slot in about 8 seconds**, not ~50 minutes. We
measured it on both a lead and a real patient-linked appointment, and re-booked the freed slot
successfully straight afterwards. The earlier "~50 minutes" observation was wrong and we are
retiring it.

That removes the practical reason for wanting a hard delete. We would still like a yes/no on whether
one exists (question 9), but it is no longer blocking anything.

One correction to our own earlier reporting, for your records: we previously said leads do not block
a slot until staff confirm them. They do — a lead blocks its slot immediately, exactly like a
confirmed appointment.

## 10. Can the API expose a provider's working hours (shift start/end)?

Callers ask things like *"until what time is Dr. Baricz Anna there today?"*, and we cannot answer it
without inventing something, which we will not do.

`get_work_days.php` returns only free slots (`wday` + `free_timespace[{slot, slotid}]`) and
`get_info.php` returns no hours either, so a provider's **shift end is not derivable**: if the last
free slot is 15:00 the provider may still be working until 21:00, with the rest already booked.

Could you expose, per calendar and per day:

- the working interval (start and end), and ideally
- any break within it, so we do not offer a time inside one.

Either as extra fields on `get_work_days.php`'s records, as a block on `get_info.php`, or as a
separate endpoint — whichever fits your model. We only need to read it.

## 11. The `ai_*` fields on `get_info.php` — can the clinic fill them in?

Each calendar comes back with eight fields that look built for exactly this integration, and every
one of them is empty on all 30 calendars:

`ai_doctor_title`, `ai_description`, `ai_default_language`, `ai_supported_languages`,
`ai_emergency_contacts`, `ai_public_names_hu`, `ai_public_names_ro`, `ai_public_names_en`

- Are these editable by the institution in the evolvo admin panel, and if so where?
- What is the expected shape of each — free text, a code list, an array?
- Is `ai_doctor_title` the intended place for a provider's **type** (doctor vs optometrist)? We
  currently infer that from the `Dr. …` / `Optometrist …` name prefix, which works on all 30
  calendars today but would break silently if a calendar were ever named differently.
- Are `ai_public_names_*` meant to be the **spoken** form of a provider's name per language? Speech
  recognition mangles staff names badly, and a per-language spoken form would help us directly.

If they are meant for a different product and we should ignore them, that is a perfectly good answer
too — we would just like to know before we build anything that duplicates them.

## 12. Can a phone lookup return agenda entries too?

`get_schedule_patient.php` still does not return `Agenda` (lead) records when we look a patient up by
phone, even with `schedule_form=0` — it only returns real appointments. Because the voice agent must
be able to find and cancel a booking it made itself, and its own bookings start as agenda entries, we
work around it by scanning `get_schedule.php` in five 7-day windows and filtering by phone on our
side: **six calls where one should do**, on every lookup, on a live phone call where latency is
audible to the caller.

Is a phone lookup that covers agenda entries on the roadmap? Either `get_schedule_patient.php`
including them, or any endpoint that takes a phone number and returns both kinds, would remove the
scan entirely and take roughly a second out of every cancellation call.

If the omission is deliberate, knowing why would help us too — we would stop treating it as a gap.

