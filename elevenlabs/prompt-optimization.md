# Prompt and context optimization — branch `n8n-evolvo-optimized`

Branch `agtbrch_8901m2086230ener47prmd238jyn`, copied from `n8n-evolvo-integration`
(`agtbrch_2201m1y0ysy2fc9rmj3hc3mhszz7`) at version seq 23. 0% live traffic. Main untouched.

## Why: where a turn's tokens actually go

Per-turn accounting from real calls (ElevenLabs `charging.llm_usage`, exact numbers):

| | System prompt | Input tokens, first LLM turn |
| --- | --- | --- |
| Main | ~5,200 est. | 24,054 |
| n8n-evolvo-integration | ~6,900 est. | 27,274 |

The system prompt is roughly a quarter of what the model reads each turn. The rest is tool
schemas, built-in tools, procedure machinery, RAG context and history.

Two facts matter more than prompt length:

- **Prompt caching almost never hits.** 18 of 20 LLM turns in `conv_7401m203tp4tf6rb826ym9t2xz47`
  report `input_cache_read: 0` with a full ~25–30k `input_cache_write`. The model reprocesses the
  whole context every turn. Observed LLM TTFB 0.6–2.2 s. Not controllable from the prompt.
- **RAG retrieval is mostly noise.** Every retrieval in that call returned
  `used_chunk_ids: []` while pulling 20 chunks.

## What was changed on the branch

1. **System prompt de-duplicated and tightened** — 29,162 → 26,769 chars (**8.2%**, ~560 est. tokens).
   Consolidated: the phone read-back gate (was stated in full 4×, now one `## The phone read-back
   gate` section), the branch-name normalization table (was 2×), the Guardrails section (9 of 13
   lines restated rules given earlier), filler/repetition rules (3×), holding lines (2×), one-question-
   per-turn (4×). All 85 distinct rules verified present afterwards by automated check.
2. **RAG `max_retrieved_rag_chunks_count` 20 → 6.**
3. **The tool-failure hang-up fix was carried across** — see `procedure-tool-failure-hangup.md`.
   Branch creation does *not* copy procedure drafts, so all three procedures were re-applied by hand
   and re-verified: compiled graph has 0 `end` nodes, 0 `tool` nodes, 0 `Failure` edges, 0 `end_call`.

Expected effect: ~7% less input per turn, on the order of 50–150 ms off first-byte latency.
Worth having; it will not by itself change how the agent feels. The cache-miss pattern is the
item with real latency upside, and it is a question for ElevenLabs.

## What was NOT changed, and why

**Tool descriptions were left alone.** The original plan was to trim the five `evolvo_*` tools
(10,163 chars of description and parameter text, ~2,540 est. tokens). Reading them changed the call:

- The descriptions carry the operational semantics the model needs at call time — the
  `phone_confirmed` / `slot_accepted` gates, the `confirm_phone_first` and `offer_slot_first`
  recovery paths, the `request_type` enum meanings, `duplicate` handling. The optimized prompt now
  *delegates* to them ("Each tool's own description tells you what its parameters mean, when each
  flag may be true, and how to read its result"). Trimming both would drop the semantics entirely,
  most visibly on the non-procedure path (the reschedule hand-back, where the base agent calls the
  tools directly with no procedure step text loaded).
- The tools are workspace-level objects shared with `n8n-evolvo-integration`. Editing in place would
  change the control arm of the A/B comparison. Isolating them would mean five duplicate tools and a
  permanent maintenance fork.

Net: a real but modest saving (~1,000 tokens, ~4% of per-turn input) against losing gate semantics
and forking the tools. Not taken.

## Resolved: the runtime executes the procedures, not the stale workflow blob

Earlier this file recorded an open question: the agent config's `workflow` graph still held the old
hang-up structure (8 `tool` nodes, 8 `end` nodes with `return_when_nested: false`) even after the
procedure drafts were committed, and it was unclear which artifact the runtime actually ran.

Call `conv_5301m20adnk4et6rs9h64d4j58t0` settles it. Every node in its trace is an
`override_agent` or `say` node from the **new** compiled procedures —
`agtprc_7801..._4_if_1_override_agent`, `_4_if_2_override_agent`, `_4_if_4_override_agent`,
`_4_if_6_override_agent`, `_4_if_12_say` — and no `_tool` or `_end` node appears anywhere. The old
graph's `_4_if_7_tool` and `_4_if_9_end` were not traversed.

So the `workflow` field in the agent config is a stale cache, not the executed artifact.
**The tool-failure hang-up fix is live on this branch.** No UI compile is needed for it to take
effect. `n8n-evolvo-integration` still holds its fix as uncommitted procedure drafts, so it does
still need a publish there.

One consequence worth knowing: the `evolvo_*` webhooks are invoked as **nested tools inside the
node-transition call**, not as top-level tool calls. In that trace,
`notify_condition_1_met` carried `{"nested_tools":{"evolvo_check_availability":{"location":"Postei"}}}`.
This is the same mechanism the old `end_call` hang-up used. It also means tool-level settings
(`pre_tool_speech`, `tool_call_sound`) may or may not apply to these invocations — a test call is
the only way to confirm.

## Security note

`evolvo_log_request` (and the other `evolvo_*` webhook tools) carry the n8n shared secret as a
**plaintext value** in `api_schema.request_headers`, rather than as a `secret_id` reference to the
workspace secret store. Anyone with read access to the tool config can read it. Worth moving to the
secret store and rotating.
