# Per-language pronunciation dictionaries

The problem: text-to-speech applies **one** language's letter-to-sound rules to the whole
utterance, so a Romanian name spoken by the Hungarian voice comes out with Hungarian
phonetics, and vice versa. Some concrete failures:

| written | correct | Hungarian voice says | Romanian voice says |
|---|---|---|---|
| Anica | /aˈnika/ | "Anitsa" (`c` = /ts/ in HU) | correct |
| Camelia | /kaˈmelia/ | "Tsamelia" | correct |
| Istratuc | /istraˈtuk/ | "Ishtratuts" (`s` = /ʃ/) | correct |
| Székely | /ˈseːkɛj/ | correct | "Sze-ke-li" (no `sz` digraph in RO) |
| Baricz | /ˈbɒrits/ | correct | `cz` is not Romanian |
| Jeremiás | /ˈjɛrɛmiaːʃ/ | correct | "Zheremias" (`j` = /ʒ/ in RO) |
| Elekes | /ˈɛlɛkɛʃ/ | correct | "Elekes" with a final /s/ |

## The mechanism, verified 2026-09-21

`pronunciation_dictionary_locators` can be set **per language preset**, not only on the base
agent. Probed live against `agent_3101kyq03vpxfpb9vsskgfh2f0bd`: the field is accepted and
persisted inside `conversation_config.language_presets.hu.overrides.tts` and `.en.overrides.tts`,
alongside the `voice_id` override the Hungarian preset already carried.

That is what makes this approach work at all. One workspace-wide dictionary could not help,
because a single fixed alias cannot be right in both languages — you would be choosing which
language to mispronounce.

Romanian is the base agent language (`agent.language: "ro"`), so there is no `ro` preset: the
Romanian dictionary attaches to `conversation_config.tts.pronunciation_dictionary_locators`.

| voice | attaches to | contains |
|---|---|---|
| Romanian (base), `eXpIbVcVbLo8ZJQDlDnl` | `conversation_config.tts` | `ro-voice.pls` — Hungarian names respelled in Romanian orthography |
| Hungarian, `xjlfQQ3ynqiEyRpArrT8` | `language_presets.hu.overrides.tts` | `hu-voice.pls` — Romanian names respelled in Hungarian orthography |
| English (base voice) | `language_presets.en.overrides.tts` | undecided — see below |

## What is NOT done

1. **The dictionaries do not exist yet.** The ElevenLabs MCP server exposes no
   pronunciation-dictionary tools and this session has no REST API key, so the `.pls` files here
   have to be uploaded through the dashboard. Once they exist, attaching them is a one-line
   config change per preset.
2. **The name lists are partial** — 14 of roughly 30 calendars, gathered from live tool results
   and call transcripts rather than from a roster. Complete them from the evolvo calendar list.
3. **Nothing here has been heard.** Every alias below is a prediction about how the engine will
   read it. They need one pass with someone who speaks both languages, listening.
4. **English.** An English caller hears the base Romanian voice, so `ro-voice.pls` applies to
   them by default. Whether Hungarian names should also be respelled for English is an open
   question — probably yes, and probably the same file.

## Two things to fix first

**The calendar names are missing their diacritics.** evolvo stores `Szekely`, not `Székely`;
`Laszlo`, not `László`; `Ormenisan`, not `Ormenișan`. That degrades pronunciation even in the
*matching* language, and it changes what the alias has to be keyed on — an entry for `Székely`
will not fire on a calendar that says `Szekely`. The graphemes below are therefore keyed on the
stripped spellings evolvo actually returns.

`Ormenisan` is the interesting case: the Hungarian voice reads the stripped spelling correctly
(HU `s` = /ʃ/, which is what `ș` needs), and the Romanian voice reads it wrongly. The
cross-language problem and the diacritic problem cancel out in one direction and compound in the
other.

**`Dr. Ilovan Anca` is still misspelt in evolvo** — the client says `Anica`. Fix the calendar
before keying a dictionary entry to either spelling.

## Getting the name list

A read-only n8n workflow spec and a ready-to-paste prompt for the n8n agent are in
[`../../n8n/provider-roster-workflow-prompt.md`](../../n8n/provider-roster-workflow-prompt.md). It dumps every
calendar keyed on `calendarid` (not the name, which is about to change) with four empty columns for a human to
fill in: `name_display`, `spoken_ro`, `spoken_hu`, `notes`. That one table feeds both this dictionary and the
option C fallback below.

## Interaction with the language gate

Saying a Hungarian name inside a Romanian sentence is **not** a language switch and must not
call `language_detection`. If anyone ever tries to solve pronunciation by switching language per
name, calls will thrash between voices. The gate in the system prompt keys on the language the
agent is about to speak, and one foreign proper noun does not change that — but the wording has
never been tested against this case.

## If this route fails

Option C, kept in reserve: n8n returns `doctor_spoken_ro` and `doctor_spoken_hu` next to
`doctor`, exactly as it already returns `date_spoken` next to `date`, and the agent speaks
whichever matches the language it is in while still sending the canonical `doctor` back to the
tools. No platform feature needed, works on any model or voice.
