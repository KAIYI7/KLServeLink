import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/chat_detail_screen.dart';
import '../../../core/theme/theme.dart';

class UserSearchDelegate extends SearchDelegate<void> {
  UserSearchDelegate();

  @override
  String get searchFieldLabel => "Search users...";

  @override
  TextStyle? get searchFieldStyle => const TextStyle(fontWeight: FontWeight.w800);

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: KLPalette.bg,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: KLPalette.bg),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
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
          borderSide: BorderSide(color: KLPalette.primary),
        ),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () => query = "",
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: () => close(context, null),
  );

  Query<Map<String, dynamic>> _queryUsers(String q) {
    final col = FirebaseFirestore.instance.collection('users');
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      return col.limit(25);
    }

    return col
        .orderBy('name')
        .startAt([trimmed])
        .endAt(['$trimmed\uf8ff'])
        .limit(25);
  }

  Widget _buildList(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _queryUsers(query).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Search failed.",
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs
            .where((d) => d.id != myUid)
            .toList();

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              "No users found.",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['name'] ?? 'User').toString();
            final photoUrl = (m['photoUrl'] ?? '').toString().trim();

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  close(context, null);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatDetailScreen(peerUid: d.id)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: KLPalette.bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: KLPalette.border),
                  ),
                  child: Row(
                    children: [
                      _UserAvatar(url: photoUrl.isEmpty ? null : photoUrl, radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: KLPalette.text2),
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

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  @override
  Widget buildResults(BuildContext context) => _buildList(context);
}

class _UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;

  const _UserAvatar({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    return Container(
      height: radius * 2,
      width: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: KLPalette.tint100,
      ),
      child: (u.isNotEmpty)
          ? ClipOval(
        child: Image.network(
          u,
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.person, color: KLPalette.text2),
        ),
      )
          : const Icon(Icons.person, color: KLPalette.text2),
    );
  }
}