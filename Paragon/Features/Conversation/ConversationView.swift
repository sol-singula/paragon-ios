import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// One person: their conversation per branch (chips), the timeline, and the
/// composer that sends through paragon-send from the line the server names.
struct ConversationView: View {
    let personId: String
    @State var threadId: String?

    @Environment(CallManager.self) private var calls
    @State private var view: PersonView?
    @State private var error: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var scrollKey = 0
    @State private var house: URL?
    @State private var houseBig = false

    var body: some View {
        VStack(spacing: 0) {
            if let v = view {
                if v.threads.count > 1 { chips(v) }
                if let h = house { houseRow(h, v) }
                if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
                TimelineList(events: v.timeline ?? [], scrollKey: scrollKey)
                Composer(draft: $draft, label: v.sendLabel, sending: sending,
                         blocked: v.canSend == false ? (v.lockedReason ?? "You can't text from this conversation.") : nil,
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { title }
            ToolbarItem(placement: .topBarTrailing) {
                Button { call() } label: { Image(systemName: "phone.fill") }
                    .tint(Theme.cyan)
                    .disabled(currentThread == nil || calls.active != nil)
                    .accessibilityLabel("Call")
            }
        }
        .task(id: threadId) { await poll() }
        .task(id: personId) { await loadHouse() }
        .onAppear { Presence.shared.focus(personId: personId, name: view?.person.name) }
        .onDisappear { Presence.shared.focus(personId: nil, name: nil) }
        .fullScreenCover(isPresented: $houseBig) { ImageViewer(url: house) }
    }

    /// Their house, from Nexus's saved Street View: tap to see it big
    /// (founder, 2026-11-09).
    private func houseRow(_ url: URL, _ v: PersonView) -> some View {
        Button { houseBig = true } label: {
            HStack(spacing: 10) {
                RemoteImage(url: url, fill: true)
                    .frame(width: 64, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.lead?.address ?? "Their house").font(.meta).foregroundStyle(Theme.secondary).lineLimit(2)
                    Text("Tap to view").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .accessibilityLabel("Their house. Tap to view it full screen.")
    }

    private func loadHouse() async {
        house = nil
        // Ask once the person is known; only a person linked to a Nexus lead has one.
        for _ in 0..<20 where view == nil { try? await Task.sleep(for: .milliseconds(300)) }
        guard view?.person.nexusLeadId != nil || view?.lead != nil else { return }
        if let s = try? await API.housePhoto(personId), let u = URL(string: s) { house = u }
    }

    private var currentThread: String? { view?.threadId ?? threadId }

    private var title: some View {
        let t = view?.threads.first { $0.id == view?.threadId }
        return VStack(spacing: 1) {
            Text(view?.person.name ?? " ").font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
            let sub = [Branch.of(t?.brand).name, t?.state, view?.person.city].compactMap { $0 }.joined(separator: " · ")
            if view != nil { Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
        }
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
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func load() async {
        do {
            view = try await API.person(personId, thread: threadId)
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

    private func send(_ files: [SharedFile]) async -> Bool {
        guard let t = currentThread else { return false }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !files.isEmpty else { return false }
        sending = true
        defer { sending = false }
        do {
            try await API.send(thread: t, body: body, attachments: files)
            draft = ""
            await load()
            scrollKey += 1
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func call() {
        guard let t = currentThread, let v = view else { return }
        let th = v.threads.first { $0.id == t }
        calls.place(thread: t, name: v.person.name, brand: th?.brand)
    }
}

