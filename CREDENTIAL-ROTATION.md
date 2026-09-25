# Credential rotation runbook

Two credentials need rotating. They are **not** the same shape of job: one has to change in two
places at the same moment, the other is a single edit in n8n. Verified against the live n8n workflow
`jLUnlrt9zM8VWZvp` (`versionId 33ffcf07-8727-4859-ac64-37d3a168db6d`) and the live agent
`agent_5301m37q64aye28t44vx4cbmtkv7` on 2026-09-25.

**No values in this file, ever.** Names of credentials and ids of secret *references* are fine;
the values they hold are not.

---

## 1. The n8n webhook secret — `X-Optofarm-Secret`

This is the urgent one. The six n8n webhooks are reachable from the open internet and this header is
their only protection, so anyone who reads the repository history can create or cancel real patient
appointments. **Two places, and they are validated against each other, so they must change together.**

### Place A — n8n
**Credentials → `Optofarm Webhook Secret`** (type: Header Auth). One record, edited once.

It is attached to all six webhook nodes, so nothing else needs touching:

| node | path |
|---|---|
| `CA Webhook` | `optofarm-check-availability` |
| `BOOK Webhook` | `optofarm-book-appointment` |
| `FIND Webhook` | `optofarm-find-appointments` |
| `MAN Webhook` | `optofarm-manage-appointment` |
| `LOG Webhook` | `optofarm-log-request` |
| `DIAG Webhook` | `optofarm-diag-v4` |

### Place B — ElevenLabs
**Workspace `optofarm@splitagency.eu` → Settings → Secrets → the secret with id
`ZciGOunVuZMmFjCLg4a4`.** Edit that secret's **value in place**.

Do **not** create a new secret and repoint the tools. All five tools carry
`"request_headers": {"X-Optofarm-Secret": {"secret_id": "ZciGOunVuZMmFjCLg4a4"}}` — a reference, not
a copy — so editing the value once covers `evolvo_check_availability`, `evolvo_book_appointment`,
`evolvo_find_appointments`, `evolvo_manage_appointment` and `evolvo_log_request`. A new secret would
turn one edit into five. (The id itself is a reference and is not a credential.)

### Also remember
`DIAG Webhook` (`optofarm-diag-v4`) shares the same n8n credential but **has no ElevenLabs tool** —
it is called by hand. Whatever calls it (Postman, the n8n developer's saved request) starts
returning 401 the moment Place A changes, and needs the new value too.

### Order, and the gap
Either order works; there is no way to avoid a short window where one side has the new value and the
other has the old, because n8n's Header Auth credential holds exactly one value. So:

1. Do it **after hours**, with both tabs already open.
2. Change one, then immediately the other. The window is seconds.
3. Keep the header **name** `X-Optofarm-Secret` identical on both sides. Only the value changes.
4. Smoke test one real availability lookup afterwards.

A call landing inside the window degrades rather than breaks: the tools' error handling tells the
agent never to mention a system or an error, to say in one sentence that a colleague will call back,
to give the branch's direct number and opening hours, and never to end the call.

---

## 2. The evolvo API key

**One place. n8n only — ElevenLabs never sees this key.**

**Credentials → `Evolvo API Key`** (type: Header Auth). Attached to the six authentication nodes:
`get_auth.php`, `CA get_auth.php`, `BOOK get_auth.php`, `FIND get_auth.php`, `MAN get_auth.php`,
`DIAG get_auth.php`.

Every other evolvo node — all the `get_info` / `get_work_days` / `post_schedule` / `get_schedule` /
`update_schedule` / `get_patient` calls — sends an `Authorization` header built from the short-lived
token that `get_auth.php` returns at runtime. **None of them needs changing.**

The new key has to be issued by **dRoot Solutions** first. Two things worth saying when asking:

- evolvo restricts access by IP as well, so confirm the whitelist still matches n8n's egress address.
- the key is partly shielded by that whitelist, which is why it is second in the queue and not first.

---

## 3. Afterwards — the history

The repository is **still public** (`LichtBach/optofarm-va`, checked 2026-09-25, 0 forks). Rotating
is what actually removes the risk; it makes the committed values worthless. Purging the history or
making the repository private is a separate decision and does **not** substitute for rotating, since
anyone may already have a clone.

What was committed, and where it still sits in history:

- the webhook secret value — `ELEVENLABS_TOOLS.md`
- the evolvo API key — both Postman collections

What is **not** a leak, so nobody needs to chase it: the `secret_id` in `README.md` and in
`elevenlabs/procedures/live-snapshot-2026-09-25/agent-config.json` is a pointer to a secret, not the
secret. It authenticates nothing on its own.
