# Vizio XR

Vizio XR is a Flutter-based scene assistant designed to stay useful across multiple device classes:

- Phone and tablet mode with live camera scanning when available
- AR mode on supported Android and iOS hardware
- VR-style split view for phone headsets
- Windows webcam preview with a desktop lab fallback for testing
- Desktop lab feed on macOS and Linux for camera-like testing
- Guided simulation mode on web or unsupported hardware

The current app includes:

- Real object detection pipeline using TFLite and the bundled SSD MobileNet model
- Detection results include bounding boxes and estimated distances for known objects
- Focus-targeted detection: the overlay now filters detections around a movable focus reticle (pointer-driven, with eye-gaze hook when available)
- Frame capture from the mobile camera plugin and the Windows WebRTC webcam surface
- A detector abstraction (`DetectorService`) with real (`TfliteDetectorService`) and mock (`MockDetectorService`) backends
- Native language-model bridge support through `lm_channel`, plus a template fallback
- Cross-platform TTS and live STT service integration with platform-aware fallbacks
- Local settings for alert saving, reduced model mode, and voice selection
- A native VR capability bridge through `vr_channel` (Meta device detection + VR capability reporting)

## What Works Today

- Android and iOS:
  The app captures frames from the camera plugin, runs TFLite inference, and displays real bounding-box overlays with distance estimates. AR mode is available on supported devices.
- Web:
  The app uses a guided simulation surface. Detection returns empty results (no misleading fakes).
- Windows:
  The app opens a real webcam preview via `flutter_webrtc` and captures frames through `RepaintBoundary`. If the TFLite native library is present, real detection runs on those frames. Otherwise the UI clearly shows no detections instead of hard-coded placeholders.
- macOS and Linux:
  These desktop targets use the desktop lab feed with manual scan controls. TFLite detection works if the native library is installed.
- Phone headset VR:
  The app can switch into split-view mode for Cardboard-style phone headsets.
- Native Quest / OpenXR VR:
  The project includes a platform channel stub, but true immersive native VR still requires device SDK and OpenXR integration on Android.

## Detection Pipeline

The detection system uses a layered architecture:

1. **`DetectorService`** — abstract interface that accepts a `DetectionFrame` (raw pixel bytes + dimensions).
2. **`TfliteDetectorService`** — loads `assets/tflite/object_detection.tflite` via `tflite_flutter` and runs SSD MobileNet inference with COCO 80-class labels. Falls back gracefully if the native TFLite library is missing.
3. **`MockDetectorService`** — returns an empty list. Used in tests and on platforms where inference isn't available yet.
4. **`TfliteService`** — singleton façade that picks the right `DetectorService` at startup and exposes `runDetection(frame:)`.

### Object Classes

The bundled model uses the COCO label map. COCO has no dedicated "can" or "soda can" class — a soda can typically maps to **bottle** (class 44) or **cup** (class 47). The UI shows these as "bottle / can" to be helpful.

### Focused Detection

By default, the app uses a center focus point and filters detections to objects near that point. In Vision Assist mode you can tap or drag on the preview to move the focus reticle. This reduces overlay clutter and gives near-pointer object priority for speech descriptions.

On platforms exposing gaze data through `vr_channel`, the same focus point can be driven by eye tracking.

### Distance Estimation

Distance is estimated from bounding-box height using the pinhole-camera model with known real-world object heights (e.g. person ≈ 1.7 m, bottle ≈ 0.22 m). This is approximate and is labelled "estimated" in the UI. For production use, depth-sensor or AR-pose data should replace this heuristic.

## Setup

1. Install Flutter and your platform toolchains.
2. Run `flutter pub get`.
3. Keep the bundled model and face assets under `assets/tflite/` and `assets/faces/`.
4. For Android AR builds, use a device that supports ARCore.
5. For iOS AR builds, use hardware that supports ARKit.
6. **Windows TFLite setup** (required for real detection on Windows):
   - Download `libtensorflowlite_c-win64.dll` from the [TensorFlow Lite releases](https://github.com/niclas-niclas/tflite_flutter_helper/releases) or build it from the TFLite source.
   - Place the DLL next to the built executable or in a directory on your system `PATH`.
   - Without this DLL, the app still runs but detection results will be empty.

## Run

1. Start the app with `flutter run`.
2. Use the top bar actions:
   `AR` opens the phone AR experience on supported mobile hardware.
   `VR` toggles headset-style split view.
   `Headset` checks the native VR bridge stub.
   `Settings` opens persistence and voice options.
3. Press **Trigger Scan** or **Run Desktop Scan** to capture a frame and run detection.

## Platform Notes

- Android:
  The app now sets `minSdk` to `24`, which matches the AR plugin requirement.
  TFLite native library is bundled automatically by `tflite_flutter`.
  VR capability reporting and Meta headset detection are exposed through `vr_channel`.
- iOS:
  Camera usage messaging is configured in `Info.plist`.
  TFLite native library is included via CocoaPods.
  iPhone/iPad AR remains conditional on ARKit-capable hardware.
- Windows:
  Desktop builds use a webcam preview when possible, plus a lab feed fallback. Real inference requires the TFLite DLL (see Setup).
- macOS and Linux:
  Lab feed with scan controls. TFLite support depends on the platform native library.
- Web:
  Web stays usable through the simulation surface. No inference runs on web.

## Current Limits

- The SLAM service is still simulated and should be replaced with production AR pose or OpenXR tracking for real deployments.
- Distance estimation is heuristic-based (bounding-box size), not depth-sensor-backed.
- The COCO model does not have a dedicated "can" class; soda cans register as "bottle".
- Native Quest / XR-glasses support is partial: capability detection is implemented, and Meta shell launch is attempted on supported Android headsets, but full immersive OpenXR scene integration is still pending.
- TFLite inference on Windows requires manual setup of the native library. On Android and iOS it works out of the box.

## Model Research Notes (March 2026)

The following low-latency model options were reviewed for this app's use case (AR/VR scene understanding + live transcription):

- Object detection (Google MediaPipe task guide):
  EfficientDet-Lite0 (recommended balanced option), EfficientDet-Lite2 (higher accuracy, higher latency), SSD MobileNetV2 (fastest/lightest among listed options).
- Mobile latency reference from MediaPipe benchmarks (Pixel 6 CPU):
  EfficientDet-Lite0 int8 ~29.31ms, SSD MobileNetV2 float32 ~36.30ms, EfficientDet-Lite2 int8 ~70.91ms.
- Multilingual ASR (Whisper family):
  `openai/whisper-tiny` (39M), `openai/whisper-base` (74M), `openai/whisper-small` (244M).
- Ultra-small live ASR option (English-focused):
  `UsefulSensors/moonshine-tiny` (27M) and `UsefulSensors/moonshine-base` (61M), designed for constrained hardware and real-time transcription use cases.
- Apple-specific on-device path:
  `argmaxinc/whisperkit-coreml` for CoreML-based Whisper deployments on Apple Silicon.

References:

- https://ai.google.dev/edge/mediapipe/solutions/vision/object_detector
- https://huggingface.co/openai/whisper-tiny
- https://huggingface.co/openai/whisper-base
- https://huggingface.co/openai/whisper-small
- https://huggingface.co/UsefulSensors/moonshine-tiny
- https://huggingface.co/UsefulSensors/moonshine-base
- https://huggingface.co/argmaxinc/whisperkit-coreml
