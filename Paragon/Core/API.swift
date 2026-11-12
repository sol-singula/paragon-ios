import Foundation

enum APIError: LocalizedError {
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .server(let m): return m
        case .decoding(let m): return "Paragon sent something this version can't read (\(m))."
        }
    }
}

/// Every Paragon read and write is a `public.paragon_*` function (it checks
/// the caller is a member first). Sending a text and calling go through edge
/// functions, as on the desktop.
enum API {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: Raw requests

    private static func request(_ url: URL, body: [String: Any?]) async throws -> Data {
        // App Store screenshots only (launch argument -PARAGONDEMO): made-up data, no network.
        if Demo.on { return Demo.data(url.lastPathComponent, body) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        // A failed refresh or request is never a sign out: it shows
        // "Reconnecting…" (Session) and the caller's own retry tries again.
        let token: String
        do { token = try await Supa.accessToken() } catch {
            if !Session.isDefinitiveAuthFailure(error) { await Session.shared.noteConnectionTrouble() }
            throw error
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let clean = body.mapValues { $0 ?? NSNull() }
        req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch {
            if error is URLError { await Session.shared.noteConnectionTrouble() }
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 502 || status == 503 || status == 504 || status >= 520 {
            await Session.shared.noteConnectionTrouble()
        } else {
            await Session.shared.noteConnected()
        }
        guard (200..<300).contains(status) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["error"] as? String) ?? (obj?["message"] as? String)
                ?? String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
                ?? "Paragon didn't answer (\(status))."
            throw APIError.server(msg)
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch let DecodingError.keyNotFound(key, ctx) { throw APIError.decoding("\(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))") }
        catch let DecodingError.typeMismatch(_, ctx) { throw APIError.decoding(ctx.codingPath.map(\.stringValue).joined(separator: ".")) }
        catch let DecodingError.valueNotFound(_, ctx) { throw APIError.decoding(ctx.codingPath.map(\.stringValue).joined(separator: ".")) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    static func rpc<T: Decodable>(_ fn: String, _ args: [String: Any?] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await request(AppConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(fn)"), body: args)
        return try decode(T.self, data)
    }

    /// An rpc whose answer isn't needed (or is void).
    static func call(_ fn: String, _ args: [String: Any?] = [:]) async throws {
        _ = try await request(AppConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/\(fn)"), body: args)
    }

    static func function<T: Decodable>(_ name: String, query: [String: String] = [:], body: [String: Any?] = [:], as type: T.Type = T.self) async throws -> T {
        var comps = URLComponents(url: AppConfig.supabaseURL.appendingPathComponent("functions/v1/\(name)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let data = try await request(comps.url!, body: body)
        return try decode(T.self, data)
    }

    // MARK: Paragon

    static func me() async throws -> Me? { try await rpc("paragon_me", as: Me?.self) }

    /// The person's own app choices (paragon_ui_prefs), the same on every copy of the app.
    static func uiPrefs() async throws -> UiPrefs? {
        try await rpc("paragon_ui_prefs", as: UiPrefs?.self)
    }

    /// Merges one level deep (`["inbox": ["tab": "all"]]`); NSNull removes a key.
    @discardableResult
    static func uiPrefsSet(_ p: [String: Any]) async throws -> UiPrefs? {
        try await rpc("paragon_ui_prefs_set", ["p": p], as: UiPrefs?.self)
    }

    /// The app icon badge: my late waiting conversations (paragon_badge_count).
    static func badgeCount() async throws -> Int {
        try await rpc("paragon_badge_count", as: Int?.self) ?? 0
    }

    /// The inbox, filtered by one choice (`paragon_queue(p_filter, ...)`):
    /// all | homeowners | logistics | brand:<brand>. A server without that
    /// overload gets the old call.
    static func queue(filter: String, search: String?, promises: String? = nil) async throws -> [QueueItem] {
        do {
            var args: [String: Any?] = ["p_filter": filter, "p_search": search]
            if let promises { args["p_promises"] = promises }
            return try await rpc("paragon_queue", args, as: [QueueItem]?.self) ?? []
        } catch {
            let m = error.localizedDescription
            guard m.contains("p_filter") || m.localizedCaseInsensitiveContains("function") || m.contains("schema cache") else { throw error }
            let brand: String? = filter == "logistics" ? "logistics" : filter.hasPrefix("brand:") ? String(filter.dropFirst(6)) : nil
            return try await rpc("paragon_queue", ["p_homeowners_only": filter == "homeowners", "p_brand": brand, "p_search": search], as: [QueueItem]?.self) ?? []
        }
    }

    /// Solbuild's search: clients, team, contractors, businesses.
    static func globalSearch(_ query: String, limit: Int = 30) async throws -> [GlobalSearchRow] {
        try await rpc("global_search", ["p_query": query, "p_limit": limit], as: [GlobalSearchRow]?.self) ?? []
    }

    /// The person a Nexus lead already is in Paragon, or nil.
    static func leadConversation(_ lead: String) async throws -> String? {
        try await rpc("paragon_lead_conversation", ["p_lead": lead], as: String?.self)
    }

    static func leadContact(_ lead: String) async throws -> LeadContact? {
        try await rpc("paragon_lead_contact", ["p_lead": lead], as: LeadContact?.self)
    }

    /// Who has this number: a person and their customer conversations, or nil.
    static func phoneLookup(_ phone: String) async throws -> PhoneLookup? {
        try await rpc("paragon_phone_lookup", ["p_phone": phone], as: PhoneLookup?.self)
    }

    static func lines() async throws -> [LineInfo] {
        try await rpc("paragon_lines", as: [LineInfo]?.self) ?? []
    }

    /// Brand and state, never a line: an existing brand thread keeps its own.
    static func startThread(phone: String, name: String, brand: String, state: String, guessed: Bool) async throws -> StartedThread {
        try await rpc("paragon_start_thread", ["p_phone": phone, "p_name": name, "p_brand": brand, "p_state": state, "p_state_guessed": guessed], as: StartedThread.self)
    }

    static func person(_ person: String, thread: String?) async throws -> PersonView? {
        try await rpc("paragon_person", ["p_person": person, "p_thread": thread], as: PersonView?.self)
    }

    /// My personal line, or (founders and managers) a teammate's.
    static func personal(member: String? = nil) async throws -> [PersonalItem] {
        try await rpc("paragon_personal", member.map { ["p_member": $0] } ?? [:], as: [PersonalItem]?.self) ?? []
    }

    /// Off the waiting list with a reason (logged). It comes back when they
    /// text or call again.
    static func releaseThread(_ thread: String, reason: String) async throws {
        try await call("paragon_thread_release", ["p_thread": thread, "p_reason": reason])
    }

    /// Homeowner, contractor, vendor or spam. Returns how many conversations
    /// spam released.
    @discardableResult
    static func setContactType(_ person: String, type: String) async throws -> Int {
        struct R: Decodable { let ok: Bool?; let released: Flex? }
        return Int(try await rpc("paragon_set_contact_type", ["p_person": person, "p_type": type], as: R.self).released?.value ?? 0)
    }

    /// My pins on Recent (founder, 2026-11-11), oldest first. Only mine, on every device.
    struct Pin: Decodable { let person_id: String }
    static func pins() async throws -> [String] {
        try await rpc("paragon_pins", as: [Pin].self).map(\.person_id)
    }
    @discardableResult
    static func pin(_ person: String, on: Bool) async throws -> [String] {
        try await rpc("paragon_pin", ["p_person": person, "p_on": on], as: [Pin].self).map(\.person_id)
    }

    static func personDetails(_ person: String) async throws -> PersonDetails? {
        try await rpc("paragon_person_details", ["p_person": person], as: PersonDetails?.self)
    }

    /// "Not it" on a suggested address: never suggest that address for this contact again.
    static func declineFoundAddress(_ person: String, _ address: String) async throws {
        try await call("paragon_decline_found_address", ["p_person": person, "p_address": address])
    }

    static func personUpdate(_ person: String, email: String? = nil, address: String? = nil, notes: String? = nil) async throws {
        try await call("paragon_person_update", ["p_person": person, "p_email": email, "p_address": address, "p_notes": notes])
    }

    static func personRename(_ person: String, name: String) async throws {
        try await call("paragon_person_rename", ["p_person": person, "p_name": name])
    }

    static func personalThread(_ thread: String) async throws -> PersonalThread? {
        try await rpc("paragon_personal_thread", ["p_thread": thread], as: PersonalThread?.self)
    }

    static func notifications() async throws -> [Notice] {
        try await rpc("paragon_notifications", as: [Notice]?.self) ?? []
    }

    static func notificationsRead() async throws { try await call("paragon_notifications_read") }

    /// Gold (2026-11-10): they did not pick up. Out of the inbox, back for the
    /// next try, or a normal conversation after the last one.
    struct WebFormLater: Decodable { let ended: Bool?; let tries: Int?; let maxTries: Int?; let dueAt: String? }
    static func webFormLater(_ id: String) async throws -> WebFormLater {
        try await rpc("paragon_web_form_later", ["p_id": id])
    }
    /// Gold no more: a normal conversation now.
    static func webFormDone(_ id: String, note: String? = nil) async throws {
        try await call("paragon_web_form_done", ["p_id": id, "p_note": note])
    }

    static func atlasCardAct(_ id: String, action: String, due: String? = nil, note: String? = nil) async throws {
        try await call("paragon_atlas_card_act", ["p_id": id, "p_action": action, "p_due": due, "p_note": note, "p_member": nil])
    }

    // MARK: Promises (WHO, WHEN, WHAT). The server checks who may take and
    // act on each one; nothing here decides that.

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// The WHO picker for a conversation: me first, then who can take it.
    /// Where Atlas would put a vague WHEN ("soon", "today", "this_week") for
    /// that owner (nil = me): `paragon_promise_slot`.
    static func promiseSlot(thread: String, owner: String?, hint: String) async throws -> PromiseSlot? {
        try await rpc("paragon_promise_slot", ["p_thread": thread, "p_owner": owner, "p_hint": hint], as: PromiseSlot?.self)
    }

    /// Add a promise at the time Atlas places for a vague WHEN.
    @discardableResult
    static func promiseAddVague(thread: String, owner: String?, hint: String, text: String) async throws -> PromiseSlot? {
        try await rpc("paragon_promise_add_vague", ["p_thread": thread, "p_owner": owner, "p_hint": hint, "p_text": text], as: PromiseSlot?.self)
    }

    /// The quick WHENs for a conversation (owner nil = me, or the promise's
    /// own owner when `promise` is the one being moved).
    static func promiseChoices(thread: String, owner: String?, promise: String?) async throws -> [PromiseChoice] {
        (try await rpc("paragon_promise_choices", ["p_thread": thread, "p_owner": owner, "p_promise": promise], as: LossyList<PromiseChoice>?.self))?.items ?? []
    }

    /// Move a promise or card to a quick WHEN (`owner`: the new WHO, when it changes too).
    static func promiseMove(_ id: String, hint: String, owner: String?) async throws {
        try await call("paragon_promise_move", ["p_id": id, "p_hint": hint, "p_owner": owner])
    }

    static func promisePeople(thread: String) async throws -> [PromisePerson] {
        (try await rpc("paragon_promise_people", ["p_thread": thread], as: LossyList<PromisePerson>?.self))?.items ?? []
    }

    /// `owner` nil is me. Returns the new promise's id.
    @discardableResult
    static func promiseAdd(thread: String, owner: String?, due: Date, text: String) async throws -> String? {
        struct R: Decodable { let id: String?; let threadStatus: String? }
        return try await rpc("paragon_promise_add", ["p_thread": thread, "p_owner": owner, "p_due": iso.string(from: due), "p_text": text],
                             as: R?.self)?.id
    }

    /// `kept` or `dismissed`.
    static func promiseDone(_ id: String, outcome: String, note: String? = nil) async throws {
        try await call("paragon_promise_done", ["p_id": id, "p_outcome": outcome, "p_note": note])
    }

    static func promiseReassign(_ id: String, owner: String, note: String? = nil) async throws {
        try await call("paragon_promise_reassign", ["p_id": id, "p_owner": owner, "p_note": note])
    }

    /// WHEN and/or WHAT; nil leaves it as it is.
    static func promiseUpdate(_ id: String, due: Date?, text: String?) async throws {
        try await call("paragon_promise_update", ["p_id": id, "p_due": due.map { iso.string(from: $0) }, "p_text": text])
    }

    /// Every promise on a conversation (open, and those cleared in the last
    /// two weeks).
    static func threadPromises(_ thread: String) async throws -> [ThreadPromise] {
        (try await rpc("paragon_thread_promises", ["p_thread": thread], as: LossyList<ThreadPromise>?.self))?.items ?? []
    }

    /// Hand an Atlas card (not a promise) to someone.
    static func atlasCardHand(_ id: String, to member: String) async throws {
        try await call("paragon_atlas_card_act", ["p_id": id, "p_action": "hand", "p_due": nil, "p_note": nil, "p_member": member])
    }

    /// With the call's sid the card names the line the customer dialed
    /// (`paragon_call_card(thread, parent)`), never the 877 bridge; an older
    /// server gets the thread's line.
    static func callCard(_ thread: String, parent: String? = nil) async throws -> CallCard? {
        if let parent, !parent.isEmpty,
           let c = try? await rpc("paragon_call_card", ["p_thread": thread, "p_parent": parent], as: CallCard?.self) { return c }
        return try await rpc("paragon_call_card", ["p_thread": thread], as: CallCard?.self)
    }

    /// Only paragon-send sends. Attachments are files already uploaded to
    /// the public paragon-shared bucket (`Storage.uploadShared`); the body
    /// may be empty when there are some.
    /// Returns the message's id (`paragon.messages.id`, the timeline's id)
    /// when the function names it. `clientId` is ours, for the server to
    /// echo back if it ever does; it never changes what is sent.
    @discardableResult
    static func send(thread: String, body: String, attachments: [SharedFile] = [], clientId: String? = nil) async throws -> String? {
        struct Sent: Decodable { let ok: Bool?; let messageId: String? }
        let files: [[String: Any]] = attachments.map { ["path": $0.path, "name": $0.name, "type": $0.type] }
        var payload: [String: Any?] = ["thread_id": thread, "body": body, "attachments": files]
        if let clientId { payload["client_id"] = clientId }
        return try await function("paragon-send", body: payload, as: Sent.self).messageId
    }

    /// The Street View image Nexus saved for their lead, or null.
    static func housePhoto(_ person: String) async throws -> String? {
        try await rpc("paragon_house_photo", ["p_person": person], as: String?.self)
    }

    /// Everyone on the team: photo, and whether they're on a call.
    static func team() async throws -> [TeamMember] {
        try await rpc("paragon_team", as: [TeamMember]?.self) ?? []
    }

    /// I am here (every 30 s while Paragon is open): paragon_team's `online`.
    static func presencePing() async throws {
        try await call("paragon_presence_ping")
    }

    static func costs(days: Int, grain: String = "day") async throws -> Costs {
        try await rpc("paragon_costs", ["p_days": days, "p_grain": grain], as: Costs.self)
    }

    // MARK: Team chat (each one checks the caller can see the channel)

    static func teamChannels() async throws -> TeamOverview {
        try await rpc("paragon_team_channels", as: TeamOverview.self)
    }

    static func teamRead(channel: String, before: String? = nil, limit: Int = 60) async throws -> TeamPage {
        try await rpc("paragon_team_read", ["p_channel": channel, "p_before": before, "p_limit": limit], as: TeamPage.self)
    }

    static func teamPost(channel: String, body: String, attachments: [TeamAttachment], replyTo: String?, mentions: [String]) async throws -> TeamMessage {
        try await rpc("paragon_team_post", ["p_channel": channel, "p_body": body, "p_attachments": attachments.map(\.json),
                                            "p_reply_to": replyTo, "p_mentions": mentions], as: TeamMessage.self)
    }

    static func teamEdit(message: String, body: String) async throws -> TeamMessage {
        try await rpc("paragon_team_edit", ["p_message": message, "p_body": body], as: TeamMessage.self)
    }

    static func teamDelete(message: String) async throws {
        try await call("paragon_team_delete", ["p_message": message])
    }

    static func teamReact(message: String, emoji: String, on: Bool) async throws -> TeamMessage {
        try await rpc("paragon_team_react", ["p_message": message, "p_emoji": emoji, "p_on": on], as: TeamMessage.self)
    }

    static func teamMarkRead(channel: String) async throws {
        try await call("paragon_team_mark_read", ["p_channel": channel])
    }

    /// `p` holds only the keys that change: notify (all | mentions | none),
    /// mute (off | 1h | 8h | tomorrow | forever), always, quiet (or NSNull).
    static func teamPrefsSet(channel: String, _ p: [String: Any]) async throws {
        try await call("paragon_team_prefs_set", ["p_channel": channel, "p": p])
    }

    /// `p`: dnd (off | 1h | 8h | tomorrow | on), quiet (or NSNull), time_zone.
    static func teamMeSet(_ p: [String: Any]) async throws {
        try await call("paragon_team_me_set", ["p": p])
    }

    static func teamRecentGifs() async throws -> [TeamAttachment] {
        try await rpc("paragon_team_recent_gifs", ["p_limit": 24], as: [TeamAttachment]?.self) ?? []
    }

    static func voiceToken() async throws -> VoiceToken {
        try await function("paragon-voice", query: ["op": "token", "platform": "ios", "env": AppConfig.apnsEnv], as: VoiceToken.self)
    }

    static func voiceControl(action: String, parent: String) async throws {
        struct Ok: Decodable { let ok: Bool? }
        _ = try await function("paragon-voice", query: ["op": "control"], body: ["action": action, "parent": parent], as: Ok.self)
    }

    /// Hand an incoming call to a teammate (the desktop's Transfer).
    static func voiceTransfer(parent: String, to: String) async throws {
        struct Ok: Decodable { let ok: Bool? }
        _ = try await function("paragon-voice", query: ["op": "control"], body: ["action": "transfer", "parent": parent, "to": to], as: Ok.self)
    }

    /// More than two on a call: who is on it, add someone (a teammate's id or
    /// a number), take someone off. The server makes it a conference.
    static func callPeople(parent: String) async throws -> CallPeople {
        try await function("paragon-voice", query: ["op": "control"], body: ["action": "people", "parent": parent], as: CallPeople.self)
    }
    static func callAdd(parent: String, member: String? = nil, number: String? = nil) async throws -> CallPeople {
        var b: [String: Any?] = ["action": "add", "parent": parent]
        if let member { b["member"] = member }
        if let number { b["number"] = number }
        return try await function("paragon-voice", query: ["op": "control"], body: b, as: CallPeople.self)
    }
    static func callRemove(parent: String, key: String) async throws -> CallPeople {
        try await function("paragon-voice", query: ["op": "control"], body: ["action": "remove", "parent": parent, "key": key], as: CallPeople.self)
    }
    static func callTargets(thread: String) async throws -> [CallTarget] {
        try await rpc("paragon_call_targets", ["p_thread": thread], as: [CallTarget]?.self) ?? []
    }

    static func registerDevice(token: String, kind: String) async throws {
        try await call("paragon_device_register", ["p_token": token, "p_kind": kind, "p_env": AppConfig.apnsEnv, "p_bundle": AppConfig.bundleID])
    }

    static func unregisterDevice(token: String) async throws {
        try await call("paragon_device_unregister", ["p_token": token])
    }
}
