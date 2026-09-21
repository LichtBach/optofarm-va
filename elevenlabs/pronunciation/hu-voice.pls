<?xml version="1.0" encoding="UTF-8"?>
<!--
  Attaches to: language_presets.hu.overrides.tts.pronunciation_dictionary_locators
  Purpose:     make the Hungarian voice say ROMANIAN names correctly.
  Hungarian reading rules that bite: c = /ts/, s = /S/, sz = /s/, a = /O/.
  UNVERIFIED - every alias is a prediction. Listen before trusting.
-->
<lexicon version="1.0"
         xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
         alphabet="ipa" xml:lang="hu-HU">

  <!-- Providers: the killer is Hungarian c = /ts/ where Romanian wants /k/ -->
  <lexeme><grapheme>Anica</grapheme><alias>Aniká</alias></lexeme>
  <lexeme><grapheme>Camelia</grapheme><alias>Kamélia</alias></lexeme>
  <lexeme><grapheme>Istratuc</grapheme><alias>Isztratuk</alias></lexeme>
  <lexeme><grapheme>Ardelean</grapheme><alias>Árdeleán</alias></lexeme>
  <lexeme><grapheme>Adina</grapheme><alias>Ádiná</alias></lexeme>
  <lexeme><grapheme>Petrea</grapheme><alias>Petreá</alias></lexeme>
  <lexeme><grapheme>Alexandra</grapheme><alias>Álekszándrá</alias></lexeme>
  <lexeme><grapheme>Tripon</grapheme><alias>Tripon</alias></lexeme>
  <lexeme><grapheme>Natalia</grapheme><alias>Nátáliá</alias></lexeme>
  <lexeme><grapheme>Dorina</grapheme><alias>Doriná</alias></lexeme>

  <!-- Place names a Hungarian caller may hear -->
  <lexeme><grapheme>Postei</grapheme><alias>Postyei</alias></lexeme>
  <lexeme><grapheme>Trandafirilor</grapheme><alias>Trándáfirilor</alias></lexeme>
  <lexeme><grapheme>Republicii</grapheme><alias>Republiki</alias></lexeme>
  <lexeme><grapheme>Principala</grapheme><alias>Principálá</alias></lexeme>
  <lexeme><grapheme>Scolii</grapheme><alias>Skoli</alias></lexeme>

</lexicon>
