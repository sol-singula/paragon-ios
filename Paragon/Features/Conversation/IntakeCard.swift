import SwiftUI

// MARK: What a customer call settled, for Nexus (paragon_call_intake / paragon-intake)

struct IntakeProposal: Decodable {
    struct Appointment: Decodable {
        let agreed: Bool?
        let date: String?
        let time: String?
        let type: String?
        let typeWhy: String?
        let notes: String?
    }
    let name: String?
    let address: String?
    let email: String?
    let description: String?
    let appointment: Appointment?
    let alreadyBookedId: String?
    let summary: String?
}

/// Who goes, from Crew (founder, 2026-11-16): the zone's primary for the
/// type's seat, the backup when the primary is busy, the nearest when nobody
/// is picked; nothing when the address is unknown or outside every zone.
struct IntakeAssignee: Decodable, Equatable {
    let why: String?
    let role: String?
    let area: String?
    let userId: String?
    let name: String?
    let primary: String?
    let backup: String?
    let busyAt: String?
}

/// The card's edits, kept with the call.
struct IntakeDraft: Decodable {
    struct Texts: Decodable { let onBooking: Bool?; let dayBefore: Bool?; let sameDay: Bool? }
    let name: String?
    let address: String?
    let email: String?
    let description: String?
    let company: String?
    let book: Bool?
    let type: String?
    let date: String?
    let time: String?
    let notes: String?
    let assignee: String?
    let assigneePicked: Bool?
    let texts: Texts?
}

struct IntakeGeo: Decodable, Hashable {
    let address: String?
    let lat: Flex?
    let lon: Flex?
    let found: Bool?
}

struct CallIntake: Decodable {
    struct Call: Decodable { let id: String; let at: String?; let ended: Bool?; let words: Bool? }
    struct Line: Decodable { let label: String?; let state: String?; let company: String? }
    struct Company: Decodable { let key: String; let name: String }
    struct Lead: Decodable { let id: String; let name: String?; let address: String?; let how: String?; let mapped: Bool? }
    struct Who: Decodable { let id: String; let name: String? }
    /// Which confirmation texts this company sends, as the console's appointment form reads them.
    struct Texts: Decodable { let onBooking: Bool?; let types: [String]?; let dayBefore: Bool?; let sameDay: Bool?; let hours: Flex? }
    struct Appointment: Decodable { let id: String; let date: String?; let time: String?; let typeName: String?; let upcoming: Bool? }
    struct Result: Decodable {
        let leadId: String?
        let appointmentId: String?
        let created: Bool?
        let type: String?
        let date: String?
        let time: String?
        let by: String?
    }
    struct Claim: Decodable { let id: String?; let name: String? }
    struct Intake: Decodable {
        let status: String?
        let proposal: IntakeProposal?
        let result: Lenient<ResultBox>?
        let draft: Lenient<DraftBox>?
        let geo: Lenient<IntakeGeo>?
        /// Someone pressed the button and it is running (one press at a time).
        let claimedBy: Claim?
        /// Held for the rep who took the call until then; nobody else sees the card before it.
        let heldUntil: String?
    }

    let call: Call
    let space: String?
    let personId: String
    let threadId: String
    let name: String?
    let email: String?
    let address: String?
    let phone: String?
    let line: Line?
    let zone: String?
    let company: Company?
    let lead: Lead?
    let texts: Texts?
    let appointments: [Appointment]?
    let intake: Intake?
}

/// Lenient needs Hashable; these boxes carry the plain structs.
struct ResultBox: Decodable, Hashable {
    let value: CallIntake.Result
    init(from decoder: Decoder) throws { value = try CallIntake.Result(from: decoder) }
    static func == (a: ResultBox, b: ResultBox) -> Bool { true }
    func hash(into h: inout Hasher) {}
}
struct DraftBox: Decodable, Hashable {
    let value: IntakeDraft
    init(from decoder: Decoder) throws { value = try IntakeDraft(from: decoder) }
    static func == (a: DraftBox, b: DraftBox) -> Bool { true }
    func hash(into h: inout Hasher) {}
}

extension CallIntake.Intake {
    var resultValue: CallIntake.Result? { result?.value?.value }
    var draftValue: IntakeDraft? { draft?.value?.value }
    var geoValue: IntakeGeo? { geo?.value }
}

/// Reads any answer and keeps nothing (inserts whose rows are not needed).
struct Ignored: Decodable { init(from decoder: Decoder) throws {} }

extension API {
    static func callIntake(_ call: String) async throws -> CallIntake? {
        try await rpc("paragon_call_intake", ["p_call": call], as: CallIntake?.self)
    }
    static func callIntakeSet(_ call: String, status: String, result: [String: Any]? = nil) async throws {
        try await self.call("paragon_call_intake_set", ["p_call": call, "p_status": status, "p_result": result])
    }
    static func callIntakeDraft(_ call: String, draft: [String: Any]) async throws {
        try await self.call("paragon_call_intake_draft", ["p_call": call, "p_draft": draft])
    }
    struct IntakeClaim: Decodable { let ok: Bool; let status: String?; let by: String? }
    static func callIntakeClaim(_ call: String) async throws -> IntakeClaim? {
        try await rpc("paragon_call_intake_claim", ["p_call": call], as: IntakeClaim?.self)
    }
    static func callIntakeRelease(_ call: String) async throws {
        try await self.call("paragon_call_intake_release", ["p_call": call])
    }
    static func callIntakeAssignee(_ call: String, type: String, date: String?, time: String?) async throws -> IntakeAssignee? {
        try await rpc("paragon_call_intake_assignee",
                      ["p_call": call, "p_type": type, "p_date": date?.isEmpty == false ? date : nil, "p_time": time?.isEmpty == false ? time : nil],
                      as: IntakeAssignee?.self)
    }
    private struct GeoAnswer: Decodable { let geo: IntakeGeo? }
    static func callIntakeGeocode(_ call: String, address: String) async throws -> IntakeGeo? {
        try await function("paragon-intake", body: ["call_id": call, "action": "geocode", "address": address], as: GeoAnswer?.self)?.geo
    }
    private struct ReadAnswer: Decodable { let context: CallIntake? }
    static func callIntakeRead(_ call: String, again: Bool = false) async throws -> CallIntake? {
        try await function("paragon-intake", body: ["call_id": call, "again": again], as: ReadAnswer?.self)?.context
    }
}

/// A value for a JSON body, or JSON null.
func orNull(_ v: Any?) -> Any { v ?? NSNull() }

// MARK: Nexus, as the member's own login (the desktop's booking/BookAppointment.tsx)

@MainActor
enum NexusBooking {
    static let site = "https://solbuild.net"
    static let solaraOne = "8279dd23-cdeb-4d1a-b538-b6962eb4710f"

    struct Viewer: Decodable { let id: String; let fullName: String?; let adminRoleId: String?; let enterpriseAccountId: String? }
    struct Setup { let viewer: Viewer; let enterpriseAccountId: String? }
    struct Person: Decodable, Hashable, Identifiable {
        struct Ent: Decodable, Hashable { let name: String? }
        let id: String
        let fullName: String?
        let isActive: Bool?
        let isDeleted: Bool?
        let enterpriseAccount: Ent?
        var label: String { [fullName ?? "Someone", enterpriseAccount?.name].compactMap { $0 }.joined(separator: " · ") }
    }
    private struct ApptType: Decodable { let id: String; let name: String; let slug: String?; let enterpriseAccountId: String? }
    private struct EntRow: Decodable { let enterpriseAccountId: String? }
    private struct Edge: Decodable { let sourceEnterpriseId: String?; let targetEnterpriseId: String? }
    private struct Override: Decodable { let userId: String; let allowed: Bool? }
    private struct IdRow: Decodable { let id: String }

    private static var cached: Setup?

    /// Who is booking, as Nexus knows them (users by user_id, then email,
    /// then id), and the console that login opens (nil = the admin console).
    static func setup() async throws -> Setup {
        if let cached { return cached }
        let user = try await Supa.client.auth.session.user
        let uid = user.id.uuidString.lowercased()
        let fields = "id,full_name,admin_role_id,enterprise_account_id"
        var viewer = try await API.table("GET", "users", query: ["select": fields, "user_id": "eq.\(uid)", "limit": "1"], as: [Viewer].self).first
        if viewer == nil, let email = user.email, !email.isEmpty {
            viewer = try await API.table("GET", "users", query: ["select": fields, "email": "eq.\(email)", "limit": "1"], as: [Viewer].self).first
        }
        if viewer == nil {
            viewer = try await API.table("GET", "users", query: ["select": fields, "id": "eq.\(uid)", "limit": "1"], as: [Viewer].self).first
        }
        guard let viewer else { throw APIError.server("Your login has no Nexus user, so Nexus would not let you book either.") }
        var ent: String?
        if viewer.adminRoleId == nil {
            ent = try await API.table("GET", "enterprise_users",
                                      query: ["select": "enterprise_account_id", "auth_user_id": "eq.\(uid)", "is_active": "eq.true", "limit": "1"],
                                      as: [EntRow].self).first?.enterpriseAccountId
        }
        let s = Setup(viewer: viewer, enterpriseAccountId: ent)
        cached = s
        return s
    }

    /// A client's page in the console this login opens.
    static func leadURL(_ lead: String) -> URL? {
        URL(string: "\(site)\(cached?.enterpriseAccountId != nil ? "/enterprise" : "/admin")/lead/\(lead)")
    }

    private static func targets(of source: String) async -> [String] {
        let rows = (try? await API.table("GET", "enterprise_sharing_targets",
                                         query: ["select": "target_enterprise_id", "source_enterprise_id": "eq.\(source)"], as: [Edge].self)) ?? []
        return rows.compactMap(\.targetEnterpriseId)
    }

    /// Me, whoever shares into me, and everyone else they share into (Nexus getEnterpriseFamilyIds).
    private static func familyIds(_ ent: String) async -> [String] {
        let down = await targets(of: ent)
        let up = ((try? await API.table("GET", "enterprise_sharing_targets",
                                        query: ["select": "source_enterprise_id", "target_enterprise_id": "eq.\(ent)"], as: [Edge].self)) ?? [])
            .compactMap(\.sourceEnterpriseId)
        var siblings: [String] = []
        for p in up { siblings += await targets(of: p) }
        var seen = Set<String>()
        return ([ent] + down + up + siblings).filter { seen.insert($0).inserted }
    }

    private static func dedupe(_ people: [Person]) -> [Person] {
        var seen = Set<String>()
        return people.filter { p in
            guard p.isDeleted != true, p.isActive != false else { return false }
            return seen.insert(p.id).inserted
        }
    }

    /// Who can be sent: the calendar's roster (admins in the family, or
    /// Solara's console scope, plus anyone on loan in, minus Singula's blocks).
    static func roster() async -> [Person] {
        guard let s = try? await setup() else { return [] }
        let fields = "id,full_name,is_active,is_deleted,enterprise_account:enterprise_accounts!enterprise_account_id(name)"
        var q = ["select": fields, "site_role": "eq.admin", "order": "full_name"]
        if let ent = s.enterpriseAccountId {
            let family = await familyIds(ent)
            q["enterprise_account_id"] = "in.(\(family.joined(separator: ",")))"
        } else {
            let shared = await targets(of: solaraOne)
            let scope = [solaraOne] + shared
            q["or"] = "(enterprise_account_id.in.(\(scope.joined(separator: ","))),enterprise_account_id.is.null)"
        }
        var list = (try? await API.table("GET", "users", query: q, as: [Person].self)) ?? []
        if let ent = s.enterpriseAccountId {
            let loaned = (try? await API.table("GET", "users",
                                               query: ["select": fields, "site_role": "eq.admin", "shared_with_enterprise_id": "eq.\(ent)", "order": "full_name"],
                                               as: [Person].self)) ?? []
            list = dedupe(list + loaned)
            let rows = (try? await API.table("GET", "enterprise_assignment_overrides",
                                             query: ["select": "user_id,allowed", "enterprise_account_id": "eq.\(ent)"], as: [Override].self)) ?? []
            let blocked = Set(rows.filter { $0.allowed == false }.map(\.userId))
            list = list.filter { !blocked.contains($0.id) }
            let missing = rows.filter { r in r.allowed == true && !list.contains(where: { p in p.id == r.userId }) }.map(\.userId)
            if !missing.isEmpty {
                let granted = (try? await API.table("GET", "users",
                                                    query: ["select": fields, "id": "in.(\(missing.joined(separator: ",")))", "order": "full_name"],
                                                    as: [Person].self)) ?? []
                list += granted
            }
        }
        return dedupe(list)
    }

    /// The type row Nexus books with: one per name, an enterprise's own row wins.
    private static func type(_ slug: String) async throws -> ApptType {
        let rows = try await API.table("GET", "appointment_types",
                                       query: ["select": "id,name,slug,enterprise_account_id", "is_active": "eq.true", "order": "sort_order"],
                                       as: [ApptType].self)
        var byName: [String: ApptType] = [:]
        var order: [String] = []
        for r in rows {
            if let e = byName[r.name] {
                if r.enterpriseAccountId != nil && e.enterpriseAccountId == nil { byName[r.name] = r }
            } else { byName[r.name] = r; order.append(r.name) }
        }
        let types = order.compactMap { byName[$0] }
        guard let t = types.first(where: { $0.slug == slug }) ?? types.first(where: { $0.slug == "appointment" }) else {
            throw APIError.server("No such appointment type in Nexus")
        }
        return t
    }

    /// The appointment at the agreed time, in the customer's zone, with its
    /// notes and texts: the same rows the console writes (appointments,
    /// activity_main, activity_log), so Nexus's triggers do the rest.
    static func book(lead: String, person: String, thread: String, zone: String?, slug: String, date: String, time: String,
                     assignee: String, notes: String, texts: (onBooking: Bool, dayBefore: Bool, sameDay: Bool)) async throws -> String {
        let s = try await setup()
        let t = try await type(slug)
        var apptZone = zone ?? "America/Denver"
        if let z = try? await API.rpc("resolve_appointment_timezone", ["p_lead_id": lead, "p_enterprise": s.enterpriseAccountId], as: String?.self),
           !z.isEmpty { apptZone = z }
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let row: [String: Any] = [
            "appointment_date": date,
            "appointment_time": TimeText.forDB(TimeText.normalize(time)),
            "end_time": NSNull(),
            "timezone": apptZone,
            "is_event": false,
            "event_title": NSNull(),
            "appointment_type": t.slug ?? slug,
            "appointment_type_id": t.id,
            "lead_id": lead,
            "assigned_to": assignee,
            "assigned_by": s.viewer.id,
            "status": "assigned",
            "enterprise_account_id": orNull(s.enterpriseAccountId),
            "notes": orNull(n.isEmpty ? nil : n),
            "text_notification_disabled": !texts.onBooking,
            "reminder_disabled": !texts.sameDay,
            "day_before_disabled": !texts.dayBefore,
        ]
        guard let id = try await API.table("POST", "appointments", query: ["select": "id"], body: row, as: [IdRow].self).first?.id else {
            throw APIError.server("Nexus did not return the appointment")
        }
        Task { _ = try? await API.function("classify-appointment-type", body: ["appointmentId": id], as: Ignored?.self) }
        let tslug = t.slug ?? slug
        _ = try await API.table("POST", "activity_main", returning: false, body: [
            "lead_id": lead, "state": "scheduled",
            "status": tslug == "appointment" ? "appointment_set" : tslug,
            "approach": NSNull(), "phase": tslug == "follow_up" ? "call" : "appointment",
            "source": "solbuild", "source_user": s.viewer.fullName ?? "Admin",
            "data": "\(t.name) scheduled for \(date) at \(time)",
        ] as [String: Any], as: [Ignored].self)
        if tslug == "appointment" {
            _ = try await API.table("POST", "activity_log", returning: false, body: [
                "lead_id": lead, "user_id": s.viewer.id, "activity_type": "appointment_set",
                "metadata": ["appointment_date": date, "appointment_time": time],
            ] as [String: Any], as: [Ignored].self)
        }
        do { try await API.call("paragon_booking_link", ["p_person": person, "p_lead": lead, "p_appointment": id, "p_thread": thread]) }
        catch { NSLog("Paragon: booking link: \(error.localizedDescription)") }
        return id
    }
}

/// The calendar's time helpers, as they are there ("2pm" -> "2:00pm" -> "2pm").
enum TimeText {
    private static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
    static func normalize(_ time: String) -> String {
        if time.isEmpty { return "10:00am" }
        let lower = time.lowercased().replacingOccurrences(of: " ", with: "")
        guard let g = match(lower, "^(\\d{1,2})(?::(\\d{2}))?(am|pm)$") else { return time }
        return "\(g[1]):\(g[2].isEmpty ? "00" : g[2])\(g[3])"
    }
    static func forDB(_ time: String) -> String {
        let lower = time.lowercased().replacingOccurrences(of: " ", with: "")
        guard let g = match(lower, "^(\\d{1,2}):(\\d{2})(am|pm)$") else { return time }
        return g[2] == "00" ? "\(g[1])\(g[3])" : "\(g[1]):\(g[2])\(g[3])"
    }
    private static let ymd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    private static let pretty: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    static func day(_ s: String) -> Date? { ymd.date(from: s) }
    static func string(_ d: Date) -> String { ymd.string(from: d) }
    /// "Tue, Nov 18".
    static func prettyDate(_ s: String?) -> String {
        guard let s, let d = ymd.date(from: s) else { return s ?? "" }
        return pretty.string(from: d)
    }
}

// MARK: The card

private let intakeGreen = Color(hex: 0x10B981)
private let typeChips: [(String, String)] = [
    ("appointment", "Appointment"), ("measure", "Measure"), ("install", "Install"), ("service", "Service"),
    ("site_visit", "Jobsite visit"), ("sales_call", "Sales call"), ("follow_up", "Follow up"),
]
private func typeLabel(_ slug: String) -> String { typeChips.first { $0.0 == slug }?.1 ?? "Appointment" }

/// After a customer call (owner, 2026-11-13; "Popup 2", founder 2026-11-16),
/// the desktop's `screens/inbox/IntakeCard.tsx`: Atlas reads every answered
/// customer call on its own (the paragon_intake cron), and this card fills in
/// what the rep would type: the lead in the branch of the line they called,
/// its description, the appointment at the time agreed and its notes. One
/// button does it in that order, as the rep's own Nexus login.
///  - The rep who took the call has it alone for a minute (`held_until`);
///    nobody else sees it before then.
///  - One press at a time (claim): a second person reads "X is adding this to Nexus…".
///  - Done by hand in Nexus, it closes itself (the server settles it).
///  - Who goes comes from Crew (`paragon_call_intake_assignee`); someone must
///    be picked before it books.
///  - The confirmation texts are switches; a type that texts nobody says so.
///  - Edits are kept with the call (`paragon_call_intake_draft`).
struct IntakeCard: View {
    let callId: String
    let at: String

    @Environment(Session.self) private var session
    @State private var ctx: CallIntake?
    @State private var mine = false
    @State private var asked = false
    @State private var error: String?

    private var recent: Bool { (Stamp.date(at).map { Date().timeIntervalSince($0) } ?? .infinity) < 24 * 3600 }
    private var status: String? { ctx?.intake?.status }
    private var heldUntil: Date? { Stamp.date(ctx?.intake?.heldUntil) }
    private var held: Bool { (heldUntil ?? .distantPast) > Date() }
    private var settled: Bool { ["done", "dismissed", "none", "failed"].contains(status ?? "") }
    private var busy: Bool {
        status == "reading" || status == "running" || held || (status == nil && ctx?.call.ended == true && recent)
    }

    var body: some View {
        content
            .task(id: "\(callId)|\(settled)|\(mine)|\(busy)") { await poll() }
    }

    @ViewBuilder private var content: some View {
        if let c = ctx, c.space == "customer" {
            switch status {
            case nil:
                if recent && c.call.ended == true && c.call.words == true { line(busy: true) { Text("Atlas is reading the call for Nexus…") } }
            case "reading"?:
                line(busy: true) { Text("Atlas is reading the call for Nexus…") }
            case _ where held:
                // The rep who took the call has it alone for its first minute.
                EmptyView()
            case "failed"?:
                line {
                    Text("Could not read the call for Nexus.")
                    Button("Try again") {
                        Task {
                            do { if let x = try await API.callIntakeRead(callId, again: true) { ctx = x } }
                            catch { Toast.shared.show("Could not read it: \(error.localizedDescription)", error: true) }
                        }
                    }
                    .font(.metaMedium).foregroundStyle(intakeGreen).buttonStyle(.plain)
                }
            case "done"?:
                doneLine(c)
            case "none"?, "dismissed"?:
                EmptyView()
            default:
                if let p = c.intake?.proposal { live(c, p) }
            }
        }
    }

    @ViewBuilder private func live(_ c: CallIntake, _ p: IntakeProposal) -> some View {
        let claimer = c.intake?.claimedBy
        if status == "running" && !mine {
            line(busy: true) {
                Text(claimer?.id != nil && claimer?.id == session.me?.id
                     ? "You started adding this to Nexus. Checking it finished…"
                     : "\(claimer?.name?.isEmpty == false ? claimer!.name! : "A teammate") is adding this to Nexus…")
            }
        } else if let bid = p.alreadyBookedId, !bid.isEmpty, let booked = c.appointments?.first(where: { $0.id == bid }) {
            line(done: true, dismiss: { Task { try? await API.callIntakeSet(callId, status: "dismissed"); await load() } }) {
                Text("Already booked: \(booked.typeName ?? "Appointment") \(TimeText.prettyDate(booked.date))\(booked.time.map { " at \($0)" } ?? "")")
                if let l = c.lead { openLead(l.id) }
            }
        } else {
            IntakeForm(ctx: c, p: p, onDone: { Task { await load() } }, onRunning: { mine = $0 })
        }
    }

    private func doneLine(_ c: CallIntake) -> some View {
        let r = c.intake?.resultValue
        let head = r?.by == "nexus" ? "Done in Nexus" : r?.created == true ? "Added to Nexus" : "In Nexus"
        var tail = ""
        if r?.appointmentId != nil, let d = r?.date {
            tail = " · \(r?.type ?? "Appointment") booked \(TimeText.prettyDate(d))\(r?.time.map { " at \($0)" } ?? "")"
        }
        return line(done: true) {
            Text(head + tail)
            if let l = r?.leadId { openLead(l) }
        }
    }

    private func openLead(_ id: String) -> some View {
        Button {
            Task {
                _ = try? await NexusBooking.setup()
                if let u = NexusBooking.leadURL(id) { _ = await UIApplication.shared.open(u) }
            }
        } label: {
            HStack(spacing: 2) {
                Text("Open in Nexus")
                Image(systemName: "arrow.up.right.square").font(.system(size: 10))
            }
            .font(.meta).foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private func line<C: View>(busy: Bool = false, done: Bool = false, dismiss: (() -> Void)? = nil, @ViewBuilder _ body: () -> C) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.mini).tint(intakeGreen) }
            else if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(intakeGreen) }
            else { AtlasFace(size: 13) }
            FlowRow(spacing: 5) { body() }
                .font(.meta)
                .foregroundStyle(done ? intakeGreen : Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Hide")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(intakeGreen.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(intakeGreen.opacity(0.25)))
        .padding(.horizontal, 4).padding(.top, 2)
    }

    private func load() async {
        do {
            let c = try await API.callIntake(callId)
            ctx = c
            // Nobody has asked yet (the cron asks within a minute anyway): ask now.
            if let c, c.call.ended == true, c.call.words == true, c.intake == nil, recent, !asked {
                asked = true
                do { if let x = try await API.callIntakeRead(callId) { ctx = x } } catch { asked = false }
            }
        } catch { /* the next look */ }
    }

    /// Busy (reading, someone pressing, held for the rep who took it): every
    /// 4 s. Ready: every 15 s, so a card done in Nexus or by a teammate closes
    /// here too. Done, or this screen pressing: no more polling.
    private func poll() async {
        await load()
        while !Task.isCancelled && !settled && !mine {
            try? await Task.sleep(for: .seconds(busy ? 4 : 15))
            if Task.isCancelled { return }
            await load()
        }
    }
}

private struct DraftState: Equatable {
    var name, address, email, description, company: String
    var book: Bool
    var type, date, time, notes, assignee: String
    var picked: Bool
    var onBooking, dayBefore, sameDay: Bool

    var json: [String: Any] {
        ["name": name, "address": address, "email": email, "description": description, "company": company,
         "book": book, "type": type, "date": date, "time": time, "notes": notes, "assignee": assignee,
         "assignee_picked": picked,
         "texts": ["on_booking": onBooking, "day_before": dayBefore, "same_day": sameDay]]
    }
}

private struct AssigneeAsk: Equatable { let book: Bool; let type: String; let date: String; let time: String; let geo: IntakeGeo?; let picked: Bool }

private enum StepState { case todo, doing, done, skip, error }
private struct Step: Identifiable { let key: String; var label: String; var state: StepState; var id: String { key } }

private struct IntakeForm: View {
    let ctx: CallIntake
    let p: IntakeProposal
    let onDone: () -> Void
    let onRunning: (Bool) -> Void

    @State private var s: DraftState
    private let first: DraftState
    @State private var suggest: IntakeAssignee?
    @State private var roster: [NexusBooking.Person] = []
    @State private var steps: [Step]?
    @State private var geo: IntakeGeo?
    @State private var geoArmed = false

    init(ctx: CallIntake, p: IntakeProposal, onDone: @escaping () -> Void, onRunning: @escaping (Bool) -> Void) {
        self.ctx = ctx; self.p = p; self.onDone = onDone; self.onRunning = onRunning
        let d = ctx.intake?.draftValue
        let a = p.appointment
        let start = DraftState(
            name: d?.name ?? (p.name?.isEmpty == false ? p.name! : ctx.name ?? ""),
            address: d?.address ?? (p.address?.isEmpty == false ? p.address! : ctx.address ?? ""),
            email: d?.email ?? (p.email?.isEmpty == false ? p.email! : ctx.email ?? ""),
            description: d?.description ?? (p.description ?? ""),
            company: d?.company ?? (ctx.company?.key ?? "solara"),
            book: d?.book ?? (a?.agreed == true && a?.date?.isEmpty == false),
            type: d?.type ?? (a?.type?.isEmpty == false ? a!.type! : "appointment"),
            date: d?.date ?? (a?.date ?? ""),
            time: d?.time ?? (a?.time ?? ""),
            notes: d?.notes ?? (a?.notes ?? ""),
            assignee: d?.assignee ?? "",
            picked: d?.assigneePicked ?? false,
            onBooking: d?.texts?.onBooking ?? true,
            dayBefore: d?.texts?.dayBefore ?? true,
            sameDay: d?.texts?.sameDay ?? true)
        _s = State(initialValue: start)
        first = start
        _geo = State(initialValue: ctx.intake?.geoValue)
    }

    private var lead: CallIntake.Lead? { ctx.lead }
    private var callId: String { ctx.call.id }
    private var canBook: Bool { s.book && !s.date.isEmpty && !s.time.trimmingCharacters(in: .whitespaces).isEmpty && !s.assignee.isEmpty }
    private var ready: Bool {
        (lead != nil || (s.name.trimmingCharacters(in: .whitespaces).count > 1 && ctx.phone?.isEmpty == false)) && (!s.book || canBook)
    }
    private var changedType: Bool { s.type != (p.appointment?.type?.isEmpty == false ? p.appointment!.type! : "appointment") }
    private var role: String {
        suggest?.role ?? (s.type == "measure" ? "measure" : s.type == "install" || s.type == "service" ? "install" : "sales")
    }
    private var companyName: String { ctx.company?.name ?? (s.company == "just_glass" ? "Just Glass" : "Solara One") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let steps { stepList(steps) } else { form; footer }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(intakeGreen.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(intakeGreen, lineWidth: 1.5))
        .padding(.horizontal, 4).padding(.top, 2)
        .task { roster = await NexusBooking.roster() }
        // Keep the edits with the call (a teammate who opens it, or the rep coming back, sees them).
        .task(id: s) {
            guard s != first, steps == nil else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            try? await API.callIntakeDraft(callId, draft: s.json)
        }
        // A changed address is placed again, so Crew can pick who goes (not when the client is on the map).
        .task(id: s.address) {
            guard s.address != first.address || geoArmed, lead?.mapped != true else { return }
            geoArmed = true
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            if let g = try? await API.callIntakeGeocode(callId, address: s.address.trimmingCharacters(in: .whitespaces)) { geo = g }
        }
        // Who goes, from Crew, whenever the type, the time or the place changes.
        .task(id: AssigneeAsk(book: s.book, type: s.type, date: s.date, time: s.time, geo: geo, picked: s.picked)) {
            guard s.book else { return }
            guard let a = try? await API.callIntakeAssignee(callId, type: s.type, date: s.date, time: s.time), !Task.isCancelled else { return }
            suggest = a
            if !s.picked { s.assignee = a.userId ?? "" }
        }
    }

    private var title: String {
        let t = typeLabel(s.type).lowercased()
        if lead != nil { return s.book ? "Book the \(t) they agreed to" : "In Nexus" }
        return s.book ? "Add to Nexus and book the \(t)" : "Add them to Nexus"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            AtlasFace(size: 14).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Ready").font(.meta).foregroundStyle(intakeGreen)
                }
                if let sum = p.summary, !sum.isEmpty { Text(sum).font(.meta).foregroundStyle(Theme.secondary) }
            }
            Spacer(minLength: 4)
            if steps == nil {
                Button {
                    Task {
                        do { try await API.callIntakeSet(callId, status: "dismissed"); onDone() }
                        catch { Toast.shared.show("Could not hide it: \(error.localizedDescription)", error: true) }
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
            }
        }
    }

    // MARK: Client, then the appointment (one column on a phone)

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnTitle("Client")
            if let l = lead {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("In Nexus as ") + Text(l.name ?? "a client").foregroundStyle(Theme.text) + Text(l.how == "phone" ? " (same phone)" : ""))
                    if let a = l.address, !a.isEmpty { Text(a) }
                    openLead(l.id)
                }
                .font(.meta).foregroundStyle(Theme.secondary)
            } else {
                field("Name", $s.name)
                field("Address", $s.address)
                field("Email", $s.email, keyboard: .emailAddress)
                area("What they want", "What they want done", $s.description)
                if let c = ctx.company {
                    (Text("Branch: ") + Text(c.name).foregroundStyle(Theme.text) + Text(" · they called \(ctx.line?.label ?? "our line")"))
                        .font(.meta).foregroundStyle(Theme.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text("Branch").font(.meta).foregroundStyle(Theme.muted)
                        chip("Solara One", on: s.company == "solara") { s.company = "solara" }
                        chip("Just Glass", on: s.company == "just_glass") { s.company = "just_glass" }
                    }
                }
                if ctx.phone?.isEmpty != false {
                    Text("No phone number on this conversation").font(.meta).foregroundStyle(Theme.rose)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            columnTitle("Appointment")
            Toggle(isOn: $s.book) {
                Text(p.appointment?.agreed == true ? "Book the appointment" : "No time was agreed. Book one anyway")
                    .font(.meta).foregroundStyle(Theme.secondary)
            }
            .tint(intakeGreen)
            if s.book { appointment }
        }
    }

    @ViewBuilder private var appointment: some View {
        FlowRow(spacing: 5) {
            ForEach(typeChips, id: \.0) { c in chip(c.1, on: s.type == c.0) { s.type = c.0 } }
        }
        if let why = p.appointment?.typeWhy, !why.isEmpty, !changedType {
            Text(why).font(.meta).foregroundStyle(Theme.muted)
        }
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Day").font(.meta).foregroundStyle(Theme.muted)
                if let d = TimeText.day(s.date) {
                    DatePicker("Day", selection: Binding(get: { d }, set: { s.date = TimeText.string($0) }), displayedComponents: .date)
                        .labelsHidden().tint(intakeGreen)
                } else {
                    Button("Add the day") { s.date = TimeText.string(Date()) }
                        .font(.metaMedium).foregroundStyle(intakeGreen).buttonStyle(.plain)
                        .frame(height: 34)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Time\(zoneShort.map { " (\($0))" } ?? "")").font(.meta).foregroundStyle(Theme.muted)
                TextField("2:00pm", text: $s.time)
                    .font(.ui).foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 8).frame(width: 100, height: 34)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.inputBorder))
            }
            Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text("Who goes").font(.meta).foregroundStyle(Theme.muted)
            Menu {
                Picker("Who goes", selection: Binding(get: { s.assignee }, set: { s.assignee = $0; s.picked = true })) {
                    Text("Pick who goes").tag("")
                    ForEach(options, id: \.id) { o in Text(o.label).tag(o.id) }
                }
            } label: {
                HStack {
                    Text(options.first { $0.id == s.assignee }?.label ?? "Pick who goes")
                        .font(.ui).foregroundStyle(s.assignee.isEmpty ? Theme.muted : Theme.text).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(s.assignee.isEmpty ? Theme.amber : Theme.inputBorder))
            }
            HStack(spacing: 4) {
                let note = assigneeNote
                if !note.isEmpty { Text(note) }
                if s.picked, let u = suggest?.userId, u != s.assignee {
                    Text("·")
                    Button("Use \(suggest?.name ?? "Crew's pick")") { s.picked = false; s.assignee = u }
                        .foregroundStyle(intakeGreen).buttonStyle(.plain)
                }
            }
            .font(.meta).foregroundStyle(Theme.muted)
        }
        area("Notes for whoever goes", "Gate code, who will be home", $s.notes)
        VStack(alignment: .leading, spacing: 4) {
            Text("Texts to the client").font(.meta).foregroundStyle(Theme.muted)
            let rows = textRows
            if rows.isEmpty {
                Text(noTextsNote).font(.meta).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
            } else {
                ForEach(rows, id: \.key) { r in
                    Toggle(isOn: textBinding(r.key)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.label).font(.meta).foregroundStyle(Theme.text)
                            Text("Sends \(r.when)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(intakeGreen)
                }
            }
        }
    }

    private var zoneShort: String? {
        guard let z = ctx.zone, let tz = TimeZone(identifier: z) else { return nil }
        return tz.abbreviation(for: TimeText.day(s.date) ?? Date())
    }

    private struct Option { let id: String; let label: String }
    private var options: [Option] {
        var list = roster.map { Option(id: $0.id, label: $0.label) }
        if let u = suggest?.userId, !list.contains(where: { $0.id == u }) { list.insert(Option(id: u, label: suggest?.name ?? "From Crew"), at: 0) }
        if !s.assignee.isEmpty, !list.contains(where: { $0.id == s.assignee }) { list.insert(Option(id: s.assignee, label: "Picked earlier"), at: 0) }
        return list
    }

    /// What the "who goes" pick says under it.
    private var assigneeNote: String {
        if s.picked { return "Picked by hand" }
        guard let a = suggest else { return "" }
        let area = a.area ?? "the area"
        switch a.why {
        case "primary": return "Primary \(role) for \(area)"
        case "backup": return "\(a.primary ?? "The primary") has a \(a.busyAt ?? "booking") then, so the backup for \(area)"
        case "primary_busy_no_backup": return "Primary \(role) for \(area). Has a \(a.busyAt ?? "booking") then, and there is no backup"
        case "primary_both_busy": return "Primary \(role) for \(area). The backup is busy then too"
        case "nearest": return "Nearest \(role) to \(area) (nobody picked for that zone in Crew)"
        case "nobody": return "Nobody in Crew covers \(role) in \(area). Pick who goes"
        case "outside": return "The address is outside every Crew zone. Pick who goes"
        default: return "No address yet. Pick who goes"
        }
    }

    private struct TextRow { let key: String; let label: String; let when: String }
    /// The confirmation texts this company sends, for this type.
    private var textRows: [TextRow] {
        guard let cfg = ctx.texts, typeTexts else { return [] }
        var out: [TextRow] = []
        if cfg.onBooking == true { out.append(TextRow(key: "on_booking", label: "On booking", when: "as soon as it is booked")) }
        if cfg.dayBefore == true { out.append(TextRow(key: "day_before", label: "Day before", when: "the evening before")) }
        if cfg.sameDay == true {
            let h = cfg.hours?.value ?? 1
            let n = h == h.rounded() ? String(Int(h)) : String(h)
            out.append(TextRow(key: "same_day", label: "\(n) hour\(h == 1 ? "" : "s") before", when: "on the day"))
        }
        return out
    }
    private var typeTexts: Bool { ctx.texts?.types.map { $0.contains(s.type) } ?? true }
    private var noTextsNote: String {
        ctx.texts != nil && !typeTexts
            ? "No confirmation texts go out for a \(typeLabel(s.type).lowercased()). Nothing is sent to the client."
            : "Nothing is texted to the client for this appointment."
    }
    private func textBinding(_ key: String) -> Binding<Bool> {
        switch key {
        case "on_booking": return $s.onBooking
        case "day_before": return $s.dayBefore
        default: return $s.sameDay
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(intakeGreen.opacity(0.25)).frame(height: 1)
            HStack(spacing: 10) {
                Button { Task { await run() } } label: {
                    Text(lead != nil ? (s.book ? "Book it" : "Done") : s.book ? "Add to Nexus & book" : "Add to Nexus")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(intakeGreen))
                }
                .buttonStyle(.plain)
                .disabled(!ready).opacity(ready ? 1 : 0.4)
                Text(s.book && s.assignee.isEmpty ? "Pick who goes to book it"
                     : s.book && (s.date.isEmpty || s.time.isEmpty) ? "Add the day and time to book it"
                     : "Your edits are kept if you leave this conversation")
                    .font(.meta).foregroundStyle(Theme.muted)
            }
        }
    }

    private func stepList(_ list: [Step]) -> some View {
        let busy = list.contains { $0.state == .doing }
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(list.filter { $0.state != .skip || $0.key == "lead" }) { st in
                HStack(spacing: 8) {
                    switch st.state {
                    case .doing: ProgressView().controlSize(.mini).tint(intakeGreen)
                    case .done, .skip: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(intakeGreen)
                    case .error: Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.rose)
                    case .todo: Circle().strokeBorder(Theme.border).frame(width: 12, height: 12)
                    }
                    Text(st.label)
                        .foregroundStyle(st.state == .error ? Theme.rose : st.state == .todo ? Theme.muted : Theme.text)
                }
                .font(.meta)
            }
            if !busy && list.contains(where: { $0.state == .error }) {
                Button("Back") { steps = nil; onDone() }
                    .font(.metaMedium).foregroundStyle(intakeGreen).buttonStyle(.plain)
            }
        }
    }

    // MARK: Pieces

    private func columnTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.meta)
                .foregroundStyle(on ? .white : Theme.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(on ? intakeGreen : Color.clear))
                .overlay(Capsule().strokeBorder(on ? intakeGreen : Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.meta).foregroundStyle(Theme.muted)
            TextField("", text: text)
                .font(.ui).foregroundStyle(Theme.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.inputBorder))
        }
    }

    private func area(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.meta).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...6)
                .font(.ui).foregroundStyle(Theme.text)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.inputBorder))
        }
    }

    private func openLead(_ id: String) -> some View {
        Button {
            Task {
                _ = try? await NexusBooking.setup()
                if let u = NexusBooking.leadURL(id) { _ = await UIApplication.shared.open(u) }
            }
        } label: {
            HStack(spacing: 2) {
                Text("Open in Nexus")
                Image(systemName: "arrow.up.right.square").font(.system(size: 10))
            }
            .font(.meta).foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }

    // MARK: The one button, in order

    private func mark(_ key: String, _ state: StepState) {
        guard var list = steps, let i = list.firstIndex(where: { $0.key == key }) else { return }
        list[i].state = state
        steps = list
    }

    private func run() async {
        // One press at a time, across everyone.
        onRunning(true)
        let claim: API.IntakeClaim?
        do { claim = try await API.callIntakeClaim(callId) } catch {
            Toast.shared.show("Could not start: \(error.localizedDescription)", error: true)
            onRunning(false); onDone(); return
        }
        guard let claim, claim.ok else {
            onRunning(false)
            if let claim { Toast.shared.show(claim.status == "done" ? "Already done" : "\(claim.by ?? "A teammate") is already doing this", error: true) }
            onDone()
            return
        }
        let book = canBook
        let name = s.name.trimmingCharacters(in: .whitespaces)
        let description = s.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = s.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        steps = [
            Step(key: "lead", label: lead != nil ? "In Nexus as \(lead?.name ?? "a client")" : "Add \(name) to \(companyName)", state: lead != nil ? .skip : .todo),
            Step(key: "desc", label: "Description", state: lead != nil || description.isEmpty ? .skip : .todo),
            Step(key: "appt", label: book ? "Book \(typeLabel(s.type)) \(TimeText.prettyDate(s.date)) at \(s.time)" : "No appointment", state: book ? .todo : .skip),
            Step(key: "notes", label: "Appointment notes", state: book && !notes.isEmpty ? .todo : .skip),
        ]
        var leadId = lead?.id
        var created = false
        var apptId: String?
        do {
            // 1 + 2: the lead, with its description, in the branch of the line they called.
            if leadId == nil {
                mark("lead", .doing); if !description.isEmpty { mark("desc", .doing) }
                let email = s.email.trimmingCharacters(in: .whitespaces)
                let address = s.address.trimmingCharacters(in: .whitespaces)
                var args: [String: Any?] = [
                    "p_person": ctx.personId, "p_thread": ctx.threadId, "p_name": name, "p_phone": ctx.phone,
                    "p_email": email.isEmpty ? nil : email, "p_address": address.isEmpty ? nil : address,
                    "p_description": description.isEmpty ? nil : description, "p_company": s.company,
                ]
                let r = try await API.rpc("paragon_nexus_lead_create", args, as: LeadCreated?.self)
                if let dup = r?.duplicate {
                    args["p_link_existing"] = dup.id
                    let l = try await API.rpc("paragon_nexus_lead_create", args, as: LeadCreated?.self)
                    leadId = l?.leadId
                    if var list = steps {
                        for i in list.indices {
                            if list[i].key == "lead" { list[i].label = "Already in Nexus as \(dup.name ?? "a client")"; list[i].state = .done }
                            if list[i].key == "desc" { list[i].state = .skip }
                        }
                        steps = list
                    }
                } else {
                    leadId = r?.leadId
                    created = true
                    mark("lead", .done); if !description.isEmpty { mark("desc", .done) }
                }
            }
            guard let leadId else { throw APIError.server("Nexus did not return the client") }

            // 3 + 4: the appointment at the agreed time, in the customer's zone, with its notes and texts.
            if book {
                mark("appt", .doing)
                apptId = try await NexusBooking.book(lead: leadId, person: ctx.personId, thread: ctx.threadId, zone: ctx.zone,
                                                     slug: s.type, date: s.date, time: s.time, assignee: s.assignee, notes: notes,
                                                     texts: (s.onBooking, s.dayBefore, s.sameDay))
                mark("appt", .done)
                if !notes.isEmpty { mark("notes", .done) }
            }

            let typeChange: [String: Any]? = changedType ? ["from": orNull(p.appointment?.type), "to": s.type] : nil
            let fromCrew: String? = book && !s.picked && s.assignee == suggest?.userId ? suggest?.why : nil
            let result: [String: Any] = [
                "lead_id": leadId, "created": created, "appointment_id": orNull(apptId),
                "type": orNull(book ? typeLabel(s.type) : nil), "date": orNull(book ? s.date : nil), "time": orNull(book ? s.time : nil),
                "assignee": orNull(book ? s.assignee : nil),
                "type_changed": orNull(typeChange),
                "assignee_from_crew": orNull(fromCrew),
            ]
            try await API.callIntakeSet(callId, status: "done", result: result)
            Toast.shared.show(created ? "Added to Nexus" + (book ? " · \(typeLabel(s.type)) \(TimeText.prettyDate(s.date)) at \(s.time)" : "")
                              : "Done" + (book ? " · \(typeLabel(s.type)) \(TimeText.prettyDate(s.date)) at \(s.time)" : ""))
            onRunning(false)
            onDone()
        } catch {
            if var list = steps {
                for i in list.indices where list[i].state == .doing { list[i].state = .error }
                steps = list
            }
            Toast.shared.show("Stopped part way: \(error.localizedDescription)", error: true)
            // Give the card back; whatever was already made in Nexus is found, so it is never made twice.
            try? await API.callIntakeRelease(callId)
            onRunning(false)
        }
    }
}

private struct LeadCreated: Decodable {
    struct Dup: Decodable { let id: String; let name: String? }
    let leadId: String?
    let created: Bool?
    let duplicate: Dup?
}
