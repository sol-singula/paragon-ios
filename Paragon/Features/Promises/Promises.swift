import SwiftUI
import Observation

// Promises by hand and Atlas's cards on the inbox's rows (founder,
// 2026-11-09): "right click ... add a promise. it should feel very simple.
// WHO WHEN WHAT. adding the promise should clear the conversation from
// inbox". Every rule is the server's (paragon_promise_*): who may take a
// conversation, who may act on a promise, and who sees the row after.

/// What the promise sheet is for.
struct PromiseTarget: Identifiable, Hashable {
    enum Mode: Hashable {
        /// A new promise: WHO, WHEN, WHAT.
        case add
        /// WHO again, for a promise or an Atlas card.
        case hand(itemId: String, promise: Bool)
        /// WHEN (and WHAT for a promise).
        case change(itemId: String, promise: Bool, due: String?, text: String)
    }

    let threadId: String
    let personId: String?
    let name: String
    var mode: Mode = .add
    /// WHAT filled in ("Follow up with Ryan", after a call). WHO is me either way.
    var prefill: String? = nil

    var id: String {
        switch mode {
        case .add: return "add-\(threadId)"
        case .hand(let i, _): return "hand-\(i)"
        case .change(let i, _, _, _): return "change-\(i)"
        }
    }

    static func hand(_ item: RowItem, thread: String, personId: String?, name: String) -> PromiseTarget {
        PromiseTarget(threadId: item.threadId ?? thread, personId: personId, name: name, mode: .hand(itemId: item.id, promise: item.isPromise))
    }

    static func change(_ item: RowItem, thread: String, personId: String?, name: String) -> PromiseTarget {
        PromiseTarget(threadId: item.threadId ?? thread, personId: personId, name: name,
                      mode: .change(itemId: item.id, promise: item.isPromise, due: item.dueAt, text: item.title ?? ""))
    }
}

/// The short line that confirms what just happened ("Promised to Ryan ·
/// due 9:00 am"), over the tab bar for a couple of seconds.
@Observable
@MainActor
final class Toast {
    static let shared = Toast()

    private(set) var text: String?
    private(set) var isError = false
    /// A button on the toast ("Undo"), for something one tap takes back.
    private(set) var actionLabel: String?
    private var action: (() -> Void)?
    private var task: Task<Void, Never>?

    func show(_ text: String, error: Bool = false, action: (label: String, run: () -> Void)? = nil) {
        task?.cancel()
        self.text = text
        isError = error
        actionLabel = action?.label
        self.action = action?.run
        let wait: Double = action != nil ? 6 : (error ? 4 : 2.6)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.text = nil
            self?.actionLabel = nil
            self?.action = nil
        }
    }

    func runAction() {
        let a = action
        task?.cancel()
        text = nil; actionLabel = nil; action = nil
        a?()
    }
}

struct ToastView: View {
    @State private var toast = Toast.shared

    var body: some View {
        VStack {
            Spacer().allowsHitTesting(false)
            if let t = toast.text {
                HStack(spacing: 7) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Theme.rose : Theme.teal)
                    Text(t).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let label = toast.actionLabel {
                        Button(label) { toast.runAction() }
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.teal)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Theme.hover))
                .overlay(Capsule().strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .padding(.horizontal, 16).padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
                // Only a toast with a button takes touches.
                .allowsHitTesting(toast.actionLabel != nil)
            }
        }
        .animation(.snappy, value: toast.text)
    }
}

/// When a promise is due, as people say it: "9:00 am", "tomorrow 9:00 am",
/// "Tue 9:00 am", "Nov 14 9:00 am"; and how far it is from now.
enum DueTime {
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f }()
    private static let weekday: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let monthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    static func label(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time.string(from: d) }
        if cal.isDateInTomorrow(d) { return "tomorrow \(time.string(from: d))" }
        if d.timeIntervalSinceNow < 6 * 86_400, d > Date() { return "\(weekday.string(from: d)) \(time.string(from: d))" }
        return "\(monthDay.string(from: d)) \(time.string(from: d))"
    }

    /// "in 25 min", "in 3 h", "late 40 min", relative to the due time.
    static func relative(_ s: String?, now: Date = Date()) -> String {
        guard let d = Stamp.date(s) else { return "" }
        let mins = Int((abs(d.timeIntervalSince(now)) / 60).rounded())
        let span: String
        if mins < 60 { span = "\(mins) min" }
        else if mins < 24 * 60 { span = mins % 60 == 0 || mins >= 6 * 60 ? "\(mins / 60) h" : "\(mins / 60) h \(mins % 60) min" }
        else { span = "\(mins / 1440) d" }
        if d <= now { return "late \(span)" }
        return mins < 1 ? "now" : "in \(span)"
    }

    static func color(_ s: String?) -> Color {
        guard let d = Stamp.date(s) else { return Theme.muted }
        if d <= Date() { return Theme.rose }
        return d.timeIntervalSinceNow < 15 * 60 ? Theme.amber : Theme.muted
    }
}

/// Instant (founder, 2026-11-09: "it should APPEAR instant"): what was just
/// done here, hidden from every list the moment it is tapped, so it cannot be
/// tapped twice. A refusal takes it back out. Read anywhere (the models'
/// `rowItems`); `InboxModel.localTick` makes the screens redraw.
final class GoneIDs: @unchecked Sendable {
    static let shared = GoneIDs()
    private let lock = NSLock()
    private var ids: Set<String> = []
    func contains(_ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(id) }
    @MainActor func hide(_ id: String) { lock.lock(); ids.insert(id); lock.unlock(); InboxModel.shared.localTick += 1 }
    @MainActor func putBack(_ id: String) { lock.lock(); ids.remove(id); lock.unlock(); InboxModel.shared.localTick += 1 }
}

/// Done (kept), Not needed (dismissed), for a promise or any other card.
/// Instant: gone at once, the call behind it, back with the reason on a no.
enum ItemActions {
    @MainActor
    static func done(_ id: String, promise: Bool, onDone: @escaping () -> Void) {
        guard !GoneIDs.shared.contains(id) else { return }
        GoneIDs.shared.hide(id)
        Toast.shared.show(promise ? "Promise kept" : "Done")
        Task {
            do {
                if promise { try await API.promiseDone(id, outcome: "kept") }
                else { try await API.atlasCardAct(id, action: "done") }
                onDone()
            } catch { GoneIDs.shared.putBack(id); Toast.shared.show(error.localizedDescription, error: true) }
        }
    }

    @MainActor
    static func notNeeded(_ id: String, promise: Bool, onDone: @escaping () -> Void) {
        guard !GoneIDs.shared.contains(id) else { return }
        GoneIDs.shared.hide(id)
        Toast.shared.show("Cleared: not needed")
        Task {
            do {
                if promise { try await API.promiseDone(id, outcome: "dismissed") }
                else { try await API.atlasCardAct(id, action: "release", note: "Not needed") }
                onDone()
            } catch { GoneIDs.shared.putBack(id); Toast.shared.show(error.localizedDescription, error: true) }
        }
    }
}

/// The four actions on a row's card or promise, for a context menu.
struct ItemMenu: View {
    let item: RowItem
    let thread: String
    let personId: String?
    let name: String
    let open: (PromiseTarget) -> Void
    let changed: () -> Void

    var body: some View {
        Button { ItemActions.done(item.id, promise: item.isPromise, onDone: changed) } label: {
            Label("Done", systemImage: "checkmark.circle")
        }
        Button { ItemActions.notNeeded(item.id, promise: item.isPromise, onDone: changed) } label: {
            Label("Not needed", systemImage: "xmark.circle")
        }
        Button { open(.hand(item, thread: thread, personId: personId, name: name)) } label: {
            Label("Hand to…", systemImage: "arrowshape.turn.up.right")
        }
        Button { open(.change(item, thread: thread, personId: personId, name: name)) } label: {
            Label("Change…", systemImage: "clock.arrow.circlepath")
        }
    }
}

/// WHO, WHEN, WHAT in one small sheet.
struct PromiseSheet: View {
    let target: PromiseTarget
    /// Called after a save, with who now owns it (nil = unchanged or me).
    let onSaved: (_ owner: PromisePerson?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var people: [PromisePerson] = []
    @State private var peopleLoaded = false
    @State private var owner: String?
    @State private var due: Date
    @State private var text: String
    @State private var busy = false
    @State private var error: String?
    @FocusState private var whatFocused: Bool
    /// A vague WHEN ("soon", "today", "this_week") that Atlas places; nil = `due`.
    @State private var vague: String?
    @State private var slot: PromiseSlot?
    @State private var slotLoading = false
    @State private var slotError: String?

    init(target: PromiseTarget, onSaved: @escaping (_ owner: PromisePerson?) -> Void) {
        self.target = target
        self.onSaved = onSaved
        switch target.mode {
        case .change(_, _, let d, let t):
            // As it stands (late or not): WHEN is only sent when it is changed.
            _due = State(initialValue: Stamp.date(d) ?? Self.inAnHour())
            _text = State(initialValue: t)
        default:
            _due = State(initialValue: Self.inAnHour())
            _text = State(initialValue: target.prefill ?? "")
        }
    }

    private var showsWho: Bool { if case .change = target.mode { return false }; return true }
    private var showsWhen: Bool { if case .hand = target.mode { return false }; return true }
    private var showsWhat: Bool {
        switch target.mode {
        case .add: return true
        case .hand: return false
        case .change(_, let promise, _, _): return promise
        }
    }

    private var title: String {
        switch target.mode {
        case .add: return "Add promise"
        case .hand: return "Hand to…"
        case .change(_, let promise, _, _): return promise ? "Change promise" : "Move card"
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        if busy { return false }
        switch target.mode {
        case .add: return owner != nil && !trimmed.isEmpty && trimmed.count <= 200
        case .hand: return owner != nil
        case .change(_, let promise, _, _): return !promise || (!trimmed.isEmpty && trimmed.count <= 200)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsWho { who }
                    if showsWhen { when }
                    if showsWhat { what }
                    if let error { Text(error).font(.meta).foregroundStyle(Theme.rose) }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { save() }.disabled(!canSave)
                }
            }
        }
        .presentationDetents(showsWho && showsWhen ? [.large] : [.medium, .large])
        .presentationBackground(Theme.bg)
        .task { if showsWho { await loadPeople() } }
        // Where Atlas would put it, again whenever WHO changes.
        .task(id: "\(vague ?? "")|\(owner ?? "")") { await loadSlot() }
    }

    private var isAdd: Bool { if case .add = target.mode { return true }; return false }

    private func loadSlot() async {
        guard let hint = vague, owner != nil else { slot = nil; slotError = nil; return }
        let chosen = people.first { $0.id == owner }
        slotLoading = true
        slot = nil; slotError = nil
        do { slot = try await API.promiseSlot(thread: target.threadId, owner: chosen?.isMe == true ? nil : owner, hint: hint) }
        catch { if !Task.isCancelled { slotError = error.localizedDescription } }
        slotLoading = false
    }

    // MARK: WHO

    private var who: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Who")
            VStack(spacing: 0) {
                if !peopleLoaded {
                    HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }.padding(.vertical, 14)
                } else if people.isEmpty {
                    Text("Nobody on the team can take this one.").font(.meta).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 50) }
                    personRow(p)
                }
            }
            .card()
        }
    }

    private func personRow(_ p: PromisePerson) -> some View {
        let able = p.canTake != false
        let chosen = owner == p.id
        return Button { if able { owner = p.id } } label: {
            HStack(spacing: 10) {
                Face(name: p.name, url: p.photoUrl, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.isMe == true ? "\(p.name) (you)" : p.name)
                        .font(.uiMedium).foregroundStyle(able ? Theme.text : Theme.muted).lineLimit(1)
                    if !able, let w = p.whyNot, !w.isEmpty {
                        Text(String(w.prefix(1).uppercased() + w.dropFirst())).font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                    } else if let r = p.role {
                        Text(Role.label(r)).font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(chosen ? Theme.teal : Theme.border)
                    .opacity(able ? 1 : 0.4)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!able)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityHint(able ? "" : (p.whyNot ?? "Can't take this one"))
    }

    // MARK: WHEN

    private struct Chip: Identifiable { let id: String; let label: String; let date: Date }

    private var chips: [Chip] {
        var out = [Chip(id: "1h", label: "In 1 hour", date: Self.inAnHour())]
        let cal = Calendar.current, now = Date()
        if let four = cal.date(bySettingHour: 16, minute: 0, second: 0, of: now), four > now.addingTimeInterval(10 * 60) {
            out.append(Chip(id: "4pm", label: "4 PM today", date: four))
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            out.append(Chip(id: "9am", label: "Tomorrow 9 AM", date: nine))
        }
        return out
    }

    /// The vague WHEN chips (founder, 2026-11-09): Atlas picks the time.
    private static let vagueChips: [(hint: String, label: String)] = [("soon", "Soon"), ("today", "Today"), ("this_week", "This week")]

    private var when: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("When", trailing: vague == nil ? DueTime.label(due) : (slot?.label.map { "Atlas: \($0)" } ?? "Atlas picks"))
            if isAdd {
                HStack(spacing: 6) {
                    ForEach(Self.vagueChips, id: \.hint) { c in
                        let on = vague == c.hint
                        Button { vague = c.hint } label: {
                            Text(c.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                .foregroundStyle(on ? Theme.violet : Theme.text)
                                .padding(.horizontal, 10).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.violet.opacity(0.16) : Theme.hover))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Theme.violet.opacity(0.5) : Theme.violet.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Atlas picks the time, around your other promises")
                    }
                }
                if vague != nil {
                    Group {
                        if let s = slot {
                            VStack(alignment: .leading, spacing: 2) {
                                if let l = s.label { Text("Atlas: \(l)").font(.metaMedium).foregroundStyle(Theme.text) }
                                if let w = s.why { Text(w).font(.meta).foregroundStyle(Theme.muted) }
                            }
                        } else if let e = slotError {
                            Text("Could not place it: \(e)").font(.meta).foregroundStyle(Theme.rose)
                        } else if slotLoading {
                            Text("Atlas is placing it…").font(.meta).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    let on = vague == nil && abs(c.date.timeIntervalSince(due)) < 60
                    Button { vague = nil; due = c.date } label: {
                        Text(c.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            .foregroundStyle(on ? Theme.teal : Theme.text)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.teal.opacity(0.16) : Theme.hover))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Theme.teal.opacity(0.5) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            DatePicker("Pick a time", selection: Binding(get: { due }, set: { due = $0; vague = nil }), in: min(due, Date())...Date().addingTimeInterval(364 * 86_400))
                .font(.ui).foregroundStyle(Theme.secondary)
                .tint(Theme.teal)
        }
    }

    // MARK: WHAT

    private var what: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("What", trailing: trimmed.count > 160 ? "\(trimmed.count)/200" : nil)
            TextField("", text: $text, prompt: Text("Send the quote, call back about the install…").foregroundStyle(Theme.muted), axis: .vertical)
                .lineLimit(1...4)
                .font(.ui).foregroundStyle(Theme.text)
                .focused($whatFocused)
                .submitLabel(.done)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(whatFocused ? Theme.cyan.opacity(0.6) : Theme.inputBorder))
                .onChange(of: text) { _, t in if t.count > 200 { text = String(t.prefix(200)) } }
        }
    }

    // MARK: Saving

    private static func inAnHour() -> Date {
        // On the minute, so the chip and the picker agree.
        let d = Date().addingTimeInterval(3600)
        return Calendar.current.date(bySetting: .second, value: 0, of: d) ?? d
    }

    private func loadPeople() async {
        do {
            people = try await API.promisePeople(thread: target.threadId)
            if case .add = target.mode {
                owner = people.first { $0.isMe == true && $0.canTake != false }?.id
                    ?? people.first { $0.canTake != false }?.id
            }
            error = nil
        } catch { self.error = "Could not load the team: \(error.localizedDescription)" }
        peopleLoaded = true
    }

    /// Instant (founder, 2026-11-09): the sheet closes and the toast says it
    /// the moment Save is tapped; the call runs behind it, and a refusal is a
    /// toast with the server's words (the lists read again).
    private func save() {
        busy = true
        error = nil
        let chosen = people.first { $0.id == owner }
        let toOther = chosen != nil && chosen?.isMe != true
        let text = trimmed, due = due, vague = vague, slotLabel = slot?.label, onSaved = onSaved, target = target
        let work: () async throws -> Void
        switch target.mode {
        case .add:
            let to = toOther ? owner : nil
            let when = vague == nil ? DueTime.label(due) : (slotLabel ?? "when Atlas places it")
            Toast.shared.show(toOther ? "Promised to \(chosen!.first) · due \(when)" : "Promised · due \(when)")
            if toOther, let p = target.personId { InboxModel.shared.clear(personId: p) }
            work = {
                if let hint = vague { try await API.promiseAddVague(thread: target.threadId, owner: to, hint: hint, text: text) }
                else { try await API.promiseAdd(thread: target.threadId, owner: to, due: due, text: text) }
            }
        case .hand(let id, let promise):
            guard let owner = owner else { busy = false; return }
            Toast.shared.show("Handed to \(chosen?.first ?? "them")")
            if toOther { GoneIDs.shared.hide(id) }
            work = {
                do {
                    if promise { try await API.promiseReassign(id, owner: owner) }
                    else { try await API.atlasCardHand(id, to: owner) }
                } catch { if toOther { GoneIDs.shared.putBack(id) }; throw error }
            }
        case .change(let id, let promise, let before, let was):
            let moved = Stamp.date(before).map { abs($0.timeIntervalSince(due)) >= 60 } ?? true
            let edited = promise && text != was.trimmingCharacters(in: .whitespacesAndNewlines)
            guard moved || edited else { dismiss(); return }
            Toast.shared.show(moved ? "Due \(DueTime.label(due))" : "Promise updated")
            work = {
                if promise { try await API.promiseUpdate(id, due: moved ? due : nil, text: edited ? text : nil) }
                else { try await API.atlasCardAct(id, action: "move", due: API.iso.string(from: due)) }
            }
        }
        dismiss()
        Task { @MainActor in
            do { try await work(); onSaved(chosen) }
            catch {
                Toast.shared.show(error.localizedDescription, error: true)
                await InboxModel.shared.load()
            }
        }
    }
}

/// The open promises on a conversation, compact, at the top of it.
struct OpenPromises: View {
    let promises: [ThreadPromise]
    let meId: String?
    let open: (ThreadPromise) -> Void
    let hand: (ThreadPromise) -> Void
    let changed: () -> Void

    @State private var inbox = InboxModel.shared
    @State private var expanded = false

    /// Calm with many (founder, 2026-11-09): one block, "2 promises · next
    /// due Fri 9:00 am" over the soonest; tap it for the rest. What was just
    /// done here is already gone (`GoneIDs`).
    private var list: [ThreadPromise] {
        _ = inbox.localTick
        return promises.filter { !GoneIDs.shared.contains($0.id) }
            .sorted { (Stamp.date($0.dueAt) ?? .distantFuture) < (Stamp.date($1.dueAt) ?? .distantFuture) }
    }

    var body: some View {
        let all = list
        let rows = all.count > 1 && !expanded ? Array(all.prefix(1)) : all
        VStack(spacing: 0) {
            if all.count > 1 {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("\(all.count) promises").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                        if let d = Stamp.date(all.first?.dueAt) {
                            Text("· next due \(DueTime.label(d))").font(.system(size: 12))
                                .foregroundStyle(d <= Date() ? Theme.rose : Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Shows only the soonest" : "Shows every promise")
                Rectangle().fill(Theme.violet.opacity(0.18)).frame(height: 1)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Rectangle().fill(Theme.violet.opacity(0.18)).frame(height: 1) }
                row(p)
            }
        }
        .background(Theme.violet.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.violet.opacity(0.8)).frame(width: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .opacity(all.isEmpty ? 0 : 1)
        .frame(height: all.isEmpty ? 0 : nil)
        .clipped()
    }

    private func row(_ p: ThreadPromise) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(.system(size: 11)).foregroundStyle(Theme.violet)
            Text(p.what).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
            if p.memberId != nil, p.memberId == meId {
                Text("Yours").font(.tag).foregroundStyle(Theme.violet)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.violet.opacity(0.16)))
            }
            Spacer(minLength: 4)
            Text(dueText(p)).font(.system(size: 12)).monospacedDigit().foregroundStyle(DueTime.color(p.dueAt)).lineLimit(1)
            Menu {
                Button { ItemActions.done(p.id, promise: true, onDone: changed) } label: { Label("Done", systemImage: "checkmark.circle") }
                Button { ItemActions.notNeeded(p.id, promise: true, onDone: changed) } label: { Label("Not needed", systemImage: "xmark.circle") }
                Button { hand(p) } label: { Label("Hand to…", systemImage: "arrowshape.turn.up.right") }
                Button { open(p) } label: { Label("Change…", systemImage: "clock.arrow.circlepath") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .frame(width: 30, height: 26).contentShape(Rectangle())
            }
            .accessibilityLabel("Promise actions")
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
    }

    private func dueText(_ p: ThreadPromise) -> String {
        guard let d = Stamp.date(p.dueAt) else { return "" }
        return p.isOverdue ? DueTime.relative(p.dueAt) : DueTime.label(d)
    }
}
