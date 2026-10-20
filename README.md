# Vizio XR

I wanted a phone app that could describe what is in front of you and roughly how far away it is, mainly with visually impaired users in mind. Vizio XR is a Flutter prototype that runs object detection on-device and speaks the result. It is a working prototype, not a finished product.

## What it does

- Detects objects on camera frames with TFLite and a bundled SSD MobileNet (COCO) model, and draws bounding boxes.
- Estimates distance from box height against known real-world object heights. It is a heuristic and is labelled "estimated" in the UI.
- A movable focus reticle filters detections around a point, so speech and the overlay stay uncluttered. Eye gaze can drive it where the platform exposes it.
- Text-to-speech and live speech-to-text with platform fallbacks.
- Modes for phone and tablet camera, AR on ARCore/ARKit devices, a split-view VR mode for phone headsets, a Windows webcam preview, and a simulation view on web.

## How I built it

Detection sits behind a `DetectorService` interface, so the model can be swapped without touching the UI:

- `TfliteDetectorService` runs the model through `tflite_flutter` and degrades gracefully if the native library is missing.
- `MockDetectorService` returns nothing, and is used in tests and on web. I chose empty results over fake ones.
- `TfliteService` picks the right backend at startup. Platform channels (`lm_channel`, `vr_channel`) bridge to native code.

## Run it

```bash
flutter pub get
flutter run
```

Press Trigger Scan (or Run Desktop Scan) to capture a frame and detect. Android AR needs an ARCore device and iOS AR needs ARKit hardware. On Windows, real detection needs `libtensorflowlite_c-win64.dll` next to the executable or on `PATH`; without it the app runs but shows no detections.

## Known limits

- SLAM is simulated. Real AR pose or OpenXR tracking is still to do.
- Distance is bounding-box based, not depth-sensor based.
- COCO has no "can" class, so a soda can shows up as bottle or cup.
- Quest/OpenXR support is partial: headset detection works, full immersive support does not yet.
- TFLite on Windows needs a manual DLL setup. On Android and iOS it works out of the box.

## Model notes

I looked at EfficientDet-Lite and SSD MobileNet for detection, and Whisper and Moonshine for on-device speech, using the MediaPipe and Hugging Face docs. SSD MobileNet is bundled now because it is the lightest option.
