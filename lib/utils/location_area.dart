class LocationArea {
  static const _knownAreas = <String>{
    "ampang", "bangsar", "bangsar south", "bandar tun razak", "bandar tasik selatan",
    "brickfields", "bukit bintang", "bukit jalil", "bukit tunku", "cheras",
    "chow kit", "city centre", "damansara", "damansara heights", "danau kota",
    "desa petaling", "desa setapak", "desa sri hartamas", "desapark city",
    "gombak", "jalan ipoh", "jalan klang lama", "jinjang", "kampung baru",
    "kepong", "keramat", "klcc", "kl sentral", "kuchai lama", "lembah pantai",
    "maluri", "manjalara", "medan tuanku", "mid valley", "mont kiara",
    "old klang road", "oug", "pantai dalam", "petaling street", "pudu",
    "salak south", "segambut", "sentul", "seputeh", "setapak", "setiawangsa",
    "shamelin", "solaris dutamas", "sri petaling", "sri rampai", "sungai besi",
    "taman connaught", "taman desa", "taman melati", "taman tun dr ismail", "ttdi",
    "titiwangsa", "wangsa maju",
  };

  static String fromLocationText(String s) {
    if (s.trim().isEmpty) return "";

    // Normalize
    final raw = s.replaceAll(RegExp(r"\s+"), " ").trim();

    // Split by comma segments (most addresses are comma-separated)
    final parts = raw.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return "";

    final detected = _detectKnownArea(parts);
    if (detected.isNotEmpty) return detected;

    // Common “city/state/country” tails which don't want as "area"
    const stopWords = {
      "kuala lumpur",
      "wilayah persekutuan",
      "selangor",
      "malaysia",
    };

    bool isPostcode(String x) => RegExp(r"^\d{5}$").hasMatch(x);
    bool looksLikeCityLine(String x) {
      final xl = x.toLowerCase();
      if (stopWords.contains(xl)) return true;
      // "53300 Kuala Lumpur" style
      if (RegExp(r"^\d{5}\s+").hasMatch(xl)) return true;
      return false;
    }

    // Walk from the end, skipping postcode/city/state/country
    int i = parts.length - 1;

    // Skip trailing city/state/country chunks
    while (i >= 0 && looksLikeCityLine(parts[i])) {
      i--;
    }

    // If land on a pure postcode, skip it too
    if (i >= 0 && isPostcode(parts[i])) {
      i--;
    }

    // Pick a likely “area” candidate:
    // Prefer the nearest remaining token from the tail (often the neighborhood)
    while (i >= 0) {
      final cand = parts[i].trim();
      final cl = cand.toLowerCase();

      // Skip empty/stopwords again
      if (cand.isEmpty || stopWords.contains(cl) || looksLikeCityLine(cand) || isPostcode(cand)) {
        i--;
        continue;
      }

      // Avoid lines that are clearly unit/building/road
      final isRoadLike = RegExp(r"\b(jalan|lorong|persiaran|lebuh|road|rd|street|st|avenue|ave)\b", caseSensitive: false)
          .hasMatch(cand);
      final isUnitLike = RegExp(r"\b(no\.?|unit|block|blok|b-\d+|\d+[a-z]?)\b", caseSensitive: false)
          .hasMatch(cand);

      // If it's road/unit-like, keep walking upwards to find a better area token
      if (isRoadLike || isUnitLike) {
        i--;
        continue;
      }

      return _titleCase(cand);
    }

    // Fallback: if can't confidently parse, use city if present
    final city = parts.firstWhere(
          (p) => p.toLowerCase().contains("kuala lumpur"),
      orElse: () => "",
    );
    if (city.isNotEmpty) return "Kuala Lumpur";

    // Last fallback: use last part trimmed
    return _titleCase(parts.last);
  }

  static String _titleCase(String s) {
    final words = s.split(" ").where((w) => w.isNotEmpty).toList();
    return words.map((w) {
      if (w.length <= 1) return w.toUpperCase();
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(" ");
  }

  static String _detectKnownArea(List<String> parts) {
    final full = parts.join(", ").toLowerCase();

    final sorted = _knownAreas.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final a in sorted) {
      final pattern = RegExp(r'(^|[^a-z])' + RegExp.escape(a) + r'([^a-z]|$)');
      if (pattern.hasMatch(full)) {
        return _titleCase(a);
      }
    }

    return "";
  }

}