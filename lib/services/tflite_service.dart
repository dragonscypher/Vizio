import 'package:flutter/foundation.dart';

import '../models/detection_result.dart';
import 'detector_service.dart';
import 'mock_detector_service.dart';
import 'tflite_detector_service.dart';

class TfliteService {
  static final TfliteService instance = TfliteService._internal();
  TfliteService._internal();

  DetectorService? _detector;
  bool _initialized = false;

  /// Whether the active detector is providing real model inference.
  bool get isRealInference => _detector?.isRealInference ?? false;

  Future<void> loadModel() async {
    if (_initialized) return;

    final DetectorService detector;
    if (kIsWeb) {
      detector = MockDetectorService();
    } else {
      detector = TfliteDetectorService();
    }

    final ok = await detector.initialize();
    if (!ok) {
      debugPrint('TfliteService: real inference unavailable, using mock');
      _detector = MockDetectorService();
      await _detector!.initialize();
    } else {
      debugPrint('TfliteService: real inference loaded successfully');
      _detector = detector;
    }

    _initialized = true;
  }

  /// Run detection on a camera frame.
  ///
  /// If no [frame] is provided (e.g. on platforms without frame capture yet)
  /// the result is an empty list rather than the old hard-coded placeholder.
  Future<List<DetectionResult>> runDetection({DetectionFrame? frame}) async {
    if (!_initialized) {
      await loadModel();
    }

    if (frame == null || _detector == null) {
      debugPrint(
          'TfliteService.runDetection: frame=${frame != null}, detector=${_detector != null}');
      return [];
    }

    final results = await _detector!.detect(frame);
    debugPrint(
        'TfliteService.runDetection: ${results.length} detections (real=$isRealInference)');
    return results;
  }
}
