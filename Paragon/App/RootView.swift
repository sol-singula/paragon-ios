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
    @MainActor private var alerts: AlertsModel { AlertsModel.shared }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            if calls.active != nil && !calls.showScreen { CallBar() }
            TabView(selection: $router.tab) {
                InboxView()
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .tag(Router.Tab.inbox)
                PersonalView()
                    .tabItem { Label("Personal", systemImage: "person") }
                    .tag(Router.Tab.personal)
                AlertsView()
                    .tabItem { Label("Alerts", systemImage: "bell") }
                    .badge(alerts.unread)
                    .tag(Router.Tab.alerts)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Router.Tab.settings)
            }
        }
        .task { await alerts.poll() }
    }
}
