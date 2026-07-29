import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SOKO VIBE PRIVACY POLICY', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 4),
              Text('Last Updated: 29 July 2026 | Effective Date: 29 July 2026', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 24),

              _section(cs, '1. INTRODUCTION AND SCOPE',
                '1.1 This Privacy Policy ("Policy") constitutes a legally binding agreement between you ("User", "you", "your", "Data Subject") and Soko Vibe ("we", "our", "us", "the Company", "the Platform"), a company duly registered and operating under the laws of the United Republic of Tanzania.\n\n'
                '1.2 This Policy governs the collection, use, storage, processing, transfer, disclosure, and protection of your personal data when you access, register on, or use the Soko Vibe mobile application, website, or any related services, features, content, or applications (collectively, the "Services").\n\n'
                '1.3 By accessing or using our Services in any manner whatsoever, you explicitly acknowledge that you have read, understood, and freely consent to all terms of this Policy. If you do not agree with any provision of this Policy, you must IMMEDIATELY cease using our Services and delete your account.\n\n'
                '1.4 This Policy is supplementary to and should be read in conjunction with our Terms of Service. In the event of any conflict between this Policy and the Terms of Service, the Terms of Service shall prevail unless this Policy provides greater protection for your personal data.\n\n'
                '1.5 We reserve the absolute right to modify, amend, update, or replace this Policy at any time without prior notice. Any modifications shall become effective IMMEDIATELY upon posting on the Platform. Your continued use of the Services after any modification constitutes your UNCONDITIONAL acceptance of the modified Policy.\n\n'
                '1.6 It is your SOLE RESPONSIBILITY to review this Policy periodically. We strongly recommend that you check this page regularly for any changes. We will notify registered users of MATERIAL changes via email or in-app notification, but failure to receive such notification shall not invalidate the changes.\n\n'
                '1.7 This Policy applies to all users of the Platform, including but not limited to buyers, sellers, riders, drivers, and visitors who browse the Platform without registering.'),

              _section(cs, '2. DEFINITIONS AND INTERPRETATION',
                '2.1 "Personal Data" means any information relating to an identified or identifiable natural person, including but not limited to name, identification number, location data, online identifier, or any one or more factors specific to the physical, physiological, genetic, mental, economic, cultural, or social identity of that person.\n\n'
                '2.2 "Sensitive Personal Data" means data revealing racial or ethnic origin, political opinions, religious or philosophical beliefs, trade union membership, genetic data, biometric data for unique identification, data concerning health, or data concerning a natural person\'s sex life or sexual orientation.\n\n'
                '2.3 "Processing" means any operation or set of operations performed on personal data, whether or not by automated means, including collection, recording, organization, structuring, storage, adaptation, retrieval, consultation, use, disclosure, dissemination, erasure, or destruction.\n\n'
                '2.4 "Data Controller" means Soko Vibe, which determines the purposes and means of processing your personal data.\n\n'
                '2.5 "Data Processor" means any third party that processes personal data on behalf of Soko Vibe.\n\n'
                '2.6 "Data Protection Officer" (DPO) means the designated officer responsible for overseeing our data protection strategy and compliance.\n\n'
                '2.7 "Third Party" means any natural or legal person, public authority, agency, or body other than the data subject, the data controller, the data processor, and persons who are authorized to process data under the direct authority of the data controller or processor.\n\n'
                '2.8 "Consent" means any freely given, specific, informed, and unambiguous indication of your wishes by which you signify agreement to the processing of your personal data.'),

              _section(cs, '3. INFORMATION WE COLLECT — COMPREHENSIVE LIST',
                '3.1 PERSONAL IDENTIFICATION INFORMATION:\n'
                '  a) Full legal name (first name, middle name, last name) as it appears on your government-issued identification.\n'
                '  b) Date of birth and age verification.\n'
                '  c) Gender identity.\n'
                '  d) Nationality and country of residence.\n'
                '  e) Government-issued identification documents, including but not limited to:\n'
                '     i) National Identification Number (NIDA) and ID card image.\n'
                '     ii) Passport number, passport photo, and passport copy.\n'
                '     iii) Driver\'s License number, class, and license copy.\n'
                '     iv) Voter\'s Identification card.\n'
                '     v) Residence permit or work permit (for foreign nationals).\n'
                '  f) Biometric data including facial recognition images (selfies) and fingerprint data where applicable.\n'
                '  g) Signature (electronic or wet-ink scan).\n\n'
                '3.2 CONTACT INFORMATION:\n'
                '  a) Primary email address and any alternative email addresses.\n'
                '  b) Mobile phone number(s) including network operator information.\n'
                '  c) Physical residential address including street name, house number, ward, district, region, and postal code.\n'
                '  d) Business address (if applicable).\n'
                '  e) Emergency contact information including name, relationship, phone number, and email.\n\n'
                '3.3 FINANCIAL INFORMATION:\n'
                '  a) Bank account details including bank name, branch, account number, and account holder name.\n'
                '  b) Mobile money account numbers (M-Pesa, Tigo Pesa, Airtel Money, Halopesa, EzyPesa, etc.).\n'
                '  c) Transaction history including amounts, dates, counterparties, and transaction references.\n'
                '  d) Payment card information (processed through PCI-DSS compliant third-party processors; we NEVER store full card numbers).\n'
                '  e) Wallet balance and transaction logs within the Platform.\n'
                '  f) Payout preferences and withdrawal history.\n'
                '  g) Tax identification number (TIN) and business registration certificates (for business accounts).\n\n'
                '3.4 LOCATION AND MOVEMENT DATA:\n'
                '  a) Real-time precise GPS location data when the app is in use (foreground).\n'
                '  b) Background location data when the app is minimized during active rides, deliveries, or tracking sessions.\n'
                '  c) Historical location data including frequently visited locations, travel patterns, and routes.\n'
                '  d) Geotagged product listing locations.\n'
                '  e) IP address-based approximate location.\n\n'
                '3.5 DEVICE AND TECHNICAL INFORMATION:\n'
                '  a) Device type, model, manufacturer, and operating system version.\n'
                '  b) Unique device identifiers (IMEI, IMSI, Android ID, iOS IDFA, MAC address).\n'
                '  c) IP address (IPv4 and IPv6).\n'
                '  d) Browser type, version, and language settings.\n'
                '  e) Screen resolution, color depth, pixel density, and device orientation.\n'
                '  f) Mobile network operator, connection type (WiFi, 4G, 5G, etc.), signal strength, and network speed.\n'
                '  g) App version, build number, and update channel.\n'
                '  h) Installed apps list and permissions granted.\n'
                '  i) Battery level, storage space, and memory usage.\n'
                '  j) Time zone and regional settings.\n\n'
                '3.6 USAGE AND BEHAVIORAL DATA:\n'
                '  a) Pages viewed, time spent on each page, scroll depth, and interaction patterns.\n'
                '  b) Search queries, search history, and autocomplete interactions.\n'
                '  c) Products viewed, saved to wishlist, shared, or compared.\n'
                '  d) Purchase history including items bought, amounts paid, and return/refund history.\n'
                '  e) Listing history including products listed, edited, boosted, or removed.\n'
                '  f) Ratings and reviews submitted by you and about you.\n'
                '  g) Chat messages, communication history, and call logs within the Platform.\n'
                '  h) Ride history including pickup locations, dropoff locations, routes taken, fare amounts, and driver/rider ratings.\n'
                '  i) Feature usage patterns, clickstream data, and session recordings.\n'
                '  j) Crash reports, error logs, and performance metrics.\n\n'
                '3.7 COMMUNICATIONS DATA:\n'
                '  a) All chat messages exchanged between users, including text, images, voice notes, and files.\n'
                '  b) Customer support tickets, emails, and chat transcripts.\n'
                '  c) Dispute resolution communications and evidence provided.\n'
                '  d) Phone calls made through the Platform\'s call feature.\n'
                '  e) Notification preferences and delivery logs (push, SMS, email, in-app).\n\n'
                '3.8 USER-GENERATED CONTENT:\n'
                '  a) Product listings including images, videos, descriptions, prices, and specifications.\n'
                '  b) Reviews, ratings, comments, and feedback.\n'
                '  c) Profile photos, bios, and status updates.\n'
                '  d) Social media links and shared content.'),

              _section(cs, '4. METHODS OF DATA COLLECTION',
                '4.1 INFORMATION YOU PROVIDE DIRECTLY:\n'
                '  a) Registration and account creation forms.\n'
                '  b) KYC verification submissions (images, documents, selfies).\n'
                '  c) Product listing forms and checkout processes.\n'
                '  d) Communication with other users and customer support.\n'
                '  e) Profile settings and preferences.\n'
                '  f) Feedback, surveys, and promotional participation.\n\n'
                '4.2 INFORMATION COLLECTED AUTOMATICALLY:\n'
                '  a) Through cookies, tracking pixels, and similar technologies.\n'
                '  b) Through server logs and analytics tools.\n'
                '  c) Through device fingerprinting and behavioral analytics.\n'
                '  d) Through GPS, WiFi triangulation, and cell tower positioning.\n'
                '  e) Through session recording and heat mapping tools.\n\n'
                '4.3 INFORMATION FROM THIRD PARTIES:\n'
                '  a) Google Sign-In data (name, email, profile picture).\n'
                '  b) Payment processors (transaction confirmations, payment status).\n'
                '  c) Credit bureaus and fraud prevention databases.\n'
                '  d) Government databases for identity verification.\n'
                '  e) Social media platforms (if you choose to link accounts).\n'
                '  f) Public records and publicly available information.'),

              _section(cs, '5. PURPOSES AND LEGAL BASIS FOR PROCESSING',
                '5.1 We process your personal data for the following purposes, based on the following legal bases:\n\n'
                '5.2 CONTRACTUAL NECESSITY:\n'
                '  a) To create and maintain your account on the Platform.\n'
                '  b) To facilitate transactions between buyers and sellers.\n'
                '  c) To match riders with drivers and process ride-hailing services.\n'
                '  d) To process payments, escrow services, and payouts.\n'
                '  e) To provide customer support and dispute resolution.\n'
                '  f) To deliver products, services, and digital content.\n\n'
                '5.3 LEGAL COMPLIANCE:\n'
                '  a) To comply with the Tanzania Data Protection Act, 2022.\n'
                '  b) To comply with the Tanzania Anti-Money Laundering Act.\n'
                '  c) To comply with the Tanzania Electronic Transactions Act.\n'
                '  d) To comply with tax reporting obligations to the Tanzania Revenue Authority (TRA).\n'
                '  e) To comply with court orders, legal process, or governmental requests.\n'
                '  f) To enforce our Terms of Service and this Privacy Policy.\n'
                '  g) To prevent, detect, and investigate fraud, money laundering, and other illegal activities.\n\n'
                '5.4 LEGITIMATE INTERESTS:\n'
                '  a) To improve, optimize, and personalize the Platform and Services.\n'
                '  b) To analyze user behavior and trends to enhance user experience.\n'
                '  c) To develop new features, products, and services.\n'
                '  d) To ensure the security and integrity of the Platform.\n'
                '  e) To send administrative messages, security alerts, and service updates.\n'
                '  f) To generate aggregated, anonymized analytics and reports.\n'
                '  g) To conduct market research and business planning.\n\n'
                '5.5 CONSENT:\n'
                '  a) To send marketing and promotional communications (withdrawable at any time).\n'
                '  b) To collect precise location data for non-essential features.\n'
                '  c) To use your data for profiling and personalization.\n'
                '  d) To share your data with selected third-party partners for their own purposes.\n'
                '  e) To process sensitive personal data where explicit consent is required.'),

              _section(cs, '6. DATA SHARING AND DISCLOSURE — STRICT CONDITIONS',
                '6.1 GENERAL PRINCIPLE: We DO NOT and WILL NOT sell your personal information to any third party under any circumstances. Any violation of this principle by any employee, contractor, or agent will result in immediate termination and legal action.\n\n'
                '6.2 WE MAY SHARE YOUR INFORMATION WITH THE FOLLOWING CATEGORIES OF RECIPIENTS, SUBJECT TO STRICT CONTRACTUAL OBLIGATIONS:\n'
                '  a) OTHER USERS: As necessary to facilitate transactions and communications between users, including:\n'
                '     i) Sharing your name, photo, and rating with potential transaction partners.\n'
                '     ii) Sharing your pickup location with assigned drivers.\n'
                '     iii) Sharing your delivery address with sellers and delivery partners.\n'
                '     iv) Sharing your phone number with transaction parties after a confirmed transaction.\n\n'
                '  b) SERVICE PROVIDERS AND DATA PROCESSORS (all bound by Data Processing Agreements):\n'
                '     i) Cloud infrastructure providers (Google Cloud Platform, Firebase).\n'
                '     ii) Payment processors (ClickPesa, mobile money operators, banks).\n'
                '     iii) Identity verification services.\n'
                '     iv) Push notification services (OneSignal).\n'
                '     v) SMS gateway providers (Meseji, Twilio-type services).\n'
                '     vi) Image and video hosting services (Cloudinary).\n'
                '     vii) Mapping and location services (Google Maps).\n'
                '     viii) Analytics and crash reporting services.\n'
                '     ix) Email delivery services.\n'
                '     x) Customer support platforms.\n\n'
                '  c) LAW ENFORCEMENT AND REGULATORY AUTHORITIES:\n'
                '     i) When required by applicable law, court order, or legal process.\n'
                '     ii) When we believe in good faith that disclosure is necessary to protect our rights, your safety, or the safety of others.\n'
                '     iii) To investigate, prevent, or take action regarding suspected illegal activities, fraud, or violations of our Terms.\n'
                '     iv) To comply with a valid warrant, subpoena, or other legally binding request.\n\n'
                '  d) BUSINESS TRANSFEREES:\n'
                '     i) In the event of a merger, acquisition, reorganization, bankruptcy, or sale of all or substantially all of our assets.\n'
                '     ii) The acquiring entity will be bound by this Policy and may not use your data in a manner materially different from what is described herein.\n'
                '     iii) You will be notified via email and in-app notification of any such transfer at least 30 days in advance.\n\n'
                '6.3 INTERNATIONAL DATA TRANSFERS:\n'
                '  a) Your data may be transferred to and processed in countries outside Tanzania where our service providers operate.\n'
                '  b) We ensure that appropriate safeguards are in place, including:\n'
                '     i) Standard Contractual Clauses (SCCs) adopted by relevant data protection authorities.\n'
                '     ii) Binding Corporate Rules (BCRs) where applicable.\n'
                '     iii) Verification that the recipient country has adequate data protection laws.\n'
                '  c) You explicitly consent to such international transfers by using our Services.\n\n'
                '6.4 WE WILL NEVER:\n'
                '  a) Sell your personal information to any third party.\n'
                '  b) Rent or lease your personal information.\n'
                '  c) Share your sensitive personal data without your explicit consent.\n'
                '  d) Use your data for purposes incompatible with those disclosed in this Policy without obtaining your consent.'),

              _section(cs, '7. DATA RETENTION AND DELETION POLICY',
                '7.1 RETENTION PERIODS:\n'
                '  a) Active Account Data: Retained for the duration of your account\'s active status.\n'
                '  b) Inactive Account Data: Retained for a period of 12 months after your last login, after which the account may be archived.\n'
                '  c) KYC Documents: Retained for a minimum of 7 years from the date of collection, as required by Tanzanian anti-money laundering and financial regulations.\n'
                '  d) Transaction Records: Retained for a minimum of 7 years from the date of each transaction, as required by the Tanzania Revenue Authority.\n'
                '  e) Chat Messages: Retained for the duration of your account plus 90 days after account deletion.\n'
                '  f) Location Data: Retained in identifiable form for a maximum of 30 days, after which it is aggregated and anonymized.\n'
                '  g) Logs and Analytics Data: Retained for a period of 12 months.\n'
                '  h) Marketing Preferences and Consent Records: Retained for the duration of your account plus 3 years.\n\n'
                '7.2 ACCOUNT DELETION:\n'
                '  a) You may request deletion of your account through the Settings menu or by contacting our support team.\n'
                '  b) Upon receiving your deletion request, we will:\n'
                '     i) Deactivate your account within 48 hours.\n'
                '     ii) Retain your data for 90 days (the "Cooling-Off Period") during which you may reverse the deletion.\n'
                '     iii) Permanently delete your personal data after the Cooling-Off Period, subject to legal retention requirements.\n'
                '  c) Data required for legal, regulatory, or audit purposes will be retained for the legally mandated period even after account deletion.\n'
                '  d) We will provide you with a confirmation of deletion upon completion.\n\n'
                '7.3 DATA ANONYMIZATION:\n'
                '  a) Where data is retained beyond the deletion period for analytical purposes, it will be anonymized such that you cannot be identified.\n'
                '  b) Anonymized data is not considered personal data and may be used indefinitely.\n\n'
                '7.4 BACKUP RETENTION:\n'
                '  a) Data may persist in backup systems for up to 30 days after deletion from the primary system.\n'
                '  b) Backups are protected by the same security measures as production systems.'),

              _section(cs, '8. DATA SECURITY MEASURES',
                '8.1 TECHNICAL MEASURES:\n'
                '  a) End-to-end encryption (E2EE) for all chat messages using industry-standard cryptographic protocols.\n'
                '  b) TLS/SSL encryption (minimum TLS 1.2, preferred TLS 1.3) for all data in transit.\n'
                '  c) AES-256 encryption for sensitive data at rest.\n'
                '  d) Multi-factor authentication (MFA) for administrative accounts and sensitive operations.\n'
                '  e) Role-based access control (RBAC) limiting data access to authorized personnel only.\n'
                '  f) Regular security audits, vulnerability assessments, and penetration testing by independent third parties.\n'
                '  g) Automated intrusion detection and prevention systems (IDPS).\n'
                '  h) Web application firewall (WAF) to protect against common attack vectors.\n'
                '  i) Regular security patches and updates to all systems and dependencies.\n'
                '  j) API rate limiting and request validation to prevent abuse.\n'
                '  k) Database encryption, regular backups, and disaster recovery procedures.\n\n'
                '8.2 ORGANIZATIONAL MEASURES:\n'
                '  a) All employees, contractors, and agents undergo mandatory data protection training on an annual basis.\n'
                '  b) Strict access controls based on the principle of least privilege.\n'
                '  c) Confidentiality agreements binding all personnel who handle personal data.\n'
                '  d) Incident response plan and data breach notification procedures.\n'
                '  e) Designated Data Protection Officer (DPO) overseeing compliance.\n'
                '  f) Regular internal audits of data processing activities.\n\n'
                '8.3 DATA BREACH NOTIFICATION:\n'
                '  a) In the event of a data breach that compromises your personal data, we will notify you within 72 hours of becoming aware of the breach.\n'
                '  b) Notification will include the nature of the breach, categories of data affected, potential consequences, and measures taken to address the breach.\n'
                '  c) We will also notify the relevant data protection authority as required by applicable law.\n'
                '  d) We maintain cyber insurance to cover costs associated with data breach response and liability.\n\n'
                '8.4 DESPITE THE ABOVE MEASURES:\n'
                '  a) No method of electronic storage or transmission is 100% secure.\n'
                '  b) We cannot guarantee absolute security of your data.\n'
                '  c) You are responsible for maintaining the security of your account credentials.\n'
                '  d) We are not liable for unauthorized access resulting from your negligence or failure to follow security best practices.'),

              _section(cs, '9. YOUR RIGHTS AND HOW TO EXERCISE THEM',
                '9.1 UNDER THE TANZANIA DATA PROTECTION ACT, 2022, AND APPLICABLE REGULATIONS, YOU HAVE THE FOLLOWING RIGHTS:\n\n'
                '9.2 RIGHT TO BE INFORMED:\n'
                '  a) You have the right to be informed about the collection and use of your personal data.\n'
                '  b) This Policy serves as our privacy notice to you.\n\n'
                '9.3 RIGHT OF ACCESS:\n'
                '  a) You have the right to access your personal data held by us.\n'
                '  b) You may request a copy of your data in a structured, commonly used, and machine-readable format.\n'
                '  c) We will respond to access requests within 30 days.\n'
                '  d) The first copy is provided free of charge; subsequent copies may incur a reasonable administrative fee.\n\n'
                '9.4 RIGHT TO RECTIFICATION:\n'
                '  a) You have the right to request correction of inaccurate or incomplete personal data.\n'
                '  b) You may update most of your data directly through your account settings.\n'
                '  c) We will process correction requests within 15 days.\n\n'
                '9.5 RIGHT TO ERASURE ("RIGHT TO BE FORGOTTEN"):\n'
                '  a) You have the right to request deletion of your personal data in certain circumstances.\n'
                '  b) This right is not absolute and may be limited by legal obligations, pending transactions, or legitimate interests.\n'
                '  c) We will process deletion requests within 30 days, subject to verification of your identity.\n\n'
                '9.6 RIGHT TO RESTRICT PROCESSING:\n'
                '  a) You have the right to request restriction of processing of your personal data in certain circumstances.\n'
                '  b) While processing is restricted, we may store your data but not use it.\n\n'
                '9.7 RIGHT TO DATA PORTABILITY:\n'
                '  a) You have the right to receive your personal data in a structured, commonly used, and machine-readable format.\n'
                '  b) You have the right to transmit this data to another controller without hindrance.\n\n'
                '9.8 RIGHT TO OBJECT:\n'
                '  a) You have the right to object to processing of your personal data for direct marketing purposes at any time.\n'
                '  b) You have the right to object to processing based on legitimate interests.\n'
                '  c) We will cease processing unless we demonstrate compelling legitimate grounds overriding your interests.\n\n'
                '9.9 RIGHTS RELATED TO AUTOMATED DECISION-MAKING:\n'
                '  a) You have the right not to be subject to decisions based solely on automated processing that produce legal effects concerning you.\n'
                '  b) You may request human intervention in automated decision-making processes.\n'
                '  c) You may challenge decisions made through automated processing.\n\n'
                '9.10 RIGHT TO WITHDRAW CONSENT:\n'
                '  a) Where processing is based on your consent, you have the right to withdraw consent at any time.\n'
                '  b) Withdrawal does not affect the lawfulness of processing based on consent before its withdrawal.\n\n'
                '9.11 RIGHT TO LODGE A COMPLAINT:\n'
                '  a) You have the right to lodge a complaint with the relevant data protection authority in Tanzania.\n'
                '  b) We encourage you to contact us first so we can address your concerns directly.\n\n'
                '9.12 TO EXERCISE ANY OF THESE RIGHTS:\n'
                '  a) Contact us via email at dpo@soko-vibe.com.\n'
                '  b) Use the in-app support feature.\n'
                '  c) Write to us at our registered address.\n'
                '  d) We may require proof of identity before processing your request.\n'
                '  e) We will respond to all legitimate requests within 30 days, or within the timeframe required by applicable law.'),

              _section(cs, '10. COOKIES AND TRACKING TECHNOLOGIES',
                '10.1 We use the following categories of cookies and tracking technologies:\n'
                '  a) Strictly Necessary Cookies: Required for the Platform to function properly. Cannot be disabled.\n'
                '  b) Performance Cookies: Collect anonymous usage data for analytics and optimization.\n'
                '  c) Functional Cookies: Remember your preferences and settings.\n'
                '  d) Targeting/Advertising Cookies: Deliver relevant advertisements and measure ad effectiveness.\n\n'
                '10.2 Third-Party Tracking:\n'
                '  a) We use analytics services (Firebase Analytics, Google Analytics) that may set their own cookies.\n'
                '  b) We use advertising networks that may use cookies to serve targeted ads.\n'
                '  c) We are not responsible for the privacy practices of these third parties.\n\n'
                '10.3 Your Choices:\n'
                '  a) You can control cookies through your device settings and browser preferences.\n'
                '  b) Disabling certain cookies may affect the functionality of the Platform.\n'
                '  c) You can opt out of targeted advertising through your device advertising settings.'),

              _section(cs, '11. CHILDREN\'S PRIVACY — STRICT RESTRICTIONS',
                '11.1 Our Services are STRICTLY PROHIBITED for individuals under the age of 18 (eighteen) years.\n\n'
                '11.2 We do not knowingly collect, use, or process personal information from individuals under 18 years of age.\n\n'
                '11.3 If we become aware that a person under 18 has provided us with personal data, we will:\n'
                '  a) Immediately delete such data from our systems.\n'
                '  b) Permanently suspend the associated account.\n'
                '  c) Report the incident to relevant authorities if required by law.\n\n'
                '11.4 If you believe a child under 18 has provided us with personal data, you must contact us immediately at dpo@soko-vibe.com.\n\n'
                '11.5 We reserve the right to verify the age of any user through document verification or other means.\n\n'
                '11.6 Any user found to be under 18 or to have falsified their age shall have their account immediately terminated and all data deleted.'),

              _section(cs, '12. THIRD-PARTY SERVICES AND LINKS',
                '12.1 Our Platform integrates with and links to third-party services, including but not limited to:\n'
                '  a) Google Services (Firebase, Google Maps, Google Sign-In, Google Ads, Crashlytics, Performance Monitoring).\n'
                '  b) OneSignal (Push Notifications).\n'
                '  c) Cloudinary (Image and Video Hosting).\n'
                '  d) ClickPesa (Payment Processing).\n'
                '  e) Meseji (SMS Gateway).\n'
                '  f) Groq AI (AI Assistant Services).\n'
                '  g) Social media platforms (Facebook, Instagram, Twitter, WhatsApp).\n\n'
                '12.2 These third-party services have their own privacy policies governing the collection, use, and disclosure of your information.\n\n'
                '12.3 We STRONGLY ENCOURAGE you to review the privacy policies of these third parties before using their services.\n\n'
                '12.4 We are NOT RESPONSIBLE for the privacy practices, data handling, or security of any third-party services.\n\n'
                '12.5 Links to external websites or services are provided for your convenience and do not constitute endorsement.'),

              _section(cs, '13. MARKETING AND COMMUNICATIONS',
                '13.1 By creating an account, you consent to receive the following communications from us:\n'
                '  a) Transactional communications (order confirmations, payment receipts, shipping updates, ride confirmations) — these are mandatory and cannot be opted out of.\n'
                '  b) Security alerts (password changes, login notifications, suspicious activity alerts) — these are mandatory.\n'
                '  c) Service announcements (maintenance notices, policy changes, feature updates) — these are mandatory.\n'
                '  d) Marketing and promotional communications (special offers, discounts, new features, events) — these are OPTIONAL.\n\n'
                '13.2 You may opt out of marketing communications at any time by:\n'
                '  a) Toggling notification preferences in Settings.\n'
                '  b) Clicking the "Unsubscribe" link in email communications.\n'
                '  c) Contacting our support team.\n\n'
                '13.3 Even if you opt out of marketing, you will continue to receive mandatory transactional and security communications.\n\n'
                '13.4 We do not use your personal data for marketing purposes without your explicit consent.\n\n'
                '13.5 We do not share your personal data with third parties for their own marketing purposes without your explicit consent.'),

              _section(cs, '14. COMPLAINTS AND DISPUTE RESOLUTION',
                '14.1 If you have a complaint or concern about our handling of your personal data, please contact our Data Protection Officer at dpo@soko-vibe.com.\n\n'
                '14.2 We will acknowledge receipt of your complaint within 5 business days and provide a substantive response within 30 days.\n\n'
                '14.3 If you are dissatisfied with our response, you have the right to lodge a complaint with:\n'
                '  a) The Tanzania Data Protection Authority (once established).\n'
                '  b) The relevant sector regulator.\n'
                '  c) A court of competent jurisdiction in Tanzania.\n\n'
                '14.4 Any legal disputes arising from this Policy shall be governed by the laws of the United Republic of Tanzania and subject to the exclusive jurisdiction of the courts of Dar es Salaam, Tanzania.\n\n'
                '14.5 Nothing in this Policy limits your statutory rights under applicable data protection laws.'),

              _section(cs, '15. DATA PROTECTION OFFICER CONTACT',
                '15.1 We have appointed a Data Protection Officer (DPO) to oversee compliance with this Policy and applicable data protection laws.\n\n'
                '15.2 You may contact our DPO regarding any matter related to data protection and privacy:\n\n'
                '  Data Protection Officer\n'
                '  Soko Vibe Limited\n'
                '  Email: dpo@soko-vibe.com\n'
                '  Phone: +255 7XX XXX XXX\n'
                '  Address: Dar es Salaam, Tanzania\n\n'
                '  For general inquiries: support@soko-vibe.com\n\n'
                '15.3 Please clearly state the nature of your inquiry to ensure prompt handling.'),

              _section(cs, '16. CHANGES TO THIS PRIVACY POLICY',
                '16.1 We reserve the ABSOLUTE RIGHT to modify, amend, update, or replace this Policy at any time, for any reason, without prior notice.\n\n'
                '16.2 Changes become EFFECTIVE IMMEDIATELY upon posting on the Platform.\n\n'
                '16.3 For MATERIAL changes, we will make reasonable efforts to notify you via:\n'
                '  a) Email to your registered email address.\n'
                '  b) In-app notification.\n'
                '  c) A prominent notice on the Platform.\n\n'
                '16.4 Your continued use of the Platform after any changes constitutes your UNCONDITIONAL ACCEPTANCE of the modified Policy.\n\n'
                '16.5 If you do not agree with any changes, your SOLE REMEDY is to immediately stop using the Platform and delete your account.\n\n'
                '16.6 It is your RESPONSIBILITY to review this Policy regularly. We recommend checking this page at least once per month.'),

              _section(cs, '17. GOVERNING LAW AND JURISDICTION',
                '17.1 This Privacy Policy shall be governed by and construed in accordance with the laws of the United Republic of Tanzania, including but not limited to:\n'
                '  a) The Tanzania Data Protection Act, 2022.\n'
                '  b) The Electronic and Postal Communications Act, 2010.\n'
                '  c) The Anti-Money Laundering Act, 2006, as amended.\n'
                '  d) The Cybercrimes Act, 2015.\n'
                '  e) The Tanzania Communications Regulatory Authority Act, 2003.\n\n'
                '17.2 Any dispute arising from this Policy shall be subject to the exclusive jurisdiction of the courts of Dar es Salaam, Tanzania.\n\n'
                '17.3 Nothing in this Policy shall limit any legal remedies available to us under applicable law.'),

              _section(cs, '18. ACKNOWLEDGMENT AND ACCEPTANCE',
                '18.1 BY USING THE PLATFORM, YOU EXPLICITLY ACKNOWLEDGE THAT:\n'
                '  a) You have read and understood this entire Privacy Policy.\n'
                '  b) You consent to the collection, use, processing, and disclosure of your personal data as described herein.\n'
                '  c) You agree to the data retention periods specified herein.\n'
                '  d) You consent to international data transfers as described herein.\n'
                '  e) You acknowledge that this Policy may change without prior notice and you agree to be bound by such changes.\n\n'
                '18.2 IF YOU DO NOT AGREE WITH ANY PART OF THIS POLICY, YOU MUST IMMEDIATELY CEASE USING THE PLATFORM AND DELETE YOUR ACCOUNT.\n\n'
                '18.3 CONTINUED USE OF THE PLATFORM CONSTITUTES YOUR EXPLICIT ACCEPTANCE OF THIS POLICY IN ITS ENTIRETY.'),

              const SizedBox(height: 32),
              Center(
                child: Text('© 2026 Soko Vibe Limited. All rights reserved.',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(ColorScheme cs, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 14, height: 1.6, color: cs.onSurface.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}
