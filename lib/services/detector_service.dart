import 'dart:typed_data';

import '../models/detection_result.dart';

/// Raw frame data passed to a detector for inference.
class DetectionFrame {
  final Uint8List bytes;
  final int width;
  final int height;

  /// Bytes per pixel: 3 for RGB, 4 for RGBA.
  final int bytesPerPixel;

  const DetectionFrame({
    required this.bytes,
    required this.width,
    required this.height,
    this.bytesPerPixel = 3,
  });
}

/// Platform-agnostic object-detection interface.
///
/// Concrete implementations wrap a real inference engine (e.g. TFLite) or
/// return empty results as a clearly labelled mock when inference is not
/// available on the current platform.
abstract class DetectorService {
  /// Load the model and allocate resources.  Returns `true` on success.
  Future<bool> initialize();

  /// Run detection on [frame].
  Future<List<DetectionResult>> detect(DetectionFrame frame);

  /// Whether this implementation provides real inference.
  bool get isRealInference;

  /// Release any native resources.
  Future<void> dispose();
}
