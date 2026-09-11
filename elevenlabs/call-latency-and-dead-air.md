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
get the change. *(Stale as of 11 Sep: Main was unaffected at the time because it used a different
tool set. After the merge Main runs the five `evolvo_*` tools and does carry these settings.)*

## Resolved 11 Sep: the holding line fires, and node transitions are what is left

`pre_tool_speech: "force"` **does apply to nested tool invocations.** Open question 1 below is
answered. In `conv_2401m27fwpb5fx9ahtgsfdcz8xpr` (live Main, `agtvrsn_7301m239c0jtfm5bnwrydrv11mff`,
real inbound Twilio call), the line is spoken exactly once immediately before each webhook:

```
[10] agent t=28s   "Egy pillanat, kérem."
[11] agent t=28s   -> evolvo_check_availability
[31] agent t=120s  "Egy pillanat, kérem, lefoglalom az időpontot."
[32] agent t=121s  -> evolvo_book_appointment
```

Two matches in the transcript, zero elsewhere. So **open question 2 is moot — do not add `tell`
steps holding the line.** A `say` node on top of a working `force` would speak the line twice and
produce exactly the repetition the client reported.

What the fix bought, and what it did not:

| | Pre-fix `conv_5301...` | Live Main `conv_2401...` |
| --- | --- | --- |
| Call length | 202 s | 150 s |
| Silence > 2 s | 66.5 s (**33%**) | 53.6 s (**36%**) |
| Worst single gap | **15.1 s** | **7.5 s** |

The monster gaps are gone — worst halved — but the proportion of dead air did not improve. The
profile changed shape: many 4–5 s gaps instead of a few very long ones. The largest remaining ones
are the collection steps, which is open question 3 below:

```
t= 63s  4.9s  "Értem. Kérem, mondja meg a teljes nevét."          <- name step
t=108s  4.9s  phone read-back
t= 96s  4.7s  "kérem, diktálja be újra a telefonszámát"           <- phone re-ask
t= 71s  3.9s  "Kérem, diktálja be a telefonszámát számjegyenként" <- phone step
```

Name + phone + read-back alone are 13.7 s. Merging those three `ask` steps into one leaves the
~2.2 s per-turn floor but removes the transitions between them — roughly **6–7 s back**. That, plus
dropping the redundant emergency `branch`, is now the whole remaining lever on this path.

## Still open


1. ~~Do these settings apply to nested invocations?~~ **Answered 11 Sep: yes.** See above.
2. ~~Add a `tell` step per tool call if they do not fire.~~ **Moot, and now harmful** — it would
   double the holding line. See above.
3. **Node traversal is the real latency driver**, not the webhooks. Fewer steps per procedure would
   cut more dead air than anything done to the tools. Worth weighing against the step granularity
   that the hang-up fix depends on.
