import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'service_details_screen.dart';

class AllReviewsScreen extends StatelessWidget {
  final String serviceId;

  const AllReviewsScreen({
    super.key,
    required this.serviceId,
  });

  DocumentReference<Map<String, dynamic>> get _serviceRef =>
      FirebaseFirestore.instance.collection('services').doc(serviceId);

  CollectionReference<Map<String, dynamic>> get _reviewsRef =>
      _serviceRef.collection('reviews');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _serviceRef.snapshots(),
      builder: (context, serviceSnap) {
        if (!serviceSnap.hasData) {
          return const Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        final doc = serviceSnap.data!;
        if (!doc.exists) {
          return Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(title: "All Reviews", onBack: () => Navigator.pop(context), onShare: () {}),
                  const SizedBox(height: 18),
                  const Expanded(child: Center(child: Text("Service not found"))),
                ],
              ),
            ),
          );
        }

        final m = doc.data() ?? {};

        final ratingAvg = (m['ratingAvg'] is num) ? (m['ratingAvg'] as num).toDouble() : 0.0;
        final ratingCount = (m['ratingCount'] is num) ? (m['ratingCount'] as num).toInt() : 0;

        final starCounts = _readStarCounts(m['starCounts']);
        final distribution = _computeDistribution(starCounts, ratingCount);

        final totalText = "$ratingCount Reviews";

        return Scaffold(
          backgroundColor: KLPalette.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(
                children: [
                  _TopBar(
                    title: "All Reviews",
                    onBack: () => Navigator.pop(context),
                    onShare: () {},
                  ),
                  const SizedBox(height: 14),

                  _SummaryBlock(
                    rating: ratingAvg,
                    totalText: totalText,
                    distribution: distribution,
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _reviewsRef
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, reviewSnap) {
                        if (!reviewSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = reviewSnap.data!.docs;

                        if (docs.isEmpty) {
                          return ListView(
                            children: const [
                              SizedBox(height: 30),
                              Center(
                                child: Text(
                                  "No reviews yet",
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                ),
                              ),
                              SizedBox(height: 8),
                              Center(
                                child: Text(
                                  "Be the first to leave a review.",
                                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          );
                        }

                        final reviews = docs.map((d) => _reviewUiFromDoc(d)).toList();

                        return ListView.separated(
                          itemCount: reviews.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => ReviewCard(review: reviews[i]),
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

ReviewUiModel _reviewUiFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final m = doc.data() ?? {};
  final name = (m['seekerName'] ?? 'Seeker').toString();
  final text = (m['text'] ?? '').toString();
  final stars = (m['stars'] is num) ? (m['stars'] as num).toDouble() : 0.0;
  final verified = (m['verifiedJob'] ?? false) == true;

  DateTime? createdAt;
  final ts = m['createdAt'];
  if (ts is Timestamp) createdAt = ts.toDate();

  return ReviewUiModel(
    name: name,
    dateText: _formatDdMmYyyy(createdAt),
    rating: stars,
    text: text,
    verifiedJob: verified,
  );
}

String _formatDdMmYyyy(DateTime? dt) {
  if (dt == null) return "—";
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year.toString();
  return "$dd/$mm/$yyyy";
}

/// Reads {"1":int, "2":int, ...}
Map<int, int> _readStarCounts(dynamic raw) {
  final out = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  if (raw is Map) {
    final m = Map<String, dynamic>.from(raw);
    for (final k in ['1', '2', '3', '4', '5']) {
      final v = m[k];
      out[int.parse(k)] = (v is num) ? v.toInt() : 0;
    }
  }

  return out;
}

/// Returns [5★, 4★, 3★, 2★, 1★] as 0..1 fractions.
List<double> _computeDistribution(Map<int, int> starCounts, int total) {
  double frac(int n) => (total <= 0) ? 0.0 : (n / total).clamp(0.0, 1.0);

  return [
    frac(starCounts[5] ?? 0),
    frac(starCounts[4] ?? 0),
    frac(starCounts[3] ?? 0),
    frac(starCounts[2] ?? 0),
    frac(starCounts[1] ?? 0),
  ];
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        _CircleButton(icon: Icons.ios_share_rounded, onTap: onShare),
      ],
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

class _SummaryBlock extends StatelessWidget {
  final double rating;
  final String totalText;

  final List<double> distribution;

  const _SummaryBlock({
    required this.rating,
    required this.totalText,
    required this.distribution,
  });

  @override
  Widget build(BuildContext context) {
    final bars = distribution.length == 5
        ? distribution
        : const [0.0, 0.0, 0.0, 0.0, 0.0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                      (_) => const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                totalText,
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: List.generate(5, (i) {
              final star = 5 - i;
              final value = bars[i].clamp(0.0, 1.0);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text("$star", style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 10,
                          color: const Color(0xFFE5E7EB),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: value,
                              child: Container(color: KLPalette.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}