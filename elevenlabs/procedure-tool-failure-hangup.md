# Deterministic `tool_call` steps hang up the call on a webhook failure

Investigated 2026-09-08 after a Hungarian test call was cut off mid-conversation
(`conv_5801m2032ag6e3qbpg13b8ztx5v5`, on branch **Main**).

## What happens

A `tool_call` step inside a deterministic procedure compiles to a graph fragment with
**two** outgoing edges from the tool node:

```
<step>_tool  --{label:"Failure", type:"result", successful:false}-->  <step>_end
<step>_tool  --{type:"result", successful:true}-------------------->  <next step>
```

The `end` node is `{"type":"end", "return_when_nested": false}` and it **executes the
`end_call` system tool**. From the failed call's own trace:

```json
{"type":"nested_tools","node_id":"..._4_4_end",
 "requests":[{"type":"system","tool_name":"end_call",
              "params_as_json":"{\"reason\": \"Ending call as part of a workflow route.\"}"}]}
```

The caller is hung up on mid-sentence. This is executed by the graph, not decided by the
LLM, so **no amount of system-prompt wording can prevent it**.

`is_successful:false` on the tool node comes from the transport layer (`is_error` on the
webhook result): a non-2xx, a DNS failure, or exceeding the tool's timeout. It is *not*
triggered by an application-level error: the n8n workflows return HTTP 200 with
`{"success": false, "error": "no_match"}`, which records `is_error: false` and flows to
the LLM normally.

## What does not fix it

Verified empirically on a disposable probe agent (created and deleted 2026-09-08):

| Attempt | Result |
| --- | --- |
| `tool_error_handling_mode: passthrough` instead of `hide`/`auto` | Byte-identical graph. Both emit `Failure → end`. |
| `tool_error_handling_mode: summarized` | Same. |
| Wrapping the `tool_call` in a `sub_procedure` | The nested procedure's end node is also `return_when_nested: false`. |

The compiler emits `Failure → end` for **every** `tool_call` step unconditionally. There is
no setting that changes it.

## What does fix it

Do not use `tool_call` steps for webhooks that can fail. Name the tool inside an `ask`
step's instruction instead. That step compiles to a single `override_agent` node whose only
outgoing edge is an LLM condition — **no tool node, no end node, no `end_call`**:

```
<step>_override_agent --{type:"llm", condition:"...goal achieved AND the end user has given an appropriate response"}--> <next step>
```

The tool stays in the agent's `tool_ids`, so the model can still call it; a transport error
simply becomes a tool result the model handles and the conversation continues.

### Trade-off

Firing the tool becomes model-driven rather than graph-forced, and the step transition
becomes an LLM judgement. Mitigated in the rewritten instructions by:

- opening each converted step with `YOU MUST CALL THE <tool> TOOL IN THIS STEP. Actually
  call it - never ... without a successful call`;
- folding the following `tell` step (which read the tool result) into the same step, so the
  step ends on a natural question and the `ask` transition condition can be met;
- appending an explicit clause: `IF THE TOOL ERRORS, TIMES OUT, OR CANNOT BE REACHED: never
  mention a system, a tool, a technical problem or an error, never retry more than once, and
  NEVER end the call because of it`.

## Applied

Converted all 10 `tool_call` sites on branch `n8n-evolvo-integration`
(`agtbrch_2201m1y0ysy2fc9rmj3hc3mhszz7`):

| Procedure | Converted steps |
| --- | --- |
| `booking` (`agtprc_7801m0axd3y3ej590n280yw80rr0`) | `evolvo_check_availability`, `evolvo_book_appointment`, `evolvo_log_request` |
| `cancel_or_reschedule` (`agtprc_4901m0axdt4zev9tmgtcxy60x9da`) | `evolvo_find_appointments`, `evolvo_manage_appointment` (cancel), `evolvo_manage_appointment` (reschedule), `evolvo_check_availability`, `evolvo_book_appointment`, `evolvo_log_request` |
| `escalate_to_human` (`agtprc_4401m0axbt3rfcfvpj4grmp73wph`) | `evolvo_log_request` |

Compile of the converted procedures verifies: **0 `end` nodes, 0 `tool` nodes, 0 `Failure`
edges, 0 references to `end_call`** anywhere in the generated graph.

> The changes are stored as **procedure drafts**. The branch HEAD still pins the previous
> committed procedure versions, so the fix takes effect only once the drafts are published
> from the ElevenLabs UI. `agents_compile_procedures` is a preview and does not commit;
> `agents_create_deployment` only changes which branch serves live traffic.

## Still outstanding on Main

Branch **Main** (`agtbrch_6201kyq03wjnfct8p3w3bbt750vc`) is at 100% live traffic and its four
tools still point at `https://replace-me.invalid/webhook/optofarm/*`, which fails DNS on every
call. Every booking attempt on Main therefore hits the hang-up path above. Main's procedures
have not been converted.
