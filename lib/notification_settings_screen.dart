import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _role;

  // Preferences are stored under users/{uid}.notificationPrefs
  bool bookingUpdates = true;
  bool newBookingRequests = true; // provider-oriented
  bool messages = true;
  bool promos = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data() ?? <String, dynamic>{};
    _role = (data['role'] ?? '').toString();
    final prefs = (data['notificationPrefs'] is Map)
        ? (data['notificationPrefs'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    bookingUpdates = (prefs['bookingUpdates'] ?? true) == true;
    newBookingRequests = (prefs['newBookingRequests'] ?? true) == true;
    messages = (prefs['messages'] ?? true) == true;
    promos = (prefs['promos'] ?? false) == true;

    setState(() => _loading = false);
  }

  Future<void> _setPref(String key, bool value) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'notificationPrefs': {
        key: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [KLPalette.tint50, KLPalette.bg],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              children: [
                _TopBar(title: "Notification", onBack: () => Navigator.pop(context)),
                const SizedBox(height: 18),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: KLPalette.bg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (uid == null)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Please sign in to manage notification settings.'),
                            )
                          else if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else ...[
                              const Text('Bookings', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 8),
                              if ((_role ?? '').toLowerCase() == 'provider')
                                _switch(
                                  'New booking requests',
                                  newBookingRequests,
                                      (v) {
                                    setState(() => newBookingRequests = v);
                                    _setPref('newBookingRequests', v);
                                  },
                                ),
                              _switch(
                                'Booking status updates',
                                bookingUpdates,
                                    (v) {
                                  setState(() => bookingUpdates = v);
                                  _setPref('bookingUpdates', v);
                                },
                              ),
                              const SizedBox(height: 18),
                              const Text('Messages', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 8),
                              _switch(
                                'Chat messages',
                                messages,
                                    (v) {
                                  setState(() => messages = v);
                                  _setPref('messages', v);
                                },
                              ),
                              const SizedBox(height: 18),
                              const Text('Other', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 8),
                              _switch(
                                'Promotions & announcements',
                                promos,
                                    (v) {
                                  setState(() => promos = v);
                                  _setPref('promos', v);
                                },
                              ),
                            ],
                        ],
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

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          Switch(
            value: value,
            activeColor: KLPalette.primary,
            onChanged: onChanged,
          ),
        ],
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
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}