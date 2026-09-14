# n8n answers to the QA follow-ups

Answers to the two items in [`../elevenlabs/qa-followups.md`](../elevenlabs/qa-followups.md) that
asked the n8n side to check something before the prompt work could proceed — item 4 (optometrist vs
doctor) and item 5 (reading back a provider's schedule). Both were checked against **live** data on
2026-09-14, not against the documentation.

Short version: **item 4 is already built and the heuristic is confirmed — the agent can use it
today. Item 5 is impossible with the current evolvo API and has been handed to dRoot Solutions.**

---

## Item 4 — optometrist vs doctor: done, and the heuristic holds

### The prefix is reliable

Checked against a live `get_info.php` response (n8n execution 1338):

| | |
|---|---|
| Calendars | **30** |
| `Dr. …` | 21 |
| `Optometrist …` | 9 |
| Matching neither | **0** |

The prefix is present and consistently formatted on every calendar, so the heuristic is safe to
depend on. One correction to the framing in the QA file, which described the rule as *providers
without "dr." are optometrists*: the real convention is stronger — every non-doctor is **explicitly
prefixed `Optometrist`**. Nothing is identified by absence.

Two things worth knowing before treating this as settled forever:

- **The list is not static.** It was 16 calendars on 2026-09-11 and is 30 today — the clinic added
  Dr. Istratuc Dorina, Dr. Ormenisan Delia Maria, Dr. Petrea Alexandra and more optometrist
  workstations. Re-verify after clinic changes rather than assuming.
- **Classification is by prefix**, so a future calendar with neither prefix would be classified as a
  doctor. That is the safe direction to fail, but it is a silent failure. The durable fix is
  evolvo's own `ai_doctor_title` field — see the discovery below.

### `check_availability` already filters — the agent must not

This landed on 2026-09-11 and answers the QA file's second question directly. Send:

```json
{ "location": "Reghin", "provider_type": "optometrist" }
```

- `provider_type` accepts `doctor` or `optometrist`. Anything else is **ignored** (treated as
  unfiltered) rather than rejected, so an unexpected value can never fail a call.
- Every result, plus `earliest` and `requested_date_slots`, carries `provider_type`.
- `provider_type_filter` is echoed **only when the filter actually ran**. Naming a specific doctor
  bypasses the filter, and then no echo appears — so the agent must not treat a missing echo as the
  filter having failed.
- A branch that has no provider of the requested kind returns the error `no_provider_of_type`.

Re-tested against the expanded 30-calendar set on 2026-09-14:

| Request | Result |
|---|---|
| Reghin + optometrist | Dan Laura, Jeremias Zoltan |
| Trandafirilor + optometrist | Bodi Ildiko, Ifj Jeremias Laszlo |
| Fortuna + optometrist | `no_provider_of_type` — Fortuna is doctor-only |
| Fortuna + doctor | Baricz Anna, Ormenisan Delia Maria, Petrea Alexandra |

Use **Fortuna** when you need a branch that exercises `no_provider_of_type`. Reghin does have
optometrists, contrary to a guess in an older runbook.

### What is still blocked

Only the mapping from *reason for the visit* → provider type, which is Zsófi's list. The plumbing is
finished and waiting for it. When the list arrives, consider whether it belongs in the prompt at all
or in evolvo's `ai_description` field per calendar, where the clinic could maintain it themselves.

---

## Item 5 — reading back a provider's schedule: not possible today

The QA file asked to check the raw response before assuming this was a prompt change. It was
checked, and **the data is not there.** Both endpoints, from live responses:

| Endpoint | Every field it returns |
|---|---|
| `get_work_days.php` | `Records[]` of `{wday, free_timespace[{slot, slotid}]}` |
| `get_info.php` | `name`, `doctor_name`, `workstation`, `interventiontypes`, `problem_description`, `calendarid`, `slot_duration`, and eight `ai_*` fields |

There is **no shift start, no shift end, no working hours** anywhere in the thirdpartyai API. The
concern raised in the QA file is exactly right: a provider whose last free slot is 15:00 may well
work until 21:00, so free slots cannot answer "until what time is she there today?" — and
`# Guardrails` ("never invent an availability") correctly forbids approximating it.

**So this is not an ElevenLabs change.** It has been scoped and handed to dRoot Solutions as
question 10 in [`../api-docs/QUESTIONS_FOR_IMREH.md`](../api-docs/QUESTIONS_FOR_IMREH.md). If they
add working hours to `get_info.php` or `get_work_days.php`, exposing them through
`check_availability` is a small change on our side and the answer becomes a normal tool-sourced fact.

Until then the honest answer is that the agent can see free appointment times but not working hours,
followed by the earliest free slot or a callback offer.

---

## Discovery: evolvo has AI fields that nobody has filled in

`get_info.php` returns eight `ai_*` fields per calendar, and **all eight are empty on all 30
calendars**:

`ai_doctor_title` · `ai_description` · `ai_default_language` · `ai_supported_languages` ·
`ai_emergency_contacts` · `ai_public_names_hu` · `ai_public_names_ro` · `ai_public_names_en`

These look purpose-built for exactly this integration, and if the clinic can populate them from the
evolvo admin panel they would replace several things we currently hard-code or guess:

| Field | What it would solve |
|---|---|
| `ai_doctor_title` | provider type as **data**, retiring the name-prefix heuristic in item 4 |
| `ai_description` | Zsófi's visit-reason → provider routing, maintained by the clinic rather than frozen into the prompt |
| `ai_public_names_ro/hu/en` | the recurring ASR problem with provider names — a per-language spoken form, instead of pronunciation dictionaries |
| `ai_emergency_contacts` | the transfer-target question in QA item 3, per calendar instead of one hard-coded number |
| `ai_supported_languages` / `ai_default_language` | which provider can be offered to a Hungarian-speaking caller |

Whether the clinic can actually edit these, and what shape the values should take, is question 11
for dRoot Solutions. Worth asking before building anything that duplicates them.
