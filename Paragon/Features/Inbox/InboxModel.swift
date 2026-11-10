import Foundation
import Observation

@Observable
@MainActor
final class InboxModel {
    /// One for the app, so the tab bar can show the waiting count.
    static let shared = InboxModel()

    /// Waiting and All (founder, 2026-11-10: no Owed; everything is promises).
    enum Show: Hashable { case waiting, all }

    var show: Show = .waiting
    /// The filter, one choice (founder, 2026-11-10: "All" "Homeowners only"
    /// "Logistics only" or branch specific, All by default), saved on the
    /// person, the same as the desktop's: all | homeowners | logistics |
    /// brand:<brand>.
    private(set) var filter = "all"
    /// My promises (default) or All promises (founder, 2026-11-10: "make sure
    /// i only see my own. (add a filter to be able to see all promises)").
    private(set) var promises = "mine"
    var brand: String? { filter.hasPrefix("brand:") ? String(filter.dropFirst(6)) : nil }
    /// What the chip and the menu call it.
    var filterLabel: String {
        switch filter {
        case "homeowners": return "Homeowners only"
        case "logistics": return "Logistics only"
        default: return brand.map { Branch.of($0).name } ?? "All"
        }
    }
    /// The branches the menu offers: every brand we have, and any a row names.
    static let knownBrands = ["Solara", "Solara One", "Just Glass", "NixThePitch", "solbuild", "BlackSwan"]
    var search = ""

    private(set) var items: [QueueItem] = []
    /// Bumped when something is hidden or put back here (`GoneIDs`), so every
    /// list that reads rows redraws at once.
    var localTick = 0
    private(set) var loaded = false
    private(set) var error: String?

    /// Rows taken off at once (a promise given to someone else), each with
    /// when: kept off until a read that started after it, so a poll already
    /// in flight can't bring the row back.
    private var cleared: [String: Date] = [:]

    /// What the server sent, less what was just cleared here.
    private var visible: [QueueItem] { cleared.isEmpty ? items : items.filter { cleared[$0.personId] == nil } }

    /// One order per tab, no Sort control (founder, 2026-11-09): All is every
    /// conversation, most recent activity first. Waiting is the
    /// server's urgency order (one rule, every client): overdue first, then
    /// the soonest due, promises and cards in among the waiting
    /// conversations. `sort_key` keeps it after any merge; an older server
    /// without it gets its old order, waiting first. The next
    /// conversation after one closes follows this order.
    var shown: [QueueItem] {
        _ = localTick
        let rows = visible
        let base: [QueueItem]
        switch show {
        // Set for later here (a promise added or moved ahead): out of
        // Waiting at once, until something new happens on it.
        case .waiting: base = rows.filter { ($0.status == "waiting" && !LaterMarks.shared.hides($0)) || $0.isAtlas }
        case .all: base = rows
        }
        if show == .all { return recent(base) }
        // Gold first (founder, 2026-11-10: "MOST PRIORITY"), whatever the keys say.
        let gold = base.filter(\.isGold), rest = base.filter { !$0.isGold }
        if rest.contains(where: { $0.sortKey != nil }) {
            // Stable: equal or missing keys keep the server's order.
            return gold + rest.enumerated().sorted { a, b in
                let ka = a.element.sortKey, kb = b.element.sortKey
                if let ka, let kb, ka != kb { return ka.utf16.lexicographicallyPrecedes(kb.utf16) }
                if (ka == nil) != (kb == nil) { return ka != nil }
                return a.offset < b.offset
            }.map(\.element)
        }
        if show == .waiting { return gold + rest.filter { $0.status == "waiting" } + rest.filter { $0.status != "waiting" } }
        return gold + rest
    }

    /// Who is waiting on a reply and how many of them are late ("4 waiting · 1 late").
    var counts: (waiting: Int, late: Int) {
        var waiting = 0, late = 0
        for q in visible where q.status == "waiting" {
            waiting += 1
            if q.tone == .late || (q.dueSource == "clock" && q.isOverdue) { late += 1 }
        }
        return (waiting, late)
    }

    /// The one badge (founder, 2026-11-10: "badge notifications should ONLY
    /// be the total amount of LATE, waiting conversations"): the server's
    /// paragon_badge_count(), the same number as the app icon. Read after
    /// every inbox load (`Badge.refresh`); until then the late count here.
    var lateBadge: Int?
    var badge: Int { lateBadge ?? counts.late }

    var brands: [String] {
        let extra = Set(items.compactMap { $0.firstThread?.brand }).subtracting(Self.knownBrands).sorted()
        return Self.knownBrands + extra
    }

    /// The next conversation opens by itself (founder, 2026-11-09: "as soon
    /// as a conversation closes, we should open the next one in top on the
    /// inbox (however they have filtered)"). When the conversation open from
    /// the inbox leaves the list as filtered (released, closed, handed on,
    /// answered so no longer waiting), it is replaced by the row now on top;
    /// an empty list goes back to the inbox's empty state. One opened from a
    /// notification or search that was never on the list stays.
    private func followOpen(was before: [String]) {
        let router = Router.shared
        guard case .person(let p, _)? = router.inboxPath.last, before.contains(p) else { return }
        let now = shown
        if now.contains(where: { $0.personId == p }) { return }
        if let next = now.first {
            router.inboxPath[router.inboxPath.count - 1] = .person(personId: next.personId, threadId: next.openThread)
        } else {
            router.inboxPath.removeLast()
        }
    }

    private func recent(_ xs: [QueueItem]) -> [QueueItem] {
        xs.sorted { (Stamp.date($0.lastActivityAt) ?? .distantPast) > (Stamp.date($1.lastActivityAt) ?? .distantPast) }
    }

    /// A promise just went to someone else: the conversation leaves my
    /// inbox now (the server hides it from me from here on).
    func clear(personId: String) {
        let before = shown.map(\.personId)
        cleared[personId] = Date()
        followOpen(was: before)
    }

    func load() async {
        let started = Date()
        let asked = (self.filter, show)
        do {
            let rows = try await API.queue(filter: self.filter, search: nil, promises: promises)
            let before = shown.map(\.personId)
            items = rows
            cleared = cleared.filter { $0.value >= started }
            // Only when the filter is the one this read asked for.
            if asked.0 == self.filter && asked.1 == show && loaded { followOpen(was: before) }
            error = nil
            Task { await Badge.refresh() }
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
        // A number (founder, 2026-11-10): the site's search on its 10 digits,
        // and who has it in Paragon (the queue search is names only).
        let digits = LinePick.digits(q)
        async let site = Self.siteHits(digits ?? q)
        async let mine = Self.queueHits(q)
        async let who = Self.lookup(digits)
        let (rows, people, found) = await (site, mine, who)
        guard !Task.isCancelled, q == query else { return }
        let leadNames = Set(rows.filter { $0.type == "lead" }.map { $0.name.lowercased() })
        var out: [SearchHit] = rows + Array(people.filter { !leadNames.contains($0.name.lowercased()) }.prefix(8))
        if let digits, found?.ours != true {
            let threads = found?.threads ?? []
            let talked = found?.personId != nil && !threads.isEmpty
            if talked, let pid = found?.personId, !out.contains(where: { $0.type == "conversation" && $0.id == pid }),
               !leadNames.contains((found?.name ?? "").lowercased()) {
                let t = threads.first
                let sub = [t?.brand.map { Branch.of($0).name }, t?.line].compactMap { $0 }.joined(separator: " · ")
                out.append(SearchHit(id: pid, type: "conversation", name: found?.name ?? LinePick.format(digits),
                                     secondary: sub.isEmpty ? nil : sub, status: nil, statusColor: nil, brand: t?.brand))
            }
            // Nobody has it: one row for the number itself, with Text and Call.
            let client = rows.contains { $0.type == "lead" && ($0.score ?? 0) >= 100 }
            if !talked && !client {
                out.insert(SearchHit(id: digits, type: "number", name: LinePick.format(digits),
                                     secondary: found?.name.map { "\($0) · no conversation yet" } ?? "No conversation yet",
                                     status: nil, statusColor: nil, brand: nil), at: 0)
            }
        }
        hits = out
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

    private static func lookup(_ digits: String?) async -> PhoneLookup? {
        guard let digits else { return nil }
        return (try? await API.phoneLookup(digits)) ?? nil
    }

    private static func siteHits(_ q: String) async -> [SearchHit] {
        let rows = (try? await API.globalSearch(q, limit: 30)) ?? []
        return rows.map { r in
            SearchHit(id: r.id, type: r.resultType, name: r.primaryName ?? "Unnamed",
                      secondary: [r.secondaryInfo, r.extraInfo].compactMap { $0?.isEmpty == false ? $0 : nil }.first,
                      status: r.statusName, statusColor: r.statusColor, brand: nil, score: r.relevanceScore)
        }
    }

    private static func queueHits(_ q: String) async -> [SearchHit] {
        let rows = (try? await API.queue(filter: "all", search: q)) ?? []
        return rows.map { m in
            let brand = m.firstThread?.brand
            let sub = [brand.map { Branch.of($0).name }, m.preview.map(Preview.line)].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            return SearchHit(id: m.personId, type: "conversation", name: m.name, secondary: sub.isEmpty ? nil : sub,
                             status: nil, statusColor: nil, brand: brand)
        }
    }

    /// Every 20 seconds while the inbox is on screen; the task is cancelled
    /// when it isn't.
    // MARK: The person's choices (founder, 2026-11-09: "log whether staff
    // have selected more than just homeowners so that if they update their
    // app, they'll always have the same settings")
    //
    // Tab, branch and homeowners-only live on the member (paragon_ui_prefs).
    // A local copy applies at launch so nothing waits; the server's answer
    // wins when it comes, before the first queue read when it is quick.

    private static let prefsKey = "paragon.ui_prefs.inbox"
    private var prefsRead = false

    private func apply(_ i: UiPrefs.Inbox) {
        filter = i.chosen
        promises = i.promises == "all" ? "all" : "mine"
        show = i.tab == "all" ? .all : .waiting
    }

    private func cache(_ i: UiPrefs.Inbox) {
        if let d = try? JSONEncoder().encode(i) { UserDefaults.standard.set(d, forKey: Self.prefsKey) }
    }

    private var current: UiPrefs.Inbox {
        UiPrefs.Inbox(homeownersOnly: filter == "homeowners", brand: brand, tab: show == .all ? "all" : "waiting", filter: filter, promises: promises)
    }

    /// At launch or sign-in: the local copy now, then the server's.
    func loadPrefs() async {
        if !prefsRead, let d = UserDefaults.standard.data(forKey: Self.prefsKey),
           let i = try? JSONDecoder().decode(UiPrefs.Inbox.self, from: d) { apply(i) }
        prefsRead = true
        if let p = try? await API.uiPrefs(), let i = p.inbox { apply(i); cache(i) }
    }

    /// Waiting / All, picked by the person.
    func choose(show s: Show) {
        show = s
        cache(current)
        save(["tab": s == .all ? "all" : "waiting"])
    }

    /// The filter, picked by the person. The server also writes
    /// homeowners_only and brand for older builds.
    func choose(filter f: String) {
        filter = f
        cache(current)
        save(["filter": f])
        Task { await load() }
    }

    /// Whose promises show on the rows, picked by the person.
    func choose(promises p: String) {
        promises = p
        cache(current)
        save(["promises": p])
        Task { await load() }
    }

    private func save(_ inbox: [String: Any]) {
        Task {
            do { try await API.uiPrefsSet(["inbox": inbox]) }
            catch { Toast.shared.show("Could not save that choice: \(error.localizedDescription)", error: true) }
        }
    }

    func poll() async {
        await loadPrefs()
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
    /// global_search's relevance: 100 is a client whose number is exactly the search.
    var score: Double? = nil

    var key: String { "\(type)-\(id)" }
    /// Something we can text or call: a client, a conversation, or a typed number.
    var isPerson: Bool { type == "lead" || type == "conversation" || type == "number" }

    /// The desktop's groups, in its order.
    struct Group: Hashable { let type: String; let label: String; let symbol: String }
    static let groups: [Group] = [
        Group(type: "number", label: "Number", symbol: "phone"),
        Group(type: "lead", label: "Clients", symbol: "person"),
        Group(type: "conversation", label: "Conversations", symbol: "bubble.left"),
        Group(type: "contractor", label: "Contractors", symbol: "hammer"),
        Group(type: "business", label: "Businesses", symbol: "building.2"),
        Group(type: "user", label: "Team", symbol: "person.2"),
    ]
}
