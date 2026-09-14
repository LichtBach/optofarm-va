# Open questions for Imreh (evolvo API)

> **Note:** this file was created fresh in the Claude Code remote container on 2026-09-14, which
> has no `api-docs/` directory. If a local copy already exists with open items, **merge rather than
> replace** — the items below marked *(reconstructed)* were recovered from the n8n workflow's own
> sticky notes, not from the original file.

---

## 1. Hard-delete of an appointment — NEW, blocking

Optofarm would like a caller-initiated cancellation to *remove* the appointment rather than leave it
in `ANULAT`. We understand this may already be supported. Our side currently only ever sets
`state` via `update_schedule.php` (`{confirm:1, cancel:2, reschedule:3}`), and `state: 0` is rejected
as *unknown status*.

- Does `update_schedule.php` support a hard delete — a `state` value beyond 1/2/3, or an extra
  parameter (e.g. `delete=1`, `action=delete`)?
- If it is a separate endpoint instead: URL, HTTP method, body parameters.
- Is the session Bearer token from `get_auth.php` sufficient, or does delete need extra rights?
- Exact success response, and exact error response.
- **Idempotency:** what happens on a second delete of the same `scheduleid`, and on deleting a
  record already in `ANULAT`?
- Is it recoverable in the evolvo UI afterwards, or is the row gone for good?

**Please do not answer by asking us to try values.** We would be guessing state numbers against
live patient records, and the state space already contains `incheiat` (completed) and
`nu s-a prezentat` (no_show) — a wrong guess could silently mis-mark a real appointment and skew
clinic reporting.

## 2. Slot release semantics — blocking, and probing cannot answer it cleanly

- When an appointment is set to `ANULAT` (`state: 2`), **when does its slot become bookable again**
  via `get_work_days.php`? Immediately, on a schedule, or only after staff action?
- Does hard delete (Q1) behave differently from `ANULAT` here?

Context: in earlier testing a released slot did not reappear for roughly 50 minutes. We need to know
whether that is a cache, a batch job, or staff-driven, because the voice agent offers `earliest`
straight from `get_work_days.php` and would otherwise keep offering a slot that is actually free, or
hide one that is.

## 3. *(reconstructed)* `get_schedule_patient.php` — phone / results_count / name fields

From the workflow sticky note: *"Dolgozik Imre azon hogy telefonszamot tudjon vissza adni az API es
results_count + name fieldeket"* — one phone number often covers a whole family, so we need to tell
household members apart.

- Is this shipped? If so, what are the field names?
- Verified 2026-09-07: `get_schedule_patient.php` does **not** return Agenda/lead records by phone,
  so we currently scan `get_schedule.php` (`schedule_form=0`, 5 windows covering 31 days) and match
  phone + name client-side. Is that still the right workaround?

## 4. *(reconstructed)* A fresh booking is invisible to the read endpoints

After `post_schedule.php` succeeds, the new record has historically **not** appeared in
`get_schedule.php` or `get_schedule_patient.php` on an immediate read.

- Is there a propagation delay? How long?
- Is there a read that reflects a write immediately?

This matters because the voice agent may book and then, in the same call, need to find the record
to cancel or move it.

## 5. Housekeeping — leftover TEST bookings

Two `TEST TEST N8N` / `0700000009` bookings from earlier integration testing need removing by hand.
We have deliberately **not** touched them (they are outside the scope we authorise ourselves to
probe). Please delete them when convenient — or, if Q1 lands, tell us and we will clear them
ourselves.

---

## Answer template (paste back inline)

```
Q1 hard delete:   supported? yes/no
                  endpoint/param:
                  success response:
                  error response:
                  double-delete:
                  already-ANULAT:
                  recoverable in UI:
Q2 slot release:  ANULAT ->
                  delete  ->
                  mechanism (cache / batch / staff):
Q3 get_schedule_patient: shipped? field names:
Q4 write-then-read delay:
Q5 TEST rows removed: yes/no
```
