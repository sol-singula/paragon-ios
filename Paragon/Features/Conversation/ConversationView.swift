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

    var body: some View {
        VStack(spacing: 0) {
            header
            if let v = view {
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
            name: view?.person.name ?? " ",
            subtitle: view == nil ? nil : [Branch.of(t?.brand).name, t?.state, view?.person.city].compactMap { $0 }.joined(separator: " · "),
            back: { dismiss() },
            callDisabled: currentThread == nil || calls.active != nil,
            infoDisabled: view == nil,
            call: call,
            info: { infoOpen = true })
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
            if let v = view, let t = v.threadId { outbox.reconcile(thread: t, events: v.timeline ?? []) }
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
            Spacer(minLength: 4)
            PillButton(label: "Call", action: call)
                .disabled(callDisabled).opacity(callDisabled ? 0.45 : 1)
                .accessibilityLabel("Call")
            PillButton(label: "", symbol: "info.circle", action: info)
                .disabled(infoDisabled).opacity(infoDisabled ? 0.45 : 1)
                .accessibilityLabel("Contact info")
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.top, 4).padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
