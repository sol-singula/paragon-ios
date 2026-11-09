import SwiftUI

struct InboxView: View {
    @Environment(Router.self) private var router
    @State private var model = InboxModel()
    @State private var deckOpen = false
    @State private var releasing: PersonTarget?
    @Environment(CallManager.self) private var calls
    @Environment(Session.self) private var session
    @State private var composing: NewMessagePrefill?
    @State private var notice: String?
    @State private var busyHit: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.inboxPath) {
            List {
                if model.isSearching {
                    searchResults
                } else {
                    inboxSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dayGlow()
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search clients, people, numbers")
            .autocorrectionDisabled()
            .onChange(of: model.search) { _, _ in model.searchChanged() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { composing = NewMessagePrefill() } label: { Image(systemName: "square.and.pencil") }
                        .tint(Theme.secondary).accessibilityLabel("New message")
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .refreshable { await model.load() }
            .task { await model.poll() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .person(let p, let t): ConversationView(personId: p, threadId: t)
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n)
                }
            }
            .overlay { if !model.loaded { ProgressView().tint(Theme.muted) } }
            .sheet(item: $releasing) { r in ReleaseSheet(name: r.name, threadId: r.threadId) { Task { await model.load() } } }
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
            .alert("Can't do that", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(notice ?? "") }
        }
    }

    // MARK: The inbox

    @ViewBuilder private var inboxSections: some View {
        Section {
            header
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let e = model.error {
                ErrorBanner(message: e) { Task { await model.load() } }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            if let deck = model.deck, !deck.cards.isEmpty, model.search.isEmpty {
                AtlasGuide(deck: deck, open: $deckOpen) { card in
                    if let p = card.personId { router.open(.person(personId: p, threadId: card.threadId)) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        Section {
            ForEach(model.shown) { q in
                NavigationLink(value: Route.person(personId: q.personId, threadId: q.threads?.first(where: { $0.status == "waiting" })?.id ?? q.firstThread?.id)) {
                    QueueRow(q: q)
                }
                .contextMenu {
                    if let t = q.threads?.first(where: { $0.status == "waiting" })?.id ?? q.firstThread?.id {
                        Button { releasing = PersonTarget(personId: q.personId, threadId: t, name: q.name) } label: {
                            Label("Release…", systemImage: "tray.and.arrow.up")
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.border)
            }
            if model.loaded && model.shown.isEmpty {
                EmptyNote(title: model.show == .waiting ? "Nobody is waiting" : "Nothing here",
                          detail: model.show == .waiting ? "You're caught up." : nil,
                          symbol: "checkmark.circle")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
    }

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
                             onOpen: { Task { await openHit(h) } },
                             onText: { Task { await openHit(h) } },
                             onCall: { Task { await callHit(h) } })
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.border)
            }
        } header: {
            HStack {
                Text(label).font(.metaMedium).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(items.count)").font(.meta).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .textCase(nil)
        }
    }

    /// The person a result is in Paragon: a conversation is one already; a
    /// lead is whoever has their number (paragon_lead_conversation).
    private func personFor(_ h: SearchHit) async throws -> String? {
        h.type == "conversation" ? h.id : try await API.leadConversation(h.id)
    }

    /// Opening (and Text): their conversation; a lead nobody has texted yet
    /// opens New message with their name and phone filled in.
    private func openHit(_ h: SearchHit, then: NewMessagePrefill.Then = .text) async {
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
        guard calls.active == nil else { notice = "You are already on a call."; return }
        busyHit = h.key
        defer { busyHit = nil }
        do {
            guard let person = try await personFor(h) else { composing = await prefill(h, then: .call); return }
            guard let v = try await API.person(person, thread: nil) else { notice = "This conversation isn't yours to see."; return }
            let t = v.threads.first { $0.id == v.threadId && $0.locked != true } ?? v.threads.first { $0.locked != true }
            router.inboxPath.append(.person(personId: person, threadId: t?.id ?? v.threadId))
            guard let t else {
                notice = v.lockedReason ?? "Locked for you: you have spoken with them for another brand."
                return
            }
            calls.place(thread: t.id, name: v.person.name, brand: t.brand)
        } catch { notice = error.localizedDescription }
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
        return VStack(alignment: .leading, spacing: 8) {
            // The hour's greeting, the desktop's, over the hour's light.
            TimelineView(.periodic(from: .now, by: 120)) { ctx in
                let g = DayPhase.of(ctx.date).greeting
                Text(first.map { "\(g), \($0)" } ?? g)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            }
            HStack {
                Segmented(options: [(InboxModel.Show.waiting, c.waiting > 0 ? "Waiting \(c.waiting)" : "Waiting"), (.all, "All")],
                          selection: $model.show) { s in
                    s == .waiting && c.late > 0 ? AnyView(CountPill(text: "\(c.late) late")) : nil
                }
                Spacer()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                Text("Most urgent first").tag(InboxModel.Sort.urgency)
                Text("Most recent first").tag(InboxModel.Sort.recent)
            }
            Picker("Who", selection: Binding(get: { model.homeownersOnly }, set: { model.homeownersOnly = $0; Task { await model.load() } })) {
                Text("Homeowners only").tag(true)
                Text("Contractors and internal too").tag(false)
            }
            Menu("Branch") {
                Button { model.brand = nil; Task { await model.load() } } label: {
                    if model.brand == nil { Label("All branches", systemImage: "checkmark") } else { Text("All branches") }
                }
                ForEach(model.brands, id: \.self) { b in
                    Button { model.brand = b; Task { await model.load() } } label: {
                        if model.brand == b { Label(Branch.of(b).name, systemImage: "checkmark") } else { Text(Branch.of(b).name) }
                    }
                }
            }
        } label: {
            Image(systemName: model.brand != nil || !model.homeownersOnly || model.sort == .recent
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(Theme.secondary)
        }
    }
}

struct QueueRow: View {
    let q: QueueItem

    var body: some View {
        HStack(spacing: 12) {
            BranchMark(brand: q.firstThread?.brand, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(q.name)
                        .font(q.status == "closed" ? .ui : .uiMedium)
                        .foregroundStyle(q.status == "closed" ? Theme.muted : Theme.text)
                        .lineLimit(1)
                    if (q.threads?.count ?? 0) > 1 {
                        Text("\(q.threads!.count)").font(.tag).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                    }
                    if q.firstThread?.locked == true { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 4)
                    Text(clock).font(.meta).monospacedDigit().foregroundStyle(clockColor)
                }
                Text(q.preview?.isEmpty == false ? Preview.line(q.preview!) : " ")
                    .font(.meta).foregroundStyle(q.status == "closed" ? Theme.muted : Theme.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .leading) {
            if q.tone == .late { Rectangle().fill(Theme.rose).frame(width: 3).offset(x: -16).padding(.vertical, -6) }
        }
    }

    private var clock: String {
        switch q.status {
        case "waiting": return Stamp.span(q.waitingSince)
        case "owed": return "Owed"
        default: return Stamp.when(q.lastActivityAt)
        }
    }

    private var clockColor: Color {
        switch q.tone {
        case .late: return Theme.rose
        case .soon: return Theme.amber
        case .calm: return q.status == "owed" ? Theme.amber : Theme.muted
        }
    }
}

/// The one Atlas guide (owner, 2026-11-08): the next thing to do, and the
/// rest of Atlas's cards behind "N cards from Atlas".
struct AtlasGuide: View {
    let deck: AtlasDeck
    @Binding var open: Bool
    let onOpen: (AtlasCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = deck.cards.first {
                Button { onOpen(first) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AtlasRing(size: 18).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(first.title).font(.uiMedium).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                            if let why = first.why, !why.isEmpty {
                                Text(why).font(.meta).foregroundStyle(Theme.secondary).lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                            }
                            if let due = first.dueAt { Text(dueText(due)).font(.meta).foregroundStyle(dueColor(due)) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)
            }
            if deck.cards.count > 1 {
                Divider().overlay(Theme.border)
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    HStack {
                        Text("\(deck.cards.count) cards from Atlas").font(.metaMedium).foregroundStyle(Theme.violet.opacity(0.95))
                        Spacer()
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(deck.cards.dropFirst()) { c in
                        Button { onOpen(c) } label: {
                            HStack(spacing: 10) {
                                BranchMark(brand: c.brand, size: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.title).font(.meta).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                                    if let n = c.name { Text(n).font(.meta).foregroundStyle(Theme.muted).lineLimit(1) }
                                }
                                Spacer()
                                if let due = c.dueAt { Text(dueText(due)).font(.meta).foregroundStyle(dueColor(due)) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.violet.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.violet.opacity(0.35)))
    }

    private func dueText(_ s: String) -> String {
        guard let d = Stamp.date(s) else { return "" }
        return d < Date() ? "Late · \(Stamp.span(s))" : "Due \(Stamp.when(s))"
    }
    private func dueColor(_ s: String) -> Color {
        (Stamp.date(s) ?? .distantFuture) < Date() ? Theme.rose : Theme.muted
    }
}
