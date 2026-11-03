import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/app/app_state.dart';
import 'package:soko_vibe/theme/theme_manager.dart';

/// Provides the minimum widget tree that most screens expect: MaterialApp +
/// Theme + Provider wrappers.  Individual tests can wrap additional Providers
/// on top of this.
class TestApp extends StatelessWidget {
  final Widget child;
  final bool authenticated;
  final bool isAdmin;

  const TestApp({
    super.key,
    required this.child,
    this.authenticated = true,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final tm = ThemeManager()..lightTheme;
    appStateNotifier.setAppInitialized();
    appStateNotifier.setAuthState(
      authenticated: authenticated,
      admin: isAdmin,
    );

    return MaterialApp(
      home: child,
      theme: tm.lightTheme,
      darkTheme: tm.darkTheme,
    );
  }
}

/// Pump [child] wrapped in [TestApp] and return the tester for further
/// interactions.
Future<WidgetTester> pumpTestApp(
  WidgetTester tester, {
  required Widget child,
  bool authenticated = true,
  bool isAdmin = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    TestApp(
      authenticated: authenticated,
      isAdmin: isAdmin,
      child: child,
    ),
  );
  await tester.pumpAndSettle();
  return tester;
}

/// Finds a widget by [Semantics] label (accessibility-first approach).
Finder findSemanticsLabel(String label) => find.bySemanticsLabel(label);

/// Shorthand for tapping a text widget.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Shorthand for entering text into a TextField/TextFormField.
Future<void> enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

/// Returns a set of [Product]-like map for testing product feeds.
Map<String, dynamic> mockProductMap({
  String id = 'test-1',
  String name = 'Test Product',
  double price = 25000,
  String category = 'Electronics',
  String sellerId = 'seller-1',
  String sellerName = 'Test Seller',
  String location = 'Dar es Salaam',
  int stock = 10,
}) {
  return {
    'name': name,
    'description': 'A test product description.',
    'price': price,
    'currency': 'TZS',
    'images': <String>[],
    'sellerId': sellerId,
    'sellerName': sellerName,
    'category': category,
    'subcategory': '',
    'location': location,
    'district': '',
    'stock': stock,
    'isWholesale': false,
    'wholesaleTiers': <Map<String, dynamic>>[],
    'variants': <Map<String, dynamic>>{},
    'attributes': <String, dynamic>{},
    'isActive': true,
    'isFeatured': false,
    'rating': 4.5,
    'reviewCount': 12,
    'soldCount': 5,
    'viewCount': 100,
    'brand': 'TestBrand',
    'condition': 'new',
    'searchKeywords': <String>[],
    'searchName': name.toLowerCase(),
    'isBoosted': false,
  };
}
