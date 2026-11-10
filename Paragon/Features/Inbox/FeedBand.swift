import SwiftUI

// The activity feed under the inbox list (founder, 2026-11-10, "Flame sweep"),
// the desktop's ActivityFeed.tsx / lib/feed.ts: rows the system already
// writes (paragon_activity_feed), no model calls, no label, no points. At most
// three cards, newest on top; each stays five minutes and a fourth pushes the
// oldest off. A card drops in with a bounce, a flash of flame sweeps across
// it, then it is a plain card; still for Reduce Motion.

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
}

extension API {
    static func activityFeed(since: Date) async throws -> [FeedEvent] {
        try await rpc("paragon_activity_feed", ["p_since": API.iso.string(from: since)], as: [FeedEvent]?.self) ?? []
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
    static let life: TimeInterval = 5 * 60

    private(set) var cards: [Card] = []
    /// False when the server has no feed (an older database): the band is not drawn.
    private(set) var available = true
    private var seen = Set<String>()
    private var newest: Date?
    private var started = false

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
            take(evs, first: first)
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
        var next = cards
        for (e, at) in fresh {
            // On open a card lives out what is left of its five minutes; a new one gets all five.
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
            .task { await model.run() }
            .accessibilityElement(children: .contain)
        }
    }
}

struct FeedCardView: View {
    let card: FeedModel.Card
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var landed: Bool
    @State private var sweep: CGFloat

    init(card: FeedModel.Card) {
        self.card = card
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
                Text(line).font(.system(size: 12.5)).lineLimit(2)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(ago(ctx.date)).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
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
        .shadow(color: .black.opacity(0.25), radius: 9, y: 6)
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
        if s < 45 { return "just now" }
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m)m ago" : "\(Int((Double(m) / 60).rounded()))h ago"
    }
}
