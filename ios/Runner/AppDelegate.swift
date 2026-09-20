import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let notificationPrefix = "tomatolog.timer."
  private var platformChannel: FlutterMethodChannel?
  private var scheduleGeneration = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    registerNotificationCategory()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "tomatolog/platform",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    platformChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handlePlatformCall(call, result: result)
    }
  }

  private func handlePlatformCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestNotificationPermission":
      requestNotificationPermission(result)
    case "notificationStatus":
      notificationStatus(result)
    case "openCompletionNotificationSettings":
      openNotificationSettings()
      result(nil)
    case "markNotificationSetupGuideShown":
      UserDefaults.standard.set(true, forKey: "notification_setup_guide_shown")
      result(nil)
    case "showCompletionNotificationTest":
      addNotification(
        identifier: "\(notificationPrefix)test",
        title: "番茄日志",
        body: "通知、声音与震动已开启",
        delay: nil
      )
      result(nil)
    case "showTimer":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_timer", message: "计时参数无效", details: nil))
        return
      }
      scheduleTimerNotifications(arguments)
      result(nil)
    case "cancelTimer":
      clearTimerNotifications(removeDelivered: true)
      UserDefaults.standard.set(false, forKey: "timer_notifications_active")
      result(nil)
    case "completeTimer":
      UserDefaults.standard.set(false, forKey: "timer_notifications_active")
      result(nil)
    case "consumeNotificationAction":
      let action = UserDefaults.standard.string(forKey: "pending_notification_action")
      UserDefaults.standard.removeObject(forKey: "pending_notification_action")
      result(action)
    case "setKeepScreenOn":
      let active = call.arguments as? Bool ?? false
      UIApplication.shared.isIdleTimerDisabled = active
      landscapeViewController()?.setLandscapeTimerActive(active)
      result(nil)
    case "markBatteryOptimizationGuideShown", "requestBatteryOptimizationExemption":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestNotificationPermission(_ result: @escaping FlutterResult) {
    UserDefaults.standard.set(true, forKey: "notification_requested")
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { [weak self] settings in
      if settings.authorizationStatus == .denied {
        DispatchQueue.main.async {
          self?.openNotificationSettings()
          result(nil)
        }
        return
      }
      center.requestAuthorization(options: [.alert, .sound, .badge]) {
        _, _ in DispatchQueue.main.async { result(nil) }
      }
    }
  }

  private func notificationStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted: Bool
      if #available(iOS 14.0, *) {
        granted = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional ||
          settings.authorizationStatus == .ephemeral
      } else {
        granted = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional
      }
      DispatchQueue.main.async {
        result([
          "granted": granted,
          "requested": UserDefaults.standard.bool(forKey: "notification_requested"),
          "setupGuideShown": true,
          "batteryGuideShown": true,
          "batteryUnrestricted": true,
        ])
      }
    }
  }

  private func openNotificationSettings() {
    let url: URL?
    if #available(iOS 16.0, *) {
      url = URL(string: UIApplication.openNotificationSettingsURLString)
    } else {
      url = URL(string: UIApplication.openSettingsURLString)
    }
    if let url = url { UIApplication.shared.open(url) }
  }

  private func landscapeViewController() -> TimerFlutterViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController as? TimerFlutterViewController
  }

  private func registerNotificationCategory() {
    let stop = UNNotificationAction(
      identifier: "STOP_TIMER",
      title: "结束计时",
      options: [.destructive, .foreground]
    )
    let category = UNNotificationCategory(
      identifier: "TIMER",
      actions: [stop],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  private func scheduleTimerNotifications(_ arguments: [String: Any]) {
    scheduleGeneration += 1
    let generation = scheduleGeneration
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { [weak self] requests in
      guard let self, generation == self.scheduleGeneration else { return }
      center.removePendingNotificationRequests(
        withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(self.notificationPrefix) }
      )
      self.addTimerSchedule(arguments)
    }
  }

  private func addTimerSchedule(_ arguments: [String: Any]) {
    let category = (arguments["category"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "专注"
    var phase = arguments["phase"] as? String ?? "running"
    var cycle = integer(arguments["currentCycle"], fallback: 1)
    let cycles = max(1, integer(arguments["cycleCount"], fallback: 1))
    var group = integer(arguments["currentGroup"], fallback: 1)
    let groups = max(1, integer(arguments["groupCount"], fallback: 1))
    let focus = max(0, integer(arguments["focusSeconds"], fallback: 0))
    let shortBreak = max(0, integer(arguments["intervalSeconds"], fallback: 0))
    let longBreak = max(0, integer(arguments["longIntervalSeconds"], fallback: 0))
    var duration = max(0, integer(arguments["remainingSeconds"], fallback: 0))
    var delay = 0
    var index = 0

    let expiresAt = UserDefaults.standard.double(forKey: "timer_notifications_expire_at")
    let notificationsActive = UserDefaults.standard.bool(forKey: "timer_notifications_active") &&
      expiresAt > Date().timeIntervalSince1970
    if !notificationsActive {
      addNotification(
        identifier: "\(notificationPrefix)started",
        title: "\(category)开始",
        body: "第 \(group) 组，第 \(cycle)/\(cycles) 轮专注",
        delay: nil
      )
      UserDefaults.standard.set(true, forKey: "timer_notifications_active")
    }

    while index < 63 {
      delay += duration
      guard delay > 0 else { break }
      index += 1
      let title: String
      let body: String

      if phase == "running" {
        if cycle < cycles && shortBreak > 0 {
          title = "专注结束 · 短休息开始"
          body = "\(category)已完成第 \(cycle)/\(cycles) 轮"
          phase = "interval"
          duration = shortBreak
        } else if cycle < cycles {
          cycle += 1
          title = "专注结束 · 下一轮专注开始"
          body = "\(category)第 \(cycle)/\(cycles) 轮"
          duration = focus
        } else if longBreak > 0 {
          title = "专注结束 · 长休息开始"
          body = "\(category)第 \(group)/\(groups) 组专注已完成"
          phase = "longInterval"
          duration = longBreak
        } else if group < groups {
          group += 1
          cycle = 1
          title = "本组结束 · 下一组专注开始"
          body = "\(category)第 \(group)/\(groups) 组"
          duration = focus
        } else {
          title = "专注结束"
          body = "\(category)番茄钟已完成"
          addNotification(identifier: "\(notificationPrefix)\(index)", title: title, body: body, delay: delay)
          break
        }
      } else if phase == "interval" {
        cycle += 1
        title = "短休息结束 · 专注开始"
        body = "\(category)第 \(cycle)/\(cycles) 轮"
        phase = "running"
        duration = focus
      } else {
        if group < groups {
          group += 1
          cycle = 1
          title = "长休息结束 · 专注开始"
          body = "\(category)第 \(group)/\(groups) 组"
          phase = "running"
          duration = focus
        } else {
          title = "长休息结束"
          body = "\(category)番茄钟已完成"
          addNotification(identifier: "\(notificationPrefix)\(index)", title: title, body: body, delay: delay)
          break
        }
      }
      addNotification(identifier: "\(notificationPrefix)\(index)", title: title, body: body, delay: delay)
    }
    UserDefaults.standard.set(
      Date().addingTimeInterval(TimeInterval(delay)).timeIntervalSince1970,
      forKey: "timer_notifications_expire_at"
    )
  }

  private func integer(_ value: Any?, fallback: Int) -> Int {
    (value as? NSNumber)?.intValue ?? fallback
  }

  private func addNotification(identifier: String, title: String, body: String, delay: Int?) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TIMER"
    let trigger = delay.map {
      UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, $0)), repeats: false)
    }
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    )
  }

  private func clearTimerNotifications(removeDelivered: Bool) {
    scheduleGeneration += 1
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { [weak self] requests in
      guard let self else { return }
      center.removePendingNotificationRequests(
        withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(self.notificationPrefix) }
      )
    }
    if removeDelivered {
      center.getDeliveredNotifications { [weak self] notifications in
        guard let self else { return }
        center.removeDeliveredNotifications(
          withIdentifiers: notifications.map { $0.request.identifier }
            .filter { $0.hasPrefix(self.notificationPrefix) }
        )
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == "STOP_TIMER" {
      if let platformChannel {
        platformChannel.invokeMethod("stopTimer", arguments: nil)
      } else {
        UserDefaults.standard.set("stopTimer", forKey: "pending_notification_action")
      }
    }
    completionHandler()
  }
}
