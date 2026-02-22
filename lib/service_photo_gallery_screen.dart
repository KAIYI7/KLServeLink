import 'package:flutter/material.dart';
import 'theme.dart';

class ServicePhotoGalleryScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const ServicePhotoGalleryScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<ServicePhotoGalleryScreen> createState() => _ServicePhotoGalleryScreenState();
}

class _ServicePhotoGalleryScreenState extends State<ServicePhotoGalleryScreen> {
  late final PageController _pc;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, (widget.urls.length - 1).clamp(0, 1 << 30));
    _pc = PageController(initialPage: _idx);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          total == 0 ? "Photos" : "${_idx + 1} / $total",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: total == 0
          ? const Center(
        child: Text("No photos", style: TextStyle(color: Colors.white70)),
      )
          : PageView.builder(
        controller: _pc,
        onPageChanged: (i) => setState(() => _idx = i),
        itemCount: total,
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) {
                  if (p == null) return child;
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                },
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70, size: 48),
              ),
            ),
          );
        },
      ),
    );
  }
}
