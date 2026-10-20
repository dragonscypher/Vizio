import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/detection_result.dart';
import '../utils/coco_labels.dart';

class LmService {
  static final LmService instance = LmService._internal();
  LmService._internal();

  // Platform channel for native LM integration.
  static const platform = MethodChannel('lm_channel');

  /// Generate a description based on detection results.
  /// Attempts to use the native LM integration (GGML/quantized Mistral) via the platform channel.
  /// Falls back to a template-based approach if the native method is not implemented.
  Future<String> generateDescription(List<DetectionResult> detections) async {
    try {
      final String input = _prepareInput(detections);
      final String result =
          await platform.invokeMethod('generateDescription', {'input': input});
      return result;
    } on MissingPluginException {
      return _fallbackGenerateDescription(detections);
    } on PlatformException {
      return _fallbackGenerateDescription(detections);
    }
  }

  String _prepareInput(List<DetectionResult> detections) {
    final Map<String, dynamic> prompt = {
      'scene': detections
          .map((d) => {
                'label': d.label,
                'x': d.x,
                'y': d.y,
                'confidence': d.confidence,
                'left': d.left,
                'top': d.top,
                'width': d.width,
                'height': d.height,
                if (d.distanceMeters != null)
                  'distanceMeters': d.distanceMeters,
              })
          .toList(),
    };
    return jsonEncode(prompt);
  }

  String _fallbackGenerateDescription(List<DetectionResult> detections) {
    if (detections.isEmpty) {
      return 'No objects detected in this frame. The scene appears clear.';
    }

    final StringBuffer buf = StringBuffer();

    for (final det in detections) {
      final name = displayLabel(det.label);
      final pct = (det.confidence * 100).toStringAsFixed(0);

      if (det.label == 'person') {
        buf.write('Person detected ($pct% confidence)');
      } else {
        buf.write(
            '${name[0].toUpperCase()}${name.substring(1)} detected ($pct%)');
      }

      if (det.distanceMeters != null) {
        buf.write(
            ' at ~${det.distanceMeters!.toStringAsFixed(1)} m (estimated)');
      }
      buf.write('. ');
    }

    buf.write('Stay alert and move accordingly.');
    return buf.toString();
  }
}
