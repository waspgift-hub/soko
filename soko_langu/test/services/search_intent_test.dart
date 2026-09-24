import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/search_intent.dart';

void main() {
  test('understands brand + model', () {
    final i = parseSearchIntent('Samsung A55');
    expect(i.brand, 'Samsung');
    expect(i.category?.id, 'phones');
    expect(i.rest, 'a55');
  });

  test('understands brand + category + ram', () {
    final i = parseSearchIntent('HP laptop 16GB');
    expect(i.brand, 'HP');
    expect(i.category?.id, 'computers');
    expect(i.attributes['storage'], '16GB');
  });

  test('understands ram/storage pair and flags', () {
    final i = parseSearchIntent('Tecno spark 8GB 128GB dual sim');
    expect(i.brand, 'Tecno');
    expect(i.attributes['ram'], '8GB');
    expect(i.attributes['storage'], '128GB');
    expect(i.flags.contains('dualSim'), true);
  });

  test('plain text stays untouched', () {
    final i = parseSearchIntent('kitenge dress');
    expect(i.brand, isNull);
    expect(i.rest, 'kitenge dress');
  });

  test('5G flag is detected', () {
    final i = parseSearchIntent('Samsung Galaxy 5G');
    expect(i.flags.contains('fiveG'), true);
    expect(i.brand, 'Samsung');
  });
}
