import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(CallManager.self) private var calls

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                VStack(spacing: 14) { AtlasRing(size: 28, spinning: true); Text("Paragon").font(.uiMedium).foregroundStyle(Theme.muted) }
            case .signedOut:
                SignInView()
            case .notMember(let email):
                NotMemberView(email: email)
            case .ready:
                MainTabs()
            }
        }
        .task { await session.restore() }
        .fullScreenCover(isPresented: Binding(get: { calls.active != nil && calls.showScreen }, set: { calls.showScreen = $0 })) {
            CallScreen()
        }
    }
}

struct MainTabs: View {
    @Environment(Router.self) private var router
    @Environment(CallManager.self) private var calls
    @Environment(Session.self) private var session
    @MainActor private var alerts: AlertsModel { AlertsModel.shared }
    @MainActor private var team: TeamModel { TeamModel.shared }
    @MainActor private var inbox: InboxModel { InboxModel.shared }
    @MainActor private var keyboard: KeyboardWatcher { KeyboardWatcher.shared }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            if calls.active != nil && !calls.showScreen { CallBar() }
            // The system's bar is hidden on every screen (hidesSystemTabBar);
            // ParagonTabBar below is the one people see.
            TabView(selection: $router.tab) {
                InboxView().hidesSystemTabBar().tag(Router.Tab.inbox)
                PersonalView().hidesSystemTabBar().tag(Router.Tab.personal)
                TeamView().hidesSystemTabBar().tag(Router.Tab.team)
                AlertsView().hidesSystemTabBar().tag(Router.Tab.alerts)
                SettingsView().hidesSystemTabBar().tag(Router.Tab.settings)
            }
            if showsBar {
                ParagonTabBar(items: items, selection: $router.tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsBar)
        .task { await alerts.poll() }
        .task { await team.poll() }
        .task { await TeamStore.shared.poll() }
        .onAppear { if let me = session.me { Presence.shared.start(me) } }
        .onDisappear { Presence.shared.stop() }
    }

    /// The bar steps aside for the keyboard, and inside a conversation with
    /// a customer, which is drawn full height with its composer at the foot.
    private var showsBar: Bool {
        if keyboard.visible { return false }
        switch router.tab {
        case .inbox: return router.inboxPath.isEmpty
        case .personal: return router.personalPath.isEmpty
        default: return true
        }
    }

    private var items: [ParagonTabBar.Item] {
        let waiting = inbox.counts.waiting
        return [
            .init(tab: .inbox, title: "Inbox", symbol: "tray", badge: waiting > 0 ? count(waiting) : nil),
            .init(tab: .personal, title: "Personal", symbol: "person", badge: nil),
            .init(tab: .team, title: "Team", symbol: "bubble.left.and.bubble.right",
                  badge: team.mentioned ? "@" : (team.badge > 0 ? count(team.badge) : nil)),
            .init(tab: .alerts, title: "Alerts", symbol: "bell", badge: alerts.unread > 0 ? count(alerts.unread) : nil),
            .init(tab: .settings, title: "Settings", symbol: "gearshape", badge: nil),
        ]
    }

    private func count(_ n: Int) -> String { n > 99 ? "99+" : "\(n)" }
}
