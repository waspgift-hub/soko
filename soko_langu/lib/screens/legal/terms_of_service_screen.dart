import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SOKO VIBE TERMS OF SERVICE', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 4),
              Text('Last Updated: 29 July 2026 | Effective Date: 29 July 2026', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 24),

              _section(cs, '1. ACCEPTANCE OF TERMS — LEGALLY BINDING AGREEMENT',
                '1.1 By downloading, installing, accessing, browsing, registering on, or using Soko Vibe ("the Platform") in any manner whatsoever, you acknowledge, represent, warrant, and agree that you have read, understood, and agree to be LEGALLY BOUND by these Terms of Service ("Terms", "Agreement"), whether or not you are a registered user.\n\n'
                '1.2 These Terms constitute a VALID, BINDING, AND ENFORCEABLE LEGAL CONTRACT between you ("User", "you", "your") and Soko Vibe ("we", "our", "us", "the Company", "the Platform").\n\n'
                '1.3 If you do not UNCONDITIONALLY agree to these Terms in their entirety, you MUST NOT access or use the Platform in any way, and you must immediately delete the application and any related materials in your possession.\n\n'
                '1.4 We reserve the ABSOLUTE AND UNILATERAL right to modify, amend, update, supplement, suspend, or terminate these Terms at any time, for any reason, with or without notice. Changes become EFFECTIVE IMMEDIATELY upon posting on the Platform.\n\n'
                '1.5 Your continued use of the Platform after any changes constitutes your UNQUALIFIED ACCEPTANCE of the modified Terms. If you do not agree with any modification, your SOLE AND EXCLUSIVE REMEDY is to immediately stop using the Platform and delete your account.\n\n'
                '1.6 It is your SOLE RESPONSIBILITY to review these Terms periodically. We recommend checking this page at least once per month. We may notify registered users of material changes via email or in-app notification, but failure to receive such notification shall not invalidate the changes or your acceptance thereof.\n\n'
                '1.7 These Terms may be published in multiple languages for convenience. In the event of any conflict or inconsistency between different language versions, the English language version shall prevail and be binding.'),

              _section(cs, '2. ELIGIBILITY, REGISTRATION, AND ACCOUNT REQUIREMENTS',
                '2.1 AGE REQUIREMENT: You MUST be at least 18 (eighteen) years of age to use the Platform. By using the Platform, you represent and warrant under penalty of perjury that you are at least 18 years old.\n\n'
                '2.2 LEGAL CAPACITY: You must have the full legal capacity to enter into binding contracts. If you are using the Platform on behalf of a business or entity, you represent and warrant that you have the authority to bind that entity to these Terms.\n\n'
                '2.3 ACCURATE INFORMATION: You must provide accurate, current, and complete registration information. You agree to update your information promptly if it changes. Providing false or misleading information is a material breach of these Terms.\n\n'
                '2.4 SINGLE ACCOUNT ONLY: Each natural person or legal entity may maintain only ONE (1) account on the Platform. Creating, attempting to create, or maintaining multiple accounts is STRICTLY PROHIBITED and will result in the immediate and permanent suspension of all associated accounts and forfeiture of any balances or benefits.\n\n'
                '2.5 ACCOUNT SECURITY: You are SOLELY AND FULLY RESPONSIBLE for:\n'
                '  a) Maintaining the confidentiality of your password, login credentials, and authentication tokens.\n'
                '  b) All activities that occur under your account, whether authorized by you or not.\n'
                '  c) Immediately notifying us of any unauthorized use of your account or security breach.\n'
                '  d) Ensuring that you log out of your account at the end of each session, especially on shared devices.\n\n'
                '2.6 ACCOUNT SUSPENSION AND TERMINATION: We reserve the ABSOLUTE RIGHT to refuse registration, suspend, terminate, or restrict your account at our SOLE DISCRETION, without prior notice, liability, or obligation to provide reasons. Grounds for suspension or termination include but are not limited to:\n'
                '  a) Violation of any provision of these Terms.\n'
                '  b) Suspicion of fraudulent, abusive, or illegal activity.\n'
                '  c) Providing false, misleading, or incomplete information.\n'
                '  d) Multiple account creation.\n'
                '  e) Engaging in prohibited activities as defined in Section 4.\n'
                '  f) Receiving an excessive number of complaints or negative ratings.\n'
                '  g) Failure to complete KYC verification when required.\n'
                '  h) Any activity that, in our sole judgment, poses a risk to the Platform, its users, or our reputation.\n\n'
                '2.7 ACCOUNT DELETION: You may delete your account at any time through the Settings menu. Upon deletion, your account will be deactivated immediately and permanently deleted after a 90-day cooling-off period, subject to legal data retention requirements.\n\n'
                '2.8 KYC VERIFICATION: Users who wish to sell products on the Platform must submit to KYC (Know Your Customer) verification. KYC approval is at the SOLE DISCRETION of the Platform administrator. Without KYC approval, sellers may list a maximum of FIVE (5) products. Sellers may be required to undergo periodic re-verification.'),

              _section(cs, '3. PLATFORM SERVICES — ROLE AND LIMITATIONS',
                '3.1 Soko Vibe provides a technology platform that connects:\n'
                '  a) Buyers and sellers of goods and services (Marketplace Services).\n'
                '  b) Riders and drivers for transportation (Ride-Hailing Services).\n'
                '  c) Users with AI-powered assistant features.\n'
                '  d) Users with communication, payment, and delivery facilitation tools.\n\n'
                '3.2 ROLE AS INTERMEDIARY: We act SOLELY as an intermediary/platform provider. We are NOT:\n'
                '  a) A party to any transaction between buyers and sellers.\n'
                '  b) A party to any ride-hailing agreement between riders and drivers.\n'
                '  c) An employer, principal, or joint venture partner of any seller, driver, or service provider.\n'
                '  d) A provider of transportation, delivery, or logistics services.\n'
                '  e) A financial institution, bank, or payment service provider (except as an agent for payment processing).\n\n'
                '3.3 NO WARRANTY OF TRANSACTIONS: We make NO REPRESENTATIONS OR WARRANTIES regarding the quality, safety, legality, or suitability of any products, services, rides, or transactions facilitated through the Platform. All transactions are AT YOUR OWN RISK.\n\n'
                '3.4 ESCROW SERVICES: We facilitate payments through third-party payment processors. Funds are held in escrow according to our payment policy. We are not a bank and do not hold deposits or provide financial services.\n\n'
                '3.5 SERVICE MODIFICATION: We reserve the ABSOLUTE RIGHT to modify, suspend, restrict, or discontinue any aspect of the Services at any time, with or without notice, and without liability to you or any third party.\n\n'
                '3.6 SERVICE AVAILABILITY: We do not guarantee that the Platform will be available at all times, uninterrupted, error-free, or free from viruses or other harmful components. We may perform maintenance, updates, or upgrades at any time without notice.'),

              _section(cs, '4. PROHIBITED ACTIVITIES — STRICT ZERO-TOLERANCE POLICY',
                '4.1 The following activities are STRICTLY PROHIBITED on the Platform. Violation of any of these provisions constitutes a MATERIAL BREACH of these Terms and will result in IMMEDIATE AND PERMANENT ACCOUNT TERMINATION, forfeiture of any balances, and potentially referral to law enforcement authorities:\n\n'
                '4.2 ILLEGAL ACTIVITIES:\n'
                '  a) Using the Platform for any unlawful purpose or in violation of any applicable local, national, or international law.\n'
                '  b) Engaging in money laundering, terrorist financing, or any financial crime.\n'
                '  c) Listing, selling, or facilitating the sale of illegal items including but not limited to:\n'
                '     i) Illegal drugs, narcotics, and controlled substances.\n'
                '     ii) Weapons, firearms, ammunition, explosives, and weapon accessories.\n'
                '     iii) Counterfeit, replica, or pirated goods.\n'
                '     iv) Stolen property or items obtained through illegal means.\n'
                '     v) Hazardous, toxic, or dangerous materials.\n'
                '     vi) Human remains, body parts, or bodily fluids.\n'
                '     vii) Endangered species or products made from endangered species.\n'
                '     viii) Pornographic, obscene, or sexually explicit materials.\n'
                '     ix) Items that infringe intellectual property rights.\n'
                '     x) Any item whose sale is prohibited by Tanzanian law.\n\n'
                '4.3 FRAUDULENT AND DECEPTIVE ACTIVITIES:\n'
                '  a) Posting false, misleading, deceptive, or fraudulent listings, reviews, or content.\n'
                '  b) Misrepresenting the condition, authenticity, origin, or specifications of products.\n'
                '  c) Engaging in price manipulation, shill bidding, or fake transactions.\n'
                '  d) Creating fake accounts, fake reviews, or artificially inflating ratings.\n'
                '  e) Impersonating any person or entity, or falsely claiming affiliation.\n'
                '  f) Using stolen or fraudulent payment methods.\n'
                '  g) Chargeback fraud or disputing legitimate transactions without valid reason.\n\n'
                '4.4 ABUSIVE AND HARMFUL CONDUCT:\n'
                '  a) Harassing, abusing, threatening, stalking, intimidating, or bullying other users.\n'
                '  b) Posting hate speech, discriminatory content, or content that incites violence.\n'
                '  c) Sharing personal information of others without their explicit consent (doxxing).\n'
                '  d) Making false accusations, defamatory statements, or malicious reports.\n'
                '  e) Engaging in any form of discrimination based on race, ethnicity, gender, religion, age, disability, or sexual orientation.\n\n'
                '4.5 TECHNICAL VIOLATIONS:\n'
                '  a) Uploading malicious code, viruses, worms, Trojan horses, or any harmful software.\n'
                '  b) Attempting to hack, crack, bypass, or disable any security measures, encryption, or access controls.\n'
                '  c) Reverse engineering, decompiling, disassembling, or attempting to derive source code.\n'
                '  d) Using automated bots, scrapers, crawlers, spiders, or scripts to access the Platform without our express written permission.\n'
                '  e) Interfering with or disrupting the Platform\'s servers, networks, or operations.\n'
                '  f) Performing penetration testing or vulnerability scanning without prior written authorization.\n'
                '  g) Attempting to overwhelm the Platform through denial-of-service (DOS) or distributed denial-of-service (DDOS) attacks.\n\n'
                '4.6 MARKETPLACE VIOLATIONS:\n'
                '  a) Completing transactions outside the Platform to avoid fees (including exchanging contact information expressly for this purpose).\n'
                '  b) Manipulating search results, categories, or tags.\n'
                '  c) Listing products in incorrect categories.\n'
                '  d) Creating duplicate listings for the same product.\n'
                '  e) Listing services without proper licensing or qualifications where required.\n'
                '  f) Failing to fulfill orders after accepting payment.\n'
                '  g) Refusing to deliver products after receiving payment.\n'
                '  h) Demanding additional payment outside the Platform\'s payment system.\n\n'
                '4.7 PENALTIES FOR VIOLATION:\n'
                '  a) IMMEDIATE AND PERMANENT ACCOUNT SUSPENSION.\n'
                '  b) FORFEITURE of any pending payments, wallet balances, or benefits.\n'
                '  c) REFERRAL to law enforcement authorities for criminal prosecution.\n'
                '  d) CIVIL LIABILITY for all damages, costs, and expenses incurred by us or affected parties.\n'
                '  e) PERMANENT BAN from using the Platform or any associated services.\n'
                '  f) PUBLICATION of the violation (without personal data) as a deterrent to others.\n\n'
                '4.8 There is NO WARNING SYSTEM for prohibited activities. Violation results in immediate action without prior notice.'),

              _section(cs, '5. LISTING AND SELLING — STRICT REQUIREMENTS',
                '5.1 PRODUCT ACCURACY: Sellers must provide ACCURATE, TRUTHFUL, and COMPLETE descriptions of products, including:\n'
                '  a) Accurate condition (new, used, refurbished, etc.) with all defects disclosed.\n'
                '  b) Correct pricing in Tanzanian Shillings (TZS) inclusive of all applicable taxes.\n'
                '  c) Authentic, clear, and non-misleading images that accurately represent the actual item.\n'
                '  d) Accurate specifications, dimensions, colors, materials, and features.\n'
                '  e) Correct categorization and subcategorization.\n'
                '  f) Accurate stock levels and availability.\n\n'
                '5.2 ORDER FULFILLMENT:\n'
                '  a) Sellers MUST fulfill confirmed orders within the stated processing time.\n'
                '  b) If unable to fulfill, the seller MUST immediately notify the buyer and initiate a full refund.\n'
                '  c) Failure to fulfill orders may result in account penalties, suspension, or termination.\n'
                '  d) Sellers are responsible for ensuring products reach buyers in the condition described.\n\n'
                '5.3 KYC AND PRODUCT LIMITS:\n'
                '  a) Sellers without KYC approval may list a MAXIMUM of FIVE (5) products.\n'
                '  b) To list more than 5 products, sellers MUST complete KYC verification AND obtain admin approval.\n'
                '  c) KYC approval is at the SOLE DISCRETION of Platform administrators.\n'
                '  d) KYC-approved sellers are subject to periodic re-verification.\n'
                '  e) KYC status may be REVOKED by admin at any time for violation of these Terms.\n'
                '  f) KYC revocation results in immediate reduction of product listing limit to 5.\n\n'
                '5.4 PROHIBITED LISTINGS (in addition to Section 4.2):\n'
                '  a) Digital products that infringe intellectual property rights.\n'
                '  b) Services requiring professional licenses, without proof of valid licensing.\n'
                '  c) Gift cards, vouchers, or stored-value items subject to fraud risk.\n'
                '  d) Listings that redirect buyers to external websites or platforms.\n'
                '  e) Pre-orders or back-orders without clear disclosure of delivery timelines.\n\n'
                '5.5 PRICING:\n'
                '  a) All prices MUST be listed in Tanzanian Shillings (TZS).\n'
                '  b) Prices MUST include all applicable taxes, fees, and charges unless otherwise explicitly stated.\n'
                '  c) Sellers may not charge different prices than those listed on the Platform.\n'
                '  d) We reserve the right to remove or adjust obviously erroneous pricing.\n\n'
                '5.6 PRODUCT REMOVAL:\n'
                '  a) We reserve the right to remove any listing at our sole discretion without notice or explanation.\n'
                '  b) Removed listings do not count toward the seller\'s product limit if removed due to policy violation.\n'
                '  c) Sellers may not relist removed products without our express permission.'),

              _section(cs, '6. BUYING AND PAYMENTS — BINDING OBLIGATIONS',
                '6.1 PURCHASE OBLIGATION: By clicking "Buy" or "Confirm Purchase" or any equivalent action, you enter into a LEGALLY BINDING AGREEMENT to pay the total amount specified, including product price, delivery fees, and any applicable taxes.\n\n'
                '6.2 PAYMENT METHODS: We accept payment through mobile money (M-Pesa, Tigo Pesa, Airtel Money, Halopesa, EzyPesa), bank transfers, and other methods as made available. Available methods may vary based on location, transaction value, and other factors.\n\n'
                '6.3 ESCROW SYSTEM:\n'
                '  a) Payments are held in escrow by our payment processor until the buyer confirms receipt and satisfaction.\n'
                '  b) The standard escrow period is FOURTEEN (14) DAYS from delivery confirmation.\n'
                '  c) If the buyer does not confirm receipt or raise a dispute within 14 days, funds are automatically released to the seller.\n'
                '  d) If a dispute is raised, funds remain in escrow until resolution.\n\n'
                '6.4 REFUNDS AND RETURNS:\n'
                '  a) Refunds are processed at the seller\'s discretion or as determined by our dispute resolution process.\n'
                '  b) Refunds, if approved, will be processed to the original payment method within 5-10 business days.\n'
                '  c) We do not guarantee that refunds are possible for all transactions.\n'
                '  d) Shipping and processing fees may not be refundable.\n\n'
                '6.5 CANCELLATION:\n'
                '  a) Buyers may cancel an order before the seller accepts and processes it.\n'
                '  b) After the seller has accepted, cancellation requires the seller\'s consent.\n'
                '  c) Sellers may cancel orders if the product is unavailable or if the buyer\'s payment fails.\n'
                '  d) Fraudulent cancellations or excessive cancellation rates may result in account action.\n\n'
                '6.6 ALL SALES ARE FINAL once confirmed by the buyer, except as provided in our dispute resolution process.'),

              _section(cs, '7. RIDE-HAILING SERVICES — TERMS AND CONDITIONS',
                '7.1 NATURE OF SERVICE: Ride-hailing services connect riders with independent third-party drivers. DRIVERS ARE INDEPENDENT CONTRACTORS, NOT EMPLOYEES, AGENTS, OR REPRESENTATIVES OF SOKO VIBE.\n\n'
                '7.2 DRIVER REQUIREMENTS:\n'
                '  a) Drivers must possess valid driving licenses appropriate for the vehicle being operated.\n'
                '  b) Drivers must maintain valid vehicle registration, insurance, and roadworthiness certification.\n'
                '  c) Drivers must comply with all applicable Tanzanian traffic laws and regulations.\n'
                '  d) Drivers must pass a background check and KYC verification.\n'
                '  e) Drivers must maintain a minimum rating of 4.0 to remain active on the Platform.\n\n'
                '7.3 RIDER RESPONSIBILITIES:\n'
                '  a) Provide accurate pickup and drop-off locations.\n'
                '  b) Be ready at the pickup location at the scheduled time.\n'
                '  c) Ensure all passengers wear seatbelts where available.\n'
                '  d) Not request drivers to violate traffic laws.\n'
                '  e) Treat drivers with respect and courtesy.\n'
                '  f) Riders are responsible for additional charges resulting from incorrect location information, excessive waiting time, or route changes.\n\n'
                '7.4 FARES AND PAYMENT:\n'
                '  a) Fare estimates are based on distance, duration, vehicle type, and current demand.\n'
                '  b) Final fares may vary from estimates due to route changes, traffic, or additional waiting time.\n'
                '  c) Dynamic pricing (surge pricing) may apply during periods of high demand.\n'
                '  d) All fares include applicable service fees and taxes.\n'
                '  e) Payment is processed automatically through the Platform.\n\n'
                '7.5 CANCELLATION:\n'
                '  a) Riders may cancel before a driver is assigned without penalty.\n'
                '  b) After driver assignment, cancellation fees may apply.\n'
                '  c) Drivers may cancel if the rider does not show up within 5 minutes of arrival.\n'
                '  d) Excessive cancellation by either party may result in account restrictions.\n\n'
                '7.6 LIABILITY DISCLAIMER:\n'
                '  a) WE ARE NOT LIABLE FOR ANY LOSS, DAMAGE, INJURY, OR DEATH ARISING FROM RIDE-HAILING SERVICES.\n'
                '  b) DRIVERS ARE SOLELY RESPONSIBLE FOR THEIR CONDUCT, VEHICLE SAFETY, AND COMPLIANCE WITH LAWS.\n'
                '  c) RIDERS USE RIDE-HAILING SERVICES AT THEIR OWN RISK.\n'
                '  d) We encourage all users to verify driver and vehicle details before commencing a trip.\n\n'
                '7.7 RATINGS: Both riders and drivers may rate each other after each trip. Ratings below 4.0 may result in review and potential deactivation of the account.'),

              _section(cs, '8. FEES, CHARGES, AND TAXES',
                '8.1 CREATING AN ACCOUNT AND BROWSING THE PLATFORM IS FREE. Charges apply only when you use specific services.\n\n'
                '8.2 SELLING FEES:\n'
                '  a) A platform fee is charged on each completed transaction.\n'
                '  b) The fee percentage is displayed at the time of listing creation and may be modified with 14 days notice.\n'
                '  c) The fee is deducted from the seller\'s payout before release from escrow.\n\n'
                '8.3 RIDE-HAILING FEES:\n'
                '  a) A service fee is charged on each completed trip.\n'
                '  b) The fee is included in the fare displayed to the rider.\n\n'
                '8.4 BOOST AND PROMOTIONAL FEES:\n'
                '  a) Additional fees apply for product boosting and promotional features.\n'
                '  b) Boost fees are non-refundable except in cases of Platform error.\n\n'
                '8.5 WITHDRAWAL FEES: Fees may apply when withdrawing funds from your wallet. These fees are displayed before confirmation.\n\n'
                '8.6 TAXES:\n'
                '  a) You are solely responsible for reporting and paying all taxes applicable to your transactions.\n'
                '  b) We may be required to report transaction information to the Tanzania Revenue Authority (TRA).\n'
                '  c) We do not provide tax advice. Consult a tax professional for guidance.\n\n'
                '8.7 FEE MODIFICATION:\n'
                '  a) We reserve the right to change our fee structure at any time.\n'
                '  b) Changes will be communicated at least 14 days in advance for material changes.\n'
                '  c) Continued use after fee changes constitutes acceptance of the new fee structure.\n\n'
                '8.8 ALL FEES ARE NON-REFUNDABLE except as explicitly stated in our refund policy or as required by law.'),

              _section(cs, '9. DISPUTE RESOLUTION — BINDING PROCESS',
                '9.1 INFORMAL RESOLUTION: If a dispute arises between users, you agree to FIRST attempt to resolve it directly with the other party through the Platform\'s messaging system within 7 days.\n\n'
                '9.2 FORMAL DISPUTE: If informal resolution fails, either party may submit a formal dispute through the Platform\'s dispute resolution system within 30 days of the transaction date.\n\n'
                '9.3 EVIDENCE: Both parties must provide all relevant evidence, including:\n'
                '  a) Chat logs and communication records.\n'
                '  b) Transaction records and payment confirmations.\n'
                '  c) Photographs or videos of the product or issue.\n'
                '  d) Delivery and tracking information.\n'
                '  e) Any other relevant documentation.\n\n'
                '9.4 DISPUTE DECISION:\n'
                '  a) Our dispute resolution team will review the case based on evidence provided by both parties.\n'
                '  b) The decision of our dispute resolution team is FINAL AND BINDING on both parties.\n'
                '  c) Decisions are made within 14 days of receiving all necessary information.\n'
                '  d) We reserve the right to make equitable decisions that may not strictly follow these Terms.\n\n'
                '9.5 ESCROW DURING DISPUTES: Funds remain in escrow until the dispute is resolved.\n\n'
                '9.6 MEDIATION AND ARBITRATION:\n'
                '  a) If a dispute cannot be resolved through our internal process, it shall be referred to mediation.\n'
                '  b) If mediation fails, the dispute shall be resolved through binding arbitration in accordance with Tanzanian law.\n'
                '  c) The arbitration shall be conducted in Dar es Salaam, Tanzania, in the English language.\n'
                '  d) Each party shall bear its own costs, unless the arbitrator determines otherwise.\n\n'
                '9.7 CLASS ACTION WAIVER: You agree to resolve disputes with us on an INDIVIDUAL BASIS and waive any right to participate in class action lawsuits or collective arbitration.\n\n'
                '9.8 STATUTE OF LIMITATIONS: Any claim or cause of action arising from these Terms or your use of the Platform must be filed within ONE (1) YEAR of the event giving rise to the claim, or be permanently barred.'),

              _section(cs, '10. INTELLECTUAL PROPERTY RIGHTS',
                '10.1 PLATFORM OWNERSHIP:\n'
                '  a) The Platform, including its design, code, graphics, logos, trademarks, trade dress, user interface, algorithms, databases, and all content not provided by users, is the SOLE AND EXCLUSIVE PROPERTY of Soko Vibe.\n'
                '  b) All intellectual property rights are protected by Tanzanian and international copyright, trademark, patent, and trade secret laws.\n'
                '  c) No license or right to any intellectual property is granted to you except as expressly stated herein.\n\n'
                '10.2 USER CONTENT LICENSE:\n'
                '  a) You retain ownership of content you post.\n'
                '  b) By posting content, you grant Soko Vibe a NON-EXCLUSIVE, WORLDWIDE, ROYALTY-FREE, PERPETUAL, IRREVOCABLE, SUB-LICENSABLE, AND TRANSFERABLE license to use, reproduce, modify, adapt, publish, display, distribute, and create derivative works of your content on the Platform and in connection with our business.\n'
                '  c) This license survives termination of your account for the purpose of maintaining Platform integrity and historical data.\n\n'
                '10.3 REPRESENTATIONS AND WARRANTIES:\n'
                '  a) You represent and warrant that you own all content you post, or have all necessary rights, licenses, and permissions to post it.\n'
                '  b) You represent and warrant that your content does not infringe any third-party intellectual property rights.\n'
                '  c) You agree to indemnify us for any claims arising from your content.\n\n'
                '10.4 COPYRIGHT INFRINGEMENT:\n'
                '  a) We respect intellectual property rights and expect users to do the same.\n'
                '  b) We will respond to clear notices of alleged copyright infringement.\n'
                '  c) Repeat infringers may have their accounts terminated.\n'
                '  d) To report infringement, contact us with full details of the allegedly infringing content.\n\n'
                '10.5 RESTRICTIONS: You may not copy, modify, distribute, sell, lease, reverse engineer, decompile, disassemble, or create derivative works of any part of the Platform without our express written permission.'),

              _section(cs, '11. LIMITATION OF LIABILITY — COMPREHENSIVE DISCLAIMER',
                '11.1 THE PLATFORM AND ALL SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT ANY WARRANTIES, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, TITLE, OR COURSE OF PERFORMANCE.\n\n'
                '11.2 WE MAKE NO WARRANTY THAT:\n'
                '  a) The Platform will meet your requirements or expectations.\n'
                '  b) The Platform will be uninterrupted, timely, secure, or error-free.\n'
                '  c) The results obtained from using the Platform will be accurate or reliable.\n'
                '  d) The quality of any products, services, information, or other material purchased or obtained through the Platform will meet your expectations.\n'
                '  e) Any errors in the Platform will be corrected.\n\n'
                '11.3 TO THE MAXIMUM EXTENT PERMITTED BY LAW, SOKO VIBE, ITS OFFICERS, DIRECTORS, EMPLOYEES, AGENTS, AFFILIATES, SUCCESSORS, AND ASSIGNS SHALL NOT BE LIABLE FOR ANY:\n'
                '  a) Indirect, incidental, special, consequential, exemplary, or punitive damages.\n'
                '  b) Loss of profits, revenue, business opportunities, goodwill, or anticipated savings.\n'
                '  c) Loss of data, content, or information.\n'
                '  d) Loss of privacy or security.\n'
                '  e) Personal injury or property damage.\n'
                '  f) Damages resulting from transactions between users.\n'
                '  g) Damages resulting from ride-hailing services.\n'
                '  h) Damages resulting from acts of God, natural disasters, war, terrorism, or force majeure events.\n\n'
                '11.4 OUR TOTAL CUMULATIVE LIABILITY TO YOU FOR ANY CLAIM ARISING FROM THESE TERMS OR YOUR USE OF THE PLATFORM SHALL NOT EXCEED THE TOTAL AMOUNT OF FEES PAID BY YOU TO US IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM, OR ONE HUNDRED THOUSAND TANZANIAN SHILLINGS (TZS 100,000), WHICHEVER IS GREATER.\n\n'
                '11.5 THIS LIMITATION OF LIABILITY APPLIES WHETHER THE CLAIM IS BASED ON CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, PRODUCT LIABILITY, OR ANY OTHER LEGAL THEORY, AND EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.\n\n'
                '11.6 SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF CERTAIN WARRANTIES OR THE LIMITATION OF CERTAIN DAMAGES. IF YOU RESIDE IN SUCH A JURISDICTION, SOME OF THESE LIMITATIONS MAY NOT APPLY TO YOU TO THE EXTENT PROHIBITED BY LAW.\n\n'
                '11.7 THE DISCLAIMERS AND LIMITATIONS IN THIS SECTION ARE FUNDAMENTAL TERMS OF THIS AGREEMENT AND THE PLATFORM WOULD NOT BE PROVIDED WITHOUT SUCH DISCLAIMERS AND LIMITATIONS.'),

              _section(cs, '12. INDEMNIFICATION — YOUR OBLIGATION TO PROTECT US',
                '12.1 You agree to INDEMNIFY, DEFEND, AND HOLD HARMLESS Soko Vibe, its affiliates, subsidiaries, parents, officers, directors, employees, agents, contractors, licensors, service providers, successors, and assigns from and against ANY AND ALL claims, liabilities, damages, losses, costs, expenses, and fees (including but not limited to reasonable attorneys\' fees, court costs, settlement amounts, and expert witness fees) arising from or related to:\n\n'
                '  a) Your use of or access to the Platform.\n'
                '  b) Your violation of any provision of these Terms.\n'
                '  c) Your violation of any third-party rights, including but not limited to intellectual property rights, privacy rights, or contractual rights.\n'
                '  d) Your posted content, listings, reviews, or communications.\n'
                '  e) Any transaction you enter into through the Platform.\n'
                '  f) Any ride-hailing service you request or provide.\n'
                '  g) Your violation of any applicable law, regulation, or ordinance.\n'
                '  h) Your negligence, fraud, willful misconduct, or intentional acts.\n'
                '  i) Any dispute between you and another user.\n\n'
                '12.2 We reserve the right, at YOUR EXPENSE, to assume the exclusive defense and control of any matter subject to indemnification. You agree to cooperate with our defense of such claims.\n\n'
                '12.3 This indemnification obligation survives termination of your account and these Terms.'),

              _section(cs, '13. TERMINATION AND SUSPENSION',
                '13.1 TERMINATION BY YOU:\n'
                '  a) You may terminate your account at any time through the Settings menu or by contacting support.\n'
                '  b) Termination does not relieve you of obligations arising from transactions entered into before termination.\n'
                '  c) Outstanding transactions must be completed or appropriately cancelled.\n\n'
                '13.2 TERMINATION BY US:\n'
                '  a) We may suspend or terminate your account at any time, for any reason, with or without cause, with or without notice, at our SOLE DISCRETION.\n'
                '  b) We are not obligated to provide reasons for termination.\n'
                '  c) We are not liable to you or any third party for termination.\n\n'
                '13.3 EFFECTS OF TERMINATION:\n'
                '  a) Your right to access and use the Platform ceases immediately.\n'
                '  b) Your listings will be deactivated and removed from search results.\n'
                '  c) Any pending transactions will be canceled and refunded to buyers as appropriate.\n'
                '  d) Any wallet balance may be forfeited if termination is for cause.\n'
                '  e) Your data will be handled according to our Privacy Policy.\n\n'
                '13.4 SURVIVAL: The following provisions survive termination: Sections 8 (Fees), 9 (Dispute Resolution), 10 (Intellectual Property), 11 (Limitation of Liability), 12 (Indemnification), 14 (Governing Law), 15 (General Provisions), and any other provisions that by their nature should survive.'),

              _section(cs, '14. GOVERNING LAW AND JURISDICTION',
                '14.1 GOVERNING LAW: These Terms shall be governed by and construed in accordance with the laws of the United Republic of Tanzania, without regard to its conflict of law provisions. Applicable laws include but are not limited to:\n'
                '  a) The Law of Contract Act, Cap. 345.\n'
                '  b) The Electronic Transactions Act, 2015.\n'
                '  c) The Cybercrimes Act, 2015.\n'
                '  d) The Tanzania Data Protection Act, 2022.\n'
                '  e) The Anti-Money Laundering Act, 2006.\n'
                '  f) The Fair Competition Act, 2003.\n'
                '  g) The Tanzania Revenue Authority Act, Cap. 399.\n\n'
                '14.2 JURISDICTION: Any legal action or proceeding arising from these Terms or the use of the Platform shall be brought EXCLUSIVELY in the courts of Dar es Salaam, Tanzania. You submit to the personal jurisdiction of such courts.\n\n'
                '14.3 INTERNATIONAL USERS: If you access the Platform from outside Tanzania, you do so at your own initiative and are responsible for compliance with local laws. We make no representation that the Platform is appropriate or available for use in locations outside Tanzania.\n\n'
                '14.4 The United Nations Convention on Contracts for the International Sale of Goods (CISG) shall NOT apply to these Terms.'),

              _section(cs, '15. GENERAL PROVISIONS',
                '15.1 ENTIRE AGREEMENT: These Terms, together with our Privacy Policy and any other policies referenced herein, constitute the ENTIRE AND EXCLUSIVE agreement between you and Soko Vibe regarding your use of the Platform and supersede all prior and contemporaneous agreements, understandings, negotiations, and representations, whether written or oral.\n\n'
                '15.2 WAIVER: Our failure or delay in enforcing any right or provision of these Terms shall NOT constitute a waiver of such right or provision. No waiver shall be effective unless in writing and signed by an authorized representative of Soko Vibe.\n\n'
                '15.3 SEVERABILITY: If any provision of these Terms is found to be invalid, illegal, or unenforceable by a court of competent jurisdiction, the remaining provisions shall remain in FULL FORCE AND EFFECT. The invalid provision shall be modified to the minimum extent necessary to make it enforceable.\n\n'
                '15.4 ASSIGNMENT:\n'
                '  a) You may NOT assign or transfer these Terms or any of your rights or obligations hereunder, whether by operation of law or otherwise, without our prior written consent.\n'
                '  b) Any attempted assignment in violation of this section is VOID.\n'
                '  c) We may assign these Terms freely without restriction.\n\n'
                '15.5 NOTICES:\n'
                '  a) We may provide notices to you via your registered email address, in-app notifications, push notifications, SMS, or through a general posting on the Platform.\n'
                '  b) Notices are deemed received 24 hours after sending for electronic communications.\n'
                '  c) You may provide notices to us at support@soko-vibe.com.\n\n'
                '15.6 FORCE MAJEURE: We shall not be liable for any failure or delay in performance due to circumstances beyond our reasonable control, including but not limited to acts of God, natural disasters, earthquakes, floods, fires, epidemics, pandemics, war, terrorism, riots, civil commotion, embargoes, government actions, strikes, labor disputes, power outages, network failures, failure of telecommunications or internet infrastructure, and acts or omissions of third parties.\n\n'
                '15.7 RELATIONSHIP: Nothing in these Terms creates any agency, partnership, joint venture, employment, or franchise relationship between you and Soko Vibe.\n\n'
                '15.8 THIRD-PARTY BENEFICIARIES: There are no third-party beneficiaries to these Terms except as expressly stated.\n\n'
                '15.9 LANGUAGE: These Terms are originally drafted in English. Translations are provided for convenience only. In case of conflict, the English version prevails.\n\n'
                '15.10 ELECTRONIC SIGNATURE: By using the Platform, you consent to transact business electronically and acknowledge that your use of the Platform constitutes your electronic signature and acceptance of these Terms.'),

              _section(cs, '16. ACKNOWLEDGMENT AND ACCEPTANCE',
                '16.1 BY CREATING AN ACCOUNT OR USING THE PLATFORM, YOU EXPLICITLY ACKNOWLEDGE, REPRESENT, WARRANT, AND AGREE THAT:\n'
                '  a) You have read, understood, and accept these Terms in their entirety.\n'
                '  b) You are at least 18 years of age and have the legal capacity to enter into this agreement.\n'
                '  c) You agree to be legally bound by all provisions of these Terms.\n'
                '  d) You consent to the electronic delivery of this agreement and all related communications.\n'
                '  e) You acknowledge that these Terms may be modified at any time without prior notice.\n'
                '  f) You agree to review these Terms periodically.\n'
                '  g) You agree that your continued use of the Platform constitutes acceptance of any modified Terms.\n\n'
                '16.2 IF YOU DO NOT AGREE TO ALL PROVISIONS OF THESE TERMS, YOU MUST IMMEDIATELY CEASE USING THE PLATFORM AND DELETE YOUR ACCOUNT.\n\n'
                '16.3 THESE TERMS CONTAIN BINDING ARBITRATION AND CLASS ACTION WAIVER PROVISIONS THAT AFFECT YOUR LEGAL RIGHTS. PLEASE READ THEM CAREFULLY.'),

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
