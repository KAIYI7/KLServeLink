import 'package:flutter/material.dart';

enum ServiceCategory {
  cleaning,
  plumbing,
  aircon,
  handyman,
  tutoring,
}

class CategoryMeta {
  final ServiceCategory id;
  final String label;
  final IconData icon;

  const CategoryMeta(this.id, this.label, this.icon);
}

const List<CategoryMeta> kCategories = [
  CategoryMeta(ServiceCategory.cleaning, "Cleaning", Icons.cleaning_services_rounded),
  CategoryMeta(ServiceCategory.plumbing, "Plumbing", Icons.plumbing_rounded),
  CategoryMeta(ServiceCategory.aircon, "Air-Conditioning", Icons.ac_unit_rounded),
  CategoryMeta(ServiceCategory.handyman, "Handyman & Repair", Icons.handyman_rounded),
  CategoryMeta(ServiceCategory.tutoring, "Tutoring & Lessons", Icons.school_rounded),
];

extension ServiceCategoryKey on ServiceCategory {
  String get key {
    switch (this) {
      case ServiceCategory.cleaning:
        return "cleaning";
      case ServiceCategory.plumbing:
        return "plumbing";
      case ServiceCategory.aircon:
        return "aircon";
      case ServiceCategory.handyman:
        return "handyman";
      case ServiceCategory.tutoring:
        return "tutoring";
    }
  }
}

String labelForCategory(ServiceCategory c) {
  return kCategories.firstWhere((m) => m.id == c).label;
}