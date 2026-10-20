import 'package:flutter/services.dart';

class VrCapabilities {
  const VrCapabilities({
    required this.vrSupported,
    required this.metaDevice,
    required this.eyeTrackingSupported,
  });

  final bool vrSupported;
  final bool metaDevice;
  final bool eyeTrackingSupported;

  factory VrCapabilities.fromMap(Map<Object?, Object?> map) {
    bool readBool(String key) => map[key] == true;
    return VrCapabilities(
      vrSupported: readBool('vrSupported'),
      metaDevice: readBool('metaDevice'),
      eyeTrackingSupported: readBool('eyeTrackingSupported'),
    );
  }

  static const unsupported = VrCapabilities(
    vrSupported: false,
    metaDevice: false,
    eyeTrackingSupported: false,
  );
}

class VrService {
  static final VrService instance = VrService._internal();
  VrService._internal();

  static const MethodChannel _channel = MethodChannel('vr_channel');

  Future<bool> isNativeVrSupported() async {
    try {
      final bool? supported =
          await _channel.invokeMethod<bool>('isVrSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> enterNativeVrMode() async {
    try {
      final bool? entered = await _channel.invokeMethod<bool>('enterVrMode');
      return entered ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<VrCapabilities> getCapabilities() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getVrCapabilities',
      );
      if (raw == null) return VrCapabilities.unsupported;
      return VrCapabilities.fromMap(raw);
    } on MissingPluginException {
      return VrCapabilities.unsupported;
    } on PlatformException {
      return VrCapabilities.unsupported;
    }
  }

  Future<Offset?> getEyeGazePoint() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getEyeGazePoint',
      );
      if (raw == null) return null;
      final x = (raw['x'] as num?)?.toDouble();
      final y = (raw['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      if (x.isNaN || y.isNaN) return null;
      return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
