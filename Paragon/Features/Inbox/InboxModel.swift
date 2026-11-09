import Foundation
import Observation

@Observable
@MainActor
final class InboxModel {
    enum Show: Hashable { case waiting, all }
    enum Sort: Hashable { case urgency, recent }

    var show: Show = .waiting
    var sort: Sort = .urgency
    var homeownersOnly = true
    var brand: String?
    var search = ""

    private(set) var items: [QueueItem] = []
    private(set) var deck: AtlasDeck?
    private(set) var loaded = false
    private(set) var error: String?

    /// Waiting first by the clock, then owed; or everything newest first.
    var shown: [QueueItem] {
        let base: [QueueItem]
        if show == .waiting {
            let w = items.filter { $0.status == "waiting" || $0.status == "owed" }
            base = sort == .recent ? recent(w) : w.filter { $0.status == "waiting" } + w.filter { $0.status == "owed" }
        } else {
            base = sort == .recent ? recent(items) : items
        }
        return base
    }

    var counts: (waiting: Int, late: Int) {
        var waiting = 0, late = 0
        for q in items where q.status == "waiting" || q.status == "owed" {
            waiting += 1
            if q.status == "waiting" && q.tone == .late { late += 1 }
        }
        return (waiting, late)
    }

    var brands: [String] {
        Array(Set(items.compactMap { $0.firstThread?.brand })).sorted()
    }

    private func recent(_ xs: [QueueItem]) -> [QueueItem] {
        xs.sorted { (Stamp.date($0.lastActivityAt) ?? .distantPast) > (Stamp.date($1.lastActivityAt) ?? .distantPast) }
    }

    func load() async {
        do {
            let q = search.trimmingCharacters(in: .whitespaces)
            async let queue = API.queue(homeownersOnly: q.isEmpty ? homeownersOnly : false, brand: brand, search: q.isEmpty ? nil : q)
            async let cards = API.atlasCards()
            items = try await queue
            deck = try? await cards
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
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
