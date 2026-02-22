import 'package:flutter/foundation.dart';

enum BookingStatus { upcoming, completed }

class BookingUi {
  final String id;
  final String title;
  final String location;
  final double rating;
  final double price;
  final BookingStatus status;

  final DateTime scheduledAt;

  const BookingUi({
    required this.id,
    required this.title,
    required this.location,
    required this.rating,
    required this.price,
    required this.status,
    required this.scheduledAt,
  });
}

class BookingsController {
  final ValueNotifier<List<BookingUi>> items = ValueNotifier<List<BookingUi>>(_demo());

  void addUpcoming(BookingUi booking) {
    // Insert newest at top
    items.value = [booking, ...items.value];
  }

  void dispose() {
    items.dispose();
  }

  static List<BookingUi> _demo() {
    final now = DateTime.now();
    return [
      BookingUi(
        id: "b1",
        title: "Washing Clothes",
        location: "New York, US",
        rating: 5.0,
        price: 23,
        status: BookingStatus.upcoming,
        scheduledAt: now.add(const Duration(days: 2)),
      ),
      BookingUi(
        id: "b2",
        title: "Bathroom Service",
        location: "New York, US",
        rating: 5.0,
        price: 23,
        status: BookingStatus.upcoming,
        scheduledAt: now.add(const Duration(days: 4)),
      ),
      BookingUi(
        id: "b3",
        title: "Washing Clothes",
        location: "New York, US",
        rating: 5.0,
        price: 23,
        status: BookingStatus.completed,
        scheduledAt: now.subtract(const Duration(days: 7)),
      ),
      BookingUi(
        id: "b4",
        title: "House Clothing",
        location: "New York, US",
        rating: 5.0,
        price: 23,
        status: BookingStatus.completed,
        scheduledAt: now.subtract(const Duration(days: 20)),
      ),
    ];
  }
}