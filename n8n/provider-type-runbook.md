# Runbook — add `provider_type` to `optofarm-check-availability`

Routes a caller to an **optometrist** (glasses prescription, dioptre check) or a **doctor**
(disease, OCT, eye pressure, urgent) instead of offering whoever is free soonest.

Workflow: **Optofarm_ WIP** · affected chain: `CA Webhook → … → CA Format Slots` (nodes 20–34).
Three Code nodes change. Nothing else in the workflow is touched.

---

## What is already true (verified against the export)

| Fact | Consequence |
|---|---|
| `CA Validate Input` returns a **whitelist**: `{doctor, city, location, date_from, requested_date}` | An unknown `provider_type` in the body is **silently dropped, never rejected**. The ElevenLabs tool already sends it; today it is simply inert. **Main is not at risk** and there is no deadline pressure on this change. |
| `CA Match Calendars` emits **one item per calendar**, then `CA get_work_days.php` fans out over those items | Filtering here shrinks the fan-out — fewer HTTP calls, faster response. |
| `CA Format Slots` pairs `$('CA Match Calendars').all()` with `$input.all()` **by index** | ⚠️ **Filtering must happen in `CA Match Calendars`, never in `CA Format Slots`.** Dropping items in Format Slots would shift the pairing and attach every doctor/location label to the wrong calendar's slots. |
| `CA Match OK?` is `Boolean($json._error) === true` → **out0 = CA Error Out**, out1 = continue | A new error just needs `_error: true` and it routes itself. No rewiring, no new nodes. |
| `CA Webhook` uses `authentication: headerAuth` | The `X-Optofarm-Secret` is an n8n credential. Unrelated to this change. |

### The one assumption you must check first

The export contains **no provider names** — they come live from `get_info.php`, and `pinData` is empty.
So the `Dr.` / `Optometrist` prefix convention is **unverified**. Step 1 exists to verify it.
If the real names don't follow it, stop and adjust `providerKind()` before going further.

---

## Step 0 — Back out point

Workflow menu (⋯) → **Download**. Keep the file. Rollback for every step below is
"paste the old code back", and the three nodes are self-contained.

Work on a **duplicate** of the workflow if you'd rather not touch the live one until Step 6.

---

## Step 1 — Verify the naming convention (do not skip)

Open **`CA get_info.php`** (node 30) and run the CA chain once with any branch, e.g. body
`{"location":"Doja"}`. Inspect the output and list `body.Calendars[].name`.

You are checking that every name starts with either:

- `Dr.` — including compound titles like `Dr. Prof. Szekely Attila - Consiliere / Terapie psiho-ortoptica`
- `Optometrist`

Write down anything that matches neither. The classifier in Step 3 treats unmatched names as
**doctor** (the safer default: worst case an optometrist-suitable caller sees a doctor, never the
reverse). If you find a third pattern — a bare name, `Optom.`, a Hungarian title — adjust the
regexes in `providerKind()` before continuing.

---

## Step 2 — Node `CA Validate Input` (node 21)

Accept and sanitise the new field. **Replace the whole node body:**

```js
const b = ($input.first().json.body) || {};
const str = x => (typeof x === 'string' ? x.trim() : '');
const tzDate = d => new Date(Date.now() + d * 86400000)
  .toLocaleDateString('en-CA', { timeZone: 'Europe/Bucharest' });
let date_from = str(b.date_from);
const today = tzDate(0);
const requested_date = (/^\d{4}-\d{2}-\d{2}$/.test(date_from) && date_from > today) ? date_from : '';
if (!requested_date) date_from = tzDate(1);
// Only these two values survive; anything else (typo, null, "Doctor ", garbage) becomes ''
// which means "no filter" and preserves today's behaviour exactly.
const pt = str(b.provider_type).toLowerCase();
const provider_type = (pt === 'doctor' || pt === 'optometrist') ? pt : '';
return [{ json: { doctor: str(b.doctor), city: str(b.city), location: str(b.location),
  date_from, requested_date, provider_type } }];
```

Only the last three lines are new. A bad value degrades to today's unfiltered behaviour rather
than erroring — the agent is never blocked by a malformed flag.

---

## Step 3 — Node `CA Match Calendars` (node 31)

The real change. **Replace the whole node body:**

```js
const q = $('CA Validate Input').first().json;
const resp = $input.first().json;
if (resp.statusCode !== 200 || !resp.body || !resp.body.Calendars) {
  return [{ json: { _error: true, success: false, error: 'evolvo_api_error', step: 'get_info',
    status: resp.statusCode } }];
}
const norm = s => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const STOP = ['dr','dra','doktor','doctor','doamna','domnul','doctorul','doctorita','medic','medicul','doktornő','doktorno','doktor ur','ur','urnő','urno'];
const words = s => norm(s).split(/[^a-z0-9]+/).filter(w => w && !STOP.includes(w));
const lev = (a, b) => { const m = a.length, n = b.length; if (!m) return n; if (!n) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) { const cur = [i];
    for (let j = 1; j <= n; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur; }
  return prev[n]; };
// A spoken/ASR name token matches a calendar name token when equal, a prefix (>=3 chars), or within a small edit distance.
const tokEq = (q, t) => q === t || (q.length >= 3 && (t.startsWith(q) || q.startsWith(t))) || (q.length >= 3 && lev(q, t) <= (q.length >= 5 ? 2 : 1));
const nameMatch = (query, name) => { const qw = words(query), nw = words(name); return qw.length > 0 && qw.every(q => nw.some(t => tokEq(q, t))); };
// Provider kind, read off the calendar name prefix as evolvo writes it.
// "Optometrist Bodi Ildiko" -> optometrist. "Dr. Baricz Anna", "Dr. Prof. Szekely Attila - ..." -> doctor.
// Anything unrecognised is treated as a doctor: the safe direction to fail in.
const providerKind = name => {
  const n = norm(name).trim();
  if (/^optometrist\b/.test(n)) return 'optometrist';
  return 'doctor';
};
// City / branch aliases as callers say them (RO, HU, ASR variants) -> how evolvo writes the workstation.
const ALIAS = [[/^(targu|tirgu|tg\.?|tg)\s*mures$/, 'tg. mures'], [/^marosvasarhely$/, 'tg. mures'], [/^mures$/, 'tg. mures'],
  [/^(regin|szaszregen|reghin)$/, 'reghin'], [/^(szovata|sovata)$/, 'sovata'],
  [/^(posta utca|postei|posta)$/, 'postei'], [/^(rozsak tere|trandafirilor)$/, 'trandafirilor'],
  [/^(koztarsasag|szentgyorgyter|republicii)$/, 'republicii'], [/^(dozsa|doja|dozsa gyorgy)$/, 'doja'],
  [/^(bulevard|bulevardul|1 decembrie 1918)$/, '1 dec 1918 nr 49']];
const canonPlace = s => { const n = norm(s).replace(/[^a-z0-9. ]+/g, ' ').replace(/\s+/g, ' ').trim(); for (const [re, to] of ALIAS) if (re.test(n)) return to; return n; };
const placeMatch = (query, ws) => { const qn = canonPlace(query), wn = norm(ws); if (!qn) return true; if (wn.includes(qn)) return true; const qw = words(qn); return qw.length > 0 && qw.every(q => words(ws).some(t => tokEq(q, t))); };
const cals = resp.body.Calendars;
if (!q.doctor && !q.location && !q.city) {
  return [{ json: { _error: true, success: false, error: 'missing_target',
    message: 'Ask the caller which branch, city or doctor they want before checking availability. Do not guess one.',
    available_locations: [...new Set(cals.map(c => c.workstation))] } }];
}
let m = cals;
let byDoctor = null;
if (q.doctor) { byDoctor = m.filter(c => nameMatch(q.doctor, c.name)); m = byDoctor; }
if (q.city) m = m.filter(c => placeMatch(q.city, c.workstation));
if (q.location) m = m.filter(c => placeMatch(q.location, c.workstation));
if (m.length === 0 && byDoctor && byDoctor.length > 0) {
  return [{ json: { _error: true, success: false, error: 'doctor_not_at_location',
    message: 'This doctor exists but not at the requested branch. Tell the caller where the doctor works and ask whether that branch suits, or offer another doctor at the requested branch; then call again.',
    doctor: [...new Set(byDoctor.map(c => c.name))],
    doctor_locations: [...new Set(byDoctor.map(c => c.workstation))],
    doctors_at_requested_location: [...new Set(cals.filter(c => placeMatch(q.location || q.city, c.workstation)).map(c => c.name))] } }];
}
// Provider-kind filter. Deliberately skipped when the caller named a specific person:
// an explicit request for Dr. X always beats the visit-type heuristic, so a stray
// provider_type alongside a doctor name can never strand the caller.
if (q.provider_type && !q.doctor) {
  const byType = m.filter(c => providerKind(c.name) === q.provider_type);
  if (byType.length === 0 && m.length > 0) {
    return [{ json: { _error: true, success: false, error: 'no_provider_of_type',
      message: 'Nobody of the requested kind works at that branch. Say so plainly, then offer what IS available there and call again.',
      requested_provider_type: q.provider_type,
      requested_location: q.location || q.city || '',
      available_provider_types: [...new Set(m.map(c => providerKind(c.name)))],
      available_doctors: [...new Set(m.map(c => c.name))],
      available_locations: [...new Set(m.map(c => c.workstation))] } }];
  }
  m = byType;
}
if (m.length === 0) {
  return [{ json: { _error: true, success: false, error: 'no_match',
    message: 'No doctor/location matches. Offer the caller these options (at most three at a time) and call again.',
    available_doctors: [...new Set(cals.map(c => c.name))],
    available_locations: [...new Set(cals.map(c => c.workstation))] } }];
}
// A branch alone can match up to ~8 calendars; query them all so `earliest` works for no-preference callers.
if (m.length > 10) {
  return [{ json: { _error: true, success: false, error: 'too_many_matches',
    message: 'Too many calendars match. Ask the caller to narrow down by doctor or location.',
    matching_doctors: [...new Set(m.map(c => c.name))],
    matching_locations: [...new Set(m.map(c => c.workstation))] } }];
}
return m.map(c => ({ json: { calendarid: c.calendarid, doctor: c.name, location: c.workstation,
  slot_duration: c.slot_duration, provider_type: providerKind(c.name) } }));
```

Three things changed, and the ordering of them is deliberate:

1. **`providerKind()` added** next to the other helpers.
2. **The filter block** sits *after* `doctor_not_at_location` and *before* `no_match` /
   `too_many_matches`. That ordering matters: filtering before the `>10` check lets a
   provider-kind filter rescue an over-broad branch query that would otherwise be rejected,
   and placing it after the empty-set checks would mean `no_match` fires with a misleading
   message when the branch is fine but has nobody of that kind.
3. **`provider_type` added to the emitted item** so `CA Format Slots` can label each result
   without re-parsing the name.

The `_error: true` on `no_provider_of_type` is what routes it through the existing
`CA Match OK?` → `CA Error Out` path. No wiring changes.

> **Note on the regex:** the original `norm` contains a combining-mark range that some editors
> mangle on copy/paste. The version above writes it explicitly as `/[̀-ͯ]/g`, which is
> the same range, paste-safe. If your live node currently works, either form is fine.

---

## Step 4 — Node `CA Format Slots` (node 34)

Surface the kind on every result so the agent reads a field instead of parsing a name.
**Replace the whole node body:**

```js
const cals = $('CA Match Calendars').all();
const resps = $input.all();
const q = $('CA Validate Input').first().json;
const out = [];
let earliest = null;
let requestedDay = null;
for (let i = 0; i < resps.length; i++) {
  const cal = cals[i] ? cals[i].json : {};
  const r = resps[i].json;
  if (r.statusCode !== 200 || !r.body || !r.body.Records) {
    out.push({ doctor: cal.doctor, location: cal.location, provider_type: cal.provider_type,
      error: 'no_availability_data', status: r.statusCode });
    continue;
  }
  const recs = (r.body.Records || []).filter(rec => (rec.free_timespace || []).length > 0);
  const days = recs.slice(0, 4).map(rec => ({
    date: rec.wday,
    free_times: (rec.free_timespace || []).slice(0, 8).map(s => s.slot),
    total_free_slots: (rec.free_timespace || []).length,
  }));
  for (const rec of recs) {
    const t = (rec.free_timespace || [])[0];
    if (!t) continue;
    const key = rec.wday + ' ' + t.slot;
    if (!earliest || key < earliest.date + ' ' + earliest.time) earliest = { date: rec.wday, time: t.slot, doctor: cal.doctor, location: cal.location, provider_type: cal.provider_type };
    if (q.requested_date && rec.wday === q.requested_date) {
      const cand = { date: rec.wday, time: t.slot, doctor: cal.doctor, location: cal.location, provider_type: cal.provider_type, free_times: (rec.free_timespace || []).slice(0, 8).map(s => s.slot) };
      if (!requestedDay || cand.time < requestedDay.time) requestedDay = cand;
    }
  }
  out.push({ doctor: cal.doctor, location: cal.location, provider_type: cal.provider_type,
    slot_duration_minutes: cal.slot_duration, available_days: days });
}
const res = { success: true, date_searched_from: q.date_from, results: out };
if (q.provider_type) res.provider_type_filter = q.provider_type;
if (earliest) res.earliest = earliest;
if (q.requested_date) {
  res.requested_date = q.requested_date;
  res.requested_date_status = requestedDay ? 'available' : 'not_available';
  if (requestedDay) res.requested_date_slots = requestedDay;
}
res.note = 'Times are local Romania time (24h). earliest = the single earliest free slot across all matched calendars; use it for urgent callers or callers with no preference. The system searched the next ~15 working days of each calendar starting from date_searched_from.';
return [{ json: res }];
```

Additions only: `provider_type` on each `results[]` entry, on `earliest`, on
`requested_date_slots`, plus a top-level `provider_type_filter` echo so a failed filter is
visible in the execution log.

**Because the filter ran upstream, `earliest` is now automatically type-correct.** That was the
whole point of doing this server-side rather than letting the agent filter what it's handed —
`earliest` is the field the fast path depends on, and the agent can't recompute it.

---

## Step 5 — Save

Save the workflow. If you worked on a duplicate, activate it and point the
`optofarm-check-availability` webhook path across, or copy the three node bodies into the live one.

No credential, webhook path, or connection changes. The ElevenLabs side is already done —
`provider_type` is live on the tool and the agent may already be sending it.

---

## Step 6 — Test matrix

Run these against the webhook. Every one should pass before you consider this done.

| # | Body | Expect |
|---|---|---|
| 1 | `{"location":"Doja"}` | Unchanged from today. Results include a new `provider_type` on each entry and on `earliest`. **Regression check — run this first.** |
| 2 | `{"location":"Doja","provider_type":"optometrist"}` | Only `Optometrist …` names. `earliest.provider_type === "optometrist"`. `provider_type_filter: "optometrist"`. |
| 3 | `{"location":"Doja","provider_type":"doctor"}` | Only `Dr. …` names. |
| 4 | `{"location":"Reghin","provider_type":"optometrist"}` | Likely `no_provider_of_type` with `available_provider_types: ["doctor"]`. Confirms the new error routes through `CA Error Out`. |
| 5 | `{"doctor":"Baricz","provider_type":"optometrist"}` | **Baricz is still returned.** Named doctor beats the flag — proves the guard. |
| 6 | `{"location":"Doja","provider_type":"DOCTOR "}` | Case/whitespace tolerated → treated as `doctor`. |
| 7 | `{"location":"Doja","provider_type":"nonsense"}` | Falls back to unfiltered, exactly like test 1. Never an error. |
| 8 | `{"provider_type":"doctor"}` | Still `missing_target`. The flag is not a target. |
| 9 | `{"location":"Doja","provider_type":"optometrist","date_from":"<a real future date>"}` | `requested_date_slots.provider_type === "optometrist"`. |

Test 5 is the one people skip and regret. Test 1 is the regression guard.

**These were dry-run before this runbook was written.** The `CA Match Calendars` code above was
executed against synthetic calendars covering all four naming shapes (`Dr. X`, `Dr. Prof. X - long
suffix`, `Optometrist X`, and a multi-branch spread). Cases 1–8 all produced the documented result,
including `Dr. Prof. Szekely Attila - Consiliere / Terapie psiho-ortoptica` classifying as `doctor`
and case 5 returning Baricz despite the conflicting flag. What that does **not** prove is the
naming convention itself — that is Step 1, against live `get_info.php` data.

---

## Deliberately NOT changed

- **`BOOK` chain** — booking is by an explicit slot the caller already accepted; the slot
  determines the provider. Adding a filter there could only reject a valid booking.
  `BOOK Match Calendars` already handles both prefixes: `dr` is in `STOP` so it's ignored as a
  title, and `optometrist` survives as a matchable token against the same name.
- **`FIND` / `MAN` / `LOG` chains** — no provider matching involved.
- **Webhook auth, credentials, connections, node wiring** — untouched.

## Rollback

Paste the three original node bodies back (they're in your Step 0 download) and save.
No data is written by this chain, so there is nothing to undo beyond the code itself.

---

## After it's live

The ElevenLabs prompt does **not** yet instruct the agent when to send `provider_type` —
the tool description does, but the booking procedure doesn't route on visit type. Once tests
1–9 pass, that prompt-side routing is the next piece, and it's the part that actually changes
what callers hear.

Until then the tool description carries a safeguard: the agent must check that the slot it
offers carries the `Dr.` / `Optometrist` prefix it asked for and refuse it otherwise — so a
half-finished backend surfaces as a refusal to offer, not as a doctor booked for a glasses fitting.
