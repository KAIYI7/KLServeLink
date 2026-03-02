class GeoHash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String encode(double lat, double lng, {int precision = 9}) {
    var latMin = -90.0, latMax = 90.0;
    var lngMin = -180.0, lngMax = 180.0;

    final buffer = StringBuffer();
    var isEven = true;
    var bit = 0;
    var ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          ch |= 1 << (4 - bit);
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch |= 1 << (4 - bit);
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isEven = !isEven;

      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }
}