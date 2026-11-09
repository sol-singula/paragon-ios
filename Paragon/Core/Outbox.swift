import Foundation
import Observation
import UIKit

/// A file picked for a text, held in memory until its send uploads it.
struct OutFile: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let data: Data
    let preview: UIImage?
    /// Set once uploaded, so a retry never uploads it twice.
    var uploaded: SharedFile?
}

/// Texts on their way out (founder, 2026-11-09: "the second we hit send, it
/// should go to the conversation so it appears instant in the ui"). Send
/// puts the bubble in its thread at once; the uploads and paragon-send run
/// here, one at a time per thread so rapid sends keep their order, and the
/// store outlives the screen, so leaving mid-send and coming back still
/// shows them. When the timeline brings the real message (same id, or the
/// same words going out within two minutes) the local one steps aside.
/// A send that fails stays, rose, to retry or delete: the text is never lost.
@Observable
@MainActor
final class Outbox {
    static let shared = Outbox()

    enum State: Equatable {
        case queued
        case sending
        case sent(messageId: String?, at: Date)
        case failed(String)
    }

    struct Item: Identifiable {
        let id: UUID
        let threadId: String
        let body: String
        var files: [OutFile]
        let createdAt: Date
        var state: State = .queued
        var startedAt: Date?

        var isFailed: Bool { if case .failed = state { return true }; return false }
        var isSent: Bool { if case .sent = state { return true }; return false }
        var reason: String? { if case .failed(let r) = state { return r }; return nil }
    }

    private(set) var byThread: [String: [Item]] = [:]
    /// Bumped when a send in that thread went: the screen reads the thread again.
    private(set) var settled: [String: Int] = [:]
    private var running: Set<String> = []

    func items(_ thread: String?) -> [Item] {
        guard let thread else { return [] }
        return byThread[thread] ?? []
    }

    func send(thread: String, body: String, files: [OutFile]) {
        let item = Item(id: UUID(), threadId: thread, body: body, files: files, createdAt: Date())
        byThread[thread, default: []].append(item)
        kick(thread)
    }

    func retry(_ item: Item) {
        update(item.threadId, item.id) { $0.state = .queued }
        kick(item.threadId)
    }

    func delete(_ item: Item) {
        byThread[item.threadId]?.removeAll { $0.id == item.id }
    }

    /// Takes away what the timeline now shows for real.
    func reconcile(thread: String, events: [TimelineEvent]) {
        guard let list = byThread[thread], list.contains(where: \.isSent) else { return }
        var used = Set<String>()
        let outs = events.filter { !$0.isCall && !$0.isIn }
        var keep: [Item] = []
        for item in list {
            guard case .sent(let mid, let at) = item.state else { keep.append(item); continue }
            if let mid, outs.contains(where: { $0.id == mid }) { used.insert(mid); continue }
            let from = (item.startedAt ?? item.createdAt).addingTimeInterval(-60)
            let match = outs.first { e in
                guard !used.contains(e.id), (e.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == item.body,
                      let d = Stamp.date(e.at) else { return false }
                return d >= from && d <= at.addingTimeInterval(120)
            }
            if let match { used.insert(match.id); continue }
            // It went; if the timeline still doesn't show it after a few
            // minutes, the timeline is the truth.
            if Date().timeIntervalSince(at) > 180 { continue }
            keep.append(item)
        }
        byThread[thread] = keep.isEmpty ? nil : keep
    }

    // MARK: Sending

    private func update(_ thread: String, _ id: UUID, _ change: (inout Item) -> Void) {
        guard var list = byThread[thread], let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        byThread[thread] = list
    }

    private func kick(_ thread: String) {
        guard !running.contains(thread) else { return }
        running.insert(thread)
        Task {
            while let next = byThread[thread]?.first(where: { $0.state == .queued }) {
                await deliver(next)
            }
            running.remove(thread)
        }
    }

    private func deliver(_ item: Item) async {
        let t = item.threadId
        update(t, item.id) { $0.state = .sending; $0.startedAt = Date() }
        do {
            var shared: [SharedFile] = []
            for f in item.files {
                if let u = f.uploaded { shared.append(u); continue }
                let u = try await Storage.uploadShared(data: f.data, name: f.name, type: f.type)
                update(t, item.id) { it in
                    if let i = it.files.firstIndex(where: { $0.id == f.id }) { it.files[i].uploaded = u }
                }
                shared.append(u)
            }
            // Gone while uploading (deleted): send nothing.
            guard byThread[t]?.contains(where: { $0.id == item.id }) == true else { return }
            let mid = try await API.send(thread: t, body: item.body, attachments: shared, clientId: item.id.uuidString.lowercased())
            // The pictures we hold are what the real message will link to:
            // put them in the cache under those links so nothing reloads.
            for (f, s) in zip(item.files, shared) {
                if let img = f.preview, let u = Self.publicURL(s.path) { await ImageCache.shared.put(u, img) }
            }
            update(t, item.id) { $0.state = .sent(messageId: mid, at: Date()) }
            settled[t, default: 0] += 1
        } catch {
            update(t, item.id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    /// paragon-send's link for a paragon-shared file (encodeURIComponent of
    /// each part; the path holds only letters, digits, `._ ()-`).
    static func publicURL(_ path: String) -> URL? {
        var base = AppConfig.supabaseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let enc = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .encodeURIComponent) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "\(base)/storage/v1/object/public/\(Storage.shared)/\(enc)")
    }
}

private extension CharacterSet {
    static let encodeURIComponent = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
}

// MARK: - Team chat

/// A photo or GIF for a Team post: picked from Photos (uploaded when the
/// post goes) or a GIF the team sent before (copied into the channel).
struct TeamOutFile: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let data: Data?
    let preview: UIImage?
    let existing: TeamAttachment?
    var uploaded: TeamAttachment?
}

/// Team posts on their way out, the same way as texts: shown at once in
/// their channel, posted in order, kept when they fail.
@Observable
@MainActor
final class TeamOutbox {
    static let shared = TeamOutbox()

    enum State: Equatable {
        case queued
        case sending
        case sent(TeamMessage)
        case failed(String)
    }

    struct Item: Identifiable {
        let id: UUID
        let channelId: String
        let body: String
        var files: [TeamOutFile]
        let replyTo: TeamMessage?
        let mentions: [String]
        let createdAt: Date
        var state: State = .queued

        var isFailed: Bool { if case .failed = state { return true }; return false }
        var reason: String? { if case .failed(let r) = state { return r }; return nil }
        var message: TeamMessage? { if case .sent(let m) = state { return m }; return nil }
    }

    private(set) var byChannel: [String: [Item]] = [:]
    private var running: Set<String> = []

    func items(_ channel: String) -> [Item] { byChannel[channel] ?? [] }

    func post(channel: String, body: String, files: [TeamOutFile], replyTo: TeamMessage?, mentions: [String]) {
        let item = Item(id: UUID(), channelId: channel, body: body, files: files, replyTo: replyTo, mentions: mentions, createdAt: Date())
        byChannel[channel, default: []].append(item)
        kick(channel)
    }

    func retry(_ item: Item) {
        update(item.channelId, item.id) { $0.state = .queued }
        kick(item.channelId)
    }

    func delete(_ item: Item) {
        byChannel[item.channelId]?.removeAll { $0.id == item.id }
    }

    /// Posts that went and are now in the channel's own list step aside.
    func reconcile(channel: String, ids: Set<String>) {
        guard let list = byChannel[channel] else { return }
        let keep = list.filter { i in i.message.map { !ids.contains($0.id) } ?? true }
        byChannel[channel] = keep.isEmpty ? nil : keep
    }

    private func update(_ channel: String, _ id: UUID, _ change: (inout Item) -> Void) {
        guard var list = byChannel[channel], let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        byChannel[channel] = list
    }

    private func kick(_ channel: String) {
        guard !running.contains(channel) else { return }
        running.insert(channel)
        Task {
            while let next = byChannel[channel]?.first(where: { $0.state == .queued }) {
                await deliver(next)
            }
            running.remove(channel)
        }
    }

    private func deliver(_ item: Item) async {
        let c = item.channelId
        update(c, item.id) { $0.state = .sending }
        do {
            var atts: [TeamAttachment] = []
            for f in item.files {
                if let u = f.uploaded { atts.append(u); continue }
                let u: TeamAttachment
                if let e = f.existing { u = try await Storage.copyTeam(channel: c, e) }
                else if let d = f.data { u = try await Storage.uploadTeam(channel: c, data: d, name: f.name, type: f.type) }
                else { continue }
                update(c, item.id) { it in
                    if let i = it.files.firstIndex(where: { $0.id == f.id }) { it.files[i].uploaded = u }
                }
                atts.append(u)
            }
            guard byChannel[c]?.contains(where: { $0.id == item.id }) == true else { return }
            let m = try await API.teamPost(channel: c, body: item.body, attachments: atts, replyTo: item.replyTo?.id, mentions: item.mentions)
            for (f, a) in zip(item.files, atts) {
                if let img = f.preview, let u = await Storage.teamURL(a.path) { await ImageCache.shared.put(u, img) }
            }
            update(c, item.id) { $0.state = .sent(m) }
            Task { await TeamModel.shared.load() }
        } catch {
            update(c, item.id) { $0.state = .failed(error.localizedDescription) }
        }
    }
}
