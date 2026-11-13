import 'package:flutter/material.dart';

/// SW/EN localization for the Soko Vibe website.
/// Every key MUST exist in both maps (covered by locale_parity_test).
class AppStrings extends ChangeNotifier {
  String _code = 'sw'; // default for Tanzania audience
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
    final s = context
        .dependOnInheritedWidgetOfExactType<AppStringsProvider>()
        ?.strings;
    assert(s != null, 'AppStringsProvider missing above context');
    return s!;
  }

  static const _dict = <String, Map<String, String>>{
    'en': {
      'doc_title': 'Soko Vibe — Tanzania Marketplace (Under Development)',
      'nav_home': 'Home',
      'nav_about': 'About',
      'nav_how': 'How It Works',
      'nav_features': 'Features',
      'nav_buyers': 'For Buyers',
      'nav_sellers': 'For Sellers',
      'nav_pricing': 'Pricing',
      'nav_faq': 'FAQ',
      'nav_contact': 'Contact',
      'nav_updates': 'Join Waitlist',
      'nav_menu': 'Menu',
      'lang_label': 'Language',
      'badge_under_dev': 'UNDER DEVELOPMENT',
      'hero_title': 'Discover a New Way to Buy and Sell in Tanzania.',
      'hero_sub':
          'Soko Vibe is building a smarter marketplace that brings buyers, sellers, products, and services together in one simple experience.',
      'hero_status':
          'Soko Vibe is currently under development. Join our launch list and be among the first to know when we launch.',
      'cta_notify': 'Get Early Access',
      'cta_discover': 'Explore Soko Vibe',
      'hero_note':
          'Soko Vibe is under development. Features shown may change before launch.',
      'form_eyebrow': 'Launch Waitlist',
      'form_title': 'Be among the first to know when we launch',
      'form_sub':
          'Join the early-access list to receive official launch updates from Soko Vibe.',
      'form_name': 'Name (optional)',
      'form_email': 'Email address',
      'form_user_type': 'I am interested as',
      'form_type_buyer': 'Buyer',
      'form_type_seller': 'Seller',
      'form_type_both': 'Both',
      'form_submit': 'Notify Me When We Launch',
      'form_loading': 'Submitting...',
      'form_success':
          'You\'re on the list! We\'ll notify you when Soko Vibe is ready.',
      'form_success_sub':
          'We\'ll use your email for launch updates only, based on your consent.',
      'form_error': 'Something went wrong. Please try again.',
      'form_duplicate': 'You\'re already on the launch list.',
      'form_invalid': 'Please enter a valid email address.',
      'form_rate_limited': 'Too many requests. Please try again later.',
      'form_network_error': 'Unable to connect right now. Please try again.',
      'form_consent':
          'I agree to receive Soko Vibe launch updates and have read the Privacy Policy.',
      'form_consent_required':
          'Please agree to receive launch updates before subscribing.',
      'form_privacy':
          'We\'ll use your email for Soko Vibe launch updates only. No spam. No selling your data. See our Privacy Policy.',
      'final_cta_title': 'Be Part of the Soko Vibe Journey.',
      'final_cta_sub':
          'Join the early-access list and receive updates when we launch.',
      'about_eyebrow': 'What Is Soko Vibe',
      'about_title':
          'A digital marketplace experience being built for Tanzania',
      'about_body':
          'Soko Vibe is being developed as a modern social-commerce and digital marketplace platform where buyers and sellers can discover products and services, connect, and participate in a simpler online marketplace experience.',
      'about_note':
          'Soko Vibe is currently under development. Features, availability, and design may evolve before launch.',
      'highlights_title': 'Platform Highlights',
      'highlights_sub':
          'Planned and in-development experiences we are building with care.',
      'status_planned': 'Planned',
      'status_in_dev': 'In development',
      'status_verify': 'Subject to launch readiness',
      'f1_t': 'Discover products',
      'f1_b':
          'Find products and services through a simple marketplace experience.',
      'f2_t': 'Connect with sellers',
      'f2_b':
          'Explore seller profiles and communicate through supported channels when available.',
      'f3_t': 'Product media',
      'f3_b':
          'Rich product presentation, including images and video where supported.',
      'f4_t': 'Social interactions',
      'f4_b':
          'Community-oriented discovery features are being designed for relevance and safety.',
      'f5_t': 'Digital products & services',
      'f5_b':
          'Selected digital offerings may be supported as the platform matures.',
      'f6_t': 'Smart discovery',
      'f6_b':
          'Personalized and searchable discovery experiences are being developed.',
      'how_eyebrow': 'How It Works',
      'how_title': 'A simple path from discovery to marketplace connection',
      'how_1_t': 'Discover',
      'how_1_b': 'Find products and services in one place.',
      'how_2_t': 'Connect',
      'how_2_b':
          'Explore sellers and product details through the platform experience.',
      'how_3_t': 'Shop',
      'how_3_b': 'Use marketplace features as they become available at launch.',
      'how_note': 'Final workflows may change as development continues.',
      'buyers_preview_title': 'For Buyers',
      'buyers_preview_body':
          'Soko Vibe aims to help buyers discover products and services, explore seller information, and enjoy a clearer digital marketplace experience in Tanzania.',
      'sellers_preview_title': 'For Sellers',
      'sellers_preview_body':
          'Soko Vibe aims to help sellers present products, share media, build a profile, and reach potential customers. Results depend on many factors; no sales are guaranteed.',
      'trust_title': 'Trust and Safety',
      'trust_body':
          'We are building Soko Vibe with a focus on safer marketplace interactions, clear policies, and responsible platform design. Specific payment, escrow, identity verification, and transaction protection features will only be described as available when they are verified and operational.',
      'trust_note':
          'Security and protection features are communicated based on verified implementation status.',
      'faq_preview_title': 'Common Questions',
      'faq_view_all': 'View all FAQs',
      'q1': 'What is Soko Vibe?',
      'a1':
          'Soko Vibe is a social-commerce and digital marketplace platform being developed for Tanzania.',
      'q2': 'Is Soko Vibe live now?',
      'a2':
          'Not yet. The mobile application and platform are still under development. This website provides launch updates.',
      'q3': 'When will Soko Vibe launch?',
      'a3':
          'An official launch date has not been announced. Join the waitlist to receive updates.',
      'q4': 'What can buyers expect?',
      'a4':
          'Buyers can expect a discovery-focused marketplace experience. Specific features will be confirmed as they become available.',
      'q5': 'What can sellers expect?',
      'a5':
          'Sellers can expect tools for presenting products and reaching buyers as the platform launches. We do not guarantee sales or revenue.',
      'q6': 'Is my email safe?',
      'a6':
          'We use waitlist emails for launch communications you consented to receive. See our Privacy Policy for details.',
      'q7': 'Who is Soko Vibe for?',
      'a7':
          'Soko Vibe is for people in Tanzania interested in a modern marketplace experience, including buyers and sellers.',
      'foot_tag':
          'Soko Vibe — building a modern marketplace experience for Tanzania.',
      'foot_desc':
          'A social-commerce and digital marketplace platform under development, designed to bring buyers and sellers together with clarity and trust.',
      'foot_contact': 'Contact',
      'foot_links': 'Links',
      'foot_buyers': 'Buyers',
      'foot_sellers': 'Sellers',
      'foot_privacy': 'Privacy Policy',
      'foot_terms': 'Terms & Conditions',
      'foot_cookie': 'Cookie Policy',
      'foot_contact_page': 'Contact',
      'foot_rights': 'Copyright © 2026 Soko Vibe. All rights reserved.',
      // Contact form
      'contact_title': 'Contact Us',
      'contact_sub':
          'Send us a message and we will respond through official support channels.',
      'contact_name': 'Name (optional)',
      'contact_email': 'Email address',
      'contact_subject': 'Subject',
      'contact_message': 'Message',
      'contact_submit': 'Send Message',
      'contact_loading': 'Sending...',
      'contact_success': 'Thank you. Your message has been received.',
      'contact_error': 'Unable to send your message. Please try again.',
      'contact_invalid':
          'Please complete all required fields with valid information.',
      'contact_privacy':
          'We use your contact details only to respond to your message.',
      // Pages
      'page_about_title': 'About Soko Vibe',
      'page_how_title': 'How It Works',
      'page_features_title': 'Features',
      'page_buyers_title': 'For Buyers',
      'page_sellers_title': 'For Sellers',
      'page_pricing_title': 'Pricing',
      'page_pricing_pending':
          'Pricing information will be announced closer to launch.',
      'page_faq_title': 'Frequently Asked Questions',
      'page_404_title': 'Page not found',
      'page_404_body':
          'The page you are looking for may have moved or does not exist.',
      'page_404_home': 'Return Home',
      'waitlist_success_title': 'You\'re on the list',
      'waitlist_success_body':
          'Thank you for joining Soko Vibe. We\'ll send launch updates to the email you provided when important announcements are ready.',
      'waitlist_success_cta': 'Back to Home',
      // Full FAQ categories (abbreviated but complete set)
      'faq_g1_q': 'What is Soko Vibe?',
      'faq_g1_a':
          'Soko Vibe is a social-commerce and digital marketplace platform being developed for Tanzania.',
      'faq_g2_q': 'Is the app available now?',
      'faq_g2_a':
          'No. The mobile app and platform are under development. Join the waitlist for launch updates.',
      'faq_g3_q': 'How do I get launch updates?',
      'faq_g3_a':
          'Submit your email through the waitlist form and consent to receive launch communications.',
      'faq_g4_q': 'Can I buy products today?',
      'faq_g4_a':
          'Not through the launched marketplace yet. Current features and availability will be announced at launch.',
      'faq_g5_q': 'Can I sell on Soko Vibe?',
      'faq_g5_a':
          'Seller onboarding details will be announced closer to launch. Join the waitlist as a seller to receive updates.',
      'faq_g6_q': 'Are payments and escrow live?',
      'faq_g6_a':
          'Payment and transaction protection features will only be presented as available when verified and operational.',
      'faq_g7_q': 'Is Soko Vibe secure?',
      'faq_g7_a':
          'We design with security in mind and communicate specific protections based on verified implementation. See our legal pages for data practices.',
      'faq_g8_q': 'Will pricing be announced?',
      'faq_g8_a':
          'Pricing will be announced closer to launch unless verified plans are officially published.',
      'faq_g9_q': 'How can I contact support?',
      'faq_g9_a': 'Use the Contact page or email support@sokovibe.co.tz.',
      'faq_g10_q': 'How do I remove my waitlist email?',
      'faq_g10_a':
          'Email support@sokovibe.co.tz from the address you used and request removal from launch updates.',
    },
    'sw': {
      'doc_title': 'Soko Vibe — Soko la Tanzania (Inaendelezwa)',
      'nav_home': 'Mwanzo',
      'nav_about': 'Kuhusu',
      'nav_how': 'Jinsi Inavyofanya Kazi',
      'nav_features': 'Vipengele',
      'nav_buyers': 'Kwa Wanunuzi',
      'nav_sellers': 'Kwa Wauzaji',
      'nav_pricing': 'Bei',
      'nav_faq': 'Maswali',
      'nav_contact': 'Mawasiliano',
      'nav_updates': 'Jiunge na Orodha',
      'nav_menu': 'Menyu',
      'lang_label': 'Lugha',
      'badge_under_dev': 'INAENDELEZWA',
      'hero_title': 'Gundua Njia Mpya ya Kununua na Kuuza Tanzania.',
      'hero_sub':
          'Soko Vibe inajenga soko la kisasa linalowaunganisha wanunuzi, wauzaji, bidhaa, na huduma katika uzoefu mmoja rahisi.',
      'hero_status':
          'Soko Vibe bado inaendelezwa. Jiunge na orodha ya uzinduzi na uwe miongoni mwa wa kwanza kupata taarifa tutakapozindua.',
      'cta_notify': 'Pata Ufikiaji wa Mapema',
      'cta_discover': 'Chunguza Soko Vibe',
      'hero_note':
          'Soko Vibe inaendelezwa. Vipengele vinaweza kubadilika kabla ya uzinduzi.',
      'form_eyebrow': 'Orodha ya Uzinduzi',
      'form_title': 'Kuwa miongoni mwa wa kwanza kujua tutakapozindua',
      'form_sub':
          'Jiunge na orodha ya ufikiaji wa mapema kupata taarifa rasmi za uzinduzi kutoka Soko Vibe.',
      'form_name': 'Jina (si lazima)',
      'form_email': 'Anwani ya barua pepe',
      'form_user_type': 'Ninavutiwa kama',
      'form_type_buyer': 'Mnunuzi',
      'form_type_seller': 'Muuzaji',
      'form_type_both': 'Vyote',
      'form_submit': 'Nijulishe Tutakapozindua',
      'form_loading': 'Inatuma...',
      'form_success':
          'Uko kwenye orodha! Tutakujulisha Soko Vibe itakapokuwa tayari.',
      'form_success_sub':
          'Tutatumia barua pepe yako kwa taarifa za uzinduzi pekee, kulingana na ridhaa yako.',
      'form_error': 'Kuna hitilafu. Tafadhali jaribu tena.',
      'form_duplicate': 'Tayari uko kwenye orodha ya uzinduzi.',
      'form_invalid': 'Tafadhali weka barua pepe sahihi.',
      'form_rate_limited': 'Maombi mengi sana. Tafadhali jaribu tena baadaye.',
      'form_network_error':
          'Imeshindikana kuunganisha sasa. Tafadhali jaribu tena.',
      'form_consent':
          'Nakubali kupokea taarifa za uzinduzi wa Soko Vibe na nimesoma Sera ya Faragha.',
      'form_consent_required':
          'Tafadhali kubali kupokea taarifa za uzinduzi kabla ya kujiandikisha.',
      'form_privacy':
          'Tutatumia barua pepe yako kwa taarifa za uzinduzi wa Soko Vibe pekee. Hakuna spam. Hatuzui data yako. Tazama Sera ya Faragha.',
      'final_cta_title': 'Kuwa Sehemu ya Safari ya Soko Vibe.',
      'final_cta_sub':
          'Jiunge na orodha ya ufikiaji wa mapema na upokee taarifa tutakapozindua.',
      'about_eyebrow': 'Soko Vibe ni Nini',
      'about_title': 'Uzoefu wa soko la kidijitali unaojengwa kwa Tanzania',
      'about_body':
          'Soko Vibe inaendelezwa kama jukwaa la kisasa la biashara ya kijamii na soko la kidijitali ambapo wanunuzi na wauzaji wanaweza kugundua bidhaa na huduma, kuungana, na kushiriki katika uzoefu rahisi wa soko mtandaoni.',
      'about_note':
          'Soko Vibe bado inaendelezwa. Vipengele, upatikanaji, na muundo vinaweza kubadilika kabla ya uzinduzi.',
      'highlights_title': 'Mambo Muhimu ya Jukwaa',
      'highlights_sub':
          'Uzoefu uliopangwa na unaoendelezwa tunaoujenga kwa umakini.',
      'status_planned': 'Imepangwa',
      'status_in_dev': 'Inaendelezwa',
      'status_verify': 'Inategemea utayari wa uzinduzi',
      'f1_t': 'Gundua bidhaa',
      'f1_b': 'Tafuta bidhaa na huduma kupitia uzoefu rahisi wa soko.',
      'f2_t': 'Ungana na wauzaji',
      'f2_b':
          'Chunguza wasifu wa wauzaji na wasiliana kupitia njia zitakazopatikana.',
      'f3_t': 'Maudhui ya bidhaa',
      'f3_b':
          'Uwasilishaji mzuri wa bidhaa, ikiwemo picha na video pale inapowezekana.',
      'f4_t': 'Mwingiliano wa kijamii',
      'f4_b':
          'Vipengele vya ugunduzi wa kijamii vinaandaliwa kwa umuhimu na usalama.',
      'f5_t': 'Bidhaa na huduma za kidijitali',
      'f5_b':
          'Baadhi ya huduma za kidijitali zinaweza kuungwa mkono kadri jukwaa linavyokomaa.',
      'f6_t': 'Ugunduzi wa kisasa',
      'f6_b': 'Uzoefu wa ugunduzi unaobinafsishwa na wa kutafuta unaendelezwa.',
      'how_eyebrow': 'Jinsi Inavyofanya Kazi',
      'how_title': 'Njia rahisi kutoka ugunduzi hadi muunganiko wa sokoni',
      'how_1_t': 'Gundua',
      'how_1_b': 'Tafuta bidhaa na huduma mahali pamoja.',
      'how_2_t': 'Ungana',
      'how_2_b':
          'Chunguza wauzaji na maelezo ya bidhaa kupitia uzoefu wa jukwaa.',
      'how_3_t': 'Nunua',
      'how_3_b':
          'Tumia vipengele vya soko vitakapopatikana wakati wa uzinduzi.',
      'how_note':
          'Mtiririko wa mwisho unaweza kubadilika maendeleo yanapoendelea.',
      'buyers_preview_title': 'Kwa Wanunuzi',
      'buyers_preview_body':
          'Soko Vibe inalenga kuwasaidia wanunuzi kugundua bidhaa na huduma, kuchunguza taarifa za wauzaji, na kufurahia uzoefu wazi wa soko la kidijitali Tanzania.',
      'sellers_preview_title': 'Kwa Wauzaji',
      'sellers_preview_body':
          'Soko Vibe inalenga kuwasaidia wauzaji kuwasilisha bidhaa, kushiriki maudhui, kujenga wasifu, na kufikia wateja wanaowezekana. Matokeo hutegemea mambo mengi; mauzo hayajahakikishwa.',
      'trust_title': 'Uaminifu na Usalama',
      'trust_body':
          'Tunajenga Soko Vibe kwa kuzingatia mwingiliano salama wa sokoni, sera zilizo wazi, na muundo unaowajibika wa jukwaa. Vipengele maalum vya malipo, escrow, uthibitishaji wa utambulisho, na ulinzi wa miamala vitaelezwa kuwa vinapatikana tu vikithibitishwa na kufanya kazi.',
      'trust_note':
          'Vipengele vya usalama na ulinzi vinawasilishwa kulingana na hali halisi ya utekelezaji.',
      'faq_preview_title': 'Maswali ya Kawaida',
      'faq_view_all': 'Tazama maswali yote',
      'q1': 'Soko Vibe ni nini?',
      'a1':
          'Soko Vibe ni jukwaa la biashara ya kijamii na soko la kidijitali linaloendelezwa kwa Tanzania.',
      'q2': 'Je, Soko Vibe ipo hewani sasa?',
      'a2':
          'Bado. Programu ya simu na jukwaa bado vinaendelezwa. Tovuti hii inatoa taarifa za uzinduzi.',
      'q3': 'Soko Vibe itazinduliwa lini?',
      'a3':
          'Tarehe rasmi ya uzinduzi bado haijatangazwa. Jiunge na orodha kupata taarifa.',
      'q4': 'Wanunuzi watarajie nini?',
      'a4':
          'Wanunuzi watarajie uzoefu wa soko unaolenga ugunduzi. Vipengele maalum vitathibitishwa vitakapopatikana.',
      'q5': 'Wauzaji watarajie nini?',
      'a5':
          'Wauzaji watarajie zana za kuwasilisha bidhaa na kufikia wanunuzi jukwaa litakapozindua. Hatuahidi mauzo au mapato.',
      'q6': 'Je, barua pepe yangu iko salama?',
      'a6':
          'Tunatumia barua pepe za orodha kwa mawasiliano ya uzinduzi uliyokubali. Tazama Sera ya Faragha kwa maelezo.',
      'q7': 'Soko Vibe ni kwa ajili ya nani?',
      'a7':
          'Soko Vibe ni kwa watu wa Tanzania wanaopenda uzoefu wa kisasa wa soko, wakiwemo wanunuzi na wauzaji.',
      'foot_tag': 'Soko Vibe — inajenga uzoefu wa kisasa wa soko kwa Tanzania.',
      'foot_desc':
          'Jukwaa la biashara ya kijamii na soko la kidijitali linaloendelezwa, likiwaunganisha wanunuzi na wauzaji kwa uwazi na uaminifu.',
      'foot_contact': 'Mawasiliano',
      'foot_links': 'Viungo',
      'foot_buyers': 'Wanunuzi',
      'foot_sellers': 'Wauzaji',
      'foot_privacy': 'Sera ya Faragha',
      'foot_terms': 'Masharti na Vigezo',
      'foot_cookie': 'Sera ya Vidakuzi',
      'foot_contact_page': 'Mawasiliano',
      'foot_rights': 'Hakimiliki © 2026 Soko Vibe. Haki zote zimehifadhiwa.',
      'contact_title': 'Wasiliana Nasi',
      'contact_sub': 'Tutumie ujumbe na tutajibu kupitia njia rasmi za msaada.',
      'contact_name': 'Jina (si lazima)',
      'contact_email': 'Anwani ya barua pepe',
      'contact_subject': 'Mada',
      'contact_message': 'Ujumbe',
      'contact_submit': 'Tuma Ujumbe',
      'contact_loading': 'Inatuma...',
      'contact_success': 'Asante. Ujumbe wako umepokelewa.',
      'contact_error': 'Imeshindikana kutuma ujumbe. Tafadhali jaribu tena.',
      'contact_invalid':
          'Tafadhali jaza sehemu zinazohitajika kwa taarifa sahihi.',
      'contact_privacy':
          'Tunatumia maelezo yako ya mawasiliano kujibu ujumbe wako tu.',
      'page_about_title': 'Kuhusu Soko Vibe',
      'page_how_title': 'Jinsi Inavyofanya Kazi',
      'page_features_title': 'Vipengele',
      'page_buyers_title': 'Kwa Wanunuzi',
      'page_sellers_title': 'Kwa Wauzaji',
      'page_pricing_title': 'Bei',
      'page_pricing_pending': 'Taarifa za bei zitatangazwa karibu na uzinduzi.',
      'page_faq_title': 'Maswali Yanayoulizwa Mara kwa Mara',
      'page_404_title': 'Ukurasa haujapatikana',
      'page_404_body': 'Ukurasa unaoutafuta unaweza kuwa umehamishwa au haupo.',
      'page_404_home': 'Rudi Mwanzo',
      'waitlist_success_title': 'Uko kwenye orodha',
      'waitlist_success_body':
          'Asante kwa kujiunga na Soko Vibe. Tutatuma taarifa za uzinduzi kwenye barua pepe uliyotoa matangazo muhimu yatakapokuwa tayari.',
      'waitlist_success_cta': 'Rudi Mwanzo',
      'faq_g1_q': 'Soko Vibe ni nini?',
      'faq_g1_a':
          'Soko Vibe ni jukwaa la biashara ya kijamii na soko la kidijitali linaloendelezwa kwa Tanzania.',
      'faq_g2_q': 'Je, programu ipo sasa?',
      'faq_g2_a':
          'Hapana. Programu ya simu na jukwaa vinaendelezwa. Jiunge na orodha kupata taarifa za uzinduzi.',
      'faq_g3_q': 'Nipateje taarifa za uzinduzi?',
      'faq_g3_a':
          'Wasilisha barua pepe yako kupitia fomu ya orodha na ukubali kupokea mawasiliano ya uzinduzi.',
      'faq_g4_q': 'Ninaweza kununua bidhaa leo?',
      'faq_g4_a':
          'Si kupitia soko lililozinduliwa bado. Vipengele na upatikanaji vitatangazwa wakati wa uzinduzi.',
      'faq_g5_q': 'Ninaweza kuuza kwenye Soko Vibe?',
      'faq_g5_a':
          'Maelezo ya usajili wa wauzaji yatatangazwa karibu na uzinduzi. Jiunge kama muuzaji kupata taarifa.',
      'faq_g6_q': 'Je, malipo na escrow vipo hewani?',
      'faq_g6_a':
          'Vipengele vya malipo na ulinzi wa miamala vitaelezwa kuwa vinapatikana tu vikithibitishwa na kufanya kazi.',
      'faq_g7_q': 'Je, Soko Vibe ni salama?',
      'faq_g7_a':
          'Tunabuni kwa kuzingatia usalama na tunawasilisha ulinzi maalum kulingana na utekelezaji uliothibitishwa. Tazama kurasa za kisheria.',
      'faq_g8_q': 'Je, bei zitatangazwa?',
      'faq_g8_a':
          'Bei zitatangazwa karibu na uzinduzi isipokuwa mipango iliyothibitishwa itachapishwa rasmi.',
      'faq_g9_q': 'Ninawezaje kuwasiliana na msaada?',
      'faq_g9_a':
          'Tumia ukurasa wa Mawasiliano au barua pepe support@sokovibe.co.tz.',
      'faq_g10_q': 'Niondoaje barua pepe yangu kwenye orodha?',
      'faq_g10_a':
          'Tuma barua pepe kwa support@sokovibe.co.tz kutoka anwani uliyotumia na omba kuondolewa kwenye taarifa za uzinduzi.',
    },
  };
}

class AppStringsProvider extends InheritedWidget {
  final AppStrings strings;
  const AppStringsProvider({
    super.key,
    required this.strings,
    required super.child,
  });
  @override
  bool updateShouldNotify(AppStringsProvider old) =>
      old.strings.code != strings.code;
}

extension StringsX on BuildContext {
  String str(String key) => AppStrings.of(this).t(key);
}
