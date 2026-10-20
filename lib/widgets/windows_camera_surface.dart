import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Lightweight controller that lets parent widgets capture the current camera
/// frame without reaching into the widget's internal state.
class WindowsCameraController {
  Future<CapturedFrame?> Function()? _captureFrame;

  /// Capture the current video frame as raw RGBA bytes.
  Future<CapturedFrame?> captureFrame() async => _captureFrame?.call();
}

/// Raw frame data captured from the webcam surface.
class CapturedFrame {
  final Uint8List bytes;
  final int width;
  final int height;

  /// Always 4 (RGBA).
  int get bytesPerPixel => 4;

  const CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

class WindowsCameraSurface extends StatefulWidget {
  const WindowsCameraSurface({
    super.key,
    required this.fallback,
    this.onCameraReady,
    this.onCameraError,
    this.controller,
  });

  final Widget fallback;
  final VoidCallback? onCameraReady;
  final ValueChanged<String>? onCameraError;
  final WindowsCameraController? controller;

  @override
  State<WindowsCameraSurface> createState() => _WindowsCameraSurfaceState();
}

class _WindowsCameraSurfaceState extends State<WindowsCameraSurface> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final GlobalKey _boundaryKey = GlobalKey();
  MediaStream? _mediaStream;

  bool _isLoading = true;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller?._captureFrame = _captureFrame;
    _initializeCamera();
  }

  @override
  void didUpdateWidget(WindowsCameraSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller?._captureFrame = _captureFrame;
  }

  @override
  void dispose() {
    widget.controller?._captureFrame = null;
    _disposeCamera();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      await _renderer.initialize();

      _mediaStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      });

      _renderer.srcObject = _mediaStream;

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _isReady = true;
      });
      widget.onCameraReady?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _isReady = false;
        _error = error.toString();
      });
      widget.onCameraError?.call(error.toString());
    }
  }

  /// Capture the currently rendered video frame via [RepaintBoundary].
  Future<CapturedFrame?> _captureFrame() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !_isReady) return null;

    try {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      return CapturedFrame(
        bytes: byteData.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _disposeCamera() async {
    final List<MediaStreamTrack> tracks = _mediaStream?.getTracks() ?? [];
    for (final MediaStreamTrack track in tracks) {
      track.stop();
    }

    if (_mediaStream != null) {
      await _mediaStream!.dispose();
      _mediaStream = null;
    }
    _renderer.srcObject = null;
    await _renderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallback;
    }

    if (_isLoading || !_isReady) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.fallback,
          Container(
            color: Colors.black.withValues(alpha: 0.26),
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 16),
                Text(
                  'Starting Windows webcam...',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RepaintBoundary(
      key: _boundaryKey,
      child: RTCVideoView(
        _renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: false,
      ),
    );
  }
}
