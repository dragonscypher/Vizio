import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/detection_result.dart';
import '../services/detector_service.dart';
import '../services/lm_service.dart';
import '../services/stt_service.dart';
import '../services/tflite_service.dart';
import '../services/tts_service.dart';
import '../services/vr_service.dart';
import '../utils/coco_labels.dart';
import '../utils/settings_helper.dart';
import '../widgets/custom_widgets.dart';
import '../widgets/windows_camera_surface.dart';

// ---------------------------------------------------------------------------
// The two accessibility modes the app supports.
// ---------------------------------------------------------------------------
enum AccessibilityMode { deaf, blind }

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.forceSimulation = false,
    this.disableAutomation = false,
    this.platformOverride,
  });

  final bool forceSimulation;
  final bool disableAutomation;
  final TargetPlatform? platformOverride;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // ── camera ──────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  final WindowsCameraController _windowsCameraController =
      WindowsCameraController();
  bool _cameraReady = false;
  String _cameraStatus = 'Starting camera…';

  // ── mode toggle ─────────────────────────────────────────────────────────
  AccessibilityMode _mode = AccessibilityMode.blind;

  // ── blind mode state ────────────────────────────────────────────────────
  List<DetectionResult> _detections = [];
  bool _isDetecting = false;
  Timer? _detectionTimer;
  Timer? _gazeTimer;
  String _sceneDescription = '';
  DateTime? _lastSpokenTime;
  Offset _focusPoint = const Offset(0.5, 0.5);
  bool _focusFromEyeTracking = false;
  VrCapabilities _vrCapabilities = VrCapabilities.unsupported;
  bool _reduceModel = false;

  // ── deaf mode state ─────────────────────────────────────────────────────
  bool _isTranscribing = false;
  String _currentTranscript = '';
  final List<String> _transcriptHistory = [];

  // ── resolved platform helpers ───────────────────────────────────────────
  TargetPlatform get _resolvedPlatform =>
      widget.platformOverride ?? defaultTargetPlatform;

  bool get _usesWindowsCameraBackend =>
      !widget.forceSimulation && _resolvedPlatform == TargetPlatform.windows;

  bool get _supportsLiveCamera {
    if (widget.forceSimulation) return false;
    if (kIsWeb) return false; // camera plugin not available on web
    return _resolvedPlatform == TargetPlatform.android ||
        _resolvedPlatform == TargetPlatform.iOS ||
        _resolvedPlatform == TargetPlatform.windows;
  }

  // ── lifecycle ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initServices();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _gazeTimer?.cancel();
    _cameraController?.dispose();
    unawaited(SttService.instance.stopListening());
    unawaited(TtsService.instance.stop());
    super.dispose();
  }

  Future<void> _initServices() async {
    _reduceModel =
        await SettingsHelper.getBool('reduceModel', defaultValue: false);
    await _initCamera();
    await _initVrCapabilities();

    // Start blind mode detection loop by default.
    if (_mode == AccessibilityMode.blind) {
      await TtsService.instance.init();
      _startGazePolling();
      // Give the webcam a moment to start rendering frames.
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _startDetectionLoop();
    }
  }

  Future<void> _initVrCapabilities() async {
    _vrCapabilities = await VrService.instance.getCapabilities();
  }

  // ── camera init ─────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (_usesWindowsCameraBackend) {
      setState(() {
        _cameraReady = true;
        _cameraStatus = 'Windows webcam preview active.';
      });
      return;
    }

    if (!_supportsLiveCamera) {
      setState(() {
        _cameraStatus = kIsWeb
            ? 'Camera not supported on web yet.'
            : 'Camera not available on this platform.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No cameras found.');

      final preferred = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        preferred,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraStatus = 'Camera ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = 'Camera unavailable: $e';
      });
    }
  }

  // ── mode switching ──────────────────────────────────────────────────────
  void _switchMode(AccessibilityMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);

    if (mode == AccessibilityMode.blind) {
      // Leaving deaf mode → entering blind mode
      _stopTranscription();
      _startGazePolling();
      TtsService.instance.init().then((_) => _startDetectionLoop());
    } else {
      // Leaving blind mode → entering deaf mode
      _detectionTimer?.cancel();
      _detectionTimer = null;
      _stopGazePolling();
      unawaited(TtsService.instance.stop());
      setState(() {
        _detections = [];
        _sceneDescription = '';
      });
    }
  }

  // ── BLIND MODE: continuous detection + TTS ──────────────────────────────
  void _startDetectionLoop() {
    _detectionTimer?.cancel();
    final interval = _reduceModel
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 1200);
    _detectionTimer = Timer.periodic(
      interval,
      (_) => _runDetection(),
    );
    // Run one detection immediately.
    _runDetection();
  }

  Future<void> _runDetection() async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final frame = await _captureFrame();
      final results = await TfliteService.instance.runDetection(frame: frame);
      final focusedResults = _filterDetectionsByFocus(results);

      if (!mounted) return;

      setState(() => _detections = focusedResults);

      // Generate a spoken description and speak it.
      final description =
          await LmService.instance.generateDescription(focusedResults);

      if (!mounted) return;

      setState(() => _sceneDescription = description);

      // Avoid spamming TTS — wait at least 4 seconds between utterances.
      final now = DateTime.now();
      if (_lastSpokenTime == null ||
          now.difference(_lastSpokenTime!).inSeconds >= 4) {
        _lastSpokenTime = now;
        await TtsService.instance.speak(description);
      }
    } catch (_) {
      // Detection failure — keep trying on next cycle.
    } finally {
      _isDetecting = false;
    }
  }

  Future<DetectionFrame?> _captureFrame() async {
    // Mobile camera path.
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final xFile = await _cameraController!.takePicture();
        final bytes = await xFile.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: 300, height: 300);
          return DetectionFrame(
            bytes: resized.getBytes(),
            width: 300,
            height: 300,
            bytesPerPixel: 4,
          );
        }
      } catch (_) {
        // Camera might not be ready.
      }
      return null;
    }

    // Windows WebRTC camera path.
    if (_usesWindowsCameraBackend) {
      final captured = await _windowsCameraController.captureFrame();
      if (captured != null) {
        return DetectionFrame(
          bytes: captured.bytes,
          width: captured.width,
          height: captured.height,
          bytesPerPixel: captured.bytesPerPixel,
        );
      }
    }

    return null;
  }

  List<DetectionResult> _filterDetectionsByFocus(List<DetectionResult> input) {
    if (input.isEmpty) return input;

    const double focusRadius = 0.35;
    final scored = <({DetectionResult det, double score})>[];

    for (final det in input) {
      final dx = det.x - _focusPoint.dx;
      final dy = det.y - _focusPoint.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > focusRadius) continue;

      final proximityScore = 1.0 - (dist / focusRadius);
      final distanceBonus = det.distanceMeters == null
          ? 0.0
          : (1.0 / (1.0 + det.distanceMeters!)).clamp(0.0, 1.0);
      final score = (det.confidence * 0.65) +
          (proximityScore * 0.25) +
          (distanceBonus * 0.10);
      scored.add((det: det, score: score));
    }

    if (scored.isEmpty) {
      final nearest = [...input]..sort((a, b) {
          final da = math.sqrt(math.pow(a.x - _focusPoint.dx, 2) +
              math.pow(a.y - _focusPoint.dy, 2));
          final db = math.sqrt(math.pow(b.x - _focusPoint.dx, 2) +
              math.pow(b.y - _focusPoint.dy, 2));
          return da.compareTo(db);
        });
      return nearest.take(2).toList();
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(5).map((item) => item.det).toList();
  }

  void _updateFocusPoint(Offset localPosition, Size bounds) {
    if (bounds.width <= 0 || bounds.height <= 0) return;
    final nx = (localPosition.dx / bounds.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / bounds.height).clamp(0.0, 1.0);
    setState(() {
      _focusPoint = Offset(nx, ny);
      _focusFromEyeTracking = false;
    });
  }

  void _startGazePolling() {
    _gazeTimer?.cancel();
    if (!_vrCapabilities.eyeTrackingSupported) return;

    _gazeTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      final gaze = await VrService.instance.getEyeGazePoint();
      if (!mounted || gaze == null) return;
      setState(() {
        _focusPoint = gaze;
        _focusFromEyeTracking = true;
      });
    });
  }

  void _stopGazePolling() {
    _gazeTimer?.cancel();
    _gazeTimer = null;
  }

  // ── DEAF MODE: speech-to-text transcription ─────────────────────────────
  Future<void> _startTranscription() async {
    final ok = await SttService.instance.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Speech recognition is not available on this device.',
            ),
          ),
        );
      }
      return;
    }

    SttService.instance.onPartialResult = (text) {
      if (mounted) setState(() => _currentTranscript = text);
    };
    SttService.instance.onFinalResult = (text) {
      if (mounted) {
        setState(() {
          if (text.isNotEmpty) _transcriptHistory.insert(0, text);
          _currentTranscript = '';
        });
        // Restart listening for continuous transcription.
        if (_isTranscribing) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isTranscribing && mounted) {
              SttService.instance.startListening();
            }
          });
        }
      }
    };
    SttService.instance.onError = (error) {
      debugPrint('STT error: $error');
      // Try restarting.
      if (_isTranscribing && mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (_isTranscribing && mounted) {
            SttService.instance.startListening();
          }
        });
      }
    };

    setState(() => _isTranscribing = true);
    await SttService.instance.startListening();
  }

  void _stopTranscription() {
    setState(() => _isTranscribing = false);
    SttService.instance.stopListening();
    SttService.instance.onPartialResult = null;
    SttService.instance.onFinalResult = null;
    SttService.instance.onError = null;
  }

  // ── camera callbacks from Windows backend ───────────────────────────────
  void _handleWindowsCameraReady() {
    if (mounted) setState(() => _cameraStatus = 'Windows webcam ready.');
  }

  void _handleWindowsCameraError(String error) {
    if (mounted) {
      setState(() {
        _cameraReady = false;
        _cameraStatus = 'Webcam error: $error';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF03101C), Color(0xFF08131F), Color(0xFF0F2035)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              _buildModeToggle(context),
              Expanded(child: _buildCameraWithOverlay(context)),
              _buildBottomPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── top bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        children: [
          Text(
            'Vizio XR',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: _mode == AccessibilityMode.deaf
                ? 'Hearing Assist'
                : 'Vision Assist',
            icon: _mode == AccessibilityMode.deaf
                ? Icons.hearing
                : Icons.visibility,
            color: _mode == AccessibilityMode.deaf
                ? const Color(0xFF8EDBFF)
                : const Color(0xFF55E6C1),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  // ── mode toggle (deaf ↔ blind) ──────────────────────────────────────────
  Widget _buildModeToggle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'Hearing Assist',
              subtitle: 'Live transcription of speech',
              icon: Icons.hearing,
              selected: _mode == AccessibilityMode.deaf,
              onTap: () => _switchMode(AccessibilityMode.deaf),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModeButton(
              label: 'Vision Assist',
              subtitle: 'Object detection & voice',
              icon: Icons.visibility,
              selected: _mode == AccessibilityMode.blind,
              onTap: () => _switchMode(AccessibilityMode.blind),
            ),
          ),
        ],
      ),
    );
  }

  // ── camera + overlays ───────────────────────────────────────────────────
  Widget _buildCameraWithOverlay(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview layer.
            _buildCameraPreview(),
            // Mode-specific overlay.
            if (_mode == AccessibilityMode.deaf)
              _buildDeafOverlay(context)
            else
              _buildBlindOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_cameraReady) {
      return Container(
        color: const Color(0xFF07111C),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: 16),
              Text(
                _cameraStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_usesWindowsCameraBackend) {
      return WindowsCameraSurface(
        controller: _windowsCameraController,
        onCameraReady: _handleWindowsCameraReady,
        onCameraError: _handleWindowsCameraError,
        fallback: _buildFallbackSurface(),
      );
    }

    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }

    return _buildFallbackSurface();
  }

  Widget _buildFallbackSurface() {
    return Container(
      color: const Color(0xFF0A1520),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text(
              'Camera not available',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DEAF MODE OVERLAY — live transcription of ambient speech
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDeafOverlay(BuildContext context) {
    return Positioned.fill(
      child: Column(
        children: [
          const Spacer(),
          // Transcript area.
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.7),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live transcript.
                if (_currentTranscript.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF55E6C1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF55E6C1).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.mic,
                          color: Color(0xFF55E6C1),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentTranscript,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // History.
                if (_transcriptHistory.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      reverse: false,
                      itemCount: _transcriptHistory.length.clamp(0, 10),
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _transcriptHistory[index],
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: 1.0 - index * 0.08,
                              ),
                              fontSize: 14,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (!_isTranscribing &&
                    _currentTranscript.isEmpty &&
                    _transcriptHistory.isEmpty)
                  const Text(
                    'Tap the microphone button below to start\nlive speech transcription.',
                    style: TextStyle(color: Colors.white60, fontSize: 14),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BLIND MODE OVERLAY — bounding boxes + approach warnings
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBlindOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _updateFocusPoint(details.localPosition, bounds),
          onPanUpdate: (details) =>
              _updateFocusPoint(details.localPosition, bounds),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bounding-box overlays.
              LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: _detections.map((det) {
                      final left = det.left * constraints.maxWidth;
                      final top = det.top * constraints.maxHeight;
                      final width = det.width * constraints.maxWidth;
                      final height = det.height * constraints.maxHeight;
                      final label = displayLabel(det.label);

                      final bool isClose = det.distanceMeters != null &&
                          det.distanceMeters! < 1.5;

                      final Color boxColor = isClose
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFF55E6C1);

                      if (det.width < 0.01 || det.height < 0.01) {
                        // No real bounding box — show pill at center.
                        return Positioned(
                          left: det.x * constraints.maxWidth - 40,
                          top: det.y * constraints.maxHeight - 14,
                          child:
                              _detectionPill(label, det.confidence, boxColor),
                        );
                      }

                      return Positioned(
                        left: left,
                        top: top,
                        width: width,
                        height: height,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: boxColor, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: const BorderRadius.only(
                                  bottomRight: Radius.circular(6),
                                ),
                              ),
                              child: Text(
                                det.distanceLabel.isNotEmpty
                                    ? '$label ${(det.confidence * 100).toStringAsFixed(0)}% · ${det.distanceLabel}'
                                    : '$label ${(det.confidence * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: boxColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              Positioned(
                left: (_focusPoint.dx * constraints.maxWidth) - 16,
                top: (_focusPoint.dy * constraints.maxHeight) - 16,
                child: IgnorePointer(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFFFC96B), width: 2),
                      color: Colors.black.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.center_focus_strong,
                      size: 16,
                      color: Color(0xFFFFC96B),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _focusFromEyeTracking
                        ? 'Focus: eye gaze'
                        : 'Focus: pointer',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // Scene description bar at bottom.
              if (_sceneDescription.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                    child: Text(
                      _sceneDescription,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              // Detection spinner.
              if (_isDetecting)
                const Positioned(
                  top: 16,
                  right: 16,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF55E6C1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detectionPill(String label, double confidence, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label ${(confidence * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── bottom panel with action buttons ────────────────────────────────────
  Widget _buildBottomPanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: _mode == AccessibilityMode.deaf
          ? _buildDeafActions(context)
          : _buildBlindActions(context),
    );
  }

  Widget _buildDeafActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          icon: _isTranscribing ? Icons.mic_off : Icons.mic,
          label: _isTranscribing ? 'Stop Listening' : 'Start Listening',
          color: _isTranscribing
              ? const Color(0xFFFF6B6B)
              : const Color(0xFF8EDBFF),
          onTap: _isTranscribing ? _stopTranscription : _startTranscription,
        ),
        const SizedBox(width: 16),
        _ActionButton(
          icon: Icons.delete_outline,
          label: 'Clear',
          color: Colors.white54,
          onTap: () {
            setState(() {
              _transcriptHistory.clear();
              _currentTranscript = '';
            });
          },
        ),
      ],
    );
  }

  Widget _buildBlindActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          icon: Icons.radar_rounded,
          label: 'Scan Now',
          color: const Color(0xFF55E6C1),
          onTap: _runDetection,
        ),
        const SizedBox(width: 16),
        _ActionButton(
          icon: TtsService.instance.isSpeaking
              ? Icons.volume_off
              : Icons.volume_up,
          label: TtsService.instance.isSpeaking ? 'Stop Voice' : 'Speak',
          color: const Color(0xFFB8A4FF),
          onTap: () async {
            if (TtsService.instance.isSpeaking) {
              await TtsService.instance.stop();
            } else if (_sceneDescription.isNotEmpty) {
              await TtsService.instance.speak(_sceneDescription);
            }
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF55E6C1)
        : Colors.white.withValues(alpha: 0.4);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF55E6C1).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF55E6C1).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
