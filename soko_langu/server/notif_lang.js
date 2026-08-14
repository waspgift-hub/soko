// Server-side notification localization.
//
// The app lets users pick sw / en / zh in-app, but every push notification is
// generated on the server as a Swahili template with values already
// interpolated. OneSignal picks the heading language from the device locale,
// which does NOT match the user's in-app choice, so we localize the final
// string server-side instead.
//
// Titles are static so we translate them by exact match. Bodies are
// interpolated at the call site, so we match the Swahili template with a
// regex and rebuild the English/Chinese sentence from the captured values.

const swBodyToEn = [
  // ═══ Boost ═══
  {
    re: /^Boost ya (.+) haikukamilika(\. Sababu: .*)?\. Jaribu tena kwenye app\.$/,
    en: (m) => `Your boost for ${m[1]} did not complete${m[2] ? m[2] : ''}. Try again in the app.`,
  },
  {
    re: /^Bidhaa yako imepandishwa kwa daraja la (.+) kwa siku (\d+)\.$/,
    en: (m) => `Your product has been boosted to ${m[1]} tier for ${m[2]} days.`,
  },
  // ═══ Dispatch / transport ═══
  {
    re: /^(.+) imesafirishwa\. Thibitisha upokeaji ukishapata mzigo\.$/,
    en: (m) => `${m[1]} has been shipped. Confirm receipt once you receive the goods.`,
  },
  {
    re: /^(.+) limetumwa — fuatilia usafirishaji kwenye app\.$/,
    en: (m) => `${m[1]} has been dispatched — track the shipment in the app.`,
  },
  {
    re: /^(.+) ameweka taarifa za usafirishaji\. Tumia hizo taarifa kutuma bidhaa\.$/,
    en: (m) => `${m[1]} has entered shipping details. Use them to send the product.`,
  },
  // ═══ Payout / escrow release ═══
  {
    re: /^TZS (.+) zimetumwa kwa simu yako \(fee TZS (.+)\)\.$/,
    en: (m) => `TZS ${m[1]} has been sent to your phone (fee TZS ${m[2]}).`,
  },
  {
    re: /^TZS (.+) zimetumwa kwenye mobile money yako\.$/,
    en: (m) => `TZS ${m[1]} has been sent to your mobile money.`,
  },
  {
    re: /^TZS (.+) hazikutumwa\. Pesa zimerudishwa kwenye pochi yako\. Jaribu tena\.$/,
    en: (m) => `TZS ${m[1]} was not sent. The money has been returned to your wallet. Try again.`,
  },
  {
    re: /^TZS (.+) zinaandaliwa kutuma kwa (.+)\.$/,
    en: (m) => `TZS ${m[1]} is being prepared to send to ${m[2]}.`,
  },
  {
    re: /^(.+) — TZS (.+) zimewekwa salio lako\.$/,
    en: (m) => `${m[1]} — TZS ${m[2]} has been added to your balance.`,
  },
  {
    re: /^(.+) — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji\.$/,
    en: (m) => `${m[1]} — the escrow period has ended and the money has been released to the seller.`,
  },
  // ═══ Delivery confirmed ═══
  {
    re: /^(.+) — asante kwa kununua ndani ya SokoVibe!$/,
    en: (m) => `${m[1]} — thank you for buying on SokoVibe!`,
  },
  // ═══ Deposit ═══
  {
    re: /^TZS (.+) zimeongezwa kwenye pochi yako\.$/,
    en: (m) => `TZS ${m[1]} has been added to your wallet.`,
  },
  {
    re: /^Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)$/,
    en: (m) => `Your TZS ${m[1]} payment did not complete. Reason: ${m[2]}`,
  },
  // ═══ Order / payment ═══
  {
    re: /^(.+) imeuzwa\. TZS (.+) zimewekwa escrow\.$/,
    en: (m) => `${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa\.$/,
    en: (m) => `Payment for ${m[1]} has been received.`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\.$/,
    en: (m) => `Payment for ${m[1]} has been received and safely placed in escrow.`,
  },
  {
    re: /^Malipo ya (.+) hayakukamilika\. Jaribu tena kwenye app\.$/,
    en: (m) => `Payment for ${m[1]} did not complete. Try again in the app.`,
  },
  // listener.js variants
  {
    re: /^Malipo ya (.+) hayakukamilika\. Fungua app ili ujaribu tena\.$/,
    en: (m) => `Payment for ${m[1]} did not complete. Open the app to try again.`,
  },
  {
    re: /^Fedha za (.+) zimerudishwa kwenye akaunti yako\.$/,
    en: (m) => `Your funds for ${m[1]} have been returned to your account.`,
  },
  // ═══ Refund / cancel / dispute ═══
  {
    re: /^TZS (.+) zimerudishwa kwa (.+)\. Ada ya TZS (.+) imekatwa kwa gharama za payout\.$/,
    en: (m) => `TZS ${m[1]} has been refunded to you for ${m[2]}. A fee of TZS ${m[3]} was deducted for payout costs.`,
  },
  {
    re: /^(.+) imeghairiwa na mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.$/,
    en: (m) => `${m[1]} was cancelled by the buyer. The money has been removed from your pending escrow.`,
  },
  {
    re: /^Mnunuzi amefungua mgogoro kwa (.+)\. Tafadhali wasilisha ushahidi wako\.$/,
    en: (m) => `The buyer opened a dispute for ${m[1]}. Please submit your evidence.`,
  },
  {
    re: /^Tumepokea mgogoro wako kwa (.+)\. Admin atakagua na kutoa uamuzi\.$/,
    en: (m) => `We received your dispute for ${m[1]}. An admin will review and decide.`,
  },
  {
    re: /^Admin ameamua pesa zitolewe kwa muuzaji\. (.+)$/,
    en: (m) => `The admin ruled that the money be released to the seller. ${m[1]}`,
  },
  {
    re: /^Admin ameamua pesa zikutolee\. (.+)$/,
    en: (m) => `The admin ruled that the money be released to you. ${m[1]}`,
  },
  {
    re: /^Refund kamili ya TZS (.+) kwa (.+) imetumwa kwa namba yako\.$/,
    en: (m) => `A full refund of TZS ${m[1]} for ${m[2]} has been sent to your number.`,
  },
  {
    re: /^(.+) imerefundiwa mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.(.*)$/,
    en: (m) => `${m[1]} has been refunded to the buyer. The money has been removed from your pending escrow.${m[2] ? m[2] : ''}`,
  },
  // ═══ KYC ═══
  {
    re: /^(.+) ametuma KYC yake\. Tafadhali kagua\.$/,
    en: (m) => `${m[1]} submitted their KYC. Please review it.`,
  },
  {
    re: /^KYC yako imekataliwa\. Sababu: (.+)\. Wasilisha tena baada ya kurekebisha\.$/,
    en: (m) => `Your KYC was rejected. Reason: ${m[1]}. Resubmit after correcting it.`,
  },
  // ═══ Account ═══
  {
    re: /^Unaonywa \((\d+)\/3\): (.+)\. Ukiingia makosa 3, akaunti itasimamishwa kabisa\.$/,
    en: (m) => `Warning (${m[1]}/3): ${m[2]}. After 3 violations your account will be fully suspended.`,
  },
  // ═══ Flash sale ═══
  {
    re: /^(.+) inauzwa TSh (.+) pekee \(-(\d+)%\)\.$/,
    en: (m) => `${m[1]} is selling for only TSh ${m[2]} (-${m[3]}%).`,
  },
  // ═══ Orders (create/transition) ═══
  {
    re: /^(.+) ametuma agizo la (.+?)(\. Eneo: .+)?\. Toa gharama ya usafirishaji sasa\.$/,
    en: (m) => {
      const loc = m[3] ? m[3].replace(/^\. Eneo: /, '. Location: ') : '';
      return `${m[1]} placed an order for ${m[2]}${loc}. Set the shipping cost now.`;
    },
  },
  {
    re: /^Agizo lako la (.+) limewasilishwa kwa muuzaji\.$/,
    en: (m) => `Your order for ${m[1]} has been submitted to the seller.`,
  },
  {
    re: /^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa\.$/,
    en: (m) => `The seller set the shipping cost${m[2] ? ` of TZS ${m[2]}` : ''}. Pay now.`,
  },
  {
    re: /^Quote yako ya usafirishaji ya TZS (.+) imetumwa kwa (.+)\.$/,
    en: (m) => `Your shipping quote of TZS ${m[1]} was sent to ${m[2]}.`,
  },
];

// Static body strings that never change (used verbatim).
const swStaticBodyToEn = {
  'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.':
    'You are approved to sell products. You can now add new products.',
  'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.':
    'Your account has been suspended. Contact support for more details.',
  'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.':
    'Your account has been restored. You can continue using Soko Vibe.',
  'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.':
    'You have reached 3 warnings and your account has been blocked for violating policy. Contact support.',
};

const swTitleToEn = {
  'Malipo ya Boost Yameshindikana': 'Boost Payment Failed',
  'Bidhaa Imesafirishwa!': 'Product Shipped!',
  'Mnunuzi Amechagua Usafirishaji!': 'Buyer Chose Shipping!',
  'Pesa Zimetumwa Moja kwa Moja!': 'Money Sent Directly!',
  'Escrow Imefunguliwa!': 'Escrow Released!',
  'Umethibitisha Upokeaji': 'Delivery Confirmed',
  'Deposit Imethibitishwa!': 'Deposit Confirmed!',
  'Deposit Imeshindikana': 'Deposit Failed',
  '✅ Boost imewashwa!': 'Boost Activated!',
  'Umepata Mauzo!': 'You Made a Sale!',
  'Malipo Yamekamilika!': 'Payment Completed!',
  'Malipo Yameshindikana': 'Payment Failed',
  'Admin Amefungua Escrow!': 'Admin Released Escrow!',
  '💰 Pesa Zimerudishwa': 'Money Refunded',
  '❌ Oda Imeghairiwa': 'Order Cancelled',
  '⚖️ Mgogoro Umefunguliwa': 'Dispute Opened',
  '⚖️ Uamuzi wa Mgogoro': 'Dispute Resolution',
  '💰 Pesa Zimerudishwa Kamili': 'Full Refund Issued',
  '❌ Mgogoro Umekamilika': 'Dispute Closed',
  'KYC Mpya Imewasilishwa': 'New KYC Submitted',
  'KYC Imekubaliwa!': 'KYC Approved!',
  'KYC Imekataliwa': 'KYC Rejected',
  '💰 Utoaji wa Pesa Umeanzishwa': 'Withdrawal Started',
  'Akaunti Yako Imesitishwa': 'Your Account Was Suspended',
  'Akaunti Yako Imerejeshwa': 'Your Account Was Restored',
  'Escrow Imefunguliwa Kiotomatiki': 'Escrow Auto-Released',
  'Payout imefanikiwa!': 'Payout Successful!',
  '❌ Utoaji wa Pesa Umeshindwa': 'Withdrawal Failed',
  'Agizo Jipya Limewasilishwa!': 'New Order Submitted!',
  'Agizo Limewasilishwa!': 'Order Submitted!',
  'Gharama ya Usafirishaji Imewekwa!': 'Shipping Cost Set!',
  'Quote Imetumwa!': 'Quote Sent!',
  'Agizo Limetumwa!': 'Order Dispatched!',
  'Flash Sale Yako Imeanzishwa!': 'Your Flash Sale Is Live!',
  'Fedha Zimerudishwa': 'Funds Returned',
};

// warning/blocked titles have a dynamic suffix — handled by prefix match below.
const swTitlePrefixToEn = {
  'Onyo ': 'Warning ',
  'Akaunti Yako Imefungwa': 'Your Account Was Blocked',
};

function translateBody(lang, body) {
  if (lang === 'en') {
    if (swStaticBodyToEn[body]) return swStaticBodyToEn[body];
    for (const rule of swBodyToEn) {
      const m = body.match(rule.re);
      if (m) return rule.en(m);
    }
    return body;
  }
  // zh — only static/common messages have a translation; otherwise fall back
  // to English so non-Swahili users never see unlocalized Swahili.
  if (lang === 'zh') {
    const en = translateBody('en', body);
    return en === body ? body : en;
  }
  return body;
}

function translateTitle(lang, title) {
  if (lang === 'en') {
    if (swTitleToEn[title]) return swTitleToEn[title];
    for (const [prefix, enPrefix] of Object.entries(swTitlePrefixToEn)) {
      if (title.startsWith(prefix)) return enPrefix + title.slice(prefix.length);
    }
    return title;
  }
  if (lang === 'zh') {
    const en = translateTitle('en', title);
    return en === title ? title : en;
  }
  return title;
}

/// Localizes a Swahili notification title+body into `lang`.
/// Falls back to the original Swahili string when no translation exists so
/// the push is never empty.
function localizeNotif(lang, title, body) {
  if (!lang || lang === 'sw') return { title, body };
  return { title: translateTitle(lang, title), body: translateBody(lang, body) };
}

module.exports = { localizeNotif };
