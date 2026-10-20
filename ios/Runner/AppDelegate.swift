import Flutter
import UIKit
import ARKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let vrChannel = FlutterMethodChannel(name: "vr_channel", binaryMessenger: controller.binaryMessenger)
      vrChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isVrSupported":
          result(false)
        case "enterVrMode":
          result(false)
        case "getVrCapabilities":
          result([
            "vrSupported": false,
            "metaDevice": false,
            "eyeTrackingSupported": ARFaceTrackingConfiguration.isSupported,
          ])
        case "getEyeGazePoint":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
