import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// One person: their conversation per branch (chips), the timeline, and the
/// composer that sends through paragon-send from the line the server names.
struct ConversationView: View {
    let personId: String
    @State var threadId: String?

    @Environment(CallManager.self) private var calls
    @Environment(\.dismiss) private var dismiss
    @State private var view: PersonView?
    @State private var error: String?
    @State private var draft = ""
    @State private var outbox = Outbox.shared
    @State private var scrollKey = 0
    @State private var house: URL?
    @State private var houseBig = false
    @State private var infoOpen = false
    @State private var promises: [ThreadPromise] = []
    @State private var promising: PromiseTarget?
    @State private var renaming: RenameTarget?
    @State private var renames = Renames.shared
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            header
            if let v = view {
                if !promises.isEmpty {
                    OpenPromises(promises: promises, meId: session.me?.id,
                                 open: { p in promising = target(p) },
                                 changed: { Task { await load() } })
                }
                if v.threads.count > 1 { chips(v) }
                if let h = house { houseBanner(h, v) }
                if v.person.askType == true {
                    WhoIsThisBar(personId: v.person.id, name: v.person.name) { _ in Task { await load() } }
                }
                if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
                TimelineList(events: v.timeline ?? [], scrollKey: scrollKey, pending: outbox.items(v.threadId ?? currentThread))
                Composer(draft: $draft, label: v.sendLabel,
                         blocked: v.canSend == false ? (v.lockedReason ?? "You can't text from this conversation.") : nil,
                         placeholder: Composer.placeholder(for: v.person.name, named: v.person.hasName != false),
                         send: send)
                    .onChange(of: v.person.name) { _, n in Presence.shared.focus(personId: personId, name: n) }
            } else if let e = error {
                ErrorBanner(message: e) { Task { await load() } }.padding()
                Spacer()
            } else {
                Spacer(); ProgressView().tint(Theme.muted); Spacer()
            }
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: threadId) { await poll() }
        // A send went: read the thread now, so the real text takes its place.
        .onChange(of: outbox.settled[currentThread ?? ""] ?? 0) { _, _ in Task { await load() } }
        .task(id: personId) { await loadHouse() }
        .onAppear { Presence.shared.focus(personId: personId, name: view?.person.name) }
        .onDisappear { Presence.shared.focus(personId: nil, name: nil) }
        .fullScreenCover(isPresented: $houseBig) { ImageViewer(url: house) }
        .sheet(isPresented: $infoOpen) {
            ContactInfoSheet(personId: personId, threadId: currentThread) { Task { await load() } }
        }
        .sheet(item: $renaming) { r in
            RenameSheet(personId: r.personId, name: r.name, hasName: r.hasName) { Task { await load() } }
        }
        .sheet(item: $promising) { t in
            PromiseSheet(target: t) { owner in
                if case .add = t.mode, owner?.isMe == false { InboxModel.shared.clear(personId: personId) }
                if case .change = t.mode, owner?.isMe == false { InboxModel.shared.clear(personId: personId) }
                Task { await load(); await InboxModel.shared.load() }
            }
        }
    }

    private func editName() {
        guard let v = view else { return }
        renaming = RenameTarget(personId: v.person.id, name: renames.shown(v.person.id, v.person.name),
                                hasName: v.person.hasName != false || renames.justNamed(v.person.id))
    }

    private func addPromise() {
        guard let t = currentThread else { return }
        promising = PromiseTarget(threadId: t, personId: personId, name: view?.person.name ?? "")
    }

    /// Change… : WHO, WHEN, WHAT (no separate hand off, founder 2026-11-10).
    private func target(_ p: ThreadPromise) -> PromiseTarget {
        let thread = p.threadId ?? currentThread ?? ""
        let name = view?.person.name ?? ""
        return PromiseTarget(threadId: thread, personId: personId, name: name,
                             mode: .change(itemId: p.id, promise: true, due: p.dueAt, text: p.title ?? "", owner: p.memberId))
    }

    /// Their house, from Nexus's saved Street View, as a short banner
    /// across the top: tap to see it big (founder, 2026-11-09).
    private func houseBanner(_ url: URL, _ v: PersonView) -> some View {
        Button { houseBig = true } label: {
            Color.clear
                .frame(height: 88)
                .frame(maxWidth: .infinity)
                .overlay { RemoteImage(url: url, fill: true) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let a = v.lead?.address, !a.isEmpty { bannerTag(a).padding(6).padding(.trailing, 104) }
                }
                .overlay(alignment: .bottomTrailing) { bannerTag("Tap to enlarge").padding(6) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.top, 8)
        .accessibilityLabel("Their house. Tap to view it full screen.")
    }

    private func bannerTag(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.45)))
    }

    private func loadHouse() async {
        house = nil
        // Ask once the person is known; only a person linked to a Nexus lead has one.
        for _ in 0..<20 where view == nil { try? await Task.sleep(for: .milliseconds(300)) }
        guard view?.person.nexusLeadId != nil || view?.lead != nil else { return }
        if let s = try? await API.housePhoto(personId), let u = URL(string: s) { house = u }
    }

    private var currentThread: String? { view?.threadId ?? threadId }

    /// The mockup's `.chead`: a teal chevron back, the branch's mark, the
    /// name over "Brand · State", and Call and ⓘ as small grey pills.
    private var header: some View {
        let t = view?.threads.first { $0.id == view?.threadId }
        return ConversationHeader(
            brand: t?.brand,
            name: view.map { renames.shown($0.person.id, $0.person.name) } ?? " ",
            subtitle: view == nil ? nil : [Branch.of(t?.brand).name, t?.state, view?.person.city].compactMap { $0 }.joined(separator: " · "),
            back: { dismiss() },
            callDisabled: currentThread == nil || calls.active != nil,
            infoDisabled: view == nil,
            call: call,
            info: { infoOpen = true },
            addPromise: view == nil || currentThread == nil ? nil : addPromise,
            editName: view == nil ? nil : editName)
    }

    private func chips(_ v: PersonView) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(v.threads) { t in
                    Button { threadId = t.id } label: {
                        BranchChip(brand: t.brand, state: t.state, selected: t.id == v.threadId,
                                   waiting: t.status == "waiting" && t.locked != true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }

    private func load() async {
        do {
            view = try await API.person(personId, thread: threadId)
            if let v = view, let t = v.threadId {
                outbox.reconcile(thread: t, events: v.timeline ?? [])
                // The open promises, soonest first; an older server has none.
                if let ps = try? await API.threadPromises(t) {
                    promises = ps.filter(\.isOpen).sorted { (Stamp.date($0.dueAt) ?? .distantFuture) < (Stamp.date($1.dueAt) ?? .distantFuture) }
                }
            }
            if view == nil { error = "This conversation isn't yours to see." } else { error = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(6))
        }
    }

    /// Into the thread at once; the Outbox sends it from the thread's own
    /// line through paragon-send, which keeps every rule (locks, STOP).
    private func send(_ body: String, _ files: [OutFile]) {
        guard let t = currentThread, !body.isEmpty || !files.isEmpty else { return }
        outbox.send(thread: t, body: body, files: files)
        scrollKey += 1
    }

    private func call() {
        guard let t = currentThread, let v = view else { return }
        let th = v.threads.first { $0.id == t }
        calls.place(thread: t, name: v.person.name, brand: th?.brand)
    }
}


/// A conversation's own bar (the mockup's `.chead`), used with a customer
/// and on a personal line.
struct ConversationHeader: View {
    var brand: String?
    /// Personal lines have no brand: their initials instead of a mark.
    var initialsOnly = false
    let name: String
    var subtitle: String?
    let back: () -> Void
    var callDisabled = false
    var infoDisabled = false
    let call: () -> Void
    let info: () -> Void
    /// The header's menu: Add promise… (founder, 2026-11-09: WHO WHEN WHAT).
    var addPromise: (() -> Void)?
    /// Edit name (founder, 2026-11-09): from the menu, or a tap on the name.
    var editName: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if initialsOnly { Initials(name: name, size: 28) } else { BranchMark(brand: brand, size: 28) }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editName?() }
            .accessibilityAddTraits(editName != nil ? .isButton : [])
            .accessibilityHint(editName != nil ? "Tap to change their name" : "")
            Spacer(minLength: 4)
            PillButton(label: "Call", action: call)
                .disabled(callDisabled).opacity(callDisabled ? 0.45 : 1)
                .accessibilityLabel("Call")
            PillButton(label: "", symbol: "info.circle", action: info)
                .disabled(infoDisabled).opacity(infoDisabled ? 0.45 : 1)
                .accessibilityLabel("Contact info")
            if let addPromise {
                Menu {
                    Button(action: addPromise) { Label("Add promise…", systemImage: "hand.raised") }
                    if let editName {
                        Button(action: editName) { Label("Edit name", systemImage: "pencil") }
                    }
                    Button(action: info) { Label("Contact info", systemImage: "person.text.rectangle") }
                        .disabled(infoDisabled)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.hover))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.top, 4).padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
