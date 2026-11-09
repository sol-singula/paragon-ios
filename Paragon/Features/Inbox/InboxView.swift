import SwiftUI

struct InboxView: View {
    @Environment(Router.self) private var router
    @State private var model = InboxModel()
    @State private var deckOpen = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.inboxPath) {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Theme.bg)
                        .listRowSeparator(.hidden)

                    if let e = model.error {
                        ErrorBanner(message: e) { Task { await model.load() } }
                            .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                    }

                    if let deck = model.deck, !deck.cards.isEmpty, model.search.isEmpty {
                        AtlasGuide(deck: deck, open: $deckOpen) { card in
                            if let p = card.personId { router.open(.person(personId: p, threadId: card.threadId)) }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Theme.bg)
                        .listRowSeparator(.hidden)
                    }
                }

                Section {
                    ForEach(model.shown) { q in
                        NavigationLink(value: Route.person(personId: q.personId, threadId: q.threads?.first(where: { $0.status == "waiting" })?.id ?? q.firstThread?.id)) {
                            QueueRow(q: q)
                        }
                        .listRowBackground(Theme.bg)
                        .listRowSeparatorTint(Theme.border)
                    }
                    if model.loaded && model.shown.isEmpty {
                        EmptyNote(title: model.show == .waiting ? "Nobody is waiting" : "Nothing here",
                                  detail: model.show == .waiting ? "You're caught up." : nil,
                                  symbol: "checkmark.circle")
                            .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search people, numbers, words")
            .onSubmit(of: .search) { Task { await model.load() } }
            .onChange(of: model.search) { _, v in if v.isEmpty { Task { await model.load() } } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { filterMenu } }
            .refreshable { await model.load() }
            .task { await model.poll() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .person(let p, let t): ConversationView(personId: p, threadId: t)
                case .personal(let t, let n): PersonalThreadView(threadId: t, name: n)
                }
            }
            .overlay { if !model.loaded { ProgressView().tint(Theme.muted) } }
        }
    }

    private var header: some View {
        let c = model.counts
        return HStack {
            Segmented(options: [(InboxModel.Show.waiting, c.waiting > 0 ? "Waiting \(c.waiting)" : "Waiting"), (.all, "All")],
                      selection: $model.show) { s in
                s == .waiting && c.late > 0 ? AnyView(CountPill(text: "\(c.late) late")) : nil
            }
            Spacer()
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
                Text(q.preview?.isEmpty == false ? q.preview! : " ")
                    .font(.meta).foregroundStyle(q.status == "closed" ? Theme.muted : Theme.secondary)
                    .lineLimit(1)
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
                                Text(why).font(.meta).foregroundStyle(Theme.secondary).lineLimit(2).multilineTextAlignment(.leading)
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
                                    Text(c.title).font(.meta).foregroundStyle(Theme.text).lineLimit(1)
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
