import 'package:flutter/material.dart';

/// sw/en localization for the Coming Soon / Early Access page.
/// Every key MUST exist in both maps (covered by locale_parity_test).
class AppStrings extends ChangeNotifier {
  String _code = 'en';
  String get code => _code;
  bool get isSw => _code == 'sw';

  void setLocale(String code) {
    if (code != _code && _dict.containsKey(code)) {
      _code = code;
      notifyListeners();
    }
  }

  String t(String key) => _dict[_code]?[key] ?? _dict['en']?[key] ?? key;

  static Set<String> keysFor(String code) => _dict[code]?.keys.toSet() ?? {};

  static AppStrings of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppStringsProvider>()?.strings;
    assert(s != null, 'AppStringsProvider missing above context');
    return s!;
  }

  static const _dict = <String, Map<String, String>>{
    'en': {
      'doc_title': 'Soko Vibe — A Tanzanian Digital Marketplace',
      'nav_home': 'Home',
      'nav_about': 'About',
      'nav_features': 'Features',
      'nav_faq': 'FAQ',
      'nav_contact': 'Contact',
      'nav_updates': 'Get Launch Updates',
      'lang_label': 'Language',
      'badge_under_dev': 'UNDER DEVELOPMENT',
      'hero_title': 'Your Marketplace. Your Community. Your Vibe.',
      'hero_sub': 'Soko Vibe is a Tanzanian digital marketplace being built to connect buyers and sellers in a more modern, social, and convenient way. We are currently under development — register your email to be among the first to know when we launch.',
      'cta_notify': 'Notify Me at Launch',
      'cta_discover': 'Discover Soko Vibe',
      'hero_note': 'Join the early access list for launch updates.',
      'form_eyebrow': 'Early Access',
      'form_title': 'Be the first to know when Soko Vibe launches',
      'form_sub': 'Enter your email to receive launch updates and early announcements.',
      'form_name': 'Name (optional)',
      'form_email': 'Email address',
      'form_submit': 'Get Launch Updates',
      'form_loading': 'Submitting...',
      'form_success': "You're on the list!",
      'form_success_sub': 'Thank you for your interest in Soko Vibe. We’ll notify you when we go live.',
      'form_error': 'Something went wrong. Please try again.',
      'form_duplicate': "You're already on the list!",
      'form_invalid': 'Please enter a valid email address.',
      'form_privacy': 'We’ll only use your email to send Soko Vibe launch updates. No spam. No unnecessary sharing.',
      'about_eyebrow': 'What Is Soko Vibe',
      'about_title': 'A digital marketplace with its own identity',
      'about_body': 'Soko Vibe is being developed as a modern digital marketplace where people can discover products, connect with sellers, and engage in a more vibrant online shopping experience. Our goal is to build a platform that feels simple, trustworthy, and community-driven.',
      'about_note': 'Soko Vibe is currently under development. Features, design, and availability may evolve before launch.',
      'f1_t': 'Digital Marketplace',
      'f1_b': 'A place to discover and showcase products online.',
      'f2_t': 'Buyer–Seller Connection',
      'f2_b': 'Designed to make communication and discovery easier.',
      'f3_t': 'Community Vibe',
      'f3_b': 'A more engaging experience around shopping and local commerce.',
      'f4_t': 'Mobile-Friendly Experience',
      'f4_b': 'Built for convenient access across devices.',
      'f5_t': 'Modern Platform Vision',
      'f5_b': 'Focused on simplicity, growth, and future expansion.',
      'f6_t': 'Tanzanian Roots',
      'f6_b': 'Created with local relevance and digital opportunity in mind.',
      'how_eyebrow': 'How It Will Work',
      'how_title': 'A simple path from discovery to connection',
      'how_1_t': 'Discover',
      'how_1_b': 'Explore products and sellers in one place.',
      'how_2_t': 'Connect',
      'how_2_b': 'Engage with listings and marketplace opportunities.',
      'how_3_t': 'Grow',
      'how_3_b': 'Be part of a platform evolving for modern digital commerce.',
      'how_note': 'Final product features may change as development continues.',
      'early_eyebrow': 'Why Join Early',
      'early_title': 'Get closer to the launch',
      'early_1_t': 'Launch Updates',
      'early_1_b': 'Be the first to hear important launch announcements.',
      'early_2_t': 'Early Announcements',
      'early_2_b': 'Receive updates as Soko Vibe takes shape.',
      'early_3_t': 'Follow the Journey',
      'early_3_b': 'Stay connected while the platform is under development.',
      'early_4_t': 'Community Start',
      'early_4_b': 'Be part of the Soko Vibe community from the beginning.',
      'faq_eyebrow': 'FAQ',
      'faq_title': 'Frequently asked questions',
      'q1': 'What is Soko Vibe?',
      'a1': 'Soko Vibe is a digital marketplace platform currently under development in Tanzania.',
      'q2': 'Is Soko Vibe live now?',
      'a2': 'Not yet. The platform is still under development, and this page is for early interest and launch updates.',
      'q3': 'When will Soko Vibe launch?',
      'a3': "We haven't announced an official launch date yet. Register your email to receive updates.",
      'q4': 'What can I expect from Soko Vibe?',
      'a4': 'Soko Vibe aims to offer a modern marketplace experience focused on discovery, connection, and digital convenience.',
      'q5': 'How will I know when it launches?',
      'a5': 'Enter your email in the registration form, and we’ll notify you when major updates or launch news are available.',
      'q6': 'Is my email safe?',
      'a6': 'Yes. Your email will only be used for Soko Vibe updates and launch-related communication.',
      'q7': 'Who is Soko Vibe for?',
      'a7': 'Soko Vibe is for people interested in a modern Tanzanian digital marketplace experience, including future buyers, sellers, and community members.',
      'foot_tag': 'Soko Vibe — A Tanzanian Digital Marketplace.',
      'foot_desc': 'A modern digital marketplace under development, built to connect people, products, and opportunity.',
      'foot_contact': 'Contact',
      'foot_links': 'Links',
      'foot_privacy': 'Privacy Policy',
      'foot_terms': 'Terms & Conditions',
      'foot_rights': 'Copyright © 2026 Soko Vibe. All rights reserved.',
    },
    'sw': {
      'doc_title': 'Soko Vibe — Soko la Kidijitali la Tanzania',
      'nav_home': 'Mwanzo',
      'nav_about': 'Kuhusu',
      'nav_features': 'Vipengele',
      'nav_faq': 'Maswali',
      'nav_contact': 'Mawasiliano',
      'nav_updates': 'Pata Taarifa za Uzinduzi',
      'lang_label': 'Lugha',
      'badge_under_dev': 'INAENDELEZWA',
      'hero_title': 'Soko Lako. Jamii Yako. Vibe Yako.',
      'hero_sub': 'Soko Vibe ni soko la kidijitali la Tanzania linalojengwa kuunganisha wanunuzi na wauzaji kwa njia ya kisasa, ya kijamii, na rahisi. Bado tunaendelea kulijenga — jiandikishe kwa barua pepe ujue tutakapozindua.',
      'cta_notify': 'Nijulishe Tutakapozindua',
      'cta_discover': 'Gundua Soko Vibe',
      'hero_note': 'Jiunge na orodha ya taarifa za awali za uzinduzi.',
      'form_eyebrow': 'Ufikiaji wa Awali',
      'form_title': 'Kuwa wa kwanza kujua Soko Vibe itakapozinduliwa',
      'form_sub': 'Weka barua pepe yako ili upate taarifa za uzinduzi na matangazo ya awali.',
      'form_name': 'Jina (si lazima)',
      'form_email': 'Anwani ya barua pepe',
      'form_submit': 'Pata Taarifa za Uzinduzi',
      'form_loading': 'Inatuma...',
      'form_success': 'Uko kwenye orodha!',
      'form_success_sub': 'Asante kwa kuvutiwa na Soko Vibe. Tutakujulisha tutakapoanza rasmi.',
      'form_error': 'Kuna hitilafu. Tafadhali jaribu tena.',
      'form_duplicate': 'Tayari uko kwenye orodha!',
      'form_invalid': 'Tafadhali weka barua pepe sahihi.',
      'form_privacy': 'Tutatumia barua pepe yako kwa taarifa za uzinduzi wa Soko Vibe pekee. Hakuna spam. Hakuna kushiriki ovyo.',
      'about_eyebrow': 'Soko Vibe ni Nini',
      'about_title': 'Soko la kidijitali lenye utambulisho wake',
      'about_body': 'Soko Vibe linaendelezwa kama soko la kisasa la kidijitali ambapo watu wanaweza kugundua bidhaa, kuungana na wauzaji, na kupata uzoefu wa ununuzi mtandaoni unaovutia zaidi. Lengo letu ni kujenga jukwaa rahisi, linaloaminika, na linalojengwa kwa jamii.',
      'about_note': 'Soko Vibe bado linaendelezwa. Vipengele, muundo, na upatikanaji vinaweza kubadilika kabla ya uzinduzi.',
      'f1_t': 'Soko la Kidijitali',
      'f1_b': 'Mahali pa kugundua na kuonyesha bidhaa mtandaoni.',
      'f2_t': 'Muunganiko wa Mnunuzi na Muuzaji',
      'f2_b': 'Limebuniwa kurahisisha mawasiliano na ugunduzi.',
      'f3_t': 'Hisia ya Jamii',
      'f3_b': 'Uzoefu unaovutia zaidi wa ununuzi na biashara ya karibu.',
      'f4_t': 'Uzoefu Rafiki kwa Simu',
      'f4_b': 'Umejengwa kwa ufikiaji rahisi kwenye vifaa mbalimbali.',
      'f5_t': 'Maono ya Jukwaa la Kisasa',
      'f5_b': 'Yanalenga urahisi, ukuaji, na upanuzi wa baadaye.',
      'f6_t': 'Mizizi ya Kitanzania',
      'f6_b': 'Limeundwa kwa kuzingatia muktadha wa ndani na fursa za kidijitali.',
      'how_eyebrow': 'Jinsi Itakavyofanya Kazi',
      'how_title': 'Njia rahisi kutoka ugunduzi hadi muunganiko',
      'how_1_t': 'Gundua',
      'how_1_b': 'Chunguza bidhaa na wauzaji mahali pamoja.',
      'how_2_t': 'Ungana',
      'how_2_b': 'Shirikiana na matangazo na fursa za sokoni.',
      'how_3_t': 'Kua',
      'how_3_b': 'Kuwa sehemu ya jukwaa linalokua kwa biashara ya kidijitali ya kisasa.',
      'how_note': 'Vipengele vya mwisho vinaweza kubadilika maendeleo yanapoendelea.',
      'early_eyebrow': 'Kwa Nini Ujiunge Mapema',
      'early_title': 'Kuwa karibu na uzinduzi',
      'early_1_t': 'Taarifa za Uzinduzi',
      'early_1_b': 'Kuwa wa kwanza kusikia matangazo muhimu ya uzinduzi.',
      'early_2_t': 'Matangazo ya Awali',
      'early_2_b': 'Pokea taarifa Soko Vibe linapoendelea kuchukua sura.',
      'early_3_t': 'Fuata Safari',
      'early_3_b': 'Endelea kuunganishwa wakati jukwaa linaendelezwa.',
      'early_4_t': 'Mwanzo wa Jamii',
      'early_4_b': 'Kuwa sehemu ya jamii ya Soko Vibe tangu mwanzo.',
      'faq_eyebrow': 'Maswali',
      'faq_title': 'Maswali yanayoulizwa mara kwa mara',
      'q1': 'Soko Vibe ni nini?',
      'a1': 'Soko Vibe ni jukwaa la soko la kidijitali linaloendelezwa nchini Tanzania.',
      'q2': 'Je, Soko Vibe ipo hewani sasa?',
      'a2': 'Bado. Jukwaa bado linaendelezwa, na ukurasa huu ni kwa waliovutiwa mapema na taarifa za uzinduzi.',
      'q3': 'Soko Vibe itazinduliwa lini?',
      'a3': 'Bado hatujatangaza tarehe rasmi ya uzinduzi. Jiandikishe kwa barua pepe kupata taarifa.',
      'q4': 'Nitarajie nini kutoka Soko Vibe?',
      'a4': 'Soko Vibe linalenga kutoa uzoefu wa kisasa wa soko unaolenga ugunduzi, muunganiko, na urahisi wa kidijitali.',
      'q5': 'Nitajuaje litakapozinduliwa?',
      'a5': 'Weka barua pepe yako kwenye fomu, na tutakujulisha taarifa muhimu au habari za uzinduzi zitakapopatikana.',
      'q6': 'Je, barua pepe yangu iko salama?',
      'a6': 'Ndiyo. Barua pepe yako itatumika tu kwa taarifa za Soko Vibe na mawasiliano yanayohusu uzinduzi.',
      'q7': 'Soko Vibe ni kwa ajili ya nani?',
      'a7': 'Soko Vibe ni kwa watu wanaovutiwa na uzoefu wa kisasa wa soko la kidijitali la Tanzania, ikiwa ni pamoja na wanunuzi, wauzaji, na wanajamii wa baadaye.',
      'foot_tag': 'Soko Vibe — Soko la Kidijitali la Tanzania.',
      'foot_desc': 'Soko la kisasa la kidijitali linaloendelezwa, likiwaunganisha watu, bidhaa, na fursa.',
      'foot_contact': 'Mawasiliano',
      'foot_links': 'Viungo',
      'foot_privacy': 'Sera ya Faragha',
      'foot_terms': 'Masharti na Vigezo',
      'foot_rights': 'Hakimiliki © 2026 Soko Vibe. Haki zote zimehifadhiwa.',
    },
  };
}

class AppStringsProvider extends InheritedWidget {
  final AppStrings strings;
  const AppStringsProvider({super.key, required this.strings, required super.child});

  @override
  bool updateShouldNotify(AppStringsProvider old) => old.strings.code != strings.code;
}

extension StringsX on BuildContext {
  String str(String key) => AppStrings.of(this).t(key);
}
