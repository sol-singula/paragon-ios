import Foundation
import Observation
import UIKit
import UserNotifications

/// Notifications on the iPhone: ask once, hand the APNs token to Paragon
/// (`paragon_device_register`), and paragon-push sends this phone every
/// notification the desktop's bell gets, plus texts to your personal line.
@Observable
@MainActor
final class PushManager {
    static let shared = PushManager()

    enum Status { case unknown, on, off, denied }
    private(set) var status: Status = .unknown
    private(set) var lastError: String?
    @ObservationIgnored private var token: String? = UserDefaults.standard.string(forKey: "paragon.apnsToken")

    var statusText: String {
        switch status {
        case .unknown: return "Checking…"
        case .on: return token == nil ? "Allowed. Waiting for iOS to send a token…" : "On. Missed calls, texts and Atlas reach this phone."
        case .off: return "Tap to turn on."
        case .denied: return "Off in iOS Settings. Tap to open Settings."
        }
    }

    func refreshStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: status = .on
        case .denied: status = .denied
        default: status = .off
        }
    }

    /// After sign-in: ask the first time, and register every launch (the
    /// token can change, and the server moves it to whoever signed in).
    func signedIn() {
        Task {
            await refreshStatus()
            if status == .off { ask() }
            else if status == .on { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func ask() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            await refreshStatus()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func gotToken(_ data: Data) {
        let hex = data.hex
        token = hex
        UserDefaults.standard.set(hex, forKey: "paragon.apnsToken")
        Task {
            do { try await API.registerDevice(token: hex, kind: "alert"); lastError = nil }
            catch { lastError = error.localizedDescription }
        }
    }

    func failed(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// Signing out: this phone stops getting that person's notifications.
    func forgetDevice() async {
        guard let t = token else { return }
        try? await API.unregisterDevice(token: t)
    }

    func refreshBadge() {
        Task { await Badge.refresh(); await AlertsModel.shared.load() }
    }
}
