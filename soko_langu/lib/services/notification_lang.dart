// Client-side localization for in-app notifications.
//
// Mirrors server/notif_lang.js so the in-app notifications list matches what
// the user chose in the app. Server pushes are localized by the server; the
// Firestore-stored copies are Swahili templates, so we localize them at render
// time using the app's active language (sw / en / zh).

class NotificationLang {
  static const Map<String, _L> _titles = {
    'Malipo ya Boost Yameshindikana': _L('Boost Payment Failed', '推广付款失败'),
    'Bidhaa Imesafirishwa!': _L('Product Shipped!', '商品已发货！'),
    '📦 Bidhaa Imesafirishwa!': _L('Product Shipped!', '商品已发货！'),
    'Mnunuzi Amechagua Usafirishaji!': _L('Buyer Chose Shipping!', '买家已选择配送！'),
    '🚚 Mnunuzi Amechagua Usafirishaji!': _L('Buyer Chose Shipping!', '买家已选择配送！'),
    'Pesa Zimetumwa Moja kwa Moja!': _L('Money Sent Directly!', '款项已直接发送！'),
    'Escrow Imefunguliwa!': _L('Escrow Released!', '托管已释放！'),
    'Umethibitisha Upokeaji': _L('Delivery Confirmed', '已确认收货'),
    'Deposit Imethibitishwa!': _L('Deposit Confirmed!', '存款已确认！'),
    'Deposit Imeshindikana': _L('Deposit Failed', '存款失败'),
    '✅ Boost imewashwa!': _L('Boost Activated!', '推广已开启！'),
    'Umepata Mauzo!': _L('You Made a Sale!', '您有新的销售！'),
    'Malipo Yamekamilika!': _L('Payment Completed!', '付款已完成！'),
    'Malipo Yameshindikana': _L('Payment Failed', '付款失败'),
    'Admin Amefungua Escrow!': _L('Admin Released Escrow!', '管理员已释放托管！'),
    '💰 Pesa Zimerudishwa': _L('Money Refunded', '款项已退还'),
    '❌ Oda Imeghairiwa': _L('Order Cancelled', '订单已取消'),
    '⚖️ Mgogoro Umefunguliwa': _L('Dispute Opened', '争议已开启'),
    '⚖️ Uamuzi wa Mgogoro': _L('Dispute Resolution', '争议裁决'),
    '💰 Pesa Zimerudishwa Kamili': _L('Full Refund Issued', '已全额退款'),
    '❌ Mgogoro Umekamilika': _L('Dispute Closed', '争议已结束'),
    'KYC Mpya Imewasilishwa': _L('New KYC Submitted', '新 KYC 已提交'),
    'KYC Imekubaliwa!': _L('KYC Approved!', 'KYC 已通过！'),
    'KYC Imekataliwa': _L('KYC Rejected', 'KYC 被拒绝'),
    'KYC Imewasilishwa': _L('KYC Submitted', 'KYC 已提交'),
    'KYC Imefutwa': _L('KYC Revoked', 'KYC 被撤销'),
    '💰 Utoaji wa Pesa Umeanzishwa': _L('Withdrawal Started', '提现已开始'),
    'Akaunti Yako Imesitishwa': _L('Your Account Was Suspended', '您的账户已被停用'),
    'Akaunti Yako Imerejeshwa': _L('Your Account Was Restored', '您的账户已恢复'),
    'Escrow Imefunguliwa Kiotomatiki': _L('Escrow Auto-Released', '托管已自动释放'),
    'Payout imefanikiwa!': _L('Payout Successful!', '支付成功！'),
    '❌ Utoaji wa Pesa Umeshindwa': _L('Withdrawal Failed', '提现失败'),
    'Agizo Jipya Limewasilishwa!': _L('New Order Submitted!', '新订单已提交！'),
    'Agizo Limewasilishwa!': _L('Order Submitted!', '订单已提交！'),
    'Gharama ya Usafirishaji Imewekwa!': _L('Shipping Cost Set!', '运费已设置！'),
    'Quote Imetumwa!': _L('Quote Sent!', '报价已发送！'),
    'Agizo Limetumwa!': _L('Order Dispatched!', '订单已发货！'),
    'Flash Sale Yako Imeanzishwa!': _L('Your Flash Sale Is Live!', '您的闪购已上线！'),
    'Fedha Zimerudishwa': _L('Funds Returned', '款项已退回'),
    'Bidhaa Mpya ya Moto! 🔥': _L('Hot New Product! 🔥', '火爆新品！🔥'),
    'Payment Received – Escrow Held': _L('Payment Received – Escrow Held', '已收到付款 — 托管中'),
    'Akaunti Yako Imefungwa': _L('Your Account Was Blocked', '您的账户已被封禁'),
    '🚩 Ripoti Mpya Imewasilishwa': _L('New Report Submitted', '新举报已提交'),
    '⚖️ Mgogoro Mpya Unahitaji Uamuzi': _L('New Dispute Needs Decision', '新争议需要裁决'),
    'Tangaza Bidhaa Zako!': _L('Promote Your Products!', '推广您的商品！'),
  };

  static const Map<String, _L> _staticBodies = {
    'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.': _L(
      'You are approved to sell products. You can now add new products.',
      '您已获准销售商品。您现在可以上架新商品。',
    ),
    'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.': _L(
      'Your account has been suspended. Contact support for more details.',
      '您的账户已被停用。请联系客服了解更多详情。',
    ),
    'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.': _L(
      'Your account has been restored. You can continue using Soko Vibe.',
      '您的账户已恢复。您可以继续使用 Soko Vibe。',
    ),
    'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.': _L(
      'You have reached 3 warnings and your account has been blocked for violating policy. Contact support.',
      '您已达到3次警告，由于违反政策您的账户已被封禁。请联系客服。',
    ),
  };

  /// Localizes a Swahili server-stored notification title+body to the user's
  /// in-app language. Falls back to the original Swahili when no translation
  /// exists so a message is never half-translated.
  static ({String title, String body}) localize(
      String lang, String title, String body) {
    if (lang == 'sw') return (title: title, body: body);
    return (
      title: _translateTitle(lang, title),
      body: _translateBody(_staticBodies, _bodyRules, body, zh: lang == 'zh'),
    );
  }

  static String _translateTitle(String lang, String title) {
    final exact = _titles[title];
    if (exact != null) return lang == 'zh' ? exact.zh : exact.en;
    for (final rule in _titlePatterns) {
      final m = RegExp(rule.pattern).firstMatch(title);
      if (m != null) return lang == 'zh' ? rule.zh(m) : rule.en(m);
    }
    return title;
  }

  static String _translateBody(
    Map<String, _L> statics,
    List<({String pattern, _Builder en, _Builder zh})> rules,
    String body, {
    required bool zh,
  }) {
    final st = statics[body];
    if (st != null) return zh ? st.zh : st.en;
    for (final rule in rules) {
      final m = RegExp(rule.pattern).firstMatch(body);
      if (m != null) return zh ? rule.zh(m) : rule.en(m);
    }
    return body;
  }

  static final List<({String pattern, _Builder en, _Builder zh})> _titlePatterns = [
    (pattern: r'^Onyo (\d+)\/3 — Sera ya Soko Vibe$',
      en: (m) => 'Warning ${m[1]}/3 — Soko Vibe Policy',
      zh: (m) => '警告 ${m[1]}/3 — Soko Vibe 政策'),
    (pattern: r'^Bidhaa Mpya katika (.+)!$',
      en: (m) => 'New Product in ${m[1]}!',
      zh: (m) => '${m[1]}的新品！'),
    (pattern: r'^⚡ Flash Sale! -(\d+)%$',
      en: (m) => 'Flash Sale! -${m[1]}%',
      zh: (m) => '闪购特惠！-${m[1]}%'),
  ];

  static final List<({String pattern, _Builder en, _Builder zh})> _bodyRules = [
    // Boost
    (pattern: r'^Boost ya (.+) haikukamilika(?:\. Sababu: (.+))?\. Jaribu tena kwenye app\.$',
      en: (m) => 'Your boost for ${m[1]} did not complete${m[2] != null ? ' because ${m[2]}' : ''}. Try again in the app.',
      zh: (m) => '您的商品${m[1]}的推广未完成${m[2] != null ? '，因为${m[2]}' : ''}。请在应用中重试。'),
    (pattern: r'^Bidhaa yako imepandishwa kwa daraja la (.+) kwa siku (\d+)\.$',
      en: (m) => 'Your product has been boosted to ${m[1]} tier for ${m[2]} days.',
      zh: (m) => '您的商品已升级至${m[1]}档，持续${m[2]}天。'),
    (pattern: r'^Malipo ya Boost ya TZS (.+) yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi (.+)\.$',
      en: (m) => 'Your boost payment of TZS ${m[1]} was successful! Your product is now prioritized until ${m[2]}.',
      zh: (m) => '您的推广付款 TZS ${m[1]} 已成功！您的商品现在优先展示，截至 ${m[2]}。'),
    // Dispatch / transport
    (pattern: r'^(.+) imesafirishwa\. Thibitisha upokeaji ukishapata mzigo\.$',
      en: (m) => '${m[1]} has been shipped. Confirm receipt once you receive the goods.',
      zh: (m) => '${m[1]} 已发货。收到货物后请确认收货。'),
    (pattern: r'^(.+) imesafirishwa\. Angalia proof of delivery na thibitisha upokeaji\.$',
      en: (m) => '${m[1]} has been shipped. Check the proof of delivery and confirm receipt.',
      zh: (m) => '${m[1]} 已发货。请查看交货凭证并确认收货。'),
    (pattern: r'^(.+) limetumwa — fuatilia usafirishaji kwenye app\.$',
      en: (m) => '${m[1]} has been dispatched — track the shipment in the app.',
      zh: (m) => '${m[1]} 已发出 — 请在应用中跟踪物流。'),
    (pattern: r'^(.+) ameweka taarifa za usafirishaji( kwa Oda #(.+))?\. (Tumia hizo taarifa kutuma bidhaa|Fungua app na tuma bidhaa)\.$',
      en: (m) => m[3] != null
          ? '${m[1]} has entered shipping details for order #${m[3]}. Open the app and send the product.'
          : '${m[1]} has entered shipping details. Use them to send the product.',
      zh: (m) => m[3] != null
          ? '${m[1]} 已填写配送信息（订单号 #${m[3]}）。请在应用中发货。'
          : '${m[1]} 已填写配送信息。请使用这些信息发货。'),
    // Payout / escrow release
    (pattern: r'^TZS (.+) zimetumwa kwa simu yako \(fee TZS (.+)\)\.$',
      en: (m) => 'TZS ${m[1]} has been sent to your phone (fee TZS ${m[2]}).',
      zh: (m) => 'TZS ${m[1]} 已发送到您的手机（手续费 TZS ${m[2]}）。'),
    (pattern: r'^(.+) — TZS (.+) zimetumwa kwa simu yako\. Fee ya TZS (.+) imekatwa\.$',
      en: (m) => '${m[1]} — TZS ${m[2]} has been sent to your phone. A fee of TZS ${m[3]} was deducted.',
      zh: (m) => '${m[1]} — TZS ${m[2]} 已发送到您的手机。已扣除 TZS ${m[3]} 的手续费。'),
    (pattern: r'^TZS (.+) zimetumwa kwenye mobile money yako\.$',
      en: (m) => 'TZS ${m[1]} has been sent to your mobile money.',
      zh: (m) => 'TZS ${m[1]} 已发送到您的手机钱包。'),
    (pattern: r'^TZS (.+) hazikutumwa\. Pesa zimerudishwa kwenye pochi yako\. Jaribu tena\.$',
      en: (m) => 'TZS ${m[1]} was not sent. The money has been returned to your wallet. Try again.',
      zh: (m) => 'TZS ${m[1]} 未能发送。款项已退回您的钱包。请重试。'),
    (pattern: r'^TZS (.+) zinaandaliwa kutuma kwa (.+)\.$',
      en: (m) => 'TZS ${m[1]} is being prepared to send to ${m[2]}.',
      zh: (m) => '正在准备向${m[2]}发送 TZS ${m[1]}。'),
    (pattern: r'^(.+) — TZS (.+) zimewekwa salio lako\.$',
      en: (m) => '${m[1]} — TZS ${m[2]} has been added to your balance.',
      zh: (m) => '${m[1]} — 已向您的余额增加 TZS ${m[2]}。'),
    (pattern: r'^(.+) — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji\.$',
      en: (m) => '${m[1]} — the escrow period has ended and the money has been released to the seller.',
      zh: (m) => '${m[1]} — 托管期已结束，款项已释放给卖家。'),
    (pattern: r'^(.+) escrow imefunguliwa baada ya muda wake\. TZS (.+) zimewekwa kwenye salio lako\.$',
      en: (m) => '${m[1]} escrow was auto-released after its period. TZS ${m[2]} has been added to your balance.',
      zh: (m) => '${m[1]} 的托管已到期自动释放。已向您的余额增加 TZS ${m[2]}。'),
    (pattern: r'^Muda wa escrow ya (.+) umeisha\. Pesa zimefunguliwa kwa muuzaji kwa sababu haukuthibitisha upokeaji kwa muda\.$',
      en: (m) => 'The escrow period for ${m[1]} has ended. The money was released to the seller because you did not confirm receipt in time.',
      zh: (m) => '${m[1]} 的托管期已结束。由于您未及时确认收货，款项已释放给卖家。'),
    (pattern: r'^Mnunuzi amethibitisha upokeaji wa (.+)\. TZS (.+) zimewekwa kwenye salio lako\.$',
      en: (m) => 'The buyer confirmed receipt of ${m[1]}. TZS ${m[2]} has been added to your balance.',
      zh: (m) => '买家已确认收到${m[1]}。已向您的余额增加 TZS ${m[2]}。'),
    (pattern: r'^Umethibitisha kuwa umepokea (.+)\. Pesa zimefunguliwa kwa muuzaji\.$',
      en: (m) => 'You confirmed receipt of ${m[1]}. The money has been released to the seller.',
      zh: (m) => '您已确认收到${m[1]}。款项已释放给卖家。'),
    // Delivery confirmed
    (pattern: r'^(.+) — asante kwa kununua ndani ya SokoVibe!$',
      en: (m) => '${m[1]} — thank you for buying on SokoVibe!',
      zh: (m) => '${m[1]} — 感谢您在 SokoVibe 购物！'),
    // Deposit
    (pattern: r'^TZS (.+) zimeongezwa kwenye pochi yako\.$',
      en: (m) => 'TZS ${m[1]} has been added to your wallet.',
      zh: (m) => '已向您的钱包增加 TZS ${m[1]}。'),
    (pattern: r'^Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)$',
      en: (m) => 'Your TZS ${m[1]} payment did not complete because ${m[2]}',
      zh: (m) => '您的 TZS ${m[1]} 付款未完成，因为${m[2]}'),
    // Order / payment
    (pattern: r'^(.+) imeuzwa\. TZS (.+) zimewekwa escrow\.$',
      en: (m) => '${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.',
      zh: (m) => '${m[1]} 已售出。TZS ${m[2]} 已放入托管。'),
    (pattern: r'^(.+) imeuzwa\. TZS (.+) imewekwa escrow\.$',
      en: (m) => '${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.',
      zh: (m) => '${m[1]} 已售出。TZS ${m[2]} 已放入托管。'),
    (pattern: r'^Malipo ya (.+) yamepokelewa\.$',
      en: (m) => 'Payment for ${m[1]} has been received.',
      zh: (m) => '${m[1]} 的付款已收到。'),
    (pattern: r'^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\.$',
      en: (m) => 'Payment for ${m[1]} has been received and safely placed in escrow.',
      zh: (m) => '${m[1]} 的付款已收到并安全放入托管。'),
    (pattern: r'^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\. Thibitisha upokeaji ili muuzaji apate hela zake\.$',
      en: (m) => 'Payment for ${m[1]} has been received and safely placed in escrow. Confirm receipt so the seller gets their money.',
      zh: (m) => '${m[1]} 的付款已收到并安全放入托管。请确认收货，卖家才能收到款项。'),
    (pattern: r'^Malipo ya (.+) yamepokelewa\. Thibitisha upokeaji ili muuzaji apate hela zake\.$',
      en: (m) => 'Payment for ${m[1]} has been received. Confirm receipt so the seller gets their money.',
      zh: (m) => '${m[1]} 的付款已收到。请确认收货，卖家才能收到款项。'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Jaribu tena kwenye app\.$',
      en: (m) => 'Payment for ${m[1]} did not complete. Try again in the app.',
      zh: (m) => '${m[1]} 的付款未完成。请在应用中重试。'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Fungua app ili ujaribu tena\.$',
      en: (m) => 'Payment for ${m[1]} did not complete. Open the app to try again.',
      zh: (m) => '${m[1]} 的付款未完成。请打开应用重试。'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Jaribu tena au wasiliana nasi\. Sababu: (.+)$',
      en: (m) => 'Payment for ${m[1]} did not complete because ${m[2]}. Try again or contact us.',
      zh: (m) => '${m[1]} 的付款未完成，因为${m[2]}。请重试或联系我们。'),
    (pattern: r'^Fedha za (.+) zimerudishwa kwenye akaunti yako\.$',
      en: (m) => 'Your funds for ${m[1]} have been returned to your account.',
      zh: (m) => '您的${m[1]}款项已退回您的账户。'),
    // Refund / cancel / dispute
    (pattern: r'^TZS (.+) zimerudishwa kwa (.+)\. Ada ya TZS (.+) imekatwa kwa gharama za payout\.$',
      en: (m) => 'TZS ${m[1]} has been refunded to you for ${m[2]}. A fee of TZS ${m[3]} was deducted for payout costs.',
      zh: (m) => '已向您退还${m[2]}的 TZS ${m[1]}。已扣除 TZS ${m[3]} 的支付手续费。'),
    (pattern: r'^(.+) imeghairiwa na mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.$',
      en: (m) => '${m[1]} was cancelled by the buyer. The money has been removed from your pending escrow.',
      zh: (m) => '${m[1]} 已被买家取消。款项已从您的待处理托管中移出。'),
    (pattern: r'^Mnunuzi amefungua mgogoro kwa (.+)\. Tafadhali wasilisha ushahidi wako\.$',
      en: (m) => 'The buyer opened a dispute for ${m[1]}. Please submit your evidence.',
      zh: (m) => '买家就${m[1]}发起了争议。请提交您的证据。'),
    (pattern: r'^Tumepokea mgogoro wako kwa (.+)\. Admin atakagua na kutoa uamuzi\.$',
      en: (m) => 'We received your dispute for ${m[1]}. An admin will review and decide.',
      zh: (m) => '我们已收到您对${m[1]}的争议。管理员将进行审核并作出裁决。'),
    (pattern: r'^Admin ameamua pesa zitolewe kwa muuzaji\. ?(.+)?$',
      en: (m) => 'The admin ruled that the money be released to the seller.${m[1] != null ? ' ${m[1]}' : ''}',
      zh: (m) => '管理员裁定款项将释放给卖家。${m[1] ?? ''}'),
    (pattern: r'^Admin ameamua pesa zikutolee\. ?(.+)?$',
      en: (m) => 'The admin ruled that the money be released to you.${m[1] != null ? ' ${m[1]}' : ''}',
      zh: (m) => '管理员裁定款项将释放给您。${m[1] ?? ''}'),
    (pattern: r'^Refund kamili ya TZS (.+) kwa (.+) imetumwa kwa namba yako\.$',
      en: (m) => 'A full refund of TZS ${m[1]} for ${m[2]} has been sent to your number.',
      zh: (m) => '针对${m[2]}的 TZS ${m[1]} 全额退款已发送到您的号码。'),
    (pattern: r'^(.+) imerefundiwa mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.(.*)$',
      en: (m) => '${m[1]} has been refunded to the buyer. The money has been removed from your pending escrow.${m[2] ?? ''}',
      zh: (m) => '${m[1]} 已退还给买家。款项已从您的待处理托管中移出。${m[2] ?? ''}'),
    (pattern: r'^Ada ya gateway imetozwa kwenye akaunti yako\.$',
      en: (m) => 'A gateway fee has been charged to your account.',
      zh: (m) => '已向您的账户收取网关费用。'),
    // KYC
    (pattern: r'^(.+) ametuma KYC yake\. Tafadhali kagua\.$',
      en: (m) => '${m[1]} submitted their KYC. Please review it.',
      zh: (m) => '${m[1]} 提交了 KYC。请审核。'),
    (pattern: r'^KYC yako imewasilishwa\. Subiri ukaguzi wa admin\. Utapata taarifa ikikubaliwa\.$',
      en: (m) => 'Your KYC has been submitted. Wait for the admin review. You will be notified once approved.',
      zh: (m) => '您的 KYC 已提交。请等待管理员审核。通过后您将收到通知。'),
    (pattern: r'^KYC yako imekataliwa\. Sababu: (.+)\. Wasilisha tena baada ya kurekebisha\.$',
      en: (m) => 'Your KYC was rejected because ${m[1]}. Resubmit after correcting it.',
      zh: (m) => '您的 KYC 被拒绝，因为${m[1]}。请修改后重新提交。'),
    (pattern: r'^KYC yako imefutwa na admin\. Sababu: (.+)\. Tuma tena KYC yako\.$',
      en: (m) => 'Your KYC was revoked by an admin because ${m[1]}. Submit your KYC again.',
      zh: (m) => '您的 KYC 已被管理员撤销，因为${m[1]}。请重新提交 KYC。'),
    // Account
    (pattern: r'^Unaonywa \((\d+)\/3\): (.+)\. Ukiingia makosa 3, akaunti itasimamishwa kabisa\.$',
      en: (m) => 'Warning (${m[1]}/3): ${m[2]}. After 3 violations your account will be fully suspended.',
      zh: (m) => '警告（${m[1]}/3）：${m[2]}。累计3次违规后，您的账户将被完全停用。'),
    // Flash sale
    (pattern: r'^(.+) inauzwa TSh (.+) pekee \(-(\d+)%\)\.$',
      en: (m) => '${m[1]} is selling for only TSh ${m[2]} (-${m[3]}%).',
      zh: (m) => '${m[1]} 仅售 TSh ${m[2]}（-${m[3]}%）。'),
    (pattern: r'^(.+) sasa TSh (.+) pekee!$',
      en: (m) => '${m[1]} is now only TSh ${m[2]}!',
      zh: (m) => '${m[1]} 现在仅售 TSh ${m[2]}！'),
    // Orders (create/transition)
    (pattern: r'^(.+) ametuma agizo la (.+?)(\. Eneo: .+)?\. Toa gharama ya usafirishaji sasa\.$',
      en: (m) => '${m[1]} placed an order for ${m[2]}${_locTag(m[3])}. Set the shipping cost now.',
      zh: (m) => '${m[1]} 为${m[2]}下了订单${_locTagZh(m[3])}。请立即设置运费。'),
    (pattern: r'^Agizo lako la (.+) limewasilishwa kwa muuzaji\.$',
      en: (m) => 'Your order for ${m[1]} has been submitted to the seller.',
      zh: (m) => '您对${m[1]}的订单已提交给卖家。'),
    (pattern: r'^Agizo lako la (.+) limewasilishwa kwa muuzaji\. Utapokea taarifa ya gharama ya usafirishaji hivi karibuni\.$',
      en: (m) => 'Your order for ${m[1]} has been submitted to the seller. You will receive the shipping cost shortly.',
      zh: (m) => '您对${m[1]}的订单已提交给卖家。您将很快收到运费通知。'),
    (pattern: r'^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa\.$',
      en: (m) => 'The seller set the shipping cost${m[2] != null ? ' of TZS ${m[2]}' : ''}. Pay now.',
      zh: (m) => '卖家已设置运费${m[2] != null ? '（TZS ${m[2]}）' : ''}。请立即付款。'),
    (pattern: r'^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa ili agizo litumwe\.$',
      en: (m) => 'The seller set the shipping cost${m[2] != null ? ' of TZS ${m[2]}' : ''}. Pay now so the order is sent.',
      zh: (m) => '卖家已设置运费${m[2] != null ? '（TZS ${m[2]}）' : ''}。请立即付款以便发货。'),
    (pattern: r'^Quote yako ya usafirishaji ya TZS (.+) imetumwa kwa (.+)\.$',
      en: (m) => 'Your shipping quote of TZS ${m[1]} was sent to ${m[2]}.',
      zh: (m) => '您 TZS ${m[1]} 的运费报价已发送给${m[2]}。'),
  ];

  static String _locTag(String? raw) {
    if (raw == null) return '';
    return raw.replaceFirst(RegExp(r'^\. Eneo: '), '. Location: ');
  }

  static String _locTagZh(String? raw) {
    if (raw == null) return '';
    return raw.replaceFirst(RegExp(r'^\. Eneo: '), '。地点：');
  }
}

class _L {
  final String en;
  final String zh;
  const _L(this.en, this.zh);
}

typedef _Builder = String Function(Match m);