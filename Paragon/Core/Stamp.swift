import Foundation

/// Times as the desktop shows them: "4 min", "2 h 5 min", "3 d" for how long
/// someone has waited, "4:12 pm" / "Tue 4:12 pm" / "Oct 3" for when.
enum Stamp {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres sends "2026-11-09T10:22:33.123456+00:00": six fractional
    /// digits, which the formatter refuses, so they are cut to three.
    static func date(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        if s.count >= 10, !s.contains("T") { s = s.replacingOccurrences(of: " ", with: "T") }
        if let dot = s.firstIndex(of: ".") {
            let rest = s[s.index(after: dot)...]
            let digits = rest.prefix { $0.isNumber }
            let tail = rest.dropFirst(digits.count)
            s = String(s[..<dot]) + "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + String(tail)
        }
        if s.hasSuffix("+00") { s += ":00" }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }

    static func span(_ from: String?, to: Date = Date()) -> String {
        guard let d = date(from) else { return "" }
        let mins = max(0, Int((to.timeIntervalSince(d) / 60).rounded()))
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        if h < 24 { return mins % 60 == 0 ? "\(h) h" : "\(h) h \(mins % 60) min" }
        return "\(h / 24) d"
    }

    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; f.amSymbol = "am"; f.pmSymbol = "pm"; return f }()
    private static let weekday: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let monthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
    private static let monthDayYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f }()

    static func when(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        let cal = Calendar.current, now = Date()
        if cal.isDateInToday(d) { return time.string(from: d) }
        if now.timeIntervalSince(d) < 6 * 86_400 { return "\(weekday.string(from: d)) \(time.string(from: d))" }
        return cal.component(.year, from: d) == cal.component(.year, from: now) ? monthDay.string(from: d) : monthDayYear.string(from: d)
    }

    /// The exact time under a message.
    static func exact(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        if Calendar.current.isDateInToday(d) { return time.string(from: d) }
        return "\(monthDay.string(from: d)) · \(time.string(from: d))"
    }

    static func duration(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "" }
        let n = Int(s)
        return n < 60 ? "\(n)s" : "\(n / 60)m \(n % 60)s"
    }
}
