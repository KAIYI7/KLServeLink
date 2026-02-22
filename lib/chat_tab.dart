import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_repo.dart';
import 'theme.dart';
import 'seeker_nav_controller.dart';
import 'chat_models.dart';
import 'chat_detail_screen.dart';
import 'user_search_delegate.dart';

class ChatTab extends StatefulWidget {
  final SeekerNavController nav;
  const ChatTab({super.key, required this.nav});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

enum _InboxMode { chats }

class _ChatTabState extends State<ChatTab> {
  final _chatRepo = ChatRepo();
  _InboxMode mode = _InboxMode.chats;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
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
              _TopBar(
                onSearch: () => _openUserSearch(context),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: _ChatsListFirestore(
                  key: const ValueKey("chats"),
                  repo: _chatRepo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUserSearch(BuildContext context) {
    showSearch(context: context, delegate: UserSearchDelegate());
  }

}

class _ChatsListFirestore extends StatelessWidget {
  final ChatRepo repo;
  const _ChatsListFirestore({super.key, required this.repo});

  String _timeText(DateTime? dt) {
    if (dt == null) return "";
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return const Center(child: Text("Not signed in"));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: repo.watchThreads(myUid),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text("Failed to load chats."));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No chats yet."));
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final m = docs[i].data();

            final participants = (m['participants'] as List? ?? [])
                .map((e) => e.toString())
                .toList();

            final peerUid = participants.firstWhere(
                  (u) => u != myUid,
              orElse: () => "",
            );

            final lastMessage = (m['lastMessage'] ?? '').toString();
            final ts = m['updatedAt'];
            final updatedAt = (ts is Timestamp) ? ts.toDate() : null;

            final unreadCount = (m['unreadCount_$myUid'] is num)
                ? (m['unreadCount_$myUid'] as num).toInt()
                : 0;

            if (peerUid.isEmpty) {
              return const SizedBox.shrink();
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: repo.watchUser(peerUid),
              builder: (context, uSnap) {
                final u = uSnap.data?.data() ?? {};
                final peerName = (u['name'] ?? 'User').toString();

                final t = ChatThreadUi(
                  threadId: docs[i].id,
                  peerUid: peerUid,
                  peerName: peerName,
                  lastMessage: lastMessage,
                  updatedAt: updatedAt,
                  unreadCount: unreadCount,
                );

                return _ChatRowFirestore(
                  t: t,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatDetailScreen(peerUid: peerUid)),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ChatRowFirestore extends StatelessWidget {
  final ChatThreadUi t;
  final VoidCallback onTap;
  const _ChatRowFirestore({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeText = t.updatedAt == null
        ? ""
        : "${t.updatedAt!.hour.toString().padLeft(2,'0')}:${t.updatedAt!.minute.toString().padLeft(2,'0')}";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            children: [
              const CircleAvatar(radius: 26, backgroundColor: KLPalette.tint100),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.peerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      t.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(timeText, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (t.unreadCount > 0)
                    Container(
                      height: 26,
                      width: 26,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "${t.unreadCount}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSearch;

  const _TopBar({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: _CircleBrand(),
          ),

          const Center(
            child: Text(
              "Inbox",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CircleIcon(icon: Icons.search, onTap: onSearch, filled: true,),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _SegmentedInbox extends StatelessWidget {
  final _InboxMode value;
  final ValueChanged<_InboxMode> onChanged;

  const _SegmentedInbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _InboxMode v) {
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
            chip("Chats", _InboxMode.chats),
          ],
        ),
      ),
    );
  }
}

class _CallsList extends StatelessWidget {
  final List<CallLogUi> calls;
  final ValueChanged<CallLogUi> onTapCall;

  const _CallsList({super.key, required this.calls, required this.onTapCall});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: calls.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _CallRow(c: calls[i], onTapCall: () => onTapCall(calls[i])),
    );
  }
}

class _CallRow extends StatelessWidget {
  final CallLogUi c;
  final VoidCallback onTapCall;

  const _CallRow({required this.c, required this.onTapCall});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;

    switch (c.direction) {
      case CallDirection.incoming:
        icon = Icons.call_received_rounded;
        iconColor = const Color(0xFF16A34A);
        break;
      case CallDirection.outgoing:
        icon = Icons.call_made_rounded;
        iconColor = KLPalette.primary;
        break;
      case CallDirection.missed:
        icon = Icons.call_missed_outgoing_rounded;
        iconColor = const Color(0xFFEF4444);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KLPalette.bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: KLPalette.border),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: c.avatarColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(icon, size: 18, color: iconColor),
                    const SizedBox(width: 8),
                    Text(
                      c.dateText,
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onTapCall,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: KLPalette.tint200,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: const Icon(Icons.call_rounded, color: KLPalette.primary700),
            ),
          )
        ],
      ),
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
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _CircleIcon({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: filled ? KLPalette.primary : KLPalette.mutedBg,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, color: filled ? Colors.white : KLPalette.text),
      ),
    );
  }
}