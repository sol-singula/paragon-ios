import SwiftUI

/// One channel: messages oldest at the top (earlier ones load as you scroll
/// up), each with its author's face, the composer at the bottom, the bell
/// in the corner. Read up to here while it is on screen.
struct ChannelView: View {
    let channelId: String

    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var phase
    @State private var model = TeamModel.shared
    @State private var msgs: [TeamMessage]?
    @State private var more = false
    @State private var loadingOlder = false
    @State private var replyTo: TeamMessage?
    @State private var editing: TeamMessage?
    @State private var viewing: ViewedImage?
    @State private var bellOpen = false
    @State private var error: String?
    @State private var readMark: String?
    @State private var scrollKey = 0
    @State private var keepId: String?
    @State private var outbox = TeamOutbox.shared

    private var channel: TeamChannel? { model.channel(channelId) }
    private var meId: String { session.me?.id ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
            if let msgs { list(shown(msgs)) } else { Spacer(); ProgressView().tint(Theme.muted); Spacer() }
            if let c = channel {
                TeamComposer(channel: c, meId: meId, replyTo: $replyTo) { scrollKey += 1 }
            }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("# \(channel?.name ?? "")").font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
                    let n = (channel?.members?.count ?? 0) + (channel?.atlasIn == true ? 1 : 0)
                    if n > 0 { Text("\(n) people\(channel?.atlasIn == true ? " · Atlas" : "")").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { bellOpen = true } label: { Image(systemName: bellIcon).foregroundStyle(Theme.secondary) }
                    .accessibilityLabel("Notifications for this channel")
            }
        }
        .sheet(isPresented: $bellOpen) { ChannelBellSheet(channelId: channelId).presentationDetents([.medium, .large]) }
        .sheet(item: $editing) { m in EditMessageSheet(message: m) { merge([$0]) } }
        .fullScreenCover(item: $viewing) { v in ImageViewer(url: v.url) }
        .task { readMark = channel?.lastReadAt; await poll() }
        .onChange(of: msgs?.last?.id) { _, _ in markRead() }
        .onChange(of: phase) { _, p in if p == .active { markRead() } }
    }

    private var bellIcon: String {
        guard let c = channel else { return "bell" }
        if c.quietOrMuted { return "bell.slash" }
        return c.prefs?.always == true ? "bell.badge" : "bell"
    }

    private func list(_ msgs: [TeamMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if more {
                        HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }
                            .padding(.vertical, 10)
                            .onAppear { Task { await older(proxy) } }
                    } else if let c = channel {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("This is the start of \(c.name).").font(.uiMedium).foregroundStyle(Theme.text)
                            Text("\(c.about.map { "\($0). " } ?? "")Type @ to mention someone.").font(.meta).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
                    }
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        let prev = i > 0 ? msgs[i - 1] : nil
                        let newDay = prev.map { !sameDay($0.createdAt, m.createdAt) } ?? true
                        let firstNew = isFirstNew(m, prev)
                        if newDay { TeamDayDivider(at: m.createdAt) }
                        if firstNew {
                            // The rose "New" line (the mockup's `.newline`).
                            HStack(spacing: 6) {
                                Rectangle().fill(Theme.rose.opacity(0.5)).frame(height: 1)
                                Text("New").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.rose)
                                Rectangle().fill(Theme.rose.opacity(0.5)).frame(height: 1)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 4)
                        }
                        TeamMessageRow(m: m, meId: meId, isFounder: session.me?.isFounder == true,
                                       compact: !newDay && !firstNew && isRun(prev, m),
                                       onUpdate: { merge([$0]) }, onReply: { replyTo = $0 }, onEdit: { editing = $0 },
                                       onOpenPhoto: { viewing = ViewedImage(url: $0) }, onError: { error = $0 })
                            .id(m.id)
                    }
                    // Mine on the way out, after everything else.
                    ForEach(outbox.items(channelId).filter { $0.message == nil }) { p in
                        PendingTeamRow(item: p, meId: meId)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 6)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollKey) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: outbox.items(channelId).count) { old, new in if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            .onChange(of: msgs.count) { old, new in
                if let k = keepId { keepId = nil; proxy.scrollTo(k, anchor: .top) }
                else if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    private func sameDay(_ a: String, _ b: String) -> Bool {
        guard let x = Stamp.date(a), let y = Stamp.date(b) else { return true }
        return Calendar.current.isDate(x, inSameDayAs: y)
    }

    /// The next message from the same person within five minutes reads as one run.
    private func isRun(_ prev: TeamMessage?, _ m: TeamMessage) -> Bool {
        guard let p = prev, !p.isDeleted, p.author == m.author, m.replyTo == nil,
              let a = Stamp.date(p.createdAt), let b = Stamp.date(m.createdAt) else { return false }
        return b.timeIntervalSince(a) < 5 * 60
    }

    /// The "New" line sits where I had read to when I opened it.
    private func isFirstNew(_ m: TeamMessage, _ prev: TeamMessage?) -> Bool {
        guard let mark = Stamp.date(readMark), m.author != meId, let at = Stamp.date(m.createdAt), at > mark else { return false }
        guard let p = prev, let pa = Stamp.date(p.createdAt) else { return true }
        return pa <= mark
    }

    // MARK: Loading

    /// The channel as read, plus what I posted that the next read has not
    /// brought yet (paragon_team_post answers with the message itself, so it
    /// takes the pending one's place at once).
    private func shown(_ msgs: [TeamMessage]) -> [TeamMessage] {
        let have = Set(msgs.map(\.id))
        let mine = outbox.items(channelId).compactMap(\.message).filter { !have.contains($0.id) }
        guard !mine.isEmpty else { return msgs }
        return (msgs + mine).sorted { (Stamp.date($0.createdAt) ?? .distantPast) < (Stamp.date($1.createdAt) ?? .distantPast) }
    }

    private func merge(_ incoming: [TeamMessage], replaceTail: Bool = false) {
        var map = Dictionary((msgs ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if replaceTail, let from = incoming.compactMap({ Stamp.date($0.createdAt) }).min() {
            // The latest page is the truth for everything at or after its first message.
            let ids = Set(incoming.map(\.id))
            for (id, m) in map where (Stamp.date(m.createdAt) ?? .distantPast) >= from && !ids.contains(id) { map[id] = nil }
        }
        for m in incoming { map[m.id] = m }
        msgs = map.values.sorted { (Stamp.date($0.createdAt) ?? .distantPast) < (Stamp.date($1.createdAt) ?? .distantPast) }
    }

    private func poll() async {
        while !Task.isCancelled {
            do {
                let page = try await API.teamRead(channel: channelId)
                if msgs == nil { more = page.more == true }
                merge(page.messages, replaceTail: true)
                outbox.reconcile(channel: channelId, ids: Set((msgs ?? []).map(\.id)))
                error = nil
            } catch {
                if msgs == nil { msgs = [] }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func older(_ proxy: ScrollViewProxy) async {
        guard let first = msgs?.first, !loadingOlder, more else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await API.teamRead(channel: channelId, before: first.createdAt)
            keepId = first.id
            merge(page.messages)
            more = page.more == true
        } catch {
            more = false
        }
    }

    private func markRead() {
        guard phase == .active, msgs != nil else { return }
        Task { await model.markRead(channelId) }
    }
}

/// A post of mine still on its way: my face and name, "Sending…" where the
/// time goes, the photos from the phone; rose with "Not sent · Tap to
/// retry" and the reason when it failed, Delete in its menu.
private struct PendingTeamRow: View {
    let item: TeamOutbox.Item
    let meId: String
    @State private var model = TeamModel.shared
    @State private var confirmDelete = false

    var body: some View {
        let failed = item.isFailed
        HStack(alignment: .top, spacing: 8) {
            MemberFace(id: meId, name: model.name(meId), url: model.photo(meId), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.name(meId)).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                    Text(failed ? "Not sent · Tap to retry" : "Sending…").font(.system(size: 11))
                        .foregroundStyle(failed ? Theme.rose : Theme.muted)
                }
                if let r = item.replyTo {
                    HStack(spacing: 5) {
                        Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                        Text(model.first(r.author)).fontWeight(.medium).foregroundStyle(Theme.secondary)
                        Text(r.body.isEmpty ? (r.photos.isEmpty ? "" : "a photo") : r.body).lineLimit(1)
                    }
                    .font(.meta).foregroundStyle(Theme.muted)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 2) }
                }
                if !item.body.isEmpty {
                    Text(TeamRichText.render(item.body, meId: meId))
                        .font(.ui).foregroundStyle(failed ? Theme.secondary : Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.files.isEmpty {
                    let cols = item.files.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                        ForEach(item.files) { f in
                            if let img = f.preview {
                                Color.clear
                                    .aspectRatio(img.size.height > 0 ? img.size.width / img.size.height : 4.0 / 3.0, contentMode: .fit)
                                    .frame(maxHeight: item.files.count == 1 ? 300 : 160)
                                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else if let a = f.existing {
                                TeamPhoto(a: a, maxHeight: item.files.count == 1 ? 300 : 160)
                            }
                        }
                    }
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(.top, 2)
                }
                if let r = item.reason {
                    Text(r).font(.system(size: 11)).foregroundStyle(Theme.rose.opacity(0.85)).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
        .background(failed ? Theme.rose.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if failed { TeamOutbox.shared.retry(item) } }
        .contextMenu {
            if failed {
                Button { TeamOutbox.shared.retry(item) } label: { Label("Retry", systemImage: "arrow.clockwise") }
            }
            if !item.body.isEmpty {
                Button { UIPasteboard.general.string = item.body } label: { Label("Copy text", systemImage: "doc.on.doc") }
            }
            if failed {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { TeamOutbox.shared.delete(item) }
        } message: { Text("It was never posted.") }
    }
}

private struct TeamDayDivider: View {
    let at: String
    var body: some View {
        let d = Stamp.date(at)
        let f = DateFormatter()
        f.dateFormat = d.map { Calendar.current.component(.year, from: $0) == Calendar.current.component(.year, from: Date()) } == true ? "EEEE, MMMM d" : "EEEE, MMMM d, yyyy"
        let label = d.map { Calendar.current.isDateInToday($0) ? "Today" : Calendar.current.isDateInYesterday($0) ? "Yesterday" : f.string(from: $0) } ?? ""
        return HStack(spacing: 10) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Theme.border))
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Edit what I wrote.
private struct EditMessageSheet: View {
    let message: TeamMessage
    let saved: (TeamMessage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(3...12)
                    .font(.ui).foregroundStyle(Theme.text)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.input))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cyan.opacity(0.5)))
                if let error { Text(error).font(.meta).foregroundStyle(Theme.rose) }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg)
            .navigationTitle("Edit message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.photos.isEmpty)
                }
            }
        }
        .onAppear { text = message.body }
        .presentationDetents([.medium])
    }

    private func save() {
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == message.body.trimmingCharacters(in: .whitespacesAndNewlines) { dismiss(); return }
        saving = true
        Task {
            do { saved(try await API.teamEdit(message: message.id, body: text)); dismiss() }
            catch { self.error = "Not saved: \(error.localizedDescription)" }
            saving = false
        }
    }
}
