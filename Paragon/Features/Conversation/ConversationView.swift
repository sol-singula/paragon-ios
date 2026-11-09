import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            if let v = view {
                if v.threads.count > 1 { chips(v) }
                if let e = error { ErrorBanner(message: e).padding(.horizontal, 12).padding(.top, 6) }
                TimelineList(events: v.timeline ?? [], scrollKey: scrollKey)
                Composer(draft: $draft, label: v.sendLabel, sending: sending,
                         blocked: v.canSend == false ? (v.lockedReason ?? "You can't text from this conversation.") : nil,
                         send: send)
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

    private func send() {
        guard let t = currentThread else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        Task {
            do {
                try await API.send(thread: t, body: body)
                draft = ""
                await load()
                scrollKey += 1
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func call() {
        guard let t = currentThread, let v = view else { return }
        let th = v.threads.first { $0.id == t }
        calls.place(thread: t, name: v.person.name, brand: th?.brand)
    }
}

/// The box at the bottom. The line it sends from is the server's
/// `send_label` ("Text as Solara Home · (385) 333-7711"), shown above it.
struct Composer: View {
    @Binding var draft: String
    let label: String?
    let sending: Bool
    let blocked: String?
    let send: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let blocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text(blocked).font(.meta)
                }
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                if let label { Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("", text: $draft, prompt: Text("Text…").foregroundStyle(Theme.muted), axis: .vertical)
                        .lineLimit(1...6)
                        .font(.ui).foregroundStyle(Theme.text)
                        .focused($focused)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.input))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? Theme.cyan.opacity(0.6) : Theme.inputBorder))
                    Button(action: send) {
                        ZStack {
                            Circle().fill(canSend ? Theme.cyan : Theme.hover).frame(width: 36, height: 36)
                            if sending { ProgressView().tint(.black) }
                            else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(canSend ? Color.black : Theme.muted) }
                        }
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
