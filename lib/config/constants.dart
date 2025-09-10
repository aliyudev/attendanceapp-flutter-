/// Centralized face processing and verification thresholds.
/// Adjust values here to tune behavior across the app.
class FaceConstants {
  // Enrollment
  static const double enrollmentQualityMin = 0.25; // minimum per-frame quality to accept during enrollment

  // Verification
  static const double verificationQualityMin = 0.30; // minimum quality to proceed with verification
  static const double verificationSimilarityMin = 0.60; // cosine similarity match threshold

  // Liveness (simple movement-based)
  static const double livenessDxThreshold = 0.08; // required horizontal movement (normalized)
}
