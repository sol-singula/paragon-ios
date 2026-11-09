import SwiftUI

/// Team (owner, 2026-11-09): "something like slack so we can have all of
/// our communications inside the app". The staff's own chat; nothing in it
/// ever reaches a customer. Channels here (founders set who sees which on
/// the desktop, Settings → Team chat), a channel's conversation one tap in.
struct TeamView: View {
    @Environment(Router.self) private var router
    @Environment(TeamStore.self) private var team
    @Environment(Presence.self) private var presence
    @Environment(Session.self) private var session
    @State private var model = TeamModel.shared
    @State private var dndOpen = false

    private var canOpenPersonal: Bool { ["owner", "manager"].contains(session.me?.role ?? "") }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.teamPath) {
            List {
                if !team.members.isEmpty {
                    strip
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let e = model.error {
                    ErrorBanner(message: e) { Task { await model.load() } }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    ForEach(model.channels) { c in
                        NavigationLink(value: c.id) { ChannelRow(c: c) }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.border)
                    }
                } header: {
                    Text("Channels").font(.metaMedium).foregroundStyle(Theme.muted).textCase(nil)
                }
                if model.loaded && model.channels.isEmpty {
                    EmptyNote(title: "You're not in a channel yet", detail: "A founder adds people on the desktop, in Settings → Team chat.", symbol: "number")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dayGlow()
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dndOpen = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: model.dndOn ? "moon.fill" : "moon")
                            if model.dndOn { Text("DND").font(.metaMedium) }
                        }
                        .foregroundStyle(model.dndOn ? Theme.amber : Theme.secondary)
                    }
                    .accessibilityLabel("Do Not Disturb")
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(isPresented: $dndOpen) { DndSheet().presentationDetents([.medium, .large]) }
            .navigationDestination(for: String.self) { id in ChannelView(channelId: id) }
            .overlay { if !model.loaded { ProgressView().tint(Theme.muted) } }
        }
    }

    /// Everyone, with a green dot when they're online and a red phone when
    /// they're on a call (the desktop's rail).
    private var strip: some View {
        let me = session.me?.id
        let sorted = team.members.sorted { a, b in
            if (a.id == me) != (b.id == me) { return a.id == me }
            let ra = a.onCall == true ? 0 : presence.online.contains(a.id) ? 1 : 2
            let rb = b.onCall == true ? 0 : presence.online.contains(b.id) ? 1 : 2
            return ra != rb ? ra < rb : a.name < b.name
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(sorted) { m in
                    let away = m.onCall != true && !presence.online.contains(m.id)
                    VStack(spacing: 4) {
                        MemberFace(id: m.id, name: m.name, url: m.photoUrl, size: 40)
                        Text(m.id == me ? "You" : (m.name.split(separator: " ").first.map(String.init) ?? m.name))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                        if m.onCall == true, let w = m.callWith, !w.isEmpty {
                            Text(w).font(.system(size: 9)).foregroundStyle(Color(hex: 0xE5484D)).lineLimit(1)
                        }
                    }
                    .frame(width: 52)
                    .opacity(away ? 0.5 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Founders and managers: a teammate's face opens their
                        // personal line (founder, 2026-11-09).
                        guard canOpenPersonal else { return }
                        router.openPersonal(of: m.id == me ? nil : LineOf(id: m.id, name: m.name))
                    }
                    .accessibilityHint(canOpenPersonal && m.id != me ? "Opens \(m.name)\u{2019}s personal line" : "")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct ChannelRow: View {
    let c: TeamChannel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "number").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                    .font(c.showsUnread ? .system(size: 15, weight: .semibold) : .ui)
                    .foregroundStyle(c.showsUnread || (c.mentions ?? 0) > 0 ? Theme.text : Theme.secondary)
                    .lineLimit(1)
                if let a = c.about, !a.isEmpty {
                    Text(a).font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if c.quietOrMuted { Image(systemName: "bell.slash").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if let m = c.mentions, m > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "at").font(.system(size: 9, weight: .bold))
                    Text("\(m)").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color(hex: 0xE5484D)))
                .accessibilityLabel("\(m) mention\(m == 1 ? "" : "s")")
            } else if c.showsUnread, let u = c.unread {
                Text(u > 99 ? "99+" : "\(u)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.hover))
            }
        }
        .padding(.vertical, 4)
        .opacity(c.quietOrMuted ? 0.65 : 1)
    }
}
