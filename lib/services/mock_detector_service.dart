import '../models/detection_result.dart';
import 'detector_service.dart';

/// A detector that returns no detections.
///
/// Used on platforms where real inference is not yet available and in tests.
/// Unlike the old placeholder, this returns an empty list so the UI never
/// shows misleading hard-coded objects.
class MockDetectorService extends DetectorService {
  @override
  bool get isRealInference => false;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<List<DetectionResult>> detect(DetectionFrame frame) async => [];

  @override
  Future<void> dispose() async {}
}
