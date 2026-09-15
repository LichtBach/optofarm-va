# ElevenLabs changelog

Newest first. Agent `agent_3101kyq03vpxfpb9vsskgfh2f0bd` (*Optofarm Agent - DEMO*). Tools are
workspace-level and therefore live on every branch the moment they are saved; procedures are
branch-scoped and need a version committed before they reach calls.

## 2026-09-16 — system prompt slimmed: the procedures own the flows, the prompt owns the facts

The prompt had grown into a second copy of the procedures. Three whole sections re-specified, less
precisely, what the procedures already handle step by step — so the model read one version of the
booking flow in its system prompt and a more detailed, more current version again when the procedure
opened. Removed:

| Section | Size | Now owned by |
|---|---|---|
| `# Appointment flow` | 2,397 ch | `booking` procedure |
| `## Cancelling or changing an appointment` | 2,177 ch | `cancel_or_reschedule` procedure |
| `# Escalation flow` | 1,249 ch | `escalate_to_human` procedure |
| `# Decision logic` | 863 ch | the procedure triggers themselves |

**29,633 → 24,436 characters, −17.5 %.**

### What replaced them

One short section, `# What you can do, and how the work is organised`, which states the division of
labour outright — *"This prompt holds who you are, how you speak, and the facts you know. The
step-by-step handling of each job lives in your procedures"* — and then lists the four things the
agent can do for a caller. That list is the point: a caller asking *"can you book me in?"* or *"can
you tell me if my glasses are ready?"* is answered from the prompt, plainly, **without a procedure
loading to answer a question about capability.**

### What had to be kept, and was checked individually

The procedures reference the prompt by name in five places. Each target was verified present in the
new text before sending:

- **`## The phone read-back gate`** — both `booking` and `cancel_or_reschedule` say *"apply the phone
  read-back gate exactly as your system prompt defines it"*.
- **`## Branch names — normalize with this table everywhere`** — the booking intake step normalises
  against it.
- **`## What the caller is told they will receive`** — the book step and the reschedule step both say
  *"add the reminder sentence exactly as your system prompt gives it for this language"*.
- **Both reminder strings verbatim**, Romanian and Hungarian. Cutting or paraphrasing either would
  have silently broken the one sentence every successful booking ends on.

Rules that lived *inside* the removed sections were not dropped — they moved to where they belong:

- *never tell a caller a colleague will ring them back about a booking that succeeded* → **Guardrails**
- *never invent a branch the caller did not name* → folded into the existing "never invent" guardrail
- *a cancelled appointment is recorded as cancelled, never say deleted or removed* → **Guardrails**
- *Târgu Mureș has six branches, so the city alone is not enough to look up a time* → **Locations**,
  where the branch facts already are
- the booking form on the website, and the rescheduling fallback → the new capability section

`# Step 0 — Medical urgency` was compressed from 2,043 to about 1,400 characters but deliberately
**not** delegated to the booking procedure, even though that procedure has its own emergency branch.
Step 0 has to fire anywhere in a call — mid-cancellation, mid-question — not only once a booking is
under way.

Nothing else moved: `pre_tool_speech` stays auto on availability and manage, off on the other three;
`speculative_turn` false; soft timeout -1. Verified byte-for-byte against the intended text apart from
one trailing newline.

## 2026-09-15 (late night, 3) — `pre_tool_speech: auto` on the two tools the caller actually waits on

Client request: put `pre_tool_speech` back to **`auto`** on `evolvo_check_availability` and
`evolvo_manage_appointment`, so the agent decides from recent execution times whether to speak before
the call. Done — those are the right two: they are the slowest and the most variable (availability
has been measured anywhere from 0.9 s to 5.1 s depending on search width). The other three stay
`off`.

| tool | pre_tool_speech |
|---|---|
| `evolvo_check_availability` | **auto** |
| `evolvo_manage_appointment` | **auto** |
| `evolvo_book_appointment` | off |
| `evolvo_find_appointments` | off |
| `evolvo_log_request` | off |

### The setting alone would have done nothing

The prompt said *"NEVER say a holding line, a filler, or an acknowledgement… not before a lookup, not
before a question, not before anything."* That is a flat ban, so `auto` would have asked the agent to
speak and the prompt would have told it not to — a direct contradiction, resolving either to silence
(the setting wasted) or to a banned phrase.

So the ban was narrowed rather than lifted. What changed:

- **Acknowledgements stay banned outright** — no *"Bine"*, *"Rendben"*, *"Perfect"*, *"Înțeleg"*,
  *"Desigur"*. This was the *"shouldn't approve the user"* half of the complaint and none of it is
  about latency.
- **Holding lines stay banned in front of a plain question, a known fact, or anything the agent is
  not actually waiting on** — which is what produced *"Verific acum."* before a simple question.
- **One exception, deliberately narrow:** before a lookup that will take a moment, and **only when
  the system itself prompts speech first**, one short phrase of a few words. That clause is what
  `auto` triggers, so nothing else in the call gains permission.
- **The anti-repetition rule is kept and strengthened inside the exception**: it *must* differ from
  every holding phrase already used in the call, and *"silence is always better than repeating
  yourself."*

The distinction that matters: the agent may now speak **when it is genuinely waiting**, and only
then. Every previous complaint was about it speaking when it was **not** waiting — before questions,
before facts it already had, and with the same words every time.

### Worth watching

`auto` judges from *recent* latency, so early in a call it has little to go on and may speak before a
fast lookup. If a phrase reappears before turns that are obviously quick, the honest options are
`off` on `check_availability` again, or accepting it as the price of covering the slow tail. Nothing
else changed: `speculative_turn` still false, soft timeout still -1, and the no-callback-on-success
rule from the previous entry verified still in place.

## 2026-09-15 (late night, 2) — a successful booking no longer promises a callback

Client correction: **nobody rings a caller back after a booking succeeds.** The only thing they
receive is the reminder before the appointment, which the agent already says correctly. The callback
promise was left over from when `lead_pending_staff_confirmation` was understood as "a request that
staff still have to action", and it was making a finished appointment sound unfinished — the caller
hangs up expecting a phone call that never comes.

The rule now: **when `success` is true the appointment is made, whatever `booking_mode` says.** Both
modes are simply booked as far as the caller is concerned, said in the same final tone, followed by
the reminder sentence and nothing else. `booking_mode` is never mentioned to a caller.

Changed in the four places that carried it, so they cannot drift apart:

| Where | Was | Now |
|---|---|---|
| System prompt, *Appointment flow* | *"say the request is registered… and that a colleague will call back about it"* | booked in the same final tone either way, then the reminder; never a callback on a booking that succeeded |
| System prompt, *What the caller is told they will receive* | the reminder sentence | + *"That reminder is the ONLY thing a caller is ever told they will receive after a booking — no confirmation, and no phone call from a colleague."* |
| `booking` procedure, book step (`agtprcv_8801m2gj1qkafygtq7frfmck21k9`) | same callback line | same rule, with the reason spelled out: it leaves them waiting for a call that never comes |
| `evolvo_book_appointment` description | *"say the time is registered and that a colleague will call back about it"* | `booking_mode` explained as internal-only; **NEVER TELL A CALLER A COLLEAGUE WILL RING THEM BACK ABOUT A BOOKING THAT SUCCEEDED** |

Also applied to the **reschedule** path in `cancel_or_reschedule`
(`agtprcv_4901m2gj1qkqevjb2ar3p0nqd450`), which ends in a booking and carried the same promise.

### What deliberately kept its callback promise

A callback is still the right thing to say wherever the booking **did not happen**, and every one of
those was left alone — removing them would have been the opposite error:

- the booking tool erroring, timing out or being unreachable;
- `evolvo_log_request` succeeding — that IS a callback request, and the procedure now says so
  explicitly (*"This is a callback request, not a booking, so here a colleague calling back is
  exactly right and must be said"*) so the new rule cannot bleed into it;
- a reschedule where no new time could be booked — the old appointment still holds its slot and a
  colleague does pick it up;
- no appointment found on the number, and the unknown-information protocol.

Four mentions survive in the prompt, all checked individually and all on those paths.

## 2026-09-15 (late night) — `conv_5301m2ggh93feecvv9cahfg7pymv`: a regression I caused, plus a turn-taking fault

This call ran on `agtvrsn_7901m2gfstdefjx9v816mvp2eyfr`, which **did** have every fix: the
holding-line ban in the prompt, `soft_timeout -1`, `pre_tool_speech: off` on all five tools, the
schema enums. Verified by reading that exact version back. So none of the three faults below is a
stale-version artifact.

| Time | What happened |
|---|---|
| 47 s | Agent asks *"La ce punct de lucru doriți programarea?"* — **and `notify_condition_1_met` fires in the same second**, advancing the procedure past the ask |
| 49 s | *"Un moment, vă rog."* |
| 55 s | Caller: *"Am— alo?"* — twelve seconds of dead air |
| 61 s | `check_availability` called with **`location: "Postei"`** — the caller never said Poștei |
| 65 s | The offer is emitted **twice, byte-identical, concatenated with no space**: *"…Vă convine?Am marți…"* |

### 1. The invented branch is mine, and it is the serious one

An hour earlier I added `required_constraints.any_of` requiring one of `location`/`doctor`/`city`,
to stop the model calling the tool with no target. **It did stop that — by making the model fabricate
a target instead.** Needing to call and having no branch, it satisfied the schema with `Postei`.

That is strictly worse than what it replaced. A `missing_target` error costs two seconds and tells
the agent to go and ask. A fabricated branch sends a real person to the wrong shop, and **the caller
has no way to detect it** — the agent sounds exactly as confident either way. I traded a safe error
for a silent wrong answer.

**Reverted.** `required_constraints` is gone; `missing_target` is the designed and safe outcome, and
the tool description now says so at length, including *"Guessing a branch the caller never said is
the worst mistake available here… An error costs two seconds; a wrong branch costs them a wasted
journey."* The `location` description says to leave it out when the caller has not named one, and
explicitly not to carry over a branch merely mentioned while listing locations — which is where
`Postei` most likely came from, since the agent had just recited the locations at 21 s.

**The enums stay.** `city: ["Reghin","Sovata"]` and the eight-branch `location` enum constrain
*values*, and cannot induce invention the way a required-field constraint does. That distinction is
the lesson: a schema constraint that narrows a value is safe; one that forces a field to be present
pushes the model to make something up.

### 2. The duplicated utterance is a turn-taking fault, not a prompt problem

No prompt can produce a byte-identical repeat concatenated without a space. That is one turn
generated twice. The likely mechanism: **`speculative_turn: true`** — the agent speculatively
generates before the turn resolves, the caller spoke *into the silence* at 55 s while a tool call was
in flight, and both generations reached TTS.

**`speculative_turn` is now `false`.** Stated as the leading hypothesis, not a proven cause — it is
the only setting that can produce two generations of one turn, but the duplication happens inside
ElevenLabs' orchestration and cannot be confirmed from here. If it recurs with speculation off, the
next suspect is the interaction between `retranscribe_on_turn_timeout` and a caller speaking during a
tool call, and it becomes a question for ElevenLabs support.

Also set `interruption_mode: allow` on `check_availability` (was `disable_during_tool`). That mode
existed to stop callers cutting across the agent mid-lookup — but with `pre_tool_speech: off` the
agent is now **silent** during a lookup, so there is nothing to interrupt, and all the setting did
was discard the caller's *"alo?"* instead of letting it land.

### 3. "Un moment, vă rog." survived an explicit ban

The prompt names that exact phrase and forbids it. Every configured source is off. So this is the
model disregarding a direct instruction — the same class of failure as the three tool calls earlier
tonight, and more evidence for the README's design note.

There is nothing further to tighten in wording; it is already explicit and named. What is worth
noting is *where* it appeared: covering a **twelve-second stall** after the procedure advanced past
its own question. The filler was a symptom of the stall, not the disease. If the stall goes away, the
filler has nothing to cover.

### 4. The stall and the skipped ask are the root cause

`notify_condition_1_met` fired in the **same second** as the question was asked, so the procedure
moved into the availability step before the caller could answer. The agent then sat for twelve
seconds, filled the silence, invented a branch and called the tool. Everything else in this call
follows from that.

This is the ask-step skipping the README documents at roughly one run in three, and it is now the
highest-value thing left. It cannot be fixed with more prompt text — that has been tried tonight and
failed twice. The durable fix is the n8n guard already requested: reject a lookup that carries
neither `doctor` nor `provider_type`, and now also one whose `location` the transcript never
contained, so a fabricated branch is refused server-side rather than trusted.

## 2026-09-15 (late) — holding lines banned outright; what the calendar screenshot actually shows

### The prompt still *permitted* the phrases

`pre_tool_speech` is off on all five tools and the soft timeout is back to -1, but the prompt's
Language section still said *"If you do say something, keep it to a few words… vary it, or drop it."*
That is permission, and the model took it — which is how *"Verific acum."* survived. It also did not
cover acknowledgements at all, so *"Bine."* was never forbidden.

Replaced with a flat ban, naming the offenders:

> *"NEVER say a holding line, a filler, or an acknowledgement before you answer or before you look
> something up. No "Un moment", no "Verific acum", no "Verific disponibilitatea", no "Egy pillanat",
> no "Megnézem", no "Bine", no "Rendben", no "Perfect", no "Înțeleg", no "Desigur" — not before a
> lookup, not before a question, not before a fact, not before anything… Go straight to the question
> or straight to the answer, every time."*

All four paths that could produce one are now shut: forced pre-tool speech (off), soft-timeout filler
(-1), scripted lines in the procedures (removed), and prompt permission (revoked).

### The calendar screenshot: both readings are true

The client sent the evolvo staff calendar showing the Pacient Test 12:20–12:40 card still visible,
and said the appointment "is still there". It is — and it is **stamped `Anulat`** in the red side
tab. That is precisely what a cancellation looks like in evolvo; there is no delete.

So two separate things were being conflated, and both are true at once:

| Question | Answer |
|---|---|
| Is the record gone from the calendar? | **No.** It shows as `Anulat`. There is no API delete (Q9 unanswered); removing the row is a staff action — the admin panel's own trash icon is visible in that same screenshot. |
| Is the **slot** free again? | **Yes**, per the tool: `slot_released: true`, `slot_release_status: "released"`, and a note naming the 12:20 slot as bookable. |

The one thing worth verifying rather than asserting is whether the *visible card* stops staff booking
over it in the UI — that is a different question from whether the API offers the slot, and it is not
answerable from here. Asked in
[`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md) as a concrete check on
that exact date, time and calendar.

Meanwhile the agent's wording is now aligned with what actually happens: the prompt and
`evolvo_manage_appointment` both say a cancelled appointment is *recorded as cancelled* and stays in
Optofarm's records, and the agent must say **cancelled** — never *deleted* or *removed*.

## 2026-09-15 (night) — every holding-phrase path closed, and the tool constraints moved into the schema

Two live calls on the new version (`conv_6601m2ge39a8fpjb31k9h4kez8c5` booking,
`conv_2501m2gedptwfz1b2egtbe5q0hqf` cancel). Plenty now works — the purpose is asked **before** the
lookup, `provider_type` goes out, the lead wording is right, the reminder sentence is right, the
cancel is clean. Two things were still wrong, and both were mine.

### 1. The 3-second soft timeout fired on ordinary turns

Enabling `soft_timeout_config` at **3 s** this morning was a mistake. A normal turn reaches first
audio in about 2–3.5 s, so the "filler" fired on turns where **no tool ran at all** — which is why
the agent said *"Verific acum."* and then simply asked a question, and prefixed a knowledge-base
answer with *"Un moment."* Timings from the record make it unambiguous: filler at 21 s, the actual
question at 27 s, no tool call between them.

`timeout_seconds` is back to **-1**. It was -1 before today and that was correct; the repetition was
never the soft timeout's fault, it was `pre_tool_speech: force` plus the scripted lines.

### 2. `pre_tool_speech: auto` is not conservative enough

`auto` is meant to decide from recent tool latency. Tools now answer in **0.9–2.5 s** and it still
spoke before nearly every call. Set to **`off` on all five tools**. The agent now says nothing before
a webhook; a 1–2 s pause on a phone call is normal and reads as thinking, not as a fault. If a
lookup ever feels too silent, put `auto` back on `evolvo_check_availability` alone.

Together these close every path that could produce a holding phrase: no forced pre-tool speech, no
soft-timeout filler, no scripted lines in the prompt or procedures.

### 3. Prose failed, so the constraints are in the schema now

This is the important one. The call ran on `agtvrsn_7101m2gdwxjgeg1bk2k5v9wgy609` — the version
carrying, added barely an hour earlier, *"CALL IT ONCE"*, *"never call it to discover which branches
exist"* and *"NEVER send Târgu Mureș as a city"*. The agent called `check_availability` **three
times**:

| # | Params | Latency |
|---|---|---|
| 1 | `{"provider_type":"doctor"}` — **no target at all** | 1.25 s |
| 2 | `{"provider_type":"doctor","city":"Targu Mures"}` | 0.93 s |
| 3 | `{"provider_type":"doctor","location":"Doja"}` | 2.07 s |

Calls 1 and 2 are exactly what the new wording forbids. This is the README's design note landing on
us again: **the engine ignores prose roughly one run in three, whatever the wording.** So the rules
moved into the JSON schema, where the model cannot violate them:

- **`city` is now `enum: ["Reghin","Sovata"]`.** Târgu Mureș is structurally unsendable. Call 2
  becomes impossible rather than discouraged.
- **`required_constraints.any_of`** requires at least one of `location`, `doctor` or `city`. A call
  carrying only `provider_type` is now schema-invalid. Call 1 becomes impossible.
- **`location` is now an enum of the eight branch keywords**, which also kills invented branches.
- `provider_type`'s description states plainly that it *narrows* a search and never *targets* one.

A schema constraint is worth more than a paragraph of prose here, and it costs nothing at runtime.

### 4. Latency: correcting this morning's correction

I reported 3.8–5.1 s earlier today from old-version calls. On the current version the same tool
answered in **1.25 s, 0.93 s, 2.07 s** (booking 2.06 s, find 1.18 s, manage 2.20 s). The honest
statement is that `check_availability` varies **0.9–5.1 s** depending on how wide the search is — a
narrow branch lookup is ~2 s, and the 5.12 s case was a `provider_type` scan across a whole branch.
The n8n ask stands, but it is a tail-latency question, not a "the tool is always slow" one. Updated
in [`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md).

### On "it went to ANULAT and was not deleted" — the data says it worked

Raised again after the cancel call. What `evolvo_manage_appointment` actually returned:

```json
"success": true, "slot_released": true, "slot_release_status": "released",
"note": "Cancelled, and the 2026-09-15 12:20 slot is free again - it can be booked straight away."
```

So the slot **was** freed, in about 2 s, and is immediately re-bookable. There is still no hard
delete in the API (Q9 unanswered), `ANULAT` **is** how a cancellation is recorded, and removing the
row is a staff action in the evolvo admin panel. Nothing is broken here. Added to the tool
description: never tell a caller an appointment was *deleted* or *removed*, only that it was
*cancelled* — so the agent's words match what the system actually does.

### Still not right

The agent read out **six** branches (*"Poștei, Fortuna, Trandafirilor, Doja, Bulevard sau
Republicii"*) where the procedure says offer three. It had them because call 2 returned them. With
that call now impossible it must use the prompt's three — worth checking on the next test rather
than adding more wording.

## 2026-09-15 (evening) — the repeated filler was not fixed this morning, and the tool is slower than we thought

A pasted transcript showed `Un moment, vă rog.` three times and `check_availability` running several
times in one booking. First thing established, because it changes what the transcript means:

**That call predates every change made today.** The newest conversation on record starts at unix
`1789386309`; the first config change today landed at `1789398285`, about 3¼ hours later. A listing
filtered to `call_start_after_unix=1789390000` returns **zero** conversations. Every recorded call —
including the pasted one — ran on `agtvrsn_7301m239c0jtfm5bnwrydrv11mff` or older. So the transcript
shows the *old* agent, and neither the de-scripting nor the ported procedure was live for it.

That is not a reason to dismiss it. Two real problems came out of reading the actual records.

### 1. A bug in this morning's own fix: the generated filler hardcoded the phrase

Enabling `use_llm_generated_message` was supposed to replace the scripted holding line with a varied,
language-aware one. But `llm_generated_message_prompt_override` — which was left untouched — read:

> *"Output ONLY a very short filler of one to three words… Romanian: **Un moment**… Hungarian: Egy
> pillanat… English: One moment… No other words."*

The agent runs at **`temperature: 0`**. Given that prompt it would have produced *"Un moment"* every
single time. The change moved the hardcoded phrase from the prompt into the filler generator rather
than removing it, and a smoke test would have shown the same robotic repetition with no obvious
cause. Rewritten to name several options per language and to require one **not already used in this
call**; the static `message` fallback changed from `Un moment, vă rog.` to `O clipă.` so even the
fallback path does not reproduce the reported phrase.

Also confirmed from the records what the repetition actually was: the tool calls carry
`"system__message_to_speak":"Egy pillanat, kérem."` as a parameter — that is `pre_tool_speech: force`
injecting the line, which is what this morning's change to `auto` removes.

### 2. `check_availability` is 3.8–5.1 s, not 1.5–2.5 s

Measured `tool_latency_secs` from the records: **5.12 s** (Reghin + optometrist) and **3.79 s**
(Republicii). `book_appointment` in the same call was **2.91 s**. So the earlier "tools 1.5–2.5 s"
figure was wrong, and `check_availability` — the tool called most often — is roughly twice the cost
of booking. The n8n side's 7→3 optimisation was on the **cancel** path; this one appears untouched.
Asked in [`../n8n/REQUESTS_FROM_ELEVENLABS.md`](../n8n/REQUESTS_FROM_ELEVENLABS.md).

### What changed here

The client's point — *gather everything first, then call once* — is right, and the ported procedure
only half-covered it. It had a stop condition on the purpose but nothing stopping a **discovery
call**: in the transcript the agent called the tool with a bare city, got `too_many_matches`, and
read the branch list off the result. It spent 4–5 s of the caller's time to learn something already
written in its own prompt. (Tell: it offered *"Poștei, Fortuna sau Trandafirilor"* — Fortuna comes
from the tool; the prompt says Poștei, Trandafirilor, Doja.)

`booking` (`agtprcv_9301m2gdwxjjftmsmra5xh3nt135`) now says:

- **`CALL IT ONCE.`** Every call costs the caller 3–5 s of silence; a second call is only for
  something the caller *changes*, never for collecting what should have been asked first.
- **The tool is only for finding free TIMES.** Never call it to discover which branches exist, where
  they are, their hours, or who works there — all of that is prompt and knowledge-base content and
  must be answered instantly, without a tool.
- **Never send `Târgu Mureș` as a city** (six branches → `too_many_matches`). `city` is only for
  Reghin and Sovata, which have one branch each. The intake step now states that naming only Târgu
  Mureș is *not a usable place*, so the stop condition covers it.
- The intake step is headed **"GATHER EVERYTHING HERE, BEFORE ANY TOOL RUNS"** and says plainly that
  nothing in it calls a tool.
- The name/phone step is told not to ask anything about the appointment itself — that is where the
  *"Pentru ce doriți programarea? Vă rog să-mi spuneți numele"* double-question came from.
- **`time_not_available` at booking** (which is how the pasted call ended) now has explicit handling:
  say the time has just gone, offer one alternative, rebook immediately — **do not** re-ask for the
  name and number, which are already in hand. The book step also says to call straight after the
  read-back, since every added turn is time for the slot to be taken.

### The honest caveat

Wording alone has already failed at this once: the ordering rule existed before and the agent walked
past it. The README's own design note says the procedure engine skips ask-steps in roughly one run in
three *whatever the wording*, and that server-side guards have worked where prompt edits repeatedly
did not. So two guards have been requested from n8n — reject a lookup with a bare `Targu Mures`
city, and reject one carrying **neither** `doctor` nor `provider_type`, since under Zsófi's rule one
of the two is always known by the time a lookup is legitimate. Until those exist, treat this fix as
likely-but-not-proven.

## 2026-09-15 (later still) — Zsófi's visit-reason rule wired in; `provider_type` was never actually sent

Zsófi's answer arrived:

> *"Valahogy úgy kellene, hogy ha sima szemüvegfelírás, szemüvegcsere, dioptriaellenőrzés — akkor
> mindenképp optometrista legyen. Ha szembetegség, OCT, szemnyomásmérés, szűrővizsgálat, vagy egyebet
> mond a páciens, akkor mehet az orvoshoz."*

### The mapping was already right — the wiring was not

`evolvo_check_availability`'s `provider_type` parameter already described almost exactly this rule
(*"optometrist for a plain glasses prescription, a change of glasses, or a dioptre check; doctor for
an eye disease, an OCT scan, eye pressure measurement, a screening, anything urgent, and anything you
are not sure about"*). Zsófi's list **confirms** it rather than changing it — including her default,
*"vagy egyebet mond a páciens → orvos"*, which matches "anything you are not sure about → doctor".

**The real defect was that nothing reliably sent the parameter.** The booking procedure's
availability step listed `doctor`, `location`, `city` and `date_from` and stopped there, so
`provider_type` went only when the LLM chose to from the tool description alone — sometimes it did,
sometimes it did not. That is why this looked "blocked on Zsófi" when the ElevenLabs half was also
incomplete.

*(Corrected 2026-09-15 evening: this entry first said the parameter was **never** sent. The
conversation records disprove that — `conv_8701m2fvjnjre698mhm84r3bw77c` shows
`{"provider_type":"optometrist","location":"Reghin"}` going out on the old version. It was
inconsistent, not absent. The fix — instructing it in the procedure — is the same either way, but
"never" was wrong.)*

Fixed: the availability step now sends `provider_type`, derived from the answer to intake question
(2), with `doctor` stated as the safe default and the instruction to **leave it out entirely when the
caller named a person** (a named doctor always wins — refusing the person a caller asked for is worse
than offering the wrong kind).

### Two judgement calls that Zsófi's text does not settle

- **A bare "un control" / "kontroll".** Her list has `dioptriaellenőrzés` (optometrist) and
  `szűrővizsgálat` (doctor), and a caller saying only "a check-up" could mean either. Resolved toward
  her own default: a bare check-up is medical, so `doctor`. It is `optometrist` only when the caller
  ties it to glasses or dioptres (*control de dioptrii*, *dioptriaellenőrzés*). Intake question (2)
  says so explicitly and is told **not** to ask a follow-up about it — one question per turn matters
  more than the marginal accuracy.
- **A branch with no optometrist.** Not every branch has one — Fortuna is doctor-only. Falling back
  to a doctor there would quietly defeat the point of the rule, which is to keep doctor capacity for
  medical work. Decided (with the client) to honour *"mindenképp"* literally: on
  `no_provider_of_type` the agent says that branch has no optometrist, then **calls again with the
  same `provider_type` and no `location`** so the search reaches the branches that do have one, and
  offers the earliest optometrist slot naming its branch. It never volunteers the local doctor. The
  one escape hatch is caller-initiated: if they say themselves that they cannot travel, the agent may
  look again at their branch unfiltered.

`no_provider_of_type` carries no alternative-branch list, which is why the re-search drops `location`
rather than reading a field.

### Changed

- **`evolvo_check_availability`** — `provider_type` description gains the "control" disambiguation
  and an explicit "send it on every lookup where the reason is known and no person was named". The
  tool description's `no_provider_of_type` clause changes from *"offer what the result says IS
  available there"* to the re-search above. `location` notes that it must be dropped on that
  re-search.
- **`booking` procedure** (`agtprcv_4801m2gardc4e3wb0kk5atpvqb9f`) — the availability step sends
  `provider_type`; intake question (2) says what the answer decides; the negotiation rule now counts
  a changed `provider_type` as a distinct lookup.

### Worth revisiting

The classification still rests on the calendar-name prefix, and evolvo's `ai_doctor_title` field
would make it data instead (question 11 for Imreh). `ai_description` could hold this visit-reason
mapping as clinic-maintained data rather than prompt text — which would mean Zsófi edits it herself
instead of it being frozen here.

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

## 2026-09-15 — greeting latency, language/voice switching, prompt↔KB de-duplication

### Greeting latency (root cause found)
The Romanian `first_message` was 254 characters ≈ **15.3 s of audio**. A caller who
speaks during it is not answered until it finishes. In `conv_0001m2jdfs1sftq9mw6nm63kjk27`
the caller said "Hello?" at t=5 s and was answered at t=17 s:
`convai_turn_silence_before_initiation: 10.4 s` — which is exactly the remaining tail of
the greeting. The LLM itself was fast (`convai_llm_service_ttfb: 0.73 s`).
Greeting cut to 134 chars ≈ 8.1 s. Dropped the "Puteți vorbi cu mine în Română, Maghiară
sau Engleză" menu (−3.2 s); kept the recording + consent clause.
Added a `A GREETING IS NOT A TASK` rule: a bare greeting gets one short line, no lookup,
no tool, no procedure.

Residual on a bare "Hi.": `silence_before_initiation 2.72 s`, `ttf_audio 5.22 s`.
That floor is turn detection (`turn_eagerness: normal`), not the prompt. Not changed —
making it eager risks cutting off callers dictating phone numbers.

### Accent / voice
- Base voice `Dme3o25EiC1DfrBQd73f` is **"Aggie", a Hungarian voice** — used for Romanian
  and English alike. Kept on the user's instruction.
- `en` preset voice `vChnJZ1Cu89g2XXumPfT` is **"Lara", en-american** — correct and live on
  Main, but `tts_usage.per_voice_usage` shows **zero seconds** from it in both test calls,
  including `conv_5801m2jd7agwemy9qttvxt7b4m87` where `language_detection` returned
  `{"language":"en","status":"success"}` and every later turn was English.
- `conv_0001…` switched to English **without calling `language_detection` at all**
  (`features_usage.language_detection.used: false`). Prompt now states that the tool call is
  the only thing that changes the voice and must fire *before* replying in a new language;
  tool description hardened; `pre_tool_speech` set to `off` so the switch is silent.

### Prompt ↔ knowledge base de-duplication
Both FAQ docs contained call-handling instructions already owned by the prompt and the
procedures — and both told the agent to say the **clinic would confirm the appointment**:
- RO: *"Dacă răspunsul este că cererea a fost înregistrată și urmează confirmarea clinicii, spune exact asta."*
- HU: *"Ha a válasz az, hogy a kérés rögzítésre került és a klinika megerősíti, pontosan ezt mondd."*

That is the defect reported earlier as *"Clinica vă va confirma programarea"*, still live in
RAG, and it also breaks the guardrail against calling Optofarm a clinic. Removed from both,
along with the duplicated emergency and booking/cancellation sections.
Branch landmarks moved **out of the prompt into both FAQ docs**, resolving a contradiction:
the KB said *"un reper doar dacă se află în baza de cunoștințe"* while the prompt listed
landmarks for all eight branches.

| | before | after |
|---|---|---|
| system prompt | 29,633 ch | 23,331 ch (−21.3 %) |
| RO FAQ | 9,951 B | 8,455 B |
| HU FAQ | 9,753 B | 8,407 B |

### Open
- KB doc `MhVjolXAcypPXVvWoAVL` is a **folder** — the whole optica-optofarm.ro crawl. Its
  cookie-policy and privacy-policy pages outranked the FAQ on a directions query. RAG
  retrieves 6 chunks every turn and `used_chunk_ids` was `[]` on every turn inspected.
- Website "Puncte de lucru" page says `Sâmbătă: închis` for every branch, contradicting the
  prompt and both FAQ docs on Poștei being open 9–2.
- LLM is now `qwen35-397b-a17b` (was `gpt-5.6-luna`); `agent_last_updated_from: "ui"`.

## 2026-09-15 (later) — knowledge base: website crawl replaced

### Audit of the scraped site (folder `MhVjolXAcypPXVvWoAVL`, "optica-optofarm.ro Crawl Job (2026-07-30)")
18 URL documents, 101,242 bytes, all in the RAG pool competing for the 6 chunks
retrieved on every turn:

| group | docs | bytes | verdict |
|---|---|---|---|
| cookie + privacy policy, RO and HU | 4 | 40,384 | junk — 40% of the crawl |
| homepage, scraped twice for RO and twice for HU | 4 | 22,108 | `optica-optofarm.ro` and `.../` byte-identical (5,540 each) |
| Medici, RO and HU | 2 | 5,277 | **guardrail hazard** — a doctor/branch list the prompt forbids using |
| Servicii + Fabrica de lentile, RO and HU | 4 | 19,509 | duplicated by FAQ §18/§19 |
| Contact, RO and HU | 2 | 3,306 | only the general e-mail; B2B number is on Fabrica de lentile |
| Puncte de lucru, RO and HU | 2 | 10,658 | the only load-bearing data |

Replaced by folding the branch data into the two FAQ documents that were already
indexed: §15 now holds all eight branches with address, weekday and Saturday hours
and direct phone number, and §20 holds the B2B/lens-factory contact. Each language's
FAQ is therefore self-contained — §15 addresses, §16 landmarks — with no third
document to keep in sync.
**Knowledge base: 23 documents → 5. The crawl's 101,242 B is gone; the two FAQs grew
by 1,497 B and 1,726 B to carry what was worth keeping.**

A standalone bilingual locations document was created first (`FUSHtAQki9sjGxN7tswc`)
but deleted again once the FAQ route was verified: keeping both would have put the
same eight addresses in the retrieval pool twice, which is the duplication this work
set out to remove.

### Correction to the earlier entry
The claimed contradiction between the website and the FAQ over Saturday hours was
**wrong**. The Puncte de lucru page lists each branch's hours *above* its address
heading, so the `Sâmbătă: închis` blocks I first read belonged to neighbouring
branches. Poștei does show `Sâmbătă: 09:00 – 14:00`, matching the FAQ and the prompt.
The page also shows Poștei open to **21:00** on weekdays, not 20:00 — a fact the
agent did not previously hold. It is now in the new document.

### Confirmed effect on retrieval
Before, a directions query returned the cookie-policy page at rank 1
(`vector_distance` 0.130) ahead of the FAQ (0.137). After the FAQ de-duplication,
the same kind of query returns all six chunks from the two curated FAQ docs, with
the landmark list at ranks 1 and 2, and no policy page at all.

### Verified after deletion
- Romanian: "Ce număr de telefon are punctul de lucru de pe strada Poștei și la ce
  oră se închide?" → FAQ §15, `vector_distance` 0.160.
- Hungarian: "Mikor van nyitva a szentgyörgytéri üzlet és mi a telefonszáma? Hogyan
  találok oda?" → GYIK §15, `vector_distance` 0.129, returning the correct branch
  with hours and phone. That beats the best pre-cleanup match on any locations query,
  which was the cookie-policy page at 0.130.

### Gotcha for next time
A newly created knowledge-base document is not retrievable for some minutes — its RAG
index is built asynchronously and the MCP surface exposes no compute-rag-index call.
Editing an existing, already-indexed document re-indexes it promptly. Always confirm
with `agents_query_knowledge_base_rag` before deleting whatever the new content is
meant to replace.
