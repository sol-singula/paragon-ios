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

    var me: Me? { if case .ready(let m) = state { return m }; return nil }

    func restore() async {
        do {
            _ = try await Supa.client.auth.session
            await loadMe()
        } catch {
            state = .signedOut
        }
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

    private func loadMe() async {
        do {
            if let me = try await API.me() {
                state = .ready(me)
                PushManager.shared.signedIn()
                CallManager.shared.signedIn()
            } else {
                let email = (try? await Supa.client.auth.session.user.email) ?? ""
                state = .notMember(email: email)
            }
        } catch {
            // A network hiccup at launch is not "signed out": keep trying.
            self.error = Self.friendly(error)
            if case .loading = state { state = .signedOut }
        }
    }

    private static func friendly(_ error: Error) -> String {
        let m = error.localizedDescription
        if m.localizedCaseInsensitiveContains("invalid login") { return "That email and password don't match." }
        if (error as NSError).domain == NSURLErrorDomain { return "Can't reach Paragon. Check your connection." }
        return m
    }
}
