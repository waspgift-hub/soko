import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soko_vibe/utils/category_icons.dart';

void main() {
  test('slug wins over a stale icon value', () {
    expect(
      categoryIconFor(icon: '📱', slug: 'fashion', name: 'Fashion'),
      Icons.checkroom_rounded,
    );
  });

  test('canonical names resolve to rounded solid icons', () {
    expect(categoryIconFor(icon: 'smartphone'), Icons.smartphone_rounded);
    expect(categoryIconFor(icon: 'handyman'), Icons.handyman_rounded);
    expect(categoryIconFor(icon: 'package'), Icons.inventory_2_rounded);
  });

  test('legacy emoji still render for old Firestore docs', () {
    expect(categoryIconFor(icon: '📱'), Icons.smartphone_rounded);
    expect(categoryIconFor(icon: '🏠'), Icons.chair_rounded);
  });

  test('server icon URLs and unknowns fall back, never raw text', () {
    expect(
      categoryIconFor(icon: 'https://cdn/x.png'),
      Icons.inventory_2_rounded,
    );
    expect(categoryIconFor(icon: '???'), Icons.inventory_2_rounded);
    expect(categoryIconFor(), Icons.inventory_2_rounded);
  });

  test('every canonical name maps to a real icon', () {
    const names = [
      'package',
      'smartphone',
      'checkroom',
      'chair',
      'child_care',
      'spa',
      'car',
      'soccer',
      'book',
      'fastfood',
      'grocery',
      'handyman',
      'factory',
      'diamond',
      'gift',
      'shopping_bag',
      'toys',
    ];
    for (final name in names) {
      expect(categoryIconFor(icon: name), isA<IconData>());
    }
  });
}
