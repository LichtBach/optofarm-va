# Provider roster extraction — prompt for the n8n agent

A read-only diagnostic workflow that dumps every calendar in evolvo so the names can be corrected
by hand once, and the corrected table can then feed both the ElevenLabs pronunciation dictionaries
and (if wanted later) spoken-name fields in the tool responses.

Paste the block below to the n8n agent. Everything after it is context for you, not for the agent.

---

## The prompt

> Build a new, read-only diagnostic branch in the Optofarm workflow called **ROSTER**. It exists to
> dump the full provider list from evolvo once, so the names can be audited and corrected by a human.
> It must never write anything and must never be called by the ElevenLabs agent.
>
> **Trigger.** A new webhook, `optofarm-roster`, POST, protected by the same `X-Optofarm-Secret`
> header as the existing webhooks. No body parameters except an optional `format` (`json` by default,
> `csv` if asked).
>
> **Fetch.** One call to evolvo `get_info.php`, exactly as the `CA` branch already does — reuse the
> same credential and the same node settings. One request, no retries, no loops.
>
> **Transform.** For every entry in `Calendars[]`, emit one row with these fields, in this order:
>
> | field | source |
> |---|---|
> | `calendarid` | `c.calendarid` — the stable key, never the name |
> | `name_raw` | `c.name` exactly as evolvo returns it, untouched, whitespace preserved |
> | `doctor` | `splitName(c.name).doctor` — reuse the existing helper from `CA Match Calendars`, do not rewrite it |
> | `service` | `splitName(c.name).service`, empty string when there is no suffix |
> | `provider_type` | derived exactly as `CA Match Calendars` derives it today (doctor / optometrist / vision_therapy) |
> | `location` | `c.workstation` |
> | `slot_duration_minutes` | as the CA branch reads it |
> | `problem_description` | `c.problem_description` verbatim, newlines replaced with ` | ` |
>
> Then append four **empty** columns for a human to fill in: `name_display`, `spoken_ro`,
> `spoken_hu`, `notes`. Emit them empty — do not guess at them, do not transliterate, do not add
> diacritics. Filling them is a human job and a wrong guess there is worse than a blank.
>
> **Output.** `{ "success": true, "count": <n>, "fetched_at": "<ISO timestamp>", "rows": [ ... ] }`,
> sorted by `location` then `doctor`. With `format: "csv"`, return the same rows as CSV with a header
> line, UTF-8, comma-separated, every field quoted.
>
> **Constraints.** Read-only: no `post_schedule.php`, no writes of any kind. Do not touch the CA,
> BOOK, FIND, MAN or LOG branches — add nodes alongside them, share only the existing `splitName` and
> provider-type logic by copying it, so that changing ROSTER can never change booking behaviour. Do
> not add this webhook to any ElevenLabs tool.
>
> When you are done, run it once and paste back the row count and the first three rows.

---

## Why it is shaped this way

**Keyed on `calendarid`, not the name.** The whole point of the exercise is that the names are going
to change — `Anca` becomes `Anica`, `Szekely` gets its accents back. A table keyed on the name string
breaks the moment the correction lands. `calendarid` survives a rename.

**The four columns are left empty on purpose.** An LLM transliterating Hungarian names into Romanian
orthography unsupervised is exactly the failure this work exists to fix. The machine's job is to
extract; the judgement is yours.

**`problem_description` is included** because PR #5 noted it is populated on 16 of 30 calendars with a
real service list (`Prescriere ochelari`, `Tensiune oculara`, `Retinofotografie`, `Discromatie`) and
is surfaced by no tool today. Since we are dumping the calendars anyway, it costs nothing to see it,
and it may be better visit-reason routing data than the name-prefix heuristics in use now.

## What the filled table is for

One table, two consumers — which is why it is worth doing properly once:

| column | feeds |
|---|---|
| `name_display` | the corrected spelling to put back into evolvo's calendar names |
| `spoken_ro` | Romanian-voice pronunciation: the `ro-voice.pls` dictionary, or `doctor_spoken_ro` in tool responses |
| `spoken_hu` | Hungarian-voice pronunciation: the `hu-voice.pls` dictionary, or `doctor_spoken_hu` |

**The dictionary must be built last.** A pronunciation alias keys on the grapheme the TTS actually
receives, which is whatever `doctor` holds in the tool response. Correct the evolvo names first, let
the corrected form flow through, then key the dictionary on that. Building it against today's
stripped spellings means every alias silently stops firing the day the names are fixed — and nothing
visibly breaks, the phonetics just quietly revert.

**Two rules for whoever fills in the spoken columns:**

1. **The spoken form is output only.** It is never sent back to a tool, never matched on, never
   written to a booking. `CA Match Calendars` keeps matching on the raw name with its existing fuzzy
   logic — that is what recovered `Kilován` → `Dr. Ilovan Anca` on a live call, and it must not be
   disturbed.
2. **Keep `Ifj.` in the spoken form, out of the sent form.** The system prompt already says to say
   "Ifj." aloud, because it is what distinguishes father from son, but never to send it to a tool,
   because it arrives mangled by ASR and fails the match.

## Smoke test once the names are in

Per direction, one short call each, with someone who speaks both languages listening:

- **Romanian voice, Hungarian names** — ask for `Székely`, `Baricz`, `Jeremiás László`, `Elekes`.
  Listen for `sz` read as two letters, `cz` mangled, `j` as /ʒ/, final `s` as /s/ instead of /ʃ/.
- **Hungarian voice, Romanian names** — ask for `Ilovan Anica`, `Popa Camelia`, `Istratuc Dorina`.
  Listen for `c` read as /ts/ — "Anitsa", "Tsamelia" — and `s` as /ʃ/.
- **Switch mid-call** and ask for the same doctor in both languages. The name should sound right in
  each, and the switch must not trip `language_detection` on the name alone.

Then the same three with the dictionaries attached, and compare.

---

## Outcome, 2026-09-21 — the dump was taken WITHOUT building the branch

The roster is in [`provider-roster-2026-09-21.json`](provider-roster-2026-09-21.json) and
[`.csv`](provider-roster-2026-09-21.csv): 30 calendars, 16 unique providers, 8 locations.

It did not need a new workflow branch. The live `CA` branch calls `get_info.php` on every
availability check, and the n8n REST API returns each node's real input/output from past runs, so the
full `Calendars[]` payload was read straight out of execution `1464` (2026-09-21 12:25, a genuine
caller-driven run):

```
GET /api/v1/executions?workflowId=jLUnlrt9zM8VWZvp&limit=15&status=success
GET /api/v1/executions/1464?includeData=true   ->  runData['CA get_info.php']
```

`splitName` / `providerKind` were then applied off the **live** node source, not the export in this
repo — the committed `Optofarm-WIP.workflow.json` is stale and still has the pre-specialty version of
`CA Match Calendars` (no `splitName`, no `vision_therapy`). Refresh it before trusting it again.

Zero nodes added, zero writes, nothing deactivated. The ROSTER branch above is still worth building
if this needs to be repeatable on demand — but it was not worth the risk on a live 122-node workflow
for a one-off audit.

### Correction: `calendarid` CANNOT be the key

The prompt above says to key the table on `calendarid` because names are about to change. That is
wrong, and the roster is keyed on `location` + `name_raw` instead.

`calendarid` is not an id. It is an ~800-character encrypted envelope (observed lengths 792–920) that
is **regenerated on every call**. Two `get_info.php` responses 35 seconds apart, execution `1463` vs
`1464`, returned the same 30 calendars — identical name and workstation on all 30 — and **0 of 30
matching `calendarid` values**. It is bound to the session token, not to the calendar.

So there is no stable key anywhere in the thirdpartyai API. Consequences:

- The roster is a **point-in-time artifact**, valid for the spellings as of `fetched_at`. After the
  names are corrected in evolvo, re-dump and re-match on `location` + fuzzy name. With 16 providers
  across 8 named branches that is a five-minute job, not a reason to build key infrastructure.
- Never persist a `calendarid` anywhere. Anything holding one for more than the length of a single
  request is already broken. (The `CA` branch is fine — it passes the value straight from
  `get_info.php` into `get_work_days.php` inside one execution.)
- The real fix for a stable, clinic-maintained identity is `ai_public_names_hu/ro/en`, still empty on
  all 30 calendars — open question 11 with Imreh.
