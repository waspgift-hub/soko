/// Understands marketplace queries: category, subcategory, brand,
/// attributes and flags are pulled out so search can suggest visual
/// shortcuts instead of only matching raw text.
library;

import '../data/marketplace_taxonomy.dart';
import '../models/discovery_filters.dart';

class SearchIntent {
  final TaxonomyCategory? category;
  final TaxonomySub? subcategory;
  final String? brand;
  final Map<String, String> attributes;
  final Set<String> flags;
  final String rest;
  const SearchIntent({
    this.category,
    this.subcategory,
    this.brand,
    this.attributes = const {},
    this.flags = const {},
    this.rest = '',
  });

  bool get isEmpty =>
      category == null &&
      subcategory == null &&
      brand == null &&
      attributes.isEmpty &&
      flags.isEmpty &&
      rest.isEmpty;
}

/// Parses [raw] into intent. Matching is longest-first on padded text so
/// "apple" never matches inside "pineapple".
SearchIntent parseSearchIntent(String raw) {
  var rest = ' ${raw.toLowerCase()} ';

  String? takeToken(Iterable<String> tokens) {
    String? best;
    for (final t in tokens) {
      final key = t.toLowerCase();
      if (key.isEmpty) continue;
      if (rest.contains(' $key ') &&
          (best == null || key.length > best.length)) {
        best = t;
      }
    }
    if (best != null) {
      rest = rest.replaceAll(' ${best.toLowerCase()} ', ' ');
    }
    return best;
  }

  // Brand first: brand names are the most distinctive tokens.
  final brandNames = <String>{};
  for (final c in kMarketplaceTaxonomy) {
    for (final b in c.brands) {
      brandNames.add(b.name);
    }
  }
  final brandHit = takeToken(brandNames.toList()
    ..sort((a, b) => b.length.compareTo(a.length)));
  String? brand;
  if (brandHit != null) {
    for (final c in kMarketplaceTaxonomy) {
      for (final b in c.brands) {
        if (b.name == brandHit) brand = b.name;
      }
    }
  }

  // A known brand implies its primary category so "Samsung A55" still
  // lands somewhere shoppable. Specific categories outrank the general
  // electronics bucket.
  TaxonomyCategory? primaryCategoryFor(String brandName) {
    final want = brandName.toLowerCase();
    TaxonomyCategory? first;
    for (final c in kMarketplaceTaxonomy) {
      if (!c.brands.any((b) => b.name.toLowerCase() == want)) continue;
      first ??= c;
      if (c.id != 'electronics') return c;
    }
    return first;
  }

  // Category (names + legacy aliases), longest first.
  TaxonomyCategory? category;
  TaxonomyCategory? bestCat;
  var bestLen = 0;
  void consider(String token, TaxonomyCategory c) {
    final key = token.toLowerCase();
    if (key.isNotEmpty &&
        rest.contains(' $key ') &&
        key.length > bestLen) {
      bestCat = c;
      bestLen = key.length;
    }
  }

  for (final c in kMarketplaceTaxonomy) {
    consider(c.name, c);
    if (c.nameSw.isNotEmpty) consider(c.nameSw, c);
    for (final a in c.aliases) {
      consider(a, c);
    }
  }
  category = bestCat ?? (brand != null ? primaryCategoryFor(brand) : null);
  if (category != null) {
    for (final token in [
      category.name,
      category.nameSw,
      ...category.aliases,
    ]) {
      rest = rest.replaceAll(' ${token.toLowerCase()} ', ' ');
    }
  }

  // Subcategory inside the matched category, else anywhere.
  TaxonomySub? subcategory;
  final pools = category != null
      ? [category.subs]
      : [for (final c in kMarketplaceTaxonomy) c.subs];
  TaxonomySub? bestSub;
  var bestSubLen = 0;
  for (final pool in pools) {
    for (final s in pool) {
      for (final token in [s.name, s.nameSw, ...s.aliases]) {
        final key = token.toLowerCase();
        if (key.isNotEmpty &&
            rest.contains(' $key ') &&
            key.length > bestSubLen) {
          bestSub = s;
          bestSubLen = key.length;
        }
      }
    }
  }
  subcategory = bestSub;
  if (subcategory != null) {
    for (final token in [
      subcategory.name,
      subcategory.nameSw,
      ...subcategory.aliases,
    ]) {
      rest = rest.replaceAll(' ${token.toLowerCase()} ', ' ');
    }
    if (category == null) {
      for (final c in kMarketplaceTaxonomy) {
        if (c.subs.any((s) => s.id == subcategory!.id)) category = c;
      }
    }
  }

  // Attributes: RAM/storage pairs ("8GB/128GB"), explicit units, years.
  final attributes = <String, String>{};
  // Adjacent GB figures follow the phone convention RAM/storage.
  var m = RegExp(r'(\d+)\s*gb\s*[/,]?\s*(\d+)\s*gb').firstMatch(rest);
  if (m != null) {
    attributes['ram'] = '${m.group(1)}GB';
    attributes['storage'] = '${m.group(2)}GB';
    rest = rest.replaceAll(m.group(0)!, ' ');
  } else {
    m = RegExp(r'(?:ram\s*(\d+)\s*gb|(\d+)\s*gb\s*ram)').firstMatch(rest);
    if (m != null) {
      attributes['ram'] = '${m.group(1) ?? m.group(2)}GB';
      rest = rest.replaceAll(m.group(0)!, ' ');
    }
    m = RegExp(r'(\d+)\s*gb\b').firstMatch(rest);
    if (m != null) {
      attributes['storage'] = '${m.group(1)}GB';
      rest = rest.replaceAll(m.group(0)!, ' ');
    }
  }
  m = RegExp(r'(\d+(?:\.\d+)?)\s*(?:"|inch|inches)\b').firstMatch(rest);
  if (m != null) {
    attributes['screen'] = '${m.group(1)}"';
    rest = rest.replaceAll(m.group(0)!, ' ');
  }
  m = RegExp(r'(\d+)\s*mah\b').firstMatch(rest);
  if (m != null) {
    attributes['battery'] = '${m.group(1)}mAh';
    rest = rest.replaceAll(m.group(0)!, ' ');
  }
  m = RegExp(r'\b((?:19|20)\d{2})\b').firstMatch(rest);
  if (m != null) {
    attributes['year'] = m.group(1)!;
    rest = rest.replaceAll(m.group(0)!, ' ');
  }

  // Flags from shared terms.
  final flags = <String>{};
  for (final f in kPopularFlags) {
    if (f.terms.isEmpty) continue;
    for (final term in f.terms) {
      if (rest.contains(term)) {
        flags.add(f.key);
        rest = rest.replaceAll(term, ' ');
        break;
      }
    }
  }

  rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
  return SearchIntent(
    category: category,
    subcategory: subcategory,
    brand: brand,
    attributes: attributes,
    flags: flags,
    rest: rest,
  );
}
