# Call latency and dead air

Measured from `conv_5301m20adnk4et6rs9h64d4j58t0` (8 Sep 2026, 202 s, 55 messages, Hungarian,
branch `n8n-evolvo-optimized` at `agtvrsn_9101m208w43ce0n9dn8npngg567k`). Metric is
`convai_ttf_audio_since_silence` — the gap from the caller finishing speaking to the first audio back.

## The numbers

**66.5 s of a 202 s call — 33% — was silence longer than 2 s.**

| Turn | Gap | What the agent then said | What it was doing |
| --- | --- | --- | --- |
| 28 | **15.1 s** | offered the earliest slot | 3 node transitions + `evolvo_check_availability` |
| 50 | **9.8 s** | confirmed the booking | 1 node transition + `evolvo_book_appointment` |
| 42 | **8.5 s** | read the phone number back | 3 node transitions, no webhook |
| 4 | 5.2 s | emergency instruction | language detection + transfer |
| 15 | 4.5 s | "a doctor needs to look at this" | procedure entry + condition |
| 20 | 3.6 s | listed the three Târgu Mureș branches | 1 node transition |
| 34 | 3.5 s | asked for the phone number | 1 node transition |
| 32 | 3.3 s | asked for the name | 1 node transition |
| 52 | 2.9 s | farewell | 1 node transition |
| 9 | 2.2 s | "do not touch the eye" | direct answer |

## Where the time actually goes

Only about **6.7 s of that 66.5 s was webhook time** — `evolvo_check_availability` took 4.72 s in
this call (its rolling average is 1.05 s) and `evolvo_book_appointment` took 2.02 s.

The other ~60 s is **workflow node traversal**. Each step transition is a separate LLM round trip
(`notify_condition_1_met`, `progress_workflow`) at 0.6–2.2 s of TTFB each, and the agent says
nothing during any of them. The 15.1 s gap is three of those plus one webhook. The 8.5 s gap at
turn 42 involves no webhook at all — it is three node transitions back to back.

## The holding line never fired

The procedure steps instruct the agent to say "Un moment, vă rog." / "Egy pillanat, kérem." /
"One moment, please." as it makes each tool call. Searching the transcript for `pillanat`,
`moment` and `Egy pill` returns **zero matches**. The line was never spoken once in the call.

Two reasons: `pre_tool_speech` was `auto` on all five `evolvo_*` tools, and `auto` decides from
recent tool latency — these webhooks average 1–2 s, so it kept deciding not to speak. And the
instruction sits inside an `ask` step, where the model is free to call the tool without speaking first.

## What was changed

All five `evolvo_*` tools now carry:

- `pre_tool_speech: "force"` — the agent always speaks before the call instead of leaving silence.
- `tool_call_sound: "typing"` with `tool_call_sound_behavior: "always"` — an audible keyboard sound
  under the lookup. "typing" reads as a receptionist looking something up; the alternatives
  (`elevator1`–`elevator4`) sound wrong on a direct clinic line.

These tools are **workspace-level** and shared with `n8n-evolvo-integration`, so both n8n branches
get the change. Main is unaffected — it uses a different tool set (`get_availability`,
`book_appointment`, `manage_appointment`, `log_request`).

## Still open

1. **Do these settings apply to nested invocations?** The `evolvo_*` webhooks run as `nested_tools`
   inside the node-transition call, not as top-level tool calls. Whether `pre_tool_speech` and
   `tool_call_sound` fire there is not documented and could not be determined from the API. A test
   call answers it.
2. **If they do not fire**, the reliable fix is a `tell` step immediately before each tool-calling
   step, holding only the holding line. `tell` compiles to a `say` node, which is deterministic and
   is rendered in the caller's language — turn 15 of this call proves `say` nodes work. Cost: one
   extra node per tool call, so slightly more total latency in exchange for filling the silence.
3. **Node traversal is the real latency driver**, not the webhooks. Fewer steps per procedure would
   cut more dead air than anything done to the tools. Worth weighing against the step granularity
   that the hang-up fix depends on.
