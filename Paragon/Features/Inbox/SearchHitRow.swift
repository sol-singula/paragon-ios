import SwiftUI

/// One search result: the group's glyph, the name, its second line and the
/// client's status, with Text and Call on a person (founder, 2026-11-09:
/// "when a name comes up we should be able to click something to open the
/// conversation to text, or a quick call button"). Tapping the row opens it.
struct SearchHitRow: View {
    let hit: SearchHit
    let symbol: String
    var busy = false
    var callDisabled = false
    /// A client nobody has texted yet: "No texts yet", and Call reads
    /// "Start and call".
    var neverTexted = false
    let onOpen: () -> Void
    let onText: () -> Void
    let onCall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    if hit.type == "conversation" || hit.brand != nil {
                        BranchMark(brand: hit.brand, size: 34)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.hover))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name).font(.name).foregroundStyle(Theme.text).lineLimit(1)
                        HStack(spacing: 5) {
                            let sub = neverTexted ? "No texts yet" : hit.secondary
                            if let sub, !sub.isEmpty {
                                Text(sub).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.tail)
                            }
                            if let s = hit.status, !s.isEmpty {
                                if let sub, !sub.isEmpty { Text("·").font(.system(size: 14)).foregroundStyle(Theme.muted) }
                                StatusChip(name: s, color: StatusChip.color(hit.statusColor)).layoutPriority(1)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    if busy { ProgressView().controlSize(.small).tint(Theme.muted) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hit.isPerson {
                // Icons only (founder, 2026-11-10), so the name keeps the width.
                HStack(spacing: 6) {
                    IconCircleButton(symbol: "message", action: onText)
                        .accessibilityLabel("Text \(hit.name)")
                    IconCircleButton(symbol: "phone", tone: .call, action: onCall)
                        .disabled(callDisabled)
                        .opacity(callDisabled ? 0.4 : 1)
                        .accessibilityLabel(neverTexted ? "Start a conversation with \(hit.name) and call" : "Call \(hit.name)")
                }
                .fixedSize()
            }
        }
        .disabled(busy)
    }
}

/// A round, icon-only Text or Call on a search result.
struct IconCircleButton: View {
    enum Tone { case plain, call }
    let symbol: String
    var tone: Tone = .plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone == .call ? Theme.green : Theme.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tone == .call ? Theme.green.opacity(0.16) : Theme.hover))
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
    }
}

/// A Nexus status (New lead, Sold…) in its own colour, quietly.
struct StatusChip: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.tag)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.16)))
    }

    /// "#22C55E" (or "22C55E"); anything else is muted.
    static func color(_ s: String?) -> Color {
        guard var h = s?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return Theme.secondary }
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return Theme.secondary }
        return Color(hex: v)
    }
}
