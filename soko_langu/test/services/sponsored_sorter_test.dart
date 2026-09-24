import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/services/sponsored_sorter.dart';

void main() {
  group('SponsoredSorter.apply', () {
    test('floats sponsored items first, keeps tie-breaker', () {
      final list = [5, 8, 2, 7, 3];
      SponsoredSorter.apply<int>(
        list,
        isSponsored: (n) => n.isEven,
        by: (a, b) => a.compareTo(b),
      );

      final firstOdd = list.indexWhere((n) => n.isOdd);
      expect(firstOdd, greaterThanOrEqualTo(2));
      expect(list.sublist(0, firstOdd).every((n) => n.isEven), isTrue,
          reason: 'sponsored (even) must be first');
      expect(list.sublist(firstOdd).every((n) => n.isOdd), isTrue,
          reason: 'non-sponsored (odd) must stay after');
    });

    test('tie-breaker orders within the sponsored tier', () {
      final list = [5, 8, 2, 7, 3];
      SponsoredSorter.apply<int>(
        list,
        isSponsored: (n) => n.isEven,
        by: (a, b) => a.compareTo(b),
      );
      expect(list.take(2).toList(), [2, 8], reason: 'sponsored evens ascending');
    });

    test('is a no-op for balanced lists', () {
      final list = [2, 3];
      SponsoredSorter.apply<int>(list, isSponsored: (n) => n.isEven);
      expect(list, [2, 3]);
    });
  });

  group('SponsoredSorter.first', () {
    test('returns a new list, original untouched', () {
      final original = [5, 4, 3, 2];
      final sorted = SponsoredSorter.first<int>(
        original,
        isSponsored: (n) => n.isEven,
        by: (a, b) => a.compareTo(b),
      );

      expect(original, [5, 4, 3, 2], reason: 'input must not be mutated');
      expect(sorted, [2, 4, 5, 3]);
    });
  });
}
