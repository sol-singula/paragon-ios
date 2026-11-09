import SwiftUI

/// Your own line's conversations: never in the shared inbox. Founders and
/// managers can open a teammate's line from their face in Team (founder,
/// 2026-11-09: "they are free to message/call people just like normal,
/// itll just show their profile picture next to it"); the server checks the
/// role and logs every opening.
struct PersonalView: View {
    enum Show: Hashable { case recent, waiting, all }

    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(TeamStore.self) private var team
    @State private var items: [PersonalItem] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var show: Show = .recent
    @State private var releasing: PersonTarget?
    @State private var info: PersonTarget?

    private var member: LineOf? { router.personalOf }
    private var canOpenOthers: Bool { ["owner", "manager"].contains(session.me?.role ?? "") }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.personalPath) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let m = member {
                            Text("\(m.name)\u{2019}s line. What you send or call shows your face.")
                                .font(.meta).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                        }
                        let waiting = items.filter { $0.status == "waiting" }.count
                        Segmented(options: [(Show.recent, "Recent"), (.waiting, waiting > 0 ? "Waiting \(waiting)" : "Waiting"), (.all, "All")], selection: $show)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
                if let e = error {
                    ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
                ForEach(shown) { p in
                    NavigationLink(value: Route.personal(threadId: p.threadId, name: p.name)) { PersonalRow(p: p) }
                        .listRowBackground(Theme.bg)
                        .listRowSeparatorTint(Theme.border)
                        .contextMenu {
                            Button { releasing = PersonTarget(personId: p.personId, threadId: p.threadId, name: p.name) } label: {
                                Label("Release…", systemImage: "tray.and.arrow.up")
                            }
                            Button { info = PersonTarget(personId: p.personId, threadId: p.threadId, name: p.name) } label: {
                                Label("Contact info", systemImage: "person.text.rectangle")
                            }
                        }
                }
                if loaded && shown.isEmpty {
                    EmptyNote(title: emptyTitle, detail: items.isEmpty ? emptyDetail : nil, symbol: "person.crop.circle")
                        .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if member != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { router.openPersonal(of: nil) } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel("Back to my Personal")
                    }
                }
                if canOpenOthers {
                    ToolbarItem(placement: .topBarTrailing) { linesMenu }
                }
            }
            .refreshable { await load() }
            .task(id: member) { items = []; loaded = false; await poll() }
            .sheet(item: $releasing) { r in ReleaseSheet(name: r.name, threadId: r.threadId) { Task { await load() } } }
            .sheet(item: $info) { t in ContactInfoSheet(personId: t.personId, threadId: t.threadId) { Task { await load() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n)
                case .person(let p, let t): ConversationView(personId: p, threadId: t)
                }
            }
        }
    }

    /// Founders and managers: a teammate's line.
    private var linesMenu: some View {
        Menu {
            Button { router.openPersonal(of: nil) } label: {
                if member == nil { Label("My line", systemImage: "checkmark") } else { Text("My line") }
            }
            ForEach(team.members.filter { $0.id != session.me?.id }) { m in
                Button { router.openPersonal(of: LineOf(id: m.id, name: m.name)) } label: {
                    if member?.id == m.id { Label("\(m.name)\u{2019}s line", systemImage: "checkmark") } else { Text("\(m.name)\u{2019}s line") }
                }
            }
        } label: {
            Image(systemName: "person.2.circle").foregroundStyle(member != nil ? Theme.cyan : Theme.secondary)
        }
        .accessibilityLabel("Open a teammate's personal line")
    }

    /// Recent is the last two weeks plus anything waiting; spam only in All.
    private var shown: [PersonalItem] {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        return items.filter { i in
            switch show {
            case .all: return true
            case .waiting: return !i.isSpam && i.status == "waiting"
            case .recent: return !i.isSpam && (i.status == "waiting" || (Stamp.date(i.lastActivityAt) ?? .distantPast) >= cutoff)
            }
        }
    }

    private var first: String? { member.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name } }
    private var emptyTitle: String {
        if items.isEmpty { return member == nil ? "No personal conversations" : "Nothing on \(first ?? "")\u{2019}s line" }
        return show == .waiting ? "Nothing waiting on \(member == nil ? "you" : first ?? "")." : "Nothing in the last two weeks."
    }
    private var emptyDetail: String {
        member == nil ? "Texts and calls to your own line show here." : "\(member!.name) has no personal line, or nothing on it yet."
    }

    /// 'Personal · "Mason" line' (owner, 2026-11-09).
    private var title: String {
        var seen = Set<String>()
        var names = items.map(\.line).filter { !$0.isEmpty && seen.insert($0).inserted }
        if names.isEmpty, let f = first { names = [f] }
        guard !names.isEmpty else { return "Personal" }
        return "Personal · " + names.map { "“\($0)”" }.joined(separator: ", ") + (names.count > 1 ? " lines" : " line")
    }

    private func load() async {
        let asked = member
        do {
            // Most recent first, as the desktop's Personal (owner, 2026-11-08).
            let r = try await API.personal(member: asked?.id)
            guard asked == member else { return }
            items = r.sorted { (Stamp.date($0.lastActivityAt) ?? .distantPast) > (Stamp.date($1.lastActivityAt) ?? .distantPast) }
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
                HStack(spacing: 6) {
                    Text(p.name).font(p.status == "waiting" ? .uiMedium : .ui)
                        .foregroundStyle(p.status == "waiting" ? Theme.text : Theme.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    if p.askType == true {
                        Text("New").font(.tag).foregroundStyle(Theme.amber)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.amber.opacity(0.15)))
                            .accessibilityLabel("New: nobody has said who this is yet")
                    }
                    if p.isSpam { Text("Spam").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 4)
                    Text(p.status == "waiting" ? Stamp.span(p.lastActivityAt) : Stamp.when(p.lastActivityAt))
                        .font(.meta).monospacedDigit().foregroundStyle(p.status == "waiting" ? Theme.amber : Theme.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if p.previewKind == "missed" { Image(systemName: "phone.down.fill").font(.system(size: 10)).foregroundStyle(Theme.rose) }
                    else if p.previewKind == "call" { Image(systemName: "phone.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Text(Preview.line(p.preview ?? p.line)).font(.meta)
                        .foregroundStyle(p.previewKind == "missed" ? Theme.rose : Theme.secondary)
                        .lineLimit(1).truncationMode(.tail)
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
    @State private var infoOpen = false

    var body: some View {
        VStack(spacing: 0) {
            if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
            if let t = thread {
                if t.mine == false, let o = t.lineOwner {
                    Text("\(o.name)\u{2019}s personal line. What you send or call shows your face.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(Theme.panel)
                }
                if let p = t.person, p.askType == true {
                    WhoIsThisBar(personId: p.id, name: p.name) { _ in Task { await load() } }
                }
                TimelineList(events: t.timeline ?? [], scrollKey: scrollKey)
                Composer(draft: $draft, label: t.sendLabel, sending: sending,
                         blocked: t.person?.isStopped == true ? "They replied STOP" : nil, send: send)
            } else {
                Spacer(); ProgressView().tint(Theme.muted); Spacer()
            }
        }
        .background(Theme.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { infoOpen = true } label: { Image(systemName: "person.text.rectangle") }
                    .tint(Theme.secondary).disabled(thread?.person == nil).accessibilityLabel("Contact info")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { calls.place(thread: threadId, name: name, brand: nil) } label: { Image(systemName: "phone.fill") }
                    .tint(Theme.cyan).disabled(calls.active != nil).accessibilityLabel("Call")
            }
        }
        .task { while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(6)) } }
        .sheet(isPresented: $infoOpen) {
            if let p = thread?.person { ContactInfoSheet(personId: p.id, threadId: threadId) { Task { await load() } } }
        }
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
