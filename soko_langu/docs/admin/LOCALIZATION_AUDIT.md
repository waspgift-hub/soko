# Admin Console — Localization Audit

The admin console is **Kiswahili-first** with English as a runtime toggle. Because
there is no build step, translation happens in the browser: `SW2EN` in
`server/admin/admin.js` is compiled into one longest-match regular expression, and
`applyLang()` rewrites text nodes, placeholders, `title`/`aria-label`/`alt`
attributes, and `<option>` labels whenever `LANG === 'en'`.

A missing phrase therefore fails **silently**: the operator sees Swahili inside an
otherwise English screen. This document records how that risk is measured and
what the current coverage is.

## Why not a full i18n framework

The panel is a static `index.html` + `admin.js` bundle served directly by the API
process, with no bundler and no framework. Introducing a key-based catalog would
mean rewriting ~200 KB of rendering code and every backend-provided label, with
no functional gain. The phrase dictionary keeps the source readable in Kiswahili
and still produces English output on demand.

Rules that keep it correct:

1. **Full sentences beat fragments.** Entries are sorted by key length, so
   `'Agizo limefungwa kwa marejesho.'` wins over `'Agizo'`. Whenever a short label
   is a valid key but also appears inside a sentence, add the full-sentence entry
   too — otherwise English output becomes mixed-language.
2. **Dynamic strings need prefix/suffix keys.** Confirm dialogs built as
   `'Tengeneza marejesho kwenda ' + num` can only match the prefix.
3. **HTML in a key never matches.** The DOM splits `<b>` tags into separate text
   nodes, so keys containing markup must be broken into the surrounding
   fragments.
4. **Values may use single or double quotes.** Any parser (including the audit
   script) must handle both.

## The audit script

`server/scripts/i18n-admin-audit.js` reproduces the browser's translator in Node
and scans every user-visible fragment in `admin/admin.js` and `admin/index.html`.

```powershell
cd soko_langu/server
node scripts/i18n-admin-audit.js          # human report, exit 1 on real gaps
node scripts/i18n-admin-audit.js --json   # machine-readable
```

It reports two classes:

| Class | Meaning | Fails the run |
| --- | --- | --- |
| **Definite gap** | After translation the fragment still contains a Swahili function word (from a curated marker list). | Yes |
| **Possible gap** | Words outside the English vocabulary harvested from the dictionary's own translations. Usually proper nouns, enum values or intentional technical labels. | No (advisory) |

The "possible" class is deliberately advisory: `super_admin`, `wallet_credited`,
`API rate limit /min` and the Firebase project ids are correct as-is. Treat the
list as a review queue, not a failure.

## Current state

| Metric | Value |
| --- | --- |
| Dictionary entries (`SW2EN`) | 700 |
| Fragments scanned (JS + HTML) | 2,144 |
| Definite Swahili gaps | **0** |
| Possible gaps (reviewed, intentional) | 5 |
| English words left in Kiswahili source | **0** |

The five remaining "possible" entries are identifiers or English-only labels:

- `super_admin`, `wallet_credited` — role and wallet status enums
- `sokonimoko-8c171-a8d14`, `…firebaseapp.com`, `…firebasestorage.app` — project ids
- `MFA code invalid` — English technical label

## Source-level leak check

`scripts/i18n-admin-audit.js` now also strips the `SW2EN`, `NAV_EN` and
`TITLES_EN` literals and scans the remaining Kiswahili source for English-only
words (a curated list of words that already have a Kiswahili equivalent in this
panel). A hit means a string was written half in English even though `applyLang`
cannot detect it, so the panel shows English to Kiswahili operators. Current
result: **0 leaks**. The test in `test/admin-ui-assets.test.js` asserts both
zero definite gaps and zero leaks.

## Static HTML

`index.html` is not rendered by `admin.js`, so its strings must exist in the
dictionary or be written correctly in the markup. The splash, sign-in heading,
Google restriction hint, legacy-secret hint and theme button were corrected:

| Before | After (Kiswahili) |
| --- | --- |
| `Admin ni inasubiri watumishi.` | `Inapakia dashibodi ya usimamizi…` |
| `Dukani Admin` | `Soko Vibe Admin` |
| `Tumia ADMIN_SECRET (option)` | `Tumia ADMIN_SECRET (hiari)` |

## Maintenance

Run the audit in the same pass as `node scripts/lint.js` whenever admin UI text
changes. Adding a new Kiswahili string means adding its English pair to `SW2EN`
in the same commit; the audit is the check that enforces it.
