import SwiftUI

/// Atlas on a prospecting conversation (owner, 2026-11-23): Singula's prospecting agents run as Atlas, each
/// following a Mission. The desktop's design 2, the bar above the message box: what Atlas is doing, Interrupt,
/// Back to Atlas and the mission picker. Only for Atlas control (Mason, Ryan, Aaron, Taylor); the server answers
/// nil to anyone else, and the bar is not drawn.
struct AtlasMissionBar: View {
    let threadId: String
    @State private var s: ThreadAtlas?
    @State private var busy = false

    private static let violetText = Color(hex: 0xA78BFA)

    var body: some View {
        Group {
            if let s {
                HStack(alignment: .center, spacing: 10) {
                    AtlasRing(size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        (Text("Atlas ").font(.metaMedium).foregroundColor(Self.violetText)
                         + Text(Self.lead(s)).font(.meta).foregroundColor(s.state == "running" ? Theme.text : Theme.amber))
                        Text(detail(s)).font(.meta).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if s.state == "running" {
                        Button { act("interrupt") } label: {
                            Label("Interrupt", systemImage: "pause.fill").font(.metaMedium)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.violet).disabled(busy)
                    } else if s.state == "handed_off" || s.state == "paused" {
                        Button { act("resume") } label: {
                            Label("Back to Atlas", systemImage: "play.fill").font(.metaMedium)
                        }
                        .buttonStyle(.bordered).tint(Self.violetText).disabled(busy)
                    }
                    if s.state != "done", let ms = s.missions, !ms.isEmpty {
                        Menu {
                            ForEach(ms) { m in
                                Button { if m.id != s.mission?.id { act("mission", m.id) } } label: {
                                    if m.id == s.mission?.id { Label(Self.missionName(m.name), systemImage: "checkmark") }
                                    else { Text(Self.missionName(m.name)) }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle").font(.system(size: 20)).foregroundStyle(Theme.secondary)
                        }
                        .accessibilityLabel("Change the mission")
                        .disabled(busy)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.violet.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.violet.opacity(0.35)))
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
        .task(id: threadId) {
            // The engine's own tables are not in Paragon's realtime: read now, then every 20 seconds while open.
            s = nil
            while !Task.isCancelled {
                do { s = try await API.threadAtlas(threadId) } catch {}
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// A mission's name as the team reads it: Singula's "(Mason 1.8)" tag stays in Singula.
    static func missionName(_ n: String?) -> String {
        guard let n else { return "No mission" }
        let t = n.replacingOccurrences(of: #"\s*\([^)]*\d[^)]*\)\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "No mission" : t
    }

    static func lead(_ s: ThreadAtlas) -> String {
        switch s.state {
        case "running": return "is handling this"
        case "handed_off": return "handed this to you"
        case "paused": return s.status == "human_takeover" ? "stopped: a person is texting them" : "is paused here"
        default: return s.status == "opted_out" ? "stopped: they texted STOP" : "is done here"
        }
    }

    private func detail(_ s: ThreadAtlas) -> String {
        var parts = ["Mission: \(Self.missionName(s.mission?.name))"]
        if s.state == "handed_off", let r = s.reason, !r.isEmpty { parts.append(r) }
        if s.state == "running" {
            if let n = s.next { parts.append("next text \(Stamp.exact(n.at))") }
            else if s.theirTurn == true { parts.append("waiting for their reply") }
            parts.append("texting them pauses it")
        }
        return parts.joined(separator: " · ")
    }

    private func act(_ action: String, _ mission: String? = nil) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let next = try await API.threadAtlasSet(threadId, action: action, mission: mission)
                s = next
                switch action {
                case "interrupt": Toast.shared.show("Atlas stopped. It will not text them until you hand it back.")
                case "resume": Toast.shared.show(next?.theirTurn == true ? "Back to Atlas. It waits for their reply." : "Back to Atlas. It answers them now.")
                default: Toast.shared.show("Mission: \(Self.missionName(next?.mission?.name))")
                }
            } catch {
                Toast.shared.show("Could not change Atlas: \(error.localizedDescription)", error: true)
            }
        }
    }
}
