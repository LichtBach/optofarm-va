# Per-language pronunciation dictionaries

The problem: text-to-speech applies **one** language's letter-to-sound rules to the whole
utterance, so a Romanian name spoken by the Hungarian voice comes out with Hungarian phonetics,
and vice versa.

| written | correct | Hungarian voice says | Romanian voice says |
|---|---|---|---|
| `Anica` | /aˈnika/ | "Anitsa" (`c` = /ts/) | correct |
| `Camelia` | /kaˈmelia/ | "Tsamelia" | correct |
| `Istratuc` | /istraˈtuk/ | "Ishtratuts" (`s` = /ʃ/) | correct |
| `Optometrist` | /optomeˈtrist/ | "Optometrisht" | correct |
| `Székely` | /ˈseːkɛj/ | correct | "Sze-ke-li" (no `sz` digraph in RO) |
| `Baricz` | /ˈbɒrits/ | correct | `cz` is not Romanian |
| `Jeremiás` | /ˈjɛrɛmiaːʃ/ | correct | "Zheremias" (`j` = /ʒ/) |
| `Mureș` | /ˈmureʃ/ | correct (`s` = /ʃ/) | **"Mures" — evolvo stripped the `ș`** |

That last row is the one nobody expected: the **Romanian voice mispronounces Romanian**, because
evolvo strips diacritics from its own language. `Mures` appears in 6 of the 8 locations, so it
fires on nearly every call — a bigger everyday problem than any single doctor's name.

## State, 2026-09-21

| | |
|---|---|
| Model | `eleven_v3_conversational` (read live off the agent) |
| Romanian (base) voice | `eXpIbVcVbLo8ZJQDlDnl` → `conversation_config.tts` |
| Hungarian preset voice | `xjlfQQ3ynqiEyRpArrT8` → `language_presets.hu.overrides.tts` |
| English preset | no voice override — inherits the Romanian voice, and with it `ro-voice.pls` |
| Dictionaries attached | **none yet** — all three locator lists are empty |

`pronunciation_dictionary_locators` works per language preset, not only on the base agent —
probed live and persisted. That is what makes this approach possible at all: one workspace-wide
dictionary could not help, because a single fixed alias cannot be right in both languages.

## Alias, not phoneme — deliberately

Phoneme tags are documented as working on `eleven_flash_v2` and `eleven_v3`. This agent runs
**`eleven_v3_conversational`, which is on neither list**, and an unsupported phoneme tag is
*skipped silently* — no error, just the default pronunciation. Alias works on every model.

IPA is recorded in comments beside the entries that earn it, so this can be upgraded mechanically
if a live test shows `eleven_v3_conversational` honours phonemes. Don't assume it does; v3's IPA
support is the documented reason someone would switch models for this.

## Keyed on what the TTS actually receives

An alias fires on the grapheme reaching the engine — not on what evolvo stores, and not on the
"correct" spelling. As of 2026-09-21 that is:

- **Provider names in their corrected form.** The n8n `Display Names` nodes rewrite five of them
  (`Anica`, `Székely`, `Bódi Ildikó`, `Ifj. Jeremiás László`, `Jeremiás Zoltán`) on the way out.
- **Locations in the raw stripped form.** n8n does **not** touch locations, so `Tg. Mures`,
  `Piata`, `Postei`, `Scolii`, `Principala` arrive exactly as evolvo has them.

If either changes, every affected entry silently stops firing and the phonetics quietly revert.
Re-key in the same pass. This is why the dictionaries were built *after* the names were settled.

Worth knowing: **fixing the locations in n8n instead** — the same five-line map that already
corrects the names — would be cleaner than aliasing them here, because both voices would then
receive correct Romanian and only the genuine cross-language respelling would live in these files.
It was not done because it would mean re-keying this file again. Decide it once, deliberately.

## What is in each file

| file | voice | contains |
|---|---|---|
| `ro-voice.pls` | Romanian (and English) | Hungarian names respelled in Romanian orthography, plus the Romanian diacritics evolvo stripped |
| `hu-voice.pls` | Hungarian | Romanian names and places respelled in Hungarian orthography |

Some things are deliberately **absent** from `hu-voice.pls`: `Ormenisan`, `Postei` and `Scolii`
are read *correctly* by the Hungarian voice, because HU `s` = /ʃ/ is exactly what the stripped `ș`
needs. The Romanian voice is the one that gets those wrong. Don't "fix" them on the Hungarian side.

Word order is not something a lexicon can fix, so `Str.`/`Bld.` are not aliased in Hungarian
(which puts `utca` after the street name), and `Gheorghe Doja` is one entry rather than two.

## To deploy

The ElevenLabs MCP connector exposes **no** pronunciation-dictionary tools — checked again
2026-09-21. Upload is dashboard or REST.

1. Upload both `.pls` files (ElevenLabs → Pronunciation Dictionaries). Note the returned
   `pronunciation_dictionary_id` and `version_id` for each.
2. Attach `ro-voice.pls` to `conversation_config.tts.pronunciation_dictionary_locators`.
3. Attach `hu-voice.pls` to
   `conversation_config.language_presets.hu.overrides.tts.pronunciation_dictionary_locators`.
4. Leave the `en` preset alone — it inherits the base voice and the Romanian dictionary with it.

## Smoke test — every entry here is a prediction

Nothing in either file has been heard. They are informed guesses about how the engine reads a
respelling. Do one pass per direction with someone who speaks both languages listening:

- **Romanian voice, Hungarian names** — ask for `Székely`, `Baricz`, `Jeremiás László`, `Elekes`.
  Listen for `sz` read as two letters, `cz` mangled, `j` as /ʒ/, final `s` as /s/ not /ʃ/.
- **Hungarian voice, Romanian names** — ask for `Ilovan Anica`, `Popa Camelia`, `Istratuc Dorina`,
  and any optometrist. Listen for `c` as /ts/ ("Anitsa", "Tsamelia") and `s` as /ʃ/.
- **Both voices, any branch** — the location is read on every single call. `Mureș` and `Piața` in
  Romanian; `Marosvásárhely` and `Dózsa György` in Hungarian.
- **Switch mid-call** and ask for the same doctor in both languages. It should sound right in each,
  and the switch must not trip `language_detection` on the name alone.

Then the same three with the dictionaries detached, and compare. The two entries most likely to be
wrong: `Ifj` → `Ifiabb` in Romanian (`Junior` is the other defensible reading — this one is a
judgement call about what a Romanian caller expects), and the multi-word graphemes
`Tg. Mures` / `Gheorghe Doja`, which simply will not fire if multi-word matching does not work.
