import SwiftUI

/// "Who is this?" on a first contact (founder, 2026-11-09: "NOT everyone is
/// a homeowner right off the bat"). One tap. Spam releases every
/// conversation with them and keeps them out of Waiting. Shown while the
/// server says `ask_type`.
struct WhoIsThisBar: View {
    let personId: String
    let name: String
    let onDone: (String) -> Void

    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Who is this?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("First time they have reached us.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            HStack(spacing: 5) {
                ForEach(ContactType.all, id: \.value) { c in
                    Button { pick(c.value) } label: {
                        Text(busy == c.value ? "…" : c.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(c.value == "spam" ? Theme.rose : Theme.text)
                            .lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.rose) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private func pick(_ type: String) {
        busy = type
        Task {
            do { try await API.setContactType(personId, type: type); error = nil; onDone(type) }
            catch { self.error = "Could not save it: \(error.localizedDescription)" }
            busy = nil
        }
    }
}

/// Release a conversation (hold its row): off the waiting list with a
/// reason, logged. The inbox and Personal both use it.
struct ReleaseSheet: View {
    let name: String
    let threadId: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var why = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Takes this conversation off the waiting list now. It comes back the moment they text or call again. Your reason is saved in the log.")
                    .font(.meta).foregroundStyle(Theme.secondary)
                TextField("", text: $why, prompt: Text("Why? (wrong number, handled on a call, spam, they said no thanks…)").foregroundStyle(Theme.muted), axis: .vertical)
                    .lineLimit(3...6)
                    .font(.ui).foregroundStyle(Theme.text)
                    .focused($focused)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.input))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Theme.cyan.opacity(0.6) : Theme.inputBorder))
                if let error { Text(error).font(.meta).foregroundStyle(Theme.rose) }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg)
            .navigationTitle("Release \(name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Release") { release() }.disabled(busy || why.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }

    private func release() {
        busy = true
        Task {
            do { try await API.releaseThread(threadId, reason: why.trimmingCharacters(in: .whitespacesAndNewlines)); onDone(); dismiss() }
            catch { self.error = "Could not release it: \(error.localizedDescription)"; busy = false }
        }
    }
}

/// A person to act on from a list row (release, contact info).
struct PersonTarget: Identifiable, Hashable {
    let personId: String
    let threadId: String
    let name: String
    var id: String { threadId }
}

/// Their contact info, the inbox's own panel (founder, 2026-11-09: "adjust
/// contact info for phone numbers in personal lines just as we would in
/// regular conversations"): who they are, a name when they have none,
/// email, address, a note, where they came in, their appointment.
struct ContactInfoSheet: View {
    let personId: String
    var threadId: String?
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var view: PersonView?
    @State private var d: PersonDetails?
    @State private var house: URL?
    @State private var houseBig = false
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var newName = ""
    @State private var error: String?
    @State private var saved: String?

    var body: some View {
        NavigationStack {
            Form {
                if let v = view {
                    Section {
                        HStack(spacing: 12) {
                            BranchMark(brand: v.threads.first { $0.id == v.threadId }?.brand, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.person.name).font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
                                if let c = v.person.city { Text(c).font(.meta).foregroundStyle(Theme.muted).lineLimit(1) }
                            }
                        }
                        if let h = house {
                            Button { houseBig = true } label: {
                                RemoteImage(url: h, fill: true).frame(height: 140).frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Their house. Tap to view it full screen.")
                        }
                        Picker(v.person.typeKnown == true ? "They are" : "Who is this?", selection: Binding(
                            get: { v.person.typeKnown == true ? (v.person.contactType ?? "") : "" },
                            set: { t in if !t.isEmpty { setType(t) } })) {
                            if v.person.typeKnown != true { Text("Not said yet").tag("") }
                            ForEach(ContactType.all, id: \.value) { c in Text(c.label).tag(c.value) }
                        }
                    }
                    .listRowBackground(Theme.card)

                    if v.person.hasName == false {
                        Section(label: "Name them") {
                            ForEach(d?.nameSuggestions ?? [], id: \.name) { s in
                                Button { rename(s.name.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)) } label: {
                                    HStack {
                                        Text(s.name).foregroundStyle(Theme.text)
                                        Spacer()
                                        if let src = s.source { Text(src).font(.meta).foregroundStyle(Theme.muted) }
                                    }
                                }
                            }
                            HStack {
                                TextField("Their name", text: $newName).foregroundStyle(Theme.text)
                                Button("Save") { rename(newName) }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }

                    Section(label: "Contact") {
                        field("Email", "name@example.com", $email, keyboard: .emailAddress) { save(email: email) }
                        field("Address", "Street, city, state", $address) { save(address: address) }
                        if (d?.address ?? "").isEmpty, let found = d?.foundAddress, !found.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Address from their text\(d?.foundAt.map { " \(Stamp.when($0))" } ?? "")").font(.meta).foregroundStyle(Theme.muted)
                                    Text(found).foregroundStyle(Theme.text)
                                }
                                Spacer()
                                Button("Save") { address = found; save(address: found) }
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section(label: "Note") {
                        TextField("Anything the team should know", text: $notes, axis: .vertical).lineLimit(2...6).foregroundStyle(Theme.text)
                        if notes != (d?.notes ?? "") { Button("Save note") { save(notes: notes) } }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        if let w = v.lead?.description, !w.isEmpty { row("Wants", w) }
                        if let s = v.person.source, !s.isEmpty { row("Came in on", s) }
                        row("Appointment", appointment(v), muted: v.appointment == nil)
                        if let h = v.history, !h.isEmpty {
                            // Never who holds them: only where else they have talked to us.
                            row("Also", h.map { $0.brand.map { Branch.of($0).name } ?? "another line" }.joined(separator: " · "))
                        }
                    }
                    .listRowBackground(Theme.card)

                    if let saved { Text(saved).font(.meta).foregroundStyle(Theme.green).listRowBackground(Theme.bg) }
                    if let error { Text(error).font(.meta).foregroundStyle(Theme.rose).listRowBackground(Theme.bg) }
                } else if let error {
                    ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Theme.bg)
                } else {
                    HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }.listRowBackground(Theme.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Contact info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $houseBig) { ImageViewer(url: house) }
        }
        .task { await load() }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default, save: @escaping () -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted).frame(width: 70, alignment: .leading)
            TextField(placeholder, text: text)
                .foregroundStyle(Theme.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .submitLabel(.done)
                .onSubmit(save)
            if text.wrappedValue != original(label) {
                Button("Save", action: save).font(.metaMedium)
            }
        }
    }

    private func original(_ label: String) -> String {
        label == "Email" ? (d?.email ?? "") : (d?.address ?? "")
    }

    private func row(_ label: String, _ value: String, muted: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(muted ? Theme.muted : Theme.text).multilineTextAlignment(.trailing)
        }
    }

    private func appointment(_ v: PersonView) -> String {
        guard let a = v.appointment else { return "None yet" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        let day = f.date(from: a.date).map { out.string(from: $0) } ?? a.date
        return "\(a.type ?? "Appointment") \(day)\(a.time.map { " \($0)" } ?? "")\(a.confirmed == true ? ", confirmed" : "")"
    }

    private func load() async {
        do {
            async let pv = API.person(personId, thread: threadId)
            async let dd = API.personDetails(personId)
            view = try await pv
            d = try? await dd
            email = d?.email ?? ""; address = d?.address ?? ""; notes = d?.notes ?? ""
            if view == nil { error = "This person isn't yours to see." } else { error = nil }
            if house == nil, view?.person.nexusLeadId != nil || view?.lead != nil,
               let s = try? await API.housePhoto(personId), let u = URL(string: s) { house = u }
        } catch { self.error = error.localizedDescription }
    }

    private func save(email: String? = nil, address: String? = nil, notes: String? = nil) {
        Task {
            do {
                try await API.personUpdate(personId, email: email, address: address, notes: notes)
                saved = "Saved."; error = nil
                await load(); onChanged()
            } catch { self.error = "Could not save it: \(error.localizedDescription)" }
        }
    }

    private func setType(_ t: String) {
        Task {
            do { try await API.setContactType(personId, type: t); saved = t == "spam" ? "Marked as spam. Released and out of Waiting." : "Saved."; await load(); onChanged() }
            catch { self.error = "Could not change it: \(error.localizedDescription)" }
        }
    }

    private func rename(_ n: String) {
        let name = n.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do { try await API.personRename(personId, name: name); newName = ""; saved = "Saved."; await load(); onChanged() }
            catch { self.error = "Could not name them: \(error.localizedDescription)" }
        }
    }
}
