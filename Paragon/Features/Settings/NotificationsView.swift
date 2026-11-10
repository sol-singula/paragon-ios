import SwiftUI

// MARK: Model (paragon_notify_prefs)

struct NotifyScopeValue: Decodable, Hashable {
    let value: String
    let label: String
}

struct NotifyScopeOption: Decodable, Hashable {
    let label: String?
    let values: [NotifyScopeValue]
}

struct NotifyOptions: Decodable, Hashable {
    let scope: NotifyScopeOption?
}

struct NotifyCategory: Decodable, Hashable, Identifiable {
    let key: String
    let label: String
    let description: String?
    let defaultPush: Bool
    let defaultSound: Bool
    let defaultBreakthrough: Bool
    let quietHours: Bool
    let settingsElsewhere: String?
    let options: NotifyOptions?
    let defaultScope: String?
    var push: Bool
    var sound: Bool
    var breakthrough: Bool
    var scope: String?

    var id: String { key }
}

struct NotifyQuiet: Decodable, Hashable {
    var enabled: Bool
    var start: String
    var end: String
    var days: [Int]
    var timeZone: String
    var mode: String
    var activeNow: Bool
}

struct NotifyCalls: Decodable, Hashable {
    var ringInQuiet: Bool
}

struct NotifyPrefs: Decodable, Hashable {
    let role: String?
    var categories: [NotifyCategory]
    var quiet: NotifyQuiet
    var calls: NotifyCalls
}

extension API {
    static func notifyPrefs() async throws -> NotifyPrefs {
        try await rpc("paragon_notify_prefs", as: NotifyPrefs.self)
    }

    /// `p` holds only what changes: categories.<key>.{push,sound,breakthrough,scope},
    /// quiet.{enabled,start,end,days,time_zone,mode}, calls.ring_in_quiet, or reset.
    static func notifyPrefsSet(_ p: [String: Any]) async throws -> NotifyPrefs {
        try await rpc("paragon_notify_prefs_set", ["p": p], as: NotifyPrefs.self)
    }
}

/// Every change is shown at once, saved through paragon_notify_prefs_set,
/// and put back to what the server last said if it refuses.
@MainActor @Observable
final class NotifyPrefsModel {
    var prefs: NotifyPrefs?
    var error: String?
    private var confirmed: NotifyPrefs?
    private var seq = 0

    func load() async {
        do { let p = try await API.notifyPrefs(); confirmed = p; prefs = p; error = nil }
        catch { self.error = error.localizedDescription }
    }

    func save(_ patch: [String: Any], optimistic: (inout NotifyPrefs) -> Void) {
        seq += 1
        let n = seq
        if var p = prefs { optimistic(&p); prefs = p }
        Task {
            do {
                let r = try await API.notifyPrefsSet(patch)
                confirmed = r
                if n == seq { prefs = r; error = nil }
            } catch {
                if n == seq { prefs = confirmed }
                self.error = error.localizedDescription
            }
        }
    }

    func category(_ key: String, _ field: String, _ value: Any, apply: @escaping (inout NotifyCategory) -> Void) {
        save(["categories": [key: [field: value]]]) { p in
            if let i = p.categories.firstIndex(where: { $0.key == key }) { apply(&p.categories[i]) }
        }
    }

    func quiet(_ field: String, _ value: Any, apply: @escaping (inout NotifyQuiet) -> Void) {
        save(["quiet": [field: value]]) { p in apply(&p.quiet) }
    }

    func reset() async {
        seq += 1
        let n = seq
        do {
            let r = try await API.notifyPrefsSet(["reset": true])
            confirmed = r
            if n == seq { prefs = r; error = nil }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: View

/// Settings → Notifications (founder, 2026-11-09: "staff should have MAJOR
/// customization around how they are notified"). Drawn from the server's
/// list of categories; nothing about a category is hard coded here.
struct NotificationsView: View {
    @State private var model = NotifyPrefsModel()
    @State private var confirmReset = false
    @State private var teamOpen = false

    private static let commonZones = [("America/Denver", "Mountain"), ("America/Phoenix", "Arizona"), ("America/Boise", "Boise"),
                                      ("America/Los_Angeles", "Pacific"), ("America/Chicago", "Central"), ("America/New_York", "Eastern")]
    private static let days = [(1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")]
    /// The texts category's choices, in the founder's words.
    private static let scopeLabel = ["mine": "Only mine", "mine_and_new": "Mine and new ones nobody has yet", "all": "Every conversation I can see"]

    var body: some View {
        Form {
            if let e = model.error {
                Text(e).font(.meta).foregroundStyle(Theme.rose).listRowBackground(Theme.bg)
            }
            if let p = model.prefs {
                Section {
                    Text("Yours alone, on every phone and computer you sign in on. These decide what pops up and what makes a sound.")
                        .font(.meta).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.bg)

                ForEach(p.categories) { c in categorySection(c, quietOn: p.quiet.enabled) }

                quietSection(p.quiet)

                Section(label: "Calls") {
                    Toggle(isOn: Binding(get: { p.calls.ringInQuiet }, set: { v in
                        model.save(["calls": ["ring_in_quiet": v]]) { $0.calls.ringInQuiet = v }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ring my phones during quiet hours")
                            Text("Off, a call does not ring you while your quiet hours are on. If nobody else could take it, it rings you anyway.")
                                .font(.meta).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.cyan)
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Reset to defaults", role: .destructive) { confirmReset = true }
                }
                .listRowBackground(Theme.card)
            } else if model.error == nil {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Theme.bg)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $teamOpen) { DndSheet().presentationDetents([.medium, .large]) }
        .confirmationDialog("Reset notifications to the defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await model.reset() } }
        } message: {
            Text("Every switch, the texts you are told about, quiet hours and calls go back to how Paragon starts.")
        }
    }

    @ViewBuilder
    private func categorySection(_ c: NotifyCategory, quietOn: Bool) -> some View {
        let team = c.settingsElsewhere == "team"
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.label).font(.uiMedium).foregroundStyle(Theme.text)
                if let d = c.description { Text(d).font(.meta).foregroundStyle(Theme.muted) }
            }
            .padding(.vertical, 2)
            Toggle("Push", isOn: Binding(get: { c.push }, set: { v in
                model.category(c.key, "push", v) { $0.push = v }
            }))
            .tint(Theme.cyan)
            Toggle("Sound", isOn: Binding(get: { c.sound }, set: { v in
                model.category(c.key, "sound", v) { $0.sound = v }
            }))
            .tint(Theme.cyan)
            .disabled(!c.push)
            if c.quietHours && !team {
                Toggle(isOn: Binding(get: { c.breakthrough }, set: { v in
                    model.category(c.key, "breakthrough", v) { $0.breakthrough = v }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Break through quiet hours")
                        if !quietOn { Text("Only matters while quiet hours are on.").font(.meta).foregroundStyle(Theme.muted) }
                    }
                }
                .tint(Theme.cyan)
                .disabled(!c.push)
            }
            if let values = c.options?.scope?.values, !values.isEmpty {
                Picker(c.options?.scope?.label ?? "Which conversations", selection: Binding(
                    get: { c.scope ?? c.defaultScope ?? values[0].value },
                    set: { v in model.category(c.key, "scope", v) { $0.scope = v } })) {
                    ForEach(values, id: \.value) { o in Text(Self.scopeLabel[o.value] ?? o.label).tag(o.value) }
                }
                .pickerStyle(.navigationLink)
            }
            if team {
                Button { teamOpen = true } label: {
                    HStack {
                        Text("Team chat settings").foregroundStyle(Theme.cyan)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
            }
        } footer: {
            if team { Text("Each channel's bell is in the channel. Quiet hours here never apply to Team chat.") }
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private func quietSection(_ q: NotifyQuiet) -> some View {
        Section {
            Toggle(isOn: Binding(get: { q.enabled }, set: { v in model.quiet("enabled", v) { $0.enabled = v } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet hours")
                    Text("While they are on, only what you let break through makes a sound.").font(.meta).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.cyan)
            if q.enabled && q.activeNow {
                Label("Quiet hours are on now", systemImage: "moon.fill").font(.metaMedium).foregroundStyle(Theme.amber)
            }
            Group {
                DatePicker("From", selection: time(q.start) { v in model.quiet("start", v) { $0.start = v } }, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: time(q.end) { v in model.quiet("end", v) { $0.end = v } }, displayedComponents: .hourAndMinute)
                VStack(alignment: .leading, spacing: 6) {
                    Text("On the nights starting").font(.meta).foregroundStyle(Theme.muted)
                    HStack(spacing: 6) {
                        ForEach(Self.days, id: \.0) { d in
                            let sel = q.days.contains(d.0)
                            Button {
                                var ds = q.days
                                if sel { ds.removeAll { $0 == d.0 } } else { ds.append(d.0); ds.sort() }
                                model.quiet("days", ds) { $0.days = ds }
                            } label: {
                                Text(d.1).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(sel ? Theme.text : Theme.muted)
                                    .frame(width: 34, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(sel ? Theme.cyan.opacity(0.12) : .clear))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(sel ? Theme.cyan.opacity(0.6) : Theme.border))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[d.0 % 7])
                            .accessibilityAddTraits(sel ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 2)
                Picker("Time zone", selection: Binding(get: { q.timeZone }, set: { v in model.quiet("time_zone", v) { $0.timeZone = v } })) {
                    let here = TimeZone.current.identifier
                    if !Self.commonZones.contains(where: { $0.0 == q.timeZone }) && !TimeZone.knownTimeZoneIdentifiers.contains(q.timeZone) {
                        Text(q.timeZone).tag(q.timeZone)
                    }
                    Section("Common") {
                        ForEach(Self.commonZones, id: \.0) { z in Text(z.1 + (z.0 == here ? " (this iPhone)" : "")).tag(z.0) }
                    }
                    Section("Everywhere") {
                        ForEach(TimeZone.knownTimeZoneIdentifiers.filter { id in !Self.commonZones.contains { $0.0 == id } }, id: \.self) { z in
                            Text(z.replacingOccurrences(of: "_", with: " ") + (z == here ? " (this iPhone)" : "")).tag(z)
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                Picker("During quiet hours", selection: Binding(get: { q.mode }, set: { v in model.quiet("mode", v) { $0.mode = v } })) {
                    Text("Deliver silently").tag("silent")
                    Text("Hold until quiet hours end").tag("hold")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .disabled(!q.enabled)
            .opacity(q.enabled ? 1 : 0.6)
        } header: {
            SectionLabel("Quiet hours")
        } footer: {
            Text("The day chips are the day quiet hours start on; an overnight window runs into the next morning.")
        }
        .listRowBackground(Theme.card)
    }

    /// "21:00" as a time of day for the picker; a new time is saved as "HH:MM".
    private func time(_ value: String, save: @escaping (String) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let parts = value.split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: parts.first ?? 0, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                let s = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                if s != value { save(s) }
            })
    }
}
