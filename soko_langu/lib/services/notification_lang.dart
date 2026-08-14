// Client-side localization for in-app notifications.
//
// Mirrors server/notif_lang.js so the in-app notifications list matches what
// the user chose in the app. Server pushes are localized by the server; the
// Firestore-stored copies are Swahili templates, so we localize them at render
// time using the app's active language.

class NotificationLang {
  static const Map<String, String> _titles = {
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
    '📦 Bidhaa Imesafirishwa!': 'Product Shipped!',
    '🚚 Mnunuzi Amechagua Usafirishaji!': 'Buyer Chose Shipping!',
  };

  static const Map<String, String> _staticBodies = {
    'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.':
        'You are approved to sell products. You can now add new products.',
    'Akaunti yako imesitishwa. Wasiliana na msaada kwa maelezo zaidi.':
        'Your account has been suspended. Contact support for more details.',
    'Akaunti yako imerejeshwa. Sasa unaweza kuendelea kutumia Soko Vibe.':
        'Your account has been restored. You can continue using Soko Vibe.',
    'Umefikia maonyo 3 na akaunti yako imefungwa kwa kukiuka sera. Wasiliana na msaada.':
        'You have reached 3 warnings and your account has been blocked for violating policy. Contact support.',
  };

  /// Localizes a Swahili server-stored notification title+body to English.
  /// Falls back to the original Swahili when no translation exists. zh users
  /// get the English copy (better than unlocalized Swahili).
  static ({String title, String body}) localize(
      String lang, String title, String body) {
    if (lang == 'sw') return (title: title, body: body);
    final enTitle = _titles[title] ?? title;
    final enBody = _staticBodies[body] ?? _translateDynamicBody(body);
    return (title: enTitle, body: enBody);
  }

  static String _translateDynamicBody(String body) {
    for (final rule in _bodyRules) {
      final m = RegExp(rule.pattern).firstMatch(body);
      if (m != null) return rule.en(m);
    }
    return body;
  }

  static final List<({String pattern, String Function(Match m) en})> _bodyRules = [
    // Dispatch
    (pattern: r'^(.+) imesafirishwa\. Thibitisha upokeaji ukishapata mzigo\.$', en: (m) => '${m[1]} has been shipped. Confirm receipt once you receive the goods.'),
    (pattern: r'^(.+) imesafirishwa\. Angalia proof of delivery na thibitisha upokeaji\.$', en: (m) => '${m[1]} has been shipped. Check the proof of delivery and confirm receipt.'),
    (pattern: r'^(.+) limetumwa — fuatilia usafirishaji kwenye app\.$', en: (m) => '${m[1]} has been dispatched — track the shipment in the app.'),
    (pattern: r'^(.+) ameweka taarifa za usafirishaji kwa Oda #(.+)\. Fungua app na tuma bidhaa\.$', en: (m) => '${m[1]} entered shipping details for order #${m[2]}. Open the app and send the product.'),
    (pattern: r'^(.+) ameweka taarifa za usafirishaji\. Tumia hizo taarifa kutuma bidhaa\.$', en: (m) => '${m[1]} has entered shipping details. Use them to send the product.'),
    // Payout / escrow
    (pattern: r'^TZS (.+) zimetumwa kwa simu yako \(fee TZS (.+)\)\.$', en: (m) => 'TZS ${m[1]} has been sent to your phone (fee TZS ${m[2]}).'),
    (pattern: r'^TZS (.+) zimetumwa kwenye mobile money yako\.$', en: (m) => 'TZS ${m[1]} has been sent to your mobile money.'),
    (pattern: r'^TZS (.+) hazikutumwa\. Pesa zimerudishwa kwenye pochi yako\. Jaribu tena\.$', en: (m) => 'TZS ${m[1]} was not sent. The money has been returned to your wallet. Try again.'),
    (pattern: r'^TZS (.+) zinaandaliwa kutuma kwa (.+)\.$', en: (m) => 'TZS ${m[1]} is being prepared to send to ${m[2]}.'),
    (pattern: r'^(.+) — TZS (.+) zimewekwa salio lako\.$', en: (m) => '${m[1]} — TZS ${m[2]} has been added to your balance.'),
    (pattern: r'^(.+) — muda wa escrow umeisha, pesa zimefunguliwa kwa muuzaji\.$', en: (m) => '${m[1]} — the escrow period has ended and the money has been released to the seller.'),
    // Deposit
    (pattern: r'^TZS (.+) zimeongezwa kwenye pochi yako\.$', en: (m) => 'TZS ${m[1]} has been added to your wallet.'),
    (pattern: r'^Malipo ya TZS (.+) hayakukamilika\. Sababu: (.+)$', en: (m) => 'Your TZS ${m[1]} payment did not complete. Reason: ${m[2]}'),
    // Order / payment
    (pattern: r'^(.+) imeuzwa\. TZS (.+) zimewekwa escrow\.$', en: (m) => '${m[1]} has been sold. TZS ${m[2]} has been placed in escrow.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa\.$', en: (m) => 'Payment for ${m[1]} has been received.'),
    (pattern: r'^Malipo ya (.+) yamepokelewa na kuwekwa escrow salama\.$', en: (m) => 'Payment for ${m[1]} has been received and safely placed in escrow.'),
    (pattern: r'^Malipo ya (.+) hayakukamilika\. Jaribu tena kwenye app\.$', en: (m) => 'Payment for ${m[1]} did not complete. Try again in the app.'),
    // Refund / cancel / dispute
    (pattern: r'^TZS (.+) zimerudishwa kwa (.+)\. Ada ya TZS (.+) imekatwa kwa gharama za payout\.$', en: (m) => 'TZS ${m[1]} has been refunded to you for ${m[2]}. A fee of TZS ${m[3]} was deducted for payout costs.'),
    (pattern: r'^(.+) imeghairiwa na mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.$', en: (m) => '${m[1]} was cancelled by the buyer. The money has been removed from your pending escrow.'),
    (pattern: r'^Mnunuzi amefungua mgogoro kwa (.+)\. Tafadhali wasilisha ushahidi wako\.$', en: (m) => 'The buyer opened a dispute for ${m[1]}. Please submit your evidence.'),
    (pattern: r'^Tumepokea mgogoro wako kwa (.+)\. Admin atakagua na kutoa uamuzi\.$', en: (m) => 'We received your dispute for ${m[1]}. An admin will review and decide.'),
    (pattern: r'^Admin ameamua pesa zitolewe kwa muuzaji\. (.+)$', en: (m) => 'The admin ruled that the money be released to the seller. ${m[1]}'),
    (pattern: r'^Admin ameamua pesa zikutolee\. (.+)$', en: (m) => 'The admin ruled that the money be released to you. ${m[1]}'),
    (pattern: r'^Refund kamili ya TZS (.+) kwa (.+) imetumwa kwa namba yako\.$', en: (m) => 'A full refund of TZS ${m[1]} for ${m[2]} has been sent to your number.'),
    (pattern: r'^(.+) imerefundiwa mnunuzi\. Pesa zimetolewa kwenye pendingEscrow yako\.(.*)$', en: (m) => '${m[1]} has been refunded to the buyer. The money has been removed from your pending escrow.${m[2] ?? ''}'),
    // KYC
    (pattern: r'^(.+) ametuma KYC yake\. Tafadhali kagua\.$', en: (m) => '${m[1]} submitted their KYC. Please review it.'),
    (pattern: r'^KYC yako imekataliwa\. Sababu: (.+)\. Wasilisha tena baada ya kurekebisha\.$', en: (m) => 'Your KYC was rejected. Reason: ${m[1]}. Resubmit after correcting it.'),
    // Account
    (pattern: r'^Unaonywa \((\d+)\/3\): (.+)\. Ukiingia makosa 3, akaunti itasimamishwa kabisa\.$', en: (m) => 'Warning (${m[1]}/3): ${m[2]}. After 3 violations your account will be fully suspended.'),
    // Flash sale
    (pattern: r'^(.+) inauzwa TSh (.+) pekee \(-(\d+)%\)\.$', en: (m) => '${m[1]} is selling for only TSh ${m[2]} (-${m[3]}%).'),
    // Orders
    (pattern: r'^(.+) ametuma agizo la (.+?)(\. Eneo: .+)?\. Toa gharama ya usafirishaji sasa\.$', en: (m) => '${m[1]} placed an order for ${m[2]}${_locTag(m[3])}. Set the shipping cost now.'),
    (pattern: r'^Agizo lako la (.+) limewasilishwa kwa muuzaji\.$', en: (m) => 'Your order for ${m[1]} has been submitted to the seller.'),
    (pattern: r'^Muuzaji ameweka gharama ya usafirishaji( la TZS (.+))?\. Lipa sasa\.$', en: (m) => 'The seller set the shipping cost${m[2] != null ? ' of TZS ${m[2]}' : ''}. Pay now.'),
    (pattern: r'^Quote yako ya usafirishaji ya TZS (.+) imetumwa kwa (.+)\.$', en: (m) => 'Your shipping quote of TZS ${m[1]} was sent to ${m[2]}.'),
  ];

  static String _locTag(String? raw) {
    if (raw == null) return '';
    return raw.replaceFirst(RegExp(r'^\. Eneo: '), '. Location: ');
  }
}
