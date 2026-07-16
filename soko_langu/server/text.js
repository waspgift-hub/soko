// ─── Server-side localization for SMS, notifications, and API responses ──
// Usage:
//   const t = require('./text');
//   const msg = await t.forUser(uid, 'payment_success_buyer', { productName, amount });
//   const msg = t.forLang('en', 'otp_send', { otp });

const LANG_CACHE = new Map();
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

const TEXTS = {
  // ─── OTP ────────────────────────────────────────────────────
  otp_send: {
    en: ({ otp }) => `Soko Vibe: Your OTP is ${otp}. It expires in 10 minutes.`,
    sw: ({ otp }) => `Soko Vibe: OTP yako ni ${otp}. Inaisha kwa dakika 10.`,
  },
  otp_sent: {
    en: 'OTP sent to your phone',
    sw: 'OTP imetumwa kwa simu yako',
  },
  otp_failed: {
    en: 'Failed to send OTP. Please try again.',
    sw: 'Imeshindwa kutuma OTP. Jaribu tena.',
  },
  otp_no_otp: {
    en: 'No OTP found. Request a new one.',
    sw: 'Hakuna OTP. Tuma mpya.',
  },
  otp_already_used: {
    en: 'OTP already used',
    sw: 'OTP tayari imetumika',
  },
  otp_expired: {
    en: 'OTP has expired. Request a new one.',
    sw: 'OTP imeisha muda. Tuma mpya.',
  },
  otp_incorrect: {
    en: 'Incorrect OTP',
    sw: 'OTP si sahihi',
  },

  // ─── Payments ────────────────────────────────────────────────
  payment_prompt: {
    en: 'Enter your PIN on your phone to complete payment.',
    sw: 'Tuma PIN yako kwenye simu ili kukamilisha malipo.',
  },
  payment_success_buyer_title: {
    en: 'Payment Successful!',
    sw: 'Malipo Yamekamilika!',
  },
  payment_success_buyer: {
    en: ({ productName, amount }) =>
      `Payment of TZS ${amount?.toLocaleString() || ''} for ${productName || 'item'} received. Confirm receipt to release funds to the seller.`,
    sw: ({ productName, amount }) =>
      `Malipo ya ${productName || 'Bidhaa'} yamepokelewa. Thibitisha upokeaji ili muuzaji apate hela zake.`,
  },
  payment_success_buyer_sms: {
    en: ({ productName, orderId, amount }) =>
      `Soko Vibe: Payment of TZS ${amount?.toLocaleString() || ''} for Order #${orderId} received and held safely in Escrow. The seller is preparing to dispatch your item.`,
    sw: ({ productName, orderId, amount }) =>
      `Soko Vibe: Malipo ya TZS ${amount?.toLocaleString() || ''} kwa Oda #${orderId} yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.`,
  },
  payment_success_seller_title: {
    en: 'You Got a Sale!',
    sw: 'Umepata Mauzo!',
  },
  payment_success_seller: {
    en: ({ productName, amount }) =>
      `${productName || 'Item'} sold. TZS ${amount?.toLocaleString() || ''} placed in escrow. Buyer will confirm receipt to release funds.`,
    sw: ({ productName, amount }) =>
      `${productName || 'Bidhaa'} imeuzwa. TZS ${amount?.toLocaleString() || ''} zimewekwa escrow. Mnunuzi atathibitisha upokeaji ili pesa zifunguliwe.`,
  },
  payment_success_seller_sms: {
    en: ({ orderId }) =>
      `Soko Vibe: Order #${orderId} has been paid! Funds are safely in Escrow. Please complete dispatch at the bus station and upload the bus receipt in the app.`,
    sw: ({ orderId }) =>
      `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`,
  },
  payment_failed_buyer_title: {
    en: 'Payment Failed',
    sw: 'Malipo Yameshindikana',
  },
  payment_failed_buyer: {
    en: ({ productName, reason }) =>
      `Payment for ${productName || 'item'} could not be completed. Please try again or contact support.${reason ? ` Reason: ${reason}` : ''}`,
    sw: ({ productName, reason }) =>
      `Malipo ya ${productName || 'Bidhaa'} hayakukamilika. Jaribu tena au wasiliana nasi.${reason ? ` Sababu: ${reason}` : ''}`,
  },
  payment_failed_buyer_sms: {
    en: ({ productName }) =>
      `Soko Vibe: Payment for ${productName || 'item'} could not be completed. Please try again in the app.`,
    sw: ({ productName }) =>
      `Soko Vibe: Malipo ya ${productName || 'Bidhaa'} hayakukamilika. Tafadhali jaribu tena kwenye app.`,
  },

  // ─── Escrow / Dispatch ───────────────────────────────────────
  dispatch_title: {
    en: '📦 Item Dispatched!',
    sw: '📦 Bidhaa Imesafirishwa!',
  },
  dispatch_notify_buyer: {
    en: ({ productName }) =>
      `${productName || 'Item'} has been dispatched. Check proof of delivery and confirm receipt.`,
    sw: ({ productName }) =>
      `${productName || 'Bidhaa'} imesafirishwa. Angalia proof of delivery na thibitisha upokeaji.`,
  },
  dispatch_sms_buyer: {
    en: ({ orderId, busName, plateNumber }) =>
      `Soko Vibe: Your Order #${orderId} has been dispatched via ${busName || 'bus'} (${plateNumber || ''}). Open the app to see your digital receipt.`,
    sw: ({ orderId, busName, plateNumber }) =>
      `Soko Vibe: Mzigo wa Oda #${orderId} umesafirishwa kupitia basi la ${busName || 'basi'} (${plateNumber || ''}). Fungua app kuona risiti yako ya kidijitali.`,
  },
  dispatch_success: {
    en: 'Item dispatched. Buyer will be notified.',
    sw: 'Bidhaa imesafirishwa. Mnunuzi ataarifiwa.',
  },

  escrow_release_seller_title: {
    en: 'Escrow Released!',
    sw: 'Escrow Imefunguliwa!',
  },
  escrow_release_seller: {
    en: ({ productName, amount }) =>
      `Buyer confirmed receipt of ${productName || 'item'}. TZS ${amount?.toLocaleString() || ''} added to your balance.`,
    sw: ({ productName, amount }) =>
      `Mnunuzi amethibitisha upokeaji wa ${productName || 'Bidhaa'}. TZS ${amount?.toLocaleString() || ''} zimewekwa kwenye salio lako.`,
  },
  escrow_release_seller_sms: {
    en: ({ orderId, amount }) =>
      `Soko Vibe: Buyer confirmed receipt of order #${orderId}. TZS ${amount?.toLocaleString() || ''} released from Escrow to your wallet.`,
    sw: ({ orderId, amount }) =>
      `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${amount?.toLocaleString() || ''} zimetolewa Escrow na kuwekwa kwenye pochi yako.`,
  },
  escrow_release_buyer_title: {
    en: 'Receipt Confirmed',
    sw: 'Umethibitisha Upokeaji',
  },
  escrow_release_buyer: {
    en: ({ productName }) =>
      `You confirmed receipt of ${productName || 'item'}. Funds have been released to the seller.`,
    sw: ({ productName }) =>
      `Umethibitisha kuwa umepokea ${productName || 'Bidhaa'}. Pesa zimefunguliwa kwa muuzaji.`,
  },
  escrow_release_buyer_fcm: {
    en: ({ productName }) =>
      `${productName || 'Item'} — thank you for shopping on SokoVibe!`,
    sw: ({ productName }) =>
      `${productName || 'Bidhaa'} — asante kwa kununua ndani ya SokoVibe!`,
  },
  escrow_released_api: {
    en: 'Escrow released. Seller balance credited.',
    sw: 'Escrow released. Seller balance credited.',
  },

  escrow_auto_release_title: {
    en: 'Escrow Auto-Released',
    sw: 'Escrow Imefunguliwa Kiotomatiki',
  },
  escrow_auto_release_seller: {
    en: ({ productName, amount }) =>
      `Escrow for ${productName || 'item'} has been auto-released. TZS ${amount?.toLocaleString() || ''} added to your balance.`,
    sw: ({ productName, amount }) =>
      `${productName || 'Bidhaa'} escrow imefunguliwa baada ya muda wake. TZS ${amount?.toLocaleString() || ''} zimewekwa kwenye salio lako.`,
  },
  escrow_auto_release_buyer: {
    en: ({ productName }) =>
      `Escrow period for ${productName || 'item'} has ended. Funds released to seller because you did not confirm receipt in time.`,
    sw: ({ productName }) =>
      `Muda wa escrow ya ${productName || 'Bidhaa'} umeisha. Pesa zimefunguliwa kwa muuzaji kwa sababu haukuthibitisha upokeaji kwa muda.`,
  },

  // ─── Boosts ──────────────────────────────────────────────────
  boost_title: {
    en: '✅ Boost Activated!',
    sw: '✅ Boost Imewashwa!',
  },
  boost_activated: {
    en: ({ tier, days }) =>
      `Your product has been boosted to ${tier} tier for ${days} days.`,
    sw: ({ tier, days }) =>
      `Bidhaa yako imepandishwa kwa daraja la ${tier} kwa siku ${days}.`,
  },
  boost_sms: {
    en: ({ amount, expiryStr }) =>
      `Soko Vibe: Boost payment of TZS ${amount?.toLocaleString() || ''} successful! Your product is now shown as featured until ${expiryStr || ''}.`,
    sw: ({ amount, expiryStr }) =>
      `Soko Vibe: Malipo ya Boost ya TZS ${amount?.toLocaleString() || ''} yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi ${expiryStr || ''}.`,
  },
  boost_broadcast_title: {
    en: 'Hot New Product! 🔥',
    sw: 'Bidhaa Mpya ya Moto! 🔥',
  },
  boost_broadcast: {
    en: ({ sellerName }) =>
      `${sellerName || 'A seller'} has boosted a new product, check it out! 🔥`,
    sw: ({ sellerName }) =>
      `${sellerName || 'Muuzaji'} ame-boost bidhaa mpya, angalia sasa! 🔥`,
  },

  // ─── Cancellation / Refund ───────────────────────────────────
  refund_title: {
    en: '💰 Full Refund Sent',
    sw: '💰 Pesa Zimerudishwa Kamili',
  },
  refund_buyer: {
    en: ({ productName, amount }) =>
      `Full refund of TZS ${amount?.toLocaleString() || ''} for ${productName || 'item'} has been sent to your number.`,
    sw: ({ productName, amount }) =>
      `Refund kamili ya TZS ${amount?.toLocaleString() || ''} kwa ${productName || 'Bidhaa'} imetumwa kwa namba yako.`,
  },
  cancel_seller_title: {
    en: '❌ Order Cancelled',
    sw: '❌ Oda Imeghairiwa',
  },
  cancel_seller: {
    en: ({ productName }) =>
      `${productName || 'Item'} was cancelled by the buyer. Funds removed from your pending escrow.`,
    sw: ({ productName }) =>
      `${productName || 'Bidhaa'} imeghairiwa na mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`,
  },
  cancel_response: {
    en: 'Order cancelled. Your money has been refunded.',
    sw: 'Oda imeghairiwa. Hela yako imerudishwa.',
  },

  // ─── Disputes ────────────────────────────────────────────────
  dispute_title: {
    en: '⚖️ Dispute Opened',
    sw: '⚖️ Mgogoro Umefunguliwa',
  },
  dispute_opened_seller: {
    en: ({ productName }) =>
      `A dispute has been opened for ${productName || 'item'}. Please submit your evidence.`,
    sw: ({ productName }) =>
      `Mnunuzi amefungua mgogoro kwa ${productName || 'Bidhaa'}. Tafadhali wasilisha ushahidi wako.`,
  },
  dispute_opened_buyer: {
    en: ({ productName }) =>
      `We have received your dispute for ${productName || 'item'}. Admin will review and make a decision.`,
    sw: ({ productName }) =>
      `Tumepokea mgogoro wako kwa ${productName || 'Bidhaa'}. Admin atakagua na kutoa uamuzi.`,
  },
  dispute_opened_admin_title: {
    en: 'New Dispute Requires Decision',
    sw: 'Mgogoro Mpya Unahitaji Uamuzi',
  },
  dispute_opened_admin: {
    en: ({ productName, orderId }) =>
      `New dispute for ${productName || 'item'} — ${orderId || ''}. Review evidence and make a decision.`,
    sw: ({ productName, orderId }) =>
      `Mgogoro kwa ${productName || 'Bidhaa'} — ${orderId || ''}. Pitia ushahidi na toa uamuzi.`,
  },
  dispute_resolved_title: {
    en: 'Dispute Decision',
    sw: 'Uamuzi wa Mgogoro',
  },
  dispute_refund_seller_title: {
    en: 'Dispute Resolved',
    sw: 'Mgogoro Umekamilika',
  },
  dispute_response: {
    en: 'Dispute opened. Admin will review and make a decision.',
    sw: 'Dispute imefunguliwa. Admin atakagua na kutoa uamuzi.',
  },
  dispute_resolved_seller_win: {
    en: ({ note }) =>
      `Admin ruled in your favor. Funds released to you.${note ? ` ${note}` : ''}`,
    sw: ({ note }) =>
      `Admin ameamua pesa zikutolee.${note ? ` ${note}` : ''}`,
  },
  dispute_resolved_buyer_lose: {
    en: ({ note }) =>
      `Admin ruled funds be released to the seller.${note ? ` ${note}` : ''}`,
    sw: ({ note }) =>
      `Admin ameamua pesa zitolewe kwa muuzaji.${note ? ` ${note}` : ''}`,
  },
  dispute_refund_buyer: {
    en: ({ productName, amount }) =>
      `Full refund of TZS ${amount?.toLocaleString() || ''} for ${productName || 'item'} has been sent to your number.`,
    sw: ({ productName, amount }) =>
      `Refund kamili ya TZS ${amount?.toLocaleString() || ''} kwa ${productName || 'Bidhaa'} imetumwa kwa namba yako.`,
  },
  dispute_refund_seller: {
    en: ({ productName }) =>
      `${productName || 'Item'} has been refunded to the buyer. Funds removed from your pending escrow.`,
    sw: ({ productName }) =>
      `${productName || 'Bidhaa'} imerefundiwa mnunuzi. Pesa zimetolewa kwenye pendingEscrow yako.`,
  },
  dispute_refund_response: {
    en: ({ amount }) =>
      `Full refund of TZS ${amount?.toLocaleString() || ''} sent to buyer's number.`,
    sw: ({ amount }) =>
      `Refund kamili ya TZS ${amount?.toLocaleString() || ''} imetumwa kwa namba ya mnunuzi.`,
  },

  // ─── Withdrawals ─────────────────────────────────────────────
  withdrawal_initiated_title: {
    en: 'Withdrawal Initiated',
    sw: 'Utoaji wa Pesa Umeanzishwa',
  },
  withdrawal_initiated: {
    en: ({ amount, phone }) =>
      `TZS ${amount?.toLocaleString() || ''} is being processed to ${phone || 'your number'}.`,
    sw: ({ amount, phone }) =>
      `TZS ${amount?.toLocaleString() || ''} zinaandaliwa kutuma kwa ${phone || 'namba yako'}.`,
  },
  withdrawal_response: {
    en: ({ amount, phone }) =>
      `TZS ${amount?.toLocaleString() || ''} sent to ${phone || 'your number'}`,
    sw: ({ amount, phone }) =>
      `TZS ${amount?.toLocaleString() || ''} zimetumwa kwa ${phone || 'namba yako'}`,
  },

  // ─── Payouts ─────────────────────────────────────────────────
  payout_success: {
    en: ({ amount }) =>
      `TZS ${amount?.toLocaleString() || ''} has been sent to your mobile money.`,
    sw: ({ amount }) =>
      `TZS ${amount?.toLocaleString() || ''} zimetumwa kwenye mobile money yako.`,
  },
  payout_failed: {
    en: ({ amount }) =>
      `TZS ${amount?.toLocaleString() || ''} could not be sent. Funds returned to your wallet. Please try again.`,
    sw: ({ amount }) =>
      `TZS ${amount?.toLocaleString() || ''} hazikutumwa. Pesa zimerudishwa kwenye pochi yako. Jaribu tena.`,
  },

  // ─── KYC ─────────────────────────────────────────────────────
  kyc_approved_title: {
    en: 'KYC Approved!',
    sw: 'KYC Imekubaliwa!',
  },
  kyc_pending_title: {
    en: 'KYC Needs Review',
    sw: 'KYC Inahitaji Ukaguzi',
  },
  kyc_rejected_title: {
    en: 'KYC Rejected',
    sw: 'KYC Imekataliwa',
  },
  kyc_approved: {
    en: 'You have been approved to sell products. You can now list your items.',
    sw: 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa zako.',
  },
  kyc_pending: {
    en: ({ reason }) =>
      `Your KYC needs corrections: ${reason || 'Please check and resubmit'}. Please resubmit after making corrections.`,
    sw: ({ reason }) =>
      `KYC yako inahitaji marekebisho: ${reason || 'Tafadhali angalia na wasilisha tena'}. Tuma tena baada ya kusahihisha.`,
  },
  kyc_rejected: {
    en: ({ reason }) =>
      `Your KYC was rejected. Reason: ${reason || 'Please contact support'}. Please resubmit after corrections.`,
    sw: ({ reason }) =>
      `KYC yako imekataliwa. Sababu: ${reason || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`,
  },

  // ─── Account ─────────────────────────────────────────────────
  account_suspended_title: {
    en: 'Account Suspended',
    sw: 'Akaunti Yako Imesitishwa',
  },
  account_suspended: {
    en: 'Your account has been suspended. Contact support for more information.',
    sw: 'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.',
  },
  account_unsuspended_title: {
    en: 'Account Restored',
    sw: 'Akaunti Yako Imerejeshwa',
  },
  account_unsuspended: {
    en: 'Your account has been restored. You can now continue using Soko Vibe.',
    sw: 'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.',
  },

  // ─── Flash Sales ─────────────────────────────────────────────
  flash_sale_notification: {
    en: ({ productName, salePrice, discountPercent }) =>
      `⚡ Flash Sale! -${discountPercent || 0}% — ${productName || 'Item'} now TSh ${salePrice || ''} only!`,
    sw: ({ productName, salePrice, discountPercent }) =>
      `⚡ Flash Sale! -${discountPercent || 0}% — ${productName || 'Bidhaa'} sasa TSh ${salePrice || ''} pekee!`,
  },

  // ─── New Product ─────────────────────────────────────────────
  new_product_from_partner: {
    en: ({ sellerName, productName }) =>
      `${sellerName || 'Seller'} has listed a new product: ${productName || 'item'}. You have interacted with them before.`,
    sw: ({ sellerName, productName }) =>
      `${sellerName || 'Muuzaji'} ameweka bidhaa mpya: ${productName || 'bidhaa'}. Umewahi kushirikiana nao hivi karibuni.`,
  },
  new_product_broadcast: {
    en: ({ sellerName, productName }) =>
      `${sellerName || 'Seller'} has listed a new product: ${productName || 'item'}.`,
    sw: ({ sellerName, productName }) =>
      `${sellerName || 'Muuzaji'} ameweka bidhaa mpya: ${productName || 'bidhaa'}.`,
  },

  // ─── Auto-release escrow (listener) ──────────────────────────
  escrow_received_buyer_fcm: {
    en: ({ productName }) =>
      `Your payment for ${productName || 'item'} is held in escrow.`,
    sw: ({ productName }) =>
      `Malipo yako ya ${productName || 'Bidhaa'} yamehifadhiwa escrow.`,
  },
  escrow_dispatched_sms: {
    en: ({ orderId, busName, plateNumber }) =>
      `Soko Vibe: Order #${orderId} dispatched via ${busName || 'bus'} (${plateNumber || ''}). Open the app for your digital receipt.`,
    sw: ({ orderId, busName, plateNumber }) =>
      `Soko Vibe: Mzigo wa Oda #${orderId} umesafirishwa kupitia basi la ${busName || 'basi'} (${plateNumber || ''}). Fungua app kuona risiti yako ya kidijitali.`,
  },
  escrow_delivered_sms: {
    en: ({ orderId, amount }) =>
      `Soko Vibe: Buyer confirmed receipt of order #${orderId}. TZS ${amount?.toLocaleString() || ''} released from Escrow to your wallet.`,
    sw: ({ orderId, amount }) =>
      `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${amount?.toLocaleString() || ''} zimetolewa Escrow na kuwekwa kwenye pochi yako.`,
  },
  escrow_pending_sms_buyer: {
    en: ({ orderId, amount }) =>
      `Soko Vibe: Payment of TZS ${amount?.toLocaleString() || ''} for Order #${orderId} received and held safely in Escrow. The seller is preparing to dispatch your item.`,
    sw: ({ orderId, amount }) =>
      `Soko Vibe: Malipo ya TZS ${amount?.toLocaleString() || ''} kwa Oda #${orderId} yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.`,
  },
  escrow_pending_sms_seller: {
    en: ({ orderId }) =>
      `Soko Vibe: Order #${orderId} has been paid! Funds are safely in Escrow. Please complete dispatch at the bus station and upload the bus receipt in the app.`,
    sw: ({ orderId }) =>
      `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`,
  },
  payment_failed_listener_sms: {
    en: ({ productName }) =>
      `Soko Vibe: Payment for ${productName || 'item'} failed. Please open the app and try again.`,
    sw: ({ productName }) =>
      `Soko Vibe: Malipo ya ${productName || 'Bidhaa'} hayakukamilika. Tafadhali fungua app na ujaribu tena.`,
  },
  refund_listener_sms: {
    en: ({ productName, orderId }) =>
      `Soko Vibe: Funds for ${productName || 'item'} (Order #${orderId}) have been returned to your account.`,
    sw: ({ productName, orderId }) =>
      `Soko Vibe: Fedha za ${productName || 'Bidhaa'} (Oda #${orderId}) zimerudishwa kwenye akaunti yako.`,
  },
  dispute_listener_sms: {
    en: ({ productName, orderId }) =>
      `Soko Vibe: A dispute has been opened for ${productName || 'item'} (Order #${orderId}). Admin will review.`,
    sw: ({ productName, orderId }) =>
      `Soko Vibe: Mgogoro umefunguliwa kwa ${productName || 'Bidhaa'} (Oda #${orderId}). Admin atakagua.`,
  },
};

// ─── Language resolution ──────────────────────────────────────
const DEFAULT_LANG = 'sw';

async function getUserLang(uid) {
  if (!uid) return DEFAULT_LANG;
  const cached = LANG_CACHE.get(uid);
  if (cached && Date.now() - cached.ts < CACHE_TTL) return cached.lang;
  try {
    const admin = require('firebase-admin');
    const snap = await admin.firestore().collection('users').doc(uid).get();
    const lang = snap.data()?.language || DEFAULT_LANG;
    LANG_CACHE.set(uid, { lang, ts: Date.now() });
    return lang;
  } catch {
    return DEFAULT_LANG;
  }
}

// ─── Public API ───────────────────────────────────────────────
module.exports = {
  /** Get text for a specific user (looks up their language preference) */
  async forUser(uid, key, params = {}) {
    const lang = await getUserLang(uid);
    return this.forLang(lang, key, params);
  },

  /** Get text for a specific language code ('en' or 'sw') */
  forLang(lang, key, params = {}) {
    const entry = TEXTS[key];
    if (!entry) return `[missing text: ${key}]`;
    const text = entry[lang] || entry[DEFAULT_LANG];
    if (typeof text === 'function') return text(params);
    return text;
  },

  /** Get text in default language (for non-user-specific messages like API responses) */
  default(key, params = {}) {
    return this.forLang(DEFAULT_LANG, key, params);
  },

  /** Clear language cache (useful for testing) */
  clearCache() {
    LANG_CACHE.clear();
  },
};
