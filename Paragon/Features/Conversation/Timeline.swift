import SwiftUI

/// A conversation's events, oldest at the top, as the desktop draws them:
/// their texts on the left on the surface colour, ours on the right in teal,
/// Atlas's in violet with its ring, calls as a line across the middle.
struct TimelineList: View {
    let events: [TimelineEvent]
    var scrollKey: Int = 0
    /// Ours on the way out (the Outbox), after everything else.
    var pending: [Outbox.Item] = []
    @State private var viewing: ViewedImage?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                        if showDay(i) { DayDivider(at: e.at) }
                        if e.isCall { CallRow(e: e) } else { TextBubble(e: e, showFace: showFace(i) && !(i == events.count - 1 && !pending.isEmpty), open: { viewing = ViewedImage(url: $0) }) }
                    }
                    if !pending.isEmpty && !lastIsToday { DayDivider(at: ISO8601DateFormatter().string(from: Date())) }
                    ForEach(Array(pending.enumerated()), id: \.element.id) { i, p in
                        PendingBubble(item: p, showFace: i == pending.count - 1)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: events.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: pending.count) { old, new in if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            .onChange(of: scrollKey) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .fullScreenCover(item: $viewing) { v in ImageViewer(url: v.url) }
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
                    if !item.body.isEmpty {
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
