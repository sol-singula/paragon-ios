import Foundation

/// Values baked into Info.plist from Config/Secrets.xcconfig.
enum AppConfig {
    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.host != nil else {
            fatalError("SUPABASE_URL is missing. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig.")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY is missing. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig.")
        }
        return key
    }()

    static let bundleID = Bundle.main.bundleIdentifier ?? "net.solbuild.paragon"

    /// A debug build is signed for the APNs sandbox, an archived one for
    /// production. The server has to know which host to push to.
    static var apnsEnv: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
