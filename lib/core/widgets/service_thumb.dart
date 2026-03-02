import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ServiceThumb extends StatelessWidget {
  /// Pass BookingUi / ProviderBooking / anything.
  final Object model;

  final BoxFit fit;
  final IconData placeholderIcon;
  final Color? placeholderBg;
  final Color? placeholderIconColor;
  final double iconSize;

  const ServiceThumb({
    super.key,
    required this.model,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image,
    this.placeholderBg,
    this.placeholderIconColor,
    this.iconSize = 44,
  });

  // Lightweight caches to avoid repeated reads in lists.
  static final Map<String, String?> _urlCache = {};
  static final Map<String, Future<String?>> _futureCache = {};

  @override
  Widget build(BuildContext context) {
    final serviceName = _tryGetServiceName(model);
    final fallbackAsset = serviceName != null
        ? _defaultAssetForServiceName(serviceName)
        : null;

    // If model already has an image URL -> use it
    final direct = _tryGetImageUrl(model);
    if (direct != null) {
      return _NetImage(
        url: direct,
        fit: fit,
        placeholderIcon: placeholderIcon,
        bg: placeholderBg,
        iconColor: placeholderIconColor,
        iconSize: iconSize,
        fallbackAsset: fallbackAsset,
      );
    }

    // Else read service doc by serviceId/listingId
    final serviceId = _tryGetServiceId(model);
    if (serviceId == null) {
      return _NetImage(
        url: null,
        fit: fit,
        placeholderIcon: placeholderIcon,
        bg: placeholderBg,
        iconColor: placeholderIconColor,
        iconSize: iconSize,
        fallbackAsset: fallbackAsset,
      );
    }

    // If already cached, return immediately
    if (_urlCache.containsKey(serviceId)) {
      return _NetImage(
        url: _urlCache[serviceId],
        fit: fit,
        placeholderIcon: placeholderIcon,
        bg: placeholderBg,
        iconColor: placeholderIconColor,
        iconSize: iconSize,
        fallbackAsset: fallbackAsset,
      );
    }

    final future = _futureCache.putIfAbsent(serviceId, () async {
      try {
        final snap = await FirebaseFirestore.instance.collection('services').doc(serviceId).get();
        final m = snap.data() ?? <String, dynamic>{};
        final url = _coverUrlFromServiceDoc(m);
        _urlCache[serviceId] = url;
        return url;
      } catch (_) {
        _urlCache[serviceId] = null;
        return null;
      }
    });

    return FutureBuilder<String?>(
      future: future,
      builder: (context, s) {
        return _NetImage(
          url: s.data,
          fit: fit,
          placeholderIcon: placeholderIcon,
          bg: placeholderBg,
          iconColor: placeholderIconColor,
          iconSize: iconSize,
          fallbackAsset: fallbackAsset,
        );
      },
    );
  }

  String? _tryGetServiceId(Object obj) {
    final d = obj as dynamic;

    String? pick(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    try { final v = pick(d.serviceId); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.listingId); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.serviceRefId); if (v != null) return v; } catch (_) {}
    return null;
  }

  String? _tryGetImageUrl(Object obj) {
    final d = obj as dynamic;

    String? pick(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    // Common names
    try { final v = pick(d.thumbnailUrl); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.serviceThumbnailUrl); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.coverUrl); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.imageUrl); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.photoUrl); if (v != null) return v; } catch (_) {}
    try { final v = pick(d.serviceImageUrl); if (v != null) return v; } catch (_) {}

    return null;
  }

  String? _coverUrlFromServiceDoc(Map<String, dynamic> m) {
    String? pickString(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final direct = pickString(m['thumbnailUrl']) ??
        pickString(m['coverUrl']) ??
        pickString(m['imageUrl']) ??
        pickString(m['photoUrl']) ??
        pickString(m['thumbnail']);

    if (direct != null) return direct;

    final photoUrls = m['photoUrls'];
    if (photoUrls is List && photoUrls.isNotEmpty && photoUrls.first is String) {
      final v = (photoUrls.first as String).trim();
      if (v.isNotEmpty) return v;
    }

    final images = m['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
      if (first is Map) {
        final url = first['url'] ?? first['downloadUrl'] ?? first['thumbnailUrl'];
        if (url is String && url.trim().isNotEmpty) return url.trim();
      }
    }

    return null;
  }
}

class _NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData placeholderIcon;
  final Color? bg;
  final Color? iconColor;
  final double iconSize;
  final String? fallbackAsset;

  const _NetImage({
    this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image,
    this.bg,
    this.iconColor,
    this.iconSize = 44,
    this.fallbackAsset,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    Widget placeholder() {
      if (fallbackAsset != null) {
        return Image.asset(fallbackAsset!, fit: fit);
      }

      return Container(
        color: bg ?? const Color(0xFFF3F4F6),
        alignment: Alignment.center,
        child: Icon(
          placeholderIcon,
          size: iconSize,
          color: iconColor ?? const Color(0xFF9CA3AF),
        ),
      );
    }

    if (u.isEmpty) return placeholder();

    return Image.network(
      u,
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder(),
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (progress.expectedTotalBytes == null)
                    ? null
                    : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
              ),
            ),
          ],
        );
      },
    );
  }
}

String? _defaultAssetForServiceName(String serviceName) {
  final c = serviceName.toLowerCase().trim();

  if (c.contains('clean')) return 'assets/images/defaults/cleaning.jpg';
  if (c.contains('plumb')) return 'assets/images/defaults/plumbing.jpg';
  if (c.contains('handyman') || c.contains('repair')) {
    return 'assets/images/defaults/handyman.jpg';
  }
  if (c.contains('air') || c.contains('cond') || c.contains('aircon')) {
    return 'assets/images/defaults/aircon.jpg';
  }
  if (c.contains('tutor') || c.contains('lesson')) {
    return 'assets/images/defaults/tutoring.jpg';
  }

  return null;
}

String? _tryGetServiceName(Object obj) {
  final d = obj as dynamic;

  String? pick(dynamic v) =>
      (v is String && v.trim().isNotEmpty) ? v.trim() : null;

  try { final v = pick(d.serviceName); if (v != null) return v; } catch (_) {}
  try { final v = pick(d.name); if (v != null) return v; } catch (_) {}
  try { final v = pick(d.title); if (v != null) return v; } catch (_) {}

  return null;
}