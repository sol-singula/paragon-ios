import Foundation
import UniformTypeIdentifiers

/// A file uploaded to paragon-shared, ready for paragon-send.
struct SharedFile: Hashable {
    let path: String
    let name: String
    let type: String
}

/// Files, through Supabase Storage's own REST endpoints with the session's
/// token (the bucket rules decide, as for the desktop):
///
/// - **paragon-shared** (public): what we send a customer. Quo sends text
///   only, so paragon-send puts each file in the text as a link. Path
///   `<random 20 letters and digits>/<clean filename>`, as the desktop.
/// - **paragon-team** (private): Team photos and GIFs, one folder per channel
///   (`<channel>/<uuid>.<ext>`), read through signed links.
enum Storage {
    static let shared = "paragon-shared"
    static let team = "paragon-team"

    private static func encode(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? String($0) }
            .joined(separator: "/")
    }

    private static func send(_ req: inout URLRequest) async throws -> Data {
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await Supa.accessToken())", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["message"] as? String) ?? (obj?["error"] as? String) ?? "The upload didn't go through (\(status))."
            throw APIError.server(msg)
        }
        return data
    }

    static func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        let url = URL(string: "\(AppConfig.supabaseURL.absoluteString)/storage/v1/object/\(bucket)/\(encode(path))")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("false", forHTTPHeaderField: "x-upsert")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.httpBody = data
        _ = try await send(&req)
    }

    /// A file for a customer: into paragon-shared under a random folder.
    static func uploadShared(data: Data, name: String, type: String) async throws -> SharedFile {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let folder = String((0..<20).map { _ in letters.randomElement()! })
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._ ()-")
        var clean = String(String.UnicodeScalarView(name.unicodeScalars.map { allowed.contains($0) ? $0 : "_" }))
        if clean.count > 80 { clean = String(clean.suffix(80)) }
        if clean.isEmpty { clean = "file" }
        let path = "\(folder)/\(clean)"
        try await upload(bucket: shared, path: path, data: data, contentType: type)
        return SharedFile(path: path, name: name.isEmpty ? clean : name, type: type)
    }

    static let teamMax = 10 * 1024 * 1024
    static let teamTypes = ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif"]

    /// A photo or GIF for a Team channel.
    static func uploadTeam(channel: String, data: Data, name: String, type: String) async throws -> TeamAttachment {
        guard teamTypes.contains(type) else { throw APIError.server("\(name) is not a photo or GIF.") }
        guard data.count <= teamMax else { throw APIError.server("\(name) is over 10 MB.") }
        let ext = UTType(mimeType: type)?.preferredFilenameExtension ?? (type.split(separator: "/").last.map(String.init) ?? "img")
        let path = "\(channel)/\(UUID().uuidString.lowercased()).\(ext)"
        try await upload(bucket: team, path: path, data: data, contentType: type)
        let px = ImageInfo.pixelSize(data)
        return TeamAttachment(path: path, name: name, type: type, size: data.count, width: px.map { Double($0.width) }, height: px.map { Double($0.height) })
    }

    /// A GIF from another channel, copied into this one so everyone here can see it.
    static func copyTeam(channel: String, _ a: TeamAttachment) async throws -> TeamAttachment {
        if a.path.hasPrefix("\(channel)/") { return a }
        let ext = a.path.split(separator: ".").last.map(String.init) ?? "gif"
        let to = "\(channel)/\(UUID().uuidString.lowercased()).\(ext)"
        var req = URLRequest(url: URL(string: "\(AppConfig.supabaseURL.absoluteString)/storage/v1/object/copy")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["bucketId": team, "sourceKey": a.path, "destinationKey": to])
        _ = try await send(&req)
        return TeamAttachment(path: to, name: a.name, type: a.type, size: a.size, width: a.width, height: a.height)
    }

    // MARK: Signed links for the private Team bucket, kept for 50 minutes

    private static let cache = SignedCache()

    static func teamURL(_ path: String) async -> URL? {
        if let hit = await cache.get(path) { return hit }
        var req = URLRequest(url: URL(string: "\(AppConfig.supabaseURL.absoluteString)/storage/v1/object/sign/\(team)/\(encode(path))")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["expiresIn": 3600])
        guard let data = try? await send(&req),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let signed = (obj["signedURL"] as? String) ?? (obj["signedUrl"] as? String) else { return nil }
        let full = signed.hasPrefix("http") ? signed : "\(AppConfig.supabaseURL.absoluteString)/storage/v1\(signed.hasPrefix("/") ? "" : "/")\(signed)"
        guard let url = URL(string: full) else { return nil }
        await cache.put(path, url)
        return url
    }
}

private actor SignedCache {
    private var map: [String: (url: URL, until: Date)] = [:]
    func get(_ k: String) -> URL? {
        guard let hit = map[k], hit.until > Date() else { return nil }
        return hit.url
    }
    func put(_ k: String, _ u: URL) { map[k] = (u, Date().addingTimeInterval(50 * 60)) }
}

/// What a picked file is: its MIME type and a file name.
enum FileKind {
    static func mime(for type: UTType?) -> String {
        type?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Sniffs the bytes when the picker didn't say (GIF, PNG, JPEG, HEIC, WebP).
    static func sniff(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 4 else { return nil }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "image/gif" }
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "image/png" }
        if b[0] == 0xFF, b[1] == 0xD8 { return "image/jpeg" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "image/webp" }
        if b.count >= 12, String(bytes: b[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            if ["heic", "heix", "hevc", "mif1", "msf1"].contains(brand) { return "image/heic" }
        }
        return nil
    }
}
