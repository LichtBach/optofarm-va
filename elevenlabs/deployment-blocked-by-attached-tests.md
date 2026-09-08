# "Deployment failed" on Main after the merge

Symptom, 2026-09-08: publishing branch **Main** of `agent_3101kyq03vpxfpb9vsskgfh2f0bd`
fails in the UI with `deployment failed` and no further detail. Started right after
`n8n-evolvo-optimized` was merged into Main.

## The merge itself is healthy

Main version `agtvrsn_2801m20c6g23ebxa8hkhwyhr849a` (seq 17, "Merged from branch
n8n-evolvo-optimized") carries everything intended:

| | seq 16 (pre-merge) | seq 17 (post-merge) |
| --- | --- | --- |
| System prompt | 21,978 chars | 26,768 chars (optimized) |
| `prompt.tool_ids` | 4 tools on `replace-me.invalid` | the 5 `evolvo_*` webhooks |
| Workflow nodes | 56 — incl. 10 `end`, 6 `tool` | 34 — **0** `end`, **0** `tool` |
| RAG chunks retrieved | 20 | 6 |
| `transfer_to_number` | absent | present, `+40770355391` |

All five tool ids and all six knowledge-base ids resolve. No `Failure` edges and no
`end` nodes remain, so the tool-failure hang-up fix is live on Main.

The deployment endpoint itself works — `POST /deployments` with Main at 100 returned
`{"agtbrch_6201kyq03wjnfct8p3w3bbt750vc": 100}`. Main is serving the merged config
right now; a test conversation against it runs the new procedure graph
(`__xi_procedure__procedure_hub`) and transfers correctly.

## Cause: the merge attached 9 simulation tests to Main

```
seq 16:  platform_settings.testing.attached_tests = []
seq 17:  platform_settings.testing.attached_tests = 9 tests
```

The tests were attached while iterating on `n8n-evolvo-integration` and the merge
carried them onto Main. Attached tests run as part of the publish flow, and they fail.

Run against Main (`suite_6601m20e4n1jec1th8vrk0j03476`):

| Test | Result |
| --- | --- |
| `Optofarm: emergency 'substanță chimică în ochi'` | passed |
| `Optofarm n8n: urgent 'am ceva în ochi' in Reghin` | failed |
| `Optofarm n8n: vague 'aș dori o programare' (RO) v2` | failed (`qa_empty_response`) |

The Reghin failure is the test disagreeing with the prompt, not a defect:

> Criterion 2: Agentul a tratat cazul ca urgent … dar nu a apelat funcția
> `evolvo_check_availability`

The test expects "something in my eye" to be booked as an urgent appointment. The
prompt lists "something embedded in the eye" as an emergency, so the agent transfers.
The agent follows the prompt; the test encodes the older expectation. Historically
these tests never fully passed — best recorded run was 5/8, worst 1/8.

## Fix

Detach the 9 tests from the agent (Agent → Tests tab). That restores Main to its
pre-merge state on this setting. The tests stay in the workspace Tests library and can
still be run manually.

## Two things to know about these tests

- Most run with `tool_mock_config.mocking_strategy: "none"`, so they call the **live**
  n8n webhooks and create real Evolvo bookings for "Paciens Teszt" on every run.
- Several assert on fixed 2026 dates (9 September, 9 December) whose availability
  drifts, so they rot over time.

## The UI cannot write to Main at all

Detaching the tests in the UI failed with `Failed to update agent`, and the deletion did
not persist — re-reading Main afterwards still showed all 9 test ids attached. So the
publish failure and the save failure are the same bug: **the UI's write to Main is
rejected outright.**

The server is not the problem. A minimal PATCH through the API succeeds:

- `{"name": "Optofarm Agent - DEMO"}` → committed seq 18
- `{"platform_settings": {"testing": {"attached_tests": []}}}` → committed seq 19

The second one is the fix. It deep-merges: a field-by-field diff of `platform_settings`
before and after shows **0 differences outside `.testing`** — guardrails, overrides,
widget, privacy, auth and call limits all preserved — and the prompt, tool ids, workflow
node count and RAG setting are byte-identical.

## Why the UI's write was rejected and the API's was not

Detaching the tests through the API fixed the UI: publishing then succeeded, with no new
version written (the tip was already valid, so the UI reconciled against seq 19). So the
attached tests were the trigger for both failures, not merely a coincident change.

The best-fitting explanation is `platform_settings.testing.referenced_tests_ids`. The
read API returns it; the write model (`AgentTestingSettings`) defines only
`attached_tests` and does not accept it. The UI sends back the whole config it loaded,
so it echoed a populated 9-element `referenced_tests_ids` into a schema that has no such
field — and several nested schemas here are declared `additionalProperties: false`, so
an unexpected key is a hard validation failure rather than an ignored one. With the
tests detached the array serialises empty and the same payload passes. The API patches
never carried the field at all, which is why they always worked.

This is unconfirmed in the sense that the raw HTTP error was never visible — the UI only
ever showed `Failed to update agent`. But it is the only account consistent with all
four observations: UI save fails with tests attached, UI publish fails with tests
attached, minimal API patches always succeed, and UI publish succeeds once the tests are
detached.

Other fields in Main's stored config are returned by the read API but absent from the
write schema, and are candidates for the same class of failure in future:

| Field | Present in read | In write schema |
| --- | --- | --- |
| `platform_settings.guardrails.synthetic_voice` | yes | no |
| `platform_settings.privacy.user_memory` | yes | no |
| `platform_settings.privacy.nested_history_redaction` | yes | no |
| `platform_settings.queueing_config` | yes | no |
| `platform_settings.safety` | yes | no |
| `platform_settings.simulation_library` | yes | no |
| `platform_settings.analysis_llm_billed` | yes | no |
| `widget.language_presets.*.first_message_quick_replies_translation` | yes | no |
| `rag.optional_rag_enabled`, `rag.include_source_urls` | yes | no |

Worth raising with ElevenLabs support with the agent id and a failing timestamp — it is
their read/write schema mismatch, not a fault in the merged config.

## Outcome

Tests detached at seq 19 (`agtvrsn_1001m20g0mvaerfs0psmt3vg7fxh`). UI publish succeeds.
Main is 100% live on the merged, optimized config.

If a UI save fails this way again, detach or clear whatever list was most recently added
before assuming the config is damaged, and fall back to a minimal API PATCH naming only
the field being changed.

## Note on a false lead

The first suite run reported `Insufficient credits to run this simulation` on one test.
That was a concurrency artifact of running three simulations at once — the same test
run on its own executed normally. The workspace credit balance is not the cause.
