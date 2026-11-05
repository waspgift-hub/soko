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

/// Real contact/brand links for the Coming Soon page.
class SokoLinks {
  SokoLinks._();
  static const site = 'https://www.sokovibe.co.tz';
  static const emailAddress = 'support@sokovibe.co.tz';
  static const email = 'mailto:$emailAddress';
  static const privacy = '$site/privacy-policy';
  static const terms = '$site/terms-of-service';
  static const apiBase = String.fromEnvironment(
    'SOKO_API_BASE',
    defaultValue: 'https://soko-langu-server.onrender.com',
  );
}
