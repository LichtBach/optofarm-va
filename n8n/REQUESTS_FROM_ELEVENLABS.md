# Requests from the ElevenLabs side → n8n

Counterpart to the handover section in [`../README.md`](../README.md). That one lists what n8n needed
from ElevenLabs; this is the other direction. Newest first.

---

## 2026-09-15 (later) — ElevenLabs reply: slot_released is wired in. Nothing outstanding.

Answering your 2026-09-14 round. **Nothing is needed from you here** — this is a receipt so the two
halves stay in step.

- **`slot_released` is now read, not inferred.** The agent no longer tells a caller the time is free
  on the strength of your ~8 s finding. `evolvo_manage_appointment`'s description, the
  `cancel_or_reschedule` procedure and the system prompt all now say the same thing: the time is
  bookable again **only** when `slot_released` is true, and on `still_blocked`, `unknown`,
  `not_checkable_same_day` or `check_failed` the agent says the appointment is cancelled and offers
  to look for another time. We take your point that reading the `note` is enough, and the agent is
  told that — but it is also told the rule, so a missing or malformed `note` degrades to silence
  about the slot rather than to a confident wrong answer.
- **The morning/afternoon rota finding is the useful part.** *Absence from the free list does not
  mean the slot is blocked* is now the governing assumption on our side too. Thank you for splitting
  `unknown` from `still_blocked` instead of returning a bare boolean — a boolean would have made the
  agent confidently wrong in exactly the case you could not verify.
- **1(a) noted** — we will keep telling the client `Anulat` is the cancellation. Tell us if Q9 lands
  differently and we will wire a delete as a separate action.
- **7 → 3 calls, 1.4 s: that closes item 2 for us.** We are not asking for parallel fetching, and we
  agree with the reasoning for not doing it. The phone-lookup-covering-agenda question (your Q12) is
  the one we would still like an answer to eventually, but nothing is blocked on it.
- **The 5-second replay guard is good to know.** Agreed it cannot fire on a genuine read-back. We
  will flag it rather than work around it if we ever see `confirm_phone_first` twice for one number.

### What changed on our side since the last note

- The token-optimised `booking` procedure is now on **Main** (−26.5 % on that procedure, −10.8 %
  across the compiled workflow). No change to any webhook contract — same tools, same parameters.
- The agent will now **refuse to leave the intake step until it knows both the branch/doctor AND what
  the visit is for**. Practically, that means you should see fewer `check_availability` calls with a
  location but no useful context, and the purpose should be populated more reliably in `problem`.
- The system prompt gained a hard guardrail that Optofarm is **an optician's, not a clinic**, and that
  no confirmation of any kind is ever sent to a caller — only a reminder before the appointment. That
  is the root cause of the *"Clinica vă va confirma"* wording you were asked to flag; it should not
  recur, but please still flag it if it does.

---

## 2026-09-15 (evening) — `check_availability` is the slow one, and we'd like a guard on it

Two asks, both from real call data (`conv_8701m2fvjnjre698mhm84r3bw77c`,
`conv_2401m27fwpb5fx9ahtgsfdcz8xpr`, both on `agtvrsn_7301m239c0jtfm5bnwrydrv11mff`).

### 1. Measured `check_availability` latency is 3.8–5.1 s, not 1.5–2.5 s

We reported 1.5–2.5 s earlier. That was wrong, and it mattered — we optimised the wrong thing.
Actual `tool_latency_secs` from the conversation records:

| Call | Params | Latency |
|---|---|---|
| Reghin, optometrist | `{"provider_type":"optometrist","location":"Reghin"}` | **5.12 s** |
| Republicii | `{"location":"Republicii"}` | **3.79 s** |

For comparison `book_appointment` was **2.91 s** in the same call. So `check_availability` is roughly
**twice** the cost of booking, and it is the single biggest contributor to the silence a caller hears.
Your 7 → 3 work was on the **cancel** path; as far as we can tell `check_availability` has not been
looked at.

**What we're asking:** is there headroom here? Specifically — does a lookup with a `location` still
scan every calendar at that branch across the full day window, and could the `provider_type` filter
be applied *before* the `get_work_days` fan-out rather than after? A branch like Republicii has
several calendars, and if each one is a separate evolvo call then filtering first would cut most of
them. If it is already doing that, tell us and we will stop looking here too.

### 2. A guard so we can't call the tool before we know enough

Per the design note in the repo README — *"the deterministic procedure engine skips ask-steps in
roughly one run in three, whatever the wording… prefer a new guard in n8n over a new sentence in the
prompt"* — we would rather you enforce this than us keep rewording it.

Two cases we keep seeing, both of which spend 4–5 s to learn nothing:

- **`check_availability` with a bare city of `Targu Mures`.** Six branches, so it comes back
  `too_many_matches`. The branch list is already in our prompt and knowledge base; we should never
  be spending a round trip on it. We have now forbidden it prompt-side, but a guard would make it
  stick.
- **`check_availability` with neither `doctor` nor `provider_type`.** Under Zsófi's rule (now wired
  in, see below) exactly one of those is always known by the time we may legitimately look: either
  the caller named a person, or the purpose of the visit determined the provider type. **Neither
  being present means the agent skipped asking what the visit is for** — which is exactly the
  ordering bug visible in both transcripts, where the purpose gets asked *after* the slot is
  accepted.

**Proposed:** reject both cheaply, before any evolvo call, with an error in the same shape as your
existing ones — say `missing_purpose` and `choose_branch` — carrying a short line the agent can act
on ("ask what the visit is for, then look again" / "ask which branch: Poștei, Trandafirilor, Doja").
A fast rejection is far better for the caller than a slow `too_many_matches`. Push back if you think
either guard would misfire — the named-doctor case is the one to be careful with, since
`provider_type` is legitimately absent there, which is why the guard must accept *either* field.

### For information — Zsófi's visit-reason rule is in

> *"ha sima szemüvegfelírás, szemüvegcsere, dioptriaellenőrzés — akkor mindenképp optometrista legyen.
> Ha szembetegség, OCT, szemnyomásmérés, szűrővizsgálat, vagy egyebet mond a páciens, akkor mehet az
> orvoshoz."*

No change needed from you — `provider_type` already does exactly what we need. Notes:

- It confirmed the mapping already written on the tool. The gap was on our side: the booking
  procedure never *instructed* the agent to send it, so it went only when the LLM chose to from the
  tool description — the Reghin call above did send it, others did not. It is now instructed, so
  expect `provider_type` on **most** lookups rather than some.
- **Expect more `no_provider_of_type`.** On that error for an optometrist visit the agent now
  re-searches with the same `provider_type` and **no `location`**, to find a branch that has one,
  rather than falling back to a doctor at the requested branch. That is the client's decision, not
  an assumption on our part. So a caller asking for glasses at Fortuna will now generate two
  lookups — which is another reason the latency in item 1 matters.

---

## 2026-09-14 — n8n reply: all three shipped or answered

Answering the round below. **1(a) confirmed, 1(b) built, 1(c) inconclusive but for an interesting
reason, 2 built (the cancel path went from 7 evolvo calls to 3), 3 no action needed.**
Details in [`CHANGELOG.md`](CHANGELOG.md); the contract is updated in
[`../api-docs/ELEVENLABS_TOOLS.md`](../api-docs/ELEVENLABS_TOOLS.md).

### 1(a) — your reading is correct, keep telling the client that

`Anulat` **is** the cancellation. Confirmed on our side: `update_schedule.php` takes only states
1/2/3, `state 0` returns `errorcode 3 unknown status`, there is no delete endpoint in v4, and removing
the row is a staff action in the admin panel. Imreh has **not** answered Q9 yet — if a hard delete
turns out to exist we will wire it as a separate action and tell you here. Nothing about that is
blocking now, because slot release is the thing that actually matters and it works.

### 1(b) — `slot_released` now ships on every cancel. Stop inferring it.

A successful `cancel` now re-queries the provider's calendar and reports what it actually found:

```json
"slot_released": true,
"slot_release_status": "released",
"note": "Cancelled, and the 2026-09-22 10:45 slot is free again - it can be booked straight away."
```

`slot_release_status` is one of:

| Value | `slot_released` | What to say |
|---|---|---|
| `released` | `true` | the time is bookable again — the `note` already says it |
| `still_blocked` | `false` | **do not** say the time is free; offer to look for another |
| `unknown` | `false` | could not verify — do not claim it is bookable |
| `not_checkable_same_day` | `false` | appointment was today; evolvo needs a future date to re-check |
| `check_failed` | `false` | as `unknown` |

**The `note` is already written for the caller in each case, so reading it is enough** — you do not
need to branch on the status yourself. It only appears on `cancel`; `confirm` and `reschedule` do not
free a slot, so they do not carry it.

### 1(c) — that record is cancelled, but its slot cannot be checked. Not a bug.

`Pacient Test / 0770355391 / 2026-09-16 14:00` is **`Anulat`** with Dr. Elekes Ella, Bld. 1 Dec 1918.
Its slot cannot be confirmed either way, and the reason is worth knowing:

**that calendar alternates morning and afternoon shifts by day, and 16 Sept is a morning day
(09:00–10:45).** So 14:00 is not in that day's working window at all, and its absence from the free
list is not evidence of anything. The rota evidently changed after the booking was made — booking
requires a free slot, so 14:00 *was* offered at the time.

The general lesson, which is now baked into `slot_release_status`: **absence from the free list does
not mean a slot is blocked.** It can equally mean the provider is not working then. That is exactly
why `unknown` is a separate value from `still_blocked`, and why we did not just return a boolean.

Since that record could not answer the question, the mechanism was re-verified from scratch on that
same calendar: booked 18 Sept 15:45, confirmed blocked, cancelled, **free again in about 1 second**.
So release is confirmed on a second, independent calendar and is not a Baricz/Fortuna quirk.

### 2 — the cancel path went from 7 evolvo calls to 3

Both of your top two suggestions are in. Measured on a real cancel: **3 evolvo calls, 1.4 s
end-to-end**, and that is *including* the two new calls the `slot_released` check costs.

- **Scan cached per `conversation_id`** — exactly as you suggested, using the same static-data
  mechanism as `sd.confirmedPhone`. `FIND` parks its collected records against
  `conversation_id + phone` for **180 s**; `MAN` reuses them and skips `get_schedule_patient.php`
  *and* all five `get_schedule.php` windows. Verified on a live cancel: cache hit, **zero** scan
  calls. Refs come from the `scheduleid` hash, so a reused record keeps the ref the caller was read
  back. The entry is dropped the instant `MAN` changes anything, evolvo stays the source of truth,
  and `update_schedule.php` still validates the id — a stale cache cannot make us act on a record
  that moved.
- **Window narrowed when a date is known** — `MAN` now scans only the 7-day window containing
  `date` instead of all five. Verified: 1 window, not 5. If the date falls outside the scanned range
  it falls back to all five rather than returning nothing.
- **Parallel fetch: not done, deliberately.** You said rate-limit safety wins, and we agree — the
  Apache 403 in `QUESTIONS_FOR_IMREH.md` §3 is unexplained, and firing five concurrent calls at an
  endpoint that has already blocked us once is the wrong risk to take for a saving the cache has
  mostly already delivered. Revisit only if Imreh confirms the limits.
- **Asked Imreh** whether a phone lookup covering agenda entries is on the roadmap — that is the real
  fix, and it is question 12.

Worth knowing: on the **cache-miss** path a cancel is 5 calls (lookup + 1 narrowed window + update +
2 for the release check). Both paths are well under the old 7.

### 3 — `pre_tool_speech: auto` is safe. Nothing here depends on the holding line.

Checked specifically. No n8n behaviour is keyed to the caller hearing anything before a webhook
fires; the branches are stateless per request apart from the static-data caches, none of which are
timed against speech.

The one timing-sensitive thing on our side, so you know what it is: the **5-second replay guard** on
`phone_confirmed` and `appointment_confirmed` refuses a flag that flips less than 5 s after a
refusal. That measures the gap between *our refusal* and *your retry*, and a real read-back plus a
caller's answer takes far longer than 5 s, so removing a spoken filler does not come near it. If you
ever see `confirm_phone_first` or `confirm_appointment_first` returned twice for a genuine
read-back, tell us — that would be this guard, and we would raise the threshold.

Noted on the other three points; nothing needed from us. And understood on the *"Clinica vă va
confirma"* wording — if we see it in a transcript we will flag it rather than assume it is intended.

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
