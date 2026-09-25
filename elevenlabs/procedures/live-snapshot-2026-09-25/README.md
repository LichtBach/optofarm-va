# Live snapshot, 2026-09-25 — taken before the account migration

Pulled from `agent_3101kyq03vpxfpb9vsskgfh2f0bd` ("Optofarm Agent - DEMO", branch Main) in the
`zoli@splitagency.eu` ElevenLabs workspace, immediately before repointing the connector to the
Optofarm account.

Why it exists: the three live procedures were **not mirrored anywhere**. The files in
[`../proposals/`](../proposals/) are 15 September snapshots of a proposed refactor, ten days stale by
the time of the migration, and the prompt, knowledge base and tools were mirrored but the procedures
were not. Losing read access to that workspace would have lost them.

| File | What it is |
|---|---|
| `compiled-workflow.json` | The compiled form of all three procedures — `booking`, `cancel_or_reschedule`, `escalate_to_human` — 27 nodes, 30 edges. Every step's instruction text is carried verbatim inside the node prompts, so the procedures can be reconstructed from here. |
| `agent-config.json` | The full agent definition: system prompt, `built_in_tools` (all four, including the 11 transfer routes), knowledge base locators, tool ids, language presets, TTS and ASR settings, LLM choice. |

`compiled-workflow.json` is the **compiled** output, so it carries the `escalate_to_human` trigger as
narrowed on 25 September — the one that was never published on the old agent. Rebuilding in the new
account starts from the corrected text rather than the old one, which is the one silver lining in
having done the work in the wrong place.

Neither file holds a credential. `secret_id` appears five times; those are references to workspace
secrets, not the secret values, and the secrets themselves live in the ElevenLabs workspace. The
`X-Optofarm-Secret` webhook secret will need re-adding by hand in the new workspace.

What is **not** here, because it is already mirrored in its own place:

- system prompt → [`../../system-prompt.main.txt`](../../system-prompt.main.txt)
- knowledge base → [`../../knowledge-base/`](../../knowledge-base/) (all 7 documents)
- webhook tools → [`../../tools/`](../../tools/)
- pronunciation dictionaries → [`../../pronunciation/`](../../pronunciation/)
