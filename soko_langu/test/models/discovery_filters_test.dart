import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/discovery_filters.dart';
import 'package:soko_vibe/models/product_model.dart';

Product _p({
  String name = 'Samsung Galaxy A55 5G 8GB 128GB',
  String description = 'Dual SIM AMOLED phone',
  double price = 750000,
  String? brand = 'Samsung',
  String condition = 'new',
  String location = 'Dar es Salaam',
  String district = 'Ilala',
  Map<String, dynamic> attributes = const {},
  bool kyc = true,
  double rating = 4.8,
}) {
  return Product(
    id: 'p1',
    name: name,
    description: description,
    price: price,
    images: const [],
    sellerId: 's1',
    sellerName: 'S',
    category: 'Phones & Accessories',
    subcategory: 'Smartphones',
    location: location,
    createdAt: DateTime(2025, 1, 1),
    stock: 5,
    brand: brand,
    condition: condition,
    district: district,
    attributes: attributes,
    sellerKycApproved: kyc,
    rating: rating,
  );
}

void main() {
  test('empty filter matches everything', () {
    expect(const ProductFilter().matches(_p()), true);
    expect(const ProductFilter().isEmpty, true);
  });

  test('brand match is case-insensitive', () {
    expect(
      const ProductFilter(brands: {'samsung'}).matches(_p()),
      true,
    );
    expect(
      const ProductFilter(brands: {'Apple'}).matches(_p()),
      false,
    );
    expect(
      const ProductFilter(brands: {'Apple'}).matches(_p(brand: null)),
      false,
    );
  });

  test('price bounds apply', () {
    expect(
      const ProductFilter(minPrice: 800000).matches(_p()),
      false,
    );
    expect(
      const ProductFilter(maxPrice: 800000).matches(_p()),
      true,
    );
  });

  test('condition and location apply', () {
    expect(
      const ProductFilter(condition: 'used').matches(_p()),
      false,
    );
    expect(
      const ProductFilter(location: 'mwanza').matches(_p()),
      false,
    );
    expect(
      const ProductFilter(location: 'ilala').matches(_p()),
      true,
    );
  });

  test('storage matches title text numerically', () {
    expect(
      const ProductFilter(
        attributes: {
          'storage': {'128GB'}
        },
      ).matches(_p()),
      true,
    );
    expect(
      const ProductFilter(
        attributes: {
          'storage': {'256GB'}
        },
      ).matches(_p()),
      false,
    );
  });

  test('structured attributes match', () {
    final p = _p(
      name: 'HP ProBook',
      description: 'laptop',
      attributes: {'ram': '16GB'},
    );
    expect(
      const ProductFilter(
        attributes: {
          'ram': {'16GB'}
        },
      ).matches(p),
      true,
    );
  });

  test('year buckets parse listing text', () {
    final p = _p(
      name: 'Toyota IST 2017',
      description: '88000 km petrol automatic',
      price: 16500000,
    );
    expect(
      const ProductFilter(
        attributes: {
          'year': {'2015-2019'}
        },
      ).matches(p),
      true,
    );
    expect(
      const ProductFilter(
        attributes: {
          'mileage': {'50k-100k km'}
        },
      ).matches(p),
      true,
    );
    expect(
      const ProductFilter(
        attributes: {
          'fuel': {'Petrol'}
        },
      ).matches(p),
      true,
    );
    expect(
      const ProductFilter(
        attributes: {
          'transmission': {'Manual'}
        },
      ).matches(p),
      false,
    );
  });

  test('popular flags match text and fields', () {
    expect(const ProductFilter(flags: {'fiveG'}).matches(_p()), true);
    expect(const ProductFilter(flags: {'dualSim'}).matches(_p()), true);
    expect(const ProductFilter(flags: {'amoled'}).matches(_p()), true);
    expect(const ProductFilter(flags: {'verified'}).matches(_p()), true);
    expect(
      const ProductFilter(flags: {'verified'}).matches(_p(kyc: false)),
      false,
    );
    expect(const ProductFilter(flags: {'topRated'}).matches(_p()), true);
    expect(
      const ProductFilter(flags: {'topRated'}).matches(_p(rating: 3.0)),
      false,
    );
  });

  test('apply sorts and chips describe the filter', () {
    const f = ProductFilter(
      brands: {'Samsung'},
      sort: 'price_asc',
    );
    final out = f.apply([_p(price: 9), _p(price: 5)]);
    expect(out.map((e) => e.price), [5, 9]);
    expect(f.activeCount, 1);
    expect(f.chips().single.kind, 'brand');
  });
}
