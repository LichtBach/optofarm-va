# ElevenLabs changelog

Newest first. Agent `agent_3101kyq03vpxfpb9vsskgfh2f0bd` (*Optofarm Agent - DEMO*). Tools are
workspace-level and therefore live on every branch the moment they are saved; procedures are
branch-scoped and need a version committed before they reach calls.

## 2026-09-14 — reschedule auto-cancel, and the correct cancellation story

Picks up the handover in [`../README.md`](../README.md) after the n8n side verified that cancelling
releases the slot in ~8 s and made `book_appointment` cancel a marked appointment automatically.
n8n write-up: [`../n8n/slot-release-and-reschedule.md`](../n8n/slot-release-and-reschedule.md).

**There is no hard delete.** What Imreh reported was that *cancelling frees the slot*, not a new
delete endpoint. The v4 Postman collection still documents `update_schedule.php` as
`scheduleid`+`state`+`obs`, and only states 1/2/3 are accepted. Cancel (`state 2`) is the whole
mechanism, and it is now known to release the slot within seconds.

### Tools (live immediately, all branches)

- **`evolvo_book_appointment`** — taught about `replaced_appointment`. When `cancelled` is true the
  old appointment is already gone: say the appointment was **moved**, and never call
  `evolvo_manage_appointment` to cancel it (that would answer `appointment_not_found` and turn a
  finished move into an apology). When false, the new time is booked but a colleague must remove the
  old one. Also: `phone` must be the **same number** the appointment was found on or the hand-off is
  discarded, `full_name` comes from the found appointment's `person`, and `problem` should say it is
  a reschedule.
- **`evolvo_manage_appointment`** — the order is now explicit and marked load-bearing:
  **mark → check availability → book**. Booking the replacement cancels the marked appointment and
  frees its slot, so the tool must never be called a second time to cancel it; booking before marking
  leaves the old slot blocked. `action` now spells out that `cancel` releases the slot in seconds
  while `reschedule` does **not** release it — the record keeps holding the slot until a replacement
  is booked. Added that a cancelled slot is re-bookable straight away.
- **`evolvo_find_appointments`** — documents the new states from the n8n state-map fix. `scheduled`
  and `confirmed` are normal; **`needs_reschedule` is still a live appointment still holding its
  slot**, so it is listed like any other and must not be marked for rescheduling a second time.
  Cancelled records are not returned at all.

### Procedure — `cancel_or_reschedule` on **Main** (version `agtprcv_6201m2g53btqffbs7ae3dgz0k62k`)

Main carries 100% of traffic, so the change was made there rather than on `latency-step-merge`.

- Verified the reschedule step already marked *before* booking — it did; that ordering is now stated
  as load-bearing rather than incidental.
- Added the `replaced_appointment` outcome wording, and the instruction never to cancel the old
  appointment a second time.
- Added that the booking must reuse the same confirmed phone, or the old appointment is left alone.
- **Fixed a live defect found while reading it:** the step said *"if booking_mode is
  lead_pending_staff_confirmation add that **the clinic will confirm it**"* — which used the banned
  word *clinic* and promised a **confirmation**, when no confirmation is ever sent. It now says the
  new time is registered and a colleague will call back, and adds the reminder sentence
  (*Vă trimitem o notificare înainte de programare.*) that the rest of the agent already used.
- Cancel branch: added that the freed slot is bookable again within seconds, so a caller who cancels
  and changes their mind is not told the time is gone.
- `needs_reschedule` records are listed normally in the lookup step.

### Known drift

`latency-step-merge` has the 26.5 %-reduced `booking` procedure and the Romanian `notificare`
wording, but **not** these reschedule changes — it was branched before them. Promoting that branch
as-is would regress the reschedule handling. Port these edits first, or re-branch from Main.

## Earlier

See [`../ELEVENLABS_AGENT_STATUS.md`](../ELEVENLABS_AGENT_STATUS.md) for the round-by-round history,
and [`booking-procedure-optimisation.md`](booking-procedure-optimisation.md) for the 2026-09-12
token reduction on `latency-step-merge`.
