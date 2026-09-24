// Client-side localization for in-app notifications.
//
// Mirrors server/notif_lang.js so the in-app notifications list matches what
// the user chose in the app. Server pushes are localized by the server; the
// Firestore-stored copies are Swahili templates, so we localize them at render
// time using the app's active language (sw / en).

class NotificationLang {
  static const Map<String, _L> _titles = {
    'Bidhaa Imesafirishwa!': _L('Product Shipped!'),
    '📦 Bidhaa Imesafirishwa!': _L('Product Shipped!'),
    'Mnunuzi Amechagua Usafirishaji!': _L('Buyer Chose Shipping!'),
    '🚚 Mnunuzi Amechagua Usafirishaji!': _L('Buyer Chose Shipping!'),
    'Pesa Zimetumwa Moja kwa Moja!': _L('Money Sent Directly!'),
    'Escrow Imefunguliwa!': _L('Escrow Released!'),
    'Umethibitisha Upokeaji': _L('Delivery Confirmed'),
    'Deposit Imethibitishwa!': _L('Deposit Confirmed!'),
    'Deposit Imeshindikana': _L('Deposit Failed'),
    'Umepata Mauzo!': _L('You Made a Sale!'),
    'Malipo Yamekamilika!': _L('Payment Completed!'),
    'Malipo Yameshindikana': _L('Payment Failed'),
    'Admin Amefungua Escrow!': _L('Admin Released Escrow!'),
    '💰 Pesa Zimerudishwa': _L('Money Refunded'),
    '❌ Oda Imeghairiwa': _L('Order Cancelled'),
    '⚖️ Mgogoro Umefunguliwa': _L('Dispute Opened'),
    '⚖️ Uamuzi wa Mgogoro': _L('Dispute Resolution'),
    '💰 Pesa Zimerudishwa Kamili': _L('Full Refund Issued'),
    '❌ Mgogoro Umekamilika': _L('Dispute Closed'),
    'KYC Mpya Imewasilishwa': _L('New KYC Submitted'),
    'KYC Imekubaliwa!': _L('KYC Approved!'),
    'KYC Imekataliwa': _L('KYC Rejected'),
    'KYC Imewasilishwa': _L('KYC Submitted'),
    'KYC Imefutwa': _L('KYC Revoked'),
    '💰 Utoaji wa Pesa Umeanzishwa': _L('Withdrawal Started'),
    'Akaunti Yako Imesitishwa': _L('Your Account Was Suspended'),
    'Akaunti Yako Imerejeshwa': _L('Your Account Was Restored'),
    'Escrow Imefunguliwa Kiotomatiki': _L('Escrow Auto-Released'),
    'Payout imefanikiwa!': _L('Payout Successful!'),
    '❌ Utoaji wa Pesa Umeshindwa': _L('Withdrawal Failed'),
    'Agizo Jipya Limewasilishwa!': _L('New Order Submitted!'),
    'Agizo Limewasilishwa!': _L('Order Submitted!'),
    'Gharama ya Usafirishaji Imewekwa!': _L('Shipping Cost Set!'),
    'Quote Imetumwa!': _L('Quote Sent!'),
    'Agizo Limetumwa!': _L('Order Dispatched!'),
    'Flash Sale Yako Imeanzishwa!': _L('Your Flash Sale Is Live!'),
    'Fedha Zimerudishwa': _L('Funds Returned'),
    'Bidhaa Mpya ya Moto! 🔥': _L('Hot New Product! 🔥'),
    'Payment Received – Escrow Held': _L('Payment Received – Escrow Held'),
    'Akaunti Yako Imefungwa': _L('Your Account Was Blocked'),
    '🚩 Ripoti Mpya Imewasilishwa': _L('New Report Submitted'),
    '⚖️ Mgogoro Mpya Unahitaji Uamuzi': _L('New Dispute Needs Decision'),
    'Tangaza Bidhaa Zako!': _L('Promote Your Products!'),
  };

  static const Map<String, _L> _staticBodies = {
    'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.': _L('You are approved to sell products. You can now add new products.'),
    'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.': _L('Your account has been suspended. Contact support for more details.'),
    'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.': _L('Your account has been restored. You can continue using Soko Vibe.'),
    'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.': _L('You have reached 3 warnings and your account has been blocked for violating policy. Contact support.'),
  };

  /// Localizes a Swahili server-stored notification title+body to the user's
  /// in-app language. Falls back to the original Swahili when no translation
  /// exists so a message is never half-translated.
  static ({String title, String body}) localize(
      String lang, String title, String body) {
    if (lang == 'sw') return (title: title, body: body);
    return (
      title: _translateTitle(lang, title),
      body: _translateBody(_staticBodies, _bodyRules, body),
    );
  }

  static String _translateTitle(String lang, String title) {
    if (lang == 'sw') return title;
    final exact = _titles[title];
    if (exact != null) return exact.en;
    for (final rule in _titlePatterns) {
      final m = RegExp(rule.pattern).firstMatch(title);
      if (m != null) return rule.en(m);
    }
    return title;
  }

  static String _translateBody(
    Map<String, _L> statics,
    List<({String pattern, _Builder en})> rules,
    String body,
  ) {
    final st = statics[body];
    if (st != null) return st.en;
    for (final rule in rules) {
      final m = RegExp(rule.pattern).firstMatch(body);
      if (m != null) return rule.en(m);
    }
    return body;
  }

  static final List<({String pattern, _Builder en})> _titlePatterns = [
    (pattern: r'^Onyo (\d+)\/3 — Sera ya Soko Vibe$',
      en: (m) => 'Warning ${m[1]}/3 — Soko Vibe Policy'),
    (pattern: r'^Bidhaa Mpya katika (.+)!$',
      en: (m) => 'New Product in ${m[1]}!'),
    (pattern: r'^⚡ Flash Sale! -(\d+)%$',
      en: (m) => 'Flash Sale! -${m[1]}%'),
  ];

  static final List<({String pattern, _Builder en})> _bodyRules = [
    // Dispatch / transport
    (pattern: r'^(.+) imesafirishwa\. Thibitisha upokeaji ukishapata mzigo\.$',
      en: (m) => '${m[1]} has been shipped. Confirm receipt once you receive the goods.'),
    (pattern: r'^(.+) imesafirishwa\. Angalia proof of delivery na thibitisha upokeaji\.$',
      en: (m) => '${m[1]} has been shipped. Check the proof of delivery and confirm receipt.'),
    (pattern: r'^(.+) limetumwa — fuatilia usafirishaji kwenye app\.$',
      en: (m) => '${m[1]} has been dispatched — track the shipment in the app.'),
    (pattern: r'^(.+) ameweka taarifa za usafirishaji( kwa Oda #(.+))?\. (Tumia hizo taarifa kutuma bidhaa|Fungua app na tuma bidhaa)\.$',
      en: (m) => m[3] != null
          ? '${m[1]} has entered shipping details for order #${m[3]}. Open the app and send the product.'
          : '${m[1]} has entered shipping details. Use them to send the product.'),
    // Payout / escrow release
    (pattern: r'^TZS (.+) zimetumwa kwa simu yako \(fee TZS (.+)\)\.$',
      en: (m) => 'TZS ${m[1]} has been sent to your phone (fee TZS ${m[2]}).'),
    (pattern: r'^(.+) — TZS (.+) zimetumwa kwa simu yako\. Fee ya TZS (.+) imekatwa\.$',
      en: (m) => '${m[1]} — TZS ${m[2]} has been sent to your phone. A fee of TZS ${m[3]} was deducted.'),
    (pattern: r'^TZS (.+) zimetumwa kwenye mobile money yako\.$',
      en: (m) => 'TZS ${m[1]} has been sent to your mobile money.'),
    (pattern: r'^TZS (.+) hazikutumwa\. Pesa zimerudishwa kwenye pochi yako\. Jaribu tena\.$',
      en: (m) => 'TZS ${m[1]} was not sent. The money has been returned to your wallet. Try again.'),
    (pattern: r'^TZS (.+) zinaandaliwa kutuma kwa (.+)\.$',
      en: (m) => 'TZS ${m[1]} is being prepared to send to ${m[2]}.'),
    (pattern: r'^(.+) — TZS (.+) zimewekwa salio lako\.$',
      en: (m) => '${m[1]} — TZS ${m[2]} has been added to your balance.'),
    (pattern: r'^(.+) — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji\.$',
      en: (m) => '${m[1]} — the escrow period has ended and the money has been released to the seller.'),
    (pattern: r'^(.+) escrow imefunguliwa baada ya muda wake\. TZS (.+) zimewekwa kwenye salio lako\.$',
      en: (m) => '${m[1]} escrow was auto-released after its period. TZS ${m[2]} has been added to your balance.'),
    (pattern: r'^Muda wa escrow ya (.+) umeisha\. Pesa zimefunguliwa kwa muuzaji kwa sababu haukuthibitisha upokeaji kwa muda\.$',
      en: (m) => 'The escrow period for ${m[1]} has ended. The money was released to the seller because you did not confirm receipt in time.'),
    (pattern: r'^Mnunuzi amethibitisha upokeaji wa (.+)\. TZS (.+) zimewekwa kwenye salio lako\.$',
      en: (m) => 'The buyer confirmed receipt of ${m[1]}. TZS ${m[2]} has been added to your balance.'),
    (pattern: r'^Umethibitisha kuwa umepokea (.+)\. Pesa zimefunguliwa kwa muuzaji\.$',
      en: (m) => 'You confirmed receipt of ${m[1]}. The money has been released to the seller.'),
    // Delivery confirmed
    (pattern: r'^(.+) — asante kwa kununua ndani ya SokoVibe!$',
      en: (m) => '${m[1]} — thank you for buying on SokoVibe!'),
    // Deposit
    (pattern: r'^TZS (.+) zimeongezwa kwenye pochi yako\.$',
      en: (m) => 'TZS ${m[1]} has been added to your wallet.'),
    (pattern: r'^Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)$',
      en: (m) => 'Your TZS ${m[1]} payment did not complete because ${m[2]}'),
    // Order / payment
    (pattern: r'^(.+) imeuzwa\. TZS (.+) zimewekwa escrow\.$',
      en: (m) => '${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.'),
    (pattern: r'^(.+) imeuzwa\. TZS (.+) imewekwa escrow\.$',
      en: (m) => '${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa\.$',
      en: (m) => 'Payment for ${m[1]} has been received.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\.$',
      en: (m) => 'Payment for ${m[1]} has been received and safely placed in escrow.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\. Thibitisha upokeaji ili muuzaji apate hela zake\.$',
      en: (m) => 'Payment for ${m[1]} has been received and safely placed in escrow. Confirm receipt so the seller gets their money.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa\. Thibitisha upokeaji ili muuzaji apate hela zake\.$',
      en: (m) => 'Payment for ${m[1]} has been received. Confirm receipt so the seller gets their money.'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Jaribu tena kwenye app\.$',
      en: (m) => 'Payment for ${m[1]} did not complete. Try again in the app.'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Fungua app ili ujaribu tena\.$',
      en: (m) => 'Payment for ${m[1]} did not complete. Open the app to try again.'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Jaribu tena au wasiliana nasi\. Sababu: (.+)$',
      en: (m) => 'Payment for ${m[1]} did not complete because ${m[2]}. Try again or contact us.'),
    (pattern: r'^Fedha za (.+) zimerudishwa kwenye akaunti yako\.$',
      en: (m) => 'Your funds for ${m[1]} have been returned to your account.'),
    // Refund / cancel / dispute
    (pattern: r'^TZS (.+) zimerudishwa kwa (.+)\. Ada ya TZS (.+) imekatwa kwa gharama za payout\.$',
      en: (m) => 'TZS ${m[1]} has been refunded to you for ${m[2]}. A fee of TZS ${m[3]} was deducted for payout costs.'),
    (pattern: r'^(.+) imeghairiwa na mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.$',
      en: (m) => '${m[1]} was cancelled by the buyer. The money has been removed from your pending escrow.'),
    (pattern: r'^Mnunuzi amefungua mgogoro kwa (.+)\. Tafadhali wasilisha ushahidi wako\.$',
      en: (m) => 'The buyer opened a dispute for ${m[1]}. Please submit your evidence.'),
    (pattern: r'^Tumepokea mgogoro wako kwa (.+)\. Admin atakagua na kutoa uamuzi\.$',
      en: (m) => 'We received your dispute for ${m[1]}. An admin will review and decide.'),
    (pattern: r'^Admin ameamua pesa zitolewe kwa muuzaji\. ?(.+)?$',
      en: (m) => 'The admin ruled that the money be released to the seller.${m[1] != null ? ' ${m[1]}' : ''}'),
    (pattern: r'^Admin ameamua pesa zikutolee\. ?(.+)?$',
      en: (m) => 'The admin ruled that the money be released to you.${m[1] != null ? ' ${m[1]}' : ''}'),
    (pattern: r'^Refund kamili ya TZS (.+) kwa (.+) imetumwa kwa namba yako\.$',
      en: (m) => 'A full refund of TZS ${m[1]} for ${m[2]} has been sent to your number.'),
    (pattern: r'^(.+) imerefundiwa mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.(.*)$',
      en: (m) => '${m[1]} has been refunded to the buyer. The money has been removed from your pending escrow.${m[2] ?? ''}'),
    (pattern: r'^Ada ya gateway imetozwa kwenye akaunti yako\.$',
      en: (m) => 'A gateway fee has been charged to your account.'),
    // KYC
    (pattern: r'^(.+) ametuma KYC yake\. Tafadhali kagua\.$',
      en: (m) => '${m[1]} submitted their KYC. Please review it.'),
    (pattern: r'^KYC yako imewasilishwa\. Subiri ukaguzi wa admin\. Utapata taarifa ikikubaliwa\.$',
      en: (m) => 'Your KYC has been submitted. Wait for the admin review. You will be notified once approved.'),
    (pattern: r'^KYC yako imekataliwa\. Sababu: (.+)\. Wasilisha tena baada ya kurekebisha\.$',
      en: (m) => 'Your KYC was rejected because ${m[1]}. Resubmit after correcting it.'),
    (pattern: r'^KYC yako imefutwa na admin\. Sababu: (.+)\. Tuma tena KYC yako\.$',
      en: (m) => 'Your KYC was revoked by an admin because ${m[1]}. Submit your KYC again.'),
    // Account
    (pattern: r'^Unaonywa \((\d+)\/3\): (.+)\. Ukiingia makosa 3, akaunti itasimamishwa kabisa\.$',
      en: (m) => 'Warning (${m[1]}/3): ${m[2]}. After 3 violations your account will be fully suspended.'),
    // Flash sale
    (pattern: r'^(.+) inauzwa TSh (.+) pekee \(-(\d+)%\)\.$',
      en: (m) => '${m[1]} is selling for only TSh ${m[2]} (-${m[3]}%).'),
    (pattern: r'^(.+) sasa TSh (.+) pekee!$',
      en: (m) => '${m[1]} is now only TSh ${m[2]}!'),
    // Orders (create/transition)
    (pattern: r'^(.+) ametuma agizo la (.+?)(\. Eneo: .+)?\. Toa gharama ya usafirishaji sasa\.$',
      en: (m) => '${m[1]} placed an order for ${m[2]}${_locTag(m[3])}. Set the shipping cost now.'),
    (pattern: r'^Agizo lako la (.+) limewasilishwa kwa muuzaji\.$',
      en: (m) => 'Your order for ${m[1]} has been submitted to the seller.'),
    (pattern: r'^Agizo lako la (.+) limewasilishwa kwa muuzaji\. Utapokea taarifa ya gharama ya usafirishaji hivi karibuni\.$',
      en: (m) => 'Your order for ${m[1]} has been submitted to the seller. You will receive the shipping cost shortly.'),
    (pattern: r'^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa\.$',
      en: (m) => 'The seller set the shipping cost${m[2] != null ? ' of TZS ${m[2]}' : ''}. Pay now.'),
    (pattern: r'^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa ili agizo litumwe\.$',
      en: (m) => 'The seller set the shipping cost${m[2] != null ? ' of TZS ${m[2]}' : ''}. Pay now so the order is sent.'),
    (pattern: r'^Quote yako ya usafirishaji ya TZS (.+) imetumwa kwa (.+)\.$',
      en: (m) => 'Your shipping quote of TZS ${m[1]} was sent to ${m[2]}.'),
  ];

  static String _locTag(String? raw) {
    if (raw == null) return '';
    return raw.replaceFirst(RegExp(r'^\. Eneo: '), '. Location: ');
  }
}

class _L {
  final String en;
  const _L(this.en);
}

typedef _Builder = String Function(Match m);