import SwiftUI

/// A channel's bell (owner, 2026-11-09): what reaches me from this channel,
/// muting it for a while, its quiet hours, and "always", which gets through
/// Do Not Disturb and quiet hours. Mute and Nothing still win over always.
struct ChannelBellSheet: View {
    let channelId: String
    @Environment(\.dismiss) private var dismiss
    @State private var model = TeamModel.shared

    var body: some View {
        NavigationStack {
            Form {
                if let c = model.channel(channelId) {
                    Section(label: "Notify me about") {
                        choice("All messages", on: c.notify == "all") { set(["notify": "all"]) }
                        choice("Only @mentions", sub: "@your name, @everyone", on: c.notify == "mentions") { set(["notify": "mentions"]) }
                        choice("Nothing", on: c.notify == "none") { set(["notify": "none"]) }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        if c.muted {
                            Button("Unmute") { set(["mute": "off"]) }.tint(Theme.cyan)
                        } else {
                            Button("For 1 hour") { set(["mute": "1h"]) }
                            Button("Until tomorrow morning") { set(["mute": "tomorrow"]) }
                            Button("Until I unmute it") { set(["mute": "forever"]) }
                        }
                    } header: {
                        SectionLabel(c.muted ? "Muted \(TeamTime.label(c.prefs?.mutedUntil))" : "Mute")
                    } footer: {
                        Text("A muted channel still tells you when someone @mentions you by name.")
                    }
                    .tint(Theme.text)
                    .listRowBackground(Theme.card)

                    Section {
                        QuietHoursEditor(value: c.prefs?.quiet, label: "Quiet hours for this channel") { q in
                            set(["quiet": q?.json ?? NSNull()])
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Toggle("Always notify me, even on Do Not Disturb", isOn: Binding(
                            get: { c.prefs?.always == true },
                            set: { v in set(["always": v]) }))
                            .tint(Theme.cyan)
                    } footer: {
                        Text("Gets through Do Not Disturb and quiet hours. Mute and Nothing still mean nothing.")
                    }
                    .listRowBackground(Theme.card)

                    if let e = model.error { Text(e).font(.meta).foregroundStyle(Theme.rose).listRowBackground(Theme.bg) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("# \(model.channel(channelId)?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func set(_ p: [String: Any]) { Task { await model.setPrefs(channelId, p) } }
}

/// My Do Not Disturb, my own after hours, and my time zone (Team only).
struct DndSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = TeamModel.shared

    private static let zones = [("America/Denver", "Mountain"), ("America/Phoenix", "Arizona"), ("America/Los_Angeles", "Pacific"),
                                ("America/Chicago", "Central"), ("America/New_York", "Eastern")]

    var body: some View {
        NavigationStack {
            Form {
                if let me = model.overview?.me {
                    Section {
                        if model.dndOn {
                            Button("Turn it off") { set(["dnd": "off"]) }.tint(Theme.cyan)
                        } else {
                            Button("For 1 hour") { set(["dnd": "1h"]) }
                            Button("For 8 hours") { set(["dnd": "8h"]) }
                            Button("Until tomorrow morning") { set(["dnd": "tomorrow"]) }
                            Button("Until I turn it off") { set(["dnd": "on"]) }
                        }
                    } header: {
                        SectionLabel(model.dndOn ? "Do Not Disturb \(TeamTime.label(me.dndUntil))" : "Do Not Disturb")
                    } footer: {
                        Text("Team only. Channels set to always notify still get through.")
                    }
                    .tint(Theme.text)
                    .listRowBackground(Theme.card)

                    Section {
                        QuietHoursEditor(value: me.quiet, label: "My after hours") { q in set(["quiet": q?.json ?? NSNull()]) }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Picker("My time", selection: Binding(
                            get: { me.timeZone ?? "America/Denver" },
                            set: { v in set(["time_zone": v]) })) {
                            if let tz = me.timeZone, !Self.zones.contains(where: { $0.0 == tz }) { Text(tz).tag(tz) }
                            ForEach(Self.zones, id: \.0) { z in Text(z.1).tag(z.0) }
                        }
                    }
                    .listRowBackground(Theme.card)

                    if let e = model.error { Text(e).font(.meta).foregroundStyle(Theme.rose).listRowBackground(Theme.bg) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Do Not Disturb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func set(_ p: [String: Any]) { Task { await model.setMine(p) } }
}

/// From–to and days, saved when a field changes. Off: nil.
struct QuietHoursEditor: View {
    let value: TeamQuiet?
    let label: String
    let onChange: (TeamQuiet?) -> Void

    @State private var q = TeamQuiet(start: "21:00", end: "07:00", days: [])
    private static let days = [(1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")]

    var body: some View {
        let on = value != nil
        Toggle(isOn: Binding(get: { on }, set: { v in onChange(v ? q : nil) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if on {
                    Text((q.days ?? []).isEmpty ? "Every day." : "On the days picked; an overnight window belongs to the day it starts.")
                        .font(.meta).foregroundStyle(Theme.muted)
                }
            }
        }
        .tint(Theme.cyan)
        .onAppear { if let value { q = value } }
        .onChange(of: value) { _, v in if let v { q = v } }
        if on {
            DatePicker("From", selection: time(\.start), displayedComponents: .hourAndMinute)
            DatePicker("To", selection: time(\.end), displayedComponents: .hourAndMinute)
            HStack(spacing: 6) {
                ForEach(Self.days, id: \.0) { d in
                    let sel = (q.days ?? []).contains(d.0)
                    Button {
                        var ds = q.days ?? []
                        if sel { ds.removeAll { $0 == d.0 } } else { ds.append(d.0); ds.sort() }
                        put(TeamQuiet(start: q.start, end: q.end, days: ds))
                    } label: {
                        Text(d.1).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(sel ? Theme.text : Theme.muted)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 7).fill(sel ? Theme.cyan.opacity(0.12) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(sel ? Theme.cyan.opacity(0.6) : Theme.border))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func put(_ n: TeamQuiet) {
        q = n
        if value != nil { onChange(n) }
    }

    /// "21:00" as a time of day for the picker, and back.
    private func time(_ key: WritableKeyPath<TeamQuiet, String>) -> Binding<Date> {
        Binding(
            get: {
                let parts = q[keyPath: key].split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: parts.first ?? 0, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                var n = q
                n[keyPath: key] = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                put(n)
            })
    }
}

/// A row with a check when it's the one chosen.
@ViewBuilder
private func choice(_ title: String, sub: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.text)
                if let sub { Text(sub).font(.meta).foregroundStyle(Theme.muted) }
            }
            Spacer()
            if on { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) }
        }
    }
}
