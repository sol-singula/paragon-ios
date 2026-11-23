import SwiftUI

/// One thing in a contact plan (`paragon_contact_plan`). `auto`: it goes out by itself.
struct ContactPlanItem: Decodable, Hashable {
    let kind: String
    let at: String?
    let title: String
    let detail: String?
    let who: String?
    let by: String?
    let auto: Bool?
    let id: String?
    let threadId: String?
    let date: String?
    let time: String?
}

struct ContactPlanChange: Decodable, Hashable {
    struct Cleared: Decodable, Hashable { let title: String; let dueAt: String? }
    struct Detail: Decodable, Hashable {
        let quote: String?
        let why: String?
        let nextContact: String?
        let closed: [Cleared]?
        let skippedSteps: Int?
        let settled: Bool?
    }
    let at: String
    let summary: String
    let detail: Detail?
}

struct ContactPlanData: Decodable {
    /// Their latest conversation: follow_up, planned, waiting, booked, sold,
    /// stopped, ended, quiet, not_homeowner, line_off.
    let state: String?
    let endedAfter: Int?
    let items: [ContactPlanItem]?
    /// Being worked out now: 'call', 'after_call', 'read', 'talking' (a text conversation still going) or
    /// 'settling' (Atlas reading where the texts ended, owner 2026-11-23).
    let updating: String?
    let changes: [ContactPlanChange]?
    let settle: Settle?

    /// paragon.thread_settle: a text conversation counts as ended 20 quiet minutes after the last text; Atlas then
    /// reads it once and moves the plan. `ended` is what it made of it.
    struct Settle: Decodable, Hashable {
        struct Ended: Decodable, Hashable { let at: String; let summary: String }
        let state: String?
        let settleAt: String?
        let ended: Ended?
    }
}

extension API {
    static func contactPlan(_ person: String) async throws -> ContactPlanData? {
        try await rpc("paragon_contact_plan", ["p_person": person], as: ContactPlanData?.self)
    }
}

/// The contact plan (founder, 2026-11-11: "underneath the contact info, I
/// need to be able to see the contact plan"), the desktop's
/// `screens/inbox/ContactPlan.tsx` in its design "Plan 1" (founder,
/// 2026-11-16): the label on top on one line with its state and
/// "+ Follow-up", one row per item with one quiet line under it, the next
/// one highlighted, and no "Booked: …" note repeating the appointment row.
/// Everything is the server's (paragon_contact_plan); nothing is decided here.
struct ContactPlanSection: View {
    let plan: ContactPlanData
    /// "+ Follow-up": a follow-up or promise (nil hides the button).
    var onAdd: (() -> Void)?

    @State private var all = false
    @State private var changeOpen = false

    var body: some View { content(plan) }

    /// Read every minute, every few seconds while Atlas is working it out.
    static func pollDelay(_ p: ContactPlanData?) -> Duration {
        p?.updating == "talking" ? .seconds(20) : p?.updating != nil ? .seconds(4) : .seconds(60)
    }

    @ViewBuilder private func content(_ p: ContactPlanData) -> some View {
        let items = p.items ?? []
        let shown = all ? items : Array(items.prefix(5))
        let end = Self.endNote(p)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("CONTACT PLAN")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1).fixedSize()
                if let u = p.updating { updating(u) }
                Spacer(minLength: 4)
                if let onAdd {
                    Button(action: onAdd) {
                        Label("Follow-up", systemImage: "plus")
                            .font(.metaMedium).foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a follow-up or promise")
                }
            }
            if p.updating == nil, let c = p.changes?.first, let d = Stamp.date(c.at), Date().timeIntervalSince(d) < 86_400 {
                lastChange(c, age: Date().timeIntervalSince(d))
            }
            if p.updating == nil, let e = p.settle?.ended, let d = Stamp.date(e.at),
               !(p.changes?.first.flatMap { Stamp.date($0.at) }.map { abs($0.timeIntervalSince(d)) < 120 } ?? false) {
                HStack(alignment: .top, spacing: 6) {
                    AtlasFace(size: 13).padding(.top, 1)
                    (Text("After the texts (\(Self.ago(Date().timeIntervalSince(d))) ago). ").fontWeight(.medium).foregroundStyle(Theme.text)
                     + Text(e.summary + ".").foregroundStyle(Theme.secondary))
                        .font(.system(size: 11.5)).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.violet.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.violet.opacity(0.3)))
            }
            if items.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    if end.warn { Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .semibold)).padding(.top, 2) }
                    Text(end.text.isEmpty ? "Nothing planned yet." : end.text).font(.meta)
                }
                .foregroundStyle(end.warn ? Theme.rose : Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(end.warn ? Theme.rose.opacity(0.1) : Theme.input))
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, it in step(it, first: i == 0) }
                }
            }
            if items.count > 5 {
                Button(all ? "Show less" : "Show all \(items.count)") { all.toggle() }
                    .font(.meta).foregroundStyle(Theme.secondary).buttonStyle(.plain)
            }
            // No "Booked: …" note under an appointment row that says it already.
            if !items.isEmpty, !end.text.isEmpty, !(p.state == "booked" && items.contains(where: { $0.kind == "appointment" })) {
                Text(end.text).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private func updating(_ why: String) -> some View {
        if why == "talking" {
            // The texts are still going: Atlas re-plans once, when they stop (owner, 2026-11-23).
            let t = plan.settle?.settleAt.flatMap { Stamp.date($0) }.map { $0.formatted(date: .omitted, time: .shortened) }
            let words = "Texting" + (t.map { " · plan updates ~\($0)" } ?? "")
            HStack(spacing: 4) {
                Image(systemName: "text.bubble").font(.system(size: 10, weight: .semibold))
                Text(words).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Theme.muted)
            .accessibilityLabel(words)
        } else {
            updatingSpinner(why)
        }
    }

    private func updatingSpinner(_ why: String) -> some View {
        let words = why == "call" ? "Waiting for call notes" : why == "after_call" ? "Updating" : why == "settling" ? "Reading where the texts ended" : "Atlas is reading"
        return HStack(spacing: 4) {
            ProgressView().controlSize(.mini).tint(Theme.violet)
            Text(words).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.violet).lineLimit(1)
        }
        .accessibilityLabel(words)
    }

    /// What Atlas changed last, for a day: tap for the words from the call and what it cleared.
    private func lastChange(_ c: ContactPlanChange, age: TimeInterval) -> some View {
        let cleared = c.detail?.closed ?? []
        let summary = c.summary.replacingOccurrences(of: "After the call: ", with: "After the call, ")
            .replacingOccurrences(of: "After the texts: ", with: "After the texts, ")
        return Button { withAnimation(.snappy) { changeOpen.toggle() } } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
                    AtlasFace(size: 13).padding(.top, 1)
                    (Text("Plan updated \(Self.ago(age)) ago. ").fontWeight(.medium).foregroundStyle(Theme.text)
                     + Text(summary + ".").foregroundStyle(Theme.secondary))
                        .font(.system(size: 11.5))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(changeOpen ? 180 : 0)).padding(.top, 2)
                }
                if changeOpen {
                    VStack(alignment: .leading, spacing: 2) {
                        if let q = c.detail?.quote, !q.isEmpty {
                            Text(c.detail?.settled == true ? "Next: \(q)\(c.detail?.why.map { " (\($0))" } ?? "")"
                                 : "On the call: \u{201C}\(q)\u{201D}\(c.detail?.why.map { " (\($0))" } ?? "")")
                        }
                        ForEach(Array(cleared.enumerated()), id: \.offset) { _, x in Text(x.title).strikethrough() }
                        if let n = c.detail?.skippedSteps, n > 0 {
                            Text("\(n) Atlas plan \(n == 1 ? "touch" : "touches") skipped")
                        }
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .padding(.leading, 19)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.violet.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.violet.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    /// One row: icon, title, when; one quiet line under it.
    private func step(_ it: ContactPlanItem, first: Bool) -> some View {
        let late = Stamp.date(it.at).map { $0 < Date() } ?? false
        let projected = it.kind == "next_follow_up"
        let sub: String = {
            if it.kind == "appointment" && it.auto == true { return "Confirmation and reminder go out on their own" }
            var who = it.kind == "clock" ? "Whoever answers" : "Anyone"
            if it.auto == true { who = "Automatic" }
            else if let w = it.who, let f = w.split(separator: " ").first { who = "Reminds \(f)" }
            var parts = [who]
            if let d = it.detail, !d.isEmpty { parts.append(d) }
            return parts.joined(separator: " · ")
        }()
        let highlight = first && !projected
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon(it).frame(width: 16)
                Text(it.title)
                    .font(.system(size: 14, weight: highlight || it.kind == "appointment" ? .medium : .regular))
                    .foregroundStyle(projected ? Theme.secondary : Theme.text)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Text(Self.when(it))
                    .font(.meta).monospacedDigit()
                    .foregroundStyle(late ? Theme.rose : first ? Theme.cyan : Theme.secondary)
                    .lineLimit(1).fixedSize()
            }
            if !sub.isEmpty {
                Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                    .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(highlight ? Theme.input : Color.clear))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func icon(_ it: ContactPlanItem) -> some View {
        let s = Font.system(size: 12, weight: .semibold)
        switch it.kind {
        case "clock": Image(systemName: "clock").font(s).foregroundStyle(Theme.muted)
        case "appointment": Image(systemName: "calendar.badge.checkmark").font(s).foregroundStyle(Theme.muted)
        case "scheduled", "plan_text": Image(systemName: "text.bubble").font(s).foregroundStyle(Theme.muted)
        case "plan_call", "web_form": Image(systemName: "phone").font(s).foregroundStyle(Theme.muted)
        case "follow_up", "next_follow_up": Image(systemName: "arrow.turn.down.right").font(s).foregroundStyle(Color(hex: 0x60A5FA))
        default:
            if it.by == "atlas" { AtlasFace(size: 14) }
            else { Image(systemName: "sparkles").font(s).foregroundStyle(Theme.muted) }
        }
    }

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    private static let ymd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f }()

    static func when(_ it: ContactPlanItem) -> String {
        if it.kind == "appointment", let ds = it.date {
            let day = ymd.date(from: ds).map { dayFmt.string(from: $0) } ?? ds
            return it.time.map { "\(day) \($0)" } ?? day
        }
        guard let d = Stamp.date(it.at) else { return "" }
        let ms = d.timeIntervalSinceNow
        if ms < 0 { return it.kind == "clock" ? "late \(ago(-ms))" : "due \(ago(-ms)) ago" }
        let cal = Calendar.current
        let t = timeFmt.string(from: d)
        if cal.isDateInToday(d) { return ms < 3600 ? "in \(max(1, Int((ms / 60).rounded())))m" : "today \(t)" }
        if cal.isDateInTomorrow(d) { return "tomorrow \(t)" }
        return "\(dayFmt.string(from: d)) \(t)"
    }

    static func ago(_ s: TimeInterval) -> String {
        s < 3600 ? "\(max(1, Int((s / 60).rounded())))m" : s < 86_400 ? "\(Int((s / 3600).rounded()))h" : "\(Int((s / 86_400).rounded()))d"
    }

    /// What the plan says when nothing more is coming, and why (the desktop's words).
    static func endNote(_ p: ContactPlanData) -> (text: String, warn: Bool) {
        switch p.state {
        case "booked": return ("Booked: the appointment texts take it from here.", false)
        case "sold": return ("Sold: no follow-ups needed.", false)
        case "stopped": return ("They replied STOP. Nothing will go to them.", false)
        case "line_off": return ("Contact plans are off for this line, so Atlas never plans follow-ups here.", false)
        case "not_homeowner": return ("Not a homeowner, so there is no contact plan.", false)
        case "ended": return ("Plan ended: \(p.endedAfter ?? 3) follow-ups and no answer from them. Add a follow-up to keep going.", true)
        case "quiet": return ("No word from them in 60 days, so Atlas stopped following up. Add a follow-up to start again.", true)
        case "follow_up", "planned", "waiting": return ("", false)
        default: return ("Nothing planned yet.", true)
        }
    }
}
