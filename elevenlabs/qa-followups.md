# QA follow-ups — client round, 11 Sep 2026

Five items from the client's QA session (multiple people testing the demo line) plus whatever
else is in the WhatsApp group. Ordered by the weight the client put on them. Item 1 is the one
they called their biggest problem.

Read `call-latency-and-dead-air.md`, `prompt-optimization.md` and
`deployment-blocked-by-attached-tests.md` before starting — they already answer several of the
questions below with measured numbers.

## Ground rules for this round

- **Main is 100% live** (`agtbrch_6201kyq03wjnfct8p3w3bbt750vc`, seq 19,
  agent `agent_3101kyq03vpxfpb9vsskgfh2f0bd`). Do the work on a branch, demo it, merge when the
  client signs off. Do not experiment on Main.
- **Never repopulate `platform_settings.testing.attached_tests`.** It must stay `[]`. With the nine
  tests attached, the ElevenLabs UI cannot save or publish the agent at all — that is the failure
  documented in `deployment-blocked-by-attached-tests.md`.
- **Do not run the test suite.** Most of the nine tests have `tool_mock_config.mocking_strategy:
  "none"`, so every run hits the live n8n webhooks and creates real Evolvo bookings under
  "Paciens Teszt". Add mocks first if tests are needed.
- **Patch narrowly.** `agents_update` deep-merges, so send only the subtree you are changing. Do not
  read the config and echo it back — the read API returns fields the write schema rejects.
- **The five `evolvo_*` tools are workspace-level**, shared by every branch. Editing one changes all
  branches at once.

---

## 1. Latency — "it takes a very long time to answer" (highest priority)

This is already measured. From `conv_5301m20adnk4et6rs9h64d4j58t0`: **66.5 s of a 202 s call, 33%,
was silence longer than 2 s.** Of that, only ~6.7 s was webhook time. The other ~60 s is **workflow
node traversal** — each procedure step transition is its own LLM round trip at 0.6–2.2 s, and the
agent says nothing during any of them. The worst gap in that call (8.5 s) involved no webhook at all.

So do not start by optimising the prompt or the webhooks. Start with node count.

Work through these in order:

1. **Cut procedure steps.** Post-merge Main compiles to 34 nodes, 29 of them `override_agent`.
   Every one is a round trip. Go through all three procedures
   (`agtprc_4401m0axbt3rfcfvpj4grmp73wph`, `agtprc_7801m0axd3y3ej590n280yw80rr0`,
   `agtprc_4901m0axdt4zev9tmgtcxy60x9da`) and merge steps that do not need to be separate.
   Weigh each merge against the step granularity the tool-failure hang-up fix depends on — see
   `procedure-tool-failure-hangup.md`. The compiled graph must keep **0 `end` nodes, 0 `tool` nodes,
   0 `Failure` edges, 0 `end_call`**; verify after every change.
2. **Confirm whether the dead-air masking actually fires.** All five `evolvo_*` tools were set to
   `pre_tool_speech: "force"` and `tool_call_sound: "typing"` / `tool_call_sound_behavior: "always"`.
   But these webhooks run as **nested tools inside the node-transition call**, not as top-level tool
   calls, and it is undocumented whether tool-level settings apply there. In the measured call the
   holding line ("Egy pillanat, kérem.") was spoken **zero times**. Make one test call and listen.
   If nothing fires, add a `tell` step holding only the holding line immediately before each
   tool-calling step — `tell` compiles to a deterministic `say` node, which demonstrably works.
3. **Note a stale doc line.** `call-latency-and-dead-air.md` says "Main is unaffected — it uses a
   different tool set". That was true before the merge. Main now runs the five `evolvo_*` tools, so
   it does carry those settings. Correct that line.
4. **Prompt caching.** 18 of 20 LLM turns reported `input_cache_read: 0` with a full ~25–30k
   `input_cache_write` — the model reprocesses the entire context every turn. Not fixable from our
   side; it is a question for ElevenLabs support. Raise it with the agent id and a conversation id.

Report before/after as `convai_ttf_audio_since_silence` per turn on a comparable test call, not as
an impression.

### Measured: what actually drives TTFB (11 Sep)

Regression over all 24 LLM turns of `conv_5301m20adnk4et6rs9h64d4j58t0`, input tokens vs
`convai_llm_service_ttfb`:

```
n=24   tokens 12,935-18,711 (mean 17,174)   TTFB 0.50-2.20 s (mean 1.15 s)
correlation r = 0.072      r^2 = 0.005
slope = 22 ms per 1,000 tokens
```

**Context length explains 0.5% of the variance in response time.** Cutting 1,000 tokens buys
~22 ms per turn, ~0.5 s per call. Do not spend time shortening text to chase latency.

Procedure text specifically: only the *active step's* instruction is injected, never the whole
procedure. Two turns inside the same procedure, `_4_if_1` (ask name, ~600-char instruction) at
17,854 tokens vs `_4_if_4` (book_appointment, ~3,000-char instruction) at 18,615 — a 761-token
difference tracking those two steps' own text. And `procedure_hub` *after* the procedure exits
(18,134) is as high as inside it, so the climb across the call is conversation history, not
procedure text arriving. Consequences:

| What | Effect on latency |
| --- | --- |
| Total procedure length | **Zero** — never loaded at once |
| One step's instruction length | ~600 tokens ≈ **13 ms** |
| Number of steps | **~2.1 s each** |

Step *count* beats step *length* by roughly 160×. Fewer steps, not shorter steps.

Node *type* matters more than token count. The two cheapest turns in the call were
`_4_if_12_say` (14,228 tokens, **0.50 s**) and `_1_elif1_1`, a branch condition (12,935 tokens,
**0.55 s**) — both under half the 1.15 s mean, far more than their lower token count predicts.
`say` and condition nodes are cheap; `override_agent` nodes are expensive.

Prompt caching is a minor item, not the headline. 23 of 24 turns had `input_cache_read: 0`; the one
cache-hit turn ran 1.03 s against a 1.16 s mean for the misses. About 130 ms, on n=1 — consistent
with the slope, since 17 k tokens only cost ~370 ms of prefill. Still worth a support ticket
because 23/24 missing is anomalous, but do not sell it to the client as the fix.

## 2. Repetition

Two shapes, per the client: the caller says something and the agent reads it straight back, and the
agent says the same thing twice in a row.

The prompt already forbids both, in strong terms — `# Voice and response rules` has "NEVER say the
same sentence twice in one call, and never follow one instruction to the caller with a second
sentence that repeats it in other words", and `# Call memory` has "Never ask them to repeat
information they already gave". **Adding more prompt rules will not fix this.** Four separate
restatements of the repetition rule were already consolidated into one during the last optimisation
round precisely because duplication was not helping.

Look at the structure instead:

- Pull a recent conversation and find the actual repeated turns. Check whether each repetition lands
  on a node transition — an `override_agent` node injecting step text that restates what the
  previous node already said is the most likely mechanism, and it is invisible from the prompt.
- Check for overlap between procedure step text and the system prompt sections covering the same
  ground (the phone read-back gate, the holding lines, the one-question-per-turn rule).
- Fixing item 1 by merging steps should reduce this as a side effect. Do item 1 first and re-measure
  before touching anything here.

## 3. Offer a human transfer after 4–5 unproductive turns

Client's wording: after four or five turns, if the AI cannot solve it, it should **offer** to put the
caller through to a real person. Explicitly **not** an automatic transfer — offer first, transfer
only on a yes.

**This contradicts the current prompt and cannot be done by appending a rule.** `# Escalation flow`
opens with: "You can transfer a call to a colleague only in a medical emergency (see Step 0). For
everything else you cannot transfer" — and the whole escalation path routes to `evolvo_log_request`
(a callback request) rather than a live transfer. That opening line has to be rewritten, or the new
rule and the old one will fight and the model will follow whichever it read last.

What the change needs:

- Rewrite the `# Escalation flow` opening so a non-emergency transfer is permitted under a defined
  condition, keeping the callback-request path as the fallback.
- Define "unproductive turn" concretely enough to count — e.g. consecutive turns where the agent
  answered "I don't have that information", or the caller repeated or rephrased the same request.
  Do not phrase it as "after 4–5 prompts"; the model cannot count conversation turns reliably.
  A better framing is a condition on state ("if you have said you do not have the information twice,
  or the caller has restated the same request twice").
- Keep `# When to offer an appointment or a transfer` consistent: it currently says "Once the caller
  declines an appointment or a transfer, do not offer it again for the rest of the call." That rule
  should still hold after this change — one offer, not a loop.
- Decide the transfer target. `transfer_to_number` is configured for the emergency path; confirm
  which number a non-emergency transfer should reach, and what happens outside opening hours
  (it should fall back to `evolvo_log_request`, not ring an empty branch). **Ask the client for the
  number and the hours before shipping this.**
- The `# Unknown-information protocol` already offers a colleague once per call, as a *callback*.
  Reconcile the two so the caller is not offered both a transfer and a callback for the same gap.

## 4. Optometrist vs doctor

In Evolvo, providers with "dr." in the name are doctors; providers without it are optometrists.
Some cases should be booked with an optometrist (glasses and similar), not a doctor.

> **Answered by the n8n side, 2026-09-14** — see
> [`../n8n/qa-followups-answers.md`](../n8n/qa-followups-answers.md). Both checks below are done:
> the prefix heuristic is **verified against live data** (30 calendars: 21 `Dr. …`, 9
> `Optometrist …`, 0 unmatched — and note every non-doctor is *explicitly* prefixed `Optometrist`,
> nothing is identified by absence), and **`evolvo_check_availability` already filters** — send
> `provider_type: "doctor" | "optometrist"` and the agent does **not** filter the list itself. A
> branch with no such provider returns `no_provider_of_type`; an unrecognised value is ignored
> rather than rejected; `provider_type_filter` is echoed only when the filter actually ran, so a
> missing echo is not a failure. Only Zsófi's visit-reason → provider-type mapping is still
> outstanding.

**Partly blocked:** Zsófi is sending a list of which cases go to an optometrist and which to a
doctor. The routing rules cannot be written before that list arrives. What can be done now:

- Verify the "dr." prefix heuristic against real data — call `evolvo_check_availability` and look at
  the provider names it actually returns. Confirm the prefix is present and consistently formatted
  before anything depends on parsing it. If it is not reliable, the distinction needs to come from
  an n8n-side field instead, which is a backend change.
- Check whether `evolvo_check_availability` can filter by provider type, or whether the agent has to
  filter the returned list itself.
- Note the conflict to resolve when the list lands: `# Unknown-information protocol` lists
  "Doctors' specialisations" as something the agent must treat as unknown on sight. Optometrist-vs-
  doctor routing is adjacent to that, and the guardrail will suppress the new behaviour unless the
  line is narrowed.
- The appointment flow asks "Whether they want a particular doctor or the earliest available
  appointment." Once the routing list exists, provider type has to be resolved from the *reason for
  the visit* before availability is checked, which changes the order of the collection steps in
  `# Appointment flow`.

Leave a clearly marked placeholder section in the prompt rather than guessing the rules.

## 5. Reading back a provider's schedule

Client's example: "until what time is Baric Anna there today?" → "Dr. Baric Anna's schedule ends at
nine."

> **Answered by the n8n side, 2026-09-14 — this is NOT an ElevenLabs change.** The raw responses
> were checked against live data: `get_work_days.php` returns only `{wday, free_timespace[{slot,
> slotid}]}` and `get_info.php` carries no hours either, so **a shift end is not derivable from the
> API at all**. The suspicion below is exactly right, and slot data must not be used to approximate
> it. Scoped and handed to dRoot Solutions as question 10 in
> [`../api-docs/QUESTIONS_FOR_IMREH.md`](../api-docs/QUESTIONS_FOR_IMREH.md); if they expose working
> hours, surfacing them through `check_availability` is a small n8n change. Until then the honest
> answer is that the agent sees free appointment times, not working hours. Details:
> [`../n8n/qa-followups-answers.md`](../n8n/qa-followups-answers.md).

**Check feasibility first — this may not be an ElevenLabs change at all.** `evolvo_check_availability`
returns *free slots*, which is not the same as a shift end. If a provider's last free slot is 15:00
but they work until 21:00, answering from free slots gives the wrong answer. Call the webhook and
inspect the raw response:

- If the response already carries working hours or a shift end per provider, this is a prompt and
  tool-description change only.
- If it does not, it needs an n8n/Evolvo change to expose the schedule — a new endpoint or an
  extended response. That is outside this repo; scope it and hand it over rather than approximating
  from slot data.

Either way, two prompt sections block the new answer and must be updated together with it:

- `# Unknown-information protocol` — "Which doctors work at which branch, except as returned by
  `evolvo_check_availability`" and "Waiting times" both sit next to this.
- `# Guardrails` — "Never invent a price, a waiting time, a doctor's name, or an availability.
  Availability and doctors' names come only from the scheduling tools."

The guardrail is correct and should stay; the schedule answer must be sourced from a tool response,
never inferred.

---

## Also

The client said more QA findings were posted to the WhatsApp group. Ask for them before starting —
some may overlap with the above and change the priority order.
