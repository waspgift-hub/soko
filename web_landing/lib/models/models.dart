/// FAQ item referencing localization keys.
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
  FaqItem('q7', 'a7'),
];

const fullFaqItems = [
  FaqItem('faq_g1_q', 'faq_g1_a'),
  FaqItem('faq_g2_q', 'faq_g2_a'),
  FaqItem('faq_g3_q', 'faq_g3_a'),
  FaqItem('faq_g4_q', 'faq_g4_a'),
  FaqItem('faq_g5_q', 'faq_g5_a'),
  FaqItem('faq_g6_q', 'faq_g6_a'),
  FaqItem('faq_g7_q', 'faq_g7_a'),
  FaqItem('faq_g8_q', 'faq_g8_a'),
  FaqItem('faq_g9_q', 'faq_g9_a'),
  FaqItem('faq_g10_q', 'faq_g10_a'),
];

/// Real contact/brand links for the website.
class SokoLinks {
  SokoLinks._();
  static const site = 'https://www.sokovibe.co.tz';
  static const emailAddress = 'support@sokovibe.co.tz';
  static const email = 'mailto:$emailAddress';
  static const privacy = '/privacy-policy/';
  static const terms = '/terms-of-service/';
  static const cookiePolicy = '/cookie-policy/';
  static const contactPage = '/contact/';
  static const apiBase = String.fromEnvironment(
    'SOKO_API_BASE',
    defaultValue: 'https://soko-langu-server.onrender.com',
  );
}
