import SwiftUI

/// A teammate's photo (their Solbuild profile picture), else their initials.
struct Face: View {
    let name: String
    let url: String?
    var size: CGFloat = 28

    var body: some View {
        if let s = url, !s.isEmpty, let u = URL(string: s) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Initials(name: name, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityLabel(name)
        } else {
            Initials(name: name, size: size)
        }
    }
}

/// Atlas's face: the solbuild orb as a ring in violet, one flat gradient
/// from light to deep (the desktop's AtlasFace).
struct AtlasFace: View {
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .inset(by: size * 0.17)
            .stroke(LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0x8B5CF6), Color(hex: 0x6D28D9)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: size * 0.156)
            .frame(width: size, height: size)
            .accessibilityLabel("Atlas")
    }
}

/// The red phone: on a call right now.
struct PhoneBadge: View {
    var size: CGFloat = 14
    var ring: Color = Theme.bg

    var body: some View {
        Image(systemName: "phone.fill")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: 0xE5484D)))
            .overlay(Circle().strokeBorder(ring, lineWidth: 2).padding(-2))
            .accessibilityLabel("On a call")
    }
}

/// Bottom right of a face (owner, 2026-11-09): a red phone while they are
/// on a call, else a green dot while they are online, you included.
/// Nothing when they are away.
struct PresenceBadge: View {
    var onCall = false
    var online = false
    var size: CGFloat = 30
    var ring: Color = Theme.bg

    var body: some View {
        if onCall {
            PhoneBadge(size: max(12, size * 0.47), ring: ring)
        } else if online {
            let d = max(8, size * 0.33)
            Circle().fill(Theme.green).frame(width: d, height: d)
                .overlay(Circle().strokeBorder(ring, lineWidth: 2).padding(-2))
                .accessibilityLabel("Online")
        }
    }
}

extension View {
    /// A face with its presence badge in the corner.
    func presence(onCall: Bool, online: Bool, size: CGFloat, ring: Color = Theme.bg) -> some View {
        overlay(alignment: .bottomTrailing) {
            PresenceBadge(onCall: onCall, online: online, size: size, ring: ring).offset(x: 2, y: 2)
        }
    }
}

/// A teammate by member id, with their presence: their photo, or Atlas's
/// face for "atlas". Never a placeholder for a known person.
struct MemberFace: View {
    let id: String
    let name: String
    let url: String?
    var size: CGFloat = 32
    var showPresence = true
    var ring: Color = Theme.bg

    @Environment(Presence.self) private var presence
    @Environment(TeamStore.self) private var team

    var body: some View {
        if id == "atlas" {
            AtlasFace(size: size * 0.62)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.violet.opacity(0.15)))
        } else {
            Face(name: name, url: url ?? team.byId[id]?.photoUrl, size: size)
                .presence(onCall: showPresence && team.byId[id]?.onCall == true,
                          online: showPresence && presence.online.contains(id), size: size, ring: ring)
        }
    }
}
