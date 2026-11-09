import SwiftUI

/// A conversation's events, oldest at the top, as the desktop draws them:
/// their texts on the left on the surface colour, ours on the right in teal,
/// Atlas's in violet with its ring, calls as a line across the middle.
struct TimelineList: View {
    let events: [TimelineEvent]
    var scrollKey: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                        if showDay(i) { DayDivider(at: e.at) }
                        if e.isCall { CallRow(e: e) } else { TextBubble(e: e) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: events.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: scrollKey) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
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
        Text(label).font(.metaMedium).foregroundStyle(Theme.muted).padding(.vertical, 8)
    }
}

struct TextBubble: View {
    let e: TimelineEvent

    var body: some View {
        let ours = !e.isIn
        let atlas = e.atlas == true
        VStack(alignment: ours ? .trailing : .leading, spacing: 3) {
            Text(e.body?.isEmpty == false ? e.body! : "Picture")
                .font(.ui)
                .foregroundStyle(e.body?.isEmpty == false ? Theme.text : Theme.muted)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ours ? (atlas ? Theme.atlasBubble : Theme.outBubble) : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ours ? (atlas ? Theme.violet.opacity(0.35) : Theme.teal.opacity(0.3)) : Theme.border))
            HStack(spacing: 4) {
                if atlas { AtlasRing(size: 10) }
                Text(meta).font(.system(size: 11)).foregroundStyle(failed ? Theme.rose : Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: ours ? .trailing : .leading)
        .padding(ours ? .leading : .trailing, 48)
    }

    private var failed: Bool { ["failed", "undelivered"].contains(e.status ?? "") }

    private var meta: String {
        var parts: [String] = []
        if !e.isIn {
            if e.atlas == true { parts.append("Atlas") }
            else if e.automated == true { parts.append("Automated") }
            else if let by = e.by, !by.isEmpty { parts.append(by) }
        }
        parts.append(Stamp.exact(e.at))
        if failed { parts.append("Not delivered") }
        return parts.joined(separator: " · ")
    }
}

struct CallRow: View {
    let e: TimelineEvent
    @State private var transcriptOpen = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
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
