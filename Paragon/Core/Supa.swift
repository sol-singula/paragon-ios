import Foundation
import Supabase

/// The one Supabase client. Only its auth is used: every read and write goes
/// through `API` (plain PostgREST and edge-function requests with the
/// session's token), so the contract is the same `public.paragon_*` functions
/// the desktop app calls, and nothing here depends on the SDK's query builder.
///
/// The session is kept in the keychain by the SDK. That matters for calls: a
/// call can wake the app from nothing, and it has to know who is signed in.
enum Supa {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )

    /// A live access token (the SDK refreshes an expired one).
    static func accessToken() async throws -> String {
        try await client.auth.session.accessToken
    }
}
