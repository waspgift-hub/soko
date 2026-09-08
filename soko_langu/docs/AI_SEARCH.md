# Soko Vibe — AI Search Engine: Status & Roadmap

**Phase 2 deliverable — Master prompt §3–§14, §53–§62, §85–§88.**

---

## 1. Architecture (current)

```
lib/services/search_service.dart ──POST /api/search/*──▶ server/search.js (Express, Firestore index)
                                                             │  fuzzyCorrect / searchIndex /
                                                             │  runSources / record-click / trending
                                                             ▼
                                           client firestore fallback (index iko empty) + lib search
```

- **Primary engine:** `server/search.js` (inayotumiwa na app). 
- **Duplicate/dead:** `functions/search/query.js` (Cloud Functions — same algorithms, imedrifika,
  Haiwezi kufikia app). **Consolidation ni architecture work — iliyopendekezwa.**
- **Legacy:** `server/src/modules/search/search-service.js` (PostgreSQL/Prisma ILIKE — kwa web, si app).
- **AI chat:** Groq via server proxy (`/api/ai/chat`), db-grounded kwa AI assistant screen – sio kwenye
  search results UI.

## 2. Tulichokamilisha (Phase 2 — tranche 1)

### `server/query-intent.js` (mpya, pure module — ina unit tests)
- **§56 – Price language:** `800k`/`500 K`/`800,000`/`500000`, `nusu milioni` (500,000), `laki 5`,
  `elfu 800`, `milioni 2`, `mil 1.5`, `2m`, **na Kiswahili digit words** (`milioni mbili`, `laki tano`).
- **§57 – Location language:** `dar`/`dsm`/`dar es salaam`→ Dar es Salaam + 14 majors
  (arusha, mwanza, dodoma, mbeya, tanga, zanzibar, morogoro, iringa, songea, tabora, kigoma, moshi, kili).
- **§55 – Synonyms (Sw↔En):** `simu→[phone,mobile]`, `kompyuta→[computer,laptop]`, `gari→car`,
  `jokofu→fridge`, nk (≈24 pairs). Synonyms ni **candidate terms tu** — relevance bado inapima maneno
  ya user kwanza.
- **§4–§7 – Intent parser:** `"simu chini ya 800k dar"` → `{ searchQuery:'simu',
  filters:{ maxPrice:800000, location:'Dar es Salaam' } }`.
- **§06–§07 – Typo confidence:** `isHighConfidence` — auto-apply tu wakati `distance ≤ 2` **na**
  `≤ floor(len/3)`. `samsng→samsung` / `iphne→iphone` HU-apply; `cam → camera` (sepukupambanaia)
  **haiapply** — inaendelea kama suggestion tu.

### `server/search.js` (updates)
- `global-search` sasa inapiga `parseIntent`, ina-rerun high-confidence correction wakati `total===0`,
  inatumia `array-contains-any` na synonyms, na inatumia **location filter** (iliyokuwa haipo).
- Response mpya: `detected: { money, location, maxPrice, minPrice }` + `autoCorrected`.
- Analytics: `recordSearchQuery` inarecord `correctedTo`, `autoCorrected`, `detected` — msingi wa
  **typo/zero-result analytics dashboard** (§53–§54).

### Flutter client
- `SearchResponse` imepanuliwa: `detected` + `autoCorrected`.
- Search-screen header: **banner "Matokeo ya 'samsung'"** wakati correction imeapply, na **chips**
  (`≤ 800K · Dar es Salaam`) za filters zilizogunduliwa — monochrome, token-compliant.
- Translation keys: `showing_results_for` katika EN/SW/ZH.

### Tranche 2 — **G10: AI summary kwenye search UI** (`feat(ai): search summary`)
- `AiService.generateSearchSummary(query, groundedContext, total, locale)` — abstract (+ GroqService impl).
- **Grounding (§8/§9/§58):** context block hujengwa tu kutoka `SearchResult` halisi (jina/bei/muuzaji/eneo/
  rating/SILA); `total` halisi; prompt inaisa "usizidi matokeo" (§62) na kutoa "Best matches" 2–3.
- **Non-blocking (§60):** results hujitokeza mara moja; summary inafika async kwenye card. Failure au
  empty → card inatoweka kimya; hakuna dependecy kwenye results.
- **Rate limiting:** limiter tofauti `ai_search_summary` (60/h) — search haliwezi kuteketeza budget ya
  AI-chat (30/h); client dedupes same-query.
- Localization keys mpya: `ai_summarizing` (EN/SW/ZH).

## 3. Verification

- **Server unit tests: `test/search-intent.test.js` — 20/20 pass** (money parsing, intent, confidence,
  edge cases). Full server suite: **106/106 pass** (`e2e.live` haijapangiwa — inahitaji server running).
- **Flutter: `flutter analyze` zero errors, `flutter test` 145/145 pass.**

## 4. Remaining gaps (ranked) — mapango kwa futura

| # | Gap | Severity | Nini kifanyike |
|---|---|---|---|
| G10 | ~~AI answer kwenye search UI~~ ✅ **Implemented** | HIGH | `AiService.generateSearchSummary` + non-blocking card; streaming + AI-reply chat juu ya summary = future. |
| G8 | **Semantic/vector search** (§86) | HIGH | Embeddings directory + hybrid score (§87). Kifanane na catalog size. |
| G12 | **Suggested-query chips** ("phone under 500k") | MEDIUM | Static premium examples + dynamic top-converting; keyword chips. |
| G11 | **Sort chips** Best Match / Lowest Price / Nearest | MEDIUM | On search results; Nearest inahitaji location consent (§42). |
| G3 | **Analytics dashboard** (top searches, zero-result, typo) | MEDIUM | Raw logs zipo (`search_analytics`) — aggregate + UI ya admin. |
| G5 | **Compare products** (§18) | MEDIUM | CompareScreen tokei picha za select. |
| G6 | **Price-drop trigger from intent** | MEDIUM | Wire `PriceDropService` kwenye detected maxPrice. |
| — | **Consolidate engines** (Express vs functions vs PG) | LOW | Document/remove duplicate; moja tu ya truth. |
| G7/G4 | Personalization & voice in main bar | LOW–MED | Analytics events (view/search/cart) kwenye ranking. |

**Rule ya kudumu (§9/§58):** AI hawezi kubuni bei/stock/wauzaji/rating — yote yatoke kwenye data.