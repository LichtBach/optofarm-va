<?xml version="1.0" encoding="UTF-8"?>
<!--
  Attaches to: conversation_config.tts.pronunciation_dictionary_locators  (base / Romanian voice)
  Purpose:     make the Romanian voice say HUNGARIAN names correctly.
  Graphemes are the stripped spellings evolvo actually returns (no diacritics).
  UNVERIFIED - every alias is a prediction. Listen before trusting.
-->
<lexicon version="1.0"
         xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
         alphabet="ipa" xml:lang="ro-RO">

  <!-- Providers -->
  <lexeme><grapheme>Szekely</grapheme><alias>Sekei</alias></lexeme>
  <lexeme><grapheme>Baricz</grapheme><alias>Barits</alias></lexeme>
  <lexeme><grapheme>Jeremias</grapheme><alias>Ieremiaș</alias></lexeme>
  <lexeme><grapheme>Laszlo</grapheme><alias>Laslo</alias></lexeme>
  <lexeme><grapheme>Elekes</grapheme><alias>Elekeș</alias></lexeme>
  <lexeme><grapheme>Ildiko</grapheme><alias>Ildico</alias></lexeme>
  <lexeme><grapheme>Bodi</grapheme><alias>Bodi</alias></lexeme>
  <lexeme><grapheme>Zoltan</grapheme><alias>Zoltan</alias></lexeme>

  <!-- Romanian names whose diacritics evolvo strips -->
  <lexeme><grapheme>Ormenisan</grapheme><alias>Ormenișan</alias></lexeme>

  <!-- Place names a Romanian caller may hear -->
  <lexeme><grapheme>Rozsak tere</grapheme><alias>Rojac tere</alias></lexeme>
  <lexeme><grapheme>Szentgyorgyter</grapheme><alias>Sentdiurdi ter</alias></lexeme>
  <lexeme><grapheme>Szovata</grapheme><alias>Sovata</alias></lexeme>
  <lexeme><grapheme>Szaszregen</grapheme><alias>Sasreghen</alias></lexeme>
  <lexeme><grapheme>Kimikale</grapheme><alias>Chimicale</alias></lexeme>

</lexicon>
