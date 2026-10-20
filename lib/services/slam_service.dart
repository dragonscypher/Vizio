import 'dart:async';

class SlamService {
  static final SlamService instance = SlamService._internal();
  SlamService._internal();

  StreamController<Map<String, dynamic>>? _poseController;
  StreamSubscription<int>? _poseSubscription;

  Stream<Map<String, dynamic>> get poseStream {
    _ensureController();
    return _poseController!.stream;
  }

  void _ensureController() {
    _poseController ??= StreamController<Map<String, dynamic>>.broadcast();
  }

  /// Initialize ARCore or fallback to a simple motion detector.
  Future<void> initialize() async {
    _ensureController();
    await _poseSubscription?.cancel();

    // This remains a simulated pose feed until a native SLAM/OpenXR source is
    // wired in, but it now restarts cleanly across screen rebuilds.
    _poseSubscription = Stream<int>.periodic(const Duration(seconds: 3), (tick) => tick).listen((tick) {
      _poseController?.add({
        'moved': true,
        'data': tick.isEven ? 'ar_pose' : 'fallback_pose',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> dispose() async {
    await _poseSubscription?.cancel();
    _poseSubscription = null;
  }
}
