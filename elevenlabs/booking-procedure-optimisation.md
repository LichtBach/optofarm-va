# booking procedure — token reduction (branch `latency-step-merge`)

**22,253 -> 16,361 chars, ~6,180 -> ~4,545 tokens, -26.5%.**
Token figures are a ~3.6 chars/token estimate: the sandbox proxy blocks the BPE
download, so no exact count was possible. Character counts are exact.

Deployed to `latency-step-merge` (0% traffic) only. Main untouched.
Compiles clean: 27 nodes, 30 edges.

## Why 26.5% and not the 30% first estimated

The last ~3.5% would have meant cutting load-bearing rules — chiefly the dead-end
branch condition, which is the guard against the agent giving up while a caller is
still proposing alternatives. That guard is verbose because the behaviour it
prevents is one this agent has actually got wrong. Stopping at a verified 26.5%
beats hitting 30% with a silent regression.

## What was cut, and what now carries each rule

| Cut | ~chars | Now carried by |
|---|---:|---|
| Read-back mechanics, both copies | 1,684 | System prompt `## The phone read-back gate` — states it as a universal gate, more strongly than the procedure did |
| Compound-number conversion, both copies | 460 | System prompt `# Numbers and how to speak them` — same examples, stated more strongly |
| "name spoken once" rule, both copies | 300 | System prompt `# Addressing the caller — read this twice` |
| Branch-keyword mapping table | 250 | System prompt `## Branch names — normalize with this table everywhere` |
| Tool error restatements (availability, book, log) | ~350 | The three tool descriptions, which already specify every error |
| Emergency list, 3 copies -> 1 | ~150 | Branch 0 condition + system prompt `# Step 0 — Medical urgency` |
| Holding-line instruction, 3 copies | ~140 | Tool config `force_pre_tool_speech: true` enforces it mechanically |
| "never end in silence / never skip_turn" repeats | ~120 | System prompt "Never emit a silent or empty response" |
| Impossible/past date rule | ~60 | System prompt "Never pass an impossible or past date to a tool" |
| Email param note | 56 | `evolvo_book_appointment` email parameter description |

32 behavioural rules were checked individually against the new procedure, the
system prompt and the tool descriptions. All 32 covered.

## Bug fixed in passing

The name/phone/read-back step was pasted into both branches and the copies had
**already diverged**. The dead-end (callback) copy was missing the compound-number
conversion rule, both read-back example sentences, and "a corrected number is never
used until it has been read back and confirmed in its own turn" — on the one path
where a wrong number means the colleague never reaches the caller.

Both copies are now identical except for the single intended difference: why the
name is being asked for ("needed for the appointment" vs "the colleague needs it to
call them back").

## Deliberately NOT extracted to a sub-procedure

The obvious dedup — pull the read-back into a sub-procedure referenced by both
branches — was rejected. In `conv_8101m2ba36v5f8av968pgvhk1g6p`, `start_procedure`
cost 1,073 ms of LLM and 0 ms of tool. If entering a sub-procedure works the same
way, it would save ~670 tokens (~30 ms) and cost ~900 ms per entry. Wrong trade
when round trips are the actual bottleneck. Reconciling the two copies and
shortening the shared text saves on both copies and costs no round trip.

## Unresolved contradiction found (not touched)

On tool failure the procedure says **"try once more"**; the system prompt
`# Appointment flow` says **"If the tool fails, do not retry it"**. These conflict.
The procedure's version is currently the more specific and was kept as-is. Worth a
decision rather than a silent edit.

## Expected effect

Latency: modest. ~1,600 fewer tokens on each of ~15 LLM calls per booking call
trims prefill, but does not touch the ~6.3 s of bookkeeping round trips measured in
`conv_8101m2ba36v5f8av968pgvhk1g6p`, which remains the dominant cost.
The real payoff is fewer competing sources of truth, hence fewer instruction-following
misses — and each miss costs a full extra round trip.
