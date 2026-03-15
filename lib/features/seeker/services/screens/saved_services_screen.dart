import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/theme/theme.dart';
import 'package:fyp_flutter/features/seeker/navigation/seeker_nav_controller.dart';
import '../data/saved_services_repo.dart';
import '../data/seeker_services_repo.dart';
import '../widgets/saved_service_button.dart';
import 'service_details_screen.dart';

class SavedServicesScreen extends StatelessWidget {
  final SeekerNavController nav;

  const SavedServicesScreen({
    super.key,
    required this.nav,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        backgroundColor: KLPalette.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              children: [
                _TopBar(
                  title: "Saved Services",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 24),
                const Expanded(
                  child: _SavedEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: "Please login",
                    subtitle: "Login to view your saved services.",
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final savedRepo = SavedServicesRepo();
    final serviceRepo = SeekerServicesRepo();

    return StreamBuilder<List<SavedServiceEntry>>(
      stream: savedRepo.streamMySavedEntries(),
      builder: (context, savedSnap) {
        if (savedSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final savedEntries = savedSnap.data ?? const <SavedServiceEntry>[];

        if (savedEntries.isEmpty) {
          return Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  children: [
                    _TopBar(
                      title: "Saved Services",
                      onBack: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 24),
                    const Expanded(
                      child: _SavedEmptyState(
                        icon: Icons.bookmark_border_rounded,
                        title: "No saved services yet",
                        subtitle: "Tap the bookmark icon on any service to save it here.",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final savedIds = savedEntries.map((e) => e.serviceId).toSet();
        final orderMap = <String, int>{
          for (int i = 0; i < savedEntries.length; i++) savedEntries[i].serviceId: i,
        };

        return StreamBuilder<List<SeekerServiceUi>>(
          stream: serviceRepo.watchActive(),
          builder: (context, serviceSnap) {
            if (serviceSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: KLPalette.bg,
                body: SafeArea(
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final allServices = serviceSnap.data ?? const <SeekerServiceUi>[];

            final savedServices = allServices
                .where((s) => savedIds.contains(s.id))
                .toList()
              ..sort((a, b) {
                final ai = orderMap[a.id] ?? 999999;
                final bi = orderMap[b.id] ?? 999999;
                return ai.compareTo(bi);
              });

            final unavailableCount = savedEntries.length - savedServices.length;

            return Scaffold(
              backgroundColor: KLPalette.bg,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    children: [
                      _TopBar(
                        title: "Saved Services",
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Text(
                            "${savedEntries.length} saved",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: KLPalette.tint50,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: const Text(
                              "Quick access",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: KLPalette.primary,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (unavailableCount > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Text(
                            "$unavailableCount saved service${unavailableCount == 1 ? '' : 's'} "
                                "are no longer available or active.",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      Expanded(
                        child: savedServices.isEmpty
                            ? const _SavedEmptyState(
                          icon: Icons.bookmark_border_rounded,
                          title: "No active saved services",
                          subtitle: "Your saved services may have been removed or are no longer active.",
                        )
                            : ListView.separated(
                          itemCount: savedServices.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final s = savedServices[index];
                            return _SavedServiceCard(
                              nav: nav,
                              service: s,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48, height: 48),
      ],
    );
  }
}

class _SavedEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SavedEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 110,
            width: 110,
            decoration: BoxDecoration(
              color: KLPalette.tint50,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: Icon(
              icon,
              size: 48,
              color: KLPalette.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KLPalette.text2,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedServiceCard extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerServiceUi service;

  const _SavedServiceCard({
    required this.nav,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final finalPrice = (service.price.toDouble() *
        (1.0 - service.discount.toDouble().clamp(0.0, 100.0) / 100.0))
        .clamp(0.0, 1e12);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsScreen.fromServiceId(
              serviceId: service.id,
              nav: nav,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            children: [
              Container(
                height: 116,
                width: 116,
                color: KLPalette.mutedBg,
                child: _ServiceCoverImage(service: service),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              service.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SavedServiceButton(
                            serviceId: service.id,
                            size: 40,
                            backgroundColor: Colors.white,
                            savedBackgroundColor: const Color(0xFFFFF3C4),
                            iconColor: KLPalette.text,
                            savedIconColor: const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service.category,
                        style: const TextStyle(
                          color: KLPalette.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 16, color: KLPalette.text2),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              service.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: KLPalette.text2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            "RM ${finalPrice.toStringAsFixed(0)}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 20),
                          const SizedBox(width: 4),
                          Text(
                            service.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
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

String? _bestServiceImageUrl(SeekerServiceUi s) {
  final thumb = (s.thumbnailUrl ?? '').trim();
  if (thumb.isNotEmpty) return thumb;

  final photos = s.photoUrls;
  if (photos.isNotEmpty) {
    final first = photos.first.trim();
    if (first.isNotEmpty) return first;
  }

  return null;
}

String _defaultAssetForCategory(String category) {
  final c = category.toLowerCase().trim();

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

  return 'assets/images/defaults/handyman.jpg';
}

class _ServiceCoverImage extends StatelessWidget {
  final SeekerServiceUi service;

  const _ServiceCoverImage({required this.service});

  @override
  Widget build(BuildContext context) {
    final url = _bestServiceImageUrl(service);
    final fallbackAsset = _defaultAssetForCategory(service.category);

    if (url == null) {
      return Image.asset(fallbackAsset, fit: BoxFit.cover);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: KLPalette.tint50,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: KLPalette.text2, size: 42),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(fallbackAsset, fit: BoxFit.cover);
      },
    );
  }
}
