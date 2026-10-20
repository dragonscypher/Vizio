/// Simple monocular distance estimator using the pinhole-camera model:
///
///   distance = (realHeight × focalLength) / pixelHeight
///
/// The focal-length constant is calibrated for a 300×300 px input image at a
/// ~60° horizontal field-of-view, which is a reasonable default for phone and
/// laptop webcams.  Results are labelled "estimated" in the UI because this
/// method is approximate — it does not use depth sensors or AR pose data.
class DistanceEstimator {
  DistanceEstimator._();

  /// Known real-world heights (meters) for objects the app cares about.
  static const Map<String, double> _knownHeights = {
    'person': 1.70,
    'bottle': 0.22, // soda can or small bottle
    'cup': 0.12,
    'car': 1.50,
    'chair': 0.90,
    'dog': 0.50,
    'cat': 0.30,
    'bicycle': 1.10,
    'bus': 3.00,
    'truck': 2.50,
  };

  /// Assumed focal length in pixels for a 300×300 input at ~60° FOV.
  static const double _focalLengthPx = 300.0;

  /// Estimate the distance to [label] given its bounding-box height as a
  /// fraction of the image (0–1) and the image [imageHeight] in pixels.
  ///
  /// Returns `null` when the object type is unknown or the box is too small.
  static double? estimate({
    required String label,
    required double bboxHeightNormalized,
    required int imageHeight,
  }) {
    final realHeight = _knownHeights[label.toLowerCase()];
    if (realHeight == null || bboxHeightNormalized <= 0.01) return null;

    final pixelHeight = bboxHeightNormalized * imageHeight;
    if (pixelHeight <= 0) return null;

    final distance = (realHeight * _focalLengthPx) / pixelHeight;
    return distance.clamp(0.1, 50.0);
  }
}
