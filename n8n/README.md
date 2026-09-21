# The n8n side

Everything the voice agent can *do* — check availability, book, find, cancel/reschedule, log a
callback request — is an n8n webhook that talks to the droot/evolvo scheduling API. The ElevenLabs
agent never calls evolvo directly; it only ever calls the five webhooks documented in
[`../api-docs/ELEVENLABS_TOOLS.md`](../api-docs/ELEVENLABS_TOOLS.md), which is the **contract between
the two halves of this project**. If you are working on the ElevenLabs side, that file and
[`CHANGELOG.md`](CHANGELOG.md) are the two you need.

## Where it lives

| | |
|---|---|
| Instance | `https://n8n.splitagency.biz.id` (self-hosted) |
| Workflow | **Optofarm - WIP**, id `jLUnlrt9zM8VWZvp` — *one* workflow, five branches, active |
| Outbound IP to evolvo | `72.62.44.134` (whitelisted at evolvo for reads **and** writes) |
| evolvo base URL | `https://secure.mydroot.eu/evolvo/api/thirdpartyai/` |

Not the `splitagency23.app.n8n.cloud` instance — a Claude "N8n" connector defaults there and it is
unrelated to this project.

## The five branches

All live inside the one workflow, distinguished by node-name prefix. One POST webhook each.

| Prefix | Webhook path | Tool |
|---|---|---|
| `CA` | `/webhook/optofarm-check-availability` | `evolvo_check_availability` |
| `BOOK` | `/webhook/optofarm-book-appointment` | `evolvo_book_appointment` |
| `FIND` | `/webhook/optofarm-find-appointments` | `evolvo_find_appointments` |
| `MAN` | `/webhook/optofarm-manage-appointment` | `evolvo_manage_appointment` |
| `LOG` | `/webhook/optofarm-log-request` | `evolvo_log_request` → Google Sheet |

Plus a `DIAG` branch (read-only evolvo probe, safe to delete) and the original API-tester chain,
whose trigger is a **manual** trigger on purpose — it writes a real booking on every run, so it must
never have a live URL while the workflow is active.

Every branch follows the same shape:

```
Webhook → Validate Input → Input OK? ─no→ Error Out
                              │yes
                         Auth Cache → Need Auth? → get_auth.php → Store Token
                              │
                         …evolvo calls… → Format <result>
```

Session tokens are cached ~45 min in workflow static data and shared by all branches, so
`get_auth.php` is called rarely.

## Credentials — none are in this repo

| What | Where it lives |
|---|---|
| `X-Optofarm-Secret` (webhook auth) | n8n credential **"Optofarm Webhook Secret"**; ElevenLabs stores it as a workspace secret on each tool |
| evolvo API key | n8n credential **"Evolvo API Key"** (id `6RTMIBHJ3mUJZe7U`) |
| n8n REST API key | n8n → Settings → n8n API. Not stored here. |

Ask the user for any of these. **Do not paste them into this repository** — it is public. See the
security note in the root [`README.md`](../README.md).

## Design rule: guards are server-side, not prompt-side

The single most useful thing to know before changing anything. The deterministic procedure engine on
the ElevenLabs side skips "ask the caller" steps in roughly one run in three, regardless of wording,
so safety rules are **enforced in n8n and answered as errors that tell the agent what to do next**:

- `confirm_phone_first` — BOOK/FIND refuse until `phone_confirmed: true`, and refuse again if the
  flag flips less than 5 s after the refusal (no real read-back fits in that time).
- `offer_slot_first` — BOOK refuses until `slot_accepted: true`.
- `confirm_appointment_first` — MAN refuses until `appointment_confirmed: true`, and returns the
  exact `read_back` wording to say out loud.
- `ref_date_mismatch` — the `ref` and the `date` must point at the same record.

Each of those returns HTTP 200 with `success: false` and a `message` written *for the LLM*. Prefer
adding a guard here over adding a sentence to the prompt — prompt wording has repeatedly failed
where a server-side gate worked first time.

Identification is **phone-only**. Names are never used to match a caller to a record (ASR mangles
them); `find_appointments` returns every appointment on the number with a stable `ref`, and the
caller confirms one out loud.

## Testing it

`smoke-test.sh` runs a read-only availability check plus the guard paths. Booking tests write **real
records into the live clinic system** — always cancel what you create and verify the calendar is back
to its baseline. Use an obviously fake phone (`07000000xx`) and a `TEST …` name; the CRM test patient
is *Paciens Teszt* #1867 / phone `123123123`.

```bash
export OPTOFARM_WEBHOOK_SECRET=...   # from the n8n credential
./n8n/smoke-test.sh
```

## Reading what evolvo actually returned, without touching anything

The highest-value debugging trick here, and the one that is easy to miss. Past executions keep every
node's real input and output, so you can read raw evolvo responses without adding a probe node,
running a test booking, or changing the live workflow at all:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "https://n8n.splitagency.biz.id/api/v1/executions?workflowId=jLUnlrt9zM8VWZvp&limit=20"
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "https://n8n.splitagency.biz.id/api/v1/executions/<id>?includeData=true"
```

`data.resultData.runData["<node name>"][0].data.main[0][0].json` is that node's first output item.

This is how the 2026-09-14 findings were established — that `get_work_days.php` carries no working
hours, that `get_info.php` returns 30 calendars with eight empty `ai_*` fields, and how the scan
cache was verified to be skipping the evolvo calls it claims to skip (count the `.php` nodes in
`runData`). Always prefer this over adding a diagnostic node or writing a test record.

**Check the schema docs against it before trusting them.** `api-docs/*.json` is accurate but dated;
evolvo has added fields since. The execution data is the live truth.

## Editing the workflow

Via the n8n REST API (`X-N8N-API-KEY` header):

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  https://n8n.splitagency.biz.id/api/v1/workflows/jLUnlrt9zM8VWZvp -o live.json
# edit, then
curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  --data-binary @put.json \
  https://n8n.splitagency.biz.id/api/v1/workflows/jLUnlrt9zM8VWZvp
```

`PUT` takes only `name`, `nodes`, `connections`, `settings` — it rejects `id`/`active`/`tags`.

Gotchas worth not rediscovering:

- **Back up first** (`GET` to a file), and **re-`GET` and diff after the push** — cheap, and it has
  caught a bad write before.
- **Syntax-check Code nodes before pushing.** `node --check` over each `jsCode` catches everything
  that would otherwise fail at 3 a.m. on a real call.
- **New webhook nodes** need an explicit `webhookId` and a deactivate/activate cycle before the path
  goes live. Editing existing nodes needs neither.
- `responseMode` is `lastNode` on every branch — **the last node that executes is the HTTP
  response**. If you append nodes to a branch tail, the new final node becomes the responder and must
  emit the full response body.
- Code nodes break n8n's paired-item chain, so `$('Node').item` fails downstream — use `.first()`.
- **Refreshing the export: dump only `name`, `nodes`, `connections`, `settings`** — the same shape
  the `PUT` takes. A raw `GET /workflows/<id>` returns three things that must never land in this
  public repo: `staticData`, which holds the **live evolvo session token**; `activeVersion`, a full
  mirror of `nodes` (so a secret redacted from `nodes` alone survives there); and `shared`, which
  carries the owner's account details. Nothing else needs redacting — as of 2026-09-21 every evolvo
  call authenticates through the `Evolvo API Key` credential, and the only other `Authorization`
  headers are runtime expressions referencing a session token, not secrets.

## Files

- [`Optofarm-WIP.workflow.json`](Optofarm-WIP.workflow.json) — export of the live workflow,
  **126 nodes, current as of 2026-09-21**. Credential *references* are kept (names and ids are not
  secrets); no credential value has ever been resolved into it.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of what changed and why.
- [`slot-release-and-reschedule.md`](slot-release-and-reschedule.md) — the 2026-09-14 investigation
  and fix, with the measurements.
- [`provider-type-runbook.md`](provider-type-runbook.md) — doctor vs optometrist routing on `CA`.
- [`CA-nodes-rollback-pre-provider_type.json`](CA-nodes-rollback-pre-provider_type.json) — rollback
  bodies for the three `CA` nodes that runbook changed.
- [`smoke-test.sh`](smoke-test.sh) — read-only checks + guard paths.
