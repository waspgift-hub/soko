import 'package:flutter/material.dart';

/// Sample marketplace product for the preview UI (illustrative only —
/// not a live listing, price, or seller claim).
@immutable
class DemoProduct {
  final String nameSw;
  final String nameEn;
  final String price;
  final String location;
  final String seller;
  final IconData icon;
  final bool verified;
  final bool boosted;

  const DemoProduct({
    required this.nameSw,
    required this.nameEn,
    required this.price,
    required this.location,
    required this.seller,
    required this.icon,
    this.verified = true,
    this.boosted = false,
  });

  String name(bool isSw) => isSw ? nameSw : nameEn;
}

const demoProducts = [
  DemoProduct(
    nameSw: 'Samsung Galaxy A15 128GB',
    nameEn: 'Samsung Galaxy A15 128GB',
    price: 'TSh 385,000',
    location: 'Dar es Salaam',
    seller: 'TechPoint',
    icon: Icons.smartphone_outlined,
    boosted: true,
  ),
  DemoProduct(
    nameSw: 'Sofa ya kisasa vitatu',
    nameEn: 'Modern 3-seater sofa',
    price: 'TSh 750,000',
    location: 'Arusha',
    seller: 'Samani Bora',
    icon: Icons.chair_outlined,
  ),
  DemoProduct(
    nameSw: 'Viatu vya michezo Nike',
    nameEn: 'Nike sports shoes',
    price: 'TSh 145,000',
    location: 'Mwanza',
    seller: 'StepUp',
    icon: Icons.checkroom_outlined,
    boosted: true,
  ),
  DemoProduct(
    nameSw: 'Jiko la umeme 2-plate',
    nameEn: '2-plate electric cooker',
    price: 'TSh 98,000',
    location: 'Dodoma',
    seller: 'Nyumbani',
    icon: Icons.kitchen_outlined,
  ),
  DemoProduct(
    nameSw: 'Toyota IST 2005',
    nameEn: 'Toyota IST 2005',
    price: 'TSh 12,800,000',
    location: 'Dar es Salaam',
    seller: 'Magari Fresh',
    icon: Icons.directions_car_outlined,
  ),
  DemoProduct(
    nameSw: 'Mafuta ya nazi asili 1L',
    nameEn: 'Natural coconut oil 1L',
    price: 'TSh 18,000',
    location: 'Tanga',
    seller: 'Asili Products',
    icon: Icons.spa_outlined,
  ),
  DemoProduct(
    nameSw: 'Laptop HP ProBook i5',
    nameEn: 'HP ProBook i5 laptop',
    price: 'TSh 890,000',
    location: 'Mbeya',
    seller: 'CompuHub',
    icon: Icons.laptop_outlined,
    boosted: true,
  ),
  DemoProduct(
    nameSw: 'Mchele wa Kyela 25kg',
    nameEn: 'Kyela rice 25kg',
    price: 'TSh 72,000',
    location: 'Mbeya',
    seller: 'Shamba Fresh',
    icon: Icons.shopping_basket_outlined,
  ),
];

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
