class OfficeConfig {
  // Set to null to disable proximity enforcement (will still record GPS)
  static const double? lat = null; // e.g., 6.5244;
  static const double? lng = null; // e.g., 3.3792;

  // Distance threshold in meters for valid clock-in
  static const double radiusMeters = 100.0;
}
