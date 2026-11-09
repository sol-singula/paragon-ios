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
    let onOpen: () -> Void
    let onText: () -> Void
    let onCall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    if hit.type == "conversation" {
                        BranchMark(brand: hit.brand, size: 30)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.hover))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(hit.name).font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
                            if let s = hit.status, !s.isEmpty { StatusChip(name: s, color: StatusChip.color(hit.statusColor)) }
                        }
                        if let sub = hit.secondary, !sub.isEmpty {
                            Text(sub).font(.meta).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 4)
                    if busy { ProgressView().controlSize(.small).tint(Theme.muted) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hit.isPerson {
                ActionPill(symbol: "message.fill", label: "Text", tint: Theme.teal, action: onText)
                    .accessibilityLabel("Text \(hit.name)")
                ActionPill(symbol: "phone.fill", label: "Call", tint: Theme.green, action: onCall)
                    .disabled(callDisabled)
                    .opacity(callDisabled ? 0.4 : 1)
                    .accessibilityLabel("Call \(hit.name)")
            }
        }
        .padding(.vertical, 4)
        .disabled(busy)
    }
}

/// A round action beside a result. Borderless so a List row with three
/// buttons sends each tap to its own.
private struct ActionPill: View {
    let symbol: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.14)))
                .overlay(Circle().strokeBorder(tint.opacity(0.3)))
        }
        .buttonStyle(.borderless)
        .help(label)
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
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
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
