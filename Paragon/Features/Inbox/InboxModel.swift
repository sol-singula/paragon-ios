import Foundation
import Observation

@Observable
@MainActor
final class InboxModel {
    /// One for the app, so the tab bar can show the waiting count.
    static let shared = InboxModel()

    enum Show: Hashable { case waiting, owed, all }
    enum Sort: Hashable { case urgency, recent }

    var show: Show = .waiting
    var sort: Sort = .urgency
    var homeownersOnly = true
    var brand: String?
    var search = ""

    private(set) var items: [QueueItem] = []
    private(set) var loaded = false
    private(set) var error: String?

    /// Rows taken off at once (a promise given to someone else), each with
    /// when: kept off until a read that started after it, so a poll already
    /// in flight can't bring the row back.
    private var cleared: [String: Date] = [:]

    /// What the server sent, less what was just cleared here.
    private var visible: [QueueItem] { cleared.isEmpty ? items : items.filter { cleared[$0.personId] == nil } }

    /// The server's order is the urgency order (one rule, every client):
    /// overdue first, then the soonest due, promises and cards in among the
    /// waiting conversations. `sort_key` keeps it after any merge; an older
    /// server without it gets its old order, waiting before owed.
    var shown: [QueueItem] {
        let rows = visible
        let base: [QueueItem]
        switch show {
        case .waiting: base = rows.filter { $0.status == "waiting" || $0.status == "owed" || $0.isAtlas }
        case .owed: base = rows.filter { $0.status == "owed" }
        case .all: base = rows
        }
        if sort == .recent { return recent(base) }
        if base.contains(where: { $0.sortKey != nil }) {
            // Stable: equal or missing keys keep the server's order.
            return base.enumerated().sorted { a, b in
                let ka = a.element.sortKey, kb = b.element.sortKey
                if let ka, let kb, ka != kb { return ka.utf16.lexicographicallyPrecedes(kb.utf16) }
                if (ka == nil) != (kb == nil) { return ka != nil }
                return a.offset < b.offset
            }.map(\.element)
        }
        if show == .waiting { return base.filter { $0.status == "waiting" } + base.filter { $0.status != "waiting" } }
        return base
    }

    /// Who is waiting on a reply, how many of them are late, and how many
    /// replies we owe ("4 waiting · 1 late · 2 owed").
    var counts: (waiting: Int, late: Int, owed: Int) {
        var waiting = 0, late = 0, owed = 0
        for q in visible {
            if q.status == "waiting" {
                waiting += 1
                if q.tone == .late || (q.dueSource == "clock" && q.isOverdue) { late += 1 }
            } else if q.status == "owed" {
                owed += 1
            }
        }
        return (waiting, late, owed)
    }

    /// The Inbox tab's count: the waiting rows plus the overdue promises
    /// that are mine.
    var badge: Int { counts.waiting + visible.reduce(0) { $0 + $1.overdueMine } }

    var brands: [String] {
        Array(Set(items.compactMap { $0.firstThread?.brand })).sorted()
    }

    private func recent(_ xs: [QueueItem]) -> [QueueItem] {
        xs.sorted { (Stamp.date($0.lastActivityAt) ?? .distantPast) > (Stamp.date($1.lastActivityAt) ?? .distantPast) }
    }

    /// A promise just went to someone else: the conversation leaves my
    /// inbox now (the server hides it from me from here on).
    func clear(personId: String) {
        cleared[personId] = Date()
    }

    func load() async {
        let started = Date()
        do {
            items = try await API.queue(homeownersOnly: homeownersOnly, brand: brand, search: nil)
            cleared = cleared.filter { $0.value >= started }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    // MARK: Search (founder, 2026-11-09: "the search bar also doesnt seem to
    // populate anything as far as a large search goes")
    //
    // The desktop's: as you type (2+ characters, 300 ms after the last key)
    // Solbuild's global_search plus the people only Paragon knows
    // (paragon_queue with p_search), a lead that already shows as a
    // conversation listed once.

    private(set) var hits: [SearchHit] = []
    /// A client in the results → their conversation's person, or "" when
    /// nobody has texted them yet ("No texts yet", "Start and call").
    private(set) var conversationOf: [String: String] = [:]
    private(set) var searching = false
    private(set) var searchedFor = ""
    private var searchTask: Task<Void, Never>?

    var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { query.count >= 2 }

    func searchChanged() {
        searchTask?.cancel()
        let q = query
        guard q.count >= 2 else { hits = []; searching = false; searchedFor = ""; return }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        async let site = Self.siteHits(q)
        async let mine = Self.queueHits(q)
        let (rows, people) = await (site, mine)
        guard !Task.isCancelled, q == query else { return }
        let leadNames = Set(rows.filter { $0.type == "lead" }.map { $0.name.lowercased() })
        hits = rows + people.filter { !leadNames.contains($0.name.lowercased()) }.prefix(8)
        searchedFor = q
        searching = false
        await resolveLeads(rows.filter { $0.type == "lead" && (conversationOf[$0.id] ?? "").isEmpty }.prefix(10).map(\.id), for: q)
    }

    /// Whether the first clients shown have a conversation, a few at a time.
    private func resolveLeads(_ ids: [String], for q: String) async {
        guard !ids.isEmpty else { return }
        let found = await withTaskGroup(of: (String, String?).self) { group in
            for id in ids {
                group.addTask {
                    let person: String?
                    do { person = try await API.leadConversation(id) ?? "" } catch { person = nil }
                    return (id, person)
                }
            }
            var out: [(String, String?)] = []
            for await r in group { out.append(r) }
            return out
        }
        guard !Task.isCancelled, q == query else { return }
        for (id, person) in found { if let person { conversationOf[id] = person } }
    }

    /// What is known about a client's conversation: the person, "" for none
    /// yet, nil when not looked up.
    func knownConversation(_ lead: String) -> String? { conversationOf[lead] }

    private static func siteHits(_ q: String) async -> [SearchHit] {
        let rows = (try? await API.globalSearch(q, limit: 30)) ?? []
        return rows.map { r in
            SearchHit(id: r.id, type: r.resultType, name: r.primaryName ?? "Unnamed",
                      secondary: [r.secondaryInfo, r.extraInfo].compactMap { $0?.isEmpty == false ? $0 : nil }.first,
                      status: r.statusName, statusColor: r.statusColor, brand: nil)
        }
    }

    private static func queueHits(_ q: String) async -> [SearchHit] {
        let rows = (try? await API.queue(homeownersOnly: false, brand: nil, search: q)) ?? []
        return rows.map { m in
            let brand = m.firstThread?.brand
            let sub = [brand.map { Branch.of($0).name }, m.preview.map(Preview.line)].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            return SearchHit(id: m.personId, type: "conversation", name: m.name, secondary: sub.isEmpty ? nil : sub,
                             status: nil, statusColor: nil, brand: brand)
        }
    }

    /// Every 20 seconds while the inbox is on screen; the task is cancelled
    /// when it isn't.
    func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(20))
        }
    }
}

/// A search result: a Solbuild row (lead, user, contractor, business) or a
/// Paragon conversation (`type == "conversation"`, `id` is the person).
struct SearchHit: Hashable, Identifiable {
    let id: String
    let type: String
    let name: String
    let secondary: String?
    let status: String?
    let statusColor: String?
    let brand: String?

    var key: String { "\(type)-\(id)" }
    /// A person we can text or call: a client or a conversation.
    var isPerson: Bool { type == "lead" || type == "conversation" }

    /// The desktop's groups, in its order.
    struct Group: Hashable { let type: String; let label: String; let symbol: String }
    static let groups: [Group] = [
        Group(type: "lead", label: "Clients", symbol: "person"),
        Group(type: "conversation", label: "Conversations", symbol: "bubble.left"),
        Group(type: "contractor", label: "Contractors", symbol: "hammer"),
        Group(type: "business", label: "Businesses", symbol: "building.2"),
        Group(type: "user", label: "Team", symbol: "person.2"),
    ]
}
