import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/data/marketplace_taxonomy.dart';

void main() {
  test('has the 20 physical categories in order', () {
    expect(kMarketplaceTaxonomy.length, 20);
    final ids = kMarketplaceTaxonomy.map((c) => c.id).toList();
    expect(ids.toSet().length, 20);
    final orders = kMarketplaceTaxonomy.map((c) => c.order).toList();
    expect(orders.toSet().length, 20);
    for (var i = 0; i < 20; i++) {
      expect(kMarketplaceTaxonomy[i].order, i + 1);
    }
  });

  test('every category has image, icon, subs, and brands or a reason', () {
    for (final c in kMarketplaceTaxonomy) {
      expect(c.name.isNotEmpty, true, reason: c.id);
      expect(c.image.endsWith('.jpg'), true, reason: c.id);
      expect(c.icon.isNotEmpty, true, reason: c.id);
      expect(c.subs.length, greaterThanOrEqualTo(4), reason: c.id);
      final subIds = c.subs.map((s) => s.id).toList();
      expect(subIds.toSet().length, subIds.length, reason: c.id);
    }
    final brandless =
        kMarketplaceTaxonomy.where((c) => c.brands.isEmpty).toList();
    expect(brandless.map((c) => c.id), ['services']);
  });

  test('popular flags reference known flag keys', () {
    const known = {
      'fiveG', 'dualSim', 'amoled', 'bigBattery', 'eSim',
      'verified', 'topRated',
    };
    for (final c in kMarketplaceTaxonomy) {
      expect(c.popularFilters.isNotEmpty, true, reason: c.id);
      for (final f in c.popularFilters) {
        expect(known.contains(f), true, reason: '${c.id}:$f');
      }
    }
  });

  test('legacy names still resolve', () {
    expect(resolveTaxonomyByName('Electronics')?.id, 'electronics');
    expect(resolveTaxonomyByName('Fashion')?.id, 'fashion');
    expect(resolveTaxonomyByName('Phones & Tablets') != null, true);
    expect(resolveTaxonomyByName('Business & Industrial')?.id, 'business');
    expect(resolveTaxonomyByName('nope'), isNull);
    expect(taxonomyById('phones')?.name, 'Phones & Accessories');
  });

  test('taxonomy carries no digital-only goods', () {
    const banned = [
      'e-book', 'ebook', 'pdf', 'online course', 'digital download',
      'software license', 'online consulting', 'online tutoring',
      'digital subscription', 'remote service', 'remote-only',
    ];
    final names = <String>[];
    for (final c in kMarketplaceTaxonomy) {
      names.add(c.name.toLowerCase());
      for (final s in c.subs) {
        names.add(s.name.toLowerCase());
      }
    }
    for (final b in banned) {
      for (final n in names) {
        expect(n.contains(b), false, reason: '$b in $n');
      }
    }
  });
}
