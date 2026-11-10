import Foundation
import Supabase

/// The one Supabase client. Only its auth is used: every read and write goes
/// through `API` (plain PostgREST and edge-function requests with the
/// session's token), so the contract is the same `public.paragon_*` functions
/// the desktop app calls, and nothing here depends on the SDK's query builder.
///
/// The session is kept in the keychain (`KeychainLocalStorage`, service
/// supabase.gotrue.swift, `kSecAttrAccessibleAfterFirstUnlock`), named here
/// rather than left to the SDK's default so a future default cannot move it
/// and sign everyone out. That matters for calls: a call can wake the app
/// from nothing, locked, and it has to know who is signed in. Supabase
/// time-boxes sessions at 12 hours; `DeviceKey` renews them (Session).
enum Supa {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: .init(storage: KeychainLocalStorage(service: "supabase.gotrue.swift"), autoRefreshToken: true)
        )
    )

    /// A live access token (the SDK refreshes an expired one).
    static func accessToken() async throws -> String {
        try await client.auth.session.accessToken
    }
}
