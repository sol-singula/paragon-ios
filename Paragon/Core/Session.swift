import Foundation
import Observation
import Supabase

/// Signed in, and whether this person is on Paragon. A Solbuild login is not
/// a Paragon member: someone the owner hasn't added is told so plainly.
@Observable
@MainActor
final class Session {
    static let shared = Session()

    enum State: Equatable {
        case loading
        case signedOut
        case notMember(email: String)
        case ready(Me)
    }

    private(set) var state: State = .loading
    private(set) var error: String?
    private(set) var working = false
    /// Supabase isn't answering: the session is kept and we keep trying
    /// (RootView shows "Reconnecting…").
    private(set) var reconnecting = false
    private var watching = false

    var me: Me? { if case .ready(let m) = state { return m }; return nil }

    /// An outage never signs anyone out (founder, 2026-11-09). Only a
    /// definitive answer from the auth server (the refresh token is invalid,
    /// not found or revoked) does; the SDK then drops the stored session.
    /// A network error, a timeout or a 5xx keeps it and we retry with backoff.
    func restore() async {
        watchSignOut()
        var attempt = 0
        while true {
            do {
                _ = try await Supa.client.auth.session
                await loadMe()
                return
            } catch {
                if Supa.client.auth.currentSession == nil || Self.isDefinitiveAuthFailure(error) {
                    reconnecting = false
                    state = .signedOut
                    return
                }
                reconnecting = true
                try? await Task.sleep(for: Self.backoff(attempt))
                attempt += 1
            }
        }
    }

    /// The SDK says signed out only after a definitive answer or Sign out.
    private func watchSignOut() {
        guard !watching else { return }
        watching = true
        Task { [weak self] in
            for await (event, _) in Supa.client.auth.authStateChanges where event == .signedOut {
                guard let self else { return }
                self.reconnecting = false
                self.state = .signedOut
            }
        }
    }

    /// A request to Supabase failed on the network or with a 5xx.
    func noteConnectionTrouble() { reconnecting = true }
    /// A request to Supabase was answered.
    func noteConnected() { if reconnecting { reconnecting = false } }

    /// True only for an auth answer that means the refresh token is dead.
    nonisolated static func isDefinitiveAuthFailure(_ error: Error) -> Bool {
        guard let auth = error as? AuthError else { return false }
        switch auth {
        case .sessionMissing:
            return true
        case .api(_, let code, _, let response):
            guard (400..<500).contains(response.statusCode), response.statusCode != 408, response.statusCode != 429 else { return false }
            let dead: [ErrorCode] = [.refreshTokenNotFound, .refreshTokenAlreadyUsed, .sessionNotFound, .sessionExpired, .userNotFound, .userBanned]
            if dead.contains(code) { return true }
            let m = auth.message.lowercased()
            return m.contains("invalid refresh token") || m.contains("revoked")
        default:
            return false
        }
    }

    /// 1 s, 2 s, 4 s … capped at 30 s.
    nonisolated static func backoff(_ attempt: Int) -> Duration {
        .seconds(min(30, 1 << min(attempt, 5)))
    }

    func signIn(email: String, password: String) async {
        working = true; error = nil
        defer { working = false }
        do {
            try await Supa.client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            await loadMe()
        } catch {
            self.error = Self.friendly(error)
        }
    }

    func signOut() async {
        await PushManager.shared.forgetDevice()
        await CallManager.shared.unregister()
        try? await Supa.client.auth.signOut()
        state = .signedOut
    }

    /// A failed paragon_me is never "signed out" and never "not a member":
    /// keep the session and ask again with backoff.
    private func loadMe() async {
        var attempt = 0
        while true {
            do {
                if let me = try await API.me() {
                    reconnecting = false
                    state = .ready(me)
                    PushManager.shared.signedIn()
                    CallManager.shared.signedIn()
                } else {
                    reconnecting = false
                    let email = Supa.client.auth.currentSession?.user.email ?? ""
                    state = .notMember(email: email)
                }
                return
            } catch {
                if Supa.client.auth.currentSession == nil || Self.isDefinitiveAuthFailure(error) {
                    reconnecting = false
                    state = .signedOut
                    return
                }
                reconnecting = true
                try? await Task.sleep(for: Self.backoff(attempt))
                attempt += 1
            }
        }
    }

    private static func friendly(_ error: Error) -> String {
        let m = error.localizedDescription
        if m.localizedCaseInsensitiveContains("invalid login") { return "That email and password don't match." }
        if (error as NSError).domain == NSURLErrorDomain { return "Can't reach Paragon. Check your connection." }
        return m
    }
}
