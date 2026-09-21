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
| `Optometrist` | /optomeˈtrist/ | "Optometrisht" | correct |

The one nobody expected was the **Romanian voice mispronouncing Romanian**: evolvo strips
diacritics from its own language, and `Mures` appears in 6 of the 8 locations, so it fired on
nearly every call. That is now fixed upstream in n8n rather than here — see below.

## State, 2026-09-21

| | |
|---|---|
| Model | `eleven_v3_conversational` (read live off the agent) |
| Romanian (base) voice | `eXpIbVcVbLo8ZJQDlDnl` → `conversation_config.tts` |
| Hungarian preset voice | `xjlfQQ3ynqiEyRpArrT8` → `language_presets.hu.overrides.tts` |
| English preset | no voice override — inherits the Romanian voice, and with it `ro-voice.pls` |
| Dictionaries attached | **yes, 2026-09-21** — see below |

`pronunciation_dictionary_locators` works per language preset, not only on the base agent —
probed live and persisted. That is what makes this approach possible at all: one workspace-wide
dictionary could not help, because a single fixed alias cannot be right in both languages.

## Deployed

| file | dictionary id | version id | attached to |
|---|---|---|---|
| `ro-voice.pls` (20 rules) | `AaMtnNwhZIwuKDy7zI1m` | `sllOUy0OaQibE5jPf78c` | `conversation_config.tts` |
| `hu-voice.pls` (36 rules) | `3uSfRsZV5XpeC3fdtKbV` | `jgpS5JvhL4HK73Dxvd4F` | `language_presets.hu.overrides.tts` |

Uploaded as `optofarm-{ro,hu}-voice-2026-09-21` and verified rule-for-rule by downloading them back.
The `en` preset is deliberately left with an empty locator list: it overrides no voice, so it speaks
with the Romanian voice and inherits the base dictionary.

**⚠️ `language_presets` REPLACES, it does not merge.** Updating the agent with only the `hu` preset
silently deleted the `en` preset — and with it the English first message. Caught by diffing the
response against the pre-update config, and restored in the next call. Always send every preset you
want to keep, and diff afterwards.

**Older dictionaries exist in this workspace and are NOT attached**: two `optofarm_ro`/`optofarm_hu`
pairs plus an `optofarm_en`, from earlier work. They are keyed partly on the pre-correction
spellings — the newest Hungarian one still maps `Anca`, which no tool returns any more. Left alone
rather than deleted. One idea in them is worth stealing if the listening test wants it: they expand
titles (`Dr.` → `doctor`, `Prof.` → `profesor`) and alias some whole names
(`Dr. Baricz Anna` → `doamna doctor Barits Anna`).

## Alias, not phoneme — a default, not a limit

The public docs list phoneme support for `eleven_flash_v2` and `eleven_v3` only, which would exclude
this agent's `eleven_v3_conversational`. That is not the whole story. The agent carries a
**`conversation_config.tts.enable_phoneme_tags`** flag — *"Opt-in to SSML phoneme tag handling for V3
models... phoneme tags, inline and from pronunciation dictionaries, are parsed into inline IPA"* —
and it is currently **`false`**.

So phonemes are reachable here, one boolean away. Alias remains the default on merit rather than
necessity: it works whatever that flag says, and a respelling is a smaller judgement call than an
IPA transcription nobody has heard. IPA sits in the file comments, so the switch is mechanical.

## Keyed on what the TTS actually receives

An alias fires on the grapheme reaching the engine — not on what evolvo stores, and not on the
"correct" spelling. As of 2026-09-21 that is:

- **Provider names in their corrected form.** The n8n `Display Names` nodes rewrite five of them
  (`Anica`, `Székely`, `Bódi Ildikó`, `Ifj. Jeremiás László`, `Jeremiás Zoltán`) on the way out.
- **Locations with their Romanian diacritics restored** — `Tg. Mureș, Str. Poștei Nr. 3` and so
  on. The same `Display Names` map handles these as of 2026-09-21.

If either changes, every affected entry silently stops firing and the phonetics quietly revert.
Re-key in the same pass. This is why the dictionaries were built *after* the names were settled.

**Diacritics are fixed in n8n; abbreviations are expanded here.** That split is not stylistic.
Restoring a diacritic changes letters the matcher compares, and the matcher strips diacritics on
both sides, so it is free. Expanding `Tg.` to `Târgu` is three edits against a Levenshtein budget
of two — pushing it through n8n was measured to send all six Târgu branches to NO MATCH when the
agent echoed a corrected address back into a tool. A dictionary alias never reaches the matcher, so
abbreviation expansion is safe here and nowhere else.

One thing was lost by fixing locations upstream: the Hungarian voice used to read the *stripped*
`Postei` and `Scolii` correctly for free, since HU `s` = /ʃ/ is what the missing `ș` wanted. Now a
real `ș` arrives — not a Hungarian letter — so `hu-voice.pls` maps those two back to plain `s`.
A cheap price for both voices getting correct Romanian.

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

## To redeploy after an edit

The MCP connector can **attach** a dictionary (`agents_update` takes
`pronunciation_dictionary_locators`) but cannot **create** one — there is no upload tool, confirmed
by reading the connector's schemas rather than searching their names. Uploading needs the REST API
and an `xi-api-key`:

```
POST https://api.elevenlabs.io/v1/pronunciation-dictionaries/add-from-file
  -H "xi-api-key: $KEY"  -F file=@ro-voice.pls  -F name=optofarm-ro-voice-<date>
```

Editing a `.pls` means **a new upload and a new `version_id`** — a locator pins a version, so an
edited file changes nothing until the agent is re-pointed at it. Then re-attach, remembering the
`language_presets` replace-not-merge trap above, and diff the response against the previous config
before trusting it.

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
