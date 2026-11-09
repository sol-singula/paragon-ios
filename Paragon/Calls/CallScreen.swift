import SwiftUI

/// The call, full screen: who, how long, mute / keypad / speaker / end. The
/// chevron tucks it into the green bar above the tabs.
struct CallScreen: View {
    @Environment(CallManager.self) private var calls
    @State private var keypad = false
    @State private var typed = ""

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
                    BranchMark(brand: a.brand, size: 84)
                    Text(a.name).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 18).padding(.horizontal, 24)
                    if a.brand != nil { Text(Branch.of(a.brand).name).font(.ui).foregroundStyle(Theme.secondary).padding(.top, 4) }
                    CallClock(active: a).padding(.top, 10)
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
                    .padding(.bottom, 28)

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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22))
                    .foregroundStyle(on ? Color.black : Theme.text)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(on ? Theme.text : Color.white.opacity(0.12)))
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
