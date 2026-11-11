import SwiftUI

// The activity feed under the inbox list (founder, 2026-11-10, "Flame sweep"),
// the desktop's ActivityFeed.tsx / lib/feed.ts: rows the system already
// writes (paragon_activity_feed), no model calls, no label, no points. At most
// three cards, newest on top; each stays ten minutes and a fourth pushes the
// oldest off. A card drops in with a bounce, a flash of flame sweeps across
// it, then it is a plain card; still for Reduce Motion. Staff react with an
// emoji, shared with everyone; the emojis keep moving while the card is up
// (long-press one for who). "All activity" lists the last 24 hours.

struct FeedPart: Decodable, Hashable {
    let text: String
    let style: String?
}

struct FeedEvent: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let at: String
    let actorFirstName: String?
    let parts: [FeedPart]
    let reactions: [FeedReaction]?
}

struct FeedReaction: Decodable, Hashable {
    let emoji: String
    let count: Int
    let mine: Bool
    let names: [String]
}

extension API {
    static func activityFeed(since: Date, limit: Int? = nil) async throws -> [FeedEvent] {
        var args: [String: Any?] = ["p_since": API.iso.string(from: since)]
        if let limit { args["p_limit"] = limit }
        return try await rpc("paragon_activity_feed", args, as: [FeedEvent]?.self) ?? []
    }
    static func feedReact(_ id: String, _ emoji: String) async throws -> [FeedReaction] {
        try await rpc("paragon_feed_react", ["p_event_id": id, "p_emoji": emoji], as: [FeedReaction]?.self) ?? []
    }
    static func feedReactions(_ ids: [String]) async throws -> [String: [FeedReaction]] {
        try await rpc("paragon_feed_reactions", ["p_ids": ids], as: [String: [FeedReaction]]?.self) ?? [:]
    }
}

@Observable
@MainActor
final class FeedModel {
    static let shared = FeedModel()

    struct Card: Identifiable, Hashable {
        let ev: FeedEvent
        let until: Date
        let fresh: Bool
        var id: String { ev.id }
    }

    static let maxCards = 3
    static let life: TimeInterval = 10 * 60
    static let quick = ["🔥", "👏", "🎉", "💪", "🙌", "❤️"]
    static let picker = ["👍", "🔥", "👏", "🎉", "💪", "🙌", "❤️", "😂", "😮", "🤯", "🥳", "💯",
                         "⭐", "🚀", "🏆", "💰", "🤑", "💸", "🙏", "😎", "🤝", "👀", "✅", "⚡",
                         "🐐", "👑", "🎯", "🪟", "🏠", "📅", "☀️", "🌮", "🍕", "🥇", "😤", "🫡"]

    private(set) var cards: [Card] = []
    /// False when the server has no feed (an older database): the band is not drawn.
    private(set) var available = true
    private var seen = Set<String>()
    private var newest: Date?
    private var started = false
    /// Shared reactions per event id, for the band and the Activity list.
    private(set) var reactions: [String: [FeedReaction]] = [:]
    private var toggling = Set<String>()

    func reactionsOf(_ id: String) -> [FeedReaction] { reactions[id] ?? [] }

    func takeReactions(_ evs: [FeedEvent]) {
        for e in evs where !toggling.contains(e.id) {
            if let r = e.reactions { reactions[e.id] = r }
        }
    }

    /// Mine on or off: on screen at once, the server's answer replaces it.
    func toggle(_ id: String, _ emoji: String) async {
        let name = Session.shared.me?.name.split(separator: " ").first.map(String.init) ?? "Me"
        let cur = reactions[id] ?? []
        var next = cur
        if let i = next.firstIndex(where: { $0.emoji == emoji }) {
            let r = next[i]
            if r.mine {
                var names = r.names
                if let j = names.lastIndex(of: name) { names.remove(at: j) } else if !names.isEmpty { names.removeLast() }
                if r.count <= 1 { next.remove(at: i) } else { next[i] = FeedReaction(emoji: emoji, count: r.count - 1, mine: false, names: names) }
            } else {
                next[i] = FeedReaction(emoji: emoji, count: r.count + 1, mine: true, names: r.names + [name])
            }
        } else {
            next.append(FeedReaction(emoji: emoji, count: 1, mine: true, names: [name]))
        }
        toggling.insert(id)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { reactions[id] = next }
        do {
            let r = try await API.feedReact(id, emoji)
            toggling.remove(id)
            reactions[id] = r
        } catch {
            toggling.remove(id)
            reactions[id] = cur
        }
    }

    private func refreshReactions() async {
        let ids = cards.map(\.id)
        guard !ids.isEmpty, let map = try? await API.feedReactions(ids) else { return }
        for (id, r) in map where !toggling.contains(id) { reactions[id] = r }
    }

    /// One loop while the band is on screen: reads every 30 s, retires cards every 5 s.
    func run() async {
        var tick = 0
        while !Task.isCancelled && available {
            if tick % 6 == 0 { await load() }
            expire()
            tick += 1
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func load() async {
        let first = !started
        let now = Date()
        let since = first ? now.addingTimeInterval(-Self.life)
            : max(newest ?? now, now.addingTimeInterval(-30)).addingTimeInterval(-120)
        do {
            let evs = try await API.activityFeed(since: since)
            started = true
            takeReactions(evs)
            take(evs, first: first)
            // Reactions on the cards already up (their events are older than `since`).
            await refreshReactions()
        } catch {
            let m = error.localizedDescription.lowercased()
            if m.contains("could not find the function") || m.contains("pgrst202") || m.contains("not a paragon member") {
                available = false
            }
            // Anything else: keep what is on screen and try again next time.
        }
    }

    private func take(_ evs: [FeedEvent], first: Bool) {
        let now = Date()
        let fresh = evs
            .filter { !seen.contains($0.id) }
            .compactMap { e -> (FeedEvent, Date)? in
                guard let at = Stamp.date(e.at) else { return nil }
                return now.timeIntervalSince(at) < (first ? Self.life : 2 * Self.life) ? (e, at) : nil
            }
            .sorted { $0.1 < $1.1 }
            .suffix(Self.maxCards)
        for e in evs {
            seen.insert(e.id)
            if let at = Stamp.date(e.at), at > (newest ?? .distantPast) { newest = at }
        }
        guard !fresh.isEmpty else { return }
        // A new lead on the feed: its gold card is on the server already, so
        // the inbox reads it now (founder, 2026-11-11: "it must pop up instantly").
        if !first, fresh.contains(where: { $0.0.kind == "lead" }) { InboxModel.shared.refreshSoon() }
        var next = cards
        for (e, at) in fresh {
            // On open a card lives out what is left of its ten minutes; a new one gets all ten.
            next.insert(Card(ev: e, until: first ? at.addingTimeInterval(Self.life) : now.addingTimeInterval(Self.life), fresh: !first), at: 0)
        }
        withAnimation(.easeIn(duration: 0.5)) { cards = Array(next.prefix(Self.maxCards)) }
    }

    private func expire() {
        let now = Date()
        guard cards.contains(where: { $0.until <= now }) else { return }
        withAnimation(.easeIn(duration: 0.5)) { cards.removeAll { $0.until <= now } }
    }
}

struct FeedBand: View {
    @State private var model = FeedModel.shared
    @State private var showAll = false

    var body: some View {
        if model.available {
            VStack(spacing: 8) {
                if model.cards.isEmpty {
                    Spacer(minLength: 0)
                    Text("All quiet for now").font(.system(size: 11.5)).foregroundStyle(Theme.muted.opacity(0.6))
                    Spacer(minLength: 0)
                } else {
                    ForEach(model.cards) { c in
                        FeedCardView(card: c)
                            .transition(.asymmetric(insertion: .identity,
                                                    removal: .opacity.combined(with: .offset(y: 40)).combined(with: .scale(scale: 0.94))))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 206)
            .clipped()
            .background(Theme.panel.opacity(0.55))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 0.5) }
            // The 24-hour list: one quiet link (founder, 2026-11-10).
            .overlay(alignment: .bottomTrailing) {
                Button("All activity") { showAll = true }
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .sheet(isPresented: $showAll) { ActivityListView() }
            .task { await model.run() }
            .accessibilityElement(children: .contain)
        }
    }
}

struct FeedCardView: View {
    let card: FeedModel.Card
    var full = false
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var landed: Bool
    @State private var sweep: CGFloat

    init(card: FeedModel.Card, full: Bool = false) {
        self.card = card
        self.full = full
        _landed = State(initialValue: !card.fresh)
        _sweep = State(initialValue: card.fresh ? -1 : 1)
    }

    private var look: (color: Color, symbol: String) {
        switch card.ev.kind {
        case "sale": return (Color(hex: 0xF5B84B), "dollarsign")
        case "install": return (Color(hex: 0xF5B84B), "hammer")
        case "appointment": return (Color(hex: 0x2DD4BF), "calendar.badge.checkmark")
        case "measure": return (Color(hex: 0x2DD4BF), "ruler")
        case "promise_made": return (Color(hex: 0xA78BFA), "hand.raised")
        case "promise_kept": return (Color(hex: 0xA78BFA), "checkmark.seal")
        case "call": return (Color(hex: 0x60A5FA), "phone.arrow.down.left")
        case "lead": return (Color(hex: 0x4ADE80), "person.badge.plus")
        case "canvass": return (Color(hex: 0xFB923C), "door.left.hand.open")
        case "after_hours": return (Color(hex: 0xC4B5FD), "moon")
        default: return (Theme.secondary, "checkmark.seal")
        }
    }

    private var line: AttributedString {
        var out = AttributedString()
        for p in card.ev.parts {
            var a = AttributedString(p.text)
            switch p.style {
            case "b": a.foregroundColor = Theme.text; a.font = .system(size: 12.5, weight: .semibold)
            case "k": a.foregroundColor = look.color; a.font = .system(size: 12.5, weight: .semibold)
            default: a.foregroundColor = Theme.secondary
            }
            out += a
        }
        return out
    }

    var body: some View {
        let k = look
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10).fill(k.color.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay { Image(systemName: k.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(k.color) }
                if let i = card.ev.actorFirstName?.trimmingCharacters(in: .whitespaces).first {
                    Text(String(i).uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.input))
                        .overlay(Circle().stroke(Theme.hover, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line).font(.system(size: 12.5)).lineLimit(full ? nil : 2)
                HStack(spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(ago(ctx.date)).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                    FeedReactionsRow(id: card.ev.id, tint: k.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.hover))
        .overlay {
            // The flame: one bright band crossing the card once.
            GeometryReader { g in
                LinearGradient(colors: [.clear, Color(hex: 0xFB923C, opacity: 0.6), Color(hex: 0xF0616D, opacity: 0.45), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width)
                    .offset(x: sweep * g.size.width)
            }
            .allowsHitTesting(false)
            .blendMode(.plusLighter)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(full ? 0 : 0.25), radius: 9, y: 6)
        .scaleEffect(landed ? 1 : 0.9)
        .offset(y: landed ? 0 : -90)
        .opacity(landed ? 1 : 0)
        .onAppear {
            guard card.fresh, !landed else { return }
            if still { landed = true; sweep = 1; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { landed = true }
            withAnimation(.easeOut(duration: 1.1)) { sweep = 1 }
        }
        .accessibilityElement(children: .combine)
    }

    private func ago(_ now: Date) -> String {
        guard let at = Stamp.date(card.ev.at) else { return "" }
        let s = max(0, now.timeIntervalSince(at))
        if full && s >= 3600 { return at.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        if s < 45 { return "just now" }
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m)m ago" : "\(Int((Double(m) / 60).rounded()))h ago"
    }
}

/// A card's reactions and the React button: a quick row, + for the picker.
/// Long-press a reaction for who. Tapping one toggles mine.
struct FeedReactionsRow: View {
    let id: String
    let tint: Color
    @State private var model = FeedModel.shared
    @State private var picking = false
    @State private var all = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.reactionsOf(id), id: \.emoji) { r in
                Button { Task { await model.toggle(id, r.emoji) } } label: {
                    HStack(spacing: 2) {
                        AnimatedEmoji(emoji: r.emoji)
                        if r.count > 1 { Text("\(r.count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(r.mine ? Theme.text : Theme.secondary) }
                    }
                    .padding(.horizontal, 6).frame(height: 20)
                    .background(Capsule().fill(r.mine ? tint.opacity(0.18) : Theme.input))
                    .overlay(Capsule().strokeBorder(r.mine ? tint.opacity(0.55) : Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Section(r.names.count == 1 ? "Reacted" : "Reacted (\(r.names.count))") {
                        ForEach(Array(r.names.enumerated()), id: \.offset) { _, n in Text(n) }
                    }
                }
                .accessibilityLabel("\(r.emoji) \(r.names.joined(separator: ", "))")
            }
            Button { all = false; picking = true } label: {
                Image(systemName: "face.smiling").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("React")
            .popover(isPresented: $picking) {
                VStack(spacing: 4) {
                    if all {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 8), spacing: 2) {
                            ForEach(FeedModel.picker, id: \.self) { e in pick(e) }
                        }
                    } else {
                        HStack(spacing: 2) {
                            ForEach(FeedModel.quick, id: \.self) { e in pick(e) }
                            Button { all = true } label: {
                                Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("More emoji")
                        }
                    }
                }
                .padding(6)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func pick(_ e: String) -> some View {
        Button { picking = false; Task { await model.toggle(id, e) } } label: {
            Text(e).font(.system(size: 20)).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

/// An emoji that keeps moving while it is on screen: a bounce, a wiggle or a
/// pulse, chosen by the emoji so the same one always moves the same way.
/// Still for Reduce Motion.
struct AnimatedEmoji: View {
    let emoji: String
    @Environment(\.accessibilityReduceMotion) private var still

    private var seed: Int { emoji.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } }

    var body: some View {
        if still {
            Text(emoji).font(.system(size: 12))
        } else {
            TimelineView(.animation) { ctx in
                let kind = seed % 3
                let period = [1.3, 1.7, 1.5][kind]
                let t = (ctx.date.timeIntervalSinceReferenceDate + Double(seed % 9) * 0.17)
                    .truncatingRemainder(dividingBy: period) / period
                let wave = sin(t * 2 * .pi)
                Text(emoji).font(.system(size: 12))
                    .offset(y: kind == 0 ? -3 * max(0, wave) : 0)
                    .rotationEffect(.degrees(kind == 1 ? 11 * wave * (1 - t) : 0), anchor: .init(x: 0.5, y: 0.7))
                    .scaleEffect(kind == 2 ? 1 + 0.09 * (1 - cos(t * 2 * .pi)) : 1)
            }
        }
    }
}

/// Everything from the last 24 hours, newest first, with reactions; react here too.
struct ActivityListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [FeedEvent]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let events {
                    if events.isEmpty {
                        Text("Nothing in the last 24 hours.").font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(events) { e in
                                FeedCardView(card: .init(ev: e, until: .distantFuture, fresh: false), full: true)
                            }
                        }
                        .padding(12)
                    }
                } else if failed {
                    Text("Could not load the activity.").font(.system(size: 13)).foregroundStyle(Theme.rose).padding(.top, 60)
                } else {
                    ProgressView().tint(Theme.muted).padding(.top, 60)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
    }

    private func load() async {
        do {
            let evs = try await API.activityFeed(since: Date().addingTimeInterval(-24 * 3600), limit: 300)
            FeedModel.shared.takeReactions(evs)
            events = evs
            failed = false
        } catch {
            if events == nil { failed = true }
        }
    }
}
