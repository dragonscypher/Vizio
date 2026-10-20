import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/custom_widgets.dart';

class ArModeScreen extends StatefulWidget {
  const ArModeScreen({super.key});

  @override
  State<ArModeScreen> createState() => _ArModeScreenState();
}

class _ArModeScreenState extends State<ArModeScreen> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arSessionManager?.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: false,
      handlePans: true,
      handleRotation: true,
    );
    _arObjectManager?.onInitialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Mode'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF04111C),
              Color(0xFF081723),
              Color(0xFF112C42),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GlassPanel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.view_in_ar_rounded,
                        color: Color(0xFF8EDBFF),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phone AR workspace',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'This view is optimized for ARCore and ARKit phones. Move the device slowly so plane detection can lock in before you place content or trust scene guidance.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white70, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: _isSupportedPlatform
                        ? ARView(
                            onARViewCreated: _onARViewCreated,
                            planeDetectionConfig:
                                PlaneDetectionConfig.horizontalAndVertical,
                          )
                        : _buildUnsupportedState(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedState(BuildContext context) {
    return Container(
      color: const Color(0xFF08111B),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_iphone_rounded,
                size: 54,
                color: Color(0xFFFFC96B),
              ),
              const SizedBox(height: 16),
              Text(
                'AR mode needs a supported phone or tablet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'This build stays usable everywhere else, but live AR requires ARCore on Android or ARKit on iOS hardware.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
