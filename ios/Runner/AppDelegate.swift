import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let liveActivityChannelName = "com.example.airtime/live_activity"
  private var liveActivityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyA1_RD_0S0nngWZc-GXtGWJvRlM1pXy3E4")

    // Configure Firebase (if not already done by Flutter)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // Set FCM delegate
    Messaging.messaging().delegate = self

    // Register for remote notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    // Set up Live Activity MethodChannel
    setupLiveActivityChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle APNs token registration
  override func application(_ application: UIApplication,
                           didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // MARK: - Live Activity MethodChannel

  private func setupLiveActivityChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("[AppDelegate] Could not get FlutterViewController for Live Activity channel")
      return
    }

    liveActivityChannel = FlutterMethodChannel(
      name: liveActivityChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    // Set up push token callback on LiveActivityManager
    if #available(iOS 16.2, *) {
      LiveActivityManager.shared.onPushTokenUpdate = { [weak self] flightId, tokenHex in
        DispatchQueue.main.async {
          self?.liveActivityChannel?.invokeMethod("onPushTokenUpdate", arguments: [
            "flightId": flightId,
            "pushToken": tokenHex,
          ])
        }
      }
    }

    liveActivityChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleLiveActivityMethod(call: call, result: result)
    }
  }

  private func handleLiveActivityMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.2, *) else {
      result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.2+", details: nil))
      return
    }

    switch call.method {
    case "startLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.startActivity(params: params) { outcome in
        switch outcome {
        case .success(let data):
          result(data)
        case .failure(let error):
          result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "updateLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.updateActivity(params: params) { outcome in
        switch outcome {
        case .success:
          result(nil)
        case .failure(let error):
          result(FlutterError(code: "UPDATE_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "endLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.endActivity(params: params) { outcome in
        switch outcome {
        case .success:
          result(nil)
        case .failure(let error):
          result(FlutterError(code: "END_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "areActivitiesEnabled":
      result(LiveActivityManager.shared.areActivitiesEnabled())

    case "endAllActivities":
      LiveActivityManager.shared.endAllActivities()
      result(nil)

    // Train Live Activity methods
    case "startTrainLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.startTrainActivity(params: params) { outcome in
        switch outcome {
        case .success(let data):
          result(data)
        case .failure(let error):
          result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "updateTrainLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.updateTrainActivity(params: params) { outcome in
        switch outcome {
        case .success:
          result(nil)
        case .failure(let error):
          result(FlutterError(code: "UPDATE_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "endTrainLiveActivity":
      guard let params = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Map arguments", details: nil))
        return
      }
      LiveActivityManager.shared.endTrainActivity(params: params) { outcome in
        switch outcome {
        case .success:
          result(nil)
        case .failure(let error):
          result(FlutterError(code: "END_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// FCM Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("[AppDelegate] FCM token received: \(fcmToken ?? "nil")")
  }
}
