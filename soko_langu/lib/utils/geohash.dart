class Geohash {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const List<int> _bits = [16, 8, 4, 2, 1];

  static String encode(double lat, double lng, {int precision = 9}) {
    double latMin = -90, latMax = 90;
    double lngMin = -180, lngMax = 180;
    final buf = StringBuffer();
    bool isEven = true;
    int bit = 0, ch = 0;

    while (buf.length < precision) {
      if (isEven) {
        final mid = (lngMin + lngMax) / 2;
        if (lng > mid) {
          ch |= _bits[bit];
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat > mid) {
          ch |= _bits[bit];
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buf.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return buf.toString();
  }

  static List<String> neighbors(String geohash) {
    if (geohash.isEmpty) return [];
    return [geohash];
  }

  static double decodeLatitude(String geohash) {
    return _decodeRange(geohash, false).center;
  }

  static double decodeLongitude(String geohash) {
    return _decodeRange(geohash, true).center;
  }

  static _Range _decodeRange(String geohash, bool isLng) {
    double min = isLng ? -180 : -90;
    double max = isLng ? 180 : 90;
    bool isEven = true;

    for (int i = 0; i < geohash.length; i++) {
      final c = geohash[i];
      final cd = _base32.indexOf(c);
      for (int j = 0; j < 5; j++) {
        if (isEven == isLng) {
          final mid = (min + max) / 2;
          if ((cd & _bits[j]) != 0) {
            min = mid;
          } else {
            max = mid;
          }
        }
        isEven = !isEven;
      }
    }
    return _Range(min, max);
  }
}

class _Range {
  final double min;
  final double max;
  const _Range(this.min, this.max);
  double get center => (min + max) / 2;
}
