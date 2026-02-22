import 'package:flutter/foundation.dart';

enum BookingStatus { upcoming, completed }

class BookingUi {
  final String id;
  final String title;
  final String locationText;
  final double rating;
  final double unitPrice;
  final double totalAmount;
  final DateTime scheduledAt;
  final BookingStatus status;
  final bool isReviewed;

  const BookingUi({
    required this.id,
    required this.title,
    required this.locationText,
    required this.rating,
    required this.unitPrice,
    required this.totalAmount,
    required this.scheduledAt,
    required this.status,
    this.isReviewed = false,
  });

  BookingUi copyWith({BookingStatus? status, bool? isReviewed}) {
    return BookingUi(
      id: id,
      title: title,
      locationText: locationText,
      rating: rating,
      unitPrice: unitPrice,
      totalAmount: totalAmount,
      scheduledAt: scheduledAt,
      status: status ?? this.status,
      isReviewed: isReviewed ?? this.isReviewed,
    );
  }
}

class BookingStore {
  final ValueNotifier<List<BookingUi>> items = ValueNotifier<List<BookingUi>>([]);

  void add(BookingUi b) {
    items.value = [b, ...items.value];
  }

  void markCompleted(String id) {
    items.value = items.value
        .map((b) => b.id == id ? b.copyWith(status: BookingStatus.completed) : b)
        .toList();
  }

  void remove(String id) {
    items.value = items.value.where((b) => b.id != id).toList();
  }

  void markReviewed(String id) {
    items.value = items.value
        .map((b) => b.id == id ? b.copyWith(isReviewed: true) : b)
        .toList();
  }

  void dispose() => items.dispose();
}