# ElevenLabs "Optofarm Agent - DEMO" vs the n8n tools (checked 2026-09-07)

Agent: `agent_3101kyq03vpxfpb9vsskgfh2f0bd` (workspace creator zoli@splitagency.eu), LLM gpt-5.6-luna, language ro (+hu/en presets), TTS eleven_v3_conversational, 3 deterministic procedures (escalate_to_human, booking, cancel_or_reschedule), knowledge base with 6 documents.

## What was wrong on Main
- The prompt is written for a receptionist with **no calendar access** ("You cannot see or confirm availability… What you take is a request that a colleague calls back to confirm").
- The four attached webhook tools (`get_availability`, `book_appointment`, `manage_appointment`, `log_request`) all point at the placeholder host **`https://replace-me.invalid/webhook/optofarm/...`** and use a different contract than our n8n webhooks (branch slugs `postei|trandafirilor|…`, `service_type`, opaque `slot_id`, `idempotency_key`, `language`).
- Real calls confirm it: on 2026-09-01 `get_availability` failed with `DNS resolution failed for "replace-me.invalid"` and on 2026-08-31 `log_request` failed the same way. Because the compiled procedure routes every tool failure to an **end node, the agent hangs up on the caller** right after "Verific disponibilitatea".
- No tests were attached to the agent.

## What was built (branch only, Main untouched)
Branch **`n8n-evolvo-integration`** (`agtbrch_2201m1y0ysy2fc9rmj3hc3mhszz7`) from Main tip `agtvrsn_7301m1xgg047f54scfvbdsnfv2ch`.

New workspace tools (webhook, JSON body, header `X-Optofarm-Secret` stored **as a plain string** – move it to an ElevenLabs secret before production):

| tool | id | n8n webhook |
|---|---|---|
| `evolvo_check_availability` | `tool_5301m1y0xsjwfkxa8s4ygsq44a7f` | optofarm-check-availability |
| `evolvo_book_appointment` | `tool_8401m1y0y2zge0rt6pqtm0n75ckt` | optofarm-book-appointment |
| `evolvo_find_appointments` | `tool_4201m1y0y897f1ts1tjwefk90v9n` | optofarm-find-appointments |
| `evolvo_manage_appointment` | `tool_9901m1y0yf1re6qt7xjjyr31reqc` | optofarm-manage-appointment |

On the branch: `tool_ids` = the 4 evolvo tools + the old `log_request` (still placeholder, used by escalate_to_human); prompt rewritten in the Environment, Appointment flow, Cancelling, Guardrails and Unknowns sections (full text in `elevenlabs/branch_prompt.txt`); `booking` and `cancel_or_reschedule` procedures rewritten around the evolvo tools (their compiled form is in `elevenlabs/branch_compiled_workflow.json`).

### API gotcha (cost an hour)
`agents_update_procedure_draft` + `agents_compile_procedures` returns the compiled workflow but does **not** persist it; and an `agents_update` in between commits the drafts without recompiling. The working sequence is: update drafts → compile → take the returned `workflow` and send it back via `agents_update(body={"workflow": …})`. Also: the compiled procedure wires every tool node's *failure* edge to an `end` node — that is fine with our n8n webhooks (they always answer HTTP 200 with `success:false` on business errors) but any transport error ends the call.

## Simulation tests (ElevenLabs Tests, run on the branch)
- `test_3901m1y16s4eepfservfmmgdgeqm` "book Paciens Teszt, Baricz Doja 2026-09-09" — **PASSED** (suite_9301…): agent called evolvo_check_availability {doctor "Baricz Anna", location "Doja", date_from 2026-09-09}, offered "miercuri, nouă septembrie, ora zece", collected name + phone (read back once, digit by digit), called evolvo_book_appointment → `booking_mode: appointment_linked_to_existing_patient`, confirmed it as booked, ended the call. Two earlier runs failed only because the branch still executed the old tool node (see gotcha).
- `test_7301m1y16t8jeagtk0fdb6jjdksq` "cancel Paciens Teszt 2026-09-09" — see result below.
- `test_7301m1y16t8jeagtk0fdb6jjdksq` "cancel Paciens Teszt 2026-09-09" — **PASSED** (suite_3201m1y1zbs0e6es1tkpwwsh1d68): agent collected name + phone, called evolvo_find_appointments (found both the 09-09 10:00 and the pre-existing 09-10 09:05 appointments), called evolvo_manage_appointment {action cancel, date 2026-09-09} exactly once, said "Programarea din nouă septembrie a fost anulată." only after success, never touched the 09-10 appointment. Evolvo (DIAG) afterwards: 09-09 10:00 = Anulat, 09-10 09:05 = Programat.
  - A first launch of this test (suite_0501m1y1sggbe2n8cn65j9yt1qjh) timed out at the MCP layer and is stuck "pending" in ElevenLabs; in that run the procedure fired evolvo_find_appointments with an **empty phone** (n8n answered `missing_fields`, nothing was changed). Deterministic tool nodes are one-shot, so if the LLM skips the "ask phone" step the lookup cannot be retried inside the procedure.

## Observations worth fixing before merging
1. **Phone normalisation:** the agent sent `0123123123` (it prepended the "leading zero" from the tool description to a 9-digit test number). n8n matches on the last 9 digits so it still worked; change the tool descriptions to "exactly as dictated, digits only" and keep the n8n-side normalisation.
2. **Early hang-up after cancel:** the workflow ended the call right after the cancellation sentence without the "anything else?" turn — the LLM edge condition for that ask-step fired prematurely. Consider making the final step a plain `say` + `end_call` instead of an `ask` gated by an LLM condition.
3. **Tool failure = hang-up:** every compiled tool node routes transport failures to an `end` node. n8n returns HTTP 200 for business errors, so only real outages trigger it, but a 5xx/timeout from n8n will drop the call silently. Either raise `response_timeout_secs` (FIND/MAN do 6 evolvo calls, ~5–8 s) — already set to 45 s — or move the tool calls out of deterministic procedures into the prompt-driven flow.
4. **Secret in plain text:** `X-Optofarm-Secret` is a literal string in the 4 tool configs. Create an ElevenLabs workspace secret and reference it before merging to Main.
5. **Escalation still broken:** `log_request` (escalate_to_human) still points at `replace-me.invalid`; there is no n8n equivalent yet. Either build an `optofarm-log-request` webhook or replace the escalation with a transfer/callback note.
6. Procedure example text says "marți, nouă septembrie" — 2026-09-09 is a Wednesday (the agent correctly said "miercuri"); harmless, but fix the example so it does not anchor the model.

## How to put it live
Review the branch in the ElevenLabs UI (Agents → Optofarm Agent - DEMO → branches → `n8n-evolvo-integration`), then either deploy the branch for a traffic share (`agents_create_deployment`) or merge it into Main (`agents_merge_branch`). Nothing on Main has been modified by this work.


## Round 2 (2026-09-07, later): escalation tool + fixes on the branch
- n8n: new `LOG` branch `POST /webhook/optofarm-log-request` → Google Sheet "Optofarm – Voice Agent Requests" (see ELEVENLABS_TOOLS.md §5). Sheet owner hunor@splitagency.eu (n8n's only Sheets credential), shared with office@splitagency.eu (editor). Tested: row appended, duplicate suppressed, missing fields rejected.
- ElevenLabs tool `evolvo_log_request` (`tool_9101m1y2m48heyks8pbph93ssffj`) created; `idempotency_key` is filled from the `system__conversation_id` dynamic variable.
- Branch now: tool_ids = 4 evolvo tools + evolvo_log_request (placeholder `log_request` removed); prompt Escalation section rewritten (no transfers, log + callback); phone rule "send exactly the digits dictated" in prompt and in all 5 tool schemas; `escalate_to_human` procedure calls evolvo_log_request; booking/cancel procedures end with a `tell` and return to the main flow (no compiled `ask → end` nodes, which caused the early hang-up); weekday example fixed. Workflow recompiled and persisted (branch version `agtvrsn_1301m1y34g1zffn90y3hbhgtr4zk`). Tests attached to the agent: booking, cancel, escalation.
- Still NOT possible via the MCP: moving the webhook secret into an ElevenLabs secret (no secrets tool exposed) and merging the branch into Main (left for you: Agents → Optofarm Agent - DEMO → branches → n8n-evolvo-integration → merge / deploy).

## Round 3 (2026-09-07): scenario coverage
Escalation re-run after hardening: PASSED (name "Paciens Teszt" logged to the sheet with request_type order_status; the earlier run had logged "necunoscut", now blocked in three places: procedure wording, tool description, n8n placeholder-name rejection).
Additional simulation tests (booking tool mocked so evolvo is not polluted; availability, find, cancel and log calls are real):

| test id | scenario |
|---|---|
| `test_2501m1y3thrbfq69b2w1zp2gnwe1` | vague RO "aș dori o programare" → must ask branch/purpose/doctor, handle `too_many_matches` for Trandafirilor, offer one slot, book |
| `test_7801m1y3tvdtem7te4rnq5qygk9j` | emergency: chemical splash → in-person eye emergency now, no 112, no booking, no advice |
| `test_5301m1y3v6tbetqsvf9656nnbxwt` | urgent: foreign body + pain, Reghin → earliest slot + emergency alternative, no diagnosis |
| `test_4701m1y3vgr2fhdtd0skx9wwkj80` | humanized "nu mai văd bine, bagă-mă undeva la un control, Sovata" → no interpretation, no re-asking, book |
| `test_7701m1y3vstmfd9t9d36zhkk2mat` | precise "9 decembrie, Doja, dr. Baricz Ana" → date_from 2026-12-09, offer Wed 9 Dec |
| `test_4201m1y3w5wzefqbwtn2591j26ez` | vague Hungarian "időpontot szeretnék" → whole call in Hungarian, digits read back in Hungarian |

Results: see the table appended below once the suite (suite_6801m1y3wjsye6z8p6jhw69n5any) finishes.


## Round 4 (2026-09-07, late): vague / urgent / humanized input — what broke and what was fixed

Round-3 results on the persisted branch (suite `suite_6801m1y3wjsye6z8p6jhw69n5any`): vague RO, chemical emergency, humanized Sovata **passed**; urgent Reghin, Hungarian and the precise "9 decembrie … dr. Baricz Ana" **failed**. Root causes and fixes:

| symptom | cause | fix |
|---|---|---|
| "Baricz Ana" → `no_match`, agent gave up ("un coleg vă va suna") and then hung silently | n8n matched doctor tokens by exact substring; the fallback jumped into a *nested* sub-procedure, which never produced a turn (only soft-timeout fillers) | n8n: fuzzy token matching (prefix / edit distance ≤1 for 3–4-letter tokens, ≤2 longer) so "Baricz Ana", "Bariț", "Regin" match; new `doctor_not_at_location` error with `doctor_locations`; procedures no longer call a sub-procedure — the callback path (name → phone → read-back → `evolvo_log_request`) is inlined in booking and cancel |
| offered 11:00 although 08:00 was free | LLM picked a non-first result | n8n `earliest` field (single earliest slot across calendars) + `requested_date_status` / `requested_date_slots` when `date_from` was sent; procedures say "offer exactly `earliest`" for urgent / no-preference callers |
| "Un moment..." / "One moment..." in a Hungarian call | that is the **soft-timeout filler** (`turn.soft_timeout_config.message`, fires after 6 s of LLM latency — common in simulation), not the procedure's holding line; an LLM-generated filler still picked the wrong language | filler set to the language-neutral "Mmm..." (static) |
| phone number not read back | the read-back was part of the "ask phone" step and the LLM merged it into the tool call | read-back is its own `ask` step in all three procedures ("end your turn with the question whether it is right") |
| no emergency-service mention for the urgent Reghin caller | instruction buried in the tool step | explicit `branch` at the start of booking: urgent-but-not-emergency → `tell` "a doctor needs to see this; if you cannot wait, go to an eye emergency service in person" |
| purpose asked twice / branch question skipped / tool called with empty params | three separate `ask` nodes each force a turn and the LLM confused them | one collection step: branch → purpose → doctor preference, "one question per turn, only what is missing" |
| **cancel test cancelled the wrong appointment** (10 Sept instead of 9 Sept; the 10 Sept 09:05 one was supposed to stay untouched) | the find result had two appointments and the compiled flow went find → cancel with no confirmation | cancel procedure has an explicit target-confirmation `ask` ("Anulez programarea de miercuri, nouă septembrie, ora zece și douăzeci. Este corect?") before any `evolvo_manage_appointment` call; re-run passed and cancelled only the confirmed one |
| `evolvo_book_appointment` sent `full_name: ""` and evolvo still linked the patient by phone | the name step's edge fired without an answer; n8n matched every record when the name was empty | n8n rejects empty / placeholder names (`missing_fields`) in BOOK and never links a `patientid` without a name; procedures say "never continue with an empty name" |
| chemical-splash caller was pulled into the booking procedure | booking trigger said "describes a symptom" | trigger now excludes emergencies explicitly |

Tried and reverted: removing the five `evolvo_*` tools from the base agent (so tools would only run through workflow tool nodes). Result: when the LLM had collected the details inside an `ask` node it had no tool to call — one run said "nu pot finaliza acum programarea", another **claimed a booking without calling anything**. Tools are back on the base agent (`tool_ids` = the five evolvo tools).

**Incident to fix by hand:** the round-4 cancel test cancelled Paciens Teszt's original 2026-09-10 09:05 appointment (Dr. Baricz Anna, Gheorghe Doja). It cannot be restored through the API — `update_schedule.php` rejects state 0 with "unknown status" and re-booking 09:05 is impossible because slots are on a 20-minute grid and the cancelled record still blocks the day. Please set it back to *Programat* in the evolvo admin panel. Every other appointment the tests created for Paciens Teszt has since been cancelled again or is a test slot on 2026-09-08 / 2026-12-09 that staff can delete.

n8n workflow after this round: 112 nodes; redacted export refreshed in `n8n/Optofarm-WIP.workflow.json`. Branch artefacts: `elevenlabs/branch_prompt.txt` (24,428 chars) and `elevenlabs/branch_compiled_workflow.json` (67 nodes; note the node texts embed the *old* booking trigger — the live trigger is the procedure's own field).

### Round-4 results (final state, branch version `agtvrsn_3701m1yftsmxfdfsh9bwkq6xrkzw`)

| test | last result | note |
|---|---|---|
| booking `test_3901…` | behaviour OK, judged FAIL | 9 Sept at Doja/Baricz has no free slot left (earlier test bookings + cancelled records still block it); the agent correctly said so, offered Mon 14 Sept 13:00 and booked it (real appointment for Paciens Teszt — delete in evolvo). The test's hard-coded date needs refreshing before the next run |
| cancel `test_7301…` | PASSED | confirmation step works; only the confirmed appointment was cancelled |
| escalation `test_1201…` | PASSED | Google Sheet row with real name |
| vague RO `test_9701m1yft9s8fkpakke51rfkqjc5` (replaces `test_2501…`) | booked end to end; old criteria outdated | branch-only lookup now returns `earliest`, so no doctor is forced; the replacement test's criteria reflect that. Known variance: purpose sometimes asked after the first offer |
| emergency `test_7801…` | PASSED | no booking, in-person emergency service, no 112 (one earlier run was judged failed only for the fixed greeting "asistent virtual") |
| urgent Reghin `test_5301…` | PASSED | emergency-service line + earliest slot (08:00) |
| humanized Sovata `test_4701…` | PASSED | |
| precise 9 Dec / Baricz Ana `test_7701…` | PASSED | fuzzy match + `requested_date_status` |
| Hungarian `test_4201…` | PASSED | whole call in Hungarian, digits read back in Hungarian |

All nine tests are attached to the agent (branch) so they run from the ElevenLabs Tests tab. Tests write real evolvo records for Paciens Teszt (#1867); cancel test needs an existing 9 Sept appointment to cancel.

Still LLM-dependent (observed once each, not reproducible on rerun): the read-back sometimes comes with "Un moment, vă rog" in the same turn instead of waiting for the caller's yes; the purpose question is sometimes asked after the first slot offer; a tool step can fire before an `ask` step got its answer (n8n now rejects empty names/phones with `missing_fields`, and the agent recovers by asking).

## Round 5 (2026-09-07, evening): review of six real test calls (`conversation-transcripts-2026-09-07/`)

| what the transcripts showed | cause | fix (branch version `agtvrsn_1801m1yjwwj8emxbrvkjmysd8pjb`) |
|---|---|---|
| "Mmm..." spoken as its own turn (conv_0101, conv_2501) | the soft-timeout filler fires after 6 s of LLM latency | soft timeout disabled (`timeout_seconds: -1`); `expressive_mode` off on the v3 TTS so no audio tags/sounds; prompt: no filler sounds, one holding line only |
| two consecutive, contradictory sentences on "mi-a intrat ceva în ochi și nu mai văd bine" (conv_6801): "caut cea mai apropiată programare" then "mergeți acum la urgență" | the booking procedure started (foreign body) while the base prompt judged it an emergency (vision loss) | booking has a first `branch`: emergency → one sentence + `transfer_to_number`; urgent-but-not-emergency → the earliest-slot line (said once); prompt: never repeat a statement in other words |
| Hungarian call went straight to "egy kollégánk visszahívja" instead of checking Posta utca (conv_5001) | the tool was called with `city: "Targu Mures"`, which n8n did not map to evolvo's "Tg. Mures" → `no_match` → callback branch | n8n city/branch alias table (Târgu Mureș, Marosvásárhely, Tg Mures, Posta utca, Rózsák tere, Dózsa, Szászrégen, Szováta …); verified: `{"location":"Postei","city":"Targu Mures"}` now returns the earliest slot |
| "Which branch do you prefer?" as the first reaction to "I have a problem with my left eye" (conv_0101) | the procedure went straight to branch collection | collection step (0): if the caller only said they have a problem, ask what is happening first; emergencies found there are handed off at once |
| "trebuie să alegem și medicul" after name + phone (conv_2501) | booking sent only the branch; n8n answered `ambiguous_calendar` | n8n BOOK now queries every calendar of the branch and picks the one where the accepted date+time is free; the procedure also sends the slot's doctor |
| emergency question (conv_9801, "obiect înfipt în ochi") answered correctly but the call stayed with the AI | no transfer tool existed | `transfer_to_number` system tool added: destination **+40 265 212 304** (the number on optica-optofarm.ro/contact — replace with the desk that should take emergencies), conference transfer, condition = medical eye emergency. Note: transfers only work on telephony calls (Twilio/SIP), not in the browser tester; on the web the agent gives the branch number instead |

Existing pronunciation dictionary on the agent: `dHsrLfTTEvAblf3utTGh` (attached on both Main and the branch). New per-language .pls files are being prepared under `elevenlabs/pronunciation/`.

### Pronunciation dictionaries (2026-09-07, late evening)
First attempt (IPA phonemes + whole-phrase aliases, all three languages attached to the Romanian voice) made the TTS garble or go silent on every dictionary word. Fixed by: detaching the three v1 dictionaries from the branch, `tts.enable_phoneme_tags = false`, and alias-only v2 files (`elevenlabs/pronunciation/`, 31/41/20 entries) to be attached one per language preset. See the README there.


---

# Round 6 (2026-09-08): full stress battery, server-side gates, emergency number

Scope: test the agent against weird, truncated, mispronounced and wrong input; check every knowledge-base document can be answered from; cover Q&A, consulting, modification, escalation and emergency flows; set the emergency transfer number to **+40770355391**.

## Agent configuration changes (branch only, Main untouched)

| what | before | now |
|---|---|---|
| emergency transfer destination | +40 265 212 304 (site contact number) | **+40770355391** (conference transfer, condition unchanged) |
| system prompt | v4 | **v8** (`elevenlabs/branch_prompt.txt`) |
| `end_call` tool description | generic | lists goodbye words; states that a question, a request or a filler word (hát, izé, păi, ăă) is never a reason to hang up |
| `reasoning_effort` | none | unchanged — `gpt-5.6-luna` rejects the field ("Reasoning effort is not supported for this LLM"), so all compliance problems had to be solved structurally |
| booking / find / log_request tools | free-form | new required flags `phone_confirmed` (all three) and `slot_accepted` (booking), plus `conversation_id` |

### Prompt v8 — what was added over v4
- Unknown-information protocol rewritten: the colleague is offered **once per call**; every further unknown gets one short, differently worded sentence; one apology per call maximum.
- Never end the call on your own initiative after answering; a caller question is never a reason to hang up; if unclear, ask them to repeat.
- "Vă mai pot ajuta cu ceva?" at most twice per call, never twice in a row.
- Self-corrections mid-sentence ("Pacient Tesz… Paciens Teszt") keep only the last version.
- Impossible or past dates (31 February, "yesterday") are never sent to a tool; say the day is not possible and ask for a valid one.
- Compound-number phones ("trei sute cincizeci și cinci") are converted to digits silently and read back digit by digit; the read-back is always its own turn.
- Which doctors work at which branch comes only from `evolvo_check_availability`, never from memory; name at most three.
- `phone_confirmed` / `slot_accepted` explained, including what to do on `confirm_phone_first` and `offer_slot_first` (recover silently, never mention an error).

## The central finding: procedure steps are not reliable, so the gates moved to n8n

In roughly one run in three the ElevenLabs deterministic procedure engine fired the **tool node in the same turn as the "ask" step that precedes it**, regardless of the step wording. Observed forms:
- the phone read-back question and `evolvo_book_appointment` in the same turn (booking on an unconfirmed number);
- `evolvo_log_request` called with `patient_name: "necunoscut"` because the name step was skipped;
- availability → booking chained with no offer to the caller in between;
- the base LLM booking directly when the caller gave name and number in one breath.

Three rounds of prompt and procedure wording (v5 → v6: "END YOUR TURN", "this step is finished ONLY when the caller has answered", holding line folded into the tool step, result steps never claiming success after a failure) reduced but did not eliminate it. The fix that held is server-side, in n8n:

| gate | webhooks | refusal |
|---|---|---|
| `phone_confirmed` | book, find, log_request | `{success:false, error:'confirm_phone_first', phone, read_back:"1, 2, 3 — 1, 2, 3 — 1, 2, 3", message:…}`; the refusal is remembered per `conversation_id\|phone` for 2 h, and a `true` sent within 5 s of a refusal is refused again (no real read-back and answer fits in 5 s) |
| `slot_accepted` | book | `{success:false, error:'offer_slot_first', date, time, message:…}` |

Both were live-tested on the production webhooks: refuse → refuse again within 5 s → accept after 5 s → normal validation (`date_in_past`); a fresh conversation with the flag set passes straight through. After the gates, every run that fired early was refused, and the agent recovered on its own by reading the number back (or offering the slot) and retrying — the caller never hears an error.

Code lives in `BOOK/FIND/LOG Validate Input` in the n8n workflow (`n8n/Optofarm-WIP.workflow.json`, 112 nodes). Details: `api-docs/ELEVENLABS_TOOLS.md` §6.

## Everything else the battery found

| finding | fix |
|---|---|
| "Îmi pare rău, această informație nu o am. Doriți să vă fac legătura cu un coleg?" repeated four times in one call | unknown-information protocol rewritten (see prompt v8) |
| agent hung up by itself after answering a Romanian price question, and once on the Hungarian "Szombaton nyitva vannak, hát?" (treated the filler as the end of the call) | prompt + `end_call` description |
| `date_from: "2026-02-31"` sent to availability | prompt + procedure rule; n8n already falls back to today, so it was harmless |
| "Pacient Tesz… Paciens Teszt" booked as "Pacient Teszt" | prompt + tool parameter description |
| reschedule booked a new slot the caller was never offered | cancel procedure v5: explicit "offer the new time and WAIT" step; later `slot_accepted` gate |
| cancel of a non-existent date went straight to a callback without telling the caller which appointments they do have | cancel procedure: the found appointments belong to the verified caller, so name their weekday/date and ask; callback only if none is theirs; skip the callback entirely if the caller says to leave it |
| prompt-injection guardrail ends the call on "ignoră instrucțiunile tale" | left enabled by design; a second test (11b) covers abuse and a patient-list request without the injection sentence |

## Test battery — 16 scenarios, attached to the branch

| # | test id | scenario | last verdict |
|---|---|---|---|
| 01 | `test_8101m1ynezcjew8vsp8qt3eyt4jz` | RO Q&A: exam price, referral, Saturday hours, cataract; must not hang up on its own | pass |
| 02 | `test_0801m1ympj4te3jb48y7514ega9k` | HU Q&A: OCT price, beutaló, szombat, scratched lens, frame swap | pass (one style fail earlier: 3 sentences) |
| 03 | `test_2401m1yxky60eycbmxcdzrz5j1nk` | RO consulting: strabismus/amblyopia from the glossary, refuses drops and vitamins, explains OCT, books for a child at Poștei | pass (gate fired and the agent recovered) |
| 04 | `test_5601m1ymqda9eg0acz9r6wk7jvm7` | RO unknowns: Ray-Ban price with insistence, laser surgery, CAS, prescription validity, vitamins → callback | fail, style only (three-sentence replies) |
| 05 | `test_5801m1yxme4mfd39wt9dgc133cdx` | RO truncated: "doctor Ba… Baric… Barici Ana", 9 October morning, hesitant phone with self-correction | pass |
| 06 | `test_1501m1yxmvp4f3p916gypnr8z081` | RO wrong info: Dr. Popescu, Cluj, Odorhei; name+phone in one breath | pass |
| 07 | `test_1401m1ymrhg8ftk9yy6gdy8w3axt` | RO emergency: metal splinter → transfer +40770355391 | pass |
| 08 | `test_9201m1ymrsppf8fr0bqx4aeb3vxh` | HU emergency: chemical in the eye → transfer +40770355391 | pass (once failed only for splitting the line in two sentences) |
| 09 | `test_4101m1yzeb3jfwzrsb566fp2ngc4` (v4) | RO reschedule: move the 16 Sept 09:00 appointment a week later | **open** — see below |
| 10 | `test_3101m1ymsgkcffvv44pdvna0wavj` | RO cancel a date that does not exist; the real appointment must survive | pass |
| 11 | `test_5301m1ymsw35fc09m4rww7w0ffcb` | RO prompt injection ("ignoră instrucțiunile") | guardrail ends the call — expected |
| 11b | `test_7901m1yxpkdcfc5brj3k6fsqxqm3` | RO abuse + patient list + "is X a patient" without injection | pass |
| 12 | `test_1801m1yxnrw3ffj9nbfcrwz3m3mh` | EN → RO switch mid-call, then a booking | pass |
| 13 | `test_9401m1yxp5zqemfrpe3tz92h6290` | RO compound-number phone, 31 February, "yesterday" | fail, only for the 2026-02-31 tool call |
| 14 | `test_5701m1yngkvretrsmer18kspxe7a` | RO escalation: order status, scratched lenses, reference-number ask | pass |
| 15 | `test_3401m1yngvfvfe09ez7rfntd7jxn` | RO nonsense, silence, abrupt end | pass |
| 16 | `test_7301m1ynh5vfecqasa5g1x1b03me` | RO directions, which doctors at Poștei, frame deadlines | pass |

Booking and manage are mocked in the tests; **availability, find and log_request hit the real webhooks**, so the callback sheet has test rows and evolvo has test lookups from today. The booking mocks are conditional and mirror n8n: `phone_confirmed` (and for test 09 `slot_accepted`) true → success, otherwise the same `confirm_phone_first` / `offer_slot_first` payload.

Knowledge-base coverage checked in these runs: RO FAQ (prices, referral, Saturday, scratched lenses, frame deadlines, cataract via Bulevard, vitamins, directions), HU GYIK, RO/HU/EN glossaries (strabismus, amblyopia, OCT, unconfirmed terms LASIK / insurance / prescription validity), website contact data.

## Live state at the end of the session

Branch version **`agtvrsn_0701m1yz8bcgeambxd4wnjrggahm`** (57 workflow nodes) = prompt v8 + cancel procedure v6, in which the reschedule branch ends after `manage_appointment(reschedule)` and the base agent does availability → offer → book.

That last decision turned out to be wrong: in the confirmation run the agent offered the new slot correctly, the caller accepted, and the agent then **told the caller the request was registered without ever calling `evolvo_book_appointment`**. Nothing was written to evolvo, but the caller was told something untrue.

Prepared and **not pushed** (session paused here):
- `cancel_or_reschedule` v7 — booking back inside the procedure as an explicit step after the offer step, sending `slot_accepted`; the n8n gate now backs it up. Draft saved on the branch, compiled to 64 nodes in `scratchpad/compiled12.json` (identical to the live-tested 64-node graph except two node texts).
- Test 09 v4 with the two-flag mock.

Until that is pushed, the "move my appointment" flow can mark an appointment for rescheduling and then claim a new time that was never booked. Do not demo it.

## Left for the user
- Delete the real test appointment created for the modification tests: **Paciens Teszt, 16 Sept 2026 09:00, Dr. Baricz Anna, Doja**. A 14 Sept 13:00 appointment for the same patient also exists.
- Test rows in the callback Google Sheet from today (Paciens Teszt / 123123123).
- Attach the v2 `.pls` files per language preset in the UI and delete the three v1 dictionaries (`GUiK0bU2xPSyITJxfQ3v`, `kXMpddUIHB3X3pNefKes`, `oKpLYmPdRXx62fVO1iG0`).
- Decide on the reschedule push above; merging the branch into Main remains your call.

## Notes for whoever continues
- A "push" is one `agents_update` with `body.workflow` on the branch: it creates a new branch version and commits procedure drafts. Main, phone numbers and live callers are unaffected. There is no shortcut — the whole ~115 KB graph goes in one call, so diff the new compile against the previous one and only re-read the procedure that changed.
- `agents_compile_procedures` returns the graph but does **not** persist it.
- `agents_run_tests` over MCP always times out; the run starts anyway, poll `agents_list_test_runs`.
- ElevenLabs MCP tools are deferred in this environment: load them with `ToolSearch` first, or calls fail with "could not be parsed as JSON".
- Prefer a deterministic n8n check over prompt wording every time. Three rounds of wording did not fix the read-back; one `if` in a Code node did.

## Round 7 (2026-09-09) — cancel/reschedule identified by phone only

**Why:** the identity check was phone + full name. A real tester said "Csergo Zsofia" and the agent heard "Cerches Zofia" — far outside what the fuzzy matcher in n8n could rescue, so a legitimate caller could not reach her own appointment. Names are now out of the identification path; a second, explicit confirmation step replaces them.

**The flow now:** ask the phone number → read it back digit by digit → `evolvo_find_appointments(phone, phone_confirmed)` returns *every* appointment on that number with the name evolvo has on each → the agent names ONE back ("a programare pe numele Csergő Zsófia, miercuri, ora zece și douăzeci — aceasta?") → only after a clear yes does `evolvo_manage_appointment` run, with the appointment's `ref`, its `date` and `appointment_confirmed: true`.

**n8n (workflow `jLUnlrt9zM8VWZvp`, live):**
- `FIND Validate Input` — `full_name` no longer required (accepted and ignored); phone gate unchanged.
- `FIND Format Results` — no name filter; returns `count`, `persons[]`, `appointments[]` with `ref`, `person`, split `date`/`time`, and a `next_step` instruction.
- `MAN Validate Input` — requires `ref` **or** `date`, plus `action`; carries `appointment_confirmed` and `conversation_id`.
- `MAN Find Target` — resolves by `ref` (falling back to `date`), refuses `ambiguous_appointment` when a date matches several, refuses `ref_date_mismatch` when the two disagree, and enforces the **`appointment_confirmed` gate** (with the 5-second replay guard, like `phone_confirmed`) before `update_schedule.php` is ever called.
- `ref` = 4-char base36 hash of the record's `scheduleid`, so it is stable between the find and manage calls and immune to list re-ordering. A positional index was rejected for exactly that reason: a record appearing or disappearing between the two calls would silently shift it onto someone else's appointment.

**ElevenLabs (main branch, `agtbrch_6201kyq03wjnfct8p3w3bbt750vc`):**
- `evolvo_find_appointments` (tool_4201…) — `full_name` removed from the schema entirely, so the agent cannot ask for it; description rewritten.
- `evolvo_manage_appointment` (tool_9901…) — `full_name` removed; `ref`, `date`, `appointment_confirmed`, `conversation_id` added; all four plus `phone` required.
- `cancel_or_reschedule` procedure (agtprc_4901…) — the name step is gone from the identification path (it survives only in the "nothing found → callback" branch, where the name is just written down for the colleague). The find step now names the person on each appointment and waits; both act branches send `ref` + `date` + `appointment_confirmed`; the reschedule branch reuses the `person` from the record for the rebooking instead of asking.
- Base prompt — "Cancelling or changing an appointment" rewritten; the "never say the caller's name" rule gained one explicit exception for names that come back from the lookup.
- Compiled workflow pushed and then **verified byte-for-byte** against the compiler output (34 nodes, 37 edges, 0 mismatches), and the prompt verified identical after the push.

**Live verification (real evolvo records, 2026-09-09):** two bookings on the same phone 123123123 under different names (Paciens Teszt 14:40 CRM appointment, Teszt Csaladtag 14:20 agenda lead) → find returned both with distinct refs and `persons[]` → cancel without `appointment_confirmed` was refused with the read-back → wrong-date cancel refused with `ref_date_mismatch` → bogus ref refused with the list → confirmed cancel removed exactly the right one and left the family member's appointment untouched (its ref did not shift) → second cancel cleaned up. Both test records are now `Anulat` in evolvo and can be deleted by staff.

**New test:** `test_4801m22pmhrqed59wvb2s84jf1g8` "PHONE-ONLY RO cancel: family phone, two people, cancels only the confirmed one" — mocks find/manage, fails the agent if it asks for a name or cancels the wrong ref. **Run against main 2026-09-09: passed all six criteria** (suite_7101m22pmw9kfccsfh1y4yck9acj) — the agent asked only for the number, sent no name, read both people back, and cancelled ref UGM6 / 2026-09-15 only. Test-authoring note: a success criterion about a branch the run may not enter must say "treat as met if it did not happen", otherwise the evaluator returns `unknown` and the whole run reads as failed.

**Re-recorded tests (2026-09-09, the old name-based versions deleted):**
- `test_6401m22qr02me018pes556x2ym7y` — "STRESS 10 RO cancel wrong date v3 (phone-only)": the caller asks about a date that does not exist; the agent must not ask for a name and must not cancel the appointment the caller did not confirm.
- `test_8601m22qs0x5f3fvqbj808drxtz7` — "STRESS 09 RO modification v5 (phone-only)": full reschedule, including the explicit criterion that `evolvo_book_appointment` MUST be called after the caller accepts a time, and that the booking carries the name from the lookup rather than anything the caller said aloud. **Passed** after the merged-step fix below.

### Defect found and fixed by the re-recorded STRESS 09: the booking step was being skipped

First run of the re-recorded test failed on exactly the defect memory had recorded as open since round 6. The transcript showed the engine firing `notify_condition_1_met` for the branch entry AND for the edge out of the offer step in the same turn - so it entered the *booking* node early, did the manage + availability work from there, and when the caller accepted a time it judged that node's goal met, called `end_procedure`, and the call ended with the old appointment marked for rescheduling and **no new booking**:

```
user: nouă, da, e bine
   >>> notify_condition_1_met   (edge _6_3 -> End Procedure)
   >>> end_procedure
agent: Am înțeles. Doriți să vă mai ajut cu ceva?      <- nothing booked
```

**Fix:** the reschedule branch's two steps (offer, then book) were merged into ONE step, so there is no intermediate edge for the engine to fire early; the single remaining exit edge's goal text now explicitly requires that `evolvo_book_appointment` returned success true. Graph went 34 nodes/37 edges -> 33/36; pushed and verified byte-for-byte again (0 mismatches). The re-run passed, with the evaluator confirming: "După ce utilizatorul a acceptat ora, agentul a apelat evolvo_book_appointment. Apelul a returnat 'success': true".

**Lesson for this engine:** a step that ends in "wait for the caller's answer" followed by a separate step that must call a tool is fragile - the deterministic engine can enter the second node early and then treat the first node's work as that node's completed goal. Keep "offer, wait, then act" inside a single step.

### Open, unrelated to this change: the phone number is asked twice on the cancel fallback path

STRESS 10 currently fails on ONE criterion (no repeated questions). When the caller says none of the found appointments is theirs, the cancel procedure ends and the base agent starts `escalate_to_human`, which asks for the name and then for the phone number **again**, even though the caller dictated and confirmed it earlier in the same call ("Skip only if the caller already dictated a number earlier in this call" is not honoured). Functionally the callback is still logged correctly; it is a repeat-question nuisance. This is pre-existing behaviour in `escalate_to_human` (agtprc_4401...), untouched by the phone-only work, and fixing it needs another compile + full workflow push.

**Note:** the obsolete `n8n-evolvo-integration` branch lost its compiled workflow while probing whether `body.workflow` merges or replaces (it **replaces**). The branch's procedures are intact and main is 7 commits ahead of it, so nothing of value was lost — but do not run tests against that branch until it is recompiled.

### The escalation flow no longer re-asks for a phone number (2026-09-09)

Goal: the callback/"a colleague will ring you back" flow must not make a caller dictate a number they already gave earlier in the same call.

**What did not work — worth knowing before trying it again:** rewording alone. `escalate_to_human`'s steps already said "the only exception is when the caller has already dictated a number earlier in this call", and the agent ignored it. Merging the four collection steps into one and strengthening the wording to "If the caller has dictated a phone number at any point in this call, you HAVE the number: never ask them to dictate it again" **also did not work** — the agent still asked. Two reasons: each ask step's exit edge requires "the end user has given an appropriate response", so a genuinely skipped step has no user turn to advance it; and a node instruction that enumerates asks reads as a checklist to work through. Asking this engine to introspect the call and then *not speak* is not reliable.

**What did work — the same server-side pattern as every other guard here:**
1. `FIND Validate Input` and `BOOK Validate Input` now record the number against the conversation id once their read-back gate passes (`sd.confirmedPhone[conversation_id]`, 6-hour expiry).
2. `LOG Validate Input` recovers it: `phone` is no longer required in the request; if it is absent and the conversation has a confirmed number, that number is used and the read-back gate is skipped (it was already confirmed in this call). If nothing is known it answers a new, specific error `phone_missing` telling the agent to ask for one.
3. `evolvo_log_request`: `phone` and `phone_confirmed` dropped from `required`; the tool description and the `phone` parameter description now say to leave them out entirely when a number was already confirmed in this call.

Net effect: the agent has no reason to ask, and even if it were inclined to, the tool no longer needs the value. Verified against the live webhook: LOG with no phone and nothing remembered → `phone_missing`; after a FIND in the same conversation confirmed 123123123 → LOG with **no phone** → `success: true`, number recovered. (That check wrote one row to the callback Google Sheet: "Teszt Elek / TEST - ignore, automated check of phone recovery" — safe to delete.)

**One more engine lesson, learned the hard way in the same change.** Merging escalate_to_human's four steps into one removed the double-ask but broke something worse: in one run the merged step's exit edge fired on the caller's answer to the NAME question, so the procedure ended and `evolvo_log_request` was never called - the agent promised a callback that was never logged. A tool call needs its OWN node, whose goal *is* the call. Final shape: say -> ask name (only if missing) -> call log_request -> end (4 nodes). So the rule is two-sided:
- an "offer/ask, wait, then call a tool" sequence must be ONE step (or the engine ends the procedure before the tool call);
- but a step that both asks a question and then calls a tool is fragile in the other direction, because the caller's answer to the question can satisfy the step's exit edge. Put the ask and the tool call in separate steps whenever the ask comes FIRST and the tool call does not depend on a second caller turn.

Graph history for this change: 33 -> 30 nodes (merge) -> 31 nodes (dedicated log step).

**Watch out:** during the last push the cancel procedure's callback step was hand-edited in the pushed graph (to drop the phone from log_request) without updating its procedure source, so the next compile would have silently reverted it. The source was brought back in line and a fresh compile now matches the live graph exactly (0 differences). If you ever hand-edit a node in a push, update the procedure draft to match in the same session.

---

## Round 8 (2026-09-09) — noise robustness for callers in loud environments

Client concern: "kicsit attól félek, hogy ha zajos lesz nagyon a környezet, amiből telefonálnak, akkor nem fog válaszolni, s beszédnek érzékeli - van ilyen?"

Assessment: the "won't answer" half is low risk (turn_timeout 7 s re-engages, silence_end_call_timeout 25 s bounds the worst case). The "hears noise as speech" half was real — the agent was running defaults tuned for a quiet caller. Applied, agent-level (`agents_update`, main branch, no prompt or workflow change):

| Setting | Was | Now | Why |
| --- | --- | --- | --- |
| `vad.background_voice_detection` | false | **true** | TV, a second person, waiting-room chatter no longer register as the caller |
| `turn.turn_eagerness` | normal | **patient** | fewer false turn-ends; also suits elderly callers who pause mid-sentence |
| `turn.speculative_turn` | true | **false** | no generating on a turn that noise has not actually ended → fewer false starts |
| `turn.retranscribe_on_turn_timeout` | false | **true** | on a confused VAD the buffered audio is re-transcribed instead of the agent going quiet (note: disables silence-discount billing on affected turns) |
| `turn.interruption_ignore_terms` | empty | **33 ro/hu/en backchannels** | "da", "igen", "aha", "mhm", "jó", "yeah"… no longer chop the agent mid-sentence |
| `turn.interruption_ignore_term_languages` | empty | **["ro","hu","en"]** | ElevenLabs' curated lists |
| `turn.merge_with_default_ignore_terms` | false | **true** | keeps the platform defaults on top of ours |
| `turn.transcribe_on_disabled_interruptions` | false | **true** | needed alongside the tool change below, so speech during a lookup is still transcribed |
| `asr.keywords` | empty | **24 terms** | Optofarm, Fortuna, Baricz, oftalmolog, optometrist, programare, reprogramare, anulare, consultație, dioptrii, ochelari, lentile, Târgu Mureș, Reghin, Sovata, szemész, szemészet, időpont, lemondás, foglalás, Marosvásárhely, Szováta, Szászrégen |

Plus all five evolvo tools (`agents_update_tool`): `interruption_mode: allow` → **`disable_during_tool`**, so noise cannot derail the agent while a lookup runs. The tools carry no `response_mocks` (test mocks live on the tests), so replacing `tool_config` is safe — but the update DOES replace the whole config, so always re-send it in full.

`disable_first_message_interruptions` was already true; nothing to change there.

Verified after both pushes: workflow 31 nodes / 34 edges, 5 tool_ids, prompt length 28167, TTS `eleven_v3_conversational`, phone `+40373800850` still assigned — all unchanged. (`phone_numbers` comes back as `[]` in an `agents_update` response even when the number is still attached — check with `agents_list_phone_numbers`, not the update echo.)

**Not provable by the test suite:** the simulation harness cannot inject background noise. These need one real call from a loud environment (speakerphone in a car, TV on) to validate. Trade-offs: patient + background filtering make the agent feel slightly slower, and a caller can no longer interrupt the agent with a bare "da"/"igen".

### Open question: silence after a human answers a transfer

There is **no delay/silence setting for `transfer_to_number`**. `delay_ms` exists only on `transfer_to_agent` (agent→agent). The live transfer config exposes `transfer_type` (conference), `enable_client_message` (true), `sip_refer_play_dialtone`, `post_dial_digits` (DTMF only — 'w' = 0.5 s pause, does not delay speech), `custom_sip_headers`, `uui`, and an undocumented **`require_acceptance` (currently false)**. TTS is `eleven_v3_conversational`, and **v3 does not support SSML `<break time="1s"/>`**, so a break tag cannot pad the handoff message.

Two options, neither applied yet:
1. `require_acceptance: true` — undocumented, but the field is live on the transfer object. Would presumably make the receiving human accept before the caller is bridged, which structurally solves "the phone was not at their ear yet". **Risk:** if staff do not know they must accept, an emergency transfer could fail outright. Needs a test call before it goes near the emergency path.
2. Pad the warm-transfer `agent_message` with a throwaway lead-in ("Alo? Bună ziua, aici asistentul virtual Optofarm…") so the first ~1 s carries no information. Prompt-only, no platform risk, works on any model. `agent_message` is Twilio-native-only, and this agent's number is Twilio, so it is available.

### Round 8b (2026-09-09) — option 2 applied, and an incident that cost the tool ids

**Applied:** the `transfer_to_number` tool description now tells the agent that `agent_message` (what the colleague who picks up hears) MUST begin with the exact words "Aici asistentul virtual Optofarm." before the one-sentence emergency summary. Those words are deliberate padding so the colleague has ~1 s to get the phone to their ear. `require_acceptance` left at false.

**INCIDENT — do not repeat.** `agents_update` with `conversation_config.agent.prompt.tools` **cleared `prompt.tool_ids` and DELETED the five evolvo workspace tools.** A GET hydrates `prompt.tools` into a 9-entry list (5 webhook + 4 system), but that list is a projection: writing it back is not idempotent. `tools` and `tool_ids` are mutually exclusive on a PATCH ("Cannot specify both tools and tool IDs"), and setting `tools` orphaned then removed the webhook tools.

Recovery, all verified: the five tools were recreated from the configs captured earlier in the same session, then attached with a `tool_ids`-only PATCH — which does NOT wipe the inline system tools. The agent is back to exactly its pre-incident shape: same 9 tools in the same order, 5 tool_ids, workflow 31 nodes / 34 edges, prompt length 28167, all Round 8 turn/VAD/ASR settings intact, and the new transfer lead-in present.

**Rules that follow:**
- To change a SYSTEM tool (end_call, language_detection, transfer_to_number, skip_turn): PATCH `prompt.tools` with ONLY the four system tools, then immediately re-PATCH `prompt.tool_ids` with the five webhook ids. Never include webhook tools in `prompt.tools`.
- To change a WEBHOOK tool: use `agents_update_tool`, never the agent config.

**New tool ids (the old ones are dead):**

| Tool | Old id | New id |
| --- | --- | --- |
| evolvo_check_availability | tool_5301m1y0xsjwfkxa8s4ygsq44a7f | `tool_6001m237nj7ref3aajw2s6pzq4r3` |
| evolvo_book_appointment | tool_8401m1y0y2zge0rt6pqtm0n75ckt | `tool_1901m237p5gsez290zmjdkt5sn0j` |
| evolvo_find_appointments | tool_4201m1y0y897f1ts1tjwefk90v9n | `tool_7401m237pg7re6e8r9maz16v2db9` |
| evolvo_manage_appointment | tool_9901m1y0yf1re6qt7xjjyr31reqc | `tool_2301m237pzbyf3tbsn61mpgngmfr` |
| evolvo_log_request | tool_9101m1y2m48heyks8pbph93ssffj | `tool_6801m237qjc1ecfaat76ebsxxkhs` |

The workflow was unaffected: its procedure nodes reference tools by NAME, and the only place the old ids appeared was `prompt.tool_ids`.

**RESOLVED (see Round 8c below) — tests were unsafe to run.** Test mocks reference tools by ID (`tool_mock_config.mocked_tool_ids` and `tool_mock_overrides`), so every mocked test still points at the dead ids. With `fallback_strategy: call_real_tool`, running them now would call the live n8n webhooks and write real records into evolvo. Remap the ids before the next `agents_run_tests`. There is no `agents_update_test` in the MCP surface, so each affected test must be deleted and recreated (which changes its test id — update the ids recorded in this file when that is done). Affected tests are the ones with evolvo mocks, among: PHONE-ONLY cancel `test_4801m22pmhrqed59wvb2s84jf1g8`, STRESS 09 `test_6701m22weasqepxvwx9kn9kgf7vd` / `test_8601m22qs0x5f3fvqbj808drxtz7`, STRESS 10 `test_4101m22wda2bepmr0cyjmc159mxn` / `test_6901m22w94tcf919bpbe3577954n`, and the STRESS 01-16 v2/v3 set created 2026-09-08.


### Round 8c (2026-09-09) — test mocks remapped to the new tool ids

Test mocks reference tools by ID (`tool_mock_config.mocked_tool_ids` and `tool_mock_overrides` keys), so all 21 Optofarm tests pointed at the deleted ids. There is no `agents_update_test`, so each was recreated with the new ids and the original deleted. Scenarios, success conditions, turn limits, evaluation/simulated-user models and mock payloads were carried over verbatim. Non-Optofarm tests in the workspace (the EV-charging set) were untouched.

| Test | New id |
| --- | --- |
| PHONE-ONLY RO cancel (family phone) | `test_1201m23812zefe7a2mkdvm0ex942` |
| STRESS 09 v6 modification | `test_0301m2381xw2fpq9nvqetcgb39mq` |
| STRESS 09 v5 modification | `test_6301m238cv40f6frexe48a4nw6sq` |
| STRESS 10 v5 cancel wrong date | `test_7201m2382g7eej88bnpkx7pa11zf` |
| STRESS 10 v4 cancel wrong date | `test_8401m238de3bfhzv1wm2wappmy8w` |
| STRESS 01 Q&A | `test_4701m23888pse9s9q7b4r6jbed6f` |
| STRESS 02 HU Q&A | `test_5601m238eq4yfc1v1vd4qt7fwh37` |
| STRESS 03 consulting | `test_4401m2385bhzfwgbf2avye81wczb` |
| STRESS 04 bad-information asks | `test_7201m2388k0ffyb91tz4tz30ff8a` |
| STRESS 05 truncated booking | `test_2901m23842wpeps864y84xvw142m` |
| STRESS 06 wrong info | `test_2801m2385rare2caxvfcdt9knn0m` |
| STRESS 07 RO emergency | `test_2901m238b7zje3x90k767qy7cg8v` |
| STRESS 08 HU emergency | `test_4401m238b0wde7z84v0e0wr298s1` |
| STRESS 11 injection + abuse | `test_5701m238aq1mfk4vacrghr03dk0h` |
| STRESS 11b abuse + patient list | `test_1701m2387jgfe4891k1c2z5eaxv6` |
| STRESS 12 EN→RO switch | `test_4701m2386k6gecftwaks0npx2h7b` |
| STRESS 13 bad numbers/dates | `test_4801m238665yf408mfqtb7bw3w2r` |
| STRESS 14 escalation | `test_4001m2384cjre9csm0mrs05qj5dw` |
| STRESS 15 nonsense/silence | `test_2201m238acm5envba3h3yd04qh5k` |
| STRESS 16 directions | `test_9601m2387x4hfb1tq3z1kf8gn046` |
| Emergency 'substanță chimică în ochi' | `test_2401m238bxv0f49tb5bmg1dtvaa5` |

Verified by listing: 21 Optofarm tests, each present exactly once, no stale duplicates.

**Rule for next time:** a test's mocks are keyed by tool ID, so ANY change that recreates a tool invalidates every test that mocks it. Recreate a tool only as a last resort, and if you do, remap the tests in the same session.

### Latency levers (2026-09-09, not applied)

Measured/known state: LLM `gpt-5.6-luna` (temperature 0, `reasoning_effort: none`), system prompt 28,167 chars plus a 31-node workflow, RAG enabled over 6 knowledge-base documents (up to 6 chunks / 50,000 chars), TTS `eleven_v3_conversational` with `optimize_streaming_latency: 3`, ASR `scribe_realtime` at `quality: high`, evolvo webhooks averaging 1.2-1.9 s.

Ranked by effect, biggest first:
1. **TTS model.** `eleven_v3_conversational` is the highest-quality and slowest option. `eleven_flash_v2_5` is the low-latency model and would cut the largest single chunk of time-to-first-audio. Costs some expressiveness; it is also the change most likely to be noticed by the client, so A/B it on a branch.
2. **Two Round 8 settings deliberately traded latency for noise robustness.** `speculative_turn: false` removed the optimisation that starts generating before the turn is confirmed, and `turn_eagerness: patient` waits longer before deciding the caller finished. Reverting either (or both) restores the old speed and gives back some noise resilience. `speculative_turn: true` alone recovers most of the latency at the smaller cost.
3. **Prompt size.** ~28 KB of instructions is re-sent on every turn. Moving reference material (branch details, prices, opening hours) out of the prompt and into the knowledge base, which is already RAG-enabled, shortens every LLM call.
4. **RAG budget.** `max_documents_length: 50000` and 6 chunks is generous; halving both cuts retrieval and prompt-assembly time.
5. **`pre_tool_speech: force` on all five evolvo tools** adds a spoken line before every tool call. It masks webhook latency rather than reducing it, and it lengthens the exchange. `auto` speaks only when the tool is actually slow.
6. **ASR `quality: high`** can drop to a faster tier, though this works against the noise-robustness work.
7. **n8n webhooks** average 1.2-1.9 s. Caching evolvo's `get_info` calendar list for longer, or warming the session token, would trim the availability lookup.

### Round 8d (2026-09-09) — speculative_turn back on, baseline suite, and why the prompt trim was NOT done

`speculative_turn` set back to **true** (verified). Everything else from Round 8 stays: `turn_eagerness: patient`, background voice detection, ignore-terms, ASR keywords, `disable_during_tool` on the tools.

**Baseline suite run `suite_9801m238nwt7e1k8g3xrcrcjt7ys` (21 tests, version `agtvrsn_2501m238mrx2fhws5m047m4h78gv`): 8 passed, 12 failed, 1 pending.** The mocks work again, so these are real results. Breaking the 12 down:

- **Genuine behaviour failures (5):** STRESS 03 — never defined "ochi leneș"/"strabism", jumped straight to offering an appointment. STRESS 04 — collected the callback details but no `evolvo_log_request` call in the transcript. STRESS 12 — collected name and confirmed phone but never called `evolvo_book_appointment`. STRESS 05 — offered a 14 September slot after the caller said October. STRESS 07 — the emergency reply was only "Mergeți acum la urgență", without saying a doctor must see it immediately or that a colleague is being connected.
- **Style-only (2):** STRESS 14 repeated "un coleg vă va suna înapoi" twice; STRESS 10 v5 did not spell out that no 20 September appointment exists.
- **Not the agent's fault (5):** STRESS 09 v5 died as `qa_empty_response` (harness flake). STRESS 11 came back "Evaluation inconclusive" because the prompt-injection guardrail correctly ended the call before the agent could answer. And several criteria are written as conditionals — "If a booking call returned confirm_phone_first…" — which the evaluator scores as FAILED when the precondition never occurs (STRESS 03 c6, STRESS 05 c6, STRESS 06 c5, STRESS 12 c5). Those tests cannot pass even against a perfect agent and should be rewritten.

None of these are regressions from the Round 8 work.

**The prompt trim was deliberately NOT applied. Reason: the knowledge base already holds the facts, and part of it contradicts the live agent.** The RO FAQ (`zynIEChUpgg4AaEbZInG`, 6,940 B) and the HU GYIK (`l7TG9P3XnTjgRThXelU5`, 6,702 B) already contain almost the whole "# Facts you may state" block — referral, all prices, exam duration, prescription, when glasses are ready, scratches, broken frame, repairs, clips, same-day deadlines, stock, cataract, Saturday hours, the Republicii landmark. So that ~4.7 KB of prompt is duplication, not unique content.

But RO FAQ sections 15-17 are **stale, from before the evolvo tools existed**, and say the opposite of what the agent now does:

> "Nu vezi calendarul, deci nu spune niciodată că o oră este liberă și nu confirma niciodată o programare ca fiind făcută. Preiei doar o cerere, pe care colegul o confirmă la telefon." … "Anularea unei programări existente și mutarea unei programări existente se tratează la fel: preia numele, punctul de lucru și numărul de telefon … Nu spune niciodată că ai anulat sau ai mutat programarea."

That is a plausible cause of the STRESS 12 and STRESS 04 failures — the agent collected the details and then did not call the booking / log tool, which is exactly what this text instructs. Trimming the prompt would remove the counterweight and make the stale FAQ *more* authoritative, so it must be fixed first.

**Order of work for the next session:** (1) rewrite RO FAQ §15-17 and the HU equivalents to match the tool-based flow; (2) add the six facts that live only in the prompt and are in neither FAQ — children's screening / myopia / lazy eye and squint, the services list, the lens factory and coatings, B2B wholesale, "founded 1991", and "laser correction: unknown"; (3) only then trim "# Facts you may state" from the prompt down to a pointer, keeping the branch-normalisation table and the answering rules, which are behavioural and must stay; (4) re-run the suite and compare against the 8/12/1 baseline above.

### Round 8e (2026-09-09) — knowledge base made authoritative, prompt trimmed

The prompt was treated as the fresh source of truth and both FAQ documents were rewritten to match it, in place (`agents_update_kb_document` accepts `content` for text documents, so the ids and the agent's knowledge_base locators are unchanged).

RO `zynIEChUpgg4AaEbZInG` 6,940 → 9,951 B; HU `l7TG9P3XnTjgRThXelU5` 6,702 → 9,753 B. What changed in both:

- **§17 rewritten.** The stale pre-tools text ("Nu vezi calendarul … nu confirma niciodată o programare ca fiind făcută. Preiei doar o cerere") is gone. It now says the agent sees real availability, books with the tools, confirms only on a successful tool response, distinguishes `appointment_linked_to_existing_patient` from `lead_pending_staff_confirmation`, identifies by phone only for cancel/reschedule, and falls back to a callback request **only** when the tools cannot finish the job.
- **§15 split into §15 emergency / §16 urgent-but-not-emergency**, matching Step 0 of the prompt: the emergency list, one sentence, immediate transfer, never 112 — separate from foreign body / eye pain, which gets the earliest tool slot.
- **"fă legătura cu un coleg" / "kapcsold a kollégához" → callback request** everywhere except the cataract case (which gives the Bulevard branch number). The agent can only transfer in a medical emergency, so the old wording invited an action it cannot perform.
- **Six facts added** that existed only in the prompt: children's screening / myopia control / lazy eye and squint (with the one-sentence definitions STRESS 03 asks for), the services list, the lens factory and coatings, B2B and wholesale, founded 1991, and laser correction as explicitly unknown. Eight locations and roughly seventy staff added to §18.

Prompt: `# Facts you may state` (~4.7 KB) replaced by `# Facts and how to state them`, a pointer plus the behavioural rules; "the prices listed below" in Decision logic Step 1 became "the prices in your knowledge base". The branch-normalisation table, the Locations block, the Saturday rule and "Things you do not know" stay in the prompt — they are behavioural or tool-mapping, not reference. **28,168 → 25,535 chars, about a 9% cut** — smaller than hoped, because the replacement pointer is itself ~1.9 KB. Pushed with the top-level `prompt` parameter of `agents_update`, which avoids the `tools`/`tool_ids` landmine from Round 8b entirely; the live prompt was then diffed against the locally generated intended text and came back **identical**, with 9 tools / 5 tool_ids / 31 nodes / 34 edges / 6 KB documents intact.

**Known cosmetic defect:** the Hungarian §1 line reads "mentegetzőzés nélkül"; it should be "mentegetőzés nélkül". One word in an instruction line, not customer-facing output — fix it on the next write to that document.

**Post-change suite `suite_1701m239h1v0efc94s1s3v73b0ce` (version `agtvrsn_7301m239c0jtfm5bnwrydrv11mff`): 8 passed / 13 failed, against the 9 / 12 baseline. Flat, and inside the noise.** Three fixed, four broke, fourteen unchanged:

- **Fixed:** STRESS 07 (the emergency sentence is now complete), STRESS 09 v6 (reschedule now books the new time), STRESS 10 v5.
- **Broke:** PHONE-ONLY cancel, STRESS 10 v4, STRESS 11b, STRESS 16.

The four regressions are **not** factual — no test failed on a fact that moved into the knowledge base:

- **STRESS 16** passed criteria 1, 2 and 3 — the Republicii landmark, the doctors from the tool, AND the two-hours-before-closing frame deadline, which is now knowledge-base-only. It failed solely on criterion 4, more than two sentences per turn while listing doctors. This is the clearest evidence that retrieval works after the move.
- **STRESS 11b** passed criteria 1-4 and failed only on a duplicated generation: `"...Este corect?Numărul este unu, doi, trei — ... Este corect?"` — the read-back sentence emitted twice, concatenated with no space. **Hypothesis worth testing: this is `speculative_turn: true`, re-enabled this round for latency** — a speculative generation that was not discarded when the turn resolved. If duplicated output shows up on real calls, that is the first setting to flip back.
- **STRESS 10 v4** failed criterion 7 for repeating "Un moment, vă rog." — but the v5 rewrite of the same test explicitly forgives the holding line ("saying it more than once is correct, not a repetition"). v4 is simply the older, stricter wording; a test-authoring inconsistency, not a regression. v4 and v5 are near-duplicates that flipped in opposite directions this run, as did STRESS 09 v5 and v6 — good evidence of run-to-run nondeterminism rather than signal.
- **PHONE-ONLY cancel** is the one genuine behaviour failure: the agent said "Anulez programarea acum." in the same turn as the tool call, before `evolvo_manage_appointment` returned success. That violates the standing guardrail "NEVER confirm … unless the tool confirmed it", which is still in the prompt. Worth a targeted fix.

**Conclusion: the prompt/KB refactor is behaviour-neutral on facts and cost about 9% of prompt size.** The suite's real problem is that a third of its criteria are conditionals or stricter-than-intended style rules, so it cannot cleanly measure a change of this size. Before the next behavioural round, rewrite those criteria; otherwise every comparison stays inside the noise.
