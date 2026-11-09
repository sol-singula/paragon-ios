import SwiftUI
import Observation
import UserNotifications

/// The desktop's bell: missed calls, a clock running out, Atlas's cards,
/// promises. The same rows paragon-push sends to the lock screen.
@Observable
@MainActor
final class AlertsModel {
    static let shared = AlertsModel()
    private(set) var items: [Notice] = []
    private(set) var error: String?

    var unread: Int { items.filter { $0.read != true }.count }

    func load() async {
        do {
            items = try await API.notifications()
            error = nil
            UNBadge.set(unread)
        } catch { self.error = error.localizedDescription }
    }

    func markRead() async {
        guard unread > 0 else { return }
        try? await API.notificationsRead()
        await load()
    }

    func poll() async {
        while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(30)) }
    }
}

enum UNBadge {
    static func set(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(n) { _ in }
    }
}

struct AlertsView: View {
    @Environment(Router.self) private var router
    @State private var model = AlertsModel.shared

    var body: some View {
        NavigationStack {
            List {
                if let e = model.error {
                    ErrorBanner(message: e) { Task { await model.load() } }.listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
                ForEach(model.items) { n in
                    Button { open(n) } label: { AlertRow(n: n) }
                        .listRowBackground(n.read == true ? Theme.bg : Theme.card.opacity(0.6))
                        .listRowSeparatorTint(Theme.border)
                }
                if model.items.isEmpty {
                    EmptyNote(title: "No notifications", symbol: "bell.slash").listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.unread > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { Task { await model.markRead() } }.font(.metaMedium).tint(Theme.cyan)
                    }
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }

    private func open(_ n: Notice) {
        if let p = n.personId { router.open(.person(personId: p, threadId: n.threadId)) }
    }
}

struct AlertRow: View {
    let n: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(n.title).font(n.read == true ? .ui : .uiMedium).foregroundStyle(Theme.text).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(Stamp.when(n.createdAt)).font(.meta).foregroundStyle(Theme.muted)
                }
                if let b = n.body, !b.isEmpty { Text(b).font(.meta).foregroundStyle(Theme.secondary).lineLimit(3) }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var icon: some View {
        if n.kind.hasPrefix("atlas") || n.kind.hasPrefix("promise") {
            AtlasRing(size: 20)
        } else if n.kind == "call.missed" {
            Image(systemName: "phone.down.fill").foregroundStyle(Theme.rose)
        } else if n.kind.hasPrefix("clock") {
            Image(systemName: "clock.fill").foregroundStyle(Theme.amber)
        } else {
            Image(systemName: "bell.fill").foregroundStyle(Theme.muted)
        }
    }
}
