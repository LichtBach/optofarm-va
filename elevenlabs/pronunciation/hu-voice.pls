<?xml version="1.0" encoding="UTF-8"?>
<!--
  hu-voice.pls — for the HUNGARIAN voice, xjlfQQ3ynqiEyRpArrT8.
  Attaches to: language_presets.hu.overrides.tts.pronunciation_dictionary_locators

  One job: make the Hungarian voice say ROMANIAN names and places correctly.

  The Hungarian reading rules that bite, in order of damage:
    c  = /ts/   -> "Anitsa", "Tsamelia", "Republitsii"
    s  = /ʃ/    -> "Ishtratuts", "Shimona"
    sz = /s/    -> so a Romanian /s/ must be written `sz`
    a  = /ɒ/    -> so a Romanian /a/ is closer to `á`
    j  = /j/    -> so a Romanian /ʒ/ must be written `zs`

  GRAPHEMES ARE KEYED ON WHAT THE TTS ACTUALLY RECEIVES as of 2026-09-21. See the header
  of ro-voice.pls — the same re-keying warning applies here.

  ALIAS, NOT PHONEME — see ro-voice.pls for the full reasoning, including the
  `enable_phoneme_tags` flag that makes phonemes reachable on this agent. PLS matching is CASE
  SENSITIVE; graphemes are capitalised as evolvo returns them.

  UNVERIFIED — every alias is a prediction. Listen first.

  NOT LISTED ON PURPOSE: `Ormenisan`. Hungarian reads `s` as /ʃ/, which is exactly what
  the stripped `ș` needs — the Hungarian voice already says this Romanian name correctly
  and the Romanian one does not. Same for `Postei` and `Scolii`. Do not "fix" them here.
  Hungarian provider names (Székely, Baricz, Jeremiás, László, Zoltán, Bódi, Ildikó,
  Elekes, Attila, Anna, Ella) are likewise correct already in this voice.
-->
<lexicon version="1.0"
         xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
         alphabet="ipa" xml:lang="hu-HU">

  <!-- ===== The most frequent word in the whole corpus ================================
       `Optometrist` prefixes 9 of the 30 calendars. Hungarian `s` = /ʃ/ makes it
       "Optometrisht" every single time. Highest-value entry in this file. -->
  <lexeme><grapheme>Optometrist</grapheme><alias>Optometriszt</alias></lexeme>

  <!-- ===== Romanian given names ======================================================= -->
  <!-- /aˈnika/ — the headline failure: `c` = /ts/ gives "Anitsa" -->
  <lexeme><grapheme>Anica</grapheme><alias>Ániká</alias></lexeme>
  <!-- /kaˈmelia/ — "Tsamelia" without this -->
  <lexeme><grapheme>Camelia</grapheme><alias>Kamélia</alias></lexeme>
  <lexeme><grapheme>Adina</grapheme><alias>Ádiná</alias></lexeme>
  <lexeme><grapheme>Alexandra</grapheme><alias>Álekszándrá</alias></lexeme>
  <lexeme><grapheme>Dorina</grapheme><alias>Doriná</alias></lexeme>
  <lexeme><grapheme>Delia</grapheme><alias>Déliá</alias></lexeme>
  <lexeme><grapheme>Maria</grapheme><alias>Máriá</alias></lexeme>
  <lexeme><grapheme>Natalia</grapheme><alias>Nátáliá</alias></lexeme>
  <!-- /siˈmona/ — `S` alone would be /ʃ/, so it must be `Sz` -->
  <lexeme><grapheme>Simona</grapheme><alias>Szimoná</alias></lexeme>
  <lexeme><grapheme>Laura</grapheme><alias>Láurá</alias></lexeme>
  <lexeme><grapheme>Robert</grapheme><alias>Róbert</alias></lexeme>

  <!-- ===== Romanian surnames ========================================================== -->
  <!-- /istraˈtuk/ — both failures at once: "Ishtratuts" -->
  <lexeme><grapheme>Istratuc</grapheme><alias>Isztrátuk</alias></lexeme>
  <lexeme><grapheme>Ardelean</grapheme><alias>Árdeleán</alias></lexeme>
  <lexeme><grapheme>Ilovan</grapheme><alias>Ilován</alias></lexeme>
  <lexeme><grapheme>Petrea</grapheme><alias>Petreá</alias></lexeme>
  <lexeme><grapheme>Popa</grapheme><alias>Popá</alias></lexeme>
  <lexeme><grapheme>Rotar</grapheme><alias>Rotár</alias></lexeme>
  <lexeme><grapheme>Zait</grapheme><alias>Záit</alias></lexeme>
  <lexeme><grapheme>Dan</grapheme><alias>Dán</alias></lexeme>

  <!-- ===== The psycho-orthoptics service string ======================================
       Returned verbatim on Dr. Prof. Székely Attila's calendar, so the Hungarian voice
       has to read Romanian words: `c` = /ts/ and `s` = /ʃ/ both bite here. -->
  <lexeme><grapheme>Consiliere</grapheme><alias>Konszilieré</alias></lexeme>
  <lexeme><grapheme>Terapie</grapheme><alias>Terápie</alias></lexeme>
  <lexeme><grapheme>psiho</grapheme><alias>pszicho</alias></lexeme>
  <lexeme><grapheme>ortoptica</grapheme><alias>ortoptiká</alias></lexeme>

  <!-- ===== Places ====================================================================
       The Hungarian voice should use the Hungarian name of a branch where one exists —
       that is what a Hungarian caller will recognise. -->
  <!-- ONE entry, not `Tg` + `Mures` separately: two entries would collide and produce
       "Marosvásárhely Maros". If multi-word graphemes turn out not to match, this simply
       does not fire and the caller hears the Romanian name — degradation, not corruption. -->
  <lexeme><grapheme>Tg. Mureș</grapheme><alias>Marosvásárhely</alias></lexeme>
  <lexeme><grapheme>Sovata</grapheme><alias>Szováta</alias></lexeme>
  <lexeme><grapheme>Reghin</grapheme><alias>Szászrégen</alias></lexeme>
  <!-- /ˈpjatsa/ is actually right in Hungarian by accident (`c` = /ts/), but the vowel is not -->
  <lexeme><grapheme>Piața</grapheme><alias>Pjáca</alias></lexeme>
  <lexeme><grapheme>Trandafirilor</grapheme><alias>Trándáfirilor</alias></lexeme>
  <!-- /repuˈblikii/ — `c` = /ts/ gives "Republitsii" -->
  <lexeme><grapheme>Republicii</grapheme><alias>Republikii</alias></lexeme>
  <lexeme><grapheme>Principală</grapheme><alias>Principálá</alias></lexeme>
  <lexeme><grapheme>Fortuna</grapheme><alias>Fortuná</alias></lexeme>

  <!-- NEW since n8n started restoring Romanian diacritics in locations. These two used to
       need no entry at all: the Hungarian voice read the STRIPPED `Postei` and `Scolii`
       correctly, because HU `s` = /ʃ/ is exactly what the missing `ș` wanted. Now that the
       real `ș` arrives — a letter Hungarian does not have — map it back to the plain `s`
       that already produced the right sound. Losing these is the one cost of fixing the
       locations upstream, and it is a cheap one. -->
  <lexeme><grapheme>Poștei</grapheme><alias>Postei</alias></lexeme>
  <lexeme><grapheme>Școlii</grapheme><alias>Scolii</alias></lexeme>
  <lexeme><grapheme>Dec</grapheme><alias>december</alias></lexeme>
  <!-- Hungarian puts the surname first, so aliasing the two words separately would give
       "Georgye Dózsa" — backwards. One entry, in Hungarian order. -->
  <lexeme><grapheme>Gheorghe Doja</grapheme><alias>Dózsa György</alias></lexeme>

  <!-- `Str.` and `Bld.` are NOT aliased here on purpose. Hungarian puts `utca` AFTER the
       street name ("Poștei utca"), so a word-for-word alias would produce "utca Postei" —
       worse than leaving the Romanian abbreviation alone. Word order is the agent's job,
       not a lexicon's. -->

</lexicon>
