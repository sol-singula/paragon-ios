import SwiftUI

/// Search a number (founder, 2026-11-10: "if we have no previous
/// conversations, it should ask us what line we want to call/text from").
/// The desktop's `lib/linePick.ts` and `LinePicker.tsx`.
enum LinePick {
    /// A search that is a phone number: 10 digits, or 11 starting with 1,
    /// ignoring formatting. The 10 digits, else nil.
    static func digits(_ q: String) -> String? {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber || " ().+-".contains($0) }) else { return nil }
        var d = t.filter(\.isNumber)
        if d.count == 11, d.first == "1" { d.removeFirst() }
        return d.count == 10 ? d : nil
    }

    /// (801) 555-1234.
    static func format(_ d: String) -> String {
        guard d.count == 10 else { return d }
        let a = Array(d)
        return "(\(String(a[0..<3]))) \(String(a[3..<6]))-\(String(a[6..<10]))"
    }

    /// The lines I may start a customer conversation on, New message's rule:
    /// tagged customer Quo lines with a brand and a state that I am not
    /// blocked from, one per brand and state (the oldest, the one
    /// `paragon_start_thread` uses).
    static func usable(_ lines: [LineInfo]) -> [LineInfo] {
        var best: [String: LineInfo] = [:]
        for l in lines where l.kind == "customer" && l.provider == "quo" && l.inQuo == true && l.blocked != true {
            guard let b = l.brand, let s = l.state else { continue }
            let k = "\(b)|\(s)"
            if let cur = best[k], (cur.firstSeenAt ?? "") <= (l.firstSeenAt ?? "") { continue }
            best[k] = l
        }
        return Array(best.values)
    }

    struct Choice: Identifiable {
        let line: LineInfo
        let code: String
        let label: String
        let why: String?
        let suggested: Bool
        var id: String { line.id }
    }

    /// The area code's state first, then the line that has carried the most
    /// texts, then the name. The first row says why.
    static func rank(_ lines: [LineInfo], phone: String) -> [Choice] {
        let area = Places.state(forPhone: phone)
        let ac = String((digits(phone) ?? phone.filter(\.isNumber)).prefix(3))
        let rows = usable(lines).sorted { a, b in
            let la = a.state == area, lb = b.state == area
            if la != lb { return la }
            if (a.messages ?? 0) != (b.messages ?? 0) { return (a.messages ?? 0) > (b.messages ?? 0) }
            return (a.label ?? "") < (b.label ?? "")
        }
        let inArea = area != nil && rows.contains { $0.state == area }
        let areaName = area.map { Places.name[$0] ?? $0 } ?? ""
        return rows.enumerated().map { (i: Int, l: LineInfo) -> Choice in
            var why: String?
            if i == 0 {
                if inArea {
                    let an = ["A", "E", "I", "O"].contains(String(areaName.prefix(1))) ? "an" : "a"
                    why = "Suggested: \(ac) is \(an) \(areaName) area code"
                } else if area != nil {
                    why = "No line in \(areaName) for you, so the busiest line first"
                } else {
                    why = "Area code \(ac) is not one of our states, so the busiest line first"
                }
            } else if area != nil, l.state == area {
                why = "Also \(areaName)"
            }
            return Choice(line: l, code: Branch.of(l.brand).code, label: l.label ?? l.brand ?? "Line", why: why, suggested: i == 0 && inArea)
        }
    }
}

/// What the picker is for: a number, maybe a name, and Text or Call.
struct LinePickTarget: Identifiable {
    let id = UUID()
    let phone: String
    let name: String?
    let then: NewMessagePrefill.Then
}

/// The line picker, a small sheet: only my usable lines, the suggested one
/// first with why ("SH · Solara Main"). Tapping one starts the conversation
/// on it (`paragon_start_thread`), which then keeps that line.
struct LinePickerSheet: View {
    let target: LinePickTarget
    /// person, thread, name, brand
    let onStarted: (String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LineInfo]?
    @State private var busy: String?
    @State private var error: String?

    private var shown: String { LinePick.format(target.phone) }

    var body: some View {
        NavigationStack {
            List {
                if let lines {
                    let rows = LinePick.rank(lines, phone: target.phone)
                    if rows.isEmpty {
                        Text("You have no customer line to \(target.then == .call ? "call" : "text") from. A founder can give you one in People & access.")
                            .font(.meta).foregroundStyle(Theme.secondary)
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(rows) { c in
                            Button { Task { await pick(c) } } label: {
                                HStack(spacing: 10) {
                                    BranchMark(brand: c.line.brand, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        (Text(c.code).fontWeight(.bold) + Text(" · \(c.label)"))
                                            .font(.ui).foregroundStyle(Theme.text).lineLimit(1)
                                        Text(c.why ?? (c.line.state.map { Places.name[$0] ?? $0 } ?? ""))
                                            .font(.meta).foregroundStyle(c.suggested ? Theme.green : Theme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if busy == c.id { ProgressView().controlSize(.small).tint(Theme.muted) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(busy != nil)
                            .listRowBackground(Theme.card)
                        }
                    } footer: {
                        Text("No conversation with \(target.name ?? "this number") yet. The line you pick stays with it.").font(.meta)
                    }
                } else {
                    HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }.listRowBackground(Color.clear)
                }
                if let error {
                    Text(error).font(.meta).foregroundStyle(Theme.rose).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("\(target.then == .call ? "Call" : "Text") \(target.name ?? shown) from…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.secondary) }
            }
            .task {
                do { lines = try await API.lines() } catch { lines = []; self.error = error.localizedDescription }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func pick(_ c: LinePick.Choice) async {
        guard busy == nil, let brand = c.line.brand, let state = c.line.state else { return }
        busy = c.id
        defer { busy = nil }
        do {
            let r = try await API.startThread(phone: target.phone, name: target.name ?? "", brand: brand, state: state, guessed: false)
            onStarted(r.personId, r.threadId, target.name ?? shown, brand)
        } catch { self.error = error.localizedDescription }
    }
}

/// A conversation just started from the line picker opens with the composer
/// focused (Text), once: the thread id waits here until its composer appears.
@MainActor
enum ComposerFocus {
    private static var next: String?
    static func request(_ thread: String) { next = thread }
    static func take(_ thread: String?) -> Bool {
        guard let thread, next == thread else { return false }
        next = nil
        return true
    }
}
