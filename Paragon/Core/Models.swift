import Foundation

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
    var first: String { name.split(separator: " ").first.map(String.init) ?? name }
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

    var id: String { personId }
    var firstThread: QueueThread? { threads?.first }
    var tone: ClockTone { status == "waiting" ? ClockTone(pct: pct) : .calm }
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
    let owner: String?
    let label: String?
    let lastActivityAt: String?
}

struct TimelineEvent: Decodable, Hashable, Identifiable {
    let kind: String          // "text" | "call"
    let id: String
    let at: String
    let direction: String     // "in" | "out"
    let body: String?
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
    }
    struct Lead: Decodable { let id: String; let address: String?; let email: String? }
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

    var id: String { threadId }
}

struct PersonalThread: Decodable {
    let threadId: String
    let sendLabel: String?
    let timeline: [TimelineEvent]?
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

struct AtlasCard: Decodable, Hashable, Identifiable {
    struct Action: Decodable, Hashable { let type: String?; let body: String? }
    let id: String
    let kind: String
    let title: String
    let why: String?
    let action: Action?
    let dueAt: String?
    let personId: String?
    let threadId: String?
    let name: String?
    let brand: String?
    let short: String?
}

struct AtlasDeck: Decodable {
    let cards: [AtlasCard]
    let later: Int?
    let clearedToday: Int?
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
