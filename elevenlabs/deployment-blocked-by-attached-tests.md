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

## Note on a false lead

The first suite run reported `Insufficient credits to run this simulation` on one test.
That was a concurrency artifact of running three simulations at once — the same test
run on its own executed normally. The workspace credit balance is not the cause.
