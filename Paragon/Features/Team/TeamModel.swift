import Foundation
import Observation

/// The Team overview (channels, unread and @ counts, people, my DND), read
/// every 15 seconds while signed in and again after anything changes here.
/// `badge` is what the tab shows, as the desktop's sidebar: unread in
/// channels that aren't muted, plus @mentions anywhere.
@Observable
@MainActor
final class TeamModel {
    static let shared = TeamModel()

    private(set) var overview: TeamOverview?
    private(set) var error: String?
    private(set) var loaded = false

    var channels: [TeamChannel] { overview?.channels ?? [] }
    var people: [String: TeamPerson] {
        Dictionary((overview?.people ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var badge: Int {
        channels.reduce(0) { n, c in
            if c.notify == "none" { return n }
            return n + (c.muted || c.notify == "mentions" ? (c.mentions ?? 0) : (c.unread ?? 0))
        }
    }

    /// Someone @mentioned me in a channel I hear from: the tab shows "@".
    var mentioned: Bool {
        channels.contains { $0.notify != "none" && ($0.mentions ?? 0) > 0 }
    }

    var dndOn: Bool { TeamTime.isOn(overview?.me.dndUntil) }

    func channel(_ id: String) -> TeamChannel? { channels.first { $0.id == id } }

    func name(_ id: String) -> String {
        if id == "atlas" { return "Atlas" }
        return people[id]?.name ?? TeamStore.shared.byId[id]?.name ?? "Someone"
    }
    func first(_ id: String) -> String { name(id).split(separator: " ").first.map(String.init) ?? name(id) }
    func photo(_ id: String) -> String? { people[id]?.photoUrl ?? TeamStore.shared.byId[id]?.photoUrl }

    func load() async {
        do {
            overview = try await API.teamChannels()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    func poll() async {
        while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(15)) }
    }

    // MARK: Changes (each re-reads the overview)

    func setPrefs(_ channel: String, _ p: [String: Any]) async {
        do { try await API.teamPrefsSet(channel: channel, p); await load() }
        catch { self.error = "Not saved: \(error.localizedDescription)" }
    }

    func setMine(_ p: [String: Any]) async {
        do { try await API.teamMeSet(p); await load() }
        catch { self.error = "Not saved: \(error.localizedDescription)" }
    }

    func markRead(_ channel: String) async {
        try? await API.teamMarkRead(channel: channel)
        await load()
    }
}
