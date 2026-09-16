# Optofarm voice agent

A Romanian/Hungarian/English voice agent for the Optofarm eye clinics that answers the phone, offers
real appointment times, books them, and cancels or reschedules existing ones — against the live
droot/evolvo scheduling system.

It has two halves, and they are usually worked on by two different people:

| Half | What it is | Start here |
|---|---|---|
| **ElevenLabs** | the agent itself — prompt, procedures, tools, knowledge base, tests, phone number | [`elevenlabs/README.md`](elevenlabs/README.md), [`ELEVENLABS_AGENT_STATUS.md`](ELEVENLABS_AGENT_STATUS.md) |
| **n8n** | everything the agent can *do* — five webhooks wrapping the evolvo API | [`n8n/README.md`](n8n/README.md), [`n8n/CHANGELOG.md`](n8n/CHANGELOG.md) |

**The contract between them is [`api-docs/ELEVENLABS_TOOLS.md`](api-docs/ELEVENLABS_TOOLS.md)** — the
five webhook schemas, their success shapes, and every error the agent has to handle. If you change
one half, that file is how the other half finds out.

The agent never calls evolvo directly. It only ever calls the n8n webhooks, which hold the
credentials, do the multi-call scans, and enforce the safety rules.

## Repository map

```
README.md                     you are here
INTEGRATION_PROGRESS.md       running project log
N8N_WORKFLOW_ARCHITECTURE.md  deep architecture notes on the workflow
ELEVENLABS_AGENT_STATUS.md    agent status by round — the ElevenLabs half's main log

api-docs/                     the evolvo API + the webhook contract
  ELEVENLABS_TOOLS.md           ← the contract between the two halves
  QUESTIONS_FOR_IMREH.md        open questions for dRoot Solutions
  <endpoint>.json               per-endpoint schema + a live example, one file per evolvo call

n8n/                          the n8n half
  README.md                     instance, branches, credentials, how to edit safely
  CHANGELOG.md                  dated record of every change
  slot-release-and-reschedule.md   2026-09-14 investigation and fix
  qa-followups-answers.md       answers to the ElevenLabs side's open questions
  provider-type-runbook.md      doctor vs optometrist routing
  Optofarm-WIP.workflow.json    redacted export of the live workflow
  smoke-test.sh                 read-only checks + guard paths

elevenlabs/                   the ElevenLabs half — prompt, procedures, KB, QA notes
thirdpartyai-live.postman_collection_v*.json   evolvo's own Postman collections (keys redacted)
```

Note: several older documents refer to files by their `api-docs/…` and `n8n/…` paths. Those paths are
correct again — an earlier bulk upload had flattened everything into the repository root.

## Current state (2026-09-14)

**n8n — working and live.** All five webhooks are in production on one workflow. Availability,
booking (both as a lead and linked to an existing CRM patient), lookup by phone, and
confirm/cancel/reschedule all work end to end against the real clinic system. The most recent work
verified that cancelling an appointment releases its slot in about 8 seconds, and fixed two defects
it uncovered — a reschedule that leaked a slot on every use, and an untranslated Romanian state
reaching the agent. See [`n8n/slot-release-and-reschedule.md`](n8n/slot-release-and-reschedule.md).

**ElevenLabs — an account move was reported, but the live evidence does not show one.** This was
recorded here on 2026-09-14 as "the agent has been rebuilt on a different account, every id in this
repo is dead". Two independent live reads on the same day contradict that: the ids in the table
below were read from the live API by the ElevenLabs side, and the n8n side separately queried the
API and saw the *same* account and the *same* agent, actively taking calls. **Treat the table below
as the truth and this paragraph as an open question** — if a second workspace does exist, whoever
knows should record it here, because right now nothing points to one.

What is certainly true is that **ids in the older documents are unreliable** — the tool ids were all
rotated on 2026-09-09 (see `ELEVENLABS_AGENT_STATUS.md` round 8b) and most tests were recreated after
that, which changes every test id. Read the older ElevenLabs documents for their *decisions and
reasoning*, which are still valid and hard-won, and take identifiers only from the table below.

Either way the n8n side is unaffected: the webhooks, their URLs and their auth are unchanged, and the
agent talks to exactly the same five endpoints.

### The ElevenLabs half, as of 2026-09-14

Recorded per the request above. These are live and verified working today.

| | |
|---|---|
| Account | `zoli@splitagency.eu` (creator/admin on the agent and all five tools) |
| Agent | `agent_3101kyq03vpxfpb9vsskgfh2f0bd` — *Optofarm Agent - DEMO* |
| Phone | `+40373800850`, bound to **Main** |
| LLM | `gpt-5.6-luna`, `reasoning_effort: none`, `temperature: 0` |

**Branches** — `Main` `agtbrch_6201kyq03wjnfct8p3w3bbt750vc` carries **100%** of traffic.
`latency-step-merge` `agtbrch_9901m27xvmtze0ttfaa16t50kd7z` and `n8n-evolvo-integration`
`agtbrch_2201m1y0ysy2fc9rmj3hc3mhszz7` are both at 0%.

**Tools** are workspace-level, so editing one takes effect on every branch at once:

| Tool | id |
|---|---|
| `evolvo_check_availability` | `tool_6001m237nj7ref3aajw2s6pzq4r3` |
| `evolvo_book_appointment` | `tool_1901m237p5gsez290zmjdkt5sn0j` |
| `evolvo_find_appointments` | `tool_7401m237pg7re6e8r9maz16v2db9` |
| `evolvo_manage_appointment` | `tool_2301m237pzbyf3tbsn61mpgngmfr` |
| `evolvo_log_request` | `tool_6801m237qjc1ecfaat76ebsxxkhs` |

All five send `X-Optofarm-Secret` as a **workspace-secret reference**, `secret_id`
`9OEoYk2IVSNikIlwRhqE` — not a literal. When the webhook secret is rotated, update that one
workspace secret and every tool follows; the id itself is not a credential.

**Procedures** (same ids on every branch): `booking` `agtprc_7801m0axd3y3ej590n280yw80rr0`,
`cancel_or_reschedule` `agtprc_4901m0axdt4zev9tmgtcxy60x9da`, `escalate_to_human`
`agtprc_4401m0axbt3rfcfvpj4grmp73wph`.

**Publishing:** `agents_update_procedure_draft` only writes a *draft*. It does not reach live calls
until a version is committed, and the safe way to commit one is a minimal patch — `name` set to its
current value. Never send `conversation_config.agent.prompt.tools`: doing so once cleared
`prompt.tool_ids` and deleted all five webhook tools.

**Tests:** exactly one remains, `Optofarm: emergency 'substanță chimică în ochi'`
(`test_2401m238bxv0f49tb5bmg1dtvaa5`). The 21-test suite the older documents describe did not
survive the account move. Nothing currently mocks `book_appointment`. No tests are attached to Main
— deliberately, since attached tests once blocked publishing entirely.

## Handover between the two halves

### Done — the 2026-09-14 reschedule round is closed on both sides

The n8n side made `book_appointment` cancel a marked appointment once a replacement is booked, and
the ElevenLabs side taught the tools and the `cancel_or_reschedule` procedure to describe that
correctly (`replaced_appointment`, the load-bearing mark → book order, `needs_reschedule` as a live
appointment). See [`n8n/CHANGELOG.md`](n8n/CHANGELOG.md) and
[`elevenlabs/CHANGELOG.md`](elevenlabs/CHANGELOG.md) for each half.

### Open — ElevenLabs side

1. **Nothing currently mocks `book_appointment`.** Only one test survived the account move, so the
   reschedule wording is not exercised by any test, and a test without mocks hits live n8n and writes
   real evolvo records. Add mocks (including `replaced_appointment`) before running any suite.
2. **`latency-step-merge` is superseded — do not merge it.** Its optimised `booking` procedure and
   its prompt content (reminder wording, the never-call-it-a-clinic guardrail, the eight-branch
   landmarks) were ported onto Main on 2026-09-15 and re-merged with the fixes made that day. The
   branch's own copies are now the stale ones: its prompt still scripts `Un moment, vă rog.`
   Re-branch from Main if a branch is needed again.
3. ~~**Zsófi's visit-reason → provider-type list**~~ — **received and wired in 2026-09-15.** Her rule
   confirmed the mapping already written on `evolvo_check_availability`; the actual gap was that the
   booking procedure never *sent* `provider_type`, so every lookup ran unfiltered. It does now.
   A branch with no optometrist is re-searched at branches that have one rather than falling back to
   a local doctor. Unverified in a live call.
4. **The ordering leak is fixed in wording but unproven in a call.** The ported `booking` procedure
   turns "never check availability before the purpose is known" from a rule into a stop condition.
   Watch it on the next smoke test rather than assuming it holds.
5. **The agent speaks dates a day early — one prompt sentence is still missing (raised 2026-09-15).**
   On a live call it offered a slot **40 minutes in the past**: n8n returned
   `earliest 2026-09-16 15:40` and the agent said *"astăzi, marți 15 septembrie, ora 15:40"*, then
   read `2026-09-17 10:00` back as *"mâine, miercuri 16 septembrie"*. Both a day early, weekday name
   included — the model is doing ISO→spoken date arithmetic and getting it wrong, and n8n's data was
   right both times (`conv_4701m2jk8460e2es63a4zbc5j21c`, n8n execution 1409).
   **n8n side is done:** every date now ships with `date_spoken` (`"Wednesday 16 September"`, English,
   to be translated) and `relative_day` (`today` / `tomorrow` / `the day after tomorrow` / `in N days` /
   `IN THE PAST - do not offer this`), and every `note` / `next_step` / `read_back` repeats the rule
   inline. See "Speaking dates" in [`api-docs/ELEVENLABS_TOOLS.md`](api-docs/ELEVENLABS_TOOLS.md).
   **What is needed from your side:** a prompt rule, because the inline tool-result instruction is
   currently the only thing steering the model. Something like *"When you name a day, say the tool's
   `date_spoken` in the caller's language; call it today or tomorrow only if `relative_day` says so.
   Never work a date out yourself."* Also worth knowing: `check_availability` searches from **tomorrow**
   and evolvo rejects a non-future `date_from`, so **no slot it returns is ever today** — if the agent
   ever says "today", it has misread the data, and a same-day appointment simply cannot be offered.

6. **The psycho-orthoptics provider needs a prompt rule (raised 2026-09-16, n8n side done).**
   `Dr. Prof. Szekely Attila  - Consiliere / Terapie psiho-ortoptica` (Republicii) is the only
   calendar of 30 that is not general eye care, and he *was* the earliest free slot at that branch —
   so "the soonest appointment in town centre" offered a psycho-orthoptics counsellor to a caller who
   wanted glasses.
   **n8n side is done:** his name is split into a speakable `doctor` plus a separate `service`, and he
   is now excluded from every search unless the caller **named him** or the tool is called with
   `provider_type: "vision_therapy"` (which works with no location too, since there is only one such
   calendar). `provider_type: "doctor"` and unfiltered searches no longer reach him, and he is kept
   out of every `available_doctors` / `matching_doctors` / `available_provider_types` list so he
   cannot be offered out of an error payload either.
   **What is needed from your side:** the routing rule. He is already in the knowledge base, but
   nothing makes the tool call ask for him. Send `provider_type: "vision_therapy"` for squint, lazy
   eye, eye exercises / *szemtorna*, vision therapy, binocular coordination, vision rehab after a
   stroke, or learning-and-focus difficulties — and never offer him for glasses, contact lenses, eye
   pressure, OCT, general check-ups, eye disease or anything urgent. His full scope is in
   [`api-docs/ELEVENLABS_TOOLS.md`](api-docs/ELEVENLABS_TOOLS.md) under "The specialty provider".
   **Diagnosis first — answered by the clinic 2026-09-16, and now enforced server-side.** An ordinary
   eye doctor must examine the caller and recommend the therapy *before* a psycho-orthoptics
   appointment is made. So "my child has a lazy eye" is offered **a doctor**, not the therapist.
   `check_availability` returns a top-level `specialty_booking_rule` whenever he is in the results —
   with `doctors_for_diagnosis` naming the general providers at his own branch so you can offer the
   consultation in the same turn — and the `note` opens with `READ specialty_booking_rule FIRST`.
   `book_appointment` refuses his slots with `diagnosis_required` unless `diagnosis_confirmed: true`
   is sent, and that refusal happens before anything is written (verified live: his six 17 Sept slots
   were still free after a refused attempt).
   So the prompt should still *reach* him — by name or `provider_type: "vision_therapy"` — because
   that is how it learns the rule applies. What it must not do is offer his times to an undiagnosed
   caller. The shape of that turn: recognise the therapy request → say a doctor's consultation comes
   first → offer a doctor from `doctors_for_diagnosis` → book the therapy on a later call with
   `diagnosis_confirmed: true` once the caller confirms they already have the diagnosis.
   `diagnosis_confirmed` needs adding to the `evolvo_book_appointment` tool schema.

### Open — n8n side, answered 2026-09-14

Both open questions from [`elevenlabs/qa-followups.md`](elevenlabs/qa-followups.md) have been
checked against live data. Full answers: [`n8n/qa-followups-answers.md`](n8n/qa-followups-answers.md).

- **QA item 4 (optometrist vs doctor) — already built.** The `Dr. …` / `Optometrist …` prefix is
  verified across all 30 calendars with nothing unmatched, and `evolvo_check_availability` has
  filtered by `provider_type` since 2026-09-11 — **the agent must not filter the list itself**.
- **QA item 5 (read back a provider's schedule) — not possible.** Neither `get_work_days.php` nor
  `get_info.php` exposes working hours, so a shift end cannot be derived and must not be guessed
  from free slots. Handed to dRoot Solutions as question 10 in
  [`api-docs/QUESTIONS_FOR_IMREH.md`](api-docs/QUESTIONS_FOR_IMREH.md).
- **Worth a look from both halves:** every calendar carries eight `ai_*` fields
  (`ai_doctor_title`, `ai_description`, `ai_public_names_ro/hu/en`, …) and **all are empty**. If the
  clinic can fill them, they would replace the provider-type heuristic, hold the visit-reason
  routing as clinic-maintained data, and give per-language spoken forms of provider names — which is
  the standing ASR problem. Question 11 for dRoot Solutions.

### A design note, since it has caught everyone

The deterministic procedure engine skips "ask the caller" steps in roughly one run in three, whatever
the wording. That is why the phone read-back, the slot offer and the appointment confirmation are all
enforced **server-side in n8n** and answered with an error that tells the agent what to say next.
Prefer a new guard in n8n over a new sentence in the prompt — the prompt route has failed repeatedly
where the guard worked first time.

## ⚠️ Credentials: this repository is public

Two live credentials were committed here and are in the git history:

- the **n8n webhook secret** (`X-Optofarm-Secret`) — in `ELEVENLABS_TOOLS.md`;
- the **evolvo API key** — in both Postman collections.

Both have been removed from the current files, but **removing them from the working tree does not
remove them from the history of a public repository.** The webhook secret is the urgent one: the n8n
webhooks are reachable from the open internet and that header is their only protection, so anyone who
reads the history can create or cancel real patient appointments. The evolvo key is partly shielded
by evolvo's IP whitelist.

Recommended, in order: **rotate the n8n webhook secret** (n8n credential "Optofarm Webhook Secret",
then update the secret on each ElevenLabs tool — the two must change together or live calls break);
**rotate the evolvo API key** with dRoot Solutions; then decide whether to purge the history or make
the repository private.

Nothing in this repository should contain a credential. Names of n8n credentials are fine; their
values are not.
