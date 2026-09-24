/// Stable ordering that floats sponsored (boosted) items to the front of any
/// list without disturbing a caller-chosen sort key.
///
/// The implementation is deliberately list-type-agnostic (takes an
/// `isSponsored` predicate instead of depending on [Product]), so the same
/// sorter serves product feeds, search results, category pages, and seller
/// dashboards without importing a model. Product screens wire it as:
///
/// ```dart
/// SponsoredSorter.apply(products, isSponsored: (p) => p.isSponsored);
/// ```
class SponsoredSorter {
  SponsoredSorter._();

  /// Sorts [items] in place so sponsored items precede non-sponsored ones.
  ///
  /// Products within the same tier keep their relative order unless [by] is
  /// given, which is applied as the tie-breaker between items of equal
  /// sponsorship (e.g. `(a, b) => b.createdAt.compareTo(a.createdAt)` for the
  /// existing newest-first feed). `by` must be a total order if provided.
  static void apply<T>(
    List<T> items, {
    required bool Function(T) isSponsored,
    int Function(T a, T b)? by,
  }) {
    items.sort((a, b) {
      final aSponsored = isSponsored(a);
      final bSponsored = isSponsored(b);
      if (aSponsored != bSponsored) return aSponsored ? -1 : 1;
      final tieBreaker = by;
      return tieBreaker == null ? 0 : tieBreaker(a, b);
    });
  }

  /// Returns a new list with sponsored items first, leaving [items] untouched.
  static List<T> first<T>(
    List<T> items, {
    required bool Function(T) isSponsored,
    int Function(T a, T b)? by,
  }) {
    final copy = List<T>.from(items);
    apply(copy, isSponsored: isSponsored, by: by);
    return copy;
  }

  /// Dart's `List.sort` is not spec-guaranteed stable across equal keys, so
  /// callers that need an exact sub-ordering within a tier must supply [by]
  /// rather than rely on insertion order.
  static const String kStabilityNote =
      'List.sort is not guaranteed stable; provide `by` for intra-tier order.';
}
