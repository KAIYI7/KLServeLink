import 'package:flutter/material.dart';
import 'package:fyp_flutter/utils/service_thumb.dart';
import 'seeker_nav_controller.dart';
import 'booking_detail_screen.dart';
import 'theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'seeker_booking_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BookingsTab extends StatefulWidget {
  final SeekerNavController nav;
  const BookingsTab({super.key, required this.nav});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  BookingsFilter filter = BookingsFilter.all;
  bool showSearch = false;
  final searchCtrl = TextEditingController();
  String _q = "";

  @override
  void dispose() {
    widget.nav.bookingsIntent.removeListener(_onBookingsIntent);
    searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      showSearch = !showSearch;
      if (!showSearch) {
        searchCtrl.clear();
        _q = "";
      }
    });
  }

  void _showSortInfo(BuildContext context) {
    String title;
    List<String> lines;

    switch (filter) {
      case BookingsFilter.upcoming:
        title = "Sorting (Upcoming)";
        lines = [
          "Sorted by scheduled time (soonest first).",
        ];
        break;
      case BookingsFilter.completed:
        title = "Sorting (Completed)";
        lines = [
          "Sorted by scheduled time (newest first).",
        ];
        break;
      case BookingsFilter.all:
      default:
        title = "Sorting (All)";
        lines = [
          "Grouped by status:",
          "• Upcoming first (soonest first)",
          "• Completed next (newest first)",
          "• Cancelled/Declined last (newest first)",
        ];
        break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KLPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.sort, color: KLPalette.text2),
                  const SizedBox(width: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              for (final t in lines) ...[
                Text(
                  t,
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<BookingUi> _applySearch(List<BookingUi> items) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return items;

    bool match(BookingUi b) {
      final id = (b.id).toLowerCase();
      final title = (b.title).toLowerCase();
      final area = (b.locationArea).toLowerCase();

      final loc = (b.locationText).toLowerCase();

      return id.contains(q) || title.contains(q) || area.contains(q);
    }

    return items.where(match).toList();
  }
  @override
  void initState() {
    super.initState();
    widget.nav.bookingsIntent.addListener(_onBookingsIntent);
  }

  void _onBookingsIntent() {
    final intent = widget.nav.bookingsIntent.value;
    if (intent == null) return;

    setState(() => filter = intent);

    // clear intent so it doesn't re-apply on rebuild
    widget.nav.bookingsIntent.value = null;
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
                  _CircleBrand(),
                  const Spacer(),
                  const Text("Bookings", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  Row(
                    children: [
                      _CircleButton(
                        icon: showSearch ? Icons.close_rounded : Icons.search,
                        onTap: _toggleSearch,
                      ),
                      const SizedBox(width: 10),
                      _CircleButton(
                        icon: Icons.info_outline_rounded,
                        onTap: () => _showSortInfo(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _Segmented(
                value: filter,
                onChanged: (v) => setState(() => filter = v),
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  filter == BookingsFilter.upcoming
                      ? "Sorted: soonest booking first"
                      : filter == BookingsFilter.completed
                      ? "Sorted: newest booking first"
                      : "Sorted: Upcoming → Completed → Cancelled",
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                ),
              ),

              if (showSearch) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  onChanged: (v) => setState(() => _q = v),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Search by service / booking ID / location",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: KLPalette.mutedBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: KLPalette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: KLPalette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: KLPalette.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
                const SizedBox(height: 14),
              ],

              Expanded(
                child: Builder(
                  builder: (context) {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) {
                      return const Center(child: Text("Please login"));
                    }

                    final fs = SeekerBookingFirestore();

                    if (filter == BookingsFilter.all) {
                      return _AllBookingsList(
                        nav: widget.nav,
                        seekerId: uid,
                        fs: fs,
                        query: _q,
                      );
                    }

                    final effectiveTab = (filter == BookingsFilter.completed)
                        ? SeekerBookingTab.completed
                        : SeekerBookingTab.upcoming;

                    return StreamBuilder<List<BookingUi>>(
                      stream: fs.streamMyBookings(seekerId: uid, tab: effectiveTab),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                        final raw = snap.data ?? const [];
                        final items = _applySearch(raw).toList();

                        // Sort depending on filter
                        if (filter == BookingsFilter.upcoming) {
                          items.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)); // soonest first
                        } else if (filter == BookingsFilter.completed) {
                          items.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)); // newest first
                        }

                        if (_q.trim().isNotEmpty && items.isEmpty) {
                          return const Center(
                            child: Text(
                              "No results found.",
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                            ),
                          );
                        }

                        if (filter == BookingsFilter.upcoming && items.isEmpty) {
                          return _EmptyState(
                            title: "No upcoming bookings",
                            subtitle:
                            "You don’t have an upcoming booking yet.\nMake a new booking by clicking the button below.",
                            icon: Icons.event_busy_rounded,
                            buttonText: "New Booking",
                            onTap: () => widget.nav.goSearch(),
                          );
                        }

                        if (filter == BookingsFilter.completed && items.isEmpty) {
                          return _EmptyState(
                            title: "No completed bookings yet",
                            subtitle: "When you finish a service, it will appear here.",
                            icon: Icons.check_circle_outline_rounded,
                            buttonText: "Browse services",
                            onTap: () => widget.nav.goSearch(),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: 120),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) => _BookingCard(b: items[i], nav: widget.nav),
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
  }

  List<BookingUi> _applyFilter(List<BookingUi> all, BookingsFilter f) {
    switch (f) {
      case BookingsFilter.upcoming:
        return all.where((b) => b.status == BookingStatus.upcoming).toList();
      case BookingsFilter.completed:
        return all.where((b) => b.status == BookingStatus.completed).toList();
      case BookingsFilter.all:
      default:
        return all;
    }
  }
}

class _Segmented extends StatelessWidget {
  final BookingsFilter value;
  final ValueChanged<BookingsFilter> onChanged;

  const _Segmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, BookingsFilter v) {
      final selected = v == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? KLPalette.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : KLPalette.text,
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            chip("All", BookingsFilter.all),
            chip("Upcoming", BookingsFilter.upcoming),
            chip("Completed", BookingsFilter.completed),
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingUi b;
  final SeekerNavController nav;
  const _BookingCard({required this.b, required this.nav,});

  @override
  Widget build(BuildContext context) {
    final s = b.status;
    final isUpcoming = s == BookingStatus.upcoming;
    final isCompleted = s == BookingStatus.completed;
    final isCancelled = s == BookingStatus.cancelled;

    final pillBg = isUpcoming
        ? const Color(0xFFFDECC8)
        : isCompleted
        ? const Color(0xFFDFF7EA)
        : const Color(0xFFFEE2E2);

    final pillFg = isUpcoming
        ? const Color(0xFF9A6B1B)
        : isCompleted
        ? const Color(0xFF1B7B45)
        : const Color(0xFFB91C1C);

    final pillText = isUpcoming
        ? "Upcoming"
        : isCompleted
        ? "Completed"
        : "Cancelled";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(
                bookingId: b.id,
                nav: nav,
              ),
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
            child: Stack(
              children: [
                // Main row content
                Padding(
                  // extra right padding so text doesn't collide with the bottom-right action
                  padding: const EdgeInsets.fromLTRB(14, 14, 86, 14),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Image fills left side (top-left, full height)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            width: 104,
                            color: KLPalette.mutedBg,
                            child: ServiceThumb(
                              model: b,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Text content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                b.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "RM ${b.totalAmount.toStringAsFixed(2)}",
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 6),
                                  Text(
                                    b.serviceRating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.place, size: 18, color: KLPalette.text2),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      b.locationArea,
                                      style: const TextStyle(
                                        color: KLPalette.text2,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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

                // Status pill: pinned top-right (non-interactive)
                Positioned(
                  top: 10,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isUpcoming ? const Color(0xFFFDECC8) : const Color(0xFFDFF7EA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: pillFg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final String buttonText;
  final IconData icon;

  const _EmptyState({
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 22),
        Center(
          child: Container(
            height: 260,
            width: 300,
            decoration: BoxDecoration(
              color: KLPalette.tint50,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: KLPalette.border),
            ),
            child: Center(
              child: Icon(icon, size: 120, color: KLPalette.text2),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 10),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KLPalette.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: onTap,
            child: Text(buttonText,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 120),
      ],
    );
  }
}

class _CircleBrand extends StatelessWidget {
  const _CircleBrand({super.key});

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

class _AllBookingsList extends StatelessWidget {
  final SeekerNavController nav;
  final String seekerId;
  final SeekerBookingFirestore fs;
  final String query;

  const _AllBookingsList({
    required this.nav,
    required this.seekerId,
    required this.fs,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingUi>>(
      stream: fs.streamMyBookings(seekerId: seekerId, tab: SeekerBookingTab.upcoming),
      builder: (context, upSnap) {
        return StreamBuilder<List<BookingUi>>(
          stream: fs.streamMyBookings(seekerId: seekerId, tab: SeekerBookingTab.completed),
          builder: (context, coSnap) {
            return StreamBuilder<List<BookingUi>>(
              stream: fs.streamMyBookings(seekerId: seekerId, tab: SeekerBookingTab.cancelled),
              builder: (context, caSnap) {
                if (!upSnap.hasData || !coSnap.hasData || !caSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final upcoming = upSnap.data ?? const [];
                final completed = coSnap.data ?? const [];
                final cancelled = caSnap.data ?? const [];

                // merge + dedupe by id
                final map = <String, BookingUi>{};
                for (final b in upcoming) map[b.id] = b;
                for (final b in completed) map[b.id] = b;
                for (final b in cancelled) map[b.id] = b;

                final allItems = map.values.toList();

                int groupRank(BookingUi b) {
                  switch (b.status) {
                    case BookingStatus.upcoming:
                      return 0;
                    case BookingStatus.completed:
                      return 1;
                    case BookingStatus.cancelled:
                      return 2;
                  }
                }

                int compare(BookingUi a, BookingUi b) {
                  final ga = groupRank(a);
                  final gb = groupRank(b);
                  if (ga != gb) return ga.compareTo(gb);

                  // Within same group:
                  if (ga == 0) {
                    // upcoming: soonest first
                    return a.scheduledAt.compareTo(b.scheduledAt);
                  } else {
                    // completed/cancelled: newest first
                    return b.scheduledAt.compareTo(a.scheduledAt);
                  }
                }

                final q = query.trim().toLowerCase();
                final filtered = (q.isEmpty)
                    ? allItems
                    : allItems.where((b) {
                  final id = b.id.toLowerCase();
                  final title = b.title.toLowerCase();
                  final area = b.locationArea.toLowerCase();
                  return id.contains(q) || title.contains(q) || area.contains(q);
                }).toList();

                // Apply the grouped sorting after filtering
                filtered.sort(compare);

                if (q.isNotEmpty && filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      "No results found.",
                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                    ),
                  );
                }

                if (allItems.isEmpty) {
                  return _EmptyState(
                    title: "You don’t have a booking yet",
                    subtitle: "Make a new booking by clicking the button below.",
                    icon: Icons.markunread_mailbox_rounded,
                    buttonText: "New Booking",
                    onTap: () => nav.goSearch(),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _BookingCard(b: filtered[i], nav: nav),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BookingServiceThumb extends StatelessWidget {
  final BookingUi b;
  const _BookingServiceThumb({required this.b});

  @override
  Widget build(BuildContext context) {
    // Prefer an image URL already present on BookingUi
    final direct = _tryGetBookingImageUrl(b);
    if (direct != null) {
      return _NetImage(url: direct, fit: BoxFit.cover, placeholderIcon: Icons.image);
    }

    // Else fallback: fetch service doc by serviceId (if BookingUi has it)
    final serviceId = _tryGetServiceId(b);
    if (serviceId == null) {
      return _NetImage(url: null, fit: BoxFit.cover, placeholderIcon: Icons.image);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('services').doc(serviceId).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        final url = (m == null) ? null : _coverUrlFromServiceDoc(m);
        return _NetImage(url: url, fit: BoxFit.cover, placeholderIcon: Icons.image);
      },
    );
  }

  String? _tryGetServiceId(BookingUi b) {
    final d = b as dynamic;
    try {
      final v = d.serviceId;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final v = d.listingId;
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  String? _tryGetBookingImageUrl(BookingUi b) {
    final d = b as dynamic;

    String? pick(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    try { final r = pick(d.thumbnailUrl);         if (r != null) return r; } catch (_) {}
    try { final r = pick(d.serviceThumbnailUrl);  if (r != null) return r; } catch (_) {}
    try { final r = pick(d.coverUrl);             if (r != null) return r; } catch (_) {}
    try { final r = pick(d.imageUrl);             if (r != null) return r; } catch (_) {}

    return null;
  }

  String? _coverUrlFromServiceDoc(Map<String, dynamic> m) {
    String? pickString(dynamic v) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

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

    final photos = m['photos'];
    if (photos is List && photos.isNotEmpty && photos.first is String) {
      final v = (photos.first as String).trim();
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

  const _NetImage({
    this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    Widget placeholder() => SizedBox.expand(
      child: Container(
        color: KLPalette.mutedBg,
        alignment: Alignment.center,
        child: Icon(placeholderIcon, size: 42, color: KLPalette.text2),
      ),
    );

    if (u.isEmpty) return placeholder();

    return SizedBox.expand(
      child: Image.network(
        u,
        fit: fit,
        alignment: Alignment.center,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;

          final value = (progress.expectedTotalBytes == null)
              ? null
              : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1);

          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder(),
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(minHeight: 3, value: value),
              ),
            ],
          );
        },
      ),
    );
  }
}
