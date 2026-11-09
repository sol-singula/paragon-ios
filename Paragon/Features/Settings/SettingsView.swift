import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(CallManager.self) private var calls
    @State private var push = PushManager.shared
    @State private var confirmSignOut = false
    @State private var dndOpen = false
    @State private var team = TeamModel.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TopBar(title: "Settings")
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

                    Section(label: "This iPhone") {
                        StatusRow(title: "Notifications", detail: push.statusText, ok: push.status == .on) {
                            if push.status == .denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            else { push.ask() }
                        }
                        StatusRow(title: "Calls ring this phone", detail: calls.ringStatus, ok: calls.ringReady) {
                            calls.signedIn()
                        }
                        // The same Do Not Disturb as Team's moon.
                        Button { dndOpen = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: team.dndOn ? "moon.fill" : "moon")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(team.dndOn ? Theme.amber : Theme.muted)
                                    .frame(width: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Do Not Disturb").font(.ui).foregroundStyle(Theme.text)
                                    Text(team.dndOn ? "On \(TeamTime.label(team.overview?.me.dndUntil))" : "Off. Team chat only; customers still reach you.")
                                        .font(.meta).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                            }
                        }
                        .accessibilityLabel("Do Not Disturb, \(team.dndOn ? "on" : "off")")
                        if !calls.micGranted {
                            StatusRow(title: "Microphone", detail: "Needed to talk on a call. Tap to allow.", ok: false) {
                                calls.askMic()
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section(label: "Notifications") {
                        NavigationLink { NotificationsView().hidesSystemTabBar() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications").font(.ui).foregroundStyle(Theme.text)
                                Text("Texts, calls, Atlas, quiet hours: what tells you and how.")
                                    .font(.meta).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    if session.me?.isFounder == true {
                        Section(label: "Founders") {
                            NavigationLink { CostsView().hidesSystemTabBar() } label: {
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
                .environment(\.defaultMinListHeaderHeight, 0)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .hidesSystemTabBar()
            .sheet(isPresented: $dndOpen) { DndSheet().presentationDetents([.medium, .large]) }
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
