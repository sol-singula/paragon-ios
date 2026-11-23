import SwiftUI

/// Settings → Missions (owner, 2026-11-23): what Atlas follows when it texts a prospect. A mission is one of
/// Singula's prospecting agents; a save here is a new version there too. Only for people with Edit missions on
/// (Mason and Ryan): the server sends the texts to nobody else.
struct MissionsView: View {
    @State private var list: [Mission]?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("The team only sees Atlas; the mission is how it talks and when it hands a conversation to a person.")
                    .font(.meta).foregroundStyle(Theme.muted)
            }
            .listRowBackground(Theme.bg)
            if let e = error {
                Section { Text(e).font(.meta).foregroundStyle(Theme.rose) }.listRowBackground(Theme.card)
            }
            if let list {
                Section(label: "Missions") {
                    ForEach(list) { m in
                        NavigationLink { MissionEditor(m: m) { Task { await load() } }.hidesSystemTabBar() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(AtlasMissionBar.missionName(m.name)).font(.uiMedium).foregroundStyle(Theme.text)
                                    if let v = m.version { Text("v\(v)").font(.meta).foregroundStyle(Theme.muted) }
                                    if m.isActive == false { Text("off").font(.meta).foregroundStyle(Theme.muted) }
                                }
                                HStack(spacing: 8) {
                                    Text("\(m.live ?? 0) running").font(.meta).foregroundStyle(Theme.secondary)
                                    if (m.handedOff ?? 0) > 0 { Text("\(m.handedOff!) handed over").font(.meta).foregroundStyle(Theme.amber) }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            } else if error == nil {
                Section { ProgressView().tint(Theme.muted) }.listRowBackground(Theme.bg)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Missions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { list = try await API.missions(); error = nil }
        catch { self.error = "Could not load missions: \(error.localizedDescription)" }
    }
}

private struct MissionEditor: View {
    let m: Mission
    let saved: () -> Void
    @State private var character = ""
    @State private var opener = ""
    @State private var mission = ""
    @State private var persona = ""
    @State private var followup = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    private var dirty: Bool {
        character != (m.characterName ?? "") || opener != (m.opener ?? "") || mission != (m.missionBody ?? "")
            || persona != (m.personaBody ?? "") || followup != (m.followupBody ?? "")
    }

    var body: some View {
        Form {
            field("Who Atlas is", "How it introduces itself", $character, lines: 1)
            field("First text", "[first_name], [business] and [city] are filled in", $opener, lines: 4)
            field("Mission", "The goal, the steps, and when to hand it to a person (HUMAN REVIEW)", $mission, lines: 10)
            field("Voice", "How it writes", $persona, lines: 8)
            field("Follow-ups", "What it says when they go quiet", $followup, lines: 5)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(AtlasMissionBar.missionName(m.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!dirty || busy)
            }
        }
        .onAppear {
            character = m.characterName ?? ""; opener = m.opener ?? ""; mission = m.missionBody ?? ""
            persona = m.personaBody ?? ""; followup = m.followupBody ?? ""
        }
    }

    private func field(_ title: String, _ hint: String, _ text: Binding<String>, lines: Int) -> some View {
        Section {
            TextField(title, text: text, axis: .vertical)
                .lineLimit(lines...max(lines, 20))
                .font(.ui).foregroundStyle(Theme.text)
        } header: {
            Text(title).font(.metaMedium).foregroundStyle(Theme.secondary)
        } footer: {
            Text(hint).font(.meta).foregroundStyle(Theme.muted)
        }
        .listRowBackground(Theme.card)
    }

    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await API.missionSave(m.id, ["character_name": character, "opener": opener, "mission_body": mission,
                                                         "persona_body": persona, "followup_body": followup])
                Toast.shared.show(r.changed == true ? "Saved as version \(r.version ?? "")" : "Nothing changed")
                saved()
                dismiss()
            } catch {
                Toast.shared.show("Could not save it: \(error.localizedDescription)", error: true)
            }
        }
    }
}
