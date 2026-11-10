import Foundation
import Security
import Supabase

/// Staying signed in past Supabase's 12-hour session time-box (founder,
/// 2026-11-10: "they should never have to sign in again"). The desktop's
/// `web/src/lib/renew.ts`, same function, same rules.
///
/// The project ends every session 12 hours after sign-in: the refresh is
/// then answered `session_expired`, which is definitive, and the SDK drops
/// the session. This install's device key (paragon-renew, issued after a
/// sign-in, kept in the keychain readable after first unlock so a call that
/// wakes a locked phone still finds it) is traded for a one-time magic-link
/// token, and `verifyOTP` turns that into a brand new session. Only
/// paragon-renew's 401 `device_key_refused` (signed out on this device,
/// removed from Paragon, banned, password changed) is a real sign-out.
enum DeviceKey {
    enum Outcome { case renewed, retry, dead }

    private static let service = "net.solbuild.paragon.devicekey"
    private static let account = "device-key"

    // MARK: Keychain

    static var stored: String? {
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func save(_ key: String) {
        SecItemDelete(base() as CFDictionary)
        var q = base()
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func forget() { SecItemDelete(base() as CFDictionary) }

    private static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    // MARK: paragon-renew

    private static func post(_ body: [String: Any], bearer: String? = nil) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: AppConfig.supabaseURL.appendingPathComponent("functions/v1/paragon-renew"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        return (status, obj)
    }

    @MainActor private static var issuing = false

    /// After a sign-in, and for a session from before this build: make sure
    /// this install holds a key. Quiet on failure; asked again next time.
    @MainActor
    static func ensure() async {
        guard stored == nil, !issuing, let token = Supa.client.auth.currentSession?.accessToken else { return }
        issuing = true
        defer { issuing = false }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard let answer = try? await post(["action": "issue", "platform": "ios", "label": "Paragon iPhone \(build)"], bearer: token),
              answer.0 == 200, let key = answer.1["key"] as? String, stored == nil else { return }
        save(key)
    }

    @MainActor private static var renewing: Task<Outcome, Never>?

    /// The session was refused for good: trade the device key for a new one.
    @MainActor
    static func renew() async -> Outcome {
        if let running = renewing { return await running.value }
        let task = Task<Outcome, Never> { @MainActor in
            guard let key = stored else { return .dead }
            let status: Int
            let obj: [String: Any]
            do { (status, obj) = try await post(["action": "renew", "key": key]) } catch { return .retry }
            if status == 401, obj["code"] as? String == "device_key_refused" {
                print("Paragon device key refused:", obj["why"] as? String ?? "")
                forget()
                return .dead
            }
            guard status == 200, let hash = obj["token_hash"] as? String else { return .retry }
            do {
                try await Supa.client.auth.verifyOTP(tokenHash: hash, type: .magiclink)
                return .renewed
            } catch {
                // A one-time token that did not verify is ours to ask for again.
                return .retry
            }
        }
        renewing = task
        let out = await task.value
        renewing = nil
        return out
    }

    /// Sign out on this device: the key stops working. Best effort.
    static func revoke() async {
        guard let key = stored else { return }
        forget()
        _ = try? await post(["action": "revoke", "key": key])
    }
}
