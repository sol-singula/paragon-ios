import SwiftUI

/// Who's on the phone, live (Build 25, founder 2026-11-16: "iOS users aren't
/// really able to see who's on the phone live like you would on desktop").
/// The desktop's team rail as a strip at the top of the inbox: each
/// teammate on a call (never me) with the red phone, their first name and
/// "with <them> · 4:07", ticking. A tap opens that call's conversation.
/// Nothing shows while nobody else is on the phone.
struct OnThePhoneStrip: View {
    @Environment(TeamStore.self) private var team

    var body: some View {
        let on = team.othersOnCall
        if !on.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(on.count) on the phone")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0xE5484D))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(on) { m in OnThePhoneChip(member: m) }
                    }
                }
            }
        }
    }
}

struct OnThePhoneChip: View {
    let member: TeamMember

    private var first: String { member.name.split(separator: " ").first.map(String.init) ?? member.name }

    var body: some View {
        // No line or brand on the chip, for anyone (branch members included);
        // `call_with` is whatever the server lets this person see.
        let chip = HStack(spacing: 8) {
            Face(name: member.name, url: member.photoUrl, size: 30)
                .presence(onCall: true, online: true, size: 30, ring: Theme.panel)
            VStack(alignment: .leading, spacing: 1) {
                Text(first).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let clock = CallClock.text(since: member.callStartedAt, now: ctx.date)
                    Text(member.callWith.map { "with \($0) · \(clock)" } ?? clock)
                        .font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().strokeBorder(Color(hex: 0xE5484D).opacity(0.35)))

        if let p = member.callPersonId, !p.isEmpty {
            Button { Router.shared.open(.person(personId: p, threadId: nil)) } label: { chip }
                .buttonStyle(.plain)
                .accessibilityLabel("\(member.name) is on a call\(member.callWith.map { " with \($0)" } ?? ""). Open the conversation.")
        } else {
            chip
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(member.name) is on a call\(member.callWith.map { " with \($0)" } ?? "")")
        }
    }
}

/// "Ryan is on the phone with them · 4:07", ticking: a conversation's header
/// line while someone else is on a call with this person.
struct OnThePhoneLine: View {
    let member: TeamMember

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 4) {
                Image(systemName: "phone.fill").font(.system(size: 9, weight: .bold))
                Text("\(member.name) is on the phone with them · \(CallClock.text(since: member.callStartedAt, now: ctx.date))")
                    .monospacedDigit().lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(hex: 0xE5484D))
        }
        .accessibilityElement(children: .combine)
    }
}
