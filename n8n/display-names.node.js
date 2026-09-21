// Spoken/display provider names. Applied ONLY here, at the very last node before the
// webhook responds, so nothing upstream ever sees a rewritten name.
//
// Why the last node and nowhere else: `MAN rel Find Calendar` matches a cancelled
// appointment back to a calendar with `norm(c.name) === norm(a.doctor)` — an EXACT
// equality after diacritic stripping. Diacritics survive it, but "Anica" vs "Anca"
// does not. Rewriting the name in splitName (the obvious place) would silently turn
// every slot_release_status into `unknown`. So: internal logic keeps the raw evolvo
// name, the caller hears the corrected one.
//
// Matching is unaffected in the other direction too — `CA/BOOK Match Calendars`
// NFD-normalise and strip combining marks on both sides, and the "Anca"->"Anica"
// edit is within the Levenshtein<=2 budget, so the agent may echo a corrected name
// straight back into a tool and it still matches. Verified against all 16 names.
const norm = s => (s || '').toString().toLowerCase().normalize('NFD')
  .replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim();

// Keyed on the normalised RAW evolvo name. Only names that actually change are listed;
// the other ten come back untouched. Romanian names are deliberately left stripped
// (clinic's call, 2026-09-21) — only Hungarian names get their diacritics back.
const DISPLAY = {
  'dr. ilovan anca': 'Dr. Ilovan Anica',                                   // wrong given name, not a diacritic
  'optometrist bodi ildiko': 'Optometrist Bódi Ildikó',
  'optometrist ifj jeremias laszlo': 'Optometrist Ifj. Jeremiás László',   // note the restored period
  'optometrist jeremias zoltan': 'Optometrist Jeremiás Zoltán',
  // Both the split form (what the tools return) and the full raw form (what evolvo stores).
  'dr. prof. szekely attila': 'Dr. Prof. Székely Attila',
  'dr. prof. szekely attila - consiliere / terapie psiho-ortoptica':
    'Dr. Prof. Székely Attila - Consiliere / Terapie psiho-ortoptica',
};

// Every provider name evolvo held on 2026-09-21. A name arriving that is not in here
// means the clinic renamed a calendar and DISPLAY needs revisiting — warn, never fail.
const KNOWN = new Set(['dr. ardelean adina','dr. baricz anna','dr. elekes ella','dr. ilovan anca',
  'dr. istratuc dorina','dr. ormenisan delia maria','dr. petrea alexandra','dr. popa camelia',
  'dr. prof. szekely attila','dr. prof. szekely attila - consiliere / terapie psiho-ortoptica',
  'dr. rotar simona','dr. tripon robert','dr. zait natalia','optometrist bodi ildiko',
  'optometrist dan laura','optometrist ifj jeremias laszlo','optometrist jeremias zoltan']);

// Only keys that carry a provider name. Deliberately NOT a blind walk over every string:
// patient names, observations and free text must never be touched.
const NAME_KEYS = new Set(['doctor', 'available_doctors', 'doctors_at_requested_location',
  'matching_doctors', 'specialty_providers', 'calendar_name']);

const unknown = new Set();
const one = v => {
  if (typeof v !== 'string' || !v) return v;
  const k = norm(v);
  if (DISPLAY[k]) return DISPLAY[k];
  if (!KNOWN.has(k)) unknown.add(v);
  return v;
};
const walk = v => {
  if (Array.isArray(v)) return v.map(walk);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, val] of Object.entries(v)) {
      o[k] = NAME_KEYS.has(k) ? (Array.isArray(val) ? val.map(one) : one(val)) : walk(val);
    }
    return o;
  }
  return v;
};

// Never break a live call over a cosmetic rewrite: on any failure, pass the input through.
return $input.all().map(item => {
  try { return { json: walk(item.json) }; }
  catch (e) { console.log('display-names passthrough:', e.message); return item; }
});
