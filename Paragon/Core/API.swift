import Foundation

enum APIError: LocalizedError {
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .server(let m): return m
        case .decoding(let m): return "Paragon sent something this version can't read (\(m))."
        }
    }
}

/// Every Paragon read and write is a `public.paragon_*` function (it checks
/// the caller is a member first). Sending a text and calling go through edge
/// functions, as on the desktop.
enum API {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: Raw requests

    private static func request(_ url: URL, body: [String: Any?]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await Supa.accessToken())", forHTTPHeaderField: "Authorization")
        let clean = body.mapValues { $0 ?? NSNull() }
        req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["error"] as? String) ?? (obj?["message"] as? String)
                ?? String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
                ?? "Paragon didn't answer (\(status))."
            throw APIError.server(msg)
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch let DecodingError.keyNotFound(key, ctx) { throw APIError.decoding("\(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))") }
        catch let DecodingError.typeMismatch(_, ctx) { throw APIError.decoding(ctx.codingPath.map(\.stringValue).joined(separator: ".")) }
        catch let DecodingError.valueNotFound(_, ctx) { throw APIError.decoding(ctx.codingPath.map(\.stringValue).joined(separator: ".")) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    static func rpc<T: Decodable>(_ fn: String, _ args: [String: Any?] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await request(AppConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(fn)"), body: args)
        return try decode(T.self, data)
    }

    /// An rpc whose answer isn't needed (or is void).
    static func call(_ fn: String, _ args: [String: Any?] = [:]) async throws {
        _ = try await request(AppConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(fn)"), body: args)
    }

    static func function<T: Decodable>(_ name: String, query: [String: String] = [:], body: [String: Any?] = [:], as type: T.Type = T.self) async throws -> T {
        var comps = URLComponents(url: AppConfig.supabaseURL.appendingPathComponent("functions/v1/\(name)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let data = try await request(comps.url!, body: body)
        return try decode(T.self, data)
    }

    // MARK: Paragon

    static func me() async throws -> Me? { try await rpc("paragon_me", as: Me?.self) }

    static func queue(homeownersOnly: Bool, brand: String?, search: String?) async throws -> [QueueItem] {
        try await rpc("paragon_queue", ["p_homeowners_only": homeownersOnly, "p_brand": brand, "p_search": search], as: [QueueItem]?.self) ?? []
    }

    static func person(_ person: String, thread: String?) async throws -> PersonView? {
        try await rpc("paragon_person", ["p_person": person, "p_thread": thread], as: PersonView?.self)
    }

    static func personal() async throws -> [PersonalItem] {
        try await rpc("paragon_personal", as: [PersonalItem]?.self) ?? []
    }

    static func personalThread(_ thread: String) async throws -> PersonalThread? {
        try await rpc("paragon_personal_thread", ["p_thread": thread], as: PersonalThread?.self)
    }

    static func notifications() async throws -> [Notice] {
        try await rpc("paragon_notifications", as: [Notice]?.self) ?? []
    }

    static func notificationsRead() async throws { try await call("paragon_notifications_read") }

    static func atlasCards() async throws -> AtlasDeck? { try await rpc("paragon_atlas_cards", as: AtlasDeck?.self) }

    static func atlasCardAct(_ id: String, action: String, due: String? = nil, note: String? = nil) async throws {
        try await call("paragon_atlas_card_act", ["p_id": id, "p_action": action, "p_due": due, "p_note": note, "p_member": nil])
    }

    static func callCard(_ thread: String) async throws -> CallCard? {
        try await rpc("paragon_call_card", ["p_thread": thread], as: CallCard?.self)
    }

    static func send(thread: String, body: String) async throws {
        struct Sent: Decodable { let ok: Bool? }
        _ = try await function("paragon-send", body: ["thread_id": thread, "body": body], as: Sent.self)
    }

    static func voiceToken() async throws -> VoiceToken {
        try await function("paragon-voice", query: ["op": "token", "platform": "ios", "env": AppConfig.apnsEnv], as: VoiceToken.self)
    }

    static func voiceControl(action: String, parent: String) async throws {
        struct Ok: Decodable { let ok: Bool? }
        _ = try await function("paragon-voice", query: ["op": "control"], body: ["action": action, "parent": parent], as: Ok.self)
    }

    static func registerDevice(token: String, kind: String) async throws {
        try await call("paragon_device_register", ["p_token": token, "p_kind": kind, "p_env": AppConfig.apnsEnv, "p_bundle": AppConfig.bundleID])
    }

    static func unregisterDevice(token: String) async throws {
        try await call("paragon_device_unregister", ["p_token": token])
    }
}
