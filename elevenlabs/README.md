# Optofarm voice agent — ElevenLabs configuration

Source of truth for the ElevenLabs Conversational AI agent **Optofarm Agent - DEMO**
(`agent_3101kyq03vpxfpb9vsskgfh2f0bd`).

## Files

| File | ElevenLabs resource |
| --- | --- |
| `system-prompt.md` | Agent system prompt |
| `knowledge-base/kb_faq_operational_hu.md` | KB text doc `l7TG9P3XnTjgRThXelU5` |
| `knowledge-base/kb_faq_operational_ro.md` | KB text doc `zynIEChUpgg4AaEbZInG` |
| `procedure-tool-failure-hangup.md` | Why deterministic `tool_call` steps hang up the call, and the fix |

Also attached to the agent, managed in the ElevenLabs UI:

- `nCnyFsgESgiIY6S52Gyn` — Optica Optofarm, glosar de terminologie (RO)
- `qb3z7dO3OCbFDemQzqDe` — Optica Optofarm, terminology glossary (EN)
- `RqknpyMn7Z00284M0lpm` — Optica Optofarm, fogalomtár (HU)
- `MhVjolXAcypPXVvWoAVL` — crawl of https://optica-optofarm.ro/ (addresses, opening hours, services)

## Update from the client, 2026-09-07

Facts newly added or changed in this round:

- The eye examination costs **200 lei**; it stays free when glasses are made. (Previously only the free case was documented.)
- **Never tell callers to ring 112.** Urgent cases get the earliest doctor appointment, or are told to go to the emergency service in person.
- **Repairs are carried out** — the caller brings the glasses to the branch.
- If no suitably sized frame is found for a lens transfer, the lenses can sometimes be **re-edged** to fit.
- **New clip-ons and temple arms** can sometimes be ordered depending on the frame — branch colleague decides.
- **Same-day frame drop-off deadlines**: Poștei at least two hours before closing; Republicii by 14:00 (the optician works there until 16:00). No deadline known for other branches.
- **Stock enquiries** (has the vitamin order arrived?) always go to a colleague at the branch — never answered by the agent.
- **Cancelling and rescheduling** an existing appointment are now spelled out explicitly in the appointment flow.

Already covered before this round and left in place: no referral paper needed, clarifying what
the appointment is for, earliest appointment when no doctor preference, Szentgyörgytér landmark
directions, eye-pressure 30 lei / OCT 300 lei / lens from 220 lei / cataract surgery 3000 lei per eye,
new glasses the caller cannot see with, scratches cannot be polished out, coating and frame faults,
20-minute examination, previous prescription, notification when glasses are ready, urgent bookings
transferred to the branch, and opening hours served from the website crawl.

A full price list is still outstanding from the client; until it arrives the agent says it does not
have any price beyond the ones listed above.
