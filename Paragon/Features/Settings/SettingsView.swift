import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(CallManager.self) private var calls
    @State private var push = PushManager.shared
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let me = session.me {
                    Section {
                        HStack(spacing: 12) {
                            MemberFace(id: me.id, name: me.name, url: nil, size: 40, ring: Theme.card)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(me.name).font(.uiMedium).foregroundStyle(Theme.text)
                                Text([me.email, Role.label(me.role)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.meta).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("This iPhone") {
                    StatusRow(title: "Notifications", detail: push.statusText, ok: push.status == .on) {
                        if push.status == .denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        else { push.ask() }
                    }
                    StatusRow(title: "Calls ring this phone", detail: calls.ringStatus, ok: calls.ringReady) {
                        calls.signedIn()
                    }
                    if !calls.micGranted {
                        StatusRow(title: "Microphone", detail: "Needed to talk on a call. Tap to allow.", ok: false) {
                            calls.askMic()
                        }
                    }
                }
                .listRowBackground(Theme.card)

                if session.me?.isFounder == true {
                    Section("Founders") {
                        NavigationLink { CostsView() } label: {
                            Label("Costs", systemImage: "chart.bar.xaxis").foregroundStyle(Theme.text)
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Text("Lines, people, Atlas, Team chat channels and calling are set up on the desktop app (Settings).")
                        .font(.meta).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.bg)

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
                .listRowBackground(Theme.card)

                Section {
                    Text("Paragon for iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.meta).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.bg)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await push.refreshStatus() }
            .confirmationDialog("Sign out of Paragon?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            } message: {
                Text("This iPhone stops ringing and getting notifications until you sign in again.")
            }
        }
    }
}

private struct StatusRow: View {
    let title: String
    let detail: String
    let ok: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(ok ? Theme.green : Theme.amber).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui).foregroundStyle(Theme.text)
                    Text(detail).font(.meta).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !ok { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted) }
            }
        }
        .disabled(ok)
    }
}
