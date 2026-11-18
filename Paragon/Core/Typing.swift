import Foundation
import Observation
import Supabase

/// Who is typing to whom, live: the desktop's lib/typing.ts (founder,
/// 2026-11-18: "iOS users aren't seeing people typing on mobile nor are Mac or
/// desktop seeing iOS people typing"). One Realtime broadcast channel,
/// `paragon-typing`, event `typing`, payload `{ memberId, name, personId,
/// threadId, on }`, the same on every copy of Paragon; nothing is stored.
/// A teammate typing says so at most every 2.5 s while their box has words in
/// it, and "stopped" when they send or clear it; a word not repeated within
/// 6 s has gone stale. Personal conversations never say anything.
struct Typist: Equatable {
    let memberId: String
    let name: String
    let personId: String
    let threadId: String?
    let at: Date
}

@Observable
@MainActor
final class Typing {
    static let shared = Typing()

    private(set) var typists: [Typist] = []

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listen: Task<Void, Never>?
    @ObservationIgnored private var sweep: Task<Void, Never>?
    @ObservationIgnored private var me: Me?
    @ObservationIgnored private var lastSaid: (key: String, at: Date) = ("", .distantPast)

    private static let sayEvery: TimeInterval = 2.5
    private static let stale: TimeInterval = 6

    private struct Payload: Codable {
        let memberId: String
        let name: String
        let personId: String
        let threadId: String?
        let on: Bool
    }

    func start(_ me: Me) {
        guard channel == nil, !Demo.on else { return }
        self.me = me
        let ch = Supa.client.channel("paragon-typing") { $0.broadcast.receiveOwnBroadcasts = false }
        channel = ch
        let stream = ch.broadcastStream(event: "typing")
        listen = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                // The message carries the payload under "payload"; take the
                // object itself if a version hands the payload over directly.
                let p = message["payload"]?.objectValue ?? message
                self.heard(p)
            }
        }
        sweep = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let now = Date()
                if self.typists.contains(where: { now.timeIntervalSince($0.at) > Self.stale }) {
                    self.typists.removeAll { now.timeIntervalSince($0.at) > Self.stale }
                }
            }
        }
        Task { try? await ch.subscribeWithError() }
    }

    func stop() {
        listen?.cancel(); listen = nil
        sweep?.cancel(); sweep = nil
        if let ch = channel { Task { await ch.unsubscribe() } }
        channel = nil
        typists = []
        me = nil
        lastSaid = ("", .distantPast)
    }

    private func heard(_ p: JSONObject) {
        guard let member = p["memberId"]?.stringValue, member != me?.id,
              let person = p["personId"]?.stringValue, !person.isEmpty else { return }
        let on = p["on"]?.boolValue ?? false
        var rest = typists.filter { $0.memberId != member }
        if on {
            rest.append(Typist(memberId: member, name: p["name"]?.stringValue ?? "Someone", personId: person,
                               threadId: p["threadId"]?.stringValue, at: Date()))
        }
        if rest != typists { typists = rest }
    }

    /// I am typing (or stopped) in this person's conversation.
    func say(personId: String?, threadId: String?, on: Bool) {
        guard let ch = channel, let me, let personId, !personId.isEmpty else { return }
        let key = "\(personId)|\(threadId ?? "")"
        let now = Date()
        if on, lastSaid.key == key, now.timeIntervalSince(lastSaid.at) < Self.sayEvery { return }
        if !on, lastSaid.key != key { return } // never said anything here
        lastSaid = on ? (key, now) : ("", .distantPast)
        let payload = Payload(memberId: me.id, name: me.name, personId: personId, threadId: threadId, on: on)
        Task { try? await ch.broadcast(event: "typing", message: payload) }
    }

    /// Teammates typing to this person right now.
    func on(_ personId: String) -> [Typist] { typists.filter { $0.personId == personId } }

    /// "Ryan is typing" / "Ryan and Aaron are typing" / "3 people are typing".
    static func label(_ names: [String]) -> String {
        let first = names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        switch first.count {
        case 1: return "\(first[0]) is typing"
        case 2: return "\(first[0]) and \(first[1]) are typing"
        default: return "\(first.count) people are typing"
        }
    }
}
