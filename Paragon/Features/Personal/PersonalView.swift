import SwiftUI

/// Your own line's conversations: never in the shared inbox, only yours.
struct PersonalView: View {
    @Environment(Router.self) private var router
    @State private var items: [PersonalItem] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.personalPath) {
            List {
                if let e = error {
                    ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
                ForEach(items) { p in
                    NavigationLink(value: Route.personal(threadId: p.threadId, name: p.name)) { PersonalRow(p: p) }
                        .listRowBackground(Theme.bg)
                        .listRowSeparatorTint(Theme.border)
                }
                if loaded && items.isEmpty {
                    EmptyNote(title: "No personal conversations", detail: "Texts and calls to your own line show here.", symbol: "person.crop.circle")
                        .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await poll() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n)
                case .person(let p, let t): ConversationView(personId: p, threadId: t)
                }
            }
        }
    }

    /// 'Personal · "Mason" line' (owner, 2026-11-09).
    private var title: String {
        var seen = Set<String>()
        let names = items.map(\.line).filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !names.isEmpty else { return "Personal" }
        return "Personal · " + names.map { "“\($0)”" }.joined(separator: ", ") + (names.count > 1 ? " lines" : " line")
    }

    private func load() async {
        do {
            // Most recent first, as the desktop's Personal (owner, 2026-11-08).
            items = try await API.personal().sorted { (Stamp.date($0.lastActivityAt) ?? .distantPast) > (Stamp.date($1.lastActivityAt) ?? .distantPast) }
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func poll() async {
        while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(20)) }
    }
}

struct PersonalRow: View {
    let p: PersonalItem
    var body: some View {
        HStack(spacing: 12) {
            Initials(name: p.name, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(p.name).font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(p.status == "waiting" ? Stamp.span(p.lastActivityAt) : Stamp.when(p.lastActivityAt))
                        .font(.meta).monospacedDigit().foregroundStyle(p.status == "waiting" ? Theme.amber : Theme.muted)
                }
                HStack(spacing: 4) {
                    if p.previewKind == "missed" { Image(systemName: "phone.down.fill").font(.system(size: 10)).foregroundStyle(Theme.rose) }
                    else if p.previewKind == "call" { Image(systemName: "phone.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Text(p.preview ?? p.line).font(.meta)
                        .foregroundStyle(p.previewKind == "missed" ? Theme.rose : Theme.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PersonalThreadView: View {
    let threadId: String
    let name: String
    @Environment(CallManager.self) private var calls
    @State private var thread: PersonalThread?
    @State private var error: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var scrollKey = 0

    var body: some View {
        VStack(spacing: 0) {
            if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
            if let t = thread {
                TimelineList(events: t.timeline ?? [], scrollKey: scrollKey)
                Composer(draft: $draft, label: t.sendLabel, sending: sending, blocked: nil, send: send)
            } else {
                Spacer(); ProgressView().tint(Theme.muted); Spacer()
            }
        }
        .background(Theme.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { calls.place(thread: threadId, name: name, brand: nil) } label: { Image(systemName: "phone.fill") }
                    .tint(Theme.cyan).disabled(calls.active != nil).accessibilityLabel("Call")
            }
        }
        .task { while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(6)) } }
    }

    private func load() async {
        do { thread = try await API.personalThread(threadId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func send(_ files: [SharedFile]) async -> Bool {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !files.isEmpty else { return false }
        sending = true
        defer { sending = false }
        do {
            try await API.send(thread: threadId, body: body, attachments: files)
            draft = ""; await load(); scrollKey += 1
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
