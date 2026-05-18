import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "hareeg_table/local_storage",
        binaryMessenger: controller.binaryMessenger
      )
      let defaults = UserDefaults.standard

      channel.setMethodCallHandler { call, result in
        guard
          let arguments = call.arguments as? [String: Any],
          let key = arguments["key"] as? String
        else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "A storage key is required.",
            details: nil
          ))
          return
        }

        switch call.method {
        case "getString":
          result(defaults.string(forKey: key))
        case "setString":
          guard let value = arguments["value"] as? String else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "A string value is required.",
              details: nil
            ))
            return
          }
          defaults.set(value, forKey: key)
          result(nil)
        case "remove":
          defaults.removeObject(forKey: key)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
