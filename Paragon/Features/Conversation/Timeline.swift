import SwiftUI

/// A conversation's events, oldest at the top, as the desktop draws them:
/// their texts on the left on the surface colour, ours on the right in teal,
/// Atlas's in violet with its ring, calls as a line across the middle.
struct TimelineList: View {
    let events: [TimelineEvent]
    var scrollKey: Int = 0
    /// Ours on the way out (the Outbox), after everything else.
    var pending: [Outbox.Item] = []
    /// Hold a text to react (founder, 2026-11-11): the reaction goes out as a
    /// text through the Outbox, the same as a reply. Nil when we can't send.
    var react: ((TimelineEvent, String) -> Void)? = nil
    @State private var viewing: ViewedImage?
    /// At (or within a thumb of) the bottom: new things keep us there.
    @State private var pinned = true

    private static let bottomID = "timeline-bottom"
    private static let space = "timeline"

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                                if showDay(i) { DayDivider(at: e.at) }
                                if e.isCall { CallRow(e: e) }
                                else if let r = Reactions.parse(e.body) { ReactionLine(e: e, reaction: r) }
                                else {
                                    TextBubble(e: e, showFace: showFace(i) && !(i == events.count - 1 && !pending.isEmpty),
                                               open: { viewing = ViewedImage(url: $0) }, react: react)
                                }
                            }
                            if !pending.isEmpty && !lastIsToday { DayDivider(at: ISO8601DateFormatter().string(from: Date())) }
                            ForEach(Array(pending.enumerated()), id: \.element.id) { i, p in
                                PendingBubble(item: p, showFace: i == pending.count - 1)
                            }
                        }
                        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
                        // The bottom mark sits under the padding, so "at the
                        // bottom" shows the last message whole, never a sliver
                        // under the composer.
                        Color.clear.frame(height: 1).id(Self.bottomID)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: TimelineBottomY.self, value: g.frame(in: .named(Self.space)).maxY)
                            })
                    }
                }
                .coordinateSpace(name: Self.space)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(TimelineBottomY.self) { y in
                    // How far below the viewport the last message ends.
                    let near = y - outer.size.height < 90
                    if near != pinned { pinned = near }
                }
                .onAppear { settle(proxy) }
                // Always at the bottom (founder, 2026-11-09 and 2026-11-11:
                // "sometimes it's even hiding a message"): on open, and again
                // as the lazy rows find their heights.
                .onChange(of: events.first?.id) { _, _ in settle(proxy) }
                // Something new: stay at the bottom if we were there, or if
                // it is ours.
                .onChange(of: events.last?.id) { _, _ in
                    if pinned || events.last?.isIn == false { settle(proxy, quick: true) }
                }
                .onChange(of: pending.count) { old, new in if new > old { settle(proxy, quick: true) } }
                .onChange(of: scrollKey) { _, _ in settle(proxy, quick: true) }
                // The keyboard coming up, or the composer growing a line: the
                // view gets shorter; whoever was at the bottom stays there.
                .onChange(of: outer.size.height) { old, new in
                    if pinned && new != old { settle(proxy, quick: true) }
                }
                .onChange(of: KeyboardWatcher.shared.visible) { _, up in
                    if up && pinned { settle(proxy, quick: true) }
                }
            }
        }
        .fullScreenCover(item: $viewing) { v in ImageViewer(url: v.url) }
    }

    /// To the bottom now and again as the lazy rows settle (estimated
    /// heights become real ones, a keyboard finishes its animation). No
    /// animation: an animated scroll to a lazy row lands short.
    private func settle(_ proxy: ScrollViewProxy, quick: Bool = false) {
        proxy.scrollTo(Self.bottomID, anchor: .bottom)
        Task { @MainActor in
            for ms in quick ? [60, 250, 500] : [30, 120, 300, 600, 1000, 1600] {
                try? await Task.sleep(for: .milliseconds(ms))
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    /// Who sent a text of ours: Atlas, or the teammate's name.
    private func sender(_ i: Int) -> String? {
        guard events.indices.contains(i) else { return nil }
        let e = events[i]
        guard !e.isCall, !e.isIn else { return nil }
        return e.atlas == true ? "Atlas" : (e.by?.isEmpty == false ? e.by! : "Sent from Quo")
    }

    /// A face beside the last of a run of texts from the same sender.
    private func showFace(_ i: Int) -> Bool {
        guard let s = sender(i) else { return false }
        guard sender(i + 1) == s, let a = Stamp.date(events[i].at), let b = Stamp.date(events[i + 1].at) else { return true }
        return !Calendar.current.isDate(a, inSameDayAs: b)
    }

    private var lastIsToday: Bool {
        guard let d = Stamp.date(events.last?.at) else { return false }
        return Calendar.current.isDateInToday(d)
    }

    private func showDay(_ i: Int) -> Bool {
        guard let d = Stamp.date(events[i].at) else { return false }
        guard i > 0, let p = Stamp.date(events[i - 1].at) else { return true }
        return !Calendar.current.isDate(d, inSameDayAs: p)
    }
}

private struct DayDivider: View {
    let at: String
    private static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f }()
    var body: some View {
        let d = Stamp.date(at)
        let label = d.map { Calendar.current.isDateInToday($0) ? "Today" : Calendar.current.isDateInYesterday($0) ? "Yesterday" : Self.f.string(from: $0) } ?? ""
        Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted).padding(.vertical, 6)
    }
}

struct TextBubble: View {
    let e: TimelineEvent
    var showFace = false
    var open: (URL) -> Void = { _ in }
    /// Hold to react (sends a text, as the desktop's reactions do).
    var react: ((TimelineEvent, String) -> Void)? = nil

    @Environment(TeamStore.self) private var team

    var body: some View {
        let ours = !e.isIn
        let atlas = e.atlas == true
        let hasText = e.body?.isEmpty == false
        let media = e.mediaItems
        HStack(alignment: .bottom, spacing: 5) {
            VStack(alignment: ours ? .trailing : .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    if hasText || media.isEmpty {
                        Text(hasText ? e.body! : "(no text)")
                            .font(.ui)
                            .foregroundStyle(hasText ? Theme.text : Theme.muted)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(media.enumerated()), id: \.offset) { _, m in
                        if let s = m.url, let u = URL(string: s) {
                            if m.isImage {
                                // A photo they texted (or we sent): tap for the whole of it.
                                Button { open(u) } label: {
                                    RemoteImage(url: u, fill: true)
                                        .frame(width: 200, height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo. Tap to view.")
                            } else {
                                Link(destination: u) {
                                    Label(m.name ?? "Attachment", systemImage: "paperclip")
                                        .font(.meta).foregroundStyle(Theme.cyan).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bubble.fill(ours ? (atlas ? Theme.atlasBubble : Theme.outBubble) : Theme.inBubble))
                .contentShape(bubble)
                .contextMenu {
                    if let react, hasText {
                        Section("React (sends a text)") {
                            ForEach(Reactions.quick, id: \.self) { emoji in
                                Button(emoji) { react(e, emoji) }
                            }
                        }
                    }
                    if hasText {
                        Button { UIPasteboard.general.string = e.body } label: { Label("Copy text", systemImage: "doc.on.doc") }
                    }
                }
                HStack(spacing: 4) {
                    if atlas { AtlasRing(size: 10) }
                    Text(meta).font(.system(size: 11)).foregroundStyle(failed ? Theme.rose : Theme.muted)
                }
                .padding(.horizontal, 2)
            }
            if ours {
                // What we sent: the sender's face beside it (Atlas's for Atlas).
                Group {
                    if showFace {
                        if atlas { AtlasFace(size: 20) }
                        else if let m = team.member(named: e.by) { MemberFace(id: m.id, name: m.name, url: m.photoUrl, size: 20, showPresence: false) }
                        else { Face(name: e.by?.isEmpty == false ? e.by! : "Sent from Quo", url: nil, size: 20) }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 20, height: 20)
                .padding(.bottom, 19)
            }
        }
        .frame(maxWidth: .infinity, alignment: ours ? .trailing : .leading)
        .padding(ours ? .leading : .trailing, ours ? 40 : 56)
    }

    /// Rounded 16 with the corner nearest the sender small, as a text
    /// thread draws it.
    private var bubble: UnevenRoundedRectangle {
        let big: CGFloat = 16, small: CGFloat = 5
        return e.isIn
            ? UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: small, bottomTrailingRadius: big, topTrailingRadius: big, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: big, bottomTrailingRadius: small, topTrailingRadius: big, style: .continuous)
    }

    private var failed: Bool { ["failed", "undelivered"].contains(e.status ?? "") }

    private var meta: String {
        // "9:14 am · Mason": the time, then who sent it.
        var parts = [Stamp.exact(e.at)]
        if !e.isIn {
            if e.atlas == true { parts.append("Atlas") }
            else if e.automated == true { parts.append("Automated") }
            else if let by = e.by, !by.isEmpty { parts.append(by.split(separator: " ").first.map(String.init) ?? by) }
        }
        if failed { parts.append("Not delivered") }
        return parts.joined(separator: " · ")
    }
}

/// A text of ours that is still on its way: shown the moment Send is
/// pressed with the local pictures and our face, "Sending…" under it; the
/// usual time and name once it went; rose with "Not sent · Tap to retry"
/// and the reason when it didn't. Delete is in its menu.
struct PendingBubble: View {
    let item: Outbox.Item
    var showFace = true

    @Environment(Session.self) private var session
    @Environment(TeamStore.self) private var team
    @State private var confirmDelete = false

    var body: some View {
        let failed = item.isFailed
        HStack(alignment: .bottom, spacing: 5) {
            VStack(alignment: .trailing, spacing: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    if let r = Reactions.parse(item.body) {
                        // A reaction on its way: the emoji and what it answers.
                        Text("\(r.emoji) to \u{201C}\(Reactions.short(r.quote))\u{201D}").font(.ui).foregroundStyle(Theme.text)
                    } else if !item.body.isEmpty {
                        Text(item.body).font(.ui).foregroundStyle(Theme.text).textSelection(.enabled)
                    }
                    ForEach(item.files) { f in
                        if let img = f.preview {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Label(f.name, systemImage: "paperclip").font(.meta).foregroundStyle(Theme.cyan).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bubble.fill(failed ? Theme.rose.opacity(0.22) : Theme.outBubble))
                .overlay(bubble.stroke(failed ? Theme.rose.opacity(0.7) : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { if failed { Outbox.shared.retry(item) } }
                .contextMenu {
                    if failed {
                        Button { Outbox.shared.retry(item) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    }
                    if !item.body.isEmpty {
                        Button { UIPasteboard.general.string = item.body } label: { Label("Copy text", systemImage: "doc.on.doc") }
                    }
                    if failed {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .confirmationDialog("Delete this text?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { Outbox.shared.delete(item) }
                } message: { Text("It was never sent.") }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(meta).font(.system(size: 11)).foregroundStyle(failed ? Theme.rose : Theme.muted)
                    if let r = item.reason {
                        Text(r).font(.system(size: 11)).foregroundStyle(Theme.rose.opacity(0.85))
                            .multilineTextAlignment(.trailing).lineLimit(3)
                    }
                }
                .padding(.horizontal, 2)
                .onTapGesture { if failed { Outbox.shared.retry(item) } }
            }
            Group {
                if showFace, let me = session.me {
                    if let m = team.byId[me.id] { MemberFace(id: m.id, name: m.name, url: m.photoUrl, size: 20, showPresence: false) }
                    else { Face(name: me.name, url: nil, size: 20) }
                } else {
                    Color.clear
                }
            }
            .frame(width: 20, height: 20)
            .padding(.bottom, 19)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
        .accessibilityElement(children: .combine)
        .accessibilityHint(failed ? "Not sent. Double tap to try again." : "")
    }

    private var bubble: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 5, topTrailingRadius: 16, style: .continuous)
    }

    private var meta: String {
        switch item.state {
        case .queued, .sending: return "Sending…"
        case .sent(_, let at): return [Stamp.exact(at), session.me?.first].compactMap { $0 }.joined(separator: " · ")
        case .failed: return "Not sent · Tap to retry"
        }
    }
}

struct CallRow: View {
    let e: TimelineEvent
    @State private var transcriptOpen = false
    @Environment(TeamStore.self) private var team

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Who took or made it, by their face.
                if let m = team.member(named: e.by) { MemberFace(id: m.id, name: m.name, url: m.photoUrl, size: 18, showPresence: false) }
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.metaMedium).foregroundStyle(color == Theme.rose ? Theme.rose : Theme.secondary)
                Text(Stamp.exact(e.at)).font(.meta).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().strokeBorder(Theme.border))

            if let s = e.summary, !s.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    AtlasRing(size: 12).padding(.top, 3)
                    Text(s).font(.meta).foregroundStyle(Theme.secondary).textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.violet.opacity(0.07)))
            }
            if let t = e.transcript, !t.isEmpty {
                Button { withAnimation(.snappy) { transcriptOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        AtlasRing(size: 10)
                        Text(transcriptOpen ? "Hide transcript" : (e.voicemailUrl != nil ? "Voicemail transcript" : "Transcript"))
                            .font(.metaMedium).foregroundStyle(Theme.violet)
                    }
                }
                .buttonStyle(.plain)
                if transcriptOpen {
                    Text(t).font(.meta).foregroundStyle(Theme.secondary).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var missed: Bool { e.isIn && e.answered != true }
    private var icon: String {
        if e.voicemailUrl != nil { return "recordingtape" }
        if missed { return "phone.down.fill" }
        return e.isIn ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill"
    }
    private var color: Color { missed ? Theme.rose : Theme.cyan }
    private var title: String {
        if e.voicemailUrl != nil { return "Voicemail" }
        if missed { return "Missed call" }
        let d = Stamp.duration(e.duration)
        let who = e.by.map { " · \($0)" } ?? ""
        return (e.isIn ? "Call in" : "Call out") + (d.isEmpty ? "" : " · \(d)") + who
    }
}

private struct TimelineBottomY: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Emoji reactions over SMS, the desktop's `lib/reactions.ts`. SMS has no
/// reactions: a phone (or Quo) sends one as a text quoting the message,
/// iPhone's `Liked “Sounds good”` or Android / Quo's `👍 to “Sounds good”`
/// (with odd spaces round the emoji). We read both, and send ours in the
/// Android / Quo form, which phones show as a reaction.
enum Reactions {
    struct Reaction: Hashable { let emoji: String; let quote: String; let removed: Bool }

    static let quick = ["👍", "❤️", "😂", "😮", "🙏", "👏"]

    private static let words: [String: String] = [
        "liked": "👍", "loved": "❤️", "laughed at": "😂", "emphasized": "‼️", "disliked": "👎", "questioned": "❓",
    ]

    private static func rx(_ p: String, _ ci: Bool = true) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : [])
    }
    private static let removedRx = rx(#"^removed an? (?:.{1,20}) from [“"]([\s\S]*?)[”"]?\s*$"#)
    private static let wordRx = rx(#"^(liked|loved|laughed at|emphasized|disliked|questioned)\s+[“"]([\s\S]*?)[”"]?\s*$"#)
    private static let reactedRx = rx(#"^reacted\s+(\S{1,8})\s+to\s+[“"]([\s\S]*?)[”"]?\s*$"#)
    private static let emojiRx = rx(#"^(\S{1,8})\s+to\s+[“"]([\s\S]*?)[”"]?\s*$"#, false)

    /// Hair, zero-width and no-break spaces read as plain spaces.
    private static func plain(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            let odd = (0x2000...0x200F).contains(v) || (0x2028...0x202F).contains(v) || (0x205F...0x206F).contains(v) || v == 0xFEFF || v == 0x00A0
            out.append(odd ? " " : u)
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func groups(_ r: NSRegularExpression?, _ t: String) -> [String]? {
        guard let r else { return nil }
        let ns = t as NSString
        guard let m = r.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let rg = m.range(at: i)
            return rg.location == NSNotFound ? "" : ns.substring(with: rg)
        }
    }

    private static func isEmoji(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value >= 0x2000) }
    }

    static func parse(_ body: String?) -> Reaction? {
        let t = plain(body ?? "")
        // Every reaction quotes; most texts don't, and skip the patterns.
        guard !t.isEmpty, t.count < 400, t.contains("\u{201C}") || t.contains("\"") else { return nil }
        if let g = groups(removedRx, t) { return Reaction(emoji: "", quote: g[0].trimmingCharacters(in: .whitespaces), removed: true) }
        if let g = groups(wordRx, t), let e = words[g[0].lowercased()] { return Reaction(emoji: e, quote: g[1].trimmingCharacters(in: .whitespaces), removed: false) }
        if let g = groups(reactedRx, t) { return Reaction(emoji: g[0], quote: g[1].trimmingCharacters(in: .whitespaces), removed: false) }
        if let g = groups(emojiRx, t), isEmoji(g[0]) { return Reaction(emoji: g[0], quote: g[1].trimmingCharacters(in: .whitespaces), removed: false) }
        return nil
    }

    /// The text that carries our reaction; a long message is quoted in part.
    static func text(_ emoji: String, _ body: String) -> String {
        let flat = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let q = flat.count > 80 ? String(flat.prefix(77)) + "…" : flat
        return "\u{200A}\u{200B}\(emoji)\u{200B} to \u{201C}\u{200A}\(q)\u{200A}\u{201D} "
    }

    static func short(_ q: String) -> String { q.count > 60 ? String(q.prefix(60)) + "…" : q }
}

/// A reaction in the thread: one quiet line on the sender's side, "👍 They
/// reacted to “…” · 9:14 am" (the desktop's).
struct ReactionLine: View {
    let e: TimelineEvent
    let reaction: Reactions.Reaction

    var body: some View {
        let ours = !e.isIn
        let who = ours ? (e.by?.split(separator: " ").first.map(String.init) ?? "We") : "They"
        let what = reaction.removed ? "removed a reaction from" : "reacted to"
        HStack(spacing: 4) {
            if !reaction.emoji.isEmpty { Text(reaction.emoji).font(.system(size: 15)) }
            Text("\(who) \(what) \u{201C}\(Reactions.short(reaction.quote))\u{201D} · \(Stamp.exact(e.at))")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: ours ? .trailing : .leading)
        .padding(.horizontal, 4).padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
