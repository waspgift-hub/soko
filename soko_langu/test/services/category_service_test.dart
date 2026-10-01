import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/data/marketplace_taxonomy.dart';
import 'package:soko_vibe/models/category_model.dart';
import 'package:soko_vibe/services/category_service.dart';

void main() {
  group('CategoryService — the tree ships with the app', () {
    test('is synchronous, so no screen can render a loading state for it', () {
      // A Stream/Future return type is what forced the skeleton + retry UI in
      // the home strip and the category grid. This test fails to compile if the
      // API ever goes back to async.
      final List<Category> cats = CategoryService.getCategories();
      expect(cats, isNotEmpty);
    });

    test('returns the browsable roots only', () {
      final names = CategoryService.getCategories().map((c) => c.name).toList();
      expect(names, isNot(contains('Others')));
      expect(CategoryService.getCategories().every((c) => c.isActive), isTrue);
    });

    test('matches the shipped taxonomy, in taxonomy order', () {
      final shipped = CategoryService.getCategories();
      expect(shipped.length, kMarketplaceTaxonomy.length);
      for (var i = 0; i < shipped.length; i++) {
        expect(shipped[i].id, kMarketplaceTaxonomy[i].id);
        expect(shipped[i].name, kMarketplaceTaxonomy[i].name);
        expect(
          shipped[i].subcategories.length,
          kMarketplaceTaxonomy[i].subs.length,
        );
      }
    });

    test('every root carries a name for the backend product filter', () {
      // Products are fetched by category NAME (legacy Firestore records hold a
      // name, not a slug), so a blank name would silently empty the list.
      for (final c in CategoryService.getCategories()) {
        expect(c.name.trim(), isNotEmpty);
      }
    });

    test('byId resolves a root id and a subcategory slug to its root', () {
      final electronics = CategoryService.byId('electronics');
      expect(electronics, isNotNull);
      expect(
        CategoryService.byId(electronics!.subcategories.first.id)?.id,
        'electronics',
      );
      expect(CategoryService.byId('nope'), isNull);
    });

    test(
      'all exposes the hidden legacy catch-all the browsable list hides',
      () {
        expect(CategoryService.all.map((c) => c.id), contains('others'));
        expect(
          CategoryService.getCategories().map((c) => c.id),
          isNot(contains('others')),
        );
      },
    );

    test('the browsable list is unmodifiable so a screen cannot mutate it', () {
      expect(
        () => CategoryService.getCategories().removeAt(0),
        throwsUnsupportedError,
      );
    });
  });
}
