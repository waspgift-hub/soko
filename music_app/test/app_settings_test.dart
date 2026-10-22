import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe_music/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('startup sound is enabled by default', () async {
    final settings = AppSettings();
    await settings.load();

    expect(settings.startupSound, isTrue);
  });

  test('startup sound preference persists when changed', () async {
    final settings = AppSettings();
    await settings.load();

    await settings.saveStartupSound(false);
    final reloaded = AppSettings();
    await reloaded.load();

    expect(reloaded.startupSound, isFalse);
  });
}
