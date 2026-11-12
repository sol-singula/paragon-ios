import Foundation

/// Example data for App Store screenshots, and nothing else. Only on with the
/// launch argument `-PARAGONDEMO` (the Screenshots workflow passes it); then
/// every `API` request answers from here and nothing reaches the network: no
/// sign in, no presence, no push or calling permission. Every name, number
/// and message below is made up. `-DEMOSCREEN inbox|search|conversation|
/// team|channel|personal` opens that screen once the app is up.
///
/// Times are written `@T<minutes from now>` and sort keys `@K<minutes>`;
/// both are filled in at launch, so the wait clocks read right on any day.
enum Demo {
    static let on = ProcessInfo.processInfo.arguments.contains("-PARAGONDEMO")

    static var screen: String {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-DEMOSCREEN"), i + 1 < a.count else { return "inbox" }
        return a[i + 1]
    }

    static let me = "d0000000-0000-4000-8000-000000000001"
    static let online: Set<String> = [me, "d0000000-0000-4000-8000-000000000003", "d0000000-0000-4000-8000-000000000004"]
    static let sarah = "e0000000-0000-4000-8000-000000000001"
    static let sarahThread = "f0000000-0000-4000-8000-000000000001"
    static let leadership = "c0000000-0000-4000-8000-000000000001"

    /// Opens the screen `-DEMOSCREEN` names.
    @MainActor static func open() {
        let r = Router.shared
        switch screen {
        case "search":
            r.tab = .inbox
            InboxModel.shared.search = "sar"
            InboxModel.shared.searchChanged()
        case "conversation": r.open(.person(personId: sarah, threadId: sarahThread))
        case "team": r.tab = .team
        case "channel":
            r.tab = .team
            r.teamPath = [leadership]
        case "personal": r.openPersonal(of: nil)
        default: r.tab = .inbox
        }
    }

    /// What `API.request` returns for an rpc or edge function in demo mode.
    static func data(_ name: String, _ body: [String: Any?]) -> Data {
        var json = fixtures[name] ?? "null"
        if name == "paragon_queue", let s = body["p_search"] as? String, !s.isEmpty {
            json = filtered(json, key: "name", contains: s)
        } else if name == "global_search" {
            json = filtered(json, key: "primary_name", contains: (body["p_query"] as? String) ?? "")
        }
        return Data(fill(json).utf8)
    }

    private static func filtered(_ json: String, key: String, contains q: String) -> String {
        guard let rows = (try? JSONSerialization.jsonObject(with: Data(fill(json).utf8))) as? [[String: Any]] else { return "[]" }
        let keep = rows.filter { (($0[key] as? String) ?? "").lowercased().contains(q.lowercased()) }
        guard let d = try? JSONSerialization.data(withJSONObject: keep) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func replace(_ text: String, _ pattern: String, _ make: (Double) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += make(Double(ns.substring(with: match.range(at: 1))) ?? 0)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// `"@T-14"` → an ISO time 14 minutes ago; `@K5` → a sort key 5 minutes on.
    private static func fill(_ json: String) -> String {
        let timed = replace(json, "\"@T(-?[0-9.]+)\"") { m in
            "\"" + iso.string(from: Date().addingTimeInterval(m * 60)) + "\""
        }
        return replace(timed, "@K(-?[0-9.]+)") { m in
            String(format: "%016.0f", Date().addingTimeInterval(m * 60).timeIntervalSince1970 * 1000)
        }
    }

    // MARK: Fixtures (made up, every one)

    private static let fixtures: [String: String] = [
        "paragon_me": #"{"id":"d0000000-0000-4000-8000-000000000001","name":"Jake Thompson","role":"owner","email":"jake@example.com"}"#,
        "paragon_ui_prefs": uiPrefs,
        "paragon_ui_prefs_set": uiPrefs,
        "paragon_badge_count": "1",
        "paragon_pins": "[]",
        "paragon_pin": "[]",
        "paragon_queue": queue,
        "global_search": search,
        "paragon_lead_conversation": "null",
        "paragon_lines": #"[{"id":"a0000000-0000-4000-8000-000000000001","kind":"personal","brand":null,"label":"Jake","state":"UT","provider":"twilio","owner_member_id":"d0000000-0000-4000-8000-000000000001","blocked":false,"in_quo":false,"messages":12}]"#,
        "paragon_personal": personal,
        "paragon_person": person,
        "paragon_thread_promises": promises,
        "paragon_house_photo": "null",
        "paragon_notifications": "[]",
        "paragon_activity_feed": feed,
        "paragon_feed_reactions": "{}",
        "paragon_team": team,
        "paragon_team_channels": channels,
        "paragon_team_read": teamRead,
        "paragon_team_recent_gifs": "[]",
    ]

    private static let uiPrefs = #"{"inbox":{"tab":"waiting","brand":null,"filter":"all","promises":"mine","homeowners_only":false}}"#

    private static let goldForm = #"""
    {"try":1,"tries":0,"max_tries":3,"attempts":[],"brand":"Just Glass","site":"justglass.example","form_name":"quote",
     "form":{"name":"Lauren Collins","phone":"(480) 555-0187","email":"lauren@example.com","address":"2214 W Saguaro Trl, Phoenix, AZ","wants":"Window replacement",
       "message":"Six windows on the west side, the seals are going.","fields":[{"label":"Need","value":"Window replacement"},{"label":"Windows or doors","value":"6"}],
       "texts_ok":true,"submitted_at":"@T-2","site":"justglass.example"}}
    """#

    private static let goldCard = #"""
    {"id":"b0000000-0000-4000-8000-000000000001","kind":"web_form","by":"atlas","title":"Call Lauren Collins","short":"Website form · Window replacement","why":"Window replacement",
     "due_at":"@T-2","open_to_all_at":"@T-2","team":true,"escalation":0,"action_type":"call","thread_id":"f0000000-0000-4000-8000-000000000007","owner_id":null,"mine":null,"created_at":"@T-2",
     "web_form":
    """# + goldForm + "}"

    private static let promiseCard = #"""
    {"id":"b0000000-0000-4000-8000-000000000002","kind":"promise","by":"atlas","title":"Send Kevin the revised quote with black frames","short":"Revised quote",
     "why":"You said: \"I'll have the new numbers to you this afternoon\"","due_at":"@T-1","open_to_all_at":"@T60","team":false,"escalation":0,"action_type":"text",
     "thread_id":"f0000000-0000-4000-8000-000000000003","owner_id":"d0000000-0000-4000-8000-000000000001","mine":true,"created_at":"@T-95"}
    """#

    private static func waiting(_ n: Int, _ name: String, _ city: String, _ brand: String, _ state: String, pct: Double, preview: String, last: Int, due: Int) -> String {
        let p = String(format: "e0000000-0000-4000-8000-%012d", n), t = String(format: "f0000000-0000-4000-8000-%012d", n)
        return """
        {"person_id":"\(p)","thread_id":"\(t)","name":"\(name)","city":"\(city)","contact_type":"homeowner",
         "status":"waiting","pct":\(pct),"preview":"\(preview)","last_activity_at":"@T\(last)","waiting_since":"@T\(last)",
         "due_at":"@T\(due)","due_source":"clock","overdue":\(pct >= 1),"atlas":false,"gold":false,"items":[],"private":false,"assigned_to_me":false,"sort_key":"0@K\(due)-\(n)",
         "threads":[{"id":"\(t)","brand":"\(brand)","state":"\(state)","space":"customer","status":"waiting","locked":false,"due_at":"@T\(due)","clock_started_at":"@T\(last)"}]}
        """
    }

    private static func closed(_ n: Int, _ name: String, _ city: String, _ brand: String, _ state: String, preview: String, last: Int) -> String {
        let p = String(format: "e0000000-0000-4000-8000-%012d", n), t = String(format: "f0000000-0000-4000-8000-%012d", n)
        return """
        {"person_id":"\(p)","thread_id":"\(t)","name":"\(name)","city":"\(city)","contact_type":"homeowner",
         "status":"closed","pct":null,"preview":"\(preview)","last_activity_at":"@T\(last)","waiting_since":null,
         "due_at":null,"due_source":null,"overdue":false,"atlas":false,"gold":false,"items":[],"private":false,"assigned_to_me":false,"sort_key":"1@K\(last)-\(n)",
         "threads":[{"id":"\(t)","brand":"\(brand)","state":"\(state)","space":"customer","status":"closed","locked":false,"due_at":null,"clock_started_at":null}]}
        """
    }

    private static let queue: String = {
        let gold = """
        {"person_id":"e0000000-0000-4000-8000-000000000007","thread_id":"f0000000-0000-4000-8000-000000000007","name":"Lauren Collins","city":"Phoenix","contact_type":"homeowner",
         "status":"closed","pct":null,"preview":null,"last_activity_at":"@T-2","waiting_since":null,"due_at":"@T-2","due_source":"card","overdue":true,
         "atlas":true,"gold":true,"private":false,"assigned_to_me":false,"sort_key":"!000-7","title":"Call Lauren Collins","why":"Window replacement",
         "card_id":"b0000000-0000-4000-8000-000000000001","card":\(goldCard),"items":[\(goldCard)],"web_form":\(goldForm),
         "threads":[{"id":"f0000000-0000-4000-8000-000000000007","brand":"Just Glass","state":"AZ","space":"customer","status":"closed","locked":false,"due_at":null,"clock_started_at":null}]}
        """
        let promise = """
        {"person_id":"e0000000-0000-4000-8000-000000000003","thread_id":"f0000000-0000-4000-8000-000000000003","name":"Kevin Parker","city":"Boise","contact_type":"homeowner",
         "status":"closed","pct":null,"preview":"Sounds good, send it over when you can.","last_activity_at":"@T-95","waiting_since":null,
         "due_at":"@T-1","due_source":"card","overdue":true,"atlas":true,"gold":false,"private":false,"assigned_to_me":true,"sort_key":"0@K-1-3",
         "title":"Send Kevin the revised quote with black frames","card_id":"b0000000-0000-4000-8000-000000000002",
         "card":\(promiseCard),"items":[\(promiseCard)],
         "threads":[{"id":"f0000000-0000-4000-8000-000000000003","brand":"Solara","state":"ID","space":"customer","status":"closed","locked":false,"due_at":null,"clock_started_at":null}]}
        """
        let rows = [
            gold,
            waiting(1, "Sarah Mitchell", "Sandy", "Solara", "UT", pct: 1.4, preview: "Can someone come out Thursday to measure the back slider?", last: -14, due: -4),
            promise,
            waiting(2, "Chris Anderson", "Mesa", "Just Glass", "AZ", pct: 0.72, preview: "Sent a photo of the cracked pane in the kitchen", last: -7, due: 3),
            waiting(4, "Brittany Hall", "Lehi", "Solara One", "UT", pct: 0.3, preview: "Is 3pm still good for the install tomorrow?", last: -3, due: 7),
            waiting(5, "Dan Whitaker", "Draper", "Solara", "UT", pct: 0.1, preview: "Thanks! What's the warranty on the black frames?", last: -1, due: 9),
            closed(6, "Amanda Reed", "Gilbert", "Just Glass", "AZ", preview: "Perfect, see you Saturday morning", last: -180),
            closed(8, "Megan O'Brien", "Meridian", "Solara", "ID", preview: "Call out", last: -240),
            closed(10, "Sarah Jensen", "Provo", "Solara One", "UT", preview: "Got it, thank you!", last: -1500),
            closed(9, "Tom Sullivan", "Orem", "Solara", "UT", preview: "We signed! Thanks for all your help", last: -320),
        ]
        return "[" + rows.joined(separator: ",") + "]"
    }()

    private static let search = #"""
    [{"id":"e1000000-0000-4000-8000-000000000001","result_type":"lead","primary_name":"Sarah Mitchell","secondary_info":"(801) 555-0142","extra_info":"1428 E Maple Ridge Dr, Sandy, UT","relevance_score":95,"status_name":"Quoted","status_color":"#6366F1"},
     {"id":"e1000000-0000-4000-8000-000000000002","result_type":"lead","primary_name":"Sarah Bennett","secondary_info":"(208) 555-0119","extra_info":"77 N Cedar Ln, Boise, ID","relevance_score":95,"status_name":"Sold","status_color":"#22C55E"},
     {"id":"e1000000-0000-4000-8000-000000000003","result_type":"lead","primary_name":"Sara Lindquist","secondary_info":"(480) 555-0163","extra_info":"905 E Juniper Ave, Gilbert, AZ","relevance_score":90,"status_name":"New lead","status_color":"#F59E0B"},
     {"id":"e1000000-0000-4000-8000-000000000005","result_type":"lead","primary_name":"Sarah Peterson","secondary_info":"(801) 555-0128","extra_info":"412 W 900 N, Lehi, UT","relevance_score":88,"status_name":"Installed","status_color":"#14B8A6"},
     {"id":"e1000000-0000-4000-8000-000000000006","result_type":"lead","primary_name":"Sarah Collins","secondary_info":"(602) 555-0171","extra_info":"18 E Palo Verde Dr, Tempe, AZ","relevance_score":86,"status_name":"Measured","status_color":"#3B82F6"},
     {"id":"e1000000-0000-4000-8000-000000000004","result_type":"contractor","primary_name":"Sarratt Glass & Glazing","secondary_info":"Installer","extra_info":"Mesa, AZ","relevance_score":70,"status_name":null,"status_color":null}]
    """#

    private static let person = #"""
    {"person":{"id":"e0000000-0000-4000-8000-000000000001","name":"Sarah Mitchell","has_name":true,"city":"Sandy","contact_type":"homeowner","is_stopped":false,
       "source":"Solara","nexus_lead_id":"e1000000-0000-4000-8000-000000000001","type_known":true,"ask_type":false},
     "threads":[{"id":"f0000000-0000-4000-8000-000000000001","brand":"Solara","state":"UT","space":"customer","status":"waiting","locked":false,
       "label":"Sends as Solara · (801) 555-0100","due_at":"@T-4","clock_started_at":"@T-14","last_activity_at":"@T-14"}],
     "thread_id":"f0000000-0000-4000-8000-000000000001","send_label":"Sends as Solara · (801) 555-0100","can_send":true,"locked_reason":null,
     "lead":{"id":"e1000000-0000-4000-8000-000000000001","address":"1428 E Maple Ridge Dr, Sandy, UT","email":"sarah.mitchell@example.com","description":null},
     "appointment":null,"history":[],
     "timeline":[
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000011","at":"@T-4380","direction":"in","body":"Hi, is this Solara? A neighbor on Maple Ridge gave me your number.","media":[],"status":"received","automated":false,"by":null,"atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000012","at":"@T-4374","direction":"out","body":"It is! This is Jake. What can we help you with?","media":[],"status":"delivered","automated":false,"by":"Jake Thompson","atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000013","at":"@T-4370","direction":"in","body":"Our windows fog up every winter. Do you do replacements?","media":[],"status":"received","automated":false,"by":null,"atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000001","at":"@T-1560","direction":"in","body":"Hi! We got your flyer. We're thinking about replacing the sliding door and a few windows in the back.","media":[],"status":"received","automated":false,"by":null,"atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000002","at":"@T-1554","direction":"out","body":"Hi Sarah, this is Jake with Solara. Happy to help! How many windows, roughly?","media":[],"status":"delivered","automated":false,"by":"Jake Thompson","atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000003","at":"@T-1545","direction":"in","body":"Four windows plus the slider. The slider sticks every time it rains.","media":[],"status":"received","automated":false,"by":null,"atlas":false},
      {"kind":"call","id":"aa000000-0000-4000-8000-000000000004","at":"@T-1500","direction":"out","body":null,"media":[],"status":"completed","automated":false,"by":"Jake Thompson","atlas":false,
       "duration":412,"answered":true,"summary":"Went over the slider and four windows; Sarah wants black frames. Quote to follow."},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000005","at":"@T-16","direction":"in","body":"Can someone come out Thursday to measure the back slider? It's the one by the kitchen.","media":[],"status":"received","automated":false,"by":null,"atlas":false},
      {"kind":"text","id":"aa000000-0000-4000-8000-000000000006","at":"@T-14","direction":"in","body":"Afternoon works best, anytime after 2 🙏","media":[],"status":"received","automated":false,"by":null,"atlas":false}
     ]}
    """#

    private static let promises = #"""
    [{"id":"b0000000-0000-4000-8000-000000000003","kind":"promise","title":"Send Sarah the quote for the slider and four black windows","short":"Quote: slider + 4 windows",
      "why":"You said: \"I'll get you a quote by Friday\"","due_at":"@T1200","open_to_all_at":"@T1320","status":"open",
      "member_id":"d0000000-0000-4000-8000-000000000001","thread_id":"f0000000-0000-4000-8000-000000000001"}]
    """#

    private static let personal = #"""
    [{"thread_id":"f0000000-0000-4000-8000-000000000020","person_id":"e0000000-0000-4000-8000-000000000020","line":"Jake","name":"Coach Miller","phone":"+18015550177",
      "status":"waiting","last_activity_at":"@T-20","preview":"Practice moved to 6:30 tonight","preview_kind":"text","contact_type":"homeowner","ask_type":false,"released":false}]
    """#

    private static let feed = #"""
    [{"id":"sale:demo-1","kind":"sale","at":"@T-3","actor_first_name":"Megan",
      "parts":[{"text":"Megan","style":"b"},{"text":" sold ","style":null},{"text":"Tom Sullivan","style":"b"},{"text":" · $18,400","style":"k"}],
      "reactions":[{"emoji":"🔥","count":3,"mine":true,"names":["Jake","Ryan","Emily"]}]},
     {"id":"kept:demo-2","kind":"promise_kept","at":"@T-9","actor_first_name":"Ryan",
      "parts":[{"text":"Ryan kept a promise to ","style":null},{"text":"Amanda R.","style":"b"},{"text":", 2h early","style":"k"}],"reactions":[]}]
    """#

    private static let team = #"""
    [{"id":"d0000000-0000-4000-8000-000000000001","name":"Jake Thompson","role":"owner","is_me":true,"on_call":false,"call_with":null,"photo_url":null,"call_person_id":null,"call_started_at":null},
     {"id":"d0000000-0000-4000-8000-000000000002","name":"Ryan Brooks","role":"owner","is_me":false,"on_call":true,"call_with":"Chris Anderson","photo_url":null,"call_person_id":"e0000000-0000-4000-8000-000000000002","call_started_at":"@T-3"},
     {"id":"d0000000-0000-4000-8000-000000000003","name":"Emily Carter","role":"manager","is_me":false,"on_call":false,"call_with":null,"photo_url":null,"call_person_id":null,"call_started_at":null},
     {"id":"d0000000-0000-4000-8000-000000000004","name":"Megan Taylor","role":"rep","is_me":false,"on_call":false,"call_with":null,"photo_url":null,"call_person_id":null,"call_started_at":null},
     {"id":"d0000000-0000-4000-8000-000000000005","name":"Tyler Jensen","role":"rep","is_me":false,"on_call":false,"call_with":null,"photo_url":null,"call_person_id":null,"call_started_at":null}]
    """#

    private static let channels = #"""
    {"me":{"id":"d0000000-0000-4000-8000-000000000001","role":"owner","time_zone":"America/Denver","dnd_until":null,"quiet":null},
     "people":[{"id":"d0000000-0000-4000-8000-000000000001","name":"Jake Thompson","role":"owner","is_active":true,"photo_url":null},
               {"id":"d0000000-0000-4000-8000-000000000002","name":"Ryan Brooks","role":"owner","is_active":true,"photo_url":null},
               {"id":"d0000000-0000-4000-8000-000000000003","name":"Emily Carter","role":"manager","is_active":true,"photo_url":null},
               {"id":"d0000000-0000-4000-8000-000000000004","name":"Megan Taylor","role":"rep","is_active":true,"photo_url":null},
               {"id":"d0000000-0000-4000-8000-000000000005","name":"Tyler Jensen","role":"rep","is_active":true,"photo_url":null}],
     "channels":[
      {"id":"c0000000-0000-4000-8000-000000000001","name":"Leadership","about":"Jake, Ryan, Emily and Megan","atlas_in":true,"unread":2,"mentions":1,"last_at":"@T-4","last_read_at":"@T-20",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000002","d0000000-0000-4000-8000-000000000003","d0000000-0000-4000-8000-000000000004"],
       "prefs":{"notify":"all","muted_until":null,"always":false,"quiet":null}},
      {"id":"c0000000-0000-4000-8000-000000000002","name":"Everyone","about":"The whole team","atlas_in":true,"unread":5,"mentions":0,"last_at":"@T-12","last_read_at":"@T-90",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000002","d0000000-0000-4000-8000-000000000003","d0000000-0000-4000-8000-000000000004","d0000000-0000-4000-8000-000000000005"],
       "prefs":{"notify":"all","muted_until":null,"always":false,"quiet":null}},
      {"id":"c0000000-0000-4000-8000-000000000003","name":"Installs","about":"Crews and scheduling","atlas_in":true,"unread":0,"mentions":0,"last_at":"@T-45","last_read_at":"@T-40",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000004","d0000000-0000-4000-8000-000000000005"],
       "prefs":{"notify":"all","muted_until":null,"always":false,"quiet":null}},
      {"id":"c0000000-0000-4000-8000-000000000004","name":"Sales","about":"Leads, quotes and closes","atlas_in":true,"unread":0,"mentions":0,"last_at":"@T-70","last_read_at":"@T-60",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000003","d0000000-0000-4000-8000-000000000004"],
       "prefs":{"notify":"mentions","muted_until":null,"always":false,"quiet":null}},
      {"id":"c0000000-0000-4000-8000-000000000005","name":"Arizona crew","about":"Phoenix and Mesa","atlas_in":false,"unread":0,"mentions":0,"last_at":"@T-200","last_read_at":"@T-190",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000005"],
       "prefs":{"notify":"all","muted_until":null,"always":false,"quiet":null}},
      {"id":"c0000000-0000-4000-8000-000000000006","name":"Wins","about":"Every sale, every five-star review","atlas_in":true,"unread":0,"mentions":0,"last_at":"@T-300","last_read_at":"@T-290",
       "members":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000002","d0000000-0000-4000-8000-000000000003","d0000000-0000-4000-8000-000000000004","d0000000-0000-4000-8000-000000000005"],
       "prefs":{"notify":"all","muted_until":null,"always":false,"quiet":null}}]}
    """#

    private static let teamRead = #"""
    {"more":false,"messages":[
     {"id":"ab000000-0000-4000-8000-000000000011","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000001",
      "body":"Great week everyone. Arizona is up 30% on last month","mentions":[],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-1500","edited_at":null,"deleted":false,"reply_to":null,"reactions":[{"emoji":"🙌","by":["d0000000-0000-4000-8000-000000000002","d0000000-0000-4000-8000-000000000003","d0000000-0000-4000-8000-000000000004"]}]},
     {"id":"ab000000-0000-4000-8000-000000000012","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000004",
      "body":"Booked three measures in Lehi tomorrow 👍","mentions":[],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-1440","edited_at":null,"deleted":false,"reply_to":null,"reactions":[]},
     {"id":"ab000000-0000-4000-8000-000000000001","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000003",
      "body":"Morning! 14 appointments on the board today, Utah is slammed 💪","mentions":[],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-95","edited_at":null,"deleted":false,"reply_to":null,
      "reactions":[{"emoji":"🔥","by":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000002"]}]},
     {"id":"ab000000-0000-4000-8000-000000000002","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000002",
      "body":"Chris Anderson's install moved to Friday, the glass came in early","mentions":[],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-60","edited_at":null,"deleted":false,"reply_to":null,"reactions":[]},
     {"id":"ab000000-0000-4000-8000-000000000003","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000003",
      "body":"Megan just closed Tom Sullivan in Orem, a whole house of black windows 🎉","mentions":[],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-12","edited_at":null,"deleted":false,"reply_to":null,
      "reactions":[{"emoji":"🎉","by":["d0000000-0000-4000-8000-000000000001","d0000000-0000-4000-8000-000000000002"]},{"emoji":"💰","by":["d0000000-0000-4000-8000-000000000002"]}]},
     {"id":"ab000000-0000-4000-8000-000000000004","channel_id":"c0000000-0000-4000-8000-000000000001","author":"d0000000-0000-4000-8000-000000000002",
      "body":"@Jake can you take the Sarah Mitchell measure Thursday afternoon?","mentions":["d0000000-0000-4000-8000-000000000001"],"mention_all":false,"mention_atlas":false,"attachments":[],
      "created_at":"@T-4","edited_at":null,"deleted":false,"reply_to":null,"reactions":[]}]}
    """#
}
