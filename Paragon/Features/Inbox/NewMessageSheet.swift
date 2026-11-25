import SwiftUI

/// What New message starts with: empty from the compose button, or a lead
/// from search that nobody has texted yet (then Call also calls them).
struct NewMessagePrefill: Identifiable {
    enum Then { case text, call }
    let id = UUID()
    var fromSearch = false
    var name = ""
    var phone = ""
    var place = ""
    var brand: String?
    var state: String?
    var then: Then = .text
    /// Open the new conversation with the composer focused (a typed number's Text).
    var focus = false
}

/// Starting a conversation, the desktop's `NewMessage.tsx`: staff pick the
/// brand and where the customer is, never a line. The line is that brand's
/// in that state (`paragon_start_thread`); the place is read for a state and
/// the area code is the last resort, marked as a guess. Someone this brand
/// already texts keeps their own line. Nothing is sent from here.
///
/// A branch member with a start brand (owner, 2026-11-25: Troy, "Just Glass")
/// sees no brand picker, no line and no state picker: the brand is theirs, the
/// state comes from the place or the area code (marked as a guess), else is
/// left empty and the server falls back to their own state's line.
struct NewMessageSheet: View {
    let prefill: NewMessagePrefill
    /// person, thread, name, brand
    let onStarted: (String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LineInfo] = []
    @State private var name = ""
    @State private var phone = ""
    @State private var brand = ""
    @State private var place = ""
    @State private var state = ""
    @State private var busy = false
    @State private var error: String?
    @State private var primed = false

    static let brandOrder = ["Solara", "Solara One", "Just Glass", "NixThePitch", "solbuild", "BlackSwan"]

    private var statesFor: [String: [String]] {
        var m: [String: [String]] = [:]
        // The same rule as the search's line picker: my usable customer lines.
        for l in LinePick.usable(lines) {
            guard let b = l.brand, let s = l.state else { continue }
            if !(m[b]?.contains(s) ?? false) { m[b, default: []].append(s) }
        }
        return m
    }
    /// A branch member's fixed brand; nil for staff, who pick one.
    private var fixedBrand: String? { BranchMember.startBrand }
    private var brands: [String] { Self.brandOrder.filter { !(statesFor[$0]?.isEmpty ?? true) } }
    private var states: [String] { brand.isEmpty ? [] : statesFor[brand] ?? [] }

    private var fromPlace: String? {
        Places.state(in: place) ?? (place == prefill.place ? prefill.state.map { $0.uppercased() } : nil)
    }
    private var fromArea: String? { Places.state(forPhone: phone) }
    private var guessed: Bool {
        if fixedBrand != nil { return fromPlace == nil && fromArea != nil }
        return !state.isEmpty && fromPlace == nil && state == fromArea
    }
    private var valid: Bool {
        let d = phone.filter(\.isNumber)
        let number = d.count == 10 || (d.count == 11 && d.first == "1")
        if fixedBrand != nil { return number }
        return number && !brand.isEmpty && !state.isEmpty
    }
    private var calling: Bool { prefill.then == .call }

    var body: some View {
        NavigationStack {
            Form {
                if prefill.fromSearch {
                    Section {
                        Text("No texts or calls with \(prefill.name.isEmpty ? "them" : prefill.name) yet. Check where they are, then \(calling ? "start the conversation and call." : "open the conversation.")")
                            .font(.meta).foregroundStyle(Theme.secondary)
                    }
                    .listRowBackground(Theme.card)
                }
                Section {
                    TextField("Name (optional)", text: $name).textContentType(.name)
                    TextField("Mobile number", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                } footer: { Text("The number is only used to send. It is never shown in the inbox.").font(.meta) }
                .listRowBackground(Theme.card)

                if let fixed = fixedBrand {
                    Section {
                        TextField("Address or city", text: $place)
                    } footer: {
                        Text(guessed ? "Sends as \(fixed). Where they are is guessed from the area code." : "Sends as \(fixed).")
                            .font(.meta)
                    }
                    .listRowBackground(Theme.card)
                } else {
                    Section {
                        Picker("Brand", selection: $brand) {
                            Text("Choose").tag("")
                            ForEach(brands, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Address or city", text: $place)
                        if !brand.isEmpty {
                            Picker("State", selection: $state) {
                                Text("Choose").tag("")
                                ForEach(states, id: \.self) { Text(Places.name[$0] ?? $0).tag($0) }
                            }
                        }
                    } footer: {
                        Text(guessed ? "Guessed from the area code. The conversation is marked as a guess."
                             : !brand.isEmpty && states.isEmpty ? "\(brand) has no customer line yet."
                             : "Where the customer is decides which line they hear from.")
                            .font(.meta)
                    }
                    .listRowBackground(Theme.card)

                    if !brand.isEmpty && !state.isEmpty {
                        Section { Text("Sends as \(brand) · \(Places.name[state] ?? state)").font(.meta).foregroundStyle(Theme.muted) }
                            .listRowBackground(Color.clear)
                    }
                }
                if let error {
                    Section { Text(error).font(.meta).foregroundStyle(Theme.rose) }.listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.cyan)
            .navigationTitle(calling ? "Call" : "New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.secondary) }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView().tint(Theme.muted) }
                    else { Button(calling ? "Start and call" : "Open") { Task { await start() } }.disabled(!valid).fontWeight(.semibold) }
                }
            }
            .task { await loadLines() }
            .onChange(of: brand) { _, _ in state = ""; suggest() }
            .onChange(of: place) { _, _ in suggest() }
            .onChange(of: phone) { _, _ in suggest() }
        }
        .preferredColorScheme(.dark)
    }

    private func loadLines() async {
        if !primed {
            primed = true
            name = prefill.name; phone = prefill.phone; place = prefill.place
        }
        // A branch member never sees a line: nothing to load.
        if let fixed = fixedBrand { brand = fixed; return }
        do { lines = try await API.lines() } catch { self.error = error.localizedDescription }
        if brand.isEmpty, let b = prefill.brand, !(statesFor[b]?.isEmpty ?? true) { brand = b }
        suggest()
    }

    /// What the place says, else what the area code says; one state is the state.
    private func suggest() {
        if fixedBrand != nil { return }
        let s = fromPlace ?? fromArea
        if let s, states.contains(s) { state = s }
        else if states.count == 1 { state = states[0] }
    }

    private func start() async {
        busy = true
        defer { busy = false }
        do {
            let fixed = fixedBrand
            // A branch member: the server uses their brand and falls back to their own state.
            let sendBrand = fixed ?? brand
            let sendState = fixed != nil ? (fromPlace ?? fromArea ?? "") : state
            let r = try await API.startThread(phone: phone, name: name, brand: sendBrand, state: sendState, guessed: guessed)
            let shown = name.trimmingCharacters(in: .whitespaces)
            onStarted(r.personId, r.threadId, shown.isEmpty ? "New conversation" : shown, sendBrand)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The desktop's `stateFromPlace` / `stateFromAreaCode` (web/src/lib/inbox.ts).
enum Places {
    static let name: [String: String] = [
        "AZ": "Arizona", "UT": "Utah", "ID": "Idaho", "CO": "Colorado", "FL": "Florida", "WA": "Washington", "NV": "Nevada",
        "NM": "New Mexico", "TX": "Texas", "CA": "California", "OR": "Oregon", "MT": "Montana", "WY": "Wyoming",
    ]

    private static let area: [String: String] = {
        var m: [String: String] = [:]
        let groups: [(String, [String])] = [
            ("AZ", ["480", "520", "602", "623", "928"]),
            ("UT", ["385", "435", "801"]),
            ("ID", ["208", "986"]),
            ("CO", ["303", "719", "720", "970", "983"]),
            ("WA", ["206", "253", "360", "425", "509", "564"]),
            ("FL", ["239", "305", "321", "352", "386", "407", "561", "727", "754", "772", "786", "813", "850", "863", "904", "941", "954"]),
        ]
        for (s, codes) in groups { for c in codes { m[c] = s } }
        return m
    }()

    /// "Mesa, AZ" or "Mesa, Arizona" → AZ.
    static func state(in place: String) -> String? {
        let cleaned = place.uppercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        let p = " \(String(cleaned)) "
        for (code, full) in name.sorted(by: { $0.key < $1.key }) {
            if p.contains(" \(full.uppercased()) ") || p.contains(" \(code) ") { return code }
        }
        return nil
    }

    static func state(forPhone phone: String) -> String? {
        var d = phone.filter(\.isNumber)
        if d.count == 11, d.first == "1" { d.removeFirst() }
        guard d.count == 10 else { return nil }
        return area[String(d.prefix(3))]
    }
}
