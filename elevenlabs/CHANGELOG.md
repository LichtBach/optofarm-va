# ElevenLabs changelog

Newest first. Agent `agent_3101kyq03vpxfpb9vsskgfh2f0bd` (*Optofarm Agent - DEMO*). Tools are
workspace-level and therefore live on every branch the moment they are saved; procedures are
branch-scoped and need a version committed before they reach calls.

## 2026-09-15 (later) — booking optimisation ported onto Main, and cancel stops guessing

Two things landed together, because the first depends on prompt sections the second brought with it.

### 1. The booking optimisation is now on Main — but it was not a copy

`latency-step-merge` held the 26.5 %-reduced `booking` procedure. A straight merge would have been
wrong twice over: per-item newest-wins would have let Main's newer `booking` beat the optimised one,
and the optimised procedure **delegates to prompt sections Main did not have**. It says *"add the
reminder sentence exactly as your system prompt gives it for this language, and follow that section"* —
and Main had no such section. Porting the procedure alone would have pointed the agent at nothing.

So the port took the branch's prompt as the base and re-applied today's work on top. What Main gained:

- **`## What the caller is told they will receive`** — the section the procedure depends on, with
  *"Vă trimitem o notificare înainte de programare."* / *"Az időpont előtt küldünk egy emlékeztetőt."*
  and the rule that a reminder is the only thing ever sent.
- **A guardrail that kills the whole defect class**: *"Optica Optofarm is an optician's, not a clinic
  and not a hospital. Never call it a clinic in any language."* Plus *"Never promise the caller a
  confirmation of any kind that reaches them."* The `Clinica vă va confirma` bug was a symptom; this
  is the cause, removed. The Personality line now says *a network of opticians and optical stores…
  where eye examinations are also carried out*, so the prompt no longer contradicts its own guardrail.
- **Confirmed landmarks for all eight branches**, replacing the single Republicii landmark, with the
  proper-noun list (Kaufland, Flanco, BRD, BCR, Orange, Petrom, Penny, Elixon, Kimikálé, Poli 2,
  Bernády, Avram Iancu, Casa de Modă) that must not be translated.
- **The negotiation fix**: *"a caller proposing an alternative has not given up."*

Re-applied on top, so nothing from earlier today regressed: the vary-or-drop holding-line rule, the
three removed *"say a short holding line and call…"* mandates, and the explicit
*"never say that the clinic, the practice or anyone else will confirm it"* clause on the exact line
that shipped the defect.

**The optimised procedure also fixes the ordering leak** flagged this morning. Main's old wording
(*"never check availability before the branch or doctor AND the purpose are known"*) was a rule the
agent walked past. The ported version turns it into a stop condition: *"DO NOT LEAVE THIS STEP until
BOTH … are known. Being told only the branch is NOT enough to move on."* Worth watching on the next
smoke test rather than assuming it is fixed.

Measured on the compiled workflow: **31 nodes / 34 edges → 27 / 30**, and 134,935 → 120,299 chars,
**−10.8 % across all three procedures** (the booking procedure itself is −26.5 %).

### 2. Cancel now reads `slot_released` instead of asserting it

n8n shipped this (their reply in [`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md)
§1(b)). It matters more than it looks. The agent was telling callers the cancelled time was bookable
again on the strength of a **~8 s measurement**, not on anything in the response. n8n's own
investigation showed why that was fragile: for the smoke-test record the slot could not be verified
at all, because **that calendar alternates morning and afternoon shifts and 14:00 was not in that
day's window**. Absence from the free list does not mean blocked — it can mean the provider is not
working then. Hence `unknown` being a separate status from `still_blocked`.

Changed in three places so they agree:

- **`evolvo_manage_appointment` description** — *"its slot becomes bookable again within seconds"* is
  gone. It now reads `slot_released` / `slot_release_status` / `note`, and says the time is free only
  when `slot_released` is true. The `action` enum description was carrying the same assertion and was
  fixed too.
- **`cancel_or_reschedule`**, cancel step — same contract, with *"WHETHER THE TIME IS FREE AGAIN IS
  NOT YOURS TO ASSUME"* and an explicit ban on stating it from memory.
- **System prompt**, § Cancelling or changing an appointment — one line so the rule holds outside the
  procedure too.

Also dropped the `HOLDING LINE:` block from `cancel_or_reschedule` — the system prompt now carries
the vary-or-drop rule, so repeating it per-step is cost without benefit. The ported `booking` never
had one. `escalate_to_human` still does; harmless, and it can go next time that file is touched.

### Versions

| procedure | new version |
| --- | --- |
| `booking` | `agtprcv_6301m2g9hk29enxv4bb6ty78h6q6` |
| `cancel_or_reschedule` | `agtprcv_0401m2g9hk2mf1t8gn8eahd7qwx8` |
| `escalate_to_human` | `agtprcv_6101m2g75y6tfe5bkn0khjztnbyh` (unchanged) |

### Status of `latency-step-merge`

**Do not merge it.** Everything it carried that was worth having is now on Main, re-merged with
today's fixes rather than overwriting them. Its own copies are now the stale ones — its prompt still
has the scripted `Un moment, vă rog.` and the `— and nothing else` clause. Re-branch from Main if a
branch is needed again.

### From the n8n side, for the record

Their reply also confirmed: `Anulat` **is** the cancellation and that reading should stand (Q9 still
unanswered by Imreh, nothing blocked on it); the cancel path went **7 evolvo calls → 3** via a
`conversation_id` cache and a narrowed window; parallel fetching was deliberately **not** done on
rate-limit grounds; and `pre_tool_speech: auto` is safe — nothing on their side keys off the holding
line. Their one timing caveat, worth knowing if a read-back ever double-prompts: a **5-second replay
guard** on `phone_confirmed` / `appointment_confirmed`, which a real read-back never comes near.

## 2026-09-15 — first live smoke test: robotic repetition, and the last two copies of the "clinic will confirm" defect

Two live calls were run against **Main** (a booking, then a cancellation). Three problems came out of
them; all three are fixed below. n8n-side asks from the same calls are in
[`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md).

### 1. The agent sounded like a machine — `Un moment, vă rog.` before every single tool call

Root cause was three things stacked, not one:

1. **`pre_tool_speech: "force"` on all five tools.** `force` guarantees the agent speaks before every
   webhook fires. It also costs a **full extra LLM + TTS round trip per tool call** — so it was
   feeding the latency complaint at the same time.
2. **The system prompt scripted the exact words** and closed them off: *"say once and only in the
   caller's language: Romanian "Un moment, vă rog." … **— and nothing else**"*. That last clause
   forbade the variation that would have made it sound human.
3. **Each procedure step scripted the same sentence again**, so even a model inclined to vary had the
   literal string in front of it three more times.

Meanwhile `soft_timeout_config.timeout_seconds` was **`-1`** — the proper mechanism for this,
a latency-*triggered* filler, was switched off entirely.

**Fixed:**

- All five tools: `force_pre_tool_speech: false`, `pre_tool_speech: "auto"`. The agent now speaks
  before a webhook only when it judges it useful, instead of always.
- **`soft_timeout_config` enabled**: `timeout_seconds: 3`, `use_llm_generated_message: true`,
  `randomize_fillers: true`, `max_soft_timeouts_per_generation: 1`. This is the part worth
  understanding — a language-aware filler prompt was **already sitting in the config, unused**
  (`llm_generated_message_prompt_override`: *"Output ONLY a very short filler of one to three words,
  in the language the caller has been speaking…"*). Static fillers could never solve this, because
  `message` is one fixed string and the prompt forbids saying *Un moment* to a Hungarian caller.
  The generated path is the only one that is language-aware, and it now fires **only when a turn is
  actually slow**, rather than on every tool call.
- **System prompt** (§ Language): the scripted line and its *"— and nothing else"* are replaced with
  a vary-or-drop rule — silence before a lookup is explicitly allowed and preferred, and reusing a
  holding phrase already used in the same call is forbidden.
- **System prompt**, three further places: *"say a short holding line and call evolvo_…"* → *"call
  evolvo_…"*. These mandated speech before `book_appointment`, `find_appointments` and
  `log_request`; they no longer do.
- **All three Main procedures**: every scripted `Un moment, vă rog.` replaced with a `HOLDING LINE:`
  block that permits silence, requires variation, and offers two or three per-language options
  instead of one fixed sentence.

### 2. The "clinic will confirm it" defect had **three** copies, not one

The 2026-09-14 entry below records fixing this in `cancel_or_reschedule`. The smoke test proved that
was only a third of it — the agent said *"Clinica vă va confirma programarea"* on a **booking**.
Two more copies were live:

- **Main's `booking` procedure**, `evolvo_book_appointment` step — *"say the request is registered for
  that day and time and the clinic will confirm it."*
- **The system prompt**, § Appointment flow — the same sentence again.

Both now say a colleague will call back about it, and both explicitly forbid claiming that the
clinic, the practice or anyone else will confirm the appointment. `evolvo_book_appointment`'s tool
description was updated to match in the same pass, so the tool and both procedure copies now agree.

Also in `booking`: *"the full name exactly as registered at the clinic"* → *"…as it is registered
with us"*, removing the last spoken-facing use of the banned word in that step.

### 3. Latency

`pre_tool_speech: force` was removing roughly **1.5–3 s per tool call** in pure overhead — that is
the single largest ElevenLabs-side win available and it is now taken. What remains is the webhook
round trip (tools measured 1.5–2.5 s), which is n8n's side: the `FIND`/`MAN` paths scan
`get_schedule.php` in 5 × 7-day windows, **6 evolvo calls per lookup**, and do it twice in a cancel
call. That ask is written up in
[`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md) § 2.

### 4. "It went to ANULAT but wasn't deleted" — this is correct behaviour, not a bug

There is still **no hard delete** in the API (see the 2026-09-14 entry and
[`../api-docs/QUESTIONS_FOR_IMREH.md`](../api-docs/QUESTIONS_FOR_IMREH.md) Q9). `ANULAT` **is** the
cancellation. What matters operationally is not whether the row disappears but whether the **slot is
released** — and the n8n side measured that at ~8 s. Removing the row entirely is a staff action in
the evolvo admin panel. Confirmation of the release for the smoke-test record is asked for in
`REQUESTS_FROM_ELEVENLABS.md` § 1(c), along with a request for a `slot_released` flag in the
response so the agent stops *inferring* it.

### Versions

Procedures committed on Main (all three, `has_draft: false` afterwards):

| procedure | id | new version |
| --- | --- | --- |
| `booking` | `agtprc_7801m0axd3y3ej590n280yw80rr0` | `agtprcv_0301m2g75y71f5vb0z9zkp9frepf` |
| `cancel_or_reschedule` | `agtprc_4901m0axdt4zev9tmgtcxy60x9da` | `agtprcv_7501m2g75y78ez09wavaz0sjhqjv` |
| `escalate_to_human` | `agtprc_4401m0axbt3rfcfvpj4grmp73wph` | `agtprcv_6101m2g75y6tfe5bkn0khjztnbyh` |

### Gotcha worth recording

`agents_update` **does** commit pending procedure drafts — but the `workflow` block it echoes back in
its response is the **pre-update** snapshot. Reading that response will tell you the drafts did not
commit. Verify with `agents_list_procedures` (`has_draft: false` plus a changed `version_id`) or
`agents_compile_procedures` (which then answers `no_draft_to_compile`), never with the update's own
echo.

Separately: `agents_update` with a partial `body` is a **deep merge**. Patching
`conversation_config.turn.soft_timeout_config` alone left `prompt.tools`, `tool_ids` and everything
else untouched — verified after each write. That is the safe way to change one setting without
restating the whole config, which is what caused the `prompt.tools` incident in the README.

### Still open

- `latency-step-merge` has not been merged. It still holds the 26.5 %-reduced `booking` procedure and
  the Romanian `notificare` wording, and it does **not** have any of today's changes. Per-item
  newest-wins means Main's newer `booking` would now win over the branch's optimised one, so the
  optimisation needs re-porting rather than merging. Merge with `archive_source_branch: false`.
- Ordering leak, seen in the transcript: the agent called `check_availability` before the purpose of
  the visit was known, then backfilled the question after the slot was accepted. The `booking`
  procedure already forbids this (*"never check availability before the branch or doctor AND the
  purpose are known"*), so this is a compliance problem, not a missing rule. Worth watching on the
  next smoke test before adding more prompt text.

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
