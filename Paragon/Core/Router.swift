import Foundation
import Observation

/// Which tab is up, and where a tapped notification wants to go.
@Observable
@MainActor
final class Router {
    static let shared = Router()

    enum Tab: Hashable { case inbox, personal, team, alerts, settings }

    var tab: Tab = .inbox
    var inboxPath: [Route] = []
    var personalPath: [Route] = []
    /// Team channel ids.
    var teamPath: [String] = []

    func open(_ route: Route) {
        switch route {
        case .person:
            tab = .inbox
            inboxPath = [route]
        case .personal:
            tab = .personal
            personalPath = [route]
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
            tab = .alerts
        }
    }
}
