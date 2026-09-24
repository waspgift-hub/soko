import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/category_model.dart';

void main() {
  Category cat({String icon = 'smartphone', String? image}) => Category(
        id: 'electronics',
        name: 'Electronics',
        nameSw: 'Vifaa vya Umeme',
        icon: icon,
        image: image,
        subcategories: const [],
      );

  test('prefers the explicit image', () {
    expect(cat(image: 'assets/images/categories/electronics.jpg').displayImage,
        'assets/images/categories/electronics.jpg');
  });

  test('uses a remote icon URL when image is missing', () {
    expect(cat(icon: 'https://cdn/x.png').displayImage, 'https://cdn/x.png');
  });

  test('is null for canonical icon names so the icon renders', () {
    expect(cat().displayImage, isNull);
  });
}
