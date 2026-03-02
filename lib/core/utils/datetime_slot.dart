DateTime combineDateAndSlot(DateTime date, String slot) {
  // "09.00 AM" -> "09:00 AM"
  final s = slot.trim().toUpperCase().replaceAll(".", ":");

  final parts = s.split(RegExp(r"\s+"));
  final hm = parts[0].split(":");

  int hour = int.tryParse(hm[0]) ?? 0;
  final minute = int.tryParse(hm.length > 1 ? hm[1] : "0") ?? 0;
  final ampm = parts.length > 1 ? parts[1] : "AM";

  if (ampm == "PM" && hour < 12) hour += 12;
  if (ampm == "AM" && hour == 12) hour = 0;

  return DateTime(date.year, date.month, date.day, hour, minute);
}
