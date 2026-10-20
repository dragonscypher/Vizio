import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let vrChannel = FlutterMethodChannel(name: "vr_channel", binaryMessenger: controller.engine.binaryMessenger)
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
            "eyeTrackingSupported": false,
          ])
        case "getEyeGazePoint":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
