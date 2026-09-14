# Requests from the ElevenLabs side → n8n

Counterpart to the handover section in [`../README.md`](../README.md). That one lists what n8n needed
from ElevenLabs; this is the other direction. Newest first.

---

## 2026-09-15 — after the first live smoke test

Two calls were run against Main (booking, then cancellation). Full transcripts are in the session
notes; the parts that matter to n8n are below.

### 1. Cancellation: confirm this is the final answer, and say so in the response

The cancel worked — the record went to **`Anulat`** — but the client's expectation was that the row
would *disappear* from evolvo, and it did not. We have told them `Anulat` **is** the cancellation and
that what matters is slot release, not row removal. Before we make that final, confirm our reading is
still right. It comes from
[`slot-release-and-reschedule.md`](slot-release-and-reschedule.md) and the v4 Postman collection, is:

- `update_schedule.php` accepts only states 1/2/3; `state=0` returns `errorcode 3 unknown status`;
- there is **no delete endpoint**, and what Imreh reported was that *cancelling frees the slot*;
- removing the row entirely is a **staff action in the evolvo admin panel**, not an API capability.

**What we need:**

- **(a)** Confirm that is still correct, or tell us if Q9 in
  [`../api-docs/QUESTIONS_FOR_IMREH.md`](../api-docs/QUESTIONS_FOR_IMREH.md) came back differently.
  If a hard delete does exist, we will wire it into `evolvo_manage_appointment` as a separate action.
- **(b)** **Add `slot_released` (boolean) to the cancel response**, ideally with the slot's date/time.
  Right now the agent tells the caller the appointment is cancelled and — per the tool description we
  just shipped — that the time is bookable again. That second half is an inference from your ~8 s
  finding, not something the response actually states. If the release ever lags, the agent is
  confidently wrong to a real caller. A field we can read is better than a rule we assume.
- **(c)** Please confirm the specific smoke-test record released its slot:
  **Pacient Test / `0770355391` / Wed 16 Sept 14:00**. If it did, nothing further is needed and this
  is purely a wording problem on our side.

### 2. Tool latency is now the largest remaining block — `find` and `manage` especially

Measured on the live calls: **tools 1.5–2.5 s**, LLM 1.3–2.5 s. We are removing a forced
pre-tool-speech turn on the ElevenLabs side, which takes out roughly 1.5–3 s per tool call. After
that, the webhook round trip is the biggest single remaining component of a turn.

The known cost centre is documented in your own changelog: `get_schedule_patient.php` does not return
Agenda/lead records by phone, so `FIND` and `MAN` scan `get_schedule.php` in **5 × 7-day windows** —
**6 evolvo calls per lookup instead of 1**.

**What would help, roughly in order of value:**

- **Cache the scan per `conversation_id`.** Inside one call, `FIND` then `MAN` both scan the same
  31 days for the same phone. The second scan is pure waste — the first result could be reused from
  static data with a short TTL, the same mechanism `sd.confirmedPhone` and `sd.pendingResched`
  already use. On the cancel path this alone should remove ~6 evolvo calls.
- **Narrow the window when the caller has named a date.** A caller who says "my appointment on the
  16th" does not need 31 days scanned.
- **Fetch the 5 windows in parallel** rather than sequentially, if n8n's HTTP node allows it here and
  it does not risk the rate limit that produced the Apache 403 documented in
  `QUESTIONS_FOR_IMREH.md` §3. Rate-limit safety wins over speed — do not do this if it is close.
- If any of the above is already in place, tell us and we will stop looking here.

**Also worth asking Imreh:** is a phone lookup that covers agenda entries on the roadmap? That turns
6 calls back into 1 and is the real fix.

### 3. For information — what has now changed on the ElevenLabs side

All shipped and live on Main. No action needed, listed so the two halves stay in step:

- **`pre_tool_speech` is now `auto` (was `force`) on all five tools.** The agent **no longer always
  speaks before a webhook fires**. If anything on your side depends on the caller hearing a holding
  line before a call lands — a timing assumption, a debounce, anything keyed to that extra turn —
  **say so and we will reconsider**. This is the one change here that could affect you.
- The scripted "Un moment, vă rog." is gone from the prompt and from all three procedures. Fillers
  are now latency-triggered (`soft_timeout_config`, 3 s) and LLM-generated so they follow the
  caller's language. A slow webhook is now *less* audible than it used to be, not more.
- `evolvo_book_appointment`, `evolvo_manage_appointment` and `evolvo_find_appointments` descriptions
  carry the `replaced_appointment` contract, the mark→book ordering, and `needs_reschedule`
  semantics, as the README handover asked.
- Two live wording defects were fixed on our side, both ours, neither yours: the agent was telling
  callers *"Clinica vă va confirma programarea"* on the `lead_pending_staff_confirmation` path. It
  now says a colleague will call back. If you ever see a transcript where the agent promises a
  confirmation, that is a bug on our side — please flag it.

---

## How to reply

Edit this file in place under each item, or add a dated section to
[`CHANGELOG.md`](CHANGELOG.md) and link it here. The ElevenLabs side reads both.
