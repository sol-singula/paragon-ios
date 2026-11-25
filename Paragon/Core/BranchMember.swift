import Foundation
import Observation

/// A branch member (founder, 2026-11-16: Alyssa in Solara UT2) sees only
/// their branch's clients (the server's rule) and never a line: no line or
/// brand labels (marks are plain and numbered, "Conversation 1 / 2"), no
/// "Sends as", no line picker, no New message, no Text or Call on a number
/// nobody has. They reply where the customer already talks with us. The
/// desktop's `lib/branchMember.ts`, read from `paragon_me().branch`. The
/// server enforces all of it; this only keeps the screens honest.
///
/// A branch member with `start_brand` (owner, 2026-11-25: Troy, Solara AZ1,
/// "Just Glass") may start a conversation: New message with the brand fixed
/// and no line shown; `paragon_start_thread` always uses their brand.
@MainActor
enum BranchMember {
    static var on: Bool { Session.shared.me?.branch != nil }
    /// The brand a branch member starts conversations as; nil when they may not start one.
    static var startBrand: String? {
        guard on, let b = Session.shared.me?.startBrand?.trimmingCharacters(in: .whitespaces), !b.isEmpty else { return nil }
        return b
    }
    /// Anyone not a branch member, or a branch member with a start brand.
    static var canStart: Bool { !on || startBrand != nil }
    static let noLinesReason = "You can reply only where they already talk with us"
}

/// Who else has the same street address (founder, 2026-11-16: Trent and
/// Jarvi, the same house, each sent a Just Glass web form): the desktop's
/// `lib/sameAddress.ts`. `paragon_same_address(p_people)` is asked in
/// batches for the rows on screen and kept for three minutes.
struct Twin: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let at: String?
}

@Observable
@MainActor
final class SameAddress {
    static let shared = SameAddress()

    private struct Entry { let at: Date; let twins: [Twin] }
    private var cache: [String: Entry] = [:]
    /// Bumped whenever an answer lands, so rows reading `twins(_:)` redraw.
    private(set) var tick = 0
    @ObservationIgnored private var waiting: Set<String> = []
    @ObservationIgnored private var asking: Set<String> = []
    @ObservationIgnored private var flushing: Task<Void, Never>?
    private static let ttl: TimeInterval = 180

    /// The people at this person's address, from the cache; asks for them
    /// when unknown or stale (the answer redraws whoever read it).
    func twins(_ personId: String?) -> [Twin] {
        _ = tick
        guard let personId, !personId.isEmpty else { return [] }
        let hit = cache[personId]
        if hit == nil || Date().timeIntervalSince(hit!.at) > Self.ttl { want(personId) }
        return hit?.twins ?? []
    }

    /// Ask for these now (the visible inbox rows), in one batch.
    func prefetch(_ ids: [String]) {
        for id in ids where !id.isEmpty {
            if let c = cache[id], Date().timeIntervalSince(c.at) <= Self.ttl { continue }
            want(id)
        }
    }

    private func want(_ id: String) {
        guard !asking.contains(id) else { return }
        waiting.insert(id)
        guard flushing == nil else { return }
        flushing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            await self?.flush()
        }
    }

    private func flush() async {
        while !waiting.isEmpty {
            let ids = Array(waiting.prefix(200))
            ids.forEach { waiting.remove($0); asking.insert($0) }
            let map = (try? await API.sameAddress(ids)) ?? nil
            let now = Date()
            for id in ids {
                cache[id] = Entry(at: now, twins: map?[id] ?? [])
                asking.remove(id)
            }
            tick &+= 1
        }
        flushing = nil
    }
}

extension API {
    /// `paragon_same_address(p_people uuid[])` -> { person_id: [{id, name, at}] }.
    static func sameAddress(_ people: [String]) async throws -> [String: [Twin]]? {
        try await rpc("paragon_same_address", ["p_people": people], as: [String: [Twin]]?.self)
    }
}
