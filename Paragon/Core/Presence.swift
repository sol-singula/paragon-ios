import Foundation
import Observation
import Supabase

/// Who is online, live, the same way the desktop knows (lib/presence.ts):
/// every open Paragon tracks itself on the one Realtime presence channel
/// `paragon-presence`, keyed by member id, with the person in focus.
/// Nothing is stored. A personal thread is never broadcast.
@Observable
@MainActor
final class Presence {
    static let shared = Presence()

    /// Member ids with Paragon open somewhere right now (you included).
    private(set) var online: Set<String> = []

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listen: Task<Void, Never>?
    @ObservationIgnored private var me: Me?
    @ObservationIgnored private var focus: (id: String?, name: String?) = (nil, nil)
    /// presence key → the ref of the entry we last saw join for it.
    @ObservationIgnored private var refs: [String: String] = [:]

    private struct Viewer: Codable {
        let memberId: String
        let name: String
        let personId: String?
        let personName: String?
        let since: String
    }

    func start(_ me: Me) {
        guard channel == nil else { return }
        self.me = me
        online.insert(me.id)
        if Demo.on { online = Demo.online; return }
        let ch = Supa.client.channel("paragon-presence") { $0.presence.key = me.id }
        channel = ch
        let changes = ch.presenceChange()
        listen = Task { [weak self] in
            for await action in changes {
                guard let self else { return }
                for (key, p) in action.leaves where self.refs[key] == p.ref {
                    self.refs[key] = nil
                    if key != me.id { self.online.remove(key) }
                }
                for (key, p) in action.joins {
                    self.refs[key] = p.ref
                    self.online.insert(key)
                }
            }
        }
        Task {
            try? await ch.subscribeWithError()
            await track()
        }
    }

    func stop() {
        listen?.cancel(); listen = nil
        if let ch = channel { Task { await ch.unsubscribe() } }
        channel = nil
        refs = [:]
        online = []
        me = nil
    }

    /// The conversation on screen (nil when none), as the desktop shares it.
    func focus(personId: String?, name: String?) {
        guard focus.id != personId || focus.name != name else { return }
        focus = (personId, name)
        Task { await track() }
    }

    /// Again after the app comes back to the front.
    func retrack() { Task { await track() } }

    private func track() async {
        guard let ch = channel, let me else { return }
        let v = Viewer(memberId: me.id, name: me.name, personId: focus.id, personName: focus.name,
                       since: ISO8601DateFormatter().string(from: Date()))
        try? await ch.track(v)
    }
}

/// Everyone on the team (paragon_team): photo and whether they're on a call,
/// re-read every 30 seconds while signed in, like the desktop's lib/team.ts.
@Observable
@MainActor
final class TeamStore {
    static let shared = TeamStore()

    private(set) var members: [TeamMember] = []

    var byId: [String: TeamMember] { Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    /// A text's `by` is a member's name: their photo by name.
    func photo(named name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return members.first { $0.name == name }?.photoUrl
    }
    func member(named name: String?) -> TeamMember? {
        guard let name, !name.isEmpty else { return nil }
        return members.first { $0.name == name }
    }

    func load() async {
        if let m = try? await API.team() { members = m }
    }

    func poll() async {
        while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(30)) }
    }
}
