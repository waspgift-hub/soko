import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_web/localization/app_strings.dart';

void main() {
  test('sw and en share exactly the same keys', () {
    final sw = AppStrings.keysFor('sw');
    final en = AppStrings.keysFor('en');

    expect(sw, isNotEmpty);
    expect(en, equals(sw));
  });

  test('no empty translations', () {
    for (final code in ['sw', 'en']) {
      final strings = AppStrings()..setLocale(code);
      for (final key in AppStrings.keysFor(code)) {
        expect(strings.t(key), isNotEmpty, reason: '$code:$key');
        expect(strings.t(key), isNot(key), reason: '$code:$key');
      }
    }
  });
}
