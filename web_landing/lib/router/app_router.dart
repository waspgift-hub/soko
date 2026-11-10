import 'package:flutter/material.dart';
import '../pages/about_page.dart';
import '../pages/buyers_page.dart';
import '../pages/contact_page.dart';
import '../pages/faq_page.dart';
import '../pages/features_page.dart';
import '../pages/how_it_works_page.dart';
import '../pages/landing_page.dart';
import '../pages/not_found_page.dart';
import '../pages/pricing_page.dart';
import '../pages/sellers_page.dart';
import '../pages/waitlist_success_page.dart';

class AppRoutes {
  AppRoutes._();
  static const home = '/';
  static const about = '/about';
  static const howItWorks = '/how-it-works';
  static const features = '/features';
  static const buyers = '/buyers';
  static const sellers = '/sellers';
  static const pricing = '/pricing';
  static const faq = '/faq';
  static const contact = '/contact';
  static const waitlistSuccess = '/waitlist/success';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const cookies = '/cookies';
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? AppRoutes.home;
  final uri = Uri.tryParse(name);
  final path = uri?.path ?? '/';
  Widget page;
  switch (path) {
    case AppRoutes.home:
      page = const LandingPage();
      break;
    case AppRoutes.about:
      page = const AboutPage();
      break;
    case AppRoutes.howItWorks:
      page = const HowItWorksPage();
      break;
    case AppRoutes.features:
      page = const FeaturesPage();
      break;
    case AppRoutes.buyers:
      page = const BuyersPage();
      break;
    case AppRoutes.sellers:
      page = const SellersPage();
      break;
    case AppRoutes.pricing:
      page = const PricingPage();
      break;
    case AppRoutes.faq:
      page = const FaqPage();
      break;
    case AppRoutes.contact:
      page = const ContactPage();
      break;
    case AppRoutes.waitlistSuccess:
      page = const WaitlistSuccessPage();
      break;
    case AppRoutes.privacy:
    case AppRoutes.terms:
    case AppRoutes.cookies:
      page = _ExternalLegalPage(path: path);
      break;
    default:
      page = const NotFoundPage();
  }
  return MaterialPageRoute(builder: (_) => page, settings: settings);
}

class _ExternalLegalPage extends StatelessWidget {
  final String path;
  const _ExternalLegalPage({required this.path});
  @override
  Widget build(BuildContext context) {
    final url = switch (path) {
      AppRoutes.privacy => '/privacy-policy/',
      AppRoutes.terms => '/terms-of-service/',
      AppRoutes.cookies => '/cookie-policy/',
      _ => '/',
    };
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Opening legal pageΓÇª',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SelectableText(url),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed('/'),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
