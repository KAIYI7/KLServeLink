import 'package:flutter/material.dart';
import '../../../../core/theme/theme.dart';
import '../data/provider_services_repo.dart';
import 'provider_service_form_screen.dart';
import 'provider_service_detail_screen.dart';

enum ProviderServicesView { grid, list }

class ProviderServicesTab extends StatefulWidget {
  const ProviderServicesTab({super.key});

  @override
  State<ProviderServicesTab> createState() => _ProviderServicesTabState();
}

class _ProviderServicesTabState extends State<ProviderServicesTab> {
  final searchCtrl = TextEditingController();
  final repo = ProviderServicesRepo();

  ProviderServicesView view = ProviderServicesView.grid;

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  const _CircleBrand(),
                  const Spacer(),
                  const Text("My Services", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  _CircleButton(
                    icon: view == ProviderServicesView.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    onTap: () {
                      setState(() {
                        view = view == ProviderServicesView.grid
                            ? ProviderServicesView.list
                            : ProviderServicesView.grid;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _SearchBox(
                controller: searchCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<List<ProviderServiceUi>>(
                  stream: repo.watchMyServices(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(child: Text("Failed to load services."));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final all = snap.data!;
                    final q = searchCtrl.text.trim().toLowerCase();

                    final items = all.where((s) {
                      if (q.isEmpty) return true;
                      return s.name.toLowerCase().contains(q) ||
                          s.category.toLowerCase().contains(q);
                    }).toList();

                    if (items.isEmpty) return const _EmptyServices();

                    return (view == ProviderServicesView.grid)
                        ? _Grid(items: items)
                        : _List(items: items);
                  },
                ),
              ),

            ],
          ),
        ),
      ),

      floatingActionButton: Padding (
        padding: const EdgeInsets.only(bottom: 75),
        child : FloatingActionButton(
        backgroundColor: KLPalette.primary,
        foregroundColor: Colors.white,
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProviderServiceFormScreen()),
            );
          },
          child: const Icon(Icons.add),
      ),
    ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBox({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: KLPalette.text2),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: "Search services...",
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (controller.text.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  controller.clear();
                  onChanged("");
                },
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.close_rounded, color: KLPalette.text2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<ProviderServiceUi> items;

  const _Grid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.76,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ServiceCardGrid(s: items[i]),
    );
  }
}

class _List extends StatelessWidget {
  final List<ProviderServiceUi> items;

  const _List({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _ServiceCardList(s: items[i]),
    );
  }
}

class _ServiceCardGrid extends StatelessWidget {
  final ProviderServiceUi s;

  const _ServiceCardGrid({required this.s});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderServiceDetailScreen(service: s),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _ServiceCoverImage(s: s)),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _CategoryPill(text: s.category),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _PricePill(price: s.price),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RatingRow(rating: s.ratingAvg),
                    const SizedBox(height: 10),
                    Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        CircleAvatar(radius: 14, backgroundColor: KLPalette.tint100, child: Icon(Icons.person, size: 16, color: KLPalette.primary700)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "You",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCardList extends StatelessWidget {
  final ProviderServiceUi s;

  const _ServiceCardList({required this.s});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderServiceDetailScreen(service: s),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(26),
                  bottomLeft: Radius.circular(26),
                ),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 116,
                      child: _ServiceCoverImage(s: s),
                    ),
                    Positioned(left: 12, top: 12, child: _PricePill(price: s.price)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RatingRow(rating: s.ratingAvg),
                      const SizedBox(height: 8),
                      Text(
                        s.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: const [
                          CircleAvatar(radius: 14, backgroundColor: KLPalette.tint100, child: Icon(Icons.person, size: 16, color: KLPalette.primary700)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "You",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double rating;
  const _RatingRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 20),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2),
        ),
      ],
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String text;
  const _CategoryPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KLPalette.tint100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700, fontSize: 12),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final double price;
  const _PricePill({required this.price});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KLPalette.primary700,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "RM ${price.toStringAsFixed(0)}",
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  const _EmptyServices();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const SizedBox(height: 26),
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: KLPalette.tint50,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.storefront_rounded, size: 92, color: KLPalette.text2),
        ),
        const SizedBox(height: 18),
        const Text(
          "No services yet",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            "Create your first service so customers can find and book you.",
            textAlign: TextAlign.center,
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _CircleBrand extends StatelessWidget {
  const _CircleBrand();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        height: 48,
        width: 48,
        color: KLPalette.mutedBg,
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, color: KLPalette.text),
      ),
    );
  }
}

String _defaultAssetForCategory(String category) {
  final c = category.toLowerCase().trim();

  // normalize common variants
  if (c.contains('clean')) return 'assets/images/defaults/cleaning.jpg';
  if (c.contains('plumb')) return 'assets/images/defaults/plumbing.jpg';
  if (c.contains('Handyman & Repair') || c.contains('handyman') || c.contains('repair')) {
    return 'assets/images/defaults/handyman.jpg';
  }
  if (c.contains('air') || c.contains('cond') || c.contains('aircon')) {
    return 'assets/images/defaults/aircon.jpg';
  }
  if (c.contains('tutor') || c.contains('lesson')) {
    return 'assets/images/defaults/tutoring.jpg';
  }

  // fallback
  return 'assets/images/defaults/handyman.jpg';
}

String? _bestServiceImageUrl(ProviderServiceUi s) {
  final t = (s.thumbnailUrl ?? '').trim();
  if (t.isNotEmpty) return t;

  final photos = (s.photoUrls ?? const <String>[]);
  if (photos.isNotEmpty && photos.first.trim().isNotEmpty) return photos.first.trim();

  return null;
}

class _ServiceCoverImage extends StatelessWidget {
  final ProviderServiceUi s;
  const _ServiceCoverImage({required this.s});

  @override
  Widget build(BuildContext context) {
    final url = _bestServiceImageUrl(s);
    final fallbackAsset = _defaultAssetForCategory(s.category);

    if (url == null) {
      return Image.asset(fallbackAsset, fit: BoxFit.cover);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      // show something while loading
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: KLPalette.mutedBg,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: KLPalette.text2, size: 42),
        );
      },
      // if URL fails (403, 404, bad token), fallback to asset
      errorBuilder: (context, error, stack) {
        return Image.asset(fallbackAsset, fit: BoxFit.cover);
      },
    );
  }
}
