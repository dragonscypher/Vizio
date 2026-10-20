import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection_result.dart';
import '../utils/coco_labels.dart';
import '../utils/distance_estimator.dart';
import 'detector_service.dart';

/// Real object-detection backend backed by a TFLite model.
///
/// Supports SSD-style models (MobileNet v1/v2, EfficientDet-Lite) that output
/// 4 tensors: boxes [1,N,4], classes [1,N], scores [1,N], count [1].
class TfliteDetectorService extends DetectorService {
  static const String _assetPath = 'assets/tflite/object_detection.tflite';
  static const double _confidenceThreshold = 0.45;

  Interpreter? _interpreter;
  int _inputSize = 320; // read from model tensor at init
  int _maxDetections = 25;
  int _classIdxOffset = 0; // +1 for 0-indexed models (no background class)

  @override
  bool get isRealInference => _interpreter != null;

  @override
  Future<bool> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 4;

      // On desktop, Interpreter.fromAsset may not work.  Copy the asset to
      // a temp file and load from there.
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final modelFile = await _copyAssetToFile();
        _interpreter = Interpreter.fromFile(modelFile, options: options);
      } else {
        _interpreter =
            await Interpreter.fromAsset(_assetPath, options: options);
      }

      // Read actual input size and max detections from model.
      final inputTensor = _interpreter!.getInputTensor(0);
      final shape = inputTensor.shape; // [1, H, W, 3]
      if (shape.length == 4) _inputSize = shape[1];

      final classTensor = _interpreter!.getOutputTensor(1);
      if (classTensor.shape.length == 2) {
        _maxDetections = classTensor.shape[1];
      }

      // The google-coral SSD MobileNet v2 model uses 0-indexed COCO class
      // IDs (0 = person), while our label map is 1-indexed (0 = background,
      // 1 = person).  Detect this by checking if max-detections == 20
      // (coral) vs 10 (tf1 zoo).  A more robust check would inspect
      // tensor metadata, but tflite_flutter doesn't expose that easily.
      // Apply an offset of +1 so class indices map correctly to our labels.
      _classIdxOffset = _maxDetections == 20 ? 1 : 0;

      final outputCount = _interpreter!.getOutputTensors().length;
      debugPrint('TfliteDetectorService: model loaded OK');
      debugPrint('  input: shape=$shape, type=${inputTensor.type}, '
          'size=${_inputSize}x$_inputSize');
      debugPrint(
          '  outputs: $outputCount, maxDet=$_maxDetections, classOffset=$_classIdxOffset');

      return true;
    } catch (e) {
      debugPrint('TfliteDetectorService: init failed: $e');
      _interpreter = null;
      return false;
    }
  }

  /// Copy the bundled asset to a temporary file so `Interpreter.fromFile`
  /// works on desktop platforms.
  Future<File> _copyAssetToFile() async {
    final data = await rootBundle.load(_assetPath);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/object_detection.tflite');
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file;
  }

  @override
  Future<List<DetectionResult>> detect(DetectionFrame frame) async {
    if (_interpreter == null) return [];

    try {
      return _runInference(frame);
    } catch (e) {
      debugPrint('TfliteDetectorService.detect error: $e');
      return [];
    }
  }

  /// Run inference on the current isolate.
  List<DetectionResult> _runInference(DetectionFrame frame) {
    final inputTensor = _interpreter!.getInputTensor(0);
    final isQuantized = inputTensor.type == TensorType.uint8;

    // Center-crop geometry — must match preprocessing.
    final cropSize = frame.width < frame.height ? frame.width : frame.height;
    final cropOffX = (frame.width - cropSize) ~/ 2;
    final cropOffY = (frame.height - cropSize) ~/ 2;

    final maxDet = _maxDetections;
    final outputBoxes = List.generate(
        1, (_) => List.generate(maxDet, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(maxDet, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(maxDet, 0.0));
    final outputCount = List.filled(1, 0.0);

    final outputs = <int, Object>{
      0: outputBoxes,
      1: outputClasses,
      2: outputScores,
      3: outputCount,
    };

    final sw = Stopwatch()..start();

    if (isQuantized) {
      final input = _preprocessUint8(frame);
      _interpreter!.runForMultipleInputs([input], outputs);
    } else {
      final input = _preprocessFloat(frame);
      _interpreter!.runForMultipleInputs([input.buffer], outputs);
    }

    sw.stop();
    debugPrint('TfliteDetector: inference ${sw.elapsedMilliseconds} ms '
        '(frame ${frame.width}x${frame.height}, bpp=${frame.bytesPerPixel})');

    final count = outputCount[0].toInt().clamp(0, maxDet);
    final results = <DetectionResult>[];

    for (int i = 0; i < count; i++) {
      final score = outputScores[0][i];
      final rawClassIdx = outputClasses[0][i].toInt();
      final classIdx = rawClassIdx + _classIdxOffset;

      debugPrint(
          '  det[$i]: rawClass=$rawClassIdx mapped=$classIdx score=${score.toStringAsFixed(3)} '
          'label=${cocoLabels[classIdx] ?? "?"}');

      if (score < _confidenceThreshold) continue;

      final rawLabel = cocoLabels[classIdx] ?? 'object_$classIdx';
      if (rawLabel == 'background') continue;

      // Model outputs boxes in [0,1] relative to the cropped square.
      // Map back to the full frame's normalised coordinate space.
      final bTop = outputBoxes[0][i][0].clamp(0.0, 1.0);
      final bLeft = outputBoxes[0][i][1].clamp(0.0, 1.0);
      final bBottom = outputBoxes[0][i][2].clamp(0.0, 1.0);
      final bRight = outputBoxes[0][i][3].clamp(0.0, 1.0);

      final fLeft =
          ((cropOffX + bLeft * cropSize) / frame.width).clamp(0.0, 1.0);
      final fTop =
          ((cropOffY + bTop * cropSize) / frame.height).clamp(0.0, 1.0);
      final fRight =
          ((cropOffX + bRight * cropSize) / frame.width).clamp(0.0, 1.0);
      final fBottom =
          ((cropOffY + bBottom * cropSize) / frame.height).clamp(0.0, 1.0);

      final w = (fRight - fLeft).clamp(0.0, 1.0);
      final h = (fBottom - fTop).clamp(0.0, 1.0);

      final distance = DistanceEstimator.estimate(
        label: rawLabel,
        bboxHeightNormalized: h,
        imageHeight: _inputSize,
      );

      results.add(DetectionResult(
        label: rawLabel,
        confidence: score,
        left: fLeft,
        top: fTop,
        width: w,
        height: h,
        distanceMeters: distance,
      ));
    }

    return results;
  }

  /// Preprocess frame into a flat Uint8List for quantized (uint8) models.
  ///
  /// Center-crops the source frame to a square region before resizing to
  /// the model's input size.  This preserves aspect ratio and avoids the
  /// heavy distortion that crushed 1232×476 webcam frames into 300×300,
  /// which was the primary cause of wrong detections.
  Uint8List _preprocessUint8(DetectionFrame frame) {
    // Center-crop to the largest square that fits.
    final cropSize = frame.width < frame.height ? frame.width : frame.height;
    final cropOffX = (frame.width - cropSize) ~/ 2;
    final cropOffY = (frame.height - cropSize) ~/ 2;

    final buf = Uint8List(_inputSize * _inputSize * 3);
    int offset = 0;
    for (int py = 0; py < _inputSize; py++) {
      final srcY =
          cropOffY + (py * cropSize ~/ _inputSize).clamp(0, cropSize - 1);
      for (int px = 0; px < _inputSize; px++) {
        final srcX =
            cropOffX + (px * cropSize ~/ _inputSize).clamp(0, cropSize - 1);
        final idx = (srcY * frame.width + srcX) * frame.bytesPerPixel;
        if (idx + 2 < frame.bytes.length) {
          buf[offset] = frame.bytes[idx]; // R
          buf[offset + 1] = frame.bytes[idx + 1]; // G
          buf[offset + 2] = frame.bytes[idx + 2]; // B
        }
        offset += 3;
      }
    }
    return buf;
  }

  /// Preprocess frame into a flat Float32List for float32 models.
  Float32List _preprocessFloat(DetectionFrame frame) {
    final cropSize = frame.width < frame.height ? frame.width : frame.height;
    final cropOffX = (frame.width - cropSize) ~/ 2;
    final cropOffY = (frame.height - cropSize) ~/ 2;

    final buf = Float32List(_inputSize * _inputSize * 3);
    int offset = 0;
    for (int py = 0; py < _inputSize; py++) {
      final srcY =
          cropOffY + (py * cropSize ~/ _inputSize).clamp(0, cropSize - 1);
      for (int px = 0; px < _inputSize; px++) {
        final srcX =
            cropOffX + (px * cropSize ~/ _inputSize).clamp(0, cropSize - 1);
        final idx = (srcY * frame.width + srcX) * frame.bytesPerPixel;
        if (idx + 2 < frame.bytes.length) {
          buf[offset] = frame.bytes[idx] / 255.0;
          buf[offset + 1] = frame.bytes[idx + 1] / 255.0;
          buf[offset + 2] = frame.bytes[idx + 2] / 255.0;
        }
        offset += 3;
      }
    }
    return buf;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}
