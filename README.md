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

**ElevenLabs — moved to a new account.** The agent has been rebuilt on a **different ElevenLabs
account** from the one the older documents describe. Everything in this repository that names an
ElevenLabs `agent_…`, `tool_…`, `test_…`, `agtbrch_…` or `agtprc_…` id predates that move and those
ids are **dead**. Treat the ElevenLabs documents here as a record of *decisions and reasoning* —
which are still valid and hard-won — rather than as a set of working identifiers. The n8n side is
unaffected: the webhooks, their URLs and their auth are unchanged, and the new agent talks to exactly
the same five endpoints.

> **If you are picking up the ElevenLabs half:** please record the new account, agent id, tool ids and
> branch here, so the next person does not have to ask.

## Handover: what the n8n side needs from the ElevenLabs side

Nothing is broken without these — the mechanism works today, because both tools already send
`system__conversation_id`. These are wording changes that stop the agent from mis-describing what
actually happened.

1. **`evolvo_book_appointment` — teach it about `replaced_appointment`.** After a reschedule, the
   booking response now carries `replaced_appointment` and the old appointment is *already*
   cancelled. Without a line about it, the agent may call `evolvo_manage_appointment` to cancel the
   old one, receive `appointment_not_found`, and — following its own description — tell the caller a
   colleague will call back. A completed reschedule then sounds like a failure.
   Add: if `replaced_appointment.cancelled` is true, say the appointment was moved and do **not**
   cancel the old one; if false, the new time is booked but a colleague must remove the old one.

2. **`evolvo_manage_appointment` — make the order explicit.** It already says to run availability +
   booking after a reschedule. Add that booking the new time cancels this appointment automatically
   and frees its slot, so the tool must never be called again to cancel it. The order **mark → book**
   is now load-bearing: booking first leaves the old slot blocked.

3. **Check the cancel/reschedule procedure** still marks before it books.

4. **Tests that mock `book_appointment`** should include `replaced_appointment` in the mocked
   response, or the reschedule wording is never exercised.

A design note, since it has caught everyone: the deterministic procedure engine skips "ask the
caller" steps in roughly one run in three, whatever the wording. That is why the phone read-back,
the slot offer and the appointment confirmation are all enforced **server-side in n8n** and answered
with an error that tells the agent what to say next. Prefer a new guard in n8n over a new sentence in
the prompt — the prompt route has failed repeatedly where the guard worked first time.

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
