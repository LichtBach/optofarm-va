# Provider names — audit worksheet

16 unique providers, from [`provider-roster-2026-09-21.json`](provider-roster-2026-09-21.json)
(30 calendars; most people work 2–3 branches, so the name matters more than the row count).

Evolvo holds **every name with diacritics stripped** — all 16, without exception. That is the single
root cause behind both the pronunciation problem and the `Anca` / `Anica` question: there is no
Hungarian name in the system spelled correctly, and no way for the TTS to know `Szekely` is `Székely`.

## What needs a human decision

`name_display` is the corrected spelling to put back into evolvo. The column below is **my reading of
what the stripped form was before it was stripped** — a proposal for you to confirm, reject or fix,
not an answer. Nothing has been written anywhere. Where I am not confident I have said so rather than
guessed.

| # | `name_raw` in evolvo | proposed `name_display` | confidence | why it matters |
|---|---|---|---|---|
| 1 | `Dr. Ardelean Adina` | `Dr. Ardelean Adina` | certain | RO, no diacritics to restore |
| 2 | `Dr. Baricz Anna` | `Dr. Baricz Anna` | certain | HU, but already correct — no diacritics in it |
| 3 | `Dr. Elekes Ella` | `Dr. Elekes Ella` | certain | HU, already correct |
| 4 | `Dr. Ilovan Anca` | **`Dr. Ilovan Anica`** | **you told me** | not a diacritic — a wrong given name. Confirm before changing |
| 5 | `Dr. Istratuc Dorina` | `Dr. Istratuc Dorina` | certain | RO, already correct |
| 6 | `Dr. Ormenisan Delia Maria` | `Dr. Ormenișan Delia Maria` | high | RO `ș`. Standard surname, stripped |
| 7 | `Dr. Petrea Alexandra` | `Dr. Petrea Alexandra` | certain | RO, already correct |
| 8 | `Dr. Popa Camelia` | `Dr. Popa Camelia` | certain | RO, already correct |
| 9 | `Dr. Prof. Szekely Attila  - Consiliere / Terapie psiho-ortoptica` | `Dr. Prof. Székely Attila - Consiliere / Terapie psiho-ortoptică` | high | HU `é`; RO `ă` on the suffix. **Also has a double space before the dash** |
| 10 | `Dr. Rotar Simona` | `Dr. Rotar Simona` | certain | RO, already correct |
| 11 | `Dr. Tripon Robert` | `Dr. Tripon Robert` | certain | RO, already correct |
| 12 | `Dr. Zait Natalia` | `Dr. Zaiț Natalia` **or** `Dr. Zait Natalia` | **unsure — ask her** | `Zaiț` and `Zait` are both real surnames. Do not guess |
| 13 | `Optometrist Bodi Ildiko` | `Optometrist Bódi Ildikó` | **confirmed by the clinic 2026-09-21** | HU, both `ó` restored |
| 14 | `Optometrist Dan Laura` | `Optometrist Dan Laura` | certain | RO, already correct |
| 15 | `Optometrist Ifj Jeremias Laszlo` | `Optometrist Ifj. Jeremiás László` | high | HU `á`, `ó`. **Note the missing period after `Ifj`** |
| 16 | `Optometrist Jeremias Zoltan` | `Optometrist Jeremiás Zoltán` | high | HU `á`, `á` |

**Six names are wrong today** (4, 6, 9, 13, 15, 16), plus two open questions (12, and `Bodi`/`Bódi`
in 13). Ten are already correct — the job is smaller than it looks.

Two of the six are HU surnames shared by relatives across branches: `Jeremiás Zoltán` and
`Ifj. Jeremiás László` are separate people on separate calendars, and the `Ifj.` is the only thing
distinguishing father from son. Getting the period back matters for the spoken form.

## Order of operations — do not skip ahead

1. **Confirm this table** (you, or whoever at the clinic knows #12 and #13).
2. **Correct the names in evolvo.** Clinic-side, in the admin UI. This is the step everything else
   waits on.
3. **Re-dump the roster** and confirm the corrected spellings actually come back through
   `get_info.php` — evolvo may strip diacritics on write, which would end the whole approach and turn
   this into an `ai_public_names_*` request to Imreh instead. **Check this before doing any dictionary
   work.**
4. **Then** fill `spoken_ro` / `spoken_hu` and build the dictionaries, keyed on the corrected
   graphemes. See the reasoning in
   [`provider-roster-workflow-prompt.md`](provider-roster-workflow-prompt.md).

Step 3 is the one that can kill this. If evolvo normalises on save, the TTS never sees a diacritic
regardless of what the clinic types, and the only remaining route to correct pronunciation is a
dictionary keyed on the stripped spellings — which is fine, but it is a different plan and it should
be chosen deliberately rather than discovered after the clinic has retyped 16 names.

## Matching is not at risk either way

`CA Match Calendars` normalises with `NFD` + strip-combining-marks on both sides before comparing, so
`Székely` and `Szekely` are the same token to it, and a caller saying either still matches. Restoring
diacritics cannot break the fuzzy matcher. Confirmed by reading the live node source, not the stale
export in this repo.

---

## Decided 2026-09-21 — corrected in n8n, not in evolvo

The clinic's call: **Anca → Anica, and Hungarian names get their diacritics back. Nothing else
changes.** Romanian names keep their stripped spellings deliberately (`Ormenisan`, `Zait` stay as
they are), so questions 6 and 12 above are closed as "leave it". Question 13 is answered: it is **`Bódi`**,
confirmed by the clinic. Nothing on the name list is open any more.

Shipped as four `Display Names` nodes in the live workflow — see the
[changelog](CHANGELOG.md) and [`display-names.node.js`](display-names.node.js). The five strings that
change:

| raw in evolvo | returned to ElevenLabs |
|---|---|
| `Dr. Ilovan Anca` | `Dr. Ilovan Anica` |
| `Dr. Prof. Szekely Attila  - Consiliere / Terapie psiho-ortoptica` | `Dr. Prof. Székely Attila - Consiliere / Terapie psiho-ortoptica` |
| `Optometrist Bodi Ildiko` | `Optometrist Bódi Ildikó` |
| `Optometrist Ifj Jeremias Laszlo` | `Optometrist Ifj. Jeremiás László` |
| `Optometrist Jeremias Zoltan` | `Optometrist Jeremiás Zoltán` |

**Evolvo is never written to**, which retires the "does evolvo normalise on save?" risk entirely —
it no longer matters what evolvo does with diacritics, because we never send any.

**The pronunciation dictionaries can now be built.** The blocker was that an alias keys on the
grapheme the TTS actually receives; that grapheme is now settled and stable, because it is produced
by a map in our own workflow rather than by whatever the clinic last typed into evolvo. Key the
dictionaries on the right-hand column above.
