import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/features/seeker/services/data/seeker_services_repo.dart';
import '../../../core/widgets/category_grid_3x2.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/ui_components.dart';
import '../navigation/seeker_nav_controller.dart';
import '../services/screens/service_details_screen.dart';
import '../profile/data/seeker_user_firestore.dart';
import '../addresses/data/seeker_address_firestore.dart';
import '../addresses/screens/your_address_screen.dart';
import '../../notifications/data/notifications_repo.dart';
import '../../notifications/screens/notifications_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/screens/edit_profile_screen.dart';

class SeekerHomeScreen extends StatefulWidget {
  final SeekerNavController nav;
  const SeekerHomeScreen({super.key, required this.nav});

  @override
  State<SeekerHomeScreen> createState() => _SeekerHomeScreenState();
}

class _SeekerHomeScreenState extends State<SeekerHomeScreen> {
  final _userFs = SeekerUserFirestore();
  final _addrFs = SeekerAddressFirestore();
  final _svcRepo = SeekerServicesRepo();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar (name + main address)
                    Row(
                      children: [
                        _SeekerAvatar(uid: uid, nav: widget.nav),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StreamBuilder<String>(
                                stream: _userFs.streamMyName(),
                                builder: (context, snap) {
                                  final name = snap.data ?? "User";
                                  return Text(
                                    "Hello $name",
                                    style:
                                    Theme.of(context).textTheme.titleMedium,
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              StreamBuilder<AddressUiModel?>(
                                stream: _addrFs.streamMainAddress(
                                  uid: (FirebaseAuth
                                      .instance.currentUser?.uid ??
                                      ""),
                                ),
                                builder: (context, snap) {
                                  final a = snap.data;
                                  final label =
                                  (a == null || a.addressLine.trim().isEmpty)
                                      ? "Set your main address"
                                      : a.addressLine;

                                  return Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: 18),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        CircleIconButton(
                          icon: Icons.search,
                          filled: true,
                          onTap: () => widget.nav.goSearch(),
                        ),
                        const SizedBox(width: 12),
                        CircleIconButton(
                          icon: Icons.notifications_none_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NotificationsScreen(
                                  isProvider: false,
                                  seekerNav: widget.nav,
                                ),
                              ),
                            );
                          },
                          badge: (uid == null)
                              ? null
                              : StreamBuilder<int>(
                            stream: NotificationsRepo().unreadCount(uid),
                            builder: (_, s) {
                              final c = s.data ?? 0;
                              if (c <= 0) return const SizedBox.shrink();
                              return const NotificationDot();
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    _PromoBanner(
                      title: "Up to 20% Off on\nCleaning Services",
                      onTap: () => widget.nav.goSearch(),
                    ),
                    const SizedBox(height: 22),

                    Row(
                      children: [
                        Text("Services", style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),

            // Services grid
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: CategoryGrid3x2(
                  onTap: (cat) {
                    widget.nav.goSearch(SearchIntent.byCategory(cat));
                  },
                ),
              ),
            ),

            // Recommended for you (personalized -> fallback to popular)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title: "Recommended for You", onSeeAll: () => _openRecoWhySheet(context),),
                    const SizedBox(height: 14),

                    StreamBuilder<RecommendationsPayload?>(
                      stream: _userFs.streamMyRecommendationsPayload(limit: 5),
                      builder: (context, recSnap) {
                        if (!recSnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final payload = recSnap.data;
                        final ids = payload?.serviceIds ?? const <String>[];
                        final reasons = payload?.reasons ?? const <String, List<RecommendationReason>>{};

                        // Fallback to popular if no recommendations yet
                        if (ids.isEmpty) {
                          return StreamBuilder<List<SeekerServiceUi>>(
                            stream: _svcRepo.streamPopular(limit: 3),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child:
                                  Center(child: CircularProgressIndicator()),
                                );
                              }

                              final list =
                                  snap.data ?? const <SeekerServiceUi>[];
                              if (list.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                    "No recommendations yet.",
                                    style: TextStyle(
                                      color: KLPalette.text2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  for (int i = 0; i < list.length; i++) ...[
                                    _PopularCardFromFs(
                                      nav: widget.nav,
                                      service: list[i],
                                      tint: (i == 0)
                                          ? const Color(0xFF0EA5E9)
                                          : (i == 1)
                                          ? KLPalette.primary
                                          : const Color(0xFF60A5FA),
                                    ),
                                    if (i != list.length - 1)
                                      const SizedBox(height: 12),
                                  ],
                                ],
                              );
                            },
                          );
                        }

                        // Personalized recommendations
                        return StreamBuilder<List<SeekerServiceUi>>(
                          stream: _svcRepo.streamByIds(ids),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child:
                                Center(child: CircularProgressIndicator()),
                              );
                            }

                            final list =
                                snap.data ?? const <SeekerServiceUi>[];
                            final byId = <String, SeekerServiceUi>{
                              for (final s in list) s.id: s,
                            };

                            String? reasonTextFor(String recId) {
                              final r = reasons[recId];
                              if (r == null || r.isEmpty) return null;

                              final becauseId = r.first.becauseServiceId;
                              final becauseSvc = byId[becauseId];

                              if (becauseSvc != null && becauseSvc.name.trim().isNotEmpty) {
                                return "Because you explored ${becauseSvc.name}";
                              }
                              return "Because you explored similar services";
                            }

                            final recServices = <SeekerServiceUi>[];
                            for (final sid in ids) {
                              final s = byId[sid];
                              if (s != null) recServices.add(s);
                            }

                            if (recServices.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  "No recommended services found.",
                                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                                ),
                              );
                            }

                            return Column(
                              children: [
                                for (int i = 0; i < recServices.length; i++) ...[
                                  _PopularCardFromFs(
                                    nav: widget.nav,
                                    service: recServices[i],
                                    reasonText: reasonTextFor(recServices[i].id),
                                    tint: (i == 0)
                                        ? const Color(0xFF0EA5E9)
                                        : (i == 1)
                                        ? KLPalette.primary
                                        : const Color(0xFF60A5FA),
                                  ),
                                  if (i != recServices.length - 1)
                                    const SizedBox(height: 12),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(
                height: 92.0 + MediaQuery.of(context).padding.bottom + 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecoWhySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecoWhySheet(
        nav: widget.nav,
        userFs: _userFs,
        svcRepo: _svcRepo,
        limit: 20,
      ),
    );
  }

}

class _PromoBanner extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _PromoBanner({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    KLPalette.primary,
                    KLPalette.primary.withOpacity(0.65),
                  ],
                ),
              ),
            ),

            // subtle highlight overlay
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF111827),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            onPressed: onTap,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                "Booking Now",
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            // Right-side image placeholder
            // Positioned(
            //   right: 8,
            //   bottom: 8,
            //   child: Container(
            //     height: 180,
            //     width: 160,
            //     decoration: BoxDecoration(
            //       color: Colors.white.withOpacity(0.18),
            //       borderRadius: BorderRadius.circular(28),
            //     ),
            //     alignment: Alignment.center,
            //     child: const Icon(Icons.person, color: Colors.white, size: 70),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KLPalette.mutedBg,
              border: Border.all(color: KLPalette.border),
            ),
            child: Icon(icon, color: KLPalette.primary),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PopularCardFromFs extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerServiceUi service;
  final Color tint;
  final String? reasonText;

  const _PopularCardFromFs({
    required this.nav,
    required this.service,
    required this.tint,
    this.reasonText,
  });

  @override
  Widget build(BuildContext context) {
    final finalPrice = (service.price.toDouble() *
        (1.0 -
            service.discount.toDouble().clamp(0.0, 100.0) / 100.0))
        .clamp(0.0, 1e12);
    final priceText =
    finalPrice > 0 ? "RM ${finalPrice.toStringAsFixed(0)}" : "RM -";
    final ratingText =
    service.rating > 0 ? service.rating.toStringAsFixed(1) : "-";

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsScreen.fromServiceId(
              nav: nav,
              serviceId: service.id,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            color: tint.withOpacity(0.18),
            border: Border.all(color: KLPalette.border),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [tint.withOpacity(0.65), tint.withOpacity(0.15)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            priceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Text(
                              ratingText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          height: 66,
                          width: 90,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _SeekerServiceThumb(service: service),
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

String? _bestSeekerServiceImageUrl(SeekerServiceUi s) {
  final t = ((s.thumbnailUrl ?? '') as String).trim();
  if (t.isNotEmpty) return t;

  final photos = (s.photoUrls ?? const <String>[]);
  if (photos.isNotEmpty) {
    final first = photos.first.trim();
    if (first.isNotEmpty) return first;
  }
  return null;
}

class _SeekerServiceThumb extends StatelessWidget {
  final SeekerServiceUi service;
  const _SeekerServiceThumb({required this.service});

  @override
  Widget build(BuildContext context) {
    final url = _bestSeekerServiceImageUrl(service);
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
          color: KLPalette.mutedBg,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: KLPalette.text2, size: 28),
        );
      },
      errorBuilder: (context, error, stack) {
        return Image.asset(fallbackAsset, fit: BoxFit.cover);
      },
    );
  }
}

class _RecoWhySheet extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerUserFirestore userFs;
  final SeekerServicesRepo svcRepo;
  final int limit;

  const _RecoWhySheet({
    required this.nav,
    required this.userFs,
    required this.svcRepo,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      builder: (context, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: Material(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    height: 5,
                    width: 44,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Text(
                          "Recommended for you — explained",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: StreamBuilder<RecommendationsPayload?>(
                      stream: userFs.streamMyRecommendationsPayload(limit: limit),
                      builder: (context, recSnap) {
                        if (!recSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final payload = recSnap.data;
                        final ids = payload?.serviceIds ?? const <String>[];
                        final reasons = payload?.reasons ?? const <String, List<RecommendationReason>>{};
                        final meta = payload?.meta ?? const <String, dynamic>{};

                        final algo = (payload?.algo ?? "").trim();
                        final isColdStart = algo == "cold_start";

                        // If nothing recommended yet -> show popular in the sheet
                        if (ids.isEmpty) {
                          return StreamBuilder<List<SeekerServiceUi>>(
                            stream: svcRepo.streamPopular(limit: 10),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final list = snap.data ?? const <SeekerServiceUi>[];
                              if (list.isEmpty) {
                                return ListView(
                                  controller: scrollCtrl,
                                  padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomPad),
                                  children: const [
                                    Text(
                                      "No recommendations yet.",
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                );
                              }

                              return ListView(
                                controller: scrollCtrl,
                                padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomPad),
                                children: [
                                  _RecoMetaCard(
                                    title: "Popular services",
                                    lines: const [
                                      "You’ll see personalized recommendations after you browse or book more services.",
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  for (final s in list) ...[
                                    _RecoWhyRow(
                                      nav: nav,
                                      service: s,
                                      reasonLines: const ["Popular among users"],
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              );
                            },
                          );
                        }

                        // Collect all becauseServiceIds (top 3 per recommended item)
                        final becauseIds = <String>{};
                        for (final recId in ids) {
                          final arr = reasons[recId];
                          if (arr == null) continue;
                          for (final r in arr.take(3)) {
                            if (r.becauseServiceId.trim().isNotEmpty) {
                              becauseIds.add(r.becauseServiceId.trim());
                            }
                          }
                        }

                        final allIds = {...ids, ...becauseIds}.toList();

                        return FutureBuilder<List<SeekerServiceUi>>(
                          future: svcRepo.fetchByIds(allIds),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final list = snap.data ?? const <SeekerServiceUi>[];
                            final byId = <String, SeekerServiceUi>{
                              for (final s in list) s.id: s,
                            };

                            List<String> reasonLinesFor(String recId) {
                              final arr = reasons[recId];
                              if (arr == null || arr.isEmpty) return const [];

                              String lineFor(RecommendationReason r) {
                                final src = r.source.toLowerCase().trim();
                                final because = byId[r.becauseServiceId];
                                final name = (because?.name ?? "").trim();
                                final text = r.becauseText.trim();

                                if (src == "booked") {
                                  return name.isNotEmpty
                                      ? "Because you booked: $name"
                                      : "Because you booked similar services before";
                                }

                                if (src == "viewed") {
                                  return name.isNotEmpty
                                      ? "Because you viewed: $name"
                                      : "Because you viewed similar services recently";
                                }

                                if (src == "searched") {
                                  final q = text.isNotEmpty ? text : (name.isNotEmpty ? name : "services like this");
                                  return "Because you searched for: $q";
                                }

                                // fallback
                                if (name.isNotEmpty) return "Because you showed interest in: $name";
                                if (text.isNotEmpty) return "Because of your recent activity: $text";
                                return "Because it matches your recent activity";
                              }

                              final lines = <String>[];
                              for (final r in arr.take(3)) {
                                lines.add(lineFor(r));
                              }

                              return lines;
                            }

                            // Build ordered recommended services (keep order in ids)
                            final recServices = <SeekerServiceUi>[];
                            for (final sid in ids) {
                              final s = byId[sid];
                              if (s != null) recServices.add(s);
                            }

                            return ListView(
                              controller: scrollCtrl,
                              padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomPad),
                              children: [
                                _RecoMetaCard(
                                  title: "Note",
                                  lines:
                                  [
                                    if (isColdStart) ...[
                                      "These recommendations are based on popular and highly rated services (and your location when available).",
                                      "Browse or book a few services and the recommendations will become more personalised.",
                                    ] else ...[
                                      "We recommend services based on what you’ve browsed and booked before.",
                                      "The items under “Why you’re seeing this” are the main services that influenced each recommendation.",
                                      "You might still see a few suggestions outside your usual choices to help you discover new options.",
                                      "This is automated and may not be perfect — your next searches and bookings will improve it.",
                                    ],
                                    if (meta["geoRadiusKm"] != null)
                                      "Tip: Recommendations are prioritised within about ${meta["geoRadiusKm"]} km of your main address (when location is available).",
                                  ],
                                ),
                                const SizedBox(height: 12),

                                for (final s in recServices) ...[
                                  _RecoWhyRow(
                                    nav: nav,
                                    service: s,
                                    reasonLines: reasonLinesFor(s.id),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            );
                          },
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
  }
}

class _RecoMetaCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _RecoMetaCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KLPalette.mutedBg,
        border: Border.all(color: KLPalette.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l,
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecoWhyRow extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerServiceUi service;
  final List<String> reasonLines;

  const _RecoWhyRow({
    required this.nav,
    required this.service,
    required this.reasonLines,
  });

  @override
  Widget build(BuildContext context) {
    final finalPrice = (service.price.toDouble() *
        (1.0 - service.discount.toDouble().clamp(0.0, 100.0) / 100.0))
        .clamp(0.0, 1e12);
    final priceText = finalPrice > 0 ? "RM ${finalPrice.toStringAsFixed(0)}" : "RM -";
    final ratingText = service.rating > 0 ? service.rating.toStringAsFixed(1) : "-";

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.pop(context); // close sheet first
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsScreen.fromServiceId(
              nav: nav,
              serviceId: service.id,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: KLPalette.border),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 64,
                width: 64,
                child: _SeekerServiceThumb(service: service),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 10),
                      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 2),
                      Text(ratingText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  if (reasonLines.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      "Why you’re seeing this",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: KLPalette.text2,
                      ),
                    ),
                    const SizedBox(height: 6),

                    for (final l in reasonLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle, size: 16, color: KLPalette.primary),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: KLPalette.text2,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekerAvatar extends StatelessWidget {
  final String? uid;
  final SeekerNavController nav;

  const _SeekerAvatar({
    required this.uid,
    required this.nav,
  });

  @override
  Widget build(BuildContext context) {
    final u = (uid ?? '').trim();

    Widget avatarCircle({String? photoUrl}) {
      final url = (photoUrl ?? '').trim();

      Widget fallbackIcon() => const CircleAvatar(
        radius: 24,
        backgroundColor: KLPalette.tint50,
        child: Icon(Icons.person, color: KLPalette.primary),
      );

      if (url.isEmpty) return fallbackIcon();

      return CircleAvatar(
        radius: 24,
        backgroundColor: KLPalette.tint50,
        child: ClipOval(
          child: Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const Icon(Icons.person, color: KLPalette.primary),
          ),
        ),
      );
    }

    void openProfileTab() {
      nav.goProfile();
    }

    void openEditProfile() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      );
    }

    // Wrapper for tap + long press
    Widget wrap(Widget child) {
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: openProfileTab,
        onLongPress: openEditProfile,
        child: child,
      );
    }

    if (u.isEmpty) {
      return wrap(avatarCircle(photoUrl: null));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(u).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final photoUrl = (data['photoUrl'] ?? '').toString();

        return wrap(avatarCircle(photoUrl: photoUrl));
      },
    );
  }
}