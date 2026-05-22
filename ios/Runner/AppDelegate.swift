import Flutter
import UIKit
import AVFoundation
import UserNotifications

/// Application delegate.
///
/// Phase 1 of the PiP rollout: configure `AVAudioSession` once at launch
/// so playback keeps going when the user backgrounds the app, the screen
/// locks, or the audio routes change. This is also a prerequisite for
/// iOS Picture-in-Picture — the system won't show the floating window
/// unless the active audio session category is `.playback`.
///
/// We also subscribe to `AVAudioSession.interruptionNotification` so
/// playback recovers cleanly after a phone call, a Siri request, an
/// alarm, etc. iOS suspends the audio session during these; the
/// "ended" branch reactivates it if iOS hints `shouldResume`.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    registerForAudioInterruptions()
    // Belt-and-suspenders: explicitly become the notification-center
    // delegate AND call registerForRemoteNotifications on the main
    // thread. The firebase_messaging plugin does this from Dart when
    // requestPermission() runs, but on some devices the Dart-side call
    // arrives too late and iOS skips the APNs handshake on the first
    // boot. Calling it natively here guarantees the system asks for
    // the APNs token before any Flutter code starts executing.
    UNUserNotificationCenter.current().delegate = self
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Logs whatever Apple hands us when APNs registration succeeds.
  /// FlutterAppDelegate forwards this to the firebase_messaging plugin
  /// for us via `super`, so the FCM token resolution kicks off
  /// automatically once this fires.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    NSLog("[Unmu/push] ✅ APNs token received natively: \(hex)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog(
      "[Unmu/push] ❌ APNs registration FAILED: \(error.localizedDescription) " +
      "— check that Push Notifications is enabled on the App ID, the " +
      "provisioning profile includes the entitlement, and you're on a " +
      "real device (not simulator)."
    )
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Audio session setup

  /// Sets the shared `AVAudioSession` to a category appropriate for
  /// long-form video playback:
  ///
  ///   * `.playback` — required for background audio + PiP eligibility.
  ///     Audio keeps going when the screen locks; iOS shows playback
  ///     controls on the lock screen automatically.
  ///   * `.moviePlayback` mode — hints to iOS this is video, not music,
  ///     so the audio focus / routing rules suit the use case.
  ///
  /// We don't pass `.mixWithOthers`: the user expects their video's
  /// audio to take over if they were already listening to Spotify (the
  /// alternative is "tap reel → silent reel because Spotify still
  /// plays", which is worse UX).
  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
      try session.setActive(true, options: [])
    } catch {
      NSLog("[Unmu] AVAudioSession configure failed: \(error.localizedDescription)")
    }
  }

  /// Subscribes to the system interruption notifications. The
  /// `@objc`-tagged selector below is the actual handler.
  private func registerForAudioInterruptions() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  /// Phone call / Siri / alarm started or ended.
  ///
  /// `.began` — system pauses audio for us; Flutter's `video_player`
  ///            also notices via its controller events, so no action
  ///            needed here.
  /// `.ended` — iOS may suggest we resume (via the `shouldResume`
  ///            flag). When it does, reactivate the audio session so
  ///            our player can `play()` again.
  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
    else { return }

    switch type {
    case .began:
      // System pauses audio. Flutter side picks it up via the
      // controller's own state.
      break
    case .ended:
      if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
        if options.contains(.shouldResume) {
          do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
          } catch {
            NSLog("[Unmu] AVAudioSession resume failed: \(error.localizedDescription)")
          }
        }
      }
    @unknown default:
      // New cases added in future iOS — leave alone.
      break
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
