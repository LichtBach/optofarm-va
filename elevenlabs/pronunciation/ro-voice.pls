<?xml version="1.0" encoding="UTF-8"?>
<!--
  ro-voice.pls — for the ROMANIAN (base) voice, eXpIbVcVbLo8ZJQDlDnl.
  Attaches to: conversation_config.tts.pronunciation_dictionary_locators
  Also reaches ENGLISH callers: the `en` preset overrides no voice, so it inherits this one.

  Two jobs:
    1. Hungarian provider names, respelled in Romanian orthography.
    2. Romanian words evolvo has stripped the diacritics from — the Romanian voice
       mispronounces its OWN language because `Mures` is not `Mureș`.

  GRAPHEMES ARE KEYED ON WHAT THE TTS ACTUALLY RECEIVES as of 2026-09-21: provider names
  in their corrected form (n8n `Display Names` nodes rewrite five of them), locations in
  the raw stripped form evolvo returns (n8n does NOT touch locations). If either of those
  changes, every entry below silently stops firing. Nothing breaks visibly — the phonetics
  just quietly revert. Re-key this file in the same pass.

  ALIAS, NOT PHONEME — but the reason is narrower than the public docs suggest. The docs list
  phoneme support for `eleven_flash_v2` and `eleven_v3` only, which would exclude this agent's
  `eleven_v3_conversational`. That is not the whole story: the agent carries a
  **`conversation_config.tts.enable_phoneme_tags`** flag ("Opt-in to SSML phoneme tag handling for
  V3 models... phoneme tags, inline and from pronunciation dictionaries, are parsed into inline IPA")
  and it is currently **false**. So phonemes ARE reachable here — one boolean away — and alias is a
  deliberate default rather than the only option: it works whatever that flag says, and respelling
  is a smaller judgement call than committing to an IPA transcription nobody has heard yet. IPA is
  recorded in the comments below so the switch is mechanical if the listening test wants it.

  PLS matching is CASE SENSITIVE. Every grapheme here is capitalised because that is how
  evolvo returns it and how the agent writes it mid-sentence.

  UNVERIFIED — every alias is a prediction about how the engine reads it. Listen first.
-->
<lexicon version="1.0"
         xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
         alphabet="ipa" xml:lang="ro-RO">

  <!-- ===== Hungarian provider names ===================================================
       Romanian has no `sz` or `cz` digraph, reads `j` as /ʒ/, and gives a final `s` /s/
       where Hungarian wants /ʃ/. These are the corrected spellings n8n now sends. -->

  <!-- /ˈseːkɛj/ — RO `ch` before `e` is the only way to get /k/ there -->
  <lexeme><grapheme>Székely</grapheme><alias>Sechei</alias></lexeme>
  <!-- /ˈbɒrits/ — `cz` is not Romanian at all -->
  <lexeme><grapheme>Baricz</grapheme><alias>Barits</alias></lexeme>
  <!-- /ˈɛlɛkɛʃ/ — final `s` must become `ș` or it reads /s/ -->
  <lexeme><grapheme>Elekes</grapheme><alias>Elekeș</alias></lexeme>
  <!-- /ˈjɛrɛmiaːʃ/ — RO `j` is /ʒ/, so "Zheremias" without this -->
  <lexeme><grapheme>Jeremiás</grapheme><alias>Ieremiaș</alias></lexeme>
  <!-- /ˈlaːsloː/ — `sz` would be read as two letters -->
  <lexeme><grapheme>László</grapheme><alias>Laslo</alias></lexeme>
  <!-- /ˈzoltaːn/ — strip the non-Romanian `á` -->
  <lexeme><grapheme>Zoltán</grapheme><alias>Zoltan</alias></lexeme>
  <!-- /ˈildikoː/ -->
  <lexeme><grapheme>Ildikó</grapheme><alias>Ildico</alias></lexeme>
  <!-- /ˈboːdi/ -->
  <lexeme><grapheme>Bódi</grapheme><alias>Bodi</alias></lexeme>
  <!-- /ˈɒtillɒ/ — `Atila` is the standard Romanian spelling of the name -->
  <lexeme><grapheme>Attila</grapheme><alias>Atila</alias></lexeme>

  <!-- LOWEST CONFIDENCE ENTRY IN EITHER FILE. `Ifj.` is the Hungarian abbreviation of
       `ifjabb` (the younger) and is the ONLY thing distinguishing Jeremiás László senior
       from junior. Unaliased, the Romanian voice will spell it out letter by letter.
       `Ifiabb` approximates the Hungarian. `Junior` would be the other defensible choice
       and may be what a Romanian caller actually expects — decide this one by ear.
       Keyed without the period so it cannot interact with sentence splitting. -->
  <lexeme><grapheme>Ifj</grapheme><alias>Ifiabb</alias></lexeme>

  <!-- ===== Romanian words still arriving stripped =====================================
       The branch addresses USED to be here — `Mures`, `Piata`, `Postei`, `Scolii`,
       `Principala`. They are gone because n8n now restores those diacritics before the
       text ever reaches the engine (the `LOCATIONS` map in `Display Names`), which is the
       better place for it: both voices get correct Romanian, not just this one.
       What remains is what n8n still does NOT touch. -->

  <!-- Provider surname, left stripped in evolvo by the clinic's choice -->
  <lexeme><grapheme>Ormenisan</grapheme><alias>Ormenișan</alias></lexeme>
  <!-- Service suffix on the psycho-orthoptics calendar -->
  <lexeme><grapheme>ortoptica</grapheme><alias>ortoptică</alias></lexeme>

  <!-- ===== Abbreviations ============================================================== -->
  <!-- `Tg.` is read as two letters otherwise. Keyed without the period. -->
  <lexeme><grapheme>Tg</grapheme><alias>Târgu</alias></lexeme>
  <lexeme><grapheme>Bld</grapheme><alias>Bulevardul</alias></lexeme>
  <lexeme><grapheme>Str</grapheme><alias>Strada</alias></lexeme>
  <lexeme><grapheme>Nr</grapheme><alias>numărul</alias></lexeme>
  <!-- "Bld. 1 Dec 1918" -->
  <lexeme><grapheme>Dec</grapheme><alias>Decembrie</alias></lexeme>

  <!-- ===== Hungarian place names ======================================================
       Only fire if the agent echoes a branch the caller named in Hungarian; the tools
       always return the Romanian spellings. -->
  <lexeme><grapheme>Szováta</grapheme><alias>Sovata</alias></lexeme>
  <lexeme><grapheme>Szászrégen</grapheme><alias>Sasreghen</alias></lexeme>
  <lexeme><grapheme>Marosvásárhely</grapheme><alias>Maroșvașarhei</alias></lexeme>

</lexicon>
