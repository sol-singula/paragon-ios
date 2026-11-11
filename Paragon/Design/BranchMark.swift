import SwiftUI

/// Whose conversation it is: the branch's code in the branch's colour
/// (owner, 2026-11-06). The same table as the desktop's lib/branches.ts.
struct Branch: Equatable {
    let code: String
    let color: Color
    let name: String
    /// The letters on the solid mark: white, dark on Blackswan's white.
    var ink: Color = .white

    private static let purple = Color(hex: 0xA78BFA)

    static func of(_ brand: String?) -> Branch {
        guard let brand = brand?.trimmingCharacters(in: .whitespaces), !brand.isEmpty else {
            return Branch(code: "·", color: purple, name: "No brand")
        }
        switch brand.lowercased() {
        case "solara one": return Branch(code: "SO", color: Color(hex: 0xEA580C), name: "Solara One")
        case "just glass": return Branch(code: "JG", color: Color(hex: 0x2563EB), name: "Just Glass")
        case "blackswan": return Branch(code: "BS", color: Color(hex: 0xE4E4E7), name: "Blackswan", ink: Color(hex: 0x111111))
        case "nixthepitch": return Branch(code: "NTP", color: purple, name: "NixThePitch")
        case "solbuild": return Branch(code: "SB", color: purple, name: "solbuild")
        case let k where k.hasPrefix("solara"): return Branch(code: "SH", color: Color(hex: 0x16A34A), name: "Solara")
        default:
            let words = brand.split(separator: " ")
            let code = words.count > 1 ? words.compactMap { $0.first }.map(String.init).joined() : String(brand.prefix(2))
            return Branch(code: String(code.prefix(3)).uppercased(), color: purple, name: brand)
        }
    }
}

/// The branch as a solid round mark with its letters on it (the mockup's
/// `.mark`): SO orange, JG blue, SH green, BS white with dark letters.
struct BranchMark: View {
    let brand: String?
    var size: CGFloat = 34

    var body: some View {
        let b = Branch.of(brand)
        Text(b.code)
            .font(.system(size: size * (b.code.count > 2 ? 0.3 : 0.35), weight: .bold))
            .foregroundStyle(b.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(b.color))
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
