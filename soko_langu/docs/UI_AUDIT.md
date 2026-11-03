# Soko Vibe — UI Audit & Black & White Compliance

**Deliverable A — Master prompt §89–§90.** Audit ya screens za Flutter app (`soko_vibe`) dhidi ya
Black & White premium identity na design tokens za mradi. Status: **in-progress; tranche 1 imekamilika.**

---

## 1. Muhtasari (factual)

- **Architecture ni OK.** Design system tayari ipo na ni kamili: `lib/theme/` (ColorScheme B&W,
  `Ds.*` tokens katika `design_tokens.dart`, `AppRadius`/`AppSpacing`/`AppTypography`), na `lib/widgets/ds/`
  (~28 components: buttons, cards, inputs, chips, badges, skeleton, empty state, bottom nav glass pill).
- **Tatizo halisi si architecture — ni drift.** Screens zingine zitoka kwenye theme kwa kuandika
  colors zao (hex), radii zisizotumia tokens, na shadows nzito.
- **Rangi zenye kuandikwa moja kwa moja zote zimegeuzwa kuwa semantic tokens.**
- **Exception pekee ya intentioned:** `whatsappGreen` (#25D366) — CTA ya "chat on WhatsApp" (sanctioned
  affordance, siio kuvunja B&W), iliyobaki kwenye chat na seller CTA.

---

## 2. Tulichofanya (Tranche 1 — completed)

| Faili | Kabla | Baada |
|---|---|---|
| `lib/screens/chat/chat_page.dart` | WhatsApp clone: scaffold `#0B141A`/`#E5DDD5`, bubbles `#005C4B`/`#DCF8C6`, online `#25D366`, failed `Colors.red` nk. | Semantic tokens zote: `cs.surface`, `cs.primary`, `cs.onPrimary`, `cs.brandSuccess`, `cs.error`, `cs.onSurfaceVariant`, `cs.surfaceContainerHigh`. WhatsApp-green imebaki pale tu inapowakilisha CTA ya WhatsApp. |
| `lib/screens/profile/order_flow_screen.dart` | Rainbow nodes: `#4A90D9`, `#14B8A6`, `#059669`, `#D97706`, `#EA580C`, `#7C3AED`, `#EC4899` (7 rangi). | Monochrome: node zote `cs.primary`; `_FlowNode` hahana tena `color` field. |
| `lib/theme/app_colors.dart` | — | Nyongeza: semantic monochrome ramp `bgCanvas`, `surfaceSubtle`, `surfaceRaised`, `contentPrimary`, `contentSecondary`, `contentMuted`, `hairline` (light/dark) — inakubaliana na spec §63/§64. |

**Verification:** `flutter analyze` **zero errors** (mabadiliko yangu hayana warnings mpya);
`flutter test` **145/145 pass**; line chat_path ya `grep` inathibitisha hakuna hex za WhatsApp zilizosalia
(hata `#25D366` sanijadhiriwa mahali sahihi tu).

---

## 3. Mahali ambapo screens ziliangaliwa na kuthibitishwa OK (hakuna mabadiliko)

- **`home_screen.dart`** — hierarchy tayari premium: gradient line, AI-search bar, brand chips, category
  grid, recently viewed, trending, products grid na skeletons/empty/error states. Radii (16/18/20) ni
  springs/chips — acceptable.
- **`search_screen.dart`** — approval ya results/ad-label, discovery sections, barcode + voice. Emoji
  `'📦'` ni data model (hairender UI moja kwa moja).
- **`seller_dashboard_screen.dart`** — quick-action colors zote ni `cs.primary/secondary/tertiary` +
  `trendingOrange` ambazo **tayari ziko monochrome** (#E4E4E7/#171717). Hakuna violation.
- **`ai_assistant_screen.dart`** — mono accents (Space Grotesk headings, JetBrains Mono labels) ni
  design language (premium pattern), si drift.
- **`legal/*`** — inline `fontSize:26 bold` ni minor; raditi ya summary box ipo.

---

## 4. Roadmap (screens zilizobaki — tranche 2+)

Ukizingatia "don't break business logic" (§81), orodha hii ni ya visual-only:

1. **Consistency sweep ya product cards** (home, search, discovery): shadows/subtle radii nje ya token
   — 1 screen kanuni ya kukagua `product_card.dart`.
2. **`product_detail.dart`, `flash_sale_screen.dart`, `checkout_screen.dart`, `product_reviews_screen.dart`**
   — radii off-token (6/10/14/18) → `AppRadius.*`.
3. **`product_boost_screen.dart` + boost dialogs** — shadows nzito → thin hairlines (§31–§36).
4. **`my_ads`, `help_center`, `bookmark`/wishlist nits** — alpha contrasts.
5. **Accessibility sweep (§72):** hakikisha 44px touch targets kwenye trailing icons (open items
   kutoka audit ya a11y).
6. **Kila screen iliyobaki (~68):** grep `Color(0x` na radius literals — mwongozo wa radiyo: 8/12/16/24.

> Kanuni za mabadiliko ya visual (ili kuijenga trust, si kubadilisha identity):
> **Black = action/emphasis; White = space/content; Gray = hierarchy; Images = energy.**