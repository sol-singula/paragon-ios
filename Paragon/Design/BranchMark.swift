import SwiftUI

/// Whose conversation it is: the branch's code in the branch's colour
/// (owner, 2026-11-06). The same table as the desktop's lib/branches.ts.
struct Branch: Equatable {
    let code: String
    let color: Color
    let name: String

    private static let purple = Color(hex: 0xA78BFA)

    static func of(_ brand: String?) -> Branch {
        guard let brand = brand?.trimmingCharacters(in: .whitespaces), !brand.isEmpty else {
            return Branch(code: "·", color: purple, name: "No brand")
        }
        switch brand.lowercased() {
        case "solara one": return Branch(code: "SO", color: Color(hex: 0xF97316), name: "Solara One")
        case "just glass": return Branch(code: "JG", color: Color(hex: 0x3B82F6), name: "Just Glass")
        case "blackswan": return Branch(code: "BS", color: Color(hex: 0xF4F4F5), name: "Blackswan")
        case "nixthepitch": return Branch(code: "NTP", color: purple, name: "NixThePitch")
        case "solbuild": return Branch(code: "SB", color: purple, name: "solbuild")
        case let k where k.hasPrefix("solara"): return Branch(code: "SH", color: Color(hex: 0x22C55E), name: "Solara Home")
        default:
            let words = brand.split(separator: " ")
            let code = words.count > 1 ? words.compactMap { $0.first }.map(String.init).joined() : String(brand.prefix(2))
            return Branch(code: String(code.prefix(3)).uppercased(), color: purple, name: brand)
        }
    }
}

struct BranchMark: View {
    let brand: String?
    var size: CGFloat = 32

    var body: some View {
        let b = Branch.of(brand)
        Text(b.code)
            .font(.system(size: size * (b.code.count > 2 ? 0.3 : 0.36), weight: .bold, design: .rounded))
            .foregroundStyle(b.color)
            .frame(width: size, height: size)
            .background(Circle().fill(b.color.opacity(0.14)))
            .overlay(Circle().strokeBorder(b.color.opacity(0.55), lineWidth: 1.2))
            .accessibilityLabel(b.name)
    }
}

/// A small chip: the branch's code and name, for the conversation header.
struct BranchChip: View {
    let brand: String?
    var state: String?
    var selected = false
    var waiting = false

    var body: some View {
        let b = Branch.of(brand)
        HStack(spacing: 5) {
            Circle().fill(b.color).frame(width: 6, height: 6)
            Text([b.name, state].compactMap { $0 }.joined(separator: " · "))
                .font(.metaMedium)
                .foregroundStyle(selected ? Theme.text : Theme.secondary)
            if waiting { Circle().fill(Theme.rose).frame(width: 5, height: 5) }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(selected ? Theme.hover : Color.clear))
        .overlay(Capsule().strokeBorder(selected ? b.color.opacity(0.6) : Theme.border, lineWidth: 1))
    }
}
