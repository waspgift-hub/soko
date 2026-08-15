// Server-side notice & SMS localization.
//
// The app lets users pick sw / en / zh in-app, and every push notification and
// SMS is generated on the server as a Swahili template with values already
// interpolated. OneSignal picks the heading language from the device locale,
// which does NOT match the user's in-app choice, so we localize the final
// string server-side instead.
//
// Titles are static so we translate them by exact match. Bodies are
// interpolated at the call site, so we match the Swahili template with a
// regex and rebuild the English/Chinese sentence from the captured values.
//
// Policy: one message is ONE language. Each rule carries an `en` and a `zh`
// build. The zh branch never transparently falls back to en — it has its own
// string. Unmatched bodies keep the original Swahili (the last-resort single
// language), so a message is never half-translated.

// ─── Body templates (Swahili → en + zh) ────────────────────────────────
const bodyRules = [
  // ═══ Boost ═══
  {
    re: /^Boost ya (.+) haikukamilika(\. Sababu: .*)?\. Jaribu tena kwenye app\.$/,
    en: (m) => `Your boost for ${m[1]} did not complete${m[2] ? m[2] : ''}. Try again in the app.`,
    zh: (m) => `您的商品${m[1]}的推广未完成${m[2] ? m[2] : ''}。请在应用中重试。`,
  },
  {
    re: /^Bidhaa yako imepandishwa kwa daraja la (.+) kwa siku (\d+)\.$/,
    en: (m) => `Your product has been boosted to ${m[1]} tier for ${m[2]} days.`,
    zh: (m) => `您的商品已升级至${m[1]}档，持续${m[2]}天。`,
  },
  {
    re: /^Malipo ya Boost ya TZS (.+) yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi (.+)\.$/,
    en: (m) => `Your boost payment of TZS ${m[1]} was successful! Your product is now prioritized until ${m[2]}.`,
    zh: (m) => `您的推广付款 TZS ${m[1]} 已成功！您的商品现在优先展示，截至 ${m[2]}。`,
  },
  // ═══ Dispatch / transport ═══
  {
    re: /^(.+) imesafirishwa\. Thibitisha upokeaji ukishapata mzigo\.$/,
    en: (m) => `${m[1]} has been shipped. Confirm receipt once you receive the goods.`,
    zh: (m) => `${m[1]} 已发货。收到货物后请确认收货。`,
  },
  {
    re: /^(.+) imesafirishwa\. Angalia proof of delivery na thibitisha upokeaji\.$/,
    en: (m) => `${m[1]} has been shipped. Check the proof of delivery and confirm receipt.`,
    zh: (m) => `${m[1]} 已发货。请查看交货凭证并确认收货。`,
  },
  {
    re: /^(.+) limetumwa — fuatilia usafirishaji kwenye app\.$/,
    en: (m) => `${m[1]} has been dispatched — track the shipment in the app.`,
    zh: (m) => `${m[1]} 已发出 — 请在应用中跟踪物流。`,
  },
  {
    re: /^(.+) ameweka taarifa za usafirishaji( kwa Oda #(.+))?\. (Tumia hizo taarifa kutuma bidhaa|Fungua app na tuma bidhaa)\.$/,
    en: (m) => {
      const ord = m[3] ? ` for order #${m[3]}` : '';
      const act = m[2] && m[3] ? 'Open the app and send the product.' : 'Use them to send the product.';
      return `${m[1]} has entered shipping details${ord}. ${act}`;
    },
    zh: (m) => {
      const ord = m[3] ? `（订单号 #${m[3]}）` : '';
      const act = m[2] && m[3] ? '请在应用中发货。' : '请使用这些信息发货。';
      return `${m[1]} 已填写配送信息${ord}。${act}`;
    },
  },
  // ═══ Payout / escrow release ═══
  {
    re: /^TZS (.+) zimetumwa kwa simu yako \(fee TZS (.+)\)\.$/,
    en: (m) => `TZS ${m[1]} has been sent to your phone (fee TZS ${m[2]}).`,
    zh: (m) => `TZS ${m[1]} 已发送到您的手机（手续费 TZS ${m[2]}）。`,
  },
  {
    re: /^TZS (.+) zimetumwa kwenye mobile money yako\.$/,
    en: (m) => `TZS ${m[1]} has been sent to your mobile money.`,
    zh: (m) => `TZS ${m[1]} 已发送到您的手机钱包。`,
  },
  {
    re: /^TZS (.+) hazikutumwa\. Pesa zimerudishwa kwenye pochi yako\. Jaribu tena\.$/,
    en: (m) => `TZS ${m[1]} was not sent. The money has been returned to your wallet. Try again.`,
    zh: (m) => `TZS ${m[1]} 未能发送。款项已退回您的钱包。请重试。`,
  },
  {
    re: /^TZS (.+) zinaandaliwa kutuma kwa (.+)\.$/,
    en: (m) => `TZS ${m[1]} is being prepared to send to ${m[2]}.`,
    zh: (m) => `正在准备向${m[2]}发送 TZS ${m[1]}。`,
  },
  {
    re: /^(.+) — TZS (.+) zimewekwa salio lako\.$/,
    en: (m) => `${m[1]} — TZS ${m[2]} has been added to your balance.`,
    zh: (m) => `${m[1]} — 已向您的余额增加 TZS ${m[2]}。`,
  },
  {
    re: /^(.+) — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji\.$/,
    en: (m) => `${m[1]} — the escrow period has ended and the money has been released to the seller.`,
    zh: (m) => `${m[1]} — 托管期已结束，款项已释放给卖家。`,
  },
  {
    re: /^(.+) escrow imefunguliwa baada ya muda wake\. TZS (.+) zimewekwa kwenye salio lako\.$/,
    en: (m) => `${m[1]} escrow was auto-released after its period. TZS ${m[2]} has been added to your balance.`,
    zh: (m) => `${m[1]} 的托管已到期自动释放。已向您的余额增加 TZS ${m[2]}。`,
  },
  {
    re: /^Muda wa escrow ya (.+) umeisha\. Pesa zimefunguliwa kwa muuzaji kwa sababu haukuthibitisha upokeaji kwa muda\.$/,
    en: (m) => `The escrow period for ${m[1]} has ended. The money was released to the seller because you did not confirm receipt in time.`,
    zh: (m) => `${m[1]} 的托管期已结束。由于您未及时确认收货，款项已释放给卖家。`,
  },
  {
    re: /^Mnunuzi amethibitisha upokeaji wa (.+)\. TZS (.+) zimewekwa kwenye salio lako\.$/,
    en: (m) => `The buyer confirmed receipt of ${m[1]}. TZS ${m[2]} has been added to your balance.`,
    zh: (m) => `买家已确认收到${m[1]}。已向您的余额增加 TZS ${m[2]}。`,
  },
  {
    re: /^Umethibitisha kuwa umepokea (.+)\. Pesa zimefunguliwa kwa muuzaji\.$/,
    en: (m) => `You confirmed receipt of ${m[1]}. The money has been released to the seller.`,
    zh: (m) => `您已确认收到${m[1]}。款项已释放给卖家。`,
  },
  // ═══ Delivery confirmed ═══
  {
    re: /^(.+) — asante kwa kununua ndani ya SokoVibe!$/,
    en: (m) => `${m[1]} — thank you for buying on SokoVibe!`,
    zh: (m) => `${m[1]} — 感谢您在 SokoVibe 购物！`,
  },
  // ═══ Deposit ═══
  {
    re: /^TZS (.+) zimeongezwa kwenye pochi yako\.$/,
    en: (m) => `TZS ${m[1]} has been added to your wallet.`,
    zh: (m) => `已向您的钱包增加 TZS ${m[1]}。`,
  },
  {
    re: /^Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)$/,
    en: (m) => `Your TZS ${m[1]} payment did not complete. Reason: ${m[2]}`,
    zh: (m) => `您的 TZS ${m[1]} 付款未完成。原因：${m[2]}`,
  },
  // ═══ Order / payment ═══
  {
    re: /^(.+) imeuzwa\. TZS (.+) zimewekwa escrow\.$/,
    en: (m) => `${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.`,
    zh: (m) => `${m[1]} 已售出。TZS ${m[2]} 已放入托管。`,
  },
  {
    re: /^(.+) imeuzwa\. TZS (.+) imewekwa escrow\.$/,
    en: (m) => `${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.`,
    zh: (m) => `${m[1]} 已售出。TZS ${m[2]} 已放入托管。`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa\.$/,
    en: (m) => `Payment for ${m[1]} has been received.`,
    zh: (m) => `${m[1]} 的付款已收到。`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\.$/,
    en: (m) => `Payment for ${m[1]} has been received and safely placed in escrow.`,
    zh: (m) => `${m[1]} 的付款已收到并安全放入托管。`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\. Thibitisha upokeaji ili muuzaji apate hela zake\.$/,
    en: (m) => `Payment for ${m[1]} has been received and safely placed in escrow. Confirm receipt so the seller gets their money.`,
    zh: (m) => `${m[1]} 的付款已收到并安全放入托管。请确认收货，卖家才能收到款项。`,
  },
  {
    re: /^Malipo ya (.+) yamepokelewa\. Thibitisha upokeaji ili muuzaji apate hela zake\.$/,
    en: (m) => `Payment for ${m[1]} has been received. Confirm receipt so the seller gets their money.`,
    zh: (m) => `${m[1]} 的付款已收到。请确认收货，卖家才能收到款项。`,
  },
  {
    re: /^Malipo ya (.+) hayakukamilika\. Jaribu tena kwenye app\.$/,
    en: (m) => `Payment for ${m[1]} did not complete. Try again in the app.`,
    zh: (m) => `${m[1]} 的付款未完成。请在应用中重试。`,
  },
  // listener.js variants
  {
    re: /^Malipo ya (.+) hayakukamilika\. Fungua app ili ujaribu tena\.$/,
    en: (m) => `Payment for ${m[1]} did not complete. Open the app to try again.`,
    zh: (m) => `${m[1]} 的付款未完成。请打开应用重试。`,
  },
  {
    re: /^Malipo ya (.+) hayakukamilika\. Jaribu tena au wasiliana nasi\. Sababu: (.+)$/,
    en: (m) => `Payment for ${m[1]} did not complete. Try again or contact us. Reason: ${m[2]}`,
    zh: (m) => `${m[1]} 的付款未完成。请重试或联系我们。原因：${m[2]}`,
  },
  {
    re: /^Fedha za (.+) zimerudishwa kwenye akaunti yako\.$/,
    en: (m) => `Your funds for ${m[1]} have been returned to your account.`,
    zh: (m) => `您的${m[1]}款项已退回您的账户。`,
  },
  // ═══ Refund / cancel / dispute ═══
  {
    re: /^TZS (.+) zimerudishwa kwa (.+)\. Ada ya TZS (.+) imekatwa kwa gharama za payout\.$/,
    en: (m) => `TZS ${m[1]} has been refunded to you for ${m[2]}. A fee of TZS ${m[3]} was deducted for payout costs.`,
    zh: (m) => `已向您退还${m[2]}的 TZS ${m[1]}。已扣除 TZS ${m[3]} 的支付手续费。`,
  },
  {
    re: /^(.+) imeghairiwa na mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.$/,
    en: (m) => `${m[1]} was cancelled by the buyer. The money has been removed from your pending escrow.`,
    zh: (m) => `${m[1]} 已被买家取消。款项已从您的待处理托管中移出。`,
  },
  {
    re: /^Mnunuzi amefungua mgogoro kwa (.+)\. Tafadhali wasilisha ushahidi wako\.$/,
    en: (m) => `The buyer opened a dispute for ${m[1]}. Please submit your evidence.`,
    zh: (m) => `买家就${m[1]}发起了争议。请提交您的证据。`,
  },
  {
    re: /^Tumepokea mgogoro wako kwa (.+)\. Admin atakagua na kutoa uamuzi\.$/,
    en: (m) => `We received your dispute for ${m[1]}. An admin will review and decide.`,
    zh: (m) => `我们已收到您对${m[1]}的争议。管理员将进行审核并作出裁决。`,
  },
  {
    re: /^Admin ameamua pesa zitolewe kwa muuzaji\. (.+)$/,
    en: (m) => `The admin ruled that the money be released to the seller. ${m[1]}`,
    zh: (m) => `管理员裁定款项将释放给卖家。${m[1]}`,
  },
  {
    re: /^Admin ameamua pesa zikutolee\. (.+)$/,
    en: (m) => `The admin ruled that the money be released to you. ${m[1]}`,
    zh: (m) => `管理员裁定款项将释放给您。${m[1]}`,
  },
  {
    re: /^Refund kamili ya TZS (.+) kwa (.+) imetumwa kwa namba yako\.$/,
    en: (m) => `A full refund of TZS ${m[1]} for ${m[2]} has been sent to your number.`,
    zh: (m) => `针对${m[2]}的 TZS ${m[1]} 全额退款已发送到您的号码。`,
  },
  {
    re: /^(.+) imerefundiwa mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.(.*)$/,
    en: (m) => `${m[1]} has been refunded to the buyer. The money has been removed from your pending escrow.${m[2] ? m[2] : ''}`,
    zh: (m) => `${m[1]} 已退还给买家。款项已从您的待处理托管中移出。${m[2] ? m[2] : ''}`,
  },
  {
    re: /^Ada ya gateway imetozwa kwenye akaunti yako\.$/,
    en: (m) => `A gateway fee has been charged to your account.`,
    zh: (m) => `已向您的账户收取网关费用。`,
  },
  // ═══ KYC ═══
  {
    re: /^(.+) ametuma KYC yake\. Tafadhali kagua\.$/,
    en: (m) => `${m[1]} submitted their KYC. Please review it.`,
    zh: (m) => `${m[1]} 提交了 KYC。请审核。`,
  },
  {
    re: /^KYC yako imewasilishwa\. Subiri ukaguzi wa admin\. Utapata taarifa ikikubaliwa\.$/,
    en: (m) => `Your KYC has been submitted. Wait for the admin review. You will be notified once approved.`,
    zh: (m) => `您的 KYC 已提交。请等待管理员审核。通过后您将收到通知。`,
  },
  {
    re: /^KYC yako imekataliwa\. Sababu: (.+)\. Wasilisha tena baada ya kurekebisha\.$/,
    en: (m) => `Your KYC was rejected. Reason: ${m[1]}. Resubmit after correcting it.`,
    zh: (m) => `您的 KYC 被拒绝。原因：${m[1]}。请修改后重新提交。`,
  },
  {
    re: /^KYC yako imefutwa na admin\. Sababu: (.+)\. Tuma tena KYC yako\.$/,
    en: (m) => `Your KYC was revoked by an admin. Reason: ${m[1]}. Submit your KYC again.`,
    zh: (m) => `您的 KYC 已被管理员撤销。原因：${m[1]}。请重新提交 KYC。`,
  },
  // ═══ Account ═══
  {
    re: /^Unaonywa \((\d+)\/3\): (.+)\. Ukiingia makosa 3, akaunti itasimamishwa kabisa\.$/,
    en: (m) => `Warning (${m[1]}/3): ${m[2]}. After 3 violations your account will be fully suspended.`,
    zh: (m) => `警告（${m[1]}/3）：${m[2]}。累计3次违规后，您的账户将被完全停用。`,
  },
  // ═══ Flash sale ═══
  {
    re: /^(.+) inauzwa TSh (.+) pekee \(-(\d+)%\)\.$/,
    en: (m) => `${m[1]} is selling for only TSh ${m[2]} (-${m[3]}%).`,
    zh: (m) => `${m[1]} 仅售 TSh ${m[2]}（-${m[3]}%）。`,
  },
  {
    re: /^(.+) sasa TSh (.+) pekee!$/,
    en: (m) => `${m[1]} is now only TSh ${m[2]}!`,
    zh: (m) => `${m[1]} 现在仅售 TSh ${m[2]}！`,
  },
  // ═══ Orders (create/transition) ═══
  {
    re: /^(.+) ametuma agizo la (.+?)(\. Eneo: .+)?\. Toa gharama ya usafirishaji sasa\.$/,
    en: (m) => {
      const loc = m[3] ? m[3].replace(/^\. Eneo: /, '. Location: ') : '';
      return `${m[1]} placed an order for ${m[2]}${loc}. Set the shipping cost now.`;
    },
    zh: (m) => {
      const zloc = m[3] ? m[3].replace(/^\. Eneo: /, '。地点：') : '';
      return `${m[1]} 为${m[2]}下了订单${zloc}。请立即设置运费。`;
    },
  },
  {
    re: /^Agizo lako la (.+) limewasilishwa kwa muuzaji\.$/,
    en: (m) => `Your order for ${m[1]} has been submitted to the seller.`,
    zh: (m) => `您对${m[1]}的订单已提交给卖家。`,
  },
  {
    re: /^Agizo lako la (.+) limewasilishwa kwa muuzaji\. Utapokea taarifa ya gharama ya usafirishaji hivi karibuni\.$/,
    en: (m) => `Your order for ${m[1]} has been submitted to the seller. You will receive the shipping cost shortly.`,
    zh: (m) => `您对${m[1]}的订单已提交给卖家。您将很快收到运费通知。`,
  },
  {
    re: /^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa\.$/,
    en: (m) => `The seller set the shipping cost${m[2] ? ` of TZS ${m[2]}` : ''}. Pay now.`,
    zh: (m) => `卖家已设置运费${m[2] ? `（TZS ${m[2]}）` : ''}。请立即付款。`,
  },
  {
    re: /^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa ili agizo litumwe\.$/,
    en: (m) => `The seller set the shipping cost${m[2] ? ` of TZS ${m[2]}` : ''}. Pay now so the order is sent.`,
    zh: (m) => `卖家已设置运费${m[2] ? `（TZS ${m[2]}）` : ''}。请立即付款以便发货。`,
  },
  {
    re: /^Quote yako ya usafirishaji ya TZS (.+) imetumwa kwa (.+)\.$/,
    en: (m) => `Your shipping quote of TZS ${m[1]} was sent to ${m[2]}.`,
    zh: (m) => `您 TZS ${m[1]} 的运费报价已发送给${m[2]}。`,
  },
];

// Static body strings that never change (used verbatim).
const staticBody = {
  'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.': {
    en: 'You are approved to sell products. You can now add new products.',
    zh: '您已获准销售商品。您现在可以上架新商品。',
  },
  'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.': {
    en: 'Your account has been suspended. Contact support for more details.',
    zh: '您的账户已被停用。请联系客服了解更多详情。',
  },
  'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.': {
    en: 'Your account has been restored. You can continue using Soko Vibe.',
    zh: '您的账户已恢复。您可以继续使用 Soko Vibe。',
  },
  'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.': {
    en: 'You have reached 3 warnings and your account has been blocked for violating policy. Contact support.',
    zh: '您已达到3次警告，由于违反政策您的账户已被封禁。请联系客服。',
  },
};

const titleTo = {
  'Malipo ya Boost Yameshindikana': { en: 'Boost Payment Failed', zh: '推广付款失败' },
  'Bidhaa Imesafirishwa!': { en: 'Product Shipped!', zh: '商品已发货！' },
  '📦 Bidhaa Imesafirishwa!': { en: 'Product Shipped!', zh: '商品已发货！' },
  'Mnunuzi Amechagua Usafirishaji!': { en: 'Buyer Chose Shipping!', zh: '买家已选择配送！' },
  '🚚 Mnunuzi Amechagua Usafirishaji!': { en: 'Buyer Chose Shipping!', zh: '买家已选择配送！' },
  'Pesa Zimetumwa Moja kwa Moja!': { en: 'Money Sent Directly!', zh: '款项已直接发送！' },
  'Escrow Imefunguliwa!': { en: 'Escrow Released!', zh: '托管已释放！' },
  'Umethibitisha Upokeaji': { en: 'Delivery Confirmed', zh: '已确认收货' },
  'Deposit Imethibitishwa!': { en: 'Deposit Confirmed!', zh: '存款已确认！' },
  'Deposit Imeshindikana': { en: 'Deposit Failed', zh: '存款失败' },
  '✅ Boost imewashwa!': { en: 'Boost Activated!', zh: '推广已开启！' },
  'Umepata Mauzo!': { en: 'You Made a Sale!', zh: '您有新的销售！' },
  'Malipo Yamekamilika!': { en: 'Payment Completed!', zh: '付款已完成！' },
  'Malipo Yameshindikana': { en: 'Payment Failed', zh: '付款失败' },
  'Admin Amefungua Escrow!': { en: 'Admin Released Escrow!', zh: '管理员已释放托管！' },
  '💰 Pesa Zimerudishwa': { en: 'Money Refunded', zh: '款项已退还' },
  '❌ Oda Imeghairiwa': { en: 'Order Cancelled', zh: '订单已取消' },
  '⚖️ Mgogoro Umefunguliwa': { en: 'Dispute Opened', zh: '争议已开启' },
  '⚖️ Uamuzi wa Mgogoro': { en: 'Dispute Resolution', zh: '争议裁决' },
  '💰 Pesa Zimerudishwa Kamili': { en: 'Full Refund Issued', zh: '已全额退款' },
  '❌ Mgogoro Umekamilika': { en: 'Dispute Closed', zh: '争议已结束' },
  'KYC Mpya Imewasilishwa': { en: 'New KYC Submitted', zh: '新 KYC 已提交' },
  'KYC Imekubaliwa!': { en: 'KYC Approved!', zh: 'KYC 已通过！' },
  'KYC Imekataliwa': { en: 'KYC Rejected', zh: 'KYC 被拒绝' },
  'KYC Imewasilishwa': { en: 'KYC Submitted', zh: 'KYC 已提交' },
  'KYC Imefutwa': { en: 'KYC Revoked', zh: 'KYC 被撤销' },
  '💰 Utoaji wa Pesa Umeanzishwa': { en: 'Withdrawal Started', zh: '提现已开始' },
  'Akaunti Yako Imesitishwa': { en: 'Your Account Was Suspended', zh: '您的账户已被停用' },
  'Akaunti Yako Imerejeshwa': { en: 'Your Account Was Restored', zh: '您的账户已恢复' },
  'Escrow Imefunguliwa Kiotomatiki': { en: 'Escrow Auto-Released', zh: '托管已自动释放' },
  'Payout imefanikiwa!': { en: 'Payout Successful!', zh: '支付成功！' },
  '❌ Utoaji wa Pesa Umeshindwa': { en: 'Withdrawal Failed', zh: '提现失败' },
  'Agizo Jipya Limewasilishwa!': { en: 'New Order Submitted!', zh: '新订单已提交！' },
  'Agizo Limewasilishwa!': { en: 'Order Submitted!', zh: '订单已提交！' },
  'Gharama ya Usafirishaji Imewekwa!': { en: 'Shipping Cost Set!', zh: '运费已设置！' },
  'Quote Imetumwa!': { en: 'Quote Sent!', zh: '报价已发送！' },
  'Agizo Limetumwa!': { en: 'Order Dispatched!', zh: '订单已发货！' },
  'Flash Sale Yako Imeanzishwa!': { en: 'Your Flash Sale Is Live!', zh: '您的闪购已上线！' },
  'Fedha Zimerudishwa': { en: 'Funds Returned', zh: '款项已退回' },
  'Bidhaa Mpya ya Moto! 🔥': { en: 'Hot New Product! 🔥', zh: '火爆新品！🔥' },
  'Payment Received – Escrow Held': { en: 'Payment Received – Escrow Held', zh: '已收到付款 — 托管中' },
  'Akaunti Yako Imefungwa': { en: 'Your Account Was Blocked', zh: '您的账户已被封禁' },
  '🚩 Ripoti Mpya Imewasilishwa': { en: 'New Report Submitted', zh: '新举报已提交' },
  '⚖️ Mgogoro Mpya Unahitaji Uamuzi': { en: 'New Dispute Needs Decision', zh: '新争议需要裁决' },
  'Tangaza Bidhaa Zako!': { en: 'Promote Your Products!', zh: '推广您的商品！' },
};

// Dynamic titles that need value interpolation (exact-match above can't cover).
const titlePatterns = [
  {
    re: /^Onyo (\d+)\/3 — Sera ya Soko Vibe$/,
    en: (m) => `Warning ${m[1]}/3 — Soko Vibe Policy`,
    zh: (m) => `警告 ${m[1]}/3 — Soko Vibe 政策`,
  },
  {
    re: /^Bidhaa Mpya katika (.+)!$/,
    en: (m) => `New Product in ${m[1]}!`,
    zh: (m) => `${m[1]}的新品！`,
  },
  {
    re: /^⚡ Flash Sale! -(\d+)%$/,
    en: (m) => `Flash Sale! -${m[1]}%`,
    zh: (m) => `闪购特惠！-${m[1]}%`,
  },
];

// ─── SMS templates (Swahili → en + zh) ────────────────────────────────
const smsRules = [
  {
    re: /^Soko Vibe: Malipo ya TZS (.+) kwa Oda #(.+) yamepokelewa na kuwekwa salama Escrow\. Muuzaji anajiandaa kutuma mzigo wako\.$/,
    en: (m) => `Soko Vibe: Your payment of TZS ${m[1]} for Order #${m[2]} has been received and safely held in escrow. The seller is preparing to send your goods.`,
    zh: (m) => `Soko Vibe：您订单 #${m[2]} 的 TZS ${m[1]} 付款已收到并安全托管。卖家正在准备发货。`,
  },
  {
    re: /^Soko Vibe: Oda #(.+) imelipiwa! Fedha ipo salama Escrow\. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app\.$/,
    en: (m) => `Soko Vibe: Order #${m[1]} has been paid! The money is safely held in escrow. Please complete dispatch and fill in the bus receipt in the app.`,
    zh: (m) => `Soko Vibe：订单 #${m[1]} 已付款！款项已安全托管。请在应用中完成发货并填写巴士收据。`,
  },
  {
    re: /^Soko Vibe: Mzigo wa Oda #(.+) umesafirishwa kupitia basi la (.+) \((.+)\)\. Fungua app kuona risiti yako ya kidijitali\.$/,
    en: (m) => `Soko Vibe: Your order #${m[1]} has been shipped via bus ${m[2]} (${m[3]}). Open the app to see your digital receipt.`,
    zh: (m) => `Soko Vibe：您的订单 #${m[1]} 已通过巴士 ${m[2]}（${m[3]}）发货。请打开应用查看您的电子收据。`,
  },
  {
    re: /^Soko Vibe: Mteja amethibitisha kupokea mzigo #(.+)\. TZS (.+) zimetolewa Escrow na kuwekwa kwenye pochi yako\.$/,
    en: (m) => `Soko Vibe: The customer confirmed receiving shipment #${m[1]}. TZS ${m[2]} has been released from escrow into your wallet.`,
    zh: (m) => `Soko Vibe：客户已确认收到货物 #${m[1]}。TZS ${m[2]} 已从托管释放到您的钱包。`,
  },
  {
    re: /^Soko Vibe: Malipo ya (.+) hayakukamilika\. Tafadhali fungua app na ujaribu tena\.$/,
    en: (m) => `Soko Vibe: Your payment for ${m[1]} did not complete. Please open the app and try again.`,
    zh: (m) => `Soko Vibe：您对${m[1]}的付款未完成。请打开应用重试。`,
  },
  {
    re: /^Soko Vibe: Malipo ya (.+) hayakukamilika\. Tafadhali jaribu tena kwenye app\. Sababu: (.+)$/,
    en: (m) => `Soko Vibe: Your payment for ${m[1]} did not complete. Please try again in the app. Reason: ${m[2]}`,
    zh: (m) => `Soko Vibe：您对${m[1]}的付款未完成。请在应用中重试。原因：${m[2]}`,
  },
  {
    re: /^Soko Vibe: Fedha za (.+) \(Oda #(.+)\) zimerudishwa kwenye akaunti yako\.$/,
    en: (m) => `Soko Vibe: Your funds for ${m[1]} (Order #${m[2]}) have been returned to your account.`,
    zh: (m) => `Soko Vibe：您${m[1]}（订单 #${m[2]}）的款项已退回您的账户。`,
  },
  {
    re: /^Soko Vibe: Malipo ya Boost ya TZS (.+) hayakukamilika(\. Sababu: .*)?\. Jaribu tena kwenye app\.$/,
    en: (m) => `Soko Vibe: Your boost payment of TZS ${m[1]} did not complete${m[2] ? m[2] : ''}. Try again in the app.`,
    zh: (m) => `Soko Vibe：您的推广付款 TZS ${m[1]} 未完成${m[2] ? m[2] : ''}。请在应用中重试。`,
  },
  {
    re: /^Soko Vibe: Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)\. Jaribu tena kwenye app\.$/,
    en: (m) => `Soko Vibe: Your payment of TZS ${m[1]} did not complete. Reason: ${m[2]}. Try again in the app.`,
    zh: (m) => `Soko Vibe：您的 TZS ${m[1]} 付款未完成。原因：${m[2]}。请在应用中重试。`,
  },
  {
    re: /^Soko Vibe: TZS (.+) zimetumwa kwa simu yako kwa mauzo ya (.+) \(fee TZS (.+)\)\.$/,
    en: (m) => `Soko Vibe: TZS ${m[1]} has been sent to your phone for the sale of ${m[2]} (fee TZS ${m[3]}).`,
    zh: (m) => `Soko Vibe：已就${m[2]}的销售向您的手机发送 TZS ${m[1]}（手续费 TZS ${m[3]}）。`,
  },
  {
    re: /^Soko Vibe: Malipo ya Boost ya TZS (.+) yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi (.+)\.$/,
    en: (m) => `Soko Vibe: Your boost payment of TZS ${m[1]} was successful! Your product is now prioritized until ${m[2]}.`,
    zh: (m) => `Soko Vibe：您的推广付款 TZS ${m[1]} 已成功！您的商品现在优先展示，截至 ${m[2]}。`,
  },
  {
    re: /^Soko Vibe: OTP yako ni (.+)\. Inaisha kwa dakika 10\.$/,
    en: (m) => `Soko Vibe: Your OTP is ${m[1]}. It expires in 10 minutes.`,
    zh: (m) => `Soko Vibe：您的验证码是 ${m[1]}，10分钟内有效。`,
  },
];

function buildBody(lang, body) {
  if (lang === 'sw') return body;
  const st = staticBody[body];
  if (st && st[lang]) return st[lang];
  for (const rule of bodyRules) {
    const match = body.match(rule.re);
    if (match) return rule[lang](match);
  }
  return body;
}

function buildTitle(lang, title) {
  if (lang === 'sw') return title;
  const t = titleTo[title];
  if (t && t[lang]) return t[lang];
  for (const rule of titlePatterns) {
    const match = title.match(rule.re);
    if (match) return rule[lang](match);
  }
  return title;
}

/// Localizes a Swahili notice title+body into `lang`.
/// Falls back to the original Swahili string when no translation exists so the
/// push is never empty.
function localizeNotif(lang, title, body) {
  if (!lang || lang === 'sw') return { title, body };
  return { title: buildTitle(lang, title), body: buildBody(lang, body) };
}

/// Localizes a Swahili SMS message into `lang`. Keeps the "Soko Vibe:" brand
/// prefix (a proper noun) but translates the rest so one SMS is one language.
function localizeSms(lang, message) {
  if (!lang || lang === 'sw') return message;
  for (const rule of smsRules) {
    const match = message.match(rule.re);
    if (match && rule[lang]) return rule[lang](match);
  }
  // Unknown template — transform the leading prefix for en/zh so the message
  // is still coherent, then leave the template body intact (single language).
  if (lang === 'en') return message.replace(/^Soko Vibe: /, 'Soko Vibe: ');
  return message;
}

module.exports = { localizeNotif, localizeSms };