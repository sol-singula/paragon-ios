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
        .overlay(alignment: .top) {
            if session.reconnecting {
                HStack(spacing: 6) {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                    Text("Reconnecting…").font(.meta).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                .padding(.top, 6)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityLabel("Reconnecting")
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.reconnecting)
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
    /// The promise sheet the after-call banner opens.
    @State private var followUp: PromiseTarget?

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            if calls.active != nil && !calls.showScreen { CallBar() }
            else if calls.active == nil, let e = calls.ended { CallFollowUpBar(ended: e) { followUp = $0 } }
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
        // "Promised to Ryan · due 9:00 am" and the like.
        .overlay { ToastView() }
        .animation(.easeOut(duration: 0.2), value: calls.ended)
        .sheet(item: $followUp) { t in PromiseSheet(target: t) { _ in Task { await inbox.load() } } }
        .task { await alerts.poll() }
        .task { await inbox.poll() }
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
        // Waiting rows plus the overdue promises that are mine.
        let waiting = inbox.badge
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
