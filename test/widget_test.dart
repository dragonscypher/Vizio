import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizio/main.dart';
import 'package:vizio/models/detection_result.dart';
import 'package:vizio/screens/home_screen.dart';
import 'package:vizio/services/detector_service.dart';
import 'package:vizio/services/mock_detector_service.dart';
import 'package:vizio/utils/distance_estimator.dart';

void main() {
  testWidgets('home screen renders mode toggle for Windows-style testing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MySlamApp(
        homeOverride: HomeScreen(
          forceSimulation: true,
          disableAutomation: true,
          platformOverride: TargetPlatform.windows,
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Vizio XR'), findsOneWidget);
    expect(find.text('Hearing Assist'), findsAtLeastNWidgets(1));
    expect(find.text('Vision Assist'), findsAtLeastNWidgets(1));
  });

  group('DetectionResult model', () {
    test('x and y return bounding-box center', () {
      final det = DetectionResult(
        label: 'person',
        confidence: 0.9,
        left: 0.1,
        top: 0.2,
        width: 0.3,
        height: 0.4,
      );

      expect(det.x, closeTo(0.25, 0.001));
      expect(det.y, closeTo(0.40, 0.001));
    });

    test('distanceLabel returns empty when distance is null', () {
      final det = DetectionResult(
        label: 'person',
        confidence: 0.9,
        left: 0.0,
        top: 0.0,
        width: 0.5,
        height: 0.5,
      );

      expect(det.distanceLabel, isEmpty);
    });

    test('distanceLabel returns human-readable text', () {
      final det = DetectionResult(
        label: 'bottle',
        confidence: 0.8,
        left: 0.3,
        top: 0.3,
        width: 0.1,
        height: 0.2,
        distanceMeters: 0.6,
      );

      expect(det.distanceLabel, contains('0.6'));
    });

    test('fromMap handles legacy x/y format', () {
      final det = DetectionResult.fromMap({
        'label': 'car',
        'confidence': 0.75,
        'x': 0.5,
        'y': 0.5,
      });

      expect(det.left, 0.5);
      expect(det.top, 0.5);
      expect(det.width, 0.0);
      expect(det.height, 0.0);
    });
  });

  group('MockDetectorService', () {
    test('returns empty detections (no hard-coded fakes)', () async {
      final mock = MockDetectorService();
      await mock.initialize();

      final results = await mock.detect(
        DetectionFrame(
          bytes: Uint8List(0),
          width: 300,
          height: 300,
        ),
      );

      expect(results, isEmpty);
      expect(mock.isRealInference, isFalse);
    });
  });

  group('DistanceEstimator', () {
    test('estimates distance for known objects', () {
      final d = DistanceEstimator.estimate(
        label: 'person',
        bboxHeightNormalized: 0.5,
        imageHeight: 300,
      );

      expect(d, isNotNull);
      expect(d!, greaterThan(0.0));
    });

    test('returns null for unknown objects', () {
      final d = DistanceEstimator.estimate(
        label: 'platypus',
        bboxHeightNormalized: 0.5,
        imageHeight: 300,
      );

      expect(d, isNull);
    });

    test('returns null for tiny bounding boxes', () {
      final d = DistanceEstimator.estimate(
        label: 'person',
        bboxHeightNormalized: 0.005,
        imageHeight: 300,
      );

      expect(d, isNull);
    });
  });
}
