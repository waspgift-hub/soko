import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/utils/network_error.dart';

void main() {
  group('translateHttpStatus', () {
    test('maps oversized request URIs and headers to a length message', () {
      expect(translateHttpStatus(414), ErrorKeys.requestTooLong);
      expect(translateHttpStatus(431), ErrorKeys.requestTooLong);
    });

    test('maps oversized payloads to a payload message', () {
      expect(translateHttpStatus(413), ErrorKeys.payloadTooLarge);
    });
  });
}
