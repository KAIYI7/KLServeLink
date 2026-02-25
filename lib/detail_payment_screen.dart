import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fyp_flutter/seeker_nav_controller.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'package:pdf/pdf.dart';
import 'theme.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DetailPaymentScreen extends StatelessWidget {
  final SeekerNavController nav;
  final String serviceTitle;
  final double rating;
  final String locationText;
  final String paymentMethod;

  final String? serviceImageUrl;

  /// For simulated payment flows.
  final String? paymentStatus;

  /// Raw payment map from booking doc
  final Map<String, dynamic>? paymentData;
  final DateTime date;
  final String startTime;
  final String transactionId;
  final double totalAmount;

  const DetailPaymentScreen({
    super.key,
    required this.nav,
    required this.serviceTitle,
    required this.rating,
    required this.locationText,
    required this.paymentMethod,
    this.serviceImageUrl,
    this.paymentStatus,
    this.paymentData,
    required this.date,
    required this.startTime,
    required this.transactionId,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final timeText =
        "${_monthName(date.month)} ${date.day}, ${date.year}, $startTime";

    final p = paymentData ?? const <String, dynamic>{};
    Map<String, dynamic> meta = const <String, dynamic>{};
    if (p["meta"] is Map) meta = Map<String, dynamic>.from(p["meta"] as Map);
    if (p["card"] is Map) meta = Map<String, dynamic>.from(p["card"] as Map);

    final brand = (meta["brand"] ?? meta["cardBrand"] ?? p["brand"] ?? p["cardBrand"])?.toString();
    final last4 = (meta["last4"] ?? meta["cardLast4"] ?? p["last4"] ?? p["cardLast4"])?.toString();

    final statusLabel = (paymentStatus == null || paymentStatus!.trim().isEmpty)
        ? null
        : paymentStatus!.trim();

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                KLPalette.tint50,
                KLPalette.bg,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        nav.goBookings();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
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
                    const Text(
                      "Detail Payment",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 28),

                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          decoration: BoxDecoration(
                            color: KLPalette.bg,
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
                            child: ListView(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        height: 88,
                                        width: 88,
                                        decoration: BoxDecoration(
                                          color: KLPalette.mutedBg,
                                          border: Border.all(color: KLPalette.border),
                                        ),
                                        child: _NetImage(
                                          url: serviceImageUrl,
                                          fit: BoxFit.cover,
                                          placeholderIcon: Icons.image,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  serviceTitle,
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                                                ),
                                              ),
                                              const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                                              const SizedBox(width: 4),
                                              Text(
                                                rating.toStringAsFixed(1),
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            "RM ${totalAmount.toStringAsFixed(2)}",
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.place, size: 18, color: KLPalette.text2),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  locationText,
                                                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 18),
                                const Divider(height: 1, color: KLPalette.border),
                                const SizedBox(height: 12),

                                _receiptRow(
                                  label: "Status",
                                  valueWidget: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: KLPalette.tint50,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: KLPalette.border),
                                    ),
                                    child: Text(
                                      (paymentStatus == null || paymentStatus!.trim().isEmpty)
                                          ? "Success"
                                          : paymentStatus!.trim(),
                                      style: const TextStyle(color: KLPalette.primary, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                InkWell(
                                  onTap: () => _showTransactionIdDialog(context),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: _receiptRow(
                                      label: "Transaction ID",
                                      valueWidget: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              transactionId,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          InkWell(
                                            onTap: () async {
                                              await Clipboard.setData(ClipboardData(text: transactionId));
                                              if (!context.mounted) return;
                                              AppSnack.show(context, "Copied", type: AppSnackType.success);
                                            },
                                            borderRadius: BorderRadius.circular(999),
                                            child: const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Icon(Icons.copy_rounded, color: KLPalette.text, size: 22),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                _receiptRow(
                                    label: "Service",
                                    value: serviceTitle),

                                const SizedBox(height: 10),

                                _receiptRow(
                                  label: "Payment Method",
                                  value: paymentMethod,
                                ),
                                const SizedBox(height: 10),

                                if (statusLabel != null) ...[
                                  _receiptRow(
                                    label: "Payment",
                                    value: statusLabel!,
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                if (brand != null || last4 != null) ...[
                                  _receiptRow(
                                    label: "Card",
                                    value: "${brand ?? 'Card'}${(last4 == null || last4!.isEmpty) ? '' : ' • **** $last4'}",
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                _receiptRow(
                                  label: "Scheduled",
                                  value: timeText,
                                ),

                                const SizedBox(height: 12),
                                const Divider(height: 1, color: KLPalette.border),
                                const SizedBox(height: 12),

                                _receiptRow(
                                  label: "Total Amount",
                                  value: "RM ${totalAmount.toStringAsFixed(2)}",
                                  big: true,
                                ),

                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -36,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            height: 72,
                            width: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: Center(
                              child: Container(
                                height: 58,
                                width: 58,
                                decoration: BoxDecoration(
                                  color: KLPalette.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KLPalette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () => _downloadReceiptPdf(context),
                    child: const Text(
                      "Download E-Receipt",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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

  Widget _receiptRow({
    required String label,
    String? value,
    Widget? valueWidget,
    bool big = false,
    Color? valueColor,
  }) {
    final labelStyle = const TextStyle(
      color: KLPalette.text2,
      fontWeight: FontWeight.w800,
      fontSize: 14,
    );

    final valueStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: big ? 26 : 16,
      color: valueColor ?? KLPalette.text,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: labelStyle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value ?? "",
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
    ];
    return names[(m - 1).clamp(0, 11)];
  }

  Future<void> _showTransactionIdDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              color: KLPalette.bg,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Transaction ID",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded, color: KLPalette.text2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: KLPalette.mutedBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Text(
                      transactionId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KLPalette.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: transactionId));
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        AppSnack.show(context, "Copied", type: AppSnackType.success);
                      },
                      child: const Text("Copy", style: TextStyle(fontWeight: FontWeight.w900)),
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

  Future<void> _downloadReceiptPdf(BuildContext context) async {
    try {
      // Load logo from assets
      final logoBytes = (await rootBundle.load('assets/images/logo.png'))
          .buffer
          .asUint8List();
      final logo = pw.MemoryImage(logoBytes);

      final doc = pw.Document();

      final issuedAt = DateTime.now();
      final issuedText =
          "${_monthName(issuedAt.month)} ${issuedAt.day}, ${issuedAt.year} - "
          "${issuedAt.hour.toString().padLeft(2, '0')}:${issuedAt.minute.toString().padLeft(2, '0')}";

      final scheduledText =
          "${_monthName(date.month)} ${date.day}, ${date.year} - $startTime";

      String prettyPayment(String raw) {
        final v = raw.trim().toLowerCase();
        return switch (v) {
          "card" => "Card",
          "cash" => "Cash",
          "fp" || "fpx" => "FPX",
          "ewallet" || "e-wallet" => "E-Wallet",
          _ => raw,
        };
      }

      String maskId(String id) {
        if (id.length <= 10) return id;
        return "${id.substring(0, 6)}…${id.substring(id.length - 4)}";
      }

      pw.Widget labelValue(String label, String value, {bool mono = false}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    color: PdfColor.fromInt(0xFF6B7280), // gray-ish
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 10.8,
                    fontWeight: pw.FontWeight.bold,
                    font: mono ? pw.Font.courier() : null,
                    color: PdfColor.fromInt(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      pw.Widget sectionTitle(String t) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
          child: pw.Text(
            t.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
              color: PdfColor.fromInt(0xFF374151),
            ),
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.fromLTRB(26, 28, 26, 26),
          build: (_) => [
            // Header
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 44,
                  height: 44,
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "KLServeLink",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF111827),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "E-Receipt",
                      style: pw.TextStyle(
                        fontSize: 11.5,
                        color: PdfColor.fromInt(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Issued",
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfColor.fromInt(0xFF6B7280),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      issuedText,
                      style: pw.TextStyle(
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColor.fromInt(0xFFE5E7EB), thickness: 1),

            // Receipt Meta
            sectionTitle("Receipt Details"),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF9FAFB),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB)),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                children: [
                  labelValue("Status", "Success"),
                  labelValue("Payment Method", prettyPayment(paymentMethod)),
                  labelValue("Transaction ID", transactionId, mono: true),
                ],
              ),
            ),

            // Service
            sectionTitle("Service"),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB)),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                children: [
                  labelValue("Service Name", serviceTitle),
                  labelValue("Scheduled", scheduledText),
                ],
              ),
            ),

            // Location
            sectionTitle("Location"),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB)),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Text(
                locationText,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  color: PdfColor.fromInt(0xFF111827),
                ),
              ),
            ),

            // Amount
            sectionTitle("Payment Summary"),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF9FAFB),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB)),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                children: [
                  labelValue("Total Paid", "RM ${totalAmount.toStringAsFixed(2)}"),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColor.fromInt(0xFFE5E7EB)),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          "Amount",
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF111827),
                          ),
                        ),
                      ),
                      pw.Text(
                        "RM ${totalAmount.toStringAsFixed(2)}",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Footer
            pw.SizedBox(height: 18),
            pw.Divider(color: PdfColor.fromInt(0xFFE5E7EB), thickness: 1),
            pw.SizedBox(height: 10),
            pw.Text(
              "Thank you for using KLServeLink.",
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF111827),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              "For support, please contact us in-app",
              style: pw.TextStyle(
                fontSize: 9.5,
                color: PdfColor.fromInt(0xFF6B7280),
              ),
            ),
          ],
        ),
      );

      // Save file
      final dir = await getApplicationDocumentsDirectory();
      final safeTx = transactionId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File("${dir.path}/KLServeLink_Receipt_$safeTx.pdf");
      final bytes = await doc.save();
      await file.writeAsBytes(bytes);

      if (!context.mounted) return;

      await Printing.sharePdf(
        bytes: bytes,
        filename: "KLServeLink_Receipt_$safeTx.pdf",
      );

      AppSnack.show(context, "Receipt ready", type: AppSnackType.success);
    } catch (e) {
      if (!context.mounted) return;
      AppSnack.show(context, "Failed to generate receipt: $e", type: AppSnackType.error);
    }
  }

}

class _NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData placeholderIcon;
  final bool big;

  const _NetImage({
    this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    Widget placeholder() => Container(
      color: KLPalette.mutedBg,
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        size: big ? 68 : 34,
        color: KLPalette.text2,
      ),
    );

    if (u.isEmpty) return placeholder();

    return Image.network(
      u,
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder(),
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (progress.expectedTotalBytes == null)
                    ? null
                    : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
              ),
            ),
          ],
        );
      },
    );
  }
}