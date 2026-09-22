/// FAQ item referencing localization keys (never hard-coded copy).
class FaqItem {
  final String qKey;
  final String aKey;
  const FaqItem(this.qKey, this.aKey);
}

const faqItems = [
  FaqItem('q1', 'a1'),
  FaqItem('q2', 'a2'),
  FaqItem('q3', 'a3'),
  FaqItem('q4', 'a4'),
  FaqItem('q5', 'a5'),
  FaqItem('q6', 'a6'),
];

/// Escrow journey steps (localization keys).
const escrowSteps = [
  'esc_pay',
  'esc_hold',
  'esc_ship',
  'esc_receive',
  'esc_confirm',
  'esc_release',
];

/// Delivery timeline steps (title/body key pairs).
const deliverySteps = [
  ('deliver_1t', 'deliver_1b'),
  ('deliver_2t', 'deliver_2b'),
  ('deliver_3t', 'deliver_3b'),
  ('deliver_4t', 'deliver_4b'),
  ('deliver_5t', 'deliver_5b'),
];

/// Payment method chips (text-based; no invented logos).
const paymentMethods = [
  'M-Pesa',
  'Tigo Pesa',
  'Airtel Money',
  'HaloPesa',
  'EzyPesa',
  'ClickPesa',
];

/// Real contact entry points (must stay truthful).
class SokoLinks {
  SokoLinks._();
  static const whatsappBuy =
      'https://wa.me/255693273241?text=Hi%2C%20nataka%20kununua%20kupitia%20Soko%20Vibe.';
  static const whatsappSell =
      'https://wa.me/255693273241?text=Hi%2C%20nataka%20kuuza%20kupitia%20Soko%20Vibe.';
  static const whatsappApp =
      'https://wa.me/255693273241?text=Hi%2C%20nataka%20kupata%20app%20ya%20Soko%20Vibe.';
  static const email = 'mailto:support@sokovibe.co.tz';
}
