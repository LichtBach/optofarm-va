# Slot release on cancel, and the reschedule slot leak

**Date:** 2026-09-14 · **Status:** both defects fixed in n8n, live-verified · **Branch:** `MAN`, `FIND`, `BOOK`

Imreh (dRoot Solutions) reported that cancelling a booking now frees the reserved slot. Our own
earlier note said the opposite — that a cancelled slot stayed blocked and only reappeared ~50 minutes
later. This is the test that settled it, and the two defects it turned up.

## What was tested

Live, through the n8n webhooks, against **Dr. Baricz Anna / Tg. Mures, Fortuna / 2026-09-22**, whose
baseline was 8 free slots (09:00–10:45 in 15-minute steps). Both kinds of booking were covered,
because they behave differently inside evolvo:

- a **lead** (`lead_pending_staff_confirmation`) — a phone with no CRM patient behind it;
- a **real appointment** (`appointment_linked_to_existing_patient`) — booked with `patientid`,
  using the CRM test patient *Paciens Teszt* #1867 / `123123123`.

## Result: Imreh is right about cancel

| Action | Effect on the slot |
|---|---|
| book — lead **or** CRM-linked appointment | blocked **immediately** |
| `cancel` (evolvo state 2) | **free again ~8 s later** |
| re-book the freed slot | **succeeds** → blocked again |
| `reschedule` (evolvo state 3) | **still blocked — never released** |
| `confirm` (evolvo state 1) | stays blocked (correct); state → `confirmed`, `ref` stable |

The release is real rather than cosmetic: the freed slot was re-booked successfully, so the whole
round trip book → blocked → cancel → free → re-book → blocked holds. Cancelled records also stop
appearing in `find_appointments`, as intended.

Two older claims die here, and should not be repeated:

- ~~"slot release after cancel is delayed ~50 min"~~ — wrong, it is ~8 s.
- ~~"leads do not block the slot until staff confirm"~~ — wrong, leads block instantly, exactly like
  real appointments.

The guards were exercised in the same run and all held: an unconfirmed cancel returned
`confirm_appointment_first` and changed nothing, and a `ref` pointing at a different date returned
`ref_date_mismatch`.

## Defect 1 — `reschedule` leaked a slot on every use

evolvo state 3 (`Trebuie reprogramat`) marks a record as needing a new time but **keeps holding its
slot**. Our reschedule flow is *mark → check availability → book the new slot*, so every reschedule
permanently burned a slot in the doctor's calendar until staff cleaned it up by hand.

### The fix, and why it is shaped this way

The obvious fix — make `reschedule` cancel outright (state 2) — is wrong: if the caller then finds
nothing suitable, or the call drops, they are left with **no appointment at all**. So the old record
is cancelled only once a replacement has actually been booked:

```
MAN Format Update        on a successful state-3 update, remember the record in workflow static
                         data: sd.pendingResched[conversation_id] = {scheduleid, phone, …}, 6 h TTL

BOOK Format Booking      on a successful post_schedule, read-and-DELETE that entry (so it can fire
                         at most once), and hand the scheduleid to the new tail nodes

BOOK Resched Pending?    if → BOOK resched update_schedule.php (state 2) → BOOK Resched Done
                         else →                                           BOOK Resched Done
```

`BOOK Resched Done` is now the branch's last node and therefore the webhook responder; it strips the
internal `_resched_*` fields and appends the outcome to the response.

Safety properties, all deliberate:

- **Phone must match.** The pending entry carries the marked appointment's phone; if the booking that
  follows is for a different number, the entry is discarded without cancelling anything. A caller
  rescheduling for themselves and then booking for a family member cannot wipe the first record.
- **Consumed on read.** A second booking in the same call cannot re-fire the cancel.
- **Fails safe.** If no replacement is ever booked, the record simply stays at `needs_reschedule`
  holding its slot — visible to staff, exactly as before. Nothing is silently lost.
- **Only on success.** A failed booking leaves the pending entry intact for a retry.
- **Order matters:** mark *then* book. Booking before marking leaves the old slot blocked.

The response gains `replaced_appointment {ref, person, date, time, doctor, location, cancelled}` and
the `note` says the earlier appointment was cancelled and its slot released — or, if the cancel
failed, that the new time is booked but staff must remove the old one.

### Verified end to end

Booked 10:45 → marked it for reschedule (10:45 still blocked, as expected) → booked 10:30 in the same
conversation → **10:45 free, 10:30 held**, one appointment left on the number, and
`replaced_appointment.cancelled: true` in the response. The different-phone guard was tested
separately: booking under another number in the same call left the first appointment untouched.

## Defect 2 — raw Romanian leaked to the agent

The Romanian→English state map in `FIND Format Results` and `MAN Find Target` had five entries and no
`trebuie reprogramat`, so a rescheduled record came back with its state untranslated — which the
agent could read aloud to a Hungarian or English caller. The map now also carries:

```js
'trebuie reprogramat': 'needs_reschedule',
'reprogramat':         'rescheduled',
```

Verified: the record now reports `needs_reschedule`.

Note that `needs_reschedule` is **not** treated as cancelled, so such a record still appears in
`find_appointments` — correct, because the appointment still exists and still holds its slot.

## Regression checks after the change

Error paths (`missing_fields`), bookings with no `conversation_id` (the hand-off is simply inert),
plain `cancel`/`confirm`, and availability all behave exactly as before. Every test record created
was cancelled and the calendar verified back to its exact 8-slot baseline; the CRM test patient's own
record was not touched.

## What this means for the ElevenLabs side

The mechanism needs **no** agent change to function — both tools already send
`system__conversation_id`. What is still worth doing is wording, and it is tracked in the root
[`README.md`](../README.md) handover section: the `book_appointment` tool description does not yet
mention `replaced_appointment`, so the agent may try to cancel an already-cancelled appointment, get
`appointment_not_found`, and turn a successful reschedule into an apology.
