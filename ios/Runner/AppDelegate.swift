import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var pendingLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    // MethodChannel for deep links
    let methodChannel = FlutterMethodChannel(
      name: "zero/deep_links",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getInitialLink":
        let link = self.pendingLink
        self.pendingLink = nil
        result(link)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // EventChannel for streaming deep links
    let eventChannel = FlutterEventChannel(
      name: "zero/deep_links/events",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  // MARK: - URL handling (called from SceneDelegate)

  func handleURL(_ url: URL) {
    let value = url.absoluteString
    pendingLink = value
    eventSink?(value)
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    if let pendingLink {
      events(pendingLink)
      self.pendingLink = nil
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}