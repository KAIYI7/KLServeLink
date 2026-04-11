import 'package:flutter/material.dart';
import '../../../core/models/service_category.dart';

enum BookingsFilter { all, upcoming, completed }

class SeekerNavController {
  /// Controls which tab is selected (0..4)
  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  /// Sends an intent to Search tab
  final ValueNotifier<SearchIntent?> searchIntent = ValueNotifier<SearchIntent?>(null);

  /// Sends an intent to Bookings tab (which segment to show)
  final ValueNotifier<BookingsFilter?> bookingsIntent = ValueNotifier<BookingsFilter?>(null);

  /// Tells Chat tab to open a specific thread (provider uid)
  final ValueNotifier<String?> openChatWith = ValueNotifier<String?>(null);

  void goHome() => tabIndex.value = 0;

  void goSearch([SearchIntent? intent]) {
    if (intent != null) searchIntent.value = intent;
    tabIndex.value = 1; // Search tab
  }

  void goBookings([BookingsFilter? filter]) {
    if (filter != null) bookingsIntent.value = filter;
    tabIndex.value = 2;
  }

  void goChat() => tabIndex.value = 3;

  void goChatWith(String uid) {
    tabIndex.value = 3;
    openChatWith.value = null;
    openChatWith.value = uid;
  }

  void goProfile() => tabIndex.value = 4;

  void dispose() {
    tabIndex.dispose();
    searchIntent.dispose();
    bookingsIntent.dispose();
    openChatWith.dispose();
  }
}

class SearchIntent {
  final ServiceCategory? category;
  final String? query;

  const SearchIntent({this.category, this.query});

  // named constructors
  const SearchIntent.byCategory(ServiceCategory c) : category = c, query = null;
  const SearchIntent.byQuery(String q) : category = null, query = q;
}