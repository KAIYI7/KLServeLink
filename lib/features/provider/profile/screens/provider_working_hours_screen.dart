import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/utils/app_snack.dart';
import '../../../../core/theme/theme.dart';

class ProviderWorkingHoursScreen extends StatefulWidget {
  const ProviderWorkingHoursScreen({super.key});

  @override
  State<ProviderWorkingHoursScreen> createState() => _ProviderWorkingHoursScreenState();
}

class _ProviderWorkingHoursScreenState extends State<ProviderWorkingHoursScreen> {
  bool loading = true;
  bool saving = false;

  final days = const [
    ('mon', 'Mon'),
    ('tue', 'Tue'),
    ('wed', 'Wed'),
    ('thu', 'Thu'),
    ('fri', 'Fri'),
    ('sat', 'Sat'),
    ('sun', 'Sun'),
  ];

  late Map<String, _DayHours> model = {
    for (final d in days) d.$1: _DayHours(enabled: false, start: const TimeOfDay(hour: 9, minute: 0), end: const TimeOfDay(hour: 18, minute: 0)),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final wh = (doc.data()?['workingHours'] as Map?)?.cast<String, dynamic>();

    if (wh != null) {
      for (final key in wh.keys) {
        final v = (wh[key] as Map?)?.cast<String, dynamic>();
        if (v == null) continue;

        model[key] = _DayHours(
          enabled: (v['enabled'] ?? false) as bool,
          start: _parseTime(v['start']?.toString()) ?? const TimeOfDay(hour: 9, minute: 0),
          end: _parseTime(v['end']?.toString()) ?? const TimeOfDay(hour: 18, minute: 0),
        );
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'workingHours': {
          for (final d in days)
            d.$1: {
              'enabled': model[d.$1]!.enabled,
              'start': _fmtTime(model[d.$1]!.start),
              'end': _fmtTime(model[d.$1]!.end),
            }
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      AppSnack.show(context, "Working hours saved", type: AppSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, "Saved failed: $e", type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            children: [
              _TopBar(title: "Working Hours", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 16),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: days.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final key = days[i].$1;
                        final label = days[i].$2;
                        final day = model[key]!;

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: KLPalette.mutedBg,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                    const Spacer(),
                                    Switch(
                                      value: day.enabled,
                                      activeColor: KLPalette.primary,
                                      onChanged: (v) => setState(() => model[key] = day.copyWith(enabled: v)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimeButton(
                                        label: "Start",
                                        value: _fmtTime(day.start),
                                        enabled: day.enabled,
                                        onTap: () async {
                                          final picked = await showTimePicker(context: context, initialTime: day.start);
                                          if (picked == null) return;
                                          setState(() => model[key] = day.copyWith(start: picked));
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _TimeButton(
                                        label: "End",
                                        value: _fmtTime(day.end),
                                        enabled: day.enabled,
                                        onTap: () async {
                                          final picked = await showTimePicker(context: context, initialTime: day.end);
                                          if (picked == null) return;
                                          setState(() => model[key] = day.copyWith(end: picked));
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: saving
                      ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Save", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return "$hh:$mm";
  }

  static TimeOfDay? _parseTime(String? s) {
    if (s == null || !s.contains(':')) return null;
    final parts = s.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}

class _DayHours {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;

  const _DayHours({required this.enabled, required this.start, required this.end});

  _DayHours copyWith({bool? enabled, TimeOfDay? start, TimeOfDay? end}) {
    return _DayHours(
      enabled: enabled ?? this.enabled,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: enabled ? KLPalette.bg : KLPalette.tint50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: KLPalette.text2)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
            ),
            const Icon(Icons.access_time, color: KLPalette.text2),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

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
              color: KLPalette.mutedBg,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}