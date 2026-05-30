import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('returns error for null', () {
      expect(Validators.email(null), isNotNull);
    });
    test('returns error for empty', () {
      expect(Validators.email(''), isNotNull);
    });
    test('returns null for valid email', () {
      expect(Validators.email('user@example.com'), isNull);
      expect(Validators.email('test@co.tz'), isNull);
    });
    test('returns error for invalid email', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('@domain.com'), isNotNull);
      expect(Validators.email('user@'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('returns error for null', () {
      expect(Validators.password(null), isNotNull);
    });
    test('returns error for empty', () {
      expect(Validators.password(''), isNotNull);
    });
    test('returns error for short password', () {
      expect(Validators.password('abc'), isNotNull);
    });
    test('returns null for valid password', () {
      expect(Validators.password('abcdef'), isNull);
      expect(Validators.password('longpassword123'), isNull);
    });
  });

  group('Validators.phone', () {
    test('returns error for null', () {
      expect(Validators.phone(null), isNotNull);
    });
    test('returns error for empty', () {
      expect(Validators.phone(''), isNotNull);
    });
    test('returns null for valid TZ phone', () {
      expect(Validators.phone('0712345678'), isNull);
      expect(Validators.phone('0612345678'), isNull);
    });
    test('returns error for invalid phone', () {
      expect(Validators.phone('0112345678'), isNotNull);
      expect(Validators.phone('071234567'), isNotNull);
      expect(Validators.phone('07123456789'), isNotNull);
      expect(Validators.phone('12345678'), isNotNull);
    });
  });

  group('Validators.required', () {
    test('returns error for null', () {
      expect(Validators.required(null), isNotNull);
    });
    test('returns error for empty', () {
      expect(Validators.required(''), isNotNull);
    });
    test('returns error for whitespace', () {
      expect(Validators.required('   '), isNotNull);
    });
    test('returns null for non-empty', () {
      expect(Validators.required('value'), isNull);
    });
    test('uses custom field name', () {
      final err = Validators.required('', 'Name');
      expect(err, contains('Name'));
    });
  });

  group('Validators.number', () {
    test('returns error for null', () {
      expect(Validators.number(null), isNotNull);
    });
    test('returns error for non-numeric', () {
      expect(Validators.number('abc'), isNotNull);
    });
    test('returns null for valid numbers', () {
      expect(Validators.number('123'), isNull);
      expect(Validators.number('123.45'), isNull);
      expect(Validators.number('0'), isNull);
    });
  });
}
