import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fyp_flutter/features/reviews/screens/all_reviews_screen.dart';
import 'package:fyp_flutter/features/seeker/bookings/screens/booking_detail_screen.dart';
import 'package:fyp_flutter/features/chat/screens/chat_detail_screen.dart';
import 'package:fyp_flutter/features/provider/bookings/screens/provider_booking_details_screen.dart';
import 'package:fyp_flutter/features/seeker/navigation/seeker_nav_controller.dart';
import 'package:fyp_flutter/core/utils/app_snack.dart';

import '../../../core/theme/theme.dart';
import '../data/notifications_repo.dart';

enum _NotifFilter { all, bookings, messages, reviews }

class NotificationsScreen extends StatefulWidget {
  final bool isProvider;
  final SeekerNavController? seekerNav;

  const NotificationsScreen({
    super.key,
    required this.isProvider,
    this.seekerNav,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = NotificationsRepo();
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  _NotifFilter _filter = _NotifFilter.all;

  Future<void> _confirmClearAll(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Clear all notifications?"),
        content: const Text("This will delete all notifications in your inbox."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.clearAll(uid);
      if (!mounted) return;
      AppSnack.show(context, "Cleared all notifications.", type: AppSnackType.success);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, "Failed to clear notifications.", type: AppSnackType.error);
    }
  }

  Future<void> _markAllRead(String uid) async {
    try {
      await _repo.markAllRead(uid);
      if (!mounted) return;
      AppSnack.show(context, "Marked all as read.", type: AppSnackType.success);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, "Failed to mark all as read.", type: AppSnackType.error);
    }
  }

  IconData _iconFor(AppNotification n) {
    final t = n.type.toLowerCase();
    if (t.contains("chat") || t.contains("message")) return Icons.chat_bubble_rounded;
    if (t.contains("booking")) return Icons.event_available_rounded;
    if (t.contains("review")) return Icons.star_rounded;
    return Icons.notifications_rounded;
  }

  String _timeLabel(DateTime? dt) {
    if (dt == null) return "";
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m";
    if (diff.inHours < 24) return "${diff.inHours}h";
    if (diff.inDays < 7) return "${diff.inDays}d";

    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  bool _isBooking(AppNotification n) => n.type.toLowerCase().contains("booking");
  bool _isMessage(AppNotification n) {
    final t = n.type.toLowerCase();
    return t.contains("chat") || t.contains("message");
  }

  bool _isReview(AppNotification n) => n.type.toLowerCase().contains("review");

  bool _passesFilter(AppNotification n) {
    switch (_filter) {
      case _NotifFilter.all:
        return true;
      case _NotifFilter.bookings:
        return _isBooking(n);
      case _NotifFilter.messages:
        return _isMessage(n);
      case _NotifFilter.reviews:
        return _isReview(n);
    }
  }

  // --------- Grouping (Today / Yesterday / Earlier) ---------

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _groupLabel(DateTime? createdAt) {
    if (createdAt == null) return "Earlier";
    final now = DateTime.now();
    final today = _dayOnly(now);
    final day = _dayOnly(createdAt);

    final diffDays = today.difference(day).inDays;
    if (diffDays <= 0) return "Today";
    if (diffDays == 1) return "Yesterday";
    return "Earlier";
  }

  List<_Section> _buildSections(List<AppNotification> items) {
    final m = <String, List<AppNotification>>{};
    for (final n in items) {
      final k = _groupLabel(n.createdAt);
      (m[k] ??= <AppNotification>[]).add(n);
    }

    int orderOf(String k) {
      switch (k) {
        case "Today":
          return 0;
        case "Yesterday":
          return 1;
        default:
          return 2;
      }
    }

    final keys = m.keys.toList()..sort((a, b) => orderOf(a).compareTo(orderOf(b)));
    return keys.map((k) => _Section(title: k, items: m[k] ?? const [])).toList();
  }

  // --------- Deep link routing ---------

  Future<void> _openNotification(String uid, AppNotification n) async {
    try {
      if (!n.read) {
        await _repo.markRead(uid: uid, notifId: n.id);
      }
    } catch (_) {}

    final data = n.data;

    // Chat
    final peerUid = (data["peerUid"] ?? data["fromUid"] ?? data["senderId"])?.toString();
    if (peerUid != null && peerUid.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailScreen(peerUid: peerUid)));
      return;
    }

    // Booking
    final bookingId = (data["bookingId"] ?? data["id"])?.toString();
    if (bookingId != null && bookingId.isNotEmpty) {
      if (!mounted) return;

      if (widget.isProvider) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderBookingDetailsScreen(bookingId: bookingId)));
        return;
      } else {
        final nav = widget.seekerNav;
        if (nav == null) {
          AppSnack.show(context, "Cannot open booking details (missing seeker navigator).", type: AppSnackType.error);
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: bookingId, nav: nav)));
        return;
      }
    }

    // Review
    final serviceId = (data["serviceId"])?.toString();
    if (serviceId != null && serviceId.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => AllReviewsScreen(serviceId: serviceId)));
      return;
    }

    if (!mounted) return;
    AppSnack.show(context, "No deep link for this notification.", type: AppSnackType.info);
  }

  // --------- UI components ---------

  Widget _summaryBar({
    required String uid,
    required int unread,
    required int total,
  }) {
    final hasAny = total > 0;
    final hasUnread = unread > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: KLPalette.mutedBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KLPalette.border.withOpacity(0.65)),
      ),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: KLPalette.bg,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.inbox_rounded, color: KLPalette.primary, size: 18),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("Inbox", style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    if (hasUnread)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: KLPalette.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "$unread unread",
                          style: const TextStyle(
                            color: KLPalette.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else if (hasAny)
                      const Text(
                        "All caught up",
                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hasAny ? "Swipe left to delete • Tap to open" : "No notifications yet",
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),

          if (hasUnread)
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: () => _markAllRead(uid),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text("Mark read", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),

          const SizedBox(width: 6),

          PopupMenuButton<String>(
            tooltip: "More",
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            icon: Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: KLPalette.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KLPalette.border),
              ),
              child: const Icon(Icons.more_horiz_rounded, color: KLPalette.text2, size: 20),
            ),
            onSelected: (v) async {
              switch (v) {
                case "read":
                  await _markAllRead(uid);
                  break;
                case "clear":
                  await _confirmClearAll(uid);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: "read",
                enabled: hasUnread,
                child: const Row(
                  children: [
                    Icon(Icons.done_all_rounded, size: 18),
                    SizedBox(width: 10),
                    Text("Mark all as read"),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "clear",
                enabled: hasAny,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    const SizedBox(width: 10),
                    const Text("Clear all", style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChips({
    required int allCount,
    required int bookingCount,
    required int messageCount,
    required int reviewCount,
  }) {
    Widget chip({
      required _NotifFilter value,
      required String label,
      required int count,
      required IconData icon,
    }) {
      final selected = _filter == value;

      return InkWell(
        onTap: () => setState(() => _filter = value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? KLPalette.primary.withOpacity(0.12) : KLPalette.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? KLPalette.primary : KLPalette.text2),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? KLPalette.primary : KLPalette.text,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? KLPalette.primary.withOpacity(0.16) : KLPalette.mutedBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KLPalette.border.withOpacity(0.8)),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: selected ? KLPalette.primary : KLPalette.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(value: _NotifFilter.all, label: "All", count: allCount, icon: Icons.inbox_rounded),
          const SizedBox(width: 10),
          chip(value: _NotifFilter.bookings, label: "Bookings", count: bookingCount, icon: Icons.event_available_rounded),
          const SizedBox(width: 10),
          chip(value: _NotifFilter.messages, label: "Messages", count: messageCount, icon: Icons.chat_bubble_rounded),
          const SizedBox(width: 10),
          chip(value: _NotifFilter.reviews, label: "Reviews", count: reviewCount, icon: Icons.star_rounded),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, thickness: 1, color: KLPalette.border.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _notifTile({
    required String uid,
    required AppNotification n,
  }) {
    final time = _timeLabel(n.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(n.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        ),
        onDismissed: (_) async {
          try {
            await _repo.deleteOne(uid: uid, notifId: n.id);
          } catch (_) {
            if (!mounted) return;
            AppSnack.show(context, "Failed to delete notification.", type: AppSnackType.error);
          }
        },
        child: _card(
          child: InkWell(
            onTap: () => _openNotification(uid, n),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: KLPalette.mutedBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Icon(_iconFor(n), color: KLPalette.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                            if (time.isNotEmpty)
                              Text(
                                time,
                                style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n.body,
                          style: const TextStyle(
                            color: KLPalette.text2,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (!n.read) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: KLPalette.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: const Text(
                              "Unread",
                              style: TextStyle(
                                color: KLPalette.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: KLPalette.mutedBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Icon(Icons.arrow_back, color: KLPalette.text),
                    ),
                  ),
                  const Spacer(),
                  const Text("Notifications", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),

              if (uid == null)
                _card(
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "You are not logged in.\nPlease sign in to view notifications.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                  ),
                )
              else
                Expanded(
                  child: StreamBuilder<List<AppNotification>>(
                    stream: _repo.notifications(uid, limit: 150),
                    builder: (context, snap) {
                      final items = snap.data ?? const <AppNotification>[];

                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // counts (for chips)
                      final bookingCount = items.where(_isBooking).length;
                      final messageCount = items.where(_isMessage).length;
                      final reviewCount = items.where(_isReview).length;

                      final filtered = items.where(_passesFilter).toList();
                      final unread = items.where((x) => !x.read).length;

                      final sections = _buildSections(filtered);

                      return Column(
                        children: [
                          _summaryBar(uid: uid, unread: unread, total: items.length),
                          const SizedBox(height: 12),

                          _filterChips(
                            allCount: items.length,
                            bookingCount: bookingCount,
                            messageCount: messageCount,
                            reviewCount: reviewCount,
                          ),

                          const SizedBox(height: 12),

                          if (filtered.isEmpty)
                            _card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: Text(
                                    items.isEmpty ? "No notifications yet." : "No notifications in this filter.",
                                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 120),
                                itemCount: sections.fold<int>(0, (sum, s) => sum + 1 + s.items.length),
                                itemBuilder: (context, index) {
                                  int cursor = 0;

                                  for (final s in sections) {
                                    // header
                                    if (index == cursor) return _sectionHeader(s.title);
                                    cursor += 1;

                                    // items
                                    final rel = index - cursor;
                                    if (rel >= 0 && rel < s.items.length) {
                                      final n = s.items[rel];
                                      return _notifTile(uid: uid, n: n);
                                    }
                                    cursor += s.items.length;
                                  }

                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                        ],
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

  static Widget _card({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: child,
      ),
    );
  }
}

class _Section {
  final String title;
  final List<AppNotification> items;
  const _Section({required this.title, required this.items});
}