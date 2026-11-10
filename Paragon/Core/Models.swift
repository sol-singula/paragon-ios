import Foundation
import CoreGraphics

// The shapes the `public.paragon_*` functions return (the desktop app's
// web/src/lib/api.ts is the reference). Keys arrive snake_case and are
// decoded camelCase. Everything that can be null is optional, and timestamps
// stay strings until shown (`Stamp`), so a new field or a null never stops a
// screen from loading.

struct Me: Decodable, Equatable {
    let id: String
    let name: String
    let email: String?
    let role: String

    var isOwner: Bool { role == "owner" }
    var isFounder: Bool { isOwner }
    var first: String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// The owner role is called Founder everywhere a person reads it (founder,
/// 2026-11-09); the value in the database stays 'owner'.
enum Role {
    static func label(_ role: String?) -> String {
        switch role {
        case "owner": return "Founder"
        case "manager": return "Manager"
        case "rep": return "Rep"
        default: return role ?? ""
        }
    }
}

/// A picture or file on a text (`media`: `[{url, type, name?}]`). Anything
/// else in that column reads as no media rather than stopping the screen.
struct MediaItem: Decodable, Hashable {
    let url: String?
    let type: String?
    let name: String?

    var isImage: Bool { (type ?? "").hasPrefix("image") }
}

struct MediaList: Decodable, Hashable {
    let items: [MediaItem]
    init(from decoder: Decoder) throws {
        items = (try? [MediaItem](from: decoder)) ?? []
    }
}

struct QueueThread: Decodable, Hashable, Identifiable {
    let id: String
    let brand: String?
    let state: String?
    let space: String?
    let status: String?
    let dueAt: String?
    let clockStartedAt: String?
    let locked: Bool?
}

struct QueueItem: Decodable, Hashable, Identifiable {
    let personId: String
    let name: String
    let city: String?
    let contactType: String?
    let status: String
    let waitingSince: String?
    let pct: Double?
    let lastActivityAt: String?
    let threads: [QueueThread]?
    let preview: String?

    // The one inbox (promises and Atlas's cards on the person's row). All
    // optional: an older server sends none of them, a newer one may send
    // more, and a malformed item never stops the inbox.
    let dueAt: String?
    /// clock | promise | card, or nil.
    let dueSource: String?
    let overdue: Bool?
    /// Ascending code-unit order is the server's urgency order.
    let sortKey: String?
    /// The conversation to open from this row.
    let threadId: String?
    /// A card or promise is merged into this row: a slight violet tint.
    let atlas: Bool?
    let card: Lenient<RowItem>?
    let cardId: String?
    let title: String?
    let why: String?
    let items: LossyList<RowItem>?
    /// A promise by hand on this row is mine.
    let assignedToMe: Bool?
    /// …and not yet a team promise: nobody else sees this conversation.
    let `private`: Bool?

    var id: String { personId }
    var firstThread: QueueThread? { threads?.first }
    var tone: ClockTone { status == "waiting" ? ClockTone(pct: pct) : .calm }

    var isAtlas: Bool { allItems.isEmpty ? atlas == true : !rowItems.isEmpty }
    var isPrivate: Bool { self.`private` == true }
    private var allItems: [RowItem] { items?.items ?? (card?.value.map { [$0] } ?? []) }
    /// Every card and promise on the row, soonest first, less what was just
    /// done here (`GoneIDs`, instant).
    var rowItems: [RowItem] { allItems.filter { !GoneIDs.shared.contains($0.id) } }
    /// The leading item (soonest due).
    var leadItem: RowItem? { card?.value.flatMap { GoneIDs.shared.contains($0.id) ? nil : $0 } ?? rowItems.first }
    var isOverdue: Bool {
        if let o = overdue { return o && dueAt != nil }
        return (Stamp.date(dueAt) ?? .distantFuture) <= Date()
    }
    /// The conversation a tap opens: the server's choice, else the waiting
    /// thread, else the first.
    var openThread: String? {
        threadId ?? threads?.first(where: { $0.status == "waiting" })?.id ?? firstThread?.id
    }
    /// Overdue promises on this row that are mine (the tab's badge).
    var overdueMine: Int {
        rowItems.filter { $0.kind == "promise" && $0.mine == true && $0.isOverdue }.count
    }
}

/// A card or promise on an inbox row (`paragon_queue` items[] and card).
struct RowItem: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String?
    /// hand | atlas
    let by: String?
    let title: String?
    let why: String?
    let short: String?
    let dueAt: String?
    let openToAllAt: String?
    let team: Bool?
    let escalation: Flex?
    let actionType: String?
    let body: String?
    let threadId: String?
    let ownerId: String?
    let mine: Bool?
    let createdBy: String?
    let createdByName: String?
    let createdAt: String?

    var isPromise: Bool { kind == "promise" }
    var byHand: Bool { by == "hand" }
    var isOverdue: Bool { (Stamp.date(dueAt) ?? .distantFuture) <= Date() }
    var what: String { (title?.isEmpty == false ? title : short) ?? (isPromise ? "Promise" : "Atlas card") }
}

/// A promise on a conversation (`paragon_thread_promises`, the card's own
/// shape). The owner's name is never read (no owner's name anywhere);
/// `memberId` names whose it is (their first name, from the team).
struct ThreadPromise: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String?
    let title: String?
    let why: String?
    let dueAt: String?
    let openToAllAt: String?
    let status: String?
    let memberId: String?
    let threadId: String?
    let short: String?

    var isOpen: Bool { status == nil || status == "open" }
    var isOverdue: Bool { (Stamp.date(dueAt) ?? .distantFuture) <= Date() }
    var what: String { (title?.isEmpty == false ? title : short) ?? "Promise" }
}

/// One person in the WHO picker (`paragon_promise_people`): me first, then
/// who can take it; `whyNot` says why someone can't.
/// paragon_ui_prefs: the inbox's tab, branch and homeowners-only, kept on the member.
struct UiPrefs: Codable, Hashable {
    struct Inbox: Codable, Hashable {
        var homeownersOnly: Bool?
        var brand: String?
        var tab: String?
    }
    var inbox: Inbox?
}

/// Where Atlas puts a vague WHEN: "Tue 1:00 pm" and why. Also what
/// `paragon_promise_add_vague` answers (its id, due_at and why).
struct PromiseSlot: Decodable, Hashable {
    let id: String?
    let dueAt: String?
    let label: String?
    let why: String?
    let hint: String?
}

struct PromisePerson: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String?
    let photoUrl: String?
    let isMe: Bool?
    let canTake: Bool?
    let whyNot: String?

    var first: String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// A list where an element this version can't read is skipped.
struct LossyList<T: Decodable & Hashable>: Decodable, Hashable {
    let items: [T]
    init(from decoder: Decoder) throws {
        var out: [T] = []
        if var c = try? decoder.unkeyedContainer() {
            while !c.isAtEnd {
                if let v = try? c.decode(T.self) { out.append(v) }
                else { _ = try? c.decode(Skip.self) }
            }
        }
        items = out
    }
    /// Reads anything, so a bad element is stepped over, never looped on.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}

/// A value that reads as nil when this version can't read it.
struct Lenient<T: Decodable & Hashable>: Decodable, Hashable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum ClockTone { case calm, soon, late
    init(pct: Double?) {
        guard let p = pct else { self = .calm; return }
        self = p >= 1 ? .late : p >= 0.5 ? .soon : .calm
    }
    static func of(started: String?, due: String?) -> ClockTone {
        guard let a = Stamp.date(started), let b = Stamp.date(due), b > a else { return .calm }
        return ClockTone(pct: Date().timeIntervalSince(a) / b.timeIntervalSince(a))
    }
}

struct PersonThread: Decodable, Hashable, Identifiable {
    let id: String
    let brand: String?
    let state: String?
    let space: String?
    let status: String?
    let dueAt: String?
    let clockStartedAt: String?
    let locked: Bool?
    // No owner's name on a conversation (founder, 2026-11-09): the server
    // sends threads[].owner as null and nothing here reads it.
    let label: String?
    let lastActivityAt: String?
}

struct TimelineEvent: Decodable, Hashable, Identifiable {
    let kind: String          // "text" | "call"
    let id: String
    let at: String
    let direction: String     // "in" | "out"
    let body: String?
    let media: MediaList?
    let status: String?
    let automated: Bool?
    let by: String?
    let atlas: Bool?
    let duration: Double?
    let answered: Bool?
    let voicemailUrl: String?
    let transcript: String?
    let summary: String?

    var isCall: Bool { kind == "call" }
    var mediaItems: [MediaItem] { media?.items ?? [] }
    var isIn: Bool { direction == "in" }
}

struct PersonView: Decodable {
    struct Person: Decodable {
        let id: String
        let name: String
        let hasName: Bool?
        let city: String?
        let contactType: String?
        let isStopped: Bool?
        let source: String?
        let nexusLeadId: String?
        /** Someone picked their type, or they are a Nexus client. */
        let typeKnown: Bool?
        /** A first contact nobody has classified: ask "Who is this?". */
        let askType: Bool?
    }
    struct Lead: Decodable { let id: String; let address: String?; let email: String?; let description: String? }
    /// Where else they have talked to us. Never who holds them.
    struct History: Decodable { let brand: String? }
    struct Appointment: Decodable { let date: String; let time: String?; let type: String?; let confirmed: Bool? }

    let person: Person
    let threads: [PersonThread]
    let threadId: String?
    let sendLabel: String?
    let canSend: Bool?
    let lockedReason: String?
    let timeline: [TimelineEvent]?
    let lead: Lead?
    let appointment: Appointment?
    let history: [History]?
}

struct PersonalItem: Decodable, Hashable, Identifiable {
    let threadId: String
    let personId: String
    let line: String
    let name: String
    let phone: String?
    let status: String
    let lastActivityAt: String?
    let preview: String?
    let previewKind: String?
    let contactType: String?
    let askType: Bool?
    /** Released with nothing since (a release sticks). */
    let released: Bool?

    var id: String { threadId }
    var isSpam: Bool { contactType == "spam" }
}

struct PersonalThread: Decodable {
    struct LineOwner: Decodable, Hashable { let id: String; let name: String }
    struct Person: Decodable, Hashable {
        let id: String
        let name: String
        let hasName: Bool?
        let contactType: String?
        let typeKnown: Bool?
        let askType: Bool?
        let isStopped: Bool?
        let nexusLeadId: String?
    }
    let threadId: String
    let sendLabel: String?
    let timeline: [TimelineEvent]?
    /** Whose personal line this is, and whether it is mine. */
    let lineOwner: LineOwner?
    let mine: Bool?
    let person: Person?
    let released: Bool?
}

/// A person's contact info (paragon_person_details), the inbox's panel.
struct PersonDetails: Decodable {
    struct Suggestion: Decodable, Hashable { let name: String; let source: String? }
    let email: String?
    let address: String?
    let notes: String?
    let foundAddress: String?
    let foundAt: String?
    let nameSuggestions: [Suggestion]?
    /// Every number they have, the first one first, `label` already
    /// formatted ("(801) 566-1177"). Optional: an older server sends none.
    let phones: [Phone]?
    struct Phone: Decodable, Hashable { let phone: String; let label: String? }
}

/// What a person is (paragon_set_contact_type). Spam releases every
/// conversation with them and keeps them out of Waiting.
enum ContactType {
    static let all: [(value: String, label: String)] = [("homeowner", "Homeowner"), ("contractor", "Contractor"), ("vendor", "Vendor"), ("spam", "Spam")]
    static func label(_ v: String?) -> String { all.first { $0.value == v }?.label ?? "Automated" }
}

struct Notice: Decodable, Hashable, Identifiable {
    let id: Int64
    let kind: String
    let title: String
    let body: String?
    let personId: String?
    let threadId: String?
    let createdAt: String
    let read: Bool?
}

struct CallCard: Decodable {
    let threadId: String
    let personId: String
    let brand: String?
    let state: String?
    let line: String?
    let name: String
    let hasName: Bool?
    let city: String?
    let greeting: String?
}

/// Someone added to a call (a conference, paragon-voice op=control).
struct CallPerson: Decodable, Hashable, Identifiable {
    let key: String
    let kind: String      // member | number
    let id: String
    let name: String
    let status: String    // joining | talking | left | no answer
    let by: String?
    var on: Bool { status != "left" && status != "no answer" }
}
struct CallPeople: Decodable { let conference: Bool?; let people: [CallPerson]? }
/// Who a call may go to (paragon_call_targets): the transfer and Add lists.
struct CallTarget: Decodable, Hashable, Identifiable { let id: String; let name: String; let role: String?; let busy: Bool? }

struct VoiceToken: Decodable {
    let token: String
    let identity: String
    /// False while no iPhone Push Credential is saved on the server: calls
    /// can be placed, but nothing rings this phone.
    let pushReady: Bool?
}

/// Where a notification or a tap wants to go.
enum Route: Hashable {
    case person(personId: String, threadId: String?)
    case personal(threadId: String, name: String)
}

/// A number the server may send as a JSON number or as a numeric string
/// (Postgres numerics). Anything unreadable is 0.
struct Flex: Decodable, Hashable {
    let value: Double
    init(_ v: Double) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) ?? 0 }
        else { value = 0 }
    }
}

// MARK: Team (paragon_team): everyone, their photo, whether they're on a call

struct TeamMember: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String?
    let photoUrl: String?
    let isMe: Bool?
    let onCall: Bool?
    let callWith: String?
    let callPersonId: String?
    let callStartedAt: String?
}

// MARK: Team chat (paragon_team_*)

struct TeamQuiet: Codable, Hashable {
    var start: String
    var end: String
    var days: [Int]?

    var json: [String: Any] { ["start": start, "end": end, "days": days ?? []] }
}

struct TeamPrefs: Decodable, Hashable {
    let notify: String?          // all | mentions | none
    let mutedUntil: String?      // a time, or "infinity"
    let always: Bool?
    let quiet: TeamQuiet?
}

struct TeamChannel: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let about: String?
    let atlasIn: Bool?
    let members: [String]?
    let unread: Int?
    let mentions: Int?
    let lastAt: String?
    let lastReadAt: String?
    let prefs: TeamPrefs?

    var notify: String { prefs?.notify ?? "all" }
    var muted: Bool { TeamTime.isOn(prefs?.mutedUntil) }
    var quietOrMuted: Bool { muted || notify == "none" }
    /// Unread shown bold with a count: not muted, not "only @mentions".
    var showsUnread: Bool { (unread ?? 0) > 0 && !quietOrMuted && notify != "mentions" }
}

struct TeamPerson: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String?
    let photoUrl: String?
    let isActive: Bool?
}

struct TeamOverview: Decodable {
    struct MeRow: Decodable, Hashable {
        let id: String
        let role: String?
        let timeZone: String?
        let dndUntil: String?
        let quiet: TeamQuiet?
    }
    let me: MeRow
    let people: [TeamPerson]?
    let channels: [TeamChannel]?
}

struct TeamAttachment: Codable, Hashable {
    let path: String
    let name: String?
    let type: String?
    let size: Int?
    let width: Double?
    let height: Double?

    var isGif: Bool { (type ?? "") == "image/gif" || path.lowercased().hasSuffix(".gif") }
    var ratio: CGFloat {
        if let w = width, let h = height, w > 0, h > 0 { return CGFloat(w / h) }
        return 4.0 / 3.0
    }
    var json: [String: Any] {
        var d: [String: Any] = ["path": path, "name": name ?? "photo", "type": type ?? "image/jpeg", "size": size ?? 0]
        d["width"] = width.map { $0 as Any } ?? NSNull()
        d["height"] = height.map { $0 as Any } ?? NSNull()
        return d
    }
}

struct TeamMessage: Decodable, Hashable, Identifiable {
    struct ReplyTo: Decodable, Hashable {
        let id: String
        let author: String
        let body: String?
        let deleted: Bool?
        let photos: Int?
    }
    struct Reaction: Decodable, Hashable {
        let emoji: String
        let by: [String]
    }

    let id: String
    let channelId: String
    /// A member id, or "atlas".
    let author: String
    let body: String
    let mentions: [String]?
    let mentionAll: Bool?
    let mentionAtlas: Bool?
    let attachments: [TeamAttachment]?
    let createdAt: String
    let editedAt: String?
    let deleted: Bool?
    let replyTo: ReplyTo?
    let reactions: [Reaction]?

    var isDeleted: Bool { deleted == true }
    var photos: [TeamAttachment] { attachments ?? [] }
}

struct TeamPage: Decodable {
    let messages: [TeamMessage]
    let more: Bool?
}

/// `muted_until` / `dnd_until`: null (off), a time, or "infinity".
enum TeamTime {
    static func isOn(_ until: String?) -> Bool {
        guard let u = until, !u.isEmpty else { return false }
        if u == "infinity" { return true }
        return (Stamp.date(u) ?? .distantPast) > Date()
    }

    /// "until 3:40 pm", "until tomorrow 8:00 am", "until you turn it off".
    static func label(_ until: String?) -> String {
        guard let u = until, !u.isEmpty else { return "" }
        if u == "infinity" { return "until you turn it off" }
        guard let d = Stamp.date(u) else { return "" }
        let t = DateFormatter(); t.dateFormat = "h:mm a"; t.amSymbol = "am"; t.pmSymbol = "pm"
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "until \(t.string(from: d))" }
        if cal.isDateInTomorrow(d) { return "until tomorrow \(t.string(from: d))" }
        let day = DateFormatter(); day.dateFormat = "EEE, MMM d"
        return "until \(day.string(from: d)) \(t.string(from: d))"
    }
}

// MARK: Costs (founders: paragon_costs)

struct Costs: Decodable {
    struct Totals: Decodable { let thinking: Flex?; let twilioCalls: Flex?; let twilioTexts: Flex?; let twilioOther: Flex? }
    struct ByModel: Decodable, Hashable { let model: String; let usd: Flex; let n: Int? }
    struct ByClient: Decodable, Hashable { let personId: String?; let name: String; let usd: Flex; let n: Int? }
    struct ByDay: Decodable, Hashable { let day: String; let thinking: Flex; let twilio: Flex }
    struct ByLine: Decodable, Hashable { let line: String; let calls: Int?; let texts: Int?; let usd: Flex }

    let days: Int?
    let budgetUsd: Flex?
    let todayThinkingUsd: Flex?
    let twilioSyncedAt: String?
    let twilioError: String?
    let totals: Totals?
    let byModel: [ByModel]?
    let byClient: [ByClient]?
    let noClientUsd: Flex?
    let byDay: [ByDay]?
    let twilioByLine: [ByLine]?
}

// MARK: Search (Solbuild's own global_search, the website's search bar)

/// One row of `global_search`. `resultType` is lead, user, contractor,
/// business…; the inbox adds its own "conversation" hits from paragon_queue.
struct GlobalSearchRow: Decodable, Hashable {
    let id: String
    let resultType: String
    let primaryName: String?
    let secondaryInfo: String?
    let extraInfo: String?
    let relevanceScore: Double?
    let statusName: String?
    let statusColor: String?
}

/// A lead's name and phone (and a guess at brand and state), to start a
/// conversation with someone Paragon has never texted (`paragon_lead_contact`).
struct LeadContact: Decodable {
    let name: String?
    let phone: String?
    let address: String?
    let brand: String?
    let state: String?
}

/// A line as `paragon_lines` lists it; New message needs only the customer
/// lines' brand and state, never the number.
struct LineInfo: Decodable, Hashable, Identifiable {
    let id: String
    let provider: String?
    let brand: String?
    let state: String?
    let kind: String?
    let inQuo: Bool?
}

struct StartedThread: Decodable {
    let threadId: String
    let personId: String
    let sendLabel: String?
}
