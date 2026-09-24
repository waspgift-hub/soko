/// Category-aware product filtering for discovery surfaces.
///
/// Firestore has no composite index for every attribute combination, so the
/// category page loads its bounded product list once and applies the picked
/// filters client-side. Server queries stay on indexed equality filters.
library;

import '../models/product_model.dart';

/// Quick quality/tech flag matched against listing text and fields.
class PopularFlag {
  final String key;
  final String? label;
  final String? labelKey;
  final List<String> terms;
  const PopularFlag({
    required this.key,
    this.label,
    this.labelKey,
    this.terms = const [],
  });
}

const List<PopularFlag> kPopularFlags = [
  PopularFlag(key: 'fiveG', label: '5G', terms: ['5g']),
  PopularFlag(
    key: 'dualSim',
    label: 'Dual SIM',
    terms: ['dual sim', 'dual-sim', 'dualsim'],
  ),
  PopularFlag(key: 'amoled', label: 'AMOLED', terms: ['amoled']),
  PopularFlag(
    key: 'bigBattery',
    label: '5000mAh+',
    terms: ['5000mah', '5100mah', '6000mah', '7000mah'],
  ),
  PopularFlag(key: 'eSim', label: 'eSIM', terms: ['esim', 'e-sim']),
  PopularFlag(key: 'verified', labelKey: 'verified'),
  PopularFlag(key: 'topRated', labelKey: 'top_rated'),
];

PopularFlag? popularFlagByKey(String key) {
  for (final f in kPopularFlags) {
    if (f.key == key) return f;
  }
  return null;
}

/// One removable entry in the active-filters row. Price chips are built by
/// the UI straight from the filter so currency formatting stays in one place.
class FilterChipData {
  final String kind;
  final String value;
  final String? labelKey;
  final String? label;
  const FilterChipData({
    required this.kind,
    required this.value,
    this.labelKey,
    this.label,
  });
}

/// Selected discovery filters. Empty means "no filtering".
class ProductFilter {
  final Set<String> brands;
  final double? minPrice;
  final double? maxPrice;
  final String condition;
  final String location;
  final Map<String, Set<String>> attributes;
  final Set<String> flags;
  final String sort;
  const ProductFilter({
    this.brands = const {},
    this.minPrice,
    this.maxPrice,
    this.condition = 'all',
    this.location = '',
    this.attributes = const {},
    this.flags = const {},
    this.sort = 'newest',
  });

  bool get isEmpty =>
      brands.isEmpty &&
      minPrice == null &&
      maxPrice == null &&
      condition == 'all' &&
      location.isEmpty &&
      attributes.values.every((s) => s.isEmpty) &&
      flags.isEmpty;

  int get activeCount {
    var n = brands.length + flags.length;
    if (minPrice != null || maxPrice != null) n++;
    if (condition != 'all') n++;
    if (location.isNotEmpty) n++;
    for (final s in attributes.values) {
      n += s.length;
    }
    return n;
  }

  ProductFilter copyWith({
    Set<String>? brands,
    double? minPrice,
    double? maxPrice,
    bool clearPriceBounds = false,
    String? condition,
    String? location,
    Map<String, Set<String>>? attributes,
    Set<String>? flags,
    String? sort,
  }) {
    return ProductFilter(
      brands: brands ?? this.brands,
      minPrice: clearPriceBounds ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPriceBounds ? null : (maxPrice ?? this.maxPrice),
      condition: condition ?? this.condition,
      location: location ?? this.location,
      attributes: attributes ?? this.attributes,
      flags: flags ?? this.flags,
      sort: sort ?? this.sort,
    );
  }

  /// Filters [input] in place order, then applies [sort].
  List<Product> apply(List<Product> input) {
    final out = input.where(matches).toList();
    switch (sort) {
      case 'price_asc':
        out.sort((a, b) => a.price.compareTo(b.price));
      case 'price_desc':
        out.sort((a, b) => b.price.compareTo(a.price));
      case 'popular':
        out.sort((a, b) {
          if (a.isSponsored != b.isSponsored) return a.isSponsored ? -1 : 1;
          final r = b.rating.compareTo(a.rating);
          if (r != 0) return r;
          return b.soldCount.compareTo(a.soldCount);
        });
      default:
        break;
    }
    return out;
  }

  bool matches(Product p) {
    if (brands.isNotEmpty) {
      final b = (p.brand ?? '').trim().toLowerCase();
      if (b.isEmpty) return false;
      var hit = false;
      for (final s in brands) {
        if (s.trim().toLowerCase() == b) {
          hit = true;
          break;
        }
      }
      if (!hit) return false;
    }
    if (minPrice != null && p.price < minPrice!) return false;
    if (maxPrice != null && p.price > maxPrice!) return false;
    if (condition != 'all' && p.condition.toLowerCase() != condition) {
      return false;
    }
    if (location.isNotEmpty) {
      final q = location.toLowerCase();
      if (!'${p.location} ${p.district}'.toLowerCase().contains(q)) {
        return false;
      }
    }
    for (final entry in attributes.entries) {
      if (entry.value.isEmpty) continue;
      var hit = false;
      for (final o in entry.value) {
        if (_matchOption(entry.key, o, p)) {
          hit = true;
          break;
        }
      }
      if (!hit) return false;
    }
    for (final f in flags) {
      if (!_matchFlag(f, p)) return false;
    }
    return true;
  }

  /// Removable chips for brands, condition, location, attributes, flags.
  List<FilterChipData> chips() {
    final out = <FilterChipData>[];
    for (final b in brands) {
      out.add(FilterChipData(kind: 'brand', value: b));
    }
    if (condition != 'all') {
      out.add(FilterChipData(kind: 'condition', value: condition));
    }
    if (location.isNotEmpty) {
      out.add(FilterChipData(kind: 'location', value: location));
    }
    attributes.forEach((key, values) {
      for (final v in values) {
        out.add(FilterChipData(kind: 'attr:$key', value: v));
      }
    });
    for (final f in flags) {
      final def = popularFlagByKey(f);
      out.add(FilterChipData(
        kind: 'flag',
        value: f,
        label: def?.label,
        labelKey: def?.labelKey,
      ));
    }
    return out;
  }
}

/// Lowercase name + description + attribute values: the text sellers write.
String _searchText(Product p) {
  final buf = StringBuffer('${p.name} ${p.description} ');
  p.attributes.forEach((k, v) {
    buf.write('$k $v ');
  });
  return buf.toString().toLowerCase();
}

String? _attributeValue(Product p, String key) {
  for (final entry in p.attributes.entries) {
    if (entry.key.toLowerCase() == key.toLowerCase()) {
      final v = entry.value;
      if (v == null) return null;
      return v.toString();
    }
  }
  return null;
}

bool _matchOption(String key, String option, Product p) {
  final structured = _attributeValue(p, key);
  if (structured != null &&
      _squash(structured) == _squash(option)) {
    return true;
  }
  final text = _searchText(p);
  if (key == 'year') return _matchYear(option, text);
  if (key == 'mileage') return _matchMileage(option, text);
  final num = _numberWithUnit(option);
  if (num != null) return _textHasNumberWithUnit(text, num.value, num.unit);
  return text.contains(option.toLowerCase());
}

String _squash(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Reads a leading number-plus-unit token such as 8GB or 5000mAh.
({double value, String unit})? _numberWithUnit(String option) {
  final m = RegExp(
    r'^([\d.]+)\s*(tb|gb|mah|km|"|inch|inches|w)\b',
    caseSensitive: false,
  ).firstMatch(option.trim());
  if (m == null) return null;
  final value = double.tryParse(m.group(1)!);
  if (value == null) return null;
  return (value: value, unit: m.group(2)!.toLowerCase());
}

bool _textHasNumberWithUnit(String text, double value, String unit) {
  final pattern = unit == '"'
      ? r'([\d.]+)\s*("|inch|inches)\b'
      : r'([\d.]+)\s*' + RegExp.escape(unit) + r'\b';
  for (final m in RegExp(pattern).allMatches(text)) {
    var v = double.tryParse(m.group(1)!);
    if (v == null) continue;
    if (unit == 'tb') v *= 1024;
    final want = unit == 'tb' ? value * 1024 : value;
    if ((v - want).abs() < 0.001) return true;
  }
  // GB also matches the same figure written as TB fractions is skipped;
  // a TB listing matches an equal GB figure instead.
  if (unit == 'gb') {
    for (final m in RegExp(r'([\d.]+)\s*tb\b').allMatches(text)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null && ((v * 1024 - value).abs() < 0.001)) return true;
    }
  }
  return false;
}

bool _matchYear(String option, String text) {
  final years = RegExp(r'\b(19\d{2}|20[0-3]\d)\b')
      .allMatches(text)
      .map((m) => int.parse(m.group(1)!))
      .toList();
  if (years.isEmpty) return false;
  bool inRange(int y) {
    switch (option) {
      case '2020+':
        return y >= 2020;
      case '2015-2019':
        return y >= 2015 && y <= 2019;
      case '2010-2014':
        return y >= 2010 && y <= 2014;
      case 'Before 2010':
        return y < 2010;
      default:
        return text.contains(option.toLowerCase());
    }
  }

  return years.any(inRange);
}

bool _matchMileage(String option, String text) {
  final kms = <double>[];
  for (final m in RegExp(r'([\d,.]+)\s*k?\s*km\b').allMatches(text)) {
    var raw = m.group(1)!.replaceAll(',', '').toLowerCase();
    var v = double.tryParse(raw.replaceAll('k', ''));
    if (v == null) continue;
    if (raw.contains('k')) v *= 1000;
    kms.add(v);
  }
  if (kms.isEmpty) return false;
  bool inRange(double km) {
    switch (option) {
      case 'Under 50k km':
        return km < 50000;
      case '50k-100k km':
        return km >= 50000 && km <= 100000;
      case 'Over 100k km':
        return km > 100000;
      default:
        return text.contains(option.toLowerCase());
    }
  }

  return kms.any(inRange);
}

bool _matchFlag(String key, Product p) {
  switch (key) {
    case 'verified':
      return p.sellerKycApproved;
    case 'topRated':
      return p.rating >= 4.5;
    default:
      final def = popularFlagByKey(key);
      if (def == null) return true;
      final text = _searchText(p);
      return def.terms.any(text.contains);
  }
}
