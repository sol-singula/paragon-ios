import Foundation
import Observation

/// A teammate whose personal line is open.
struct LineOf: Equatable, Hashable { let id: String; let name: String }

/// Which tab is up, and where a tapped notification wants to go.
@Observable
@MainActor
final class Router {
    static let shared = Router()

    /// No Alerts tab (founder, 2026-11-10: "Remove the 'alerts' page on iOS").
    enum Tab: Hashable { case inbox, personal, team, settings }

    var tab: Tab = .inbox
    var inboxPath: [Route] = []
    var personalPath: [Route] = []
    /// Whose personal line Personal shows: nil is mine; founders and
    /// managers open a teammate's from their face (Team).
    var personalOf: LineOf?
    /// Team channel ids.
    var teamPath: [String] = []

    /// My own line is the inbox's Personal filter (founder, 2026-11-11: no
    /// Personal tab); a teammate's line (founders and managers, from Team)
    /// still opens on its own page, off the tab bar.
    func openPersonal(of member: LineOf?) {
        personalOf = member
        personalPath = []
        if member == nil {
            InboxModel.shared.choose(show: .personal)
            inboxPath = []
            tab = .inbox
        } else {
            tab = .personal
        }
    }

    func open(_ route: Route) {
        switch route {
        case .person:
            tab = .inbox
            inboxPath = [route]
        case .personal:
            // A text to my personal line: its conversation, over the inbox.
            tab = .inbox
            personalOf = nil
            inboxPath = [route]
        }
    }

    /// From a push's custom keys (paragon-push): kind, thread_id, person_id.
    func open(push keys: [String: String], title: String?) {
        let thread = keys["thread_id"], person = keys["person_id"]
        if keys["kind"]?.hasPrefix("team.") == true {
            tab = .team
        } else if keys["kind"] == "personal.text", let thread {
            open(.personal(threadId: thread, name: title ?? "Personal"))
        } else if let person {
            open(.person(personId: person, threadId: thread))
        } else {
            // Nothing to open (an owner's page about a line, say): the inbox.
            tab = .inbox
            inboxPath = []
        }
    }
}
