class DetectionResult {
  final String label;
  final double confidence;

  /// Bounding box in normalized coordinates (0.0–1.0).
  final double left;
  final double top;
  final double width;
  final double height;

  /// Estimated distance in meters. Null when unavailable.
  final double? distanceMeters;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.distanceMeters,
  });

  /// Center X position (normalized 0–1). Backward-compatible accessor.
  double get x => left + width / 2;

  /// Center Y position (normalized 0–1). Backward-compatible accessor.
  double get y => top + height / 2;

  /// Human-readable distance string, empty when distance is unavailable.
  String get distanceLabel {
    if (distanceMeters == null) return '';
    final d = distanceMeters!;
    if (d < 0.5) return 'very close (~${d.toStringAsFixed(1)} m)';
    if (d < 1.5) return 'nearby (~${d.toStringAsFixed(1)} m)';
    if (d < 3.0) return '~${d.toStringAsFixed(1)} m away';
    return 'far (~${d.toStringAsFixed(1)} m)';
  }

  factory DetectionResult.fromMap(Map<String, dynamic> map) {
    final left = (map['left'] as num?)?.toDouble() ??
        (map['x'] as num?)?.toDouble() ??
        0.0;
    final top = (map['top'] as num?)?.toDouble() ??
        (map['y'] as num?)?.toDouble() ??
        0.0;
    return DetectionResult(
      label: map['label'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      left: left,
      top: top,
      width: (map['width'] as num?)?.toDouble() ?? 0.0,
      height: (map['height'] as num?)?.toDouble() ?? 0.0,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble(),
    );
  }
}
