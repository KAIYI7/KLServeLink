import '../../features/provider/services/data/provider_services_repo.dart';

class ServicePricingVM {
  final double basePrice;        // service.price
  final double discountPct;      // service.discount (0..100)
  final double finalPackage;     // basePrice after discount
  final double savedAmount;      // basePrice - finalPackage
  final double durationHours;    // durationHours + durationMins/60
  final int durationH;
  final int durationM;
  final double hourlyRate;       // prefer service.hourlyRate, else computed

  const ServicePricingVM({
    required this.basePrice,
    required this.discountPct,
    required this.finalPackage,
    required this.savedAmount,
    required this.durationHours,
    required this.durationH,
    required this.durationM,
    required this.hourlyRate,
  });

  factory ServicePricingVM.fromService(ProviderServiceUi s) {
    final base = (s.price.isFinite && s.price > 0) ? s.price : 0.0;

    final discRaw = (s.discount.isFinite) ? s.discount : 0.0;
    final disc = discRaw.clamp(0.0, 100.0).toDouble();

    final finalPkg = base * (1.0 - disc / 100.0);
    final saved = (base - finalPkg).clamp(0.0, double.infinity).toDouble();

    final h = s.durationHours;
    final m = s.durationMins;
    final durHr = (h.clamp(0, 999)) + (m.clamp(0, 59) / 60.0);

    final hr = (s.hourlyRate.isFinite && s.hourlyRate > 0)
        ? s.hourlyRate
        : (durHr > 0 ? (finalPkg / durHr) : 0.0);

    return ServicePricingVM(
      basePrice: base,
      discountPct: disc,
      finalPackage: finalPkg,
      savedAmount: saved,
      durationHours: durHr,
      durationH: h,
      durationM: m,
      hourlyRate: hr,
    );
  }

  factory ServicePricingVM.fromSeekerService(dynamic s) {
    // Base price
    final base =
    (s.price is num && s.price.isFinite && s.price > 0)
        ? s.price.toDouble()
        : 0.0;

    // Discount
    final discRaw =
    (s.discount is num && s.discount.isFinite)
        ? s.discount.toDouble()
        : 0.0;
    final disc = discRaw.clamp(0.0, 100.0);

    // Final price
    final finalPkg = (base * (1.0 - disc / 100.0))
        .clamp(0.0, double.infinity);

    final saved = (base - finalPkg)
        .clamp(0.0, double.infinity);

    // Duration
    final int h =
    (s.durationHours is num) ? (s.durationHours as num).toInt() : 0;
    final int m =
    (s.durationMins is num) ? (s.durationMins as num).toInt() : 0;

    final durHr = h + (m.clamp(0, 59) / 60.0);

    // Hourly rate
    final hr =
    (s.hourlyRate is num && s.hourlyRate.isFinite && s.hourlyRate > 0)
        ? s.hourlyRate.toDouble()
        : (durHr > 0 ? (finalPkg / durHr) : 0.0);

    return ServicePricingVM(
      basePrice: base,
      discountPct: disc,
      finalPackage: finalPkg,
      savedAmount: saved,
      durationHours: durHr,
      durationH: h,
      durationM: m,
      hourlyRate: hr,
    );
  }

  static String rm(num v, {int decimals = 2}) {
    final n = v.isFinite ? v.toDouble() : 0.0;
    return "RM${n.toStringAsFixed(decimals)}";
  }

  String get durationLabel {
    if (durationH <= 0 && durationM <= 0) return "-";
    if (durationH > 0 && durationM > 0) return "${durationH}h ${durationM}m";
    if (durationH > 0) return "${durationH}h";
    return "${durationM}m";
  }

  factory ServicePricingVM.fromBookedService(dynamic s) {
    final base = (s.basePrice.isFinite && s.basePrice > 0) ? s.basePrice : 0.0;
    final disc = (s.discountPct.isFinite ? s.discountPct : 0.0).clamp(0.0, 100.0);
    final finalPkg = (s.floorPrice.isFinite && s.floorPrice > 0)
        ? s.floorPrice
        : (base * (1.0 - disc / 100.0));
    final saved = (base - finalPkg).clamp(0.0, double.infinity);
    final durHr = (s.durationH.clamp(0, 999)) + (s.durationM.clamp(0, 59) / 60.0);
    final hr = (s.hourlyRate.isFinite && s.hourlyRate > 0) ? s.hourlyRate : (durHr > 0 ? (finalPkg / durHr) : 0.0);

    return ServicePricingVM(
      basePrice: base,
      discountPct: disc,
      finalPackage: finalPkg,
      savedAmount: saved,
      durationHours: durHr,
      durationH: s.durationH,
      durationM: s.durationM,
      hourlyRate: hr,
    );
  }
}