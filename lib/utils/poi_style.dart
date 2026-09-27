import 'package:flutter/material.dart';

/// The category ids [PoiService] classifies results into, and how the
/// UI labels/icons them - kept in one place so the search sheet and any
/// future POI-related UI stay in sync.
const List<String> poiCategories = ['food', 'restroom', 'fuel', 'atm_bank', 'pharmacy'];

IconData iconForPoiCategory(String category) {
  switch (category) {
    case 'food':
      return Icons.restaurant;
    case 'restroom':
      return Icons.wc;
    case 'fuel':
      return Icons.local_gas_station;
    case 'atm_bank':
      return Icons.local_atm;
    case 'pharmacy':
      return Icons.local_pharmacy;
    default:
      return Icons.place;
  }
}

String labelForPoiCategory(String category) {
  switch (category) {
    case 'food':
      return 'Food';
    case 'restroom':
      return 'Restrooms';
    case 'fuel':
      return 'Fuel';
    case 'atm_bank':
      return 'ATM / Bank';
    case 'pharmacy':
      return 'Pharmacy';
    default:
      return 'Places';
  }
}
