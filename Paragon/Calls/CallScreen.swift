import SwiftUI

/// The call, full screen: who, how long, mute / keypad / speaker / end. The
/// chevron tucks it into the green bar above the tabs.
struct CallScreen: View {
    @Environment(CallManager.self) private var calls
    @State private var keypad = false
    @State private var typed = ""
    @State private var facts: CallFacts?
    @State private var adding = false
    @State private var transferring = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0F2A26), Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let a = calls.active {
                VStack(spacing: 0) {
                    HStack {
                        Button { calls.showScreen = false } label: {
                            Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.secondary)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)

                    Spacer(minLength: 20)
                    // The desktop's "Orbit" (founder, 2026-11-09): amber while it
                    // rings, green once connected, a bright streak running round.
                    BranchMark(brand: a.brand, size: 84)
                        .overlay { OrbitRing(live: a.phase == .connected, lineWidth: 3).padding(-9) }
                    Text(a.name).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 18).padding(.horizontal, 24)
                    if a.brand != nil { Text(Branch.of(a.brand).name).font(.ui).foregroundStyle(Theme.secondary).padding(.top, 4) }
                    // The line on the call, small (the one they dialed on a call in).
                    if let line = a.line { Text(line).font(.system(size: 12)).foregroundStyle(Theme.secondary.opacity(0.8)).padding(.top, 1) }
                    CallClock(active: a).padding(.top, 10)
                    if !keypad { factsCard(a).padding(.top, 14).padding(.horizontal, 24) }
                    if keypad {
                        Text(typed.isEmpty ? " " : typed).font(.system(size: 26, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text).padding(.top, 18)
                    }
                    Spacer()

                    if keypad {
                        Keypad { d in typed += d; calls.digits(d) }.padding(.bottom, 24)
                    }

                    if a.direction == .incoming && a.phase == .ringing {
                        Button { calls.sendToAtlas() } label: {
                            HStack(spacing: 8) { AtlasRing(size: 16); Text("Send to Atlas").font(.uiMedium) }
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Capsule().fill(Theme.violet.opacity(0.18)))
                                .overlay(Capsule().strokeBorder(Theme.violet.opacity(0.5)))
                        }
                        .padding(.bottom, 24)
                    }

                    if a.direction == .incoming && a.phase == .ringing {
                        HStack(spacing: 70) {
                            Button { calls.end() } label: {
                                Image(systemName: "phone.down.fill").font(.system(size: 28)).foregroundStyle(.white)
                                    .frame(width: 76, height: 76).background(Circle().fill(Theme.rose))
                            }
                            .accessibilityLabel("Decline")
                            Button { calls.answer() } label: {
                                Image(systemName: "phone.fill").font(.system(size: 28)).foregroundStyle(.white)
                                    .frame(width: 76, height: 76).background(Circle().fill(Theme.green))
                            }
                            .accessibilityLabel("Answer")
                        }
                        .padding(.bottom, 40)
                    } else {
                    HStack(spacing: 28) {
                        RoundButton(symbol: a.muted ? "mic.slash.fill" : "mic.fill", label: "Mute", on: a.muted) { calls.toggleMute() }
                        RoundButton(symbol: "circle.grid.3x3.fill", label: "Keypad", on: keypad) { keypad.toggle() }
                        RoundButton(symbol: "speaker.wave.2.fill", label: "Speaker", on: a.speaker) { calls.toggleSpeaker() }
                    }
                    .padding(.bottom, 18)
                    if a.phase == .connected {
                        HStack(spacing: 28) {
                            RoundButton(symbol: "person.badge.plus", label: "Add", on: false, tint: Theme.green) { adding = true }
                            if a.direction == .incoming {
                                RoundButton(symbol: "arrow.left.arrow.right", label: "Transfer", on: false) { transferring = true }
                                    .disabled(calls.conference).opacity(calls.conference ? 0.4 : 1)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    Button { calls.end() } label: {
                        Image(systemName: "phone.down.fill").font(.system(size: 28)).foregroundStyle(.white)
                            .frame(width: 76, height: 76).background(Circle().fill(Theme.rose))
                    }
                    .accessibilityLabel("End call")
                    .padding(.bottom, 40)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: calls.active?.thread) { await loadFacts() }
        .sheet(isPresented: $adding) { AddToCallSheet(thread: calls.active?.thread ?? "", mode: .add) }
        .sheet(isPresented: $transferring) { AddToCallSheet(thread: calls.active?.thread ?? "", mode: .transfer) }
    }

    /// The client card under the name: the job, their last text, and who
    /// else is on the call.
    @ViewBuilder private func factsCard(_ a: CallManager.Active) -> some View {
        let on: [CallPerson] = calls.people.filter { $0.on }
        let job: String? = facts?.job
        let last: String? = on.isEmpty ? facts?.last : nil
        if job != nil || last != nil || !on.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let job { FactLine(label: "Job", value: job) }
                if let last { FactLine(label: "Last", value: last) }
                if !on.isEmpty {
                    FactLine(label: "With", value: Self.withText(on))
                    ForEach(on) { p in PersonLine(person: p) { calls.remove(p) } }
                    Text("If you leave, the others stay on.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        }
    }

    private static func firstName(_ n: String) -> String { n.split(separator: " ").first.map(String.init) ?? n }

    private static func withText(_ on: [CallPerson]) -> String {
        var names: [String] = ["You"]
        for p in on { names.append(p.status == "joining" ? firstName(p.name) + " (joining…)" : firstName(p.name)) }
        return names.joined(separator: ", ")
    }

    private func loadFacts() async {
        facts = nil
        guard let t = calls.active?.thread, !t.isEmpty,
              let card = try? await API.callCard(t),
              let v = try? await API.person(card.personId, thread: t) else { return }
        var job: [String] = []
        if let d = v.lead?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { job.append(String(d.prefix(80))) }
        if let ap = v.appointment {
            var parts: [String] = [ap.type ?? "Appointment", ap.date]
            if let t = ap.time { parts.append(t) }
            job.append(parts.joined(separator: " "))
        }
        var lastText: String? = nil
        if let e = v.timeline?.last(where: { $0.kind == "text" && !($0.body ?? "").isEmpty }) {
            let who: String = e.direction == "out" ? "Us: " : ""
            let body: String = String((e.body ?? "").prefix(80))
            lastText = who + "“" + body + "”"
        }
        facts = CallFacts(job: job.isEmpty ? nil : job.joined(separator: " · "), last: lastText)
    }
}

struct CallFacts: Equatable { let job: String?; let last: String? }

private struct FactLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(value).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(2)
        }
    }
}

private struct PersonLine: View {
    let person: CallPerson
    let remove: () -> Void
    var body: some View {
        let joining = person.status == "joining"
        HStack(spacing: 8) {
            Text(person.name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            Text(joining ? "Joining…" : "Talking").font(.system(size: 12)).foregroundStyle(joining ? Theme.amber : Theme.secondary)
            if !person.key.hasPrefix("tmp-") {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Take \(person.name) off the call")
            }
        }
    }
}

/// "Orbit": a bright streak running round a ring, amber and quick (1.6 s a
/// lap) while ringing, green and slower (3.2 s) once connected. Still for
/// Reduce Motion.
struct OrbitRing: View {
    let live: Bool
    var lineWidth: CGFloat = 3
    var cornerRadius: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var spin = false

    private var color: Color { live ? Color(hex: 0x10B981) : Color(hex: 0xF59E0B) }
    private var gradient: AngularGradient {
        AngularGradient(stops: [.init(color: color.opacity(0.18), location: 0), .init(color: color, location: 0.11),
                                .init(color: color.opacity(0.18), location: 0.25), .init(color: color.opacity(0.18), location: 1)],
                        center: .center)
    }

    var body: some View {
        Group {
            if let r = cornerRadius {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(still ? AnyShapeStyle(color) : AnyShapeStyle(gradient), lineWidth: lineWidth)
            } else {
                Circle()
                    .strokeBorder(still ? AnyShapeStyle(color) : AnyShapeStyle(gradient), lineWidth: lineWidth)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
        }
        .onAppear { if !still && cornerRadius == nil { spin = false; withAnimation(.linear(duration: live ? 3.2 : 1.6).repeatForever(autoreverses: false)) { spin = true } } }
        .onChange(of: live) { _, l in
            guard !still, cornerRadius == nil else { return }
            spin = false
            withAnimation(.linear(duration: l ? 3.2 : 1.6).repeatForever(autoreverses: false)) { spin = true }
        }
        .allowsHitTesting(false)
    }
}

/// Add to this call (teammates with online dots, or a number), or Transfer.
struct AddToCallSheet: View {
    enum Mode { case add, transfer }
    let thread: String
    let mode: Mode
    @Environment(CallManager.self) private var calls
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [CallTarget]?
    @State private var q = ""
    @MainActor private var presence: Presence { Presence.shared }

    private var digits: String { q.filter(\.isNumber) }

    var body: some View {
        NavigationStack {
            List {
                Section("Team") {
                    if targets == nil { ProgressView().tint(Theme.muted) }
                    if let t = targets, t.isEmpty { Text("Nobody else can take this caller.").font(.meta).foregroundStyle(Theme.muted) }
                    ForEach((targets ?? []).filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }) { t in
                        let already = calls.people.contains { $0.id == t.id && $0.on }
                        Button {
                            if mode == .add { calls.add(member: t.id, name: t.name) } else { calls.transfer(to: t) }
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Face(name: t.name, url: nil, size: 28)
                                Text(t.name).foregroundStyle(Theme.text)
                                Spacer()
                                if t.busy == true { Text("on a call").font(.meta).foregroundStyle(Theme.muted) }
                                else { Circle().fill(presence.online.contains(t.id) ? Theme.green : Theme.muted).frame(width: 8, height: 8)
                                        .accessibilityLabel(presence.online.contains(t.id) ? "Online" : "Offline") }
                            }
                        }
                        .disabled(t.busy == true || already)
                    }
                }
                if mode == .add {
                    Section("Or a number") {
                        Button {
                            calls.add(number: q, name: q)
                            dismiss()
                        } label: {
                            Text(digits.count >= 10 ? "Dial \(q)" : "Type a number in the search").foregroundStyle(digits.count >= 10 ? Theme.text : Theme.muted)
                        }
                        .disabled(digits.count < 10)
                    }
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or number…")
            .navigationTitle(mode == .add ? "Add to this call" : "Hand the call to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { targets = (try? await API.callTargets(thread: thread)) ?? [] }
    }
}

/// "Calling…", "Ringing…", or the running time once connected.
struct CallClock: View {
    let active: CallManager.Active

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(text(ctx.date)).font(.system(size: 16, weight: .medium)).monospacedDigit()
                .foregroundStyle(active.phase == .connected ? Theme.cyan : Theme.secondary)
        }
    }

    private func text(_ now: Date) -> String {
        switch active.phase {
        case .ringing: return active.direction == .incoming ? "Incoming call" : "Ringing…"
        case .connecting: return active.direction == .incoming ? "Connecting…" : "Calling…"
        case .reconnecting: return "Reconnecting…"
        case .connected:
            let s = Int(now.timeIntervalSince(active.connectedAt ?? now))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let on: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22))
                    .foregroundStyle(on ? Color.black : Theme.text)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(on ? Theme.text : (tint?.opacity(0.3) ?? Color.white.opacity(0.12))))
                Text(label).font(.meta).foregroundStyle(Theme.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Keypad: View {
    let tap: (String) -> Void
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { d in
                        Button { tap(d) } label: {
                            Text(d).font(.system(size: 26)).foregroundStyle(Theme.text)
                                .frame(width: 62, height: 62).background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// On a call with the screen tucked away: a green bar above the tabs, the
/// same "find the call fast" the desktop's green button gives.
struct CallBar: View {
    @Environment(CallManager.self) private var calls

    var body: some View {
        if let a = calls.active {
            Button { calls.showScreen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill").font(.system(size: 12, weight: .bold))
                    Text(a.name).font(.metaMedium).lineLimit(1)
                    CallClock(active: a)
                    Spacer()
                    Text("Return to call").font(.metaMedium)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.green)
                // The same Orbit as the call screen, so it is easy to find.
                .overlay { OrbitBar(live: a.phase == .connected) }
            }
            .buttonStyle(.plain)
        }
    }
}

/// After a connected call ends (founder, 2026-11-09): Add promise, or Follow
/// up later (WHO = me, WHAT "Follow up with <name>"). × dismisses it; it goes
/// by itself after 30 s, and the next call clears it.
struct CallFollowUpBar: View {
    let ended: CallManager.Ended
    let open: (PromiseTarget) -> Void
    @Environment(CallManager.self) private var calls

    var body: some View {
        HStack(spacing: 8) {
            Text("Call with \(ended.name) ended").font(.meta).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Button {
                open(PromiseTarget(threadId: ended.thread, personId: nil, name: ended.name))
                calls.clearEnded()
            } label: { Text("Add promise").font(.metaMedium) }
            .buttonStyle(.bordered).tint(Theme.violet).controlSize(.small)
            Button {
                open(PromiseTarget(threadId: ended.thread, personId: nil, name: ended.name, prefill: "Follow up with \(ended.name)"))
                calls.clearEnded()
            } label: { Text("Follow up later").font(.metaMedium) }
            .buttonStyle(.bordered).tint(Theme.teal).controlSize(.small)
            Button { calls.clearEnded() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The green bar's border: a light streak running along it (still for Reduce Motion).
private struct OrbitBar: View {
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var x: CGFloat = -1

    var body: some View {
        GeometryReader { g in
            if !still {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.35)
                    .offset(x: x * g.size.width)
                    .onAppear { withAnimation(.linear(duration: live ? 3.2 : 1.6).repeatForever(autoreverses: false)) { x = 1 } }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
