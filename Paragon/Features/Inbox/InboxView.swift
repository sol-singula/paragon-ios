import SwiftUI

struct InboxView: View {
    @Environment(Router.self) private var router
    @State private var model = InboxModel.shared
    @State private var promising: PromiseTarget?
    @State private var releasing: PersonTarget?
    @State private var renaming: RenameTarget?
    @Environment(CallManager.self) private var calls
    @Environment(Session.self) private var session
    @State private var composing: NewMessagePrefill?
    @State private var notice: String?
    @State private var busyHit: String?
    @State private var pickingLine: LinePickTarget?
    @State private var personalInfo: PersonTarget?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.inboxPath) {
            VStack(spacing: 0) {
                // No New message button (founder, 2026-11-11): search a name
                // or a number and Text it from the results.
                TopBar(title: "Inbox") {
                    filterMenu
                }
                SearchField(text: $model.search, prompt: "Search clients, people, numbers") { call in submitSearch(call: call) }
                List {
                    if model.isSearching {
                        searchResults
                    } else {
                        inboxSections
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .environment(\.defaultMinListHeaderHeight, 0)
                .refreshable { await model.load() }
                .overlay { if !model.loaded { ProgressView().tint(Theme.muted) } }
                // The activity feed (founder, 2026-11-10): a band under the list.
                if !model.isSearching { FeedBand() }
            }
            .dayGlow()
            .toolbar(.hidden, for: .navigationBar)
            .hidesSystemTabBar()
            .onChange(of: model.search) { _, _ in model.searchChanged() }
            // Back from a conversation: read the list now, so a row I just
            // answered, typed or promised is already gone.
            .onChange(of: router.inboxPath.count) { was, now in if now < was { Task { await model.load() } } }
            // The inbox polls from MainTabs, so it keeps up while a
            // conversation is open (the list underneath is current when you go back).
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .person(let p, let t): ConversationView(personId: p, threadId: t).id(p).hidesSystemTabBar()
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n).hidesSystemTabBar()
                }
            }
            .sheet(item: $releasing) { r in
                ReleaseSheet(name: r.name, threadId: r.threadId,
                             onGone: { if model.show == .personal { model.dropPersonal(thread: r.threadId) } else { model.clear(personId: r.personId) } },
                             onPromise: { what in
                                 // Once the release sheet is down, Add promise (WHO = me, WHAT = the reason).
                                 Task { @MainActor in
                                     try? await Task.sleep(for: .milliseconds(450))
                                     promising = PromiseTarget(threadId: r.threadId, personId: r.personId, name: r.name, prefill: what.isEmpty ? nil : what)
                                 }
                             }) { Task { await model.load() } }
            }
            .sheet(item: $renaming) { r in RenameSheet(personId: r.personId, name: r.name, hasName: r.hasName) }
            .sheet(item: $personalInfo) { t in ContactInfoSheet(personId: t.personId, threadId: t.threadId) { reload() } }
            .sheet(item: $promising) { t in
                PromiseSheet(target: t) { owner in
                    // Given to someone else: off my inbox at once.
                    if case .add = t.mode, let p = t.personId, owner?.isMe == false { model.clear(personId: p) }
                    if case .change(_, true, _, _, _) = t.mode, let p = t.personId, owner?.isMe == false { model.clear(personId: p) }
                    Task { await model.load() }
                }
            }
            .sheet(item: $composing) { p in
                NewMessageSheet(prefill: p) { person, thread, name, brand in
                    composing = nil
                    router.inboxPath.append(.person(personId: person, threadId: thread))
                    // After the sheet is gone, so the call screen can come up.
                    if p.then == .call {
                        Task { try? await Task.sleep(for: .milliseconds(700)); calls.place(thread: thread, name: name, brand: brand) }
                    }
                    Task { await model.load() }
                }
            }
            // A number with no conversation (founder, 2026-11-10): pick the line.
            .sheet(item: $pickingLine) { t in
                LinePickerSheet(target: t) { person, thread, name, brand in
                    pickingLine = nil
                    if t.then == .text { ComposerFocus.request(thread) }
                    model.search = ""
                    router.inboxPath.append(.person(personId: person, threadId: thread))
                    if t.then == .call {
                        Task { try? await Task.sleep(for: .milliseconds(700)); calls.place(thread: thread, name: name, brand: brand) }
                    }
                    Task { await model.load() }
                }
            }
            .alert("Can't do that", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(notice ?? "") }
        }
    }

    // MARK: The inbox

    @ViewBuilder private var inboxSections: some View {
        Section {
            header
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let e = model.error {
                ErrorBanner(message: e) { Task { await model.load() } }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

        }

        if model.show == .personal {
            personalSection
        } else {
        Section {
            ForEach(model.shown) { q in
                NavigationLink(value: Route.person(personId: q.personId, threadId: q.openThread)) {
                    QueueRow(q: q, answered: model.answered(q))
                }
                .contextMenu { rowMenu(q) }
                .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                .listRowBackground(QueueRowBackground(atlas: q.isAtlas, gold: q.isGold))
                .listRowSeparatorTint(Theme.border)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            if model.loaded && model.shown.isEmpty {
                EmptyNote(title: model.show == .waiting ? "Nothing urgent" : "Nothing here",
                          detail: model.show == .all ? nil : "You're caught up.",
                          symbol: "checkmark.circle")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        }
    }

    /// Personal (founder, 2026-11-11): my own line's conversations, most
    /// recent first, as Recent is; no Urgent / Recent / All inside it.
    @ViewBuilder private var personalSection: some View {
        Section {
            ForEach(model.personalShown) { p in
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
                        Button { personalInfo = PersonTarget(personId: p.personId, threadId: p.threadId, name: p.name) } label: {
                            Label("Contact info", systemImage: "person.text.rectangle")
                        }
                    }
            }
            if model.loaded && model.personalShown.isEmpty {
                EmptyNote(title: "No personal conversations", detail: "Texts and calls to your own line show here.", symbol: "person.crop.circle")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
    }

    /// Hold a row: Add promise…, the card or promise's own actions, Release….
    @ViewBuilder private func rowMenu(_ q: QueueItem) -> some View {
        if let g = q.goldItem {
            // A gold card is not a promise: its own two actions.
            Section("New website lead") {
                Button { Gold.later(g, personId: q.personId, name: q.name, changed: reload) } label: {
                    Label("Try again later", systemImage: "clock.arrow.circlepath")
                }
                Button { Gold.done(g, name: q.name, changed: reload) } label: {
                    Label("Talked to them · not gold", systemImage: "checkmark")
                }
            }
        }
        if let t = q.openThread {
            // One promise per conversation: Change promise… for the open one.
            if let p = q.rowItems.first(where: { $0.isPromise }) {
                Button { promising = PromiseTarget.change(p, thread: t, personId: q.personId, name: q.name) } label: {
                    Label("Change promise…", systemImage: "hand.raised")
                }
            } else {
                Button { promising = PromiseTarget(threadId: t, personId: q.personId, name: q.name) } label: {
                    Label("Add promise…", systemImage: "hand.raised")
                }
            }
            let items = q.rowItems.filter { !$0.isGold }
            if items.count == 1, let i = items.first {
                Section(i.what) {
                    ItemMenu(item: i, thread: t, personId: q.personId, name: q.name, open: { promising = $0 }, changed: reload)
                }
            } else if items.count > 1 {
                Section {
                    ForEach(items) { i in
                        Menu(Stamp.date(i.dueAt).map { "\(i.what) · \(DueTime.label($0))" } ?? i.what) {
                            ItemMenu(item: i, thread: t, personId: q.personId, name: q.name, open: { promising = $0 }, changed: reload)
                        }
                    }
                }
            }
            Section {
                Button {
                    let n = Renames.shared.shown(q.personId, q.name)
                    renaming = RenameTarget(personId: q.personId, name: n, hasName: n != q.name || !(q.name.hasPrefix("+") || q.name.hasPrefix("(")))
                } label: {
                    Label("Edit name", systemImage: "pencil")
                }
                // Not on Recent (founder, 2026-11-11): Recent is everyone, so nothing to release there.
                if model.show != .all {
                    Button { releasing = PersonTarget(personId: q.personId, threadId: t, name: q.name) } label: {
                        Label("Release…", systemImage: "tray.and.arrow.up")
                    }
                }
            }
        }
    }

    private func reload() { Task { await model.load() } }

    // MARK: Search results, grouped as on the desktop

    @ViewBuilder private var searchResults: some View {
        if model.searching && model.hits.isEmpty {
            HStack(spacing: 8) { Spacer(); ProgressView().tint(Theme.muted); Text("Searching…").font(.meta).foregroundStyle(Theme.muted); Spacer() }
                .padding(.vertical, 24)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else if model.hits.isEmpty && !model.searching && !model.searchedFor.isEmpty {
            EmptyNote(title: "No results for \u{201C}\(model.searchedFor)\u{201D}", detail: "Try a different spelling, a phone number or an email.", symbol: "magnifyingglass")
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else {
            let known = Set(SearchHit.groups.map(\.type))
            ForEach(SearchHit.groups, id: \.type) { g in
                let items = model.hits.filter { $0.type == g.type }
                if !items.isEmpty { resultSection(g.label, g.symbol, items) }
            }
            let other = model.hits.filter { !known.contains($0.type) }
            if !other.isEmpty { resultSection("Other", "circle.dashed", other) }
        }
    }

    private func resultSection(_ label: String, _ symbol: String, _ items: [SearchHit]) -> some View {
        Section {
            ForEach(items, id: \.key) { h in
                SearchHitRow(hit: h, symbol: symbol, busy: busyHit == h.key, callDisabled: calls.active != nil,
                             neverTexted: h.type == "lead" && model.knownConversation(h.id) == "",
                             onOpen: { Task { await openHit(h) } },
                             onText: { Task { await openHit(h) } },
                             onCall: { Task { await callHit(h) } })
                    .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.border)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        } header: {
            SectionLabel(label, trailing: "\(items.count)")
                .padding(.top, 10).padding(.bottom, 4)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    /// The person a result is in Paragon: a conversation is one already; a
    /// lead is whoever has their number (paragon_lead_conversation).
    private func personFor(_ h: SearchHit) async throws -> String? {
        if h.type == "conversation" { return h.id }
        // A "none yet" is asked again: they may have been texted since.
        if let known = model.knownConversation(h.id), !known.isEmpty { return known }
        return try await API.leadConversation(h.id)
    }

    /// Opening (and Text): their conversation; a lead nobody has texted yet
    /// opens New message with their name and phone filled in.
    private func openHit(_ h: SearchHit, then: NewMessagePrefill.Then = .text) async {
        if h.type == "number" { await actOnNumber(h.id, .text); return }
        guard h.isPerson else {
            notice = "\(h.name) has no conversation in Paragon. Only clients and people who have texted or called open here."
            return
        }
        busyHit = h.key
        defer { busyHit = nil }
        do {
            if let person = try await personFor(h) {
                router.inboxPath.append(.person(personId: person, threadId: nil))
            } else {
                composing = await prefill(h, then: then)
            }
        } catch { notice = error.localizedDescription }
    }

    /// Call: their primary conversation through CallManager, as the call
    /// button in the conversation does. A thread the wall locks is refused.
    private func callHit(_ h: SearchHit) async {
        if h.type == "number" { await actOnNumber(h.id, .call); return }
        guard calls.active == nil else { notice = "You are already on a call."; return }
        busyHit = h.key
        defer { busyHit = nil }
        do {
            guard let person = try await personFor(h) else { composing = await prefill(h, then: .call); return }
            guard let v = try await API.person(person, thread: nil) else { notice = "This conversation isn't yours to see."; return }
            let t = v.threads.first(where: { $0.id == v.threadId && $0.locked != true }) ?? v.threads.first(where: { $0.locked != true })
            router.inboxPath.append(.person(personId: person, threadId: t?.id ?? v.threadId))
            guard let t else {
                notice = v.lockedReason ?? "Locked for you: you have spoken with them for another brand."
                return
            }
            calls.place(thread: t.id, name: v.person.name, brand: t.brand)
        } catch { notice = error.localizedDescription }
    }

    /// A typed number: with conversations, its own (no question, the sticky
    /// line); with none, the line picker.
    private func actOnNumber(_ digits: String, _ then: NewMessagePrefill.Then) async {
        if then == .call, calls.active != nil { notice = "You are already on a call."; return }
        busyHit = "number-\(digits)"
        do {
            let who = try await API.phoneLookup(digits)
            busyHit = nil
            if who?.ours == true { notice = "That number is one of our own lines."; return }
            if let p = who?.personId, !(who?.threads ?? []).isEmpty {
                let h = SearchHit(id: p, type: "conversation", name: who?.name ?? LinePick.format(digits),
                                  secondary: nil, status: nil, statusColor: nil, brand: nil)
                if then == .call { await callHit(h) } else { await openHit(h) }
                return
            }
            pickingLine = LinePickTarget(phone: digits, name: who?.name, then: then)
        } catch {
            busyHit = nil
            notice = error.localizedDescription
        }
    }

    /// Return in the search on a number: Text; Cmd+Return: Call.
    private func submitSearch(call: Bool) {
        guard let d = LinePick.digits(model.query) else { return }
        let hits = model.searchedFor == model.query ? model.hits : []
        let then: NewMessagePrefill.Then = call ? .call : .text
        if !hits.contains(where: { $0.type == "number" }),
           let h = hits.first(where: { $0.type == "conversation" }) ?? hits.first(where: { $0.type == "lead" && ($0.score ?? 0) >= 100 }) {
            Task { if call { await callHit(h) } else { await openHit(h) } }
        } else {
            Task { await actOnNumber(d, then) }
        }
    }

    private func prefill(_ h: SearchHit, then: NewMessagePrefill.Then) async -> NewMessagePrefill {
        var c: LeadContact?
        if h.type == "lead" { c = try? await API.leadContact(h.id) }
        return NewMessagePrefill(fromSearch: true, name: c?.name ?? h.name, phone: c?.phone ?? "", place: c?.address ?? "",
                                 brand: c?.brand, state: c?.state, then: then)
    }

    private var header: some View {
        let c = model.counts
        let first = session.me?.first
        return VStack(alignment: .leading, spacing: 10) {
            // The hour's greeting, the desktop's, over the hour's light.
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 120)) { ctx in
                    let g = DayPhase.of(ctx.date).greeting
                    Text(first.map { "\(g), \($0)" } ?? g)
                        .font(.greeting).tracking(-0.2).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(summary(c)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            // Urgent, Recent, and Personal for a member with a personal line
            // (founder, 2026-11-11). Urgent is the server's 'waiting'.
            Segmented(options: filters(c), selection: Binding(get: { model.show }, set: { model.choose(show: $0) }))
        }
    }

    private func filters(_ c: (waiting: Int, late: Int)) -> [(InboxModel.Show, String)] {
        var out: [(InboxModel.Show, String)] = [(.waiting, c.waiting > 0 ? "Urgent \(c.waiting)" : "Urgent"), (.all, "Recent")]
        if model.hasPersonal {
            let n = model.personalWaiting
            out.append((.personal, n > 0 ? "Personal \(n)" : "Personal"))
        }
        return out
    }

    /// "4 urgent · 1 late"; only what there is.
    private func summary(_ c: (waiting: Int, late: Int)) -> String {
        guard model.loaded else { return " " }
        var parts = ["\(c.waiting) urgent"]
        if c.late > 0 { parts.append("\(c.late) late") }
        return c.waiting == 0 ? "Nothing urgent" : parts.joined(separator: " · ")
    }

    private var filterMenu: some View {
        Menu {
            // One choice (founder, 2026-11-10), the desktop's: All, Homeowners
            // only, Logistics only (a logistics job in Nexus, or a vendor or
            // contractor), or one branch.
            ForEach([("all", "All"), ("homeowners", "Homeowners only"), ("logistics", "Logistics only")], id: \.0) { f in
                Button { model.choose(filter: f.0) } label: {
                    if model.filter == f.0 { Label(f.1, systemImage: "checkmark") } else { Text(f.1) }
                }
            }
            Divider()
            ForEach(model.brands, id: \.self) { b in
                Button { model.choose(filter: "brand:\(b)") } label: {
                    let name = "\(Branch.of(b).code) · \(Branch.of(b).name)"
                    if model.brand == b { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            // Someone else's promise is on my rows only with All promises.
            ForEach([("mine", "My promises"), ("all", "All promises")], id: \.0) { f in
                Button { model.choose(promises: f.0) } label: {
                    if model.promises == f.0 { Label(f.1, systemImage: "checkmark") } else { Text(f.1) }
                }
            }
        } label: {
            Image(systemName: model.filter != "all" || model.promises == "all"
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(Theme.secondary)
        }
    }
}

struct QueueRow: View {
    let q: QueueItem
    /// Answered here a moment ago (a text or a reaction): no longer late.
    var answered = false

    var body: some View {
        HStack(spacing: 10) {
            BranchMark(brand: q.firstThread?.brand, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Renames.shared.shown(q.personId, q.name))
                        .font(.name)
                        .foregroundStyle(q.status == "closed" && !q.isAtlas ? Theme.secondary : Theme.text)
                        .lineLimit(1)
                    if (q.threads?.count ?? 0) > 1 {
                        Text("\(q.threads!.count)").font(.tag).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                    }
                    if q.firstThread?.locked == true { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 4)
                    if let w = q.goldForm, q.isGold {
                        Text(w.label).font(.tag).foregroundStyle(Theme.goldText)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold.opacity(0.22)))
                    } else {
                        Text(clock).font(.system(size: 13)).monospacedDigit().foregroundStyle(clockColor).lineLimit(1)
                    }
                }
                // Always two lines (founder, 2026-11-10): the promise (WHO · WHAT)
                // or the last message, never both.
                if let g = q.goldItem { goldLine(g) } else if let i = q.leadItem { itemLine(i) } else {
                Text(q.preview?.isEmpty == false ? Preview.line(q.preview!) : " ")
                    // A missed call (or a voicemail, which is one) reads in rose (founder, 2026-11-09).
                    .font(.system(size: 14)).foregroundStyle(
                        (q.preview?.hasPrefix("Missed call") == true || q.preview?.hasPrefix("Voicemail") == true) ? Theme.rose
                        : q.status == "closed" ? Theme.muted : Theme.secondary)
                    .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    /// Who and what of the row's leading card or promise, in one line. No
    /// time (founder, 2026-11-10): it comes up in the inbox when it is due.
    private func itemLine(_ i: RowItem) -> some View {
        HStack(spacing: 4) {
            if i.byHand { Image(systemName: "hand.raised.fill").font(.system(size: 9)) }
            else { AtlasRing(size: 10) }
            Text(who(i)).fontWeight(.semibold)
            Text("·")
            Text(i.what).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.tail)
            if q.rowItems.count > 1 {
                Text("+\(q.rowItems.count - 1)").foregroundStyle(Theme.muted).layoutPriority(1)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.violet)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// A gold row's second line: the website form and what they want.
    private func goldLine(_ g: RowItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "phone.fill").font(.system(size: 10))
            Text("Website form").fontWeight(.semibold)
            Text("·")
            Text(q.goldForm?.form?.wants ?? g.why ?? "Ready to call").foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.goldText)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// The staff member's first name (founder, 2026-11-10: "dont say 'you'
    /// or 'team' anymore, say the name of the staff member"); Atlas for one
    /// of Atlas's cards; "Anyone" for a promise nobody has.
    private func who(_ i: RowItem) -> String {
        if !i.isPromise && !i.byHand { return "Atlas" }
        if let o = i.ownerId, let n = TeamStore.shared.byId[o]?.name.split(separator: " ").first { return String(n) }
        return "Anyone"
    }

    /// Relative to the row's due time once it is late (rose); a waiting
    /// customer still on time shows how long they have waited, never a time
    /// ahead (founder, 2026-11-09: "we shouldnt say tomorrow 9am").
    private var clock: String {
        if answered && (q.dueAt == nil || q.dueSource == "clock") { return Stamp.when(q.lastActivityAt) }
        if q.dueAt != nil {
            if q.isOverdue { return DueTime.relative(q.dueAt) }
            // A promise or card ahead: no time or date, the last activity.
            if q.dueSource != "clock" { return Stamp.when(q.lastActivityAt) }
        }
        switch q.status {
        case "waiting": return Stamp.span(q.waitingSince)
        default: return Stamp.when(q.lastActivityAt)
        }
    }

    private var clockColor: Color {
        if answered && (q.dueAt == nil || q.dueSource == "clock") { return Theme.muted }
        if q.dueAt != nil, q.isOverdue { return Theme.rose }
        if q.dueAt != nil, q.dueSource != "clock" { return Theme.muted }
        switch q.tone {
        case .late: return Theme.rose
        case .soon: return Theme.amber
        case .calm: return Theme.muted
        }
    }
}

/// An Atlas row is a conversation row with a slight violet tint and a thin
/// violet leading edge; every other row stays clear.
struct QueueRowBackground: View {
    let atlas: Bool
    var gold: Bool = false
    var body: some View {
        if gold {
            // Gold (2026-11-10): a website form, ready to call.
            Theme.gold.opacity(0.18)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 3) }
        } else if atlas {
            Theme.violet.opacity(0.07)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.violet.opacity(0.85)).frame(width: 2) }
        } else {
            Color.clear
        }
    }
}
