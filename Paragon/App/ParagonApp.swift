import SwiftUI

@main
struct ParagonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase

    init() {
        // The desktop's chrome rail colour under the tabs and the titles.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.panel)
        tab.shadowColor = UIColor(Theme.border)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.shadowColor = UIColor(Theme.border)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Session.shared)
                .environment(Router.shared)
                .environment(CallManager.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
        .onChange(of: phase) { _, now in
            if now == .active { PushManager.shared.refreshBadge() }
        }
    }
}
