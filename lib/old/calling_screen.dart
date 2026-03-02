import 'package:flutter/material.dart';
import '../core/theme/theme.dart';

class CallingScreen extends StatefulWidget {
  final String name;
  final Color avatarColor;

  const CallingScreen({super.key, required this.name, required this.avatarColor});

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen> {
  bool micOn = true;
  bool speakerOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      appBar: AppBar(
        leading: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KLPalette.mutedBg,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        centerTitle: true,
        title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          const Spacer(),
          CircleAvatar(radius: 92, backgroundColor: widget.avatarColor),
          const SizedBox(height: 22),
          const Text("05:30 minutes", style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w900, fontSize: 28)),
          const Spacer(),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BigAction(
                  bg: const Color(0xFFEF4444),
                  icon: Icons.call_end_rounded,
                  fg: Colors.white,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 18),
                _BigAction(
                  bg: speakerOn ? KLPalette.primary : KLPalette.mutedBg,
                  icon: Icons.volume_up_rounded,
                  fg: speakerOn ? Colors.white : KLPalette.text,
                  onTap: () => setState(() => speakerOn = !speakerOn),
                ),
                const SizedBox(width: 18),
                _BigAction(
                  bg: micOn ? KLPalette.primary : KLPalette.mutedBg,
                  icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                  fg: micOn ? Colors.white : KLPalette.text,
                  onTap: () => setState(() => micOn = !micOn),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  final Color bg;
  final Color fg;
  final IconData icon;
  final VoidCallback onTap;

  const _BigAction({required this.bg, required this.fg, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 92,
        width: 92,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(blurRadius: 14, spreadRadius: 0, offset: Offset(0, 8), color: Color(0x22000000))],
        ),
        child: Icon(icon, color: fg, size: 34),
      ),
    );
  }
}