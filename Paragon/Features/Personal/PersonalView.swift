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
    @State private var promising: PromiseTarget?
    @State private var renaming: RenameTarget?

    private var member: LineOf? { router.personalOf }
    private var canOpenOthers: Bool { ["owner", "manager"].contains(session.me?.role ?? "") }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.personalPath) {
            VStack(spacing: 0) {
                TopBar(title: title) {
                    if member != nil {
                        Button { router.openPersonal(of: nil) } label: {
                            Image(systemName: "chevron.backward").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.teal)
                        }
                        .accessibilityLabel("Back to my Personal")
                    }
                } trailing: {
                    if canOpenOthers { linesMenu }
                }
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if let m = member {
                                Text("\(m.name)\u{2019}s line. What you send or call shows your face.")
                                    .font(.meta).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                            }
                            let waiting = items.filter { $0.status == "waiting" }.count
                            Segmented(options: [(Show.waiting, waiting > 0 ? "Waiting \(waiting)" : "Waiting"), (.recent, "Recent"), (.all, "All")], selection: $show)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    if let e = error {
                        ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    ForEach(shown) { p in
                        NavigationLink(value: Route.personal(threadId: p.threadId, name: p.name)) { PersonalRow(p: p) }
                            .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.border)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .contextMenu {
                                Button { promising = PromiseTarget(threadId: p.threadId, personId: p.personId, name: p.name) } label: {
                                    Label("Add promise…", systemImage: "hand.raised")
                                }
                                Button {
                                    let n = Renames.shared.shown(p.personId, p.name)
                                    renaming = RenameTarget(personId: p.personId, name: n, hasName: n != p.name || !p.name.hasPrefix("+"))
                                } label: {
                                    Label("Edit name", systemImage: "pencil")
                                }
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
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
            .dayGlow()
            .toolbar(.hidden, for: .navigationBar)
            .hidesSystemTabBar()
            .task(id: member) { items = []; loaded = false; await poll() }
            .sheet(item: $releasing) { r in
                // Off the list at once (the server keeps it off, 20261110080000).
                ReleaseSheet(name: r.name, threadId: r.threadId, onGone: { items.removeAll { $0.threadId == r.threadId } },
                             onPromise: { what in
                                 Task { @MainActor in
                                     try? await Task.sleep(for: .milliseconds(450))
                                     promising = PromiseTarget(threadId: r.threadId, personId: r.personId, name: r.name, prefill: what.isEmpty ? nil : what)
                                 }
                             }) { Task { await load() } }
            }
            .sheet(item: $renaming) { r in RenameSheet(personId: r.personId, name: r.name, hasName: r.hasName) { Task { await load() } } }
            .sheet(item: $info) { t in ContactInfoSheet(personId: t.personId, threadId: t.threadId) { Task { await load() } } }
            .sheet(item: $promising) { t in PromiseSheet(target: t) { _ in Task { await load(); await InboxModel.shared.load() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n).hidesSystemTabBar()
                case .person(let p, let t): ConversationView(personId: p, threadId: t).hidesSystemTabBar()
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
            Image(systemName: "person.2.circle").foregroundStyle(member != nil ? Theme.teal : Theme.secondary)
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

/// A row as the inbox draws one: a round face, the name semibold, the time
/// on the right, the preview under it; "New" on a first contact.
struct PersonalRow: View {
    let p: PersonalItem
    var body: some View {
        HStack(spacing: 10) {
            Initials(name: Renames.shared.shown(p.personId, p.name), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Renames.shared.shown(p.personId, p.name)).font(.name)
                        .foregroundStyle(p.status == "waiting" || p.askType == true ? Theme.text : Theme.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    if p.askType == true {
                        Text("New").font(.tag).foregroundStyle(Theme.amber)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amber.opacity(0.16)))
                            .accessibilityLabel("New: nobody has said who this is yet")
                    }
                    if p.isSpam { Text("Spam").font(.tag).foregroundStyle(Theme.rose.opacity(0.8)) }
                    Spacer(minLength: 4)
                    Text(p.status == "waiting" ? Stamp.span(p.lastActivityAt) : Stamp.when(p.lastActivityAt))
                        .font(.system(size: 13)).monospacedDigit().foregroundStyle(p.status == "waiting" ? Theme.amber : Theme.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if p.previewKind == "missed" { Image(systemName: "phone.down.fill").font(.system(size: 10)).foregroundStyle(Theme.rose) }
                    else if p.previewKind == "call" { Image(systemName: "phone.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Text(Preview.line(p.preview ?? p.line)).font(.system(size: 14))
                        .foregroundStyle(p.previewKind == "missed" ? Theme.rose : Theme.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }
}

struct PersonalThreadView: View {
    let threadId: String
    let name: String
    @Environment(CallManager.self) private var calls
    @Environment(\.dismiss) private var dismiss
    @State private var thread: PersonalThread?
    @State private var error: String?
    @State private var draft = ""
    @State private var outbox = Outbox.shared
    @State private var scrollKey = 0
    @State private var infoOpen = false
    @State private var promising: PromiseTarget?
    @State private var renaming: RenameTarget?
    @State private var renames = Renames.shared

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(initialsOnly: true, name: renames.shown(thread?.person?.id, thread?.person?.name ?? name),
                               subtitle: thread.map { $0.mine == false ? "\($0.lineOwner?.name ?? "A teammate")\u{2019}s line" : "Personal line" },
                               back: { dismiss() },
                               callDisabled: calls.active != nil, infoDisabled: thread?.person == nil,
                               call: { calls.place(thread: threadId, name: name, brand: nil) },
                               info: { infoOpen = true },
                               addPromise: { promising = PromiseTarget(threadId: threadId, personId: thread?.person?.id, name: thread?.person?.name ?? name) },
                               editName: thread?.person == nil ? nil : {
                                   guard let p = thread?.person else { return }
                                   renaming = RenameTarget(personId: p.id, name: renames.shown(p.id, p.name), hasName: p.hasName != false || renames.justNamed(p.id))
                               })
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
                TimelineList(events: t.timeline ?? [], scrollKey: scrollKey, pending: outbox.items(threadId))
                Composer(draft: $draft, label: t.sendLabel,
                         blocked: t.person?.isStopped == true ? "They replied STOP" : nil,
                         placeholder: Composer.placeholder(for: t.person?.name ?? name, named: t.person?.hasName != false),
                         send: send)
            } else {
                Spacer(); ProgressView().tint(Theme.muted); Spacer()
            }
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task { while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(6)) } }
        .onChange(of: outbox.settled[threadId] ?? 0) { _, _ in Task { await load() } }
        .sheet(isPresented: $infoOpen) {
            if let p = thread?.person { ContactInfoSheet(personId: p.id, threadId: threadId) { Task { await load() } } }
        }
        .sheet(item: $promising) { t in PromiseSheet(target: t) { _ in Task { await InboxModel.shared.load() } } }
        .sheet(item: $renaming) { r in RenameSheet(personId: r.personId, name: r.name, hasName: r.hasName) { Task { await load() } } }
    }

    private func load() async {
        do {
            thread = try await API.personalThread(threadId); error = nil
            if let t = thread { outbox.reconcile(thread: threadId, events: t.timeline ?? []) }
        }
        catch { self.error = error.localizedDescription }
    }

    private func send(_ body: String, _ files: [OutFile]) {
        guard !body.isEmpty || !files.isEmpty else { return }
        outbox.send(thread: threadId, body: body, files: files)
        scrollKey += 1
    }
}
