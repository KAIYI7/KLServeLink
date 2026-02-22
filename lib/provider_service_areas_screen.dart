import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

class ProviderServiceAreasScreen extends StatefulWidget {
  const ProviderServiceAreasScreen({super.key});

  @override
  State<ProviderServiceAreasScreen> createState() => _ProviderServiceAreasScreenState();
}

class _ProviderServiceAreasScreenState extends State<ProviderServiceAreasScreen> {
  final inputCtrl = TextEditingController();
  List<String> areas = [];
  bool loading = true;
  bool saving = false;

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
    final raw = doc.data()?['serviceAreas'];
    areas = (raw is List) ? raw.map((e) => e.toString()).toList() : [];
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    inputCtrl.dispose();
    super.dispose();
  }

  void _addArea() {
    final v = inputCtrl.text.trim();
    if (v.isEmpty) return;
    if (areas.any((a) => a.toLowerCase() == v.toLowerCase())) return;
    setState(() {
      areas.add(v);
      inputCtrl.clear();
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'serviceAreas': areas,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Service areas saved")));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save failed: $e")));
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
              _TopBar(title: "Service Areas", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 16),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Add area (e.g. Cheras, Bangsar)", style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: inputCtrl,
                                decoration: const InputDecoration(
                                  hintText: "Type area name",
                                  prefixIcon: Icon(Icons.map_outlined),
                                ),
                                onSubmitted: (_) => _addArea(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 56,
                              width: 56,
                              child: FilledButton(
                                onPressed: _addArea,
                                child: const Icon(Icons.add),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: areas.map((a) {
                            return Chip(
                              label: Text(a, style: const TextStyle(fontWeight: FontWeight.w900)),
                              deleteIcon: const Icon(Icons.close),
                              onDeleted: () => setState(() => areas.remove(a)),
                            );
                          }).toList(),
                        ),

                        const Spacer(),
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
              ),
            ],
          ),
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